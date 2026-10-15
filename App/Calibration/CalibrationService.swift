import Foundation
import Observation
import SwiftUI
import BlurCore
import BlurGPU

// OWNER: CALIBRATION (frozen public API, ARCHITECTURE §5.13 / AppContract/Calibration; SPEC §13). The measuring half of
// live calibration: render on this phone → fit (BlurServices.psfFitter, off the main actor) → a Run of kind .calibration
// in the Run log, which LiveFacts, the SLIDE chip, floor 1/2, the SwiftUI crown's semantic stop and σ-hold read.
//
//   • SwiftUI .blur: measureEdges (ImageRenderer at the display scale; cgImage, render(into:) or the on-screen experiment).
//   • Shadows: measureShadowEdges (SwiftUI .shadow, CALayer.render(in:), CGContext.setShadow), read from alpha.
//   • Core Image / MPS / vImage: GPUServices.appleTwins.edgeSamples (APPLE-TWINS); unavailable → an honest failure line.
//
// Scheduling (review fix E-21): every render goes through CalibrationRenderGate — one per run-loop turn, timed, × 2
// back-off after a render over 16 ms, nothing while a control is active (setControlActive), and any touch pauses the
// queue (noteTouch); a touch-paused queue resumes on the next idle tick. The SwiftUI basic set runs automatically once
// per OS build through the idle gate (≥ 10 s after launch, ≥ 3 s after the last touch, no control active, thermal
// nominal or fair: BenchModel calls `tick` only then, and this service checks it again); the sweep and single
// measurements run on demand from the Calibrate sheet.

public enum CalibrationState: Sendable, Hashable {
    case idle
    case running(done: Int, total: Int, subject: CalibrationSubject)
    case paused(done: Int, total: Int)
    case failed(String)
}

/// Why a measurement could not run (shown as words, never as a number).
public enum CalibrationFailure: Error, Sendable, Hashable, CustomStringConvertible {
    case unavailable(String)
    case noEdge
    public var description: String {
        switch self {
        case .unavailable(let why): "NOT AVAILABLE · \(why)"
        case .noEdge: "NO EDGE READ BACK · the render returned no step"
        }
    }
}

@MainActor @Observable
public final class CalibrationService {
    public private(set) var state: CalibrationState = .idle
    /// BASIC SET, SWEEP or MEASUREMENT while a job runs.
    public private(set) var jobTitle: String?
    /// The request being rendered now.
    public private(set) var current: CalibrationRequest?
    /// The last failure, in words (cleared by the next success).
    public private(set) var lastFailure: String?
    /// Border findings of SwiftUI .blur measurements this session (CAL §5.1 item 6).
    public private(set) var borderFindings: [CalibrationSubject: CalibrationBorderFinding] = [:]
    /// The on-screen path's objective capture test (this session).
    public private(set) var captureTest: CalibrationCaptureTest?
    /// True while the queue waits because of a touch (it resumes on the next idle tick).
    public private(set) var pausedByTouch = false
    /// The display scale the measurements run at (the Calibrate sheet updates it from its environment).
    public var displayScale: Double

    @ObservationIgnored private let runLog: RunLogStore
    @ObservationIgnored private let gpu: GPUContext?
    @ObservationIgnored private var idleGate: CalibrationIdleScheduler
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var progress: (done: Int, total: Int) = (0, 0)
    @ObservationIgnored private var autoBasicSetChecked = false
    @ObservationIgnored private var inJob = false

    public init(runLog: RunLogStore, gpu: GPUContext?) {
        self.runLog = runLog
        self.gpu = gpu
        displayScale = CalibrationDevice.displayScale
        idleGate = CalibrationIdleScheduler(launchTime: ProcessInfo.processInfo.systemUptime)
    }

    public var isBusy: Bool { job != nil || inJob }

    // MARK: Measuring

    /// One measurement → a Run of kind .calibration appended to the log. Returns nil when cancelled.
    public func measure(_ request: CalibrationRequest) async throws -> CalibrationResult? {
        if inJob { return try await perform(request, note: "set=single", probeBorder: false) }
        guard job == nil else { throw CalibrationFailure.unavailable("another calibration is running") }
        let box = CalibrationOutcomeBox()
        let task = Task { @MainActor in
            self.begin(title: "MEASUREMENT", total: 1)
            self.state = .running(done: 0, total: 1, subject: request.subject)
            do { box.outcome = .success(try await self.perform(request, note: "set=single", probeBorder: true)) }
            catch {
                box.outcome = .failure(error)
                self.lastFailure = "\(request.subject.title) · \(error)"
            }
            self.end()
        }
        job = task
        await task.value
        return try box.outcome.get()
    }

    /// SwiftUI basic set: radii 0.5, 1, 2, 3, 4, 8 pt × 4 phases (SPEC §13.2); automatic only through the idle gate.
    public func runBasicSet() async {
        await runJob(CalibrationPlan.basicSet(displayScale: displayScale), title: "BASIC SET", note: "set=basic")
    }

    /// The full sweep (34 radii × 4 phases for SwiftUI .blur) on demand in Calibrate.
    public func runSweep(_ subject: CalibrationSubject) async {
        await runSweep(subject, path: subject.defaultPath, colourMode: .nonLinear, opaque: false)
    }

    /// The sweep along the sheet's chosen path, working space and border setting.
    public func runSweep(_ subject: CalibrationSubject, path: CalibrationPath, colourMode: CalibrationColourMode, opaque: Bool) async {
        let scale = subject.parameterIsPoints ? displayScale : 1
        let requests = CalibrationPlan.sweepParameters(subject).map {
            CalibrationRequest(subject: subject, path: path, parameter: $0, displayScale: scale, colourMode: colourMode,
                               phases: CalibrationPlan.phases, opaque: subject == .swiftUIBlur ? opaque : nil)
        }
        await runJob(requests, title: "SWEEP", note: "set=sweep")
    }

    /// Runs the on-screen path's objective capture test (SPEC §13.3).
    public func runCaptureTest() async {
        guard job == nil else { return }
        let task = Task { @MainActor in
            self.begin(title: "CAPTURE TEST", total: 1)
            self.state = .running(done: 0, total: 1, subject: .swiftUIBlur)
            self.captureTest = await CalibrationOnScreenCapture.runCaptureTest(scale: CGFloat(self.displayScale),
                                                                                device: CalibrationDevice.stamp(gpu: self.gpu))
            if self.captureTest == nil { self.lastFailure = "CAPTURE TEST · the on-screen capture returned no image" }
            self.end()
        }
        job = task
        await task.value
    }

    public func pause() {
        guard isBusy else { return }
        CalibrationRenderGate.shared.paused = true
        state = .paused(done: progress.done, total: progress.total)
    }

    public func resume() {
        pausedByTouch = false
        CalibrationRenderGate.shared.paused = false
        if isBusy, let request = current { state = .running(done: progress.done, total: progress.total, subject: request.subject) }
    }

    public func cancel() {
        job?.cancel()
        CalibrationRenderGate.shared.reset()
        pausedByTouch = false
        state = .idle
    }

    // MARK: Reading results

    /// The newest result for a subject (any parameter).
    public func latest(_ subject: CalibrationSubject) -> CalibrationResult? { runLog.calibrations.last { $0.request.subject == subject } }

    /// Every result for a subject in the Run log, oldest first.
    public func results(_ subject: CalibrationSubject) -> [CalibrationResult] {
        runLog.runs(of: .calibration).compactMap(\.calibration).filter { $0.request.subject == subject }
    }

    /// The newest result for exactly this request's subject, path, space, scale, border setting and parameter.
    public func result(matching request: CalibrationRequest) -> CalibrationResult? {
        results(request.subject).last {
            $0.request.path == request.path && $0.request.colourMode == request.colourMode && $0.request.parameter == request.parameter
                && $0.request.displayScale == request.displayScale && ($0.request.opaque ?? false) == (request.opaque ?? false)
        }
    }

    /// The law fitted from this phone's sweep (nil until measured; the macOS law stays INFERRED until then).
    public func law(_ subject: CalibrationSubject) -> CalibrationLaw? { BlurServices.psfFitter.law(results(subject)) }

    /// True when the SwiftUI basic set has run on this OS build (SPEC §13.2: once per OS build).
    public var basicSetDoneForThisBuild: Bool {
        let build = runLog.currentOSBuild ?? CalibrationDevice.osBuild()
        return runLog.runs(of: .calibration).contains { $0.notes.contains("set=basic") && $0.device.osBuild == build }
    }

    // MARK: Idle-gate hooks from the Bench (CalibrationIdleScheduler)

    public func noteTouch(at time: Double) {
        idleGate.noteTouch(at: time)
        guard isBusy, !CalibrationRenderGate.shared.paused else { return }
        CalibrationRenderGate.shared.paused = true
        pausedByTouch = true
        state = .paused(done: progress.done, total: progress.total)
    }

    public func setControlActive(_ active: Bool) {
        idleGate.setControlActive(active)
        CalibrationRenderGate.shared.controlActive = active
    }

    public func tick(now: Double, thermal: ThermalLevel) {
        guard idleGate.mayRun(at: now, thermal: thermal) else { return }
        if pausedByTouch { resume() }
        guard !autoBasicSetChecked, runLog.isLoaded, job == nil else { return }
        autoBasicSetChecked = true
        guard !basicSetDoneForThisBuild else { return }
        Task { @MainActor [weak self] in await self?.runBasicSet() }
    }

    // MARK: Jobs

    private func runJob(_ requests: [CalibrationRequest], title: String, note: String) async {
        guard job == nil, !requests.isEmpty else { return }
        let task = Task { @MainActor in
            self.begin(title: title, total: requests.count)
            self.inJob = true
            for (i, request) in requests.enumerated() {
                if Task.isCancelled { break }
                self.progress.done = i
                self.state = CalibrationRenderGate.shared.paused ? .paused(done: i, total: requests.count)
                                                                 : .running(done: i, total: requests.count, subject: request.subject)
                do { _ = try await self.perform(request, note: note, probeBorder: false) }
                catch { self.lastFailure = "\(request.subject.title) · \(error)" }
            }
            self.inJob = false
            self.end()
        }
        job = task
        await task.value
    }

    private func begin(title: String, total: Int) {
        jobTitle = title
        progress = (0, total)
        lastFailure = nil
        CalibrationRenderGate.shared.reset()
    }

    private func end() {
        if case .failed = state {} else { state = .idle }
        if let failure = lastFailure, progress.total == 1 { state = .failed(failure) }
        job = nil
        current = nil
        jobTitle = nil
        pausedByTouch = false
        CalibrationRenderGate.shared.paused = false
    }

    /// Render → read back → fit → Run. Throws CalibrationFailure when the subject cannot be measured on this build.
    private func perform(_ request: CalibrationRequest, note: String, probeBorder: Bool) async throws -> CalibrationResult? {
        current = request
        let gate = CalibrationRenderGate.shared
        let before = gate.totalMilliseconds
        let samples: [EdgeSamples]
        var wallMilliseconds: Double?
        switch request.subject {
        case .swiftUIBlur:
            let radius = CGFloat(request.parameter), opaque = request.opaque ?? false
            samples = await measureEdges(request) { $0.blur(radius: radius, opaque: opaque) }
            if probeBorder, !Task.isCancelled,
               let finding = await probeBlurBorder(radius: request.parameter, opaque: opaque, scale: request.displayScale) {
                borderFindings[.swiftUIBlur] = finding
            }
        case .swiftUIShadow, .caLayerShadow, .cgContextShadow:
            samples = await measureShadowEdges(request)
        default:
            guard let twins = GPUServices.appleTwins, twins.supports(request.subject) else {
                throw CalibrationFailure.unavailable("\(request.subject.title) has no twin runner in this build")
            }
            guard let gpu else { throw CalibrationFailure.unavailable("no Metal device") }
            // In-process GPU / CPU work (APPLE-TWINS), not an ImageRenderer render: it does not block the run loop the way a
            // SwiftUI render does, so it is not paced by the gate; its wall-clock time is recorded instead.
            let start = DispatchTime.now().uptimeNanoseconds
            do { samples = try await twins.edgeSamples(request, context: gpu) }
            catch { throw CalibrationFailure.unavailable("\(error)") }
            wallMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        }
        if Task.isCancelled { return nil }
        guard !samples.isEmpty else { throw CalibrationFailure.noEdge }
        let milliseconds = wallMilliseconds ?? (gate.totalMilliseconds - before)
        let fitter = BlurServices.psfFitter
        let fit = await Task.detached(priority: .userInitiated) { fitter.fit(samples, request: request) }.value
        let device = CalibrationDevice.stamp(gpu: gpu)
        let result = CalibrationResult(request: request, fit: fit, device: device, durationMilliseconds: milliseconds)
        runLog.append(Self.run(result, gpu: gpu?.facts, note: note))
        lastFailure = nil
        return result
    }

    /// The Run of kind .calibration that carries a result (the Run log's exportable record, JF G-19).
    static func run(_ result: CalibrationResult, gpu: GPUFacts?, note: String) -> Run {
        let r = result.request
        let configuration = RenderConfiguration(blur: BlurID(rawValue: "calibration." + r.subject.rawValue),
                                                variant: VariantID(rawValue: r.path.rawValue),
                                                parameters: ParameterValues(["parameter": .double(r.parameter)]),
                                                settings: .standard, specimen: "calibration-edge", specimenOptions: .standard,
                                                pan: .zero, probe: .zero, windowSize: 0)
        return Run(kind: .calibration, generation: 0, slot: .a, configuration: configuration,
                   resolvedVariant: VariantResolution(variant: configuration.variant), quality: .full, device: result.device, gpu: gpu,
                   kernel: KernelSummary(sigmaEff: result.fit.sigmaPx, excessKurtosis: result.fit.excessKurtosis, fetchesPerPixel: 0,
                                         tapsPerAxis: nil, passNames: []),
                   dispatch: [], timing: nil, cost: nil, parity: nil, probe: nil, shape: nil, shader: nil, trace: nil,
                   calibration: result, deviceProbe: nil,
                   notes: ["calibration", note, "subject=\(r.subject.rawValue)", "path=\(r.path.rawValue)",
                           "colour=\(r.colourMode.rawValue)", "scale=\(r.displayScale)", "phases=\(r.phases)",
                           "opaque=\(r.opaque.map { $0 ? "true" : "false" } ?? "n/a")"])
    }
}

/// Carries a single measurement's outcome out of its job task (main-actor isolated, so it may cross into the task).
@MainActor
private final class CalibrationOutcomeBox {
    var outcome: Result<CalibrationResult?, any Error> = .success(nil)
}
