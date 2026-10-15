import Foundation
import Observation
import Metal
import UIKit
import BlurCore
import BlurGPU

// OWNER: ENGINE (frozen public API, ARCHITECTURE §5.9 / AppContract/Engine/EngineAPI.swift).
// The Bench: ONE source of truth for REQUESTED state (configuration, window view, compare state, navigation path and the
// one sheet). Controls write it and show requested values at once. The image follows `acknowledged[slot]` (the newest
// completed Run of any quality); every measurement-derived value (PIXEL, loupe, pills, rail, telemetry, Trace, pass
// intermediates, the kernel-well face and ±3σ bracket) follows `lastFull[slot]`, the newest FULL-resolution Run, and is
// HELD while a preview is on screen (review fixes P-36, P-66).
//
// The render loop (ARCHITECTURE §5.9, SPEC §4.1.6): an accepted change → RenderScheduler.requestChanged (cancelling
// measurements in flight) → RenderCoordinator.render for every active slot (A, and B/C/D in Compare; preview quality
// while a control moves) → monotonic acknowledge per slot → publish. 300 ms after the last change (`tick`): a full render
// if the last was a preview, then — never in the first 10 s after launch — budgeted timing (ABAB with B in Compare),
// then in-app parity at `.utility`, then Runs into the log. Every touch cancels measurements between command buffers and
// re-arms them. After the idle gate (CalibrationIdleScheduler) the one-time sub-texel probe and the hero-dozen pre-warm
// run in the background, and the calibration service gets its idle ticks.
//
// Launch scenarios (`-B2Scenario <name> [-B2Blur id] [-B2Specimen id] [-B2Floor n] [-B2Param key=value …]`,
// ARCHITECTURE §11.4) are applied by `handleLaunch`; the -B2Param keys ENGINE honours are listed on `LaunchParameter`.

/// The calibration service's idle-gate hooks (SPEC §2, §13.2), installed by AppEnvironment.
public struct CalibrationIdleHooks {
    public var noteTouch: @MainActor (Double) -> Void
    public var setControlActive: @MainActor (Bool) -> Void
    public var tick: @MainActor (Double, ThermalLevel) -> Void
    public init(noteTouch: @escaping @MainActor (Double) -> Void, setControlActive: @escaping @MainActor (Bool) -> Void,
                tick: @escaping @MainActor (Double, ThermalLevel) -> Void) {
        self.noteTouch = noteTouch; self.setControlActive = setControlActive; self.tick = tick
    }
}

/// The -B2Param keys `handleLaunch` honours (screenshot and test scenarios; agreed with the UI areas):
/// • `settle=1`: draw the scenario's final state (push, sheet, loupe) only after the first settled full-resolution Run of
///   A, so a screenshot never catches a half-built screen.
/// • Any key of the blur's parameters (`sigma=4`, `radius=20`, `offsets=0,1,2,2,3`, `centre=447,447`), clamped to range.
/// • `variant=<variant id>`, `ev=<−2…6>`, `probe=x,y`, `pan=x,y`, `split=0.5|off`, `zoom=1|2|4|8`, `pass=<n>`,
///   `opt.<specimen option>=<value>` (`opt.intensity=100`), `colour=linear|srgb`, `edge=clamp|mirror|wrap|zero|renormalise`,
///   `alpha=premultiplied|straight`, `preview=full`.
/// • Compare: `axis=operator|implementation|precision|space|apple`, `b=<blur id>`, `bvariant=<variant id>|cpu`,
///   `view=wipe|flip|difference1|difference16|difference256|lineUp`, `match=sigma|fwhm|edgeWidth|cost|none`, `driveB=1`,
///   `cmpsplit=0.5`.
/// • `lesson=<lesson id>` (applies a lesson), `subject=<calibration subject>` (calibrate), `tab=<tab raw value>`.
public enum LaunchParameter {
    public static let settle = "settle"
}

@MainActor @Observable
public final class BenchModel {
    // Requested state (controls write it; shown immediately).
    public private(set) var configuration: RenderConfiguration
    public private(set) var view: WindowViewState
    public private(set) var compare: CompareState?
    // Acknowledged state (from Runs).
    public private(set) var acknowledged: [RunSlot: Run] = [:]
    public private(set) var lastTimed: [RunSlot: Run] = [:]
    public private(set) var phase: RenderPhase = .idle
    public private(set) var status: StatusLine = .phase(.empty)
    /// The newest FULL-resolution acknowledged Run per slot: PIXEL, loupe, pills, telemetry and Trace read this, never a
    /// preview (`RenderQuality.publishesMeasurements`); while a preview is on screen they show these values marked HELD.
    public private(set) var lastFull: [RunSlot: Run] = [:]
    public private(set) var railChips: [RailChip] = []
    public private(set) var pills: PillContent?
    public private(set) var loupe: LoupeReading?
    public private(set) var isInteracting: Bool = false
    public private(set) var isFirstLaunch: Bool = false
    // Navigation (one NavigationStack path, one sheet).
    public var path: [Route] = []
    public var sheet: SheetDestination?
    // Collaborators.
    public let settings: AppSettings
    public let telemetry: TelemetryModel
    public let runLog: RunLogStore
    public let renderer: RenderCoordinator

    // MARK: ENGINE additions (public, additive to the frozen API)

    /// Points-to-pixels scale of the image window (3 on the 15 Pro Max), from the Bench's layout.
    public private(set) var displayScale: Double = 3
    /// The newest render failure, shown as a status warning until the next success.
    public private(set) var lastError: String?
    /// The newest parity result per slot (Jump › Worst parity pixel; floor 7).
    public private(set) var lastParity: [RunSlot: ParitySummary] = [:]
    /// The σ-hold line of the last switch: kept in the readout's accessibility value until the next change (SPEC §4.1.2).
    public private(set) var heldSigmaLine: BadgedLine?
    /// The blur he just left (σ-matched), Compare's default B (SPEC §8.2).
    public private(set) var previousConfiguration: RenderConfiguration?
    /// Compare's last-used view (the `Compare` button reopens it).
    public private(set) var lastCompareView: CompareView = .wipe
    /// True while the first-launch focus pull runs (SPEC §2: 0.0–0.6 s).
    public private(set) var isFocusPulling = false
    /// The Trace currently open (its frame is the traced frame, SPEC §6.4 rule 2).
    @ObservationIgnored public private(set) weak var activeTrace: TraceSession?
    /// Facts about the current input window (Jump menu): brightest input pixel, strongest edge on the probe row.
    public private(set) var inputFacts: BenchInputFacts?
    /// Calibration idle-gate hooks (AppEnvironment wires the CalibrationService).
    @ObservationIgnored public var calibrationHooks: CalibrationIdleHooks?
    /// `systemUptime` at launch (AppEnvironment sets the process launch time): nothing measures in the first 10 s, and the
    /// renderer notes each timing Run's seconds since launch from the same value.
    @ObservationIgnored public var launchUptime: Double { didSet { renderer.launchUptime = launchUptime } }
    /// The wall-clock moment of `launchUptime`: only timings measured in THIS session fill the GPU readout (SPEC §4.1.4:
    /// "`–.––` until it exists"); older Runs stay in the log.
    var sessionStartDate: Date { Date().addingTimeInterval(launchUptime - ProcessInfo.processInfo.systemUptime) }

    /// True while a preview is on screen: every measurement-derived readout shows its last full value, engraved HELD.
    public var isHeld: Bool { acknowledged[.a].map { !$0.quality.publishesMeasurements } ?? false }
    /// The slots on screen: A, then B (Compare), then C and D (Line-up).
    public var activeSlots: [RunSlot] {
        guard let compare else { return [.a] }
        return [.a, .b] + [RunSlot.c, .d].prefix(compare.extra.count)
    }

    // MARK: Internals

    @ObservationIgnored var clock: @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime }
    @ObservationIgnored var thermal: @MainActor () -> ThermalLevel = { BenchModel.thermalLevel(ProcessInfo.processInfo.thermalState) }
    @ObservationIgnored private var scheduler = RenderScheduler()
    @ObservationIgnored private var idleGate: CalibrationIdleScheduler
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var pending: (quality: RenderQuality, generation: UInt64)?
    @ObservationIgnored private var slotAcknowledged: [RunSlot: UInt64] = [:]
    @ObservationIgnored private var measurementTask: Task<Void, Never>?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var readoutTask: Task<Void, Never>?
    @ObservationIgnored private var persistTask: Task<Void, Never>?
    @ObservationIgnored private var focusPullTask: Task<Void, Never>?
    @ObservationIgnored private var idleWorkTask: Task<Void, Never>?
    @ObservationIgnored private var notice: (line: BadgedLine, until: Double)?
    @ObservationIgnored private var lessonLine: BadgedLine?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var persistsSnapshot = true
    @ObservationIgnored private var focusPullDone = false
    @ObservationIgnored private var subTexelProbeDone = false
    @ObservationIgnored private var prewarmDone = false
    @ObservationIgnored private var loggedGenerations: Set<String> = []
    @ObservationIgnored private var remembered: [BlurID: (parameters: ParameterValues, variant: VariantID)] = [:]
    @ObservationIgnored private var probeFollowsSpecimen = false
    @ObservationIgnored private var deferredLaunch: [@MainActor (BenchModel) -> Void] = []
    @ObservationIgnored private var settleForLaunch = false
    @ObservationIgnored private var contentCache: (key: String, content: OperatorContent)?
    @ObservationIgnored private var inputFactsKey: String?
    /// A change is waiting for its 300-ms settle (the clock ticks fast until the scheduler starts the measurements).
    @ObservationIgnored private var settlePending = false
    /// False while the app is not active: no GPU work is submitted from the background (Metal refuses it), measurements
    /// stop and re-arm, and the newest request renders as soon as the app is active again.
    @ObservationIgnored public private(set) var isAppActive = true
    @ObservationIgnored private var renderDeferredWhileInactive = false

    public init(renderer: RenderCoordinator, settings: AppSettings, telemetry: TelemetryModel, runLog: RunLogStore,
                restoring snapshot: BenchSnapshot) {
        self.renderer = renderer; self.settings = settings; self.telemetry = telemetry; self.runLog = runLog
        configuration = snapshot.configuration; view = snapshot.view; compare = snapshot.compare; isFirstLaunch = !snapshot.firstLaunchDone
        let launch = ProcessInfo.processInfo.systemUptime
        launchUptime = launch
        idleGate = CalibrationIdleScheduler(launchTime: launch)
        focusPullDone = snapshot.firstLaunchDone
        if let compare { lastCompareView = compare.view }
    }

    public var entry: CatalogEntry? { BlurRegistry.entry(configuration.blur) }
    public var op: (any BlurOperator)? { BlurRegistry.op(configuration.blur) }

    /// The default Bench state (SPEC §2): Gaussian, linear-sampled, σ 12 on Night City at its default probe.
    public static func defaultConfiguration(windowSize n: Int, settings: SilentSettings = .standard, blur: BlurID = GaussianOperator.id,
                                            specimen: SpecimenID? = nil) -> RenderConfiguration {
        let entry = BlurRegistry.entry(blur) ?? BlurRegistry.operators.first?.entry
        let specimenID = specimen ?? entry?.defaultSpecimen ?? "night-city"
        let available = SpecimenRegistry.generator(specimenID) != nil ? specimenID : (SpecimenRegistry.generators.first?.descriptor.id ?? "night-city")
        return RenderConfiguration(blur: entry?.id ?? blur, variant: entry?.defaultVariant ?? "gaussian-linear-sampling",
                                   parameters: entry?.defaultParameters ?? ParameterValues(), settings: settings, specimen: available,
                                   specimenOptions: .standard, pan: .zero, probe: provisionalProbe(available, windowSize: n), windowSize: n)
    }

    /// Where a specimen's feature probe lies before its canvas exists (Night City and the impulse: 8 px below the centre
    /// light, SPEC §2); the canvas's own `defaultProbe` replaces it as soon as the canvas is generated.
    static func provisionalProbe(_ specimen: SpecimenID, windowSize n: Int) -> PixelPoint {
        let c = SpecimenGeometry.centre(windowSize: n)
        return specimen == "night-city" || specimen == "impulse" ? PixelPoint(x: c.x, y: Swift.min(n - 1, c.y + 8)) : c
    }

    // MARK: Lifecycle

    /// The image window's size in points and the screen scale, from the Bench layout: the window is N × N device pixels.
    public func configureWindow(points: Double, scale: Double) {
        guard points.isFinite, scale.isFinite, points > 0, scale > 0 else { return }
        displayScale = scale
        let n = Swift.max(64, Int((points * scale).rounded()))
        guard n != configuration.windowSize else { return }
        let old = configuration.windowSize
        configuration = Self.resized(configuration, from: old, to: n)
        if var state = compare {
            state.b = Self.resized(state.b, from: old, to: n)
            state.extra = state.extra.map { Self.resized($0, from: old, to: n) }
            compare = state
        }
        let c = SpecimenGeometry.centre(windowSize: n)
        view.zoomCentre = SIMD2(Double(c.x), Double(c.y))
        if let loupe = view.loupe { view.loupe = Self.rescaled(loupe, from: old, to: n) }
        if started { requestRender(interacting: false) }
    }

    static func resized(_ config: RenderConfiguration, from old: Int, to n: Int) -> RenderConfiguration {
        var c = config
        c.windowSize = n
        c.probe = rescaled(config.probe, from: old, to: n)
        return c
    }
    static func rescaled(_ p: PixelPoint, from old: Int, to n: Int) -> PixelPoint {
        // Probes are feature-relative: keep the offset from the centre (SPEC §11 rule 3), clamped to the new window.
        let a = SpecimenGeometry.centre(windowSize: old), b = SpecimenGeometry.centre(windowSize: n)
        return PixelPoint(x: Swift.min(n - 1, Swift.max(0, p.x - a.x + b.x)), y: Swift.min(n - 1, Swift.max(0, p.y - a.y + b.y)))
    }

    /// Starts rendering (the Bench calls it once its window size is known). The first launch starts the focus pull.
    public func start() {
        guard !started else { return }
        started = true
        idleGate = CalibrationIdleScheduler(launchTime: launchUptime)
        refreshSpecimenProbe()
        requestRender(interacting: false)
        if isFirstLaunch && !focusPullDone { startFocusPull(reduceMotion: UIAccessibility.isReduceMotionEnabled) }
        ensureClock()
    }

    private var now: Double { clock() }

    // MARK: Blur and parameters

    /// Switches blur with σ-hold (SPEC §8.1) when MATCH σ is on; the previous blur becomes Compare's default B.
    public func selectBlur(_ id: BlurID) {
        guard id != configuration.blur, let newOp = BlurRegistry.op(id), newOp.entry.tier.runsLive else { return }
        userChanged()
        let leaving = configuration
        remembered[leaving.blur] = (leaving.parameters, leaving.variant)
        previousConfiguration = leaving
        let (parameters, line) = heldParameters(for: newOp, from: leaving)
        configuration.blur = id
        configuration.variant = remembered[id]?.variant ?? newOp.entry.defaultVariant
        configuration.parameters = parameters
        heldSigmaLine = line
        if let line { notice = (line, now + 2) }
        lessonLine = nil
        telemetry.clearMeasurements()
        syncCompare()
        acceptedChange()
    }

    /// σ-hold: the new blur's parameters for the σ the current one runs (or its own last values when σ is undefined).
    private func heldParameters(for newOp: any BlurOperator, from config: RenderConfiguration) -> (ParameterValues, BadgedLine?) {
        let own = remembered[newOp.entry.id]?.parameters ?? newOp.entry.defaultParameters
        guard settings.matchSigmaOnSwitch, let sigma = BlurRegistry.op(config.blur)?.sigma(config.operatorRequest) else { return (own, nil) }
        let hold = newOp.holdingSigma(sigma, current: own)
        return (hold.parameters, hold.statusLine)
    }

    public func selectVariant(_ id: VariantID) {
        drive { config in
            guard BlurRegistry.entry(config.blur)?.variant(id) != nil, id != config.variant else { return false }
            config.variant = id
            return true
        }
    }
    public func setParameter(_ key: ParameterKey, _ value: ParameterValue) {
        drive { config in
            guard config.parameters[key] != value else { return false }
            if BlurRegistry.entry(config.blur)?.spec(key)?.scope == .specimenExposure, case .double(let ev) = value {
                config.specimenOptions.exposureEV = Int(ev.rounded())
            }
            config.parameters[key] = value
            return true
        }
    }
    /// Crown detents: one FINE or SEMANTIC step on a parameter (drives B when `compare.drivingB`). A crown turn is an
    /// interaction: heavy blurs preview while it turns and render at full resolution 300 ms after the last detent.
    /// Turning past a range end emits nothing (Metro contract A.17).
    public func step(_ key: ParameterKey, by detents: Int, semantic: Bool) {
        guard detents != 0 else { return }
        let target = compare?.drivingB == true ? compare?.b : configuration
        guard let target, let spec = BlurRegistry.entry(target.blur)?.spec(key) else { return }
        let next: ParameterValue
        switch spec.kind {
        case .continuous(let c):
            let fallback: Double = { if case .double(let d) = spec.defaultValue { return d }; return c.range.lowerBound }()
            let current = target.parameters.double(key) ?? fallback
            let stops = c.semanticStops.map { stop in stop.id.flatMap { measuredStop($0) }.map { SemanticStop($0, label: stop.label, id: stop.id) } ?? stop }
            let value = semantic ? c.semanticStepped(from: current, by: detents, stops: stops) : c.stepped(from: current, by: detents)
            guard value != current else { return }
            next = .double(value)
        case .integer(let i):
            let current = target.parameters.int(key) ?? i.range.lowerBound
            let value = semantic ? i.semanticStepped(from: current, by: detents) : i.stepped(from: current, by: detents)
            guard value != current else { return }
            next = .int(value)
        default:
            return
        }
        idleGate.noteTouch(at: now)
        calibrationHooks?.noteTouch(now)
        crownTurning = true
        setParameter(key, next)
        crownTurning = false
        scheduler.interactionEnded(at: now)
    }
    @ObservationIgnored private var crownTurning = false

    /// A semantic stop whose value is replaced by a measurement (the SwiftUI regime switch, SPEC §9.2): the switch of the
    /// law fitted from this phone's SwiftUI sweep, once one exists; until then the declared (INFERRED) stop stands.
    private func measuredStop(_ id: String) -> Double? {
        guard id == "swiftui-regime-switch" else { return nil }
        let sweep = runLog.runs(of: .calibration).compactMap(\.calibration).filter { $0.request.subject == .swiftUIBlur }
        guard sweep.count >= 3 else { return nil }
        return BlurServices.psfFitter.law(sweep)?.switchParameter
    }

    public func setSilent(_ settings: SilentSettings) {
        drive { config in
            guard settings != config.settings else { return false }
            config.settings = settings
            return true
        }
    }

    /// Applies a change to the configuration the controls drive: A, or B while `DRIVING B` (SPEC §8.2).
    private func drive(_ change: (inout RenderConfiguration) -> Bool) {
        if var state = compare, state.drivingB {
            var b = state.b
            guard change(&b) else { return }
            userChanged()
            state.b = b
            compare = state
            acceptedChange()
            return
        }
        var a = configuration
        guard change(&a) else { return }
        userChanged()
        configuration = a
        heldSigmaLine = nil
        lessonLine = nil
        syncCompare()
        acceptedChange()
    }

    // MARK: Test image, probe and view

    public func setSpecimen(_ id: SpecimenID, options: SpecimenOptions) {
        guard SpecimenRegistry.generator(id) != nil || id == "photo" else { return }
        userChanged()
        configuration.specimen = id
        configuration.specimenOptions = options
        configuration.pan = .zero
        configuration.probe = Self.provisionalProbe(id, windowSize: configuration.windowSize)
        probeFollowsSpecimen = true
        telemetry.clearMeasurements(keepSigma: true)
        syncCompare()
        acceptedChange()
        refreshSpecimenProbe()
    }
    public func setPhoto(_ canvas: SpecimenCanvas) {
        userChanged()
        renderer.specimens.install(photo: canvas)
        configuration.specimen = "photo"
        configuration.specimenOptions = canvas.options
        configuration.pan = .zero
        configuration.probe = canvas.defaultProbe
        probeFollowsSpecimen = false
        syncCompare()
        acceptedChange()
    }
    public func setProbe(_ probe: PixelPoint) {
        let n = configuration.windowSize
        let clamped = PixelPoint(x: Swift.min(Swift.max(probe.x, 0), n - 1), y: Swift.min(Swift.max(probe.y, 0), n - 1))
        probeFollowsSpecimen = false
        guard clamped != configuration.probe else { return }
        userChanged()
        configuration.probe = clamped
        syncCompare()
        acceptedChange()
    }

    /// The Trace's Jump menu (SPEC §6.1): items that do not apply to the current blur or test image are hidden.
    public func availableJumps() -> [ProbeJump] {
        var jumps: [ProbeJump] = [.featureProbe]
        if lastFull[.a] != nil { jumps.append(.brightestOutput) }
        if lastParity[.a] != nil, lastFull[.a]?.configuration.probe == configuration.probe { jumps.append(.worstParity) }
        if inversionRingRadius() != nil { jumps.append(.inversionRing) }
        if inputFacts?.edge != nil { jumps.append(.edge) }
        if inputFacts?.isPointLight == true { jumps.append(.impulsePeak) }
        if entry?.linearity == .lsv { jumps.append(.corner) }
        jumps.append(.tileBoundary)
        return jumps
    }

    public func jumpProbe(_ jump: ProbeJump) async {
        let n = configuration.windowSize
        var target: PixelPoint?
        switch jump {
        case .featureProbe:
            target = await specimenDefaultProbe() ?? Self.provisionalProbe(configuration.specimen, windowSize: n)
        case .brightestOutput:
            target = await brightestOutputPixel()
        case .worstParity:
            if let parity = lastParity[.a] {
                target = PixelPoint(x: parity.region.origin.x + parity.stats.argmax.x, y: parity.region.origin.y + parity.stats.argmax.y)
            }
        case .inversionRing:
            if let r = inversionRingRadius() {
                let c = SpecimenGeometry.centre(windowSize: n)
                target = PixelPoint(x: Swift.min(n - 1, c.x + Int(r.rounded())), y: c.y)
            }
        case .edge:
            target = inputFacts?.edge
        case .impulsePeak:
            target = inputFacts?.brightest
        case .corner:
            // The window corner farthest from the blur's centre handle (worst sampling for zoom and spin).
            let centre = handleCentre() ?? SIMD2(Double(n) / 2, Double(n) / 2)
            let corners = [PixelPoint(x: 4, y: 4), PixelPoint(x: n - 5, y: 4), PixelPoint(x: 4, y: n - 5), PixelPoint(x: n - 5, y: n - 5)]
            target = corners.max { simd_distance(centre, $0.centre) < simd_distance(centre, $1.centre) }
        case .tileBoundary:
            // The last column/row of a 32 × 32 tile nearest the probe (32 × 32 is the Apple9 maximum, REFERENCE; the real
            // tiling is UNVERIFIED and the Trace says so).
            let p = configuration.probe
            func edge(_ v: Int) -> Int { Swift.min(n - 1, Swift.max(31, Int((Double(v + 1) / 32).rounded()) * 32 - 1)) }
            target = PixelPoint(x: edge(p.x), y: edge(p.y))
        }
        guard let target else { return }
        setProbe(target)
    }

    private func simd_distance(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { ((a - b) * (a - b)).sum().squareRoot() }

    private func handleCentre() -> SIMD2<Double>? {
        guard let spec = entry?.handles.first(where: { $0.kind == .centre }), let key = spec.parameters.first else { return nil }
        return configuration.parameters.point(key)
    }

    /// For kernels whose H goes negative, on the 36-cycle Siemens star: the radius where the local frequency
    /// ν = n_c / (2πr) meets the deepest negative lobe (SPEC §6.1, CAT E7). nil when it does not apply.
    private func inversionRingRadius() -> Double? {
        guard configuration.specimen == "siemens-star", let op,
              let minimum = op.response(ResponseQuery(), configuration.operatorRequest, content: nil)?.minimum,
              minimum.value < 0, minimum.frequency > 0 else { return nil }
        let cycles = Double(configuration.specimenOptions.choices["cycles"] ?? "36") ?? 36
        let r = cycles / (2 * Double.pi * minimum.frequency)
        return r < Double(configuration.windowSize) / 2 ? r : nil
    }

    private func brightestOutputPixel() async -> PixelPoint? {
        let n = configuration.windowSize
        guard lastFull[.a] != nil,
              let texels = try? await renderer.readTexels(slot: .a, pass: nil, region: PixelRegion(origin: .zero, size: .square(n))),
              texels.count == n * n else { return nil }
        let index = await Task.detached(priority: .userInitiated) { () -> Int in
            var best = 0, bestValue = -Float.infinity
            for (i, t) in texels.enumerated() { let l = Luma.rec709(t); if l > bestValue { bestValue = l; best = i } }
            return best
        }.value
        return PixelPoint(x: index % n, y: index / n)
    }

    public func setPan(_ pan: PixelPoint) {
        let m = SpecimenGeometry.margin
        let clamped = PixelPoint(x: Swift.min(Swift.max(pan.x, -m), m), y: Swift.min(Swift.max(pan.y, -m), m))
        guard clamped != configuration.pan else { return }
        userChanged()
        configuration.pan = clamped
        syncCompare()
        acceptedChange()
    }
    /// View zoom 1× … 8× about `centre` (window pixels); presentation only, the blur still runs at 1×.
    public func setZoom(_ zoom: Double, centre: SIMD2<Double>) {
        guard zoom.isFinite, centre.x.isFinite, centre.y.isFinite else { return }
        let n = Double(configuration.windowSize)
        view.zoom = Swift.min(Swift.max(zoom, 1), 8)
        view.zoomCentre = SIMD2(Swift.min(Swift.max(centre.x, 0), n), Swift.min(Swift.max(centre.y, 0), n))
    }
    /// A pinch ended: the zoom snaps to the nearest of 1 · 2 · 4 · 8 (SPEC §4.1.3 gesture 2).
    public func settleZoom() {
        let stops = [1.0, 2, 4, 8]
        view.zoom = stops.min { abs(log2($0 / view.zoom)) < abs(log2($1 / view.zoom)) } ?? 1
        if view.zoom == 1 { view.zoomCentre = SIMD2(Double(configuration.windowSize) / 2, Double(configuration.windowSize) / 2) }
    }
    public func setSplit(_ split: Double?) {
        view.split = split.flatMap { $0.isFinite ? Swift.min(Swift.max($0, 0), 1) : nil }
        if var state = compare, let split { state.split = Swift.min(Swift.max(split, 0), 1); compare = state }
        schedulePersist()
    }
    public func showPass(_ index: Int?) {
        if let index, let count = lastFull[.a]?.kernel.passNames.count, !(0..<count).contains(index) { return }
        view.shownPass = index
    }
    /// The Metal loupe (SPEC §4.1.3): 14 × 14 output texels around `centre` from the newest FULL-resolution Run; during a
    /// preview it keeps its last reading (HELD).
    public func setLoupe(_ centre: PixelPoint?) async {
        view.loupe = centre
        guard let centre else { loupe = nil; return }
        await refreshLoupe(at: centre)
    }
    private func refreshLoupe(at centre: PixelPoint) async {
        guard lastFull[.a] != nil else { return }
        let n = configuration.windowSize
        let region = PixelRegion.centred(on: centre, side: 14, inside: .square(n))
        guard let texels = try? await renderer.readTexels(slot: .a, pass: nil, region: region), texels.count == 196,
              view.loupe == centre else { return }
        let i = (centre.y - region.origin.y) * 14 + (centre.x - region.origin.x)
        let c = texels[Swift.min(Swift.max(i, 0), 195)]
        loupe = LoupeReading(centre: centre, texels: texels, centreLinear: .number(Double(c.x), .significant(3), .live),
                             centreCode8: .number(Double(SRGB.code8(linear: Double(c.x))), NumberStyle(precision: .decimals(0), unit: "/255",
                                                                                                         spokenUnit: "of 255"), .computed))
    }

    /// The scene became active or inactive (AppEnvironment forwards UIApplication's notifications). Inactive: nothing new
    /// is committed to the GPU and measurements in flight are cancelled (and re-armed). Active again: the newest request
    /// renders at full resolution and the re-armed measurements run after the usual 300-ms settle.
    public func setAppActive(_ active: Bool) {
        guard active != isAppActive else { return }
        isAppActive = active
        if !active {
            let cancelled = scheduler.touchBegan()
            if !cancelled.isEmpty { settlePending = true }
            perform(cancelled)
            return
        }
        if renderDeferredWhileInactive || pending != nil {
            renderDeferredWhileInactive = false
            perform([.render(quality: .full, generation: scheduler.currentGeneration)])
        }
        if lastError != nil { lastError = nil }
        scheduler.interactionEnded(at: now)
        settlePending = true
        ensureClock()
        refreshStatus()
    }

    public func beginInteraction() {
        isInteracting = true
        let t = now
        idleGate.noteTouch(at: t)
        idleGate.setControlActive(true)
        calibrationHooks?.noteTouch(t)
        calibrationHooks?.setControlActive(true)
        let cancelled = scheduler.touchBegan()
        if !cancelled.isEmpty { settlePending = true }       // the cancelled measurement re-arms after release
        perform(cancelled)
        ensureClock()
    }
    public func endInteraction() {
        guard isInteracting else { return }
        isInteracting = false
        let t = now
        idleGate.noteTouch(at: t)
        idleGate.setControlActive(false)
        calibrationHooks?.noteTouch(t)
        calibrationHooks?.setControlActive(false)
        scheduler.interactionEnded(at: t)
        ensureClock()
    }
    /// Handle drags write their parameters (window pixels) through here.
    public func moveHandle(_ handle: HandleKind, parameter: ParameterKey, to value: ParameterValue) {
        guard entry?.handles.contains(where: { $0.kind == handle && $0.parameters.contains(parameter) }) ?? true else { return }
        setParameter(parameter, value)
    }

    // MARK: Compare (SPEC §8.2)

    /// Enters Compare. With nil: B = the blur he just left (σ-matched) on the Operator axis, in the last-used view; or,
    /// when there is none, the first legal operator choice.
    public func startCompare(_ state: CompareState?) {
        if let state {
            compare = sanitized(state)
        } else if let previous = previousConfiguration, previous.blur != configuration.blur,
                  let choice = legalChoices(axis: .operator).first(where: { $0.configuration.blur == previous.blur && $0.disabledReason == nil }) {
            compare = CompareState(b: choice.configuration, axis: .operator, match: settings.matchSigmaOnSwitch ? .sigma : .none,
                                   view: lastCompareView, split: 0.5)
        } else if let choice = legalChoices(axis: .operator).first(where: { $0.disabledReason == nil })
                    ?? legalChoices(axis: .implementation).first(where: { $0.disabledReason == nil }) {
            let axis: CompareAxis = choice.configuration.blur == configuration.blur ? .implementation : .operator
            compare = CompareState(b: choice.configuration, axis: axis, match: settings.matchSigmaOnSwitch ? .sigma : .none,
                                   view: lastCompareView, split: 0.5)
        } else {
            return
        }
        if let compare { lastCompareView = compare.view }
        telemetry.deltaGPU = nil; telemetry.maxDifference = nil; telemetry.maxDifferenceAt = nil
        acceptedChange()
    }
    public func updateCompare(_ state: CompareState) {
        let clean = sanitized(state)
        guard clean != compare else { return }
        let changedImages = clean.b != compare?.b || clean.extra != compare?.extra
        compare = clean
        lastCompareView = clean.view
        if changedImages { userChanged(); acceptedChange() } else { refreshStatus(); schedulePersist() }
    }

    /// The legal B choices for an axis (SPEC §8.2): B may differ from A in exactly the axis's field.
    public func legalChoices(axis: CompareAxis) -> [CompareChoice] {
        let a = configuration
        guard let opA = op else { return [] }
        switch axis {
        case .operator:
            return BlurRegistry.stripOrder.compactMap { id -> CompareChoice? in
                guard id != a.blur, let opB = BlurRegistry.op(id) else { return nil }
                let b = operatorTwin(of: a, as: opB, current: nil, match: settings.matchSigmaOnSwitch ? .sigma : .none)
                let runs = GPUPipelineRegistry.factory(id, b.variant) != nil
                    || opB.entry.variants.contains { GPUPipelineRegistry.factory(id, $0.id) != nil }
                let reason: String? = opB.entry.tier == .system ? "SYSTEM BLUR · USE THE APPLE AXIS" : (runs ? nil : "NOT BUILT YET")
                return CompareChoice(id: "operator.\(id.rawValue)", title: opB.entry.displayName, configuration: b, disabledReason: reason)
            }
        case .implementation:
            var choices = opA.entry.variants.filter { $0.id != a.variant && $0.runsOnGPU }.map { variant -> CompareChoice in
                var b = a
                b.variant = variant.id
                let reason = opA.disabledReason(variant.id, a.operatorRequest)
                    ?? (GPUPipelineRegistry.factory(a.blur, variant.id) == nil ? "NOT BUILT YET" : nil)
                return CompareChoice(id: "implementation.\(variant.id.rawValue)", title: variant.displayName, configuration: b, disabledReason: reason)
            }
            var cpu = a
            cpu.variant = RenderCoordinator.cpuReferenceVariant(of: a.variant)
            choices.append(CompareChoice(id: "implementation.cpu", title: "CPU reference (BlurCore, Double)", configuration: cpu))
            return choices
        case .precision:
            var out: [CompareChoice] = []
            var fp16 = a; fp16.settings.accumulator = a.settings.accumulator == .fp32 ? .fp16 : .fp32
            out.append(CompareChoice(id: "precision.accumulator", title: fp16.settings.accumulator == .fp16 ? "fp16 accumulate" : "fp32 accumulate",
                                     configuration: fp16))
            var unorm = a; unorm.settings.intermediate = a.settings.intermediate == .rgba16Float ? .rgba8Unorm : .rgba16Float
            out.append(CompareChoice(id: "precision.intermediate", title: unorm.settings.intermediate == .rgba8Unorm ? "rgba8Unorm intermediates" : "rgba16Float intermediates",
                                     configuration: unorm))
            let algorithm = opA.entry.variant(opA.resolveVariant(a.operatorRequest).variant)?.algorithmClass ?? opA.entry.algorithmClass
            if algorithm == .runningSum {
                var sat = a; sat.settings.satCentring = a.settings.satCentring == .plain ? .meanCentred : .plain
                out.append(CompareChoice(id: "precision.sat", title: sat.settings.satCentring == .meanCentred ? "Mean-centred SAT" : "Plain fp32 SAT",
                                         configuration: sat))
            }
            return out
        case .space:
            var colour = a; colour.settings.colourSpace = a.settings.colourSpace == .linearLight ? .srgbEncoded : .linearLight
            var alpha = a; alpha.settings.alphaMode = a.settings.alphaMode == .premultiplied ? .straight : .premultiplied
            return [CompareChoice(id: "space.colour", title: colour.settings.colourSpace == .srgbEncoded ? "sRGB-encoded" : "Linear light",
                                  configuration: colour),
                    CompareChoice(id: "space.alpha", title: alpha.settings.alphaMode == .straight ? "Straight alpha" : "Premultiplied alpha",
                                  configuration: alpha)]
        case .apple:
            return opA.entry.appleTwins.map { twin in
                var b = a
                b.variant = RenderCoordinator.appleTwinVariant(twin.id)
                let runs = twin.subject.map { GPUServices.appleTwins?.supports($0) ?? false } ?? false
                return CompareChoice(id: "apple.\(twin.id)", title: twin.id, configuration: b,
                                     disabledReason: runs ? nil : "\(twin.id.uppercased()) DOES NOT RUN ON THIS PHONE YET")
            }
        }
    }

    /// B for the Operator axis: A's specimen, probe, pan and silent settings with B's own blur, σ-held when MATCH σ.
    private func operatorTwin(of a: RenderConfiguration, as opB: any BlurOperator, current: RenderConfiguration?, match: MatchRule) -> RenderConfiguration {
        var b = a
        b.blur = opB.entry.id
        b.variant = current?.blur == opB.entry.id ? (current?.variant ?? opB.entry.defaultVariant) : (remembered[opB.entry.id]?.variant ?? opB.entry.defaultVariant)
        let own = current?.blur == opB.entry.id ? (current?.parameters ?? opB.entry.defaultParameters)
            : (remembered[opB.entry.id]?.parameters ?? opB.entry.defaultParameters)
        if match == .sigma, let sigma = op?.sigma(a.operatorRequest) {
            b.parameters = opB.holdingSigma(sigma, current: own).parameters
        } else {
            b.parameters = own
        }
        return b
    }

    /// Keeps B (and C, D) legal after A changed: they share A's specimen, probe, pan and window, and differ only in the
    /// axis's field; with MATCH σ on the Operator axis their σ follows A's (SPEC §4.2: "σ-hold keeps B matched").
    private func syncCompare() {
        guard var state = compare else { return }
        state = sanitized(state)
        if state.axis == .operator && state.match == .sigma && !state.drivingB, let opB = BlurRegistry.op(state.b.blur) {
            state.b = operatorTwin(of: configuration, as: opB, current: state.b, match: .sigma)
            state.extra = state.extra.compactMap { c in BlurRegistry.op(c.blur).map { operatorTwin(of: configuration, as: $0, current: c, match: .sigma) } }
        }
        compare = state
    }

    /// B rebuilt from A plus B's own axis field.
    private func sanitized(_ state: CompareState) -> CompareState {
        var s = state
        func shared(_ c: RenderConfiguration) -> RenderConfiguration {
            var out = c
            out.specimen = configuration.specimen; out.specimenOptions = configuration.specimenOptions
            out.pan = configuration.pan; out.probe = configuration.probe; out.windowSize = configuration.windowSize
            return out
        }
        switch s.axis {
        case .operator:
            s.b = shared(s.b)
            if !s.drivingB { s.b.settings = configuration.settings }
        case .implementation, .apple:
            var b = configuration
            b.variant = s.b.variant
            s.b = b
        case .precision:
            var b = configuration
            b.settings.accumulator = s.b.settings.accumulator
            b.settings.intermediate = s.b.settings.intermediate
            b.settings.satCentring = s.b.settings.satCentring
            s.b = b
        case .space:
            var b = configuration
            b.settings.colourSpace = s.b.settings.colourSpace
            b.settings.alphaMode = s.b.settings.alphaMode
            s.b = b
        }
        s.extra = Array(s.extra.prefix(2)).map(shared)
        s.split = s.split.isFinite ? Swift.min(Swift.max(s.split, 0), 1) : 0.5
        if s.view == .lineUp && s.extra.isEmpty { s.view = .wipe }
        return s
    }

    public func swapCompare() {
        guard var state = compare, let opB = BlurRegistry.op(state.b.blur), opB.entry.tier.runsLive,
              !RenderCoordinator.isExternal(state.b.variant) else { return }
        userChanged()
        let a = configuration
        configuration = state.b
        state.b = a
        compare = state
        swapSlotRuns(.a, .b)
        acceptedChange()
    }
    private func swapSlotRuns(_ x: RunSlot, _ y: RunSlot) {
        let ack = acknowledged, full = lastFull, timed = lastTimed
        acknowledged[x] = ack[y]; acknowledged[y] = ack[x]
        lastFull[x] = full[y]; lastFull[y] = full[x]
        lastTimed[x] = timed[y]; lastTimed[y] = timed[x]
        lastParity[x] = nil; lastParity[y] = nil
    }
    public func setDrivingB(_ on: Bool) {
        guard var state = compare, state.drivingB != on else { return }
        state.drivingB = on
        compare = state
        refreshStatus()
    }
    public func endCompare() {
        guard compare != nil else { return }
        userChanged()
        compare = nil
        for slot in [RunSlot.b, .c, .d] {
            acknowledged[slot] = nil; lastFull[slot] = nil; lastTimed[slot] = nil; lastParity[slot] = nil; slotAcknowledged[slot] = nil
            renderer.releaseSlot(slot)
        }
        telemetry.deltaGPU = nil; telemetry.axisColumn = nil; telemetry.maxDifference = nil; telemetry.maxDifferenceAt = nil
        refreshReadouts()
        refreshStatus()
        schedulePersist()
    }

    // MARK: Lessons

    /// Sets a lesson's state (SPEC §8.5): A (and B, C, D with its axis, match and view); guided descents push the Trace.
    /// Its look-for line stays in the status row until a control changes.
    public func apply(_ lesson: Lesson) {
        guard let first = lesson.configurations.first, BlurRegistry.op(first.blur) != nil else { return }
        let n = configuration.windowSize
        let fit = { (c: RenderConfiguration) in Self.resized(c, from: c.windowSize, to: n) }
        previousConfiguration = configuration
        configuration = fit(first)
        probeFollowsSpecimen = false
        heldSigmaLine = nil
        if lesson.configurations.count > 1 {
            var state = CompareState(b: fit(lesson.configurations[1]), extra: lesson.configurations.dropFirst(2).map(fit), axis: lesson.axis,
                                     match: lesson.match, view: lesson.view ?? .wipe)
            if state.view == .lineUp && state.extra.isEmpty { state.view = .wipe }
            compare = state
            lastCompareView = state.view
        } else {
            compare = nil
        }
        telemetry.clearMeasurements()
        lessonLine = lesson.statusLine
        sheet = nil
        acceptedChange(keepLesson: true)
        if lesson.kind == .guidedDescent { path = [.trace] }
    }

    // MARK: Content (computed off the main actor from Sendable inputs)

    public func floorContext(slot: RunSlot) -> FloorContext? {
        guard let config = configuration(for: slot), BlurRegistry.op(config.blur) != nil else { return nil }
        let content = contentCache.flatMap { $0.key == contentKey(config) ? $0.content : nil }
        return FloorContext(configuration: config, homeToolID: settings.homeToolID, displayScale: displayScale,
                            live: LiveFacts(run: lastFull[slot], timedRun: lastTimed[slot], deviceProbes: runLog.deviceProbes,
                                            calibrations: runLog.calibrations),
                            content: content, compareB: slot == .a ? compare?.b : nil)
    }
    public func floorPages() async -> [FloorPage] {
        await ensureContent(for: configuration)
        guard let op, let context = floorContext(slot: .a) else { return [] }
        return await Task.detached(priority: .userInitiated) { BlurServices.floors.pages(for: op, context: context) }.value
    }
    public func makeTraceSession() -> TraceSession { TraceSession(bench: self) }

    /// Everything the fingerprint card shows (SPEC §7.1). Tier S fields are never LIVE (review fix P-31).
    public func fingerprintCard(for id: BlurID) async -> FingerprintCardModel? {
        guard let op = BlurRegistry.op(id) else { return nil }
        let entry = op.entry
        let system = entry.tier == .system
        // The strip and kurtosis are at σ_equiv 4 px (engraved AT σ 4 px); UNIQUE at the current parameters.
        var current = configuration
        if id != configuration.blur {
            current = operatorTwin(of: configuration, as: op, current: nil, match: settings.matchSigmaOnSwitch ? .sigma : .none)
        }
        var atFour = current
        atFour.parameters = op.holdingSigma(4, current: current.parameters).parameters
        let probe = configuration.probe
        let requestFour = atFour.operatorRequest, requestNow = current.operatorRequest
        let computed = await Task.detached(priority: .userInitiated) { () -> (Double?, [ResponseCurve], LabeledValue) in
            let kurtosis = op.psf(at: probe, requestFour, content: nil)?.kernel.marginalX.excessKurtosis
            var responses: [ResponseCurve] = []
            switch entry.linearity {
            case .lsi, .system, .expectation:
                if let h = op.response(ResponseQuery(), requestFour, content: nil) { responses = [h] }
            case .lsv:
                if let h = op.response(ResponseQuery(point: probe), requestFour, content: nil) { responses = [h] }
            case .nonlinear:
                responses = [0.05, 0.5].compactMap { op.response(ResponseQuery(point: probe, amplitude: $0), requestFour, content: nil) }
            }
            return (kurtosis, responses, op.uniqueNumber(requestNow))
        }.value
        let kurtosis: BadgedValue = computed.0.map { .number($0, .decimals(2), system ? .modeled : .computed) }
            ?? .words("—", spoken: "not defined for this blur")
        var partsWays: [BlurID: FloorComparison] = [:]
        for neighbour in entry.neighbours {
            guard let opN = BlurRegistry.op(neighbour) else { continue }
            let other = operatorTwin(of: atFour, as: opN, current: nil, match: .sigma)
            if let first = divergence(atFour, other).first(where: { $0.verdict == .partsWays }) { partsWays[neighbour] = first }
        }
        var strip: [ImageBuffer]?
        var stripEvidence: FingerprintEvidence = system ? .notYetMeasured : .metalModel
        var onThisPhone: ShapeMeasurement?
        var phoneEvidence: FingerprintEvidence = system ? .notYetMeasured : .metalModel
        if system {
            if let offscreen = SystemOffscreen.renderStrip(entry: entry, displayScale: displayScale), !offscreen.isEmpty {
                strip = offscreen
                stripEvidence = .offscreenRender(renderer.deviceStamp())
            }
            if let subject = entry.appleTwins.compactMap(\.subject).first, let fit = runLog.calibrations.last(where: { $0.request.subject == subject }) {
                onThisPhone = ShapeMeasurement(sigmaPx: fit.fit.sigmaPx, excessKurtosisAxis: fit.fit.excessKurtosis,
                                               excessKurtosis45: fit.fit.excessKurtosis45 ?? fit.fit.excessKurtosis,
                                               shiftSpreadPx: fit.fit.centreSpreadPx, minResponse: .nan, millisecondsPerMegapixel: nil)
                phoneEvidence = .offscreenRender(fit.device)
            }
        } else {
            let rendered = (try? await renderer.renderStrip(atFour)) ?? []
            strip = rendered.isEmpty ? nil : rendered
            onThisPhone = try? await renderer.measureShape(atFour)
        }
        var nearest: NearestMatch?
        if let shape = onThisPhone {
            let vector = BlurServices.fingerprints.vector(measured: shape, linearity: entry.linearity)
            let ops = BlurRegistry.operators.filter { $0.entry.tier.runsLive }
            if let best = await Task.detached(priority: .utility, operation: { BlurServices.fingerprints.nearest(to: vector, among: ops) }).value {
                let device: DeviceStamp = { if case .offscreenRender(let d) = phoneEvidence { return d }; return renderer.deviceStamp() }()
                nearest = NearestMatch(blur: best.blur, distance: .number(best.distance, .significant(2), .measured,
                                                                            qualifiers: system ? .offscreen : [], device: device))
            }
        }
        return FingerprintCardModel(entry: entry, unique: computed.2, excessKurtosis: kurtosis, strip: strip, stripEvidence: stripEvidence,
                                    responses: computed.1, partsWays: partsWays, onThisPhone: onThisPhone,
                                    onThisPhoneEvidence: onThisPhone == nil ? (system ? .notYetMeasured : .metalModel) : phoneEvidence,
                                    looksMostLike: nearest)
    }
    public func divergence(_ a: RenderConfiguration, _ b: RenderConfiguration) -> [FloorComparison] {
        BlurServices.divergence.compare(a, b, homeToolID: settings.homeToolID, displayScale: displayScale)
    }
    public func fieldGuidePage(for id: BlurID) async -> FieldGuidePage? {
        guard let op = BlurRegistry.op(id) else { return nil }
        let config = id == configuration.blur ? configuration
            : operatorTwin(of: configuration, as: op, current: nil, match: settings.matchSigmaOnSwitch ? .sigma : .none)
        let context = FloorContext(configuration: config, homeToolID: settings.homeToolID, displayScale: displayScale,
                                   live: LiveFacts(run: id == configuration.blur ? lastFull[.a] : nil,
                                                   timedRun: id == configuration.blur ? lastTimed[.a] : nil,
                                                   deviceProbes: runLog.deviceProbes, calibrations: runLog.calibrations))
        return await Task.detached(priority: .userInitiated) { BlurServices.fieldGuide.page(for: op, context: context) }.value
    }

    // MARK: Lifecycle

    /// Applies a launch scenario (ARCHITECTURE §11.4): every case routes to a screen. Scenario launches start from the
    /// default state of the requested blur and test image, apply `-B2Param key=value` (LaunchParameter), and are never
    /// persisted. `settle=1` draws the final state only after the first settled full-resolution Run.
    public func handleLaunch(_ launch: LaunchScenario.Launch?) {
        guard let launch else { return }
        persistsSnapshot = false
        let params = launch.parameters
        var config = BenchModel.defaultConfiguration(windowSize: configuration.windowSize, settings: settings.silentDefaults,
                                                     blur: launch.blur ?? GaussianOperator.id, specimen: launch.specimen)
        Self.applyLaunchParameters(params, to: &config)
        probeFollowsSpecimen = params["probe"] == nil
        configuration = config
        compare = nil
        let c = SpecimenGeometry.centre(windowSize: config.windowSize)
        view = WindowViewState(zoomCentre: SIMD2(Double(c.x), Double(c.y)))
        if let split = params["split"] { view.split = split == "off" ? nil : Double(split).map { Swift.min(Swift.max($0, 0), 1) } ?? 0.5 }
        if let zoom = params["zoom"].flatMap(Double.init) { view.zoom = Swift.min(Swift.max(zoom, 1), 8) }
        if let pass = params["pass"].flatMap(Int.init) { view.shownPass = pass }
        isFirstLaunch = launch.scenario == .firstLaunch
        focusPullDone = !isFirstLaunch
        // In memory only (a scenario never saves settings): the coaching line belongs to the first-launch scenario alone, so
        // every other screenshot shows the normal status row.
        settings.coachingLineArmed = isFirstLaunch
        path = []
        sheet = nil
        settleForLaunch = params[LaunchParameter.settle] == "1"
        let blur = config.blur
        var final: (@MainActor (BenchModel) -> Void)?
        switch launch.scenario {
        case .bench, .firstLaunch, .accessibility, .gallery, .contentGallery:
            break
        case .loupe:
            final = { bench in
                let p = bench.configuration.probe
                bench.view.loupe = p
                Task { await bench.setLoupe(p) }
            }
        case .compare:
            let state = Self.launchCompareState(params, a: config, bench: self)
            startCompare(state)
            if let lesson = params["lesson"].flatMap({ id in BlurServices.lessons.first { $0.id == id } }) { apply(lesson) }
        case .layers:
            let floor = launch.floor ?? .math
            final = { $0.path = [.layers(floor)] }
        case .trace:
            if let lesson = params["lesson"].flatMap({ id in BlurServices.lessons.first { $0.id == id } }) { apply(lesson); path = [] }
            final = { $0.path = [.trace] }
        case .catalog:
            let tab = params["tab"].flatMap(CatalogTab.init(rawValue:)) ?? .blurs
            final = { $0.sheet = .catalog(tab) }
        case .fingerprints: final = { $0.sheet = .catalog(.fingerprints) }
        case .divergence: final = { $0.sheet = .catalog(.divergence) }
        case .lessons:
            if let lesson = params["lesson"].flatMap({ id in BlurServices.lessons.first { $0.id == id } }) { apply(lesson) }
            else { final = { $0.sheet = .catalog(.lessons) } }
        case .fingerprint: final = { $0.sheet = .fingerprint(blur) }
        case .fieldGuide:
            let tab = params["tab"].flatMap(FieldGuideTab.init(rawValue:)) ?? .guide
            final = { $0.sheet = .fieldGuide(tab, blur) }
        case .thisPhone: final = { $0.sheet = .fieldGuide(.thisPhone, nil) }
        case .runs: final = { $0.sheet = .fieldGuide(.runs, nil) }
        case .settings: final = { $0.sheet = .fieldGuide(.settings, nil) }
        case .calibrate:
            let subject = params["subject"].flatMap(CalibrationSubject.init(rawValue:)) ?? .swiftUIBlur
            final = { $0.sheet = .calibrate(subject) }
        }
        if let final {
            if settleForLaunch || launch.scenario == .loupe { deferredLaunch.append(final) } else { final(self) }
        }
    }

    static func applyLaunchParameters(_ params: [String: String], to config: inout RenderConfiguration) {
        guard let entry = BlurRegistry.entry(config.blur) else { return }
        for (key, raw) in params {
            guard let spec = entry.spec(ParameterKey(rawValue: key)) else { continue }
            switch spec.kind {
            case .continuous(let c): if let v = Double(raw) { config.parameters[spec.key] = .double(c.clamped(v)) }
            case .integer(let i): if let v = Int(raw) { config.parameters[spec.key] = .int(i.clamped(v)) }
            case .choice(let c): if c.options.contains(where: { $0.id == raw }) { config.parameters[spec.key] = .choice(raw) }
            case .toggle: config.parameters[spec.key] = .bool(raw == "1" || raw == "true")
            case .sequence(let s):
                let list = raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    .map { Swift.min(Swift.max($0, s.elementRange.lowerBound), s.elementRange.upperBound) }
                if !list.isEmpty { config.parameters[spec.key] = .intList(list) }
            case .position:
                let xy = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                if xy.count == 2 { config.parameters[spec.key] = .point(x: xy[0], y: xy[1]) }
            }
        }
        if let variant = params["variant"], entry.variant(VariantID(rawValue: variant)) != nil { config.variant = VariantID(rawValue: variant) }
        if let ev = params["ev"].flatMap(Int.init) { config.specimenOptions.exposureEV = Swift.min(Swift.max(ev, -2), 6) }
        for (key, value) in params where key.hasPrefix("opt.") { config.specimenOptions.choices[String(key.dropFirst(4))] = value }
        let n = config.windowSize
        func point(_ raw: String?) -> PixelPoint? {
            guard let xy = raw?.split(separator: ",").compactMap({ Int($0.trimmingCharacters(in: .whitespaces)) }), xy.count == 2 else { return nil }
            return PixelPoint(x: xy[0], y: xy[1])
        }
        if let p = point(params["probe"]) { config.probe = PixelPoint(x: Swift.min(Swift.max(p.x, 0), n - 1), y: Swift.min(Swift.max(p.y, 0), n - 1)) }
        if let p = point(params["pan"]) {
            let m = SpecimenGeometry.margin
            config.pan = PixelPoint(x: Swift.min(Swift.max(p.x, -m), m), y: Swift.min(Swift.max(p.y, -m), m))
        }
        switch params["colour"] { case "srgb": config.settings.colourSpace = .srgbEncoded; case "linear": config.settings.colourSpace = .linearLight; default: break }
        if let edge = params["edge"].flatMap(EdgeMode.init(rawValue:)) { config.settings.edgeMode = edge }
        if let alpha = params["alpha"].flatMap(AlphaMode.init(rawValue:)) { config.settings.alphaMode = alpha }
        if params["preview"] == "full" { config.settings.preview = .alwaysFull }
    }

    static func launchCompareState(_ params: [String: String], a: RenderConfiguration, bench: BenchModel) -> CompareState? {
        let axis = params["axis"].flatMap(CompareAxis.init(rawValue:)) ?? .operator
        let view = params["view"].flatMap(CompareView.init(rawValue:)) ?? .wipe
        let match = params["match"].flatMap(MatchRule.init(rawValue:)) ?? .sigma
        let choices = bench.legalChoices(axis: axis).filter { $0.disabledReason == nil }
        var choice: CompareChoice?
        switch axis {
        case .operator:
            let wanted = params["b"].map(BlurID.init(rawValue:)) ?? (a.blur == "box-blur" ? GaussianOperator.id : "box-blur")
            choice = choices.first { $0.configuration.blur == wanted } ?? choices.first
        case .implementation:
            if params["bvariant"] == "cpu" { choice = choices.first { $0.id == "implementation.cpu" } }
            else if let v = params["bvariant"] { choice = choices.first { $0.configuration.variant.rawValue == v } }
            choice = choice ?? choices.first
        default:
            choice = choices.first
        }
        guard var b = choice?.configuration else { return nil }
        if axis == .operator, let opB = BlurRegistry.op(b.blur) {
            Self.applyLaunchParameters(params.filter { !["probe", "pan", "variant", "ev"].contains($0.key) && opB.entry.spec(ParameterKey(rawValue: $0.key)) != nil
                && BlurRegistry.entry(a.blur)?.spec(ParameterKey(rawValue: $0.key)) == nil }, to: &b)
        }
        let split = params["cmpsplit"].flatMap(Double.init) ?? 0.5
        return CompareState(b: b, axis: axis, match: match, view: view == .lineUp ? .wipe : view, split: split,
                            drivingB: params["driveB"] == "1")
    }

    public func snapshot() -> BenchSnapshot {
        BenchSnapshot(configuration: configuration, view: view, compare: compare, firstLaunchDone: !isFirstLaunch)
    }
    /// The scheduler clock (CADisplayLink or a 30 Hz timer while needed): settle, timing, idle calibration.
    public func tick(now: Double) {
        if !isInteracting && isAppActive {
            let actions = scheduler.tick(at: now)
            if actions.contains(where: { if case .startTiming = $0 { true } else { false } }) { settlePending = false }
            perform(actions)
        }
        if let n = notice, n.until != .infinity, n.until <= now { notice = nil }
        let thermalNow = thermal()
        if idleGate.mayRun(at: now, thermal: thermalNow) && !isInteracting {
            calibrationHooks?.tick(now, thermalNow)
            startIdleWorkIfNeeded()
        }
        refreshStatus()
    }

    // MARK: The render loop

    /// Every user-driven change: the first one ends the first-launch coaching line (SPEC §2), and a lesson's look-for line
    /// stays only until a control changes.
    private func userChanged() {
        if isFocusPulling { focusPullTask?.cancel(); focusPullTask = nil; isFocusPulling = false; focusPullDone = true }
        if isFirstLaunch {
            isFirstLaunch = false
            if settings.coachingLineArmed { settings.coachingLineArmed = false; if persistsSnapshot { settings.save() } }
        } else if settings.coachingLineArmed {
            settings.coachingLineArmed = false
            if persistsSnapshot { settings.save() }
        }
        lessonLine = nil
    }

    private func acceptedChange(keepLesson: Bool = false) {
        requestRender(interacting: isInteracting || crownTurning)
        schedulePersist()
    }

    func configuration(for slot: RunSlot) -> RenderConfiguration? {
        switch slot {
        case .a: configuration
        case .b: compare?.b
        case .c: compare.flatMap { $0.extra.count > 0 ? $0.extra[0] : nil }
        case .d: compare.flatMap { $0.extra.count > 1 ? $0.extra[1] : nil }
        }
    }

    private func requestRender(interacting: Bool) {
        guard started else { return }
        var preview: RenderQuality?
        if configuration.settings.preview == .halfWhileMoving, let op, let scale = op.previewScale(configuration.operatorRequest) {
            preview = scale >= 0.5 ? .half : .quarter
        }
        perform(scheduler.requestChanged(at: now, preview: preview, interacting: interacting))
        settlePending = true
        ensureClock()
        refreshStatus()
    }

    private func perform(_ actions: [RenderAction]) {
        for action in actions {
            switch action {
            case .render(let quality, let generation):
                pending = (quality, generation)
                if renderTask == nil { renderTask = Task { [weak self] in await self?.drainRenders() } }
            case .startTiming(let generation):
                startMeasurements(generation: generation)
            case .cancelMeasurements:
                measurementTask?.cancel(); measurementTask = nil
                renderer.cancelMeasurements(slot: nil)
                if case .timing = phase { phase = .idle }
            }
        }
    }

    private func drainRenders() async {
        while isAppActive, let next = pending {
            pending = nil
            let passes = Swift.max(1, op?.passPlan(configuration.operatorRequest).passes.count ?? 1)
            phase = next.quality == .full ? .rendering(pass: passes, of: passes) : .preview
            refreshStatus()
            for slot in activeSlots {
                guard isAppActive else { renderDeferredWhileInactive = true; break }
                guard let config = configuration(for: slot) else { continue }
                let traced = slot == .a && activeTrace != nil && next.quality == .full
                let request = RenderRequest(configuration: config, slot: slot, quality: next.quality, generation: next.generation,
                                            kind: traced ? .trace : .display, traced: traced)
                do {
                    if let run = try await renderer.render(request) { accept(run) }
                    if slot == .a { lastError = nil }
                } catch is CancellationError {
                } catch {
                    lastError = Self.describe(error)
                    markAcknowledged(slot, next.generation)       // a failed render must not leave RENDERING… up forever
                }
            }
            runDeferredLaunchIfReady()
        }
        if !isAppActive && pending != nil { renderDeferredWhileInactive = true }
        renderTask = nil
        phase = isHeld ? .preview : .idle
        refreshStatus()
    }

    static func describe(_ error: any Error) -> String {
        if let gpu = error as? GPUError {
            switch gpu {
            case .unsupported(let s), .notPrepared(let s), .missingFunction(let s), .budgetExceeded(let s), .commandBufferFailed(let s),
                 .textureAllocationFailed(let s), .encoderUnavailable(let s): return s.uppercased()
            case .noDevice: return "NO METAL DEVICE"
            case .noCommandQueue: return "NO COMMAND QUEUE"
            case .bufferAllocationFailed: return "BUFFER ALLOCATION FAILED"
            case .readbackFailed: return "READBACK FAILED"
            }
        }
        return String(describing: error).uppercased()
    }

    private func markAcknowledged(_ slot: RunSlot, _ generation: UInt64) {
        guard generation >= (slotAcknowledged[slot] ?? 0) else { return }
        slotAcknowledged[slot] = generation
        if slot == .a { _ = scheduler.acknowledge(generation) }
    }

    /// Monotonic per slot: a stale render never overwrites a newer one.
    private func accept(_ run: Run) {
        guard run.generation >= (slotAcknowledged[run.slot] ?? 0) else { return }
        markAcknowledged(run.slot, run.generation)
        publish(run)
    }

    /// Publishes an acknowledged Run. The image follows every Run; only full-resolution Runs update PIXEL, loupe, pills,
    /// rail, telemetry and Trace (a preview leaves them HELD). Internal so the phone AppTests can drive it directly.
    func publish(_ run: Run) {
        acknowledged[run.slot] = run
        if run.slot == .a { telemetry.isHeld = !run.quality.publishesMeasurements }
        guard run.quality.publishesMeasurements else { return }
        if lastFull[run.slot]?.configuration != run.configuration { lastParity[run.slot] = nil }
        lastFull[run.slot] = run
        guard run.slot == .a else { if compare != nil { refreshReadouts() }; return }
        if probeFollowsSpecimen { refreshSpecimenProbe() }
        if !Self.sameTiming(lastTimed[.a]?.configuration, run.configuration) {
            let start = sessionStartDate
            lastTimed[.a] = runLog.latestTimed(for: run.configuration).flatMap { $0.createdAt >= start ? $0 : nil }
        }
        refreshTelemetry(for: run)
        refreshReadouts()
        if let centre = view.loupe { Task { await self.refreshLoupe(at: centre) } }
        if let trace = activeTrace, run.trace != nil { trace.receive(run) }
        Task { await self.ensureContent(for: run.configuration) }
    }

    static func sameTiming(_ a: RenderConfiguration?, _ b: RenderConfiguration?) -> Bool {
        guard let a, let b else { return false }
        return RunLogStore.timingKey(a) == RunLogStore.timingKey(b)
    }

    private func refreshTelemetry(for run: Run) {
        telemetry.sigmaEff = run.kernel.sigmaEff.map { .number($0, .decimals(2, unit: "px", spokenUnit: "pixels"), .computed) }
        telemetry.gpu = gpuValue(lastTimed[.a])
        telemetry.parity = lastParity[.a].map { Self.parityValue($0, device: run.device) } ?? .notYetMeasured()
    }

    /// GPU (BLUR PASSES): the settled timing of exactly this configuration, `TOO SLOW TO TIME` above the full budget,
    /// no timing in the Simulator, `–.––` until measured.
    private func gpuValue(_ timed: Run?) -> BadgedValue {
        if renderer.gpu.facts.isSimulator { return .words("— NO GPU TIMING IN SIMULATOR", spoken: "no GPU timing in the Simulator") }
        if !RenderCoordinator.isTimeable(configuration) {
            let ms = RenderCoordinator.modeledMilliseconds(configuration) ?? 0
            return .words("TOO SLOW TO TIME", spoken: "too slow to time, about \(NumberStyle.decimals(0).text(ms)) milliseconds modeled", .modeled)
        }
        guard let timed, let timing = timed.timing, Self.sameTiming(timed.configuration, configuration) else { return .notYetMeasured(unit: "ms") }
        return Self.millisecondsValue(timing.medianMilliseconds, samples: timing.samples, device: timed.device)
    }

    static func millisecondsValue(_ ms: Double, samples: Int, device: DeviceStamp) -> BadgedValue {
        let caption = "n " + NumberStyle.integer().text(Double(samples))
        guard ms < 0.05 else {
            return .number(ms, .decimals(2, unit: "ms", spokenUnit: "milliseconds"), .measured, device: device, caption: caption)
        }
        return BadgedValue(value: ms, text: "< 0.05", unit: "ms", provenance: .measured, device: device, caption: caption,
                           spoken: "less than 0.05 milliseconds, \(Provenance.measured.spokenPhrase(device: device)), \(caption)")
    }

    /// PARITY: `≤ 1 LSB` / `3 LSB` in 8-bit steps, MEASURED, fp16 ulps in the spoken value; report-only classes say why.
    static func parityValue(_ parity: ParitySummary, device: DeviceStamp) -> BadgedValue {
        if parity.tolerance.reportOnly {
            if parity.tolerance.name == RenderCoordinator.subTexelPendingName {
                return .words("SUB-TEXEL RULE NOT YET MEASURED", spoken: "parity waits for this phone's sub-texel rule")
            }
            return .words("REPORT ONLY", spoken: "parity is shown, not judged, for this class")
        }
        let lsb = parity.stats.maxLSB8
        let ulps = NumberStyle.integer().text(parity.stats.maxULP16.rounded(.up))
        let text = lsb <= 1 ? "≤ 1" : NumberStyle.integer().text(lsb.rounded(.up))
        let spokenLSB = lsb <= 1 ? "at most 1 eight-bit step" : "\(text) eight-bit steps"
        let caption = parity.passed ? "\(ulps) ULP16" : "GPU DIFFERS FROM THE MATH"
        return BadgedValue(value: lsb, text: text, unit: "LSB", provenance: .measured, device: device, caption: caption,
                           spoken: "\(spokenLSB), \(ulps) fp16 ulps, \(Provenance.measured.spokenPhrase(device: device))"
                               + (parity.passed ? "" : ", GPU differs from the math"))
    }

    /// Rail chips and pills from the newest full Run (CONTENT-LAYERS' builder), computed off the main actor; in Compare
    /// each chip carries its floor comparison (first ≠ is `.partsWays`).
    private func refreshReadouts() {
        guard let op, let context = floorContext(slot: .a) else { return }
        let b = compare?.b
        let home = settings.homeToolID, scale = displayScale, a = configuration
        let stamp = lastFull[.a]?.id
        readoutTask?.cancel()
        readoutTask = Task { [weak self] in
            let built = await Task.detached(priority: .userInitiated) { () -> ([RailChip], PillContent, [FloorComparison]) in
                let comparisons = b.map { BlurServices.divergence.compare(a, $0, homeToolID: home, displayScale: scale) } ?? []
                return (BlurServices.floors.railChips(for: op, context: context), BlurServices.floors.pills(for: op, context: context), comparisons)
            }.value
            guard let self, !Task.isCancelled, self.lastFull[.a]?.id == stamp else { return }
            var chips = built.0
            if !built.2.isEmpty {
                chips = chips.map { chip in
                    var c = chip
                    c.comparison = built.2.first { $0.floor == chip.floor }
                    return c
                }
            }
            self.railChips = chips
            self.pills = built.1
            if self.compare != nil { self.refreshCompareColumns() }
            self.refreshStatus()
        }
    }

    // MARK: Measurements (after settle; never in the first 10 s)

    private func startMeasurements(generation: UInt64) {
        measurementTask?.cancel()
        measurementTask = Task { [weak self] in await self?.measure(generation) }
    }

    private func measure(_ generation: UInt64) async {
        while renderTask != nil {
            try? await Task.sleep(for: .milliseconds(20))
            if Task.isCancelled { return }
        }
        guard scheduler.currentGeneration == generation, let full = lastFull[.a], full.generation == generation else {
            scheduler.measurementsFinished(generation: generation)
            return
        }
        refreshInputFacts()
        // The settled display Runs go into the log once per generation.
        for slot in activeSlots {
            guard let run = lastFull[slot], run.generation == generation else { continue }
            let key = "\(slot.rawValue).\(generation)"
            if !loggedGenerations.contains(key) { loggedGenerations.insert(key); runLog.append(run) }
        }
        // SPEC §2: nothing measures in the first ten seconds after launch.
        let wait = launchUptime + 10 - now
        if wait > 0 {
            try? await Task.sleep(for: .seconds(wait + 0.05))
            if Task.isCancelled || scheduler.currentGeneration != generation { return }
        }
        guard isAppActive else { return }                     // re-armed by setAppActive(true)
        let a = configuration
        let other: RenderConfiguration? = compare.flatMap { RenderCoordinator.isExternal($0.b.variant) ? nil : $0.b }
        if !renderer.gpu.facts.isSimulator && RenderCoordinator.isTimeable(a) {
            phase = .timing
            refreshStatus()
            do {
                let runs = try await renderer.time(a, slot: .a, interleavedWith: other)
                guard !Task.isCancelled, scheduler.currentGeneration == generation else { return }
                if let runA = runs.first {
                    lastTimed[.a] = runA
                    runLog.append(runA)
                    telemetry.gpu = gpuValue(runA)
                }
                if runs.count > 1 {
                    lastTimed[.b] = runs[1]
                    runLog.append(runs[1])
                    if let ta = runs[0].timing, let tb = runs[1].timing {
                        let caption = ta.thermalChanged || tb.thermalChanged ? "THERMAL CHANGED" : (ta.interleaved ? "ABAB" : "NOT INTERLEAVED")
                        telemetry.deltaGPU = .number(ta.medianMilliseconds - tb.medianMilliseconds,
                                                     NumberStyle(precision: .decimals(2), unit: "ms", spokenUnit: "milliseconds", explicitPlus: true),
                                                     .measured, device: runs[0].device, caption: caption)
                    }
                }
                refreshReadouts()
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                telemetry.gpu = .words("NOT TIMED", spoken: "timing failed: \(Self.describe(error).lowercased())")
            }
        } else if !RenderCoordinator.isTimeable(a) {
            telemetry.gpu = gpuValue(nil)
        }
        // Parity after timing, at background priority, cancellable (review fix E-8).
        guard isAppActive else { return }
        do {
            if let summary = try await renderer.parity(a, slot: .a) {
                guard !Task.isCancelled, scheduler.currentGeneration == generation else { return }
                lastParity[.a] = summary
                telemetry.parity = Self.parityValue(summary, device: full.device)
                runLog.append(Run(kind: .parity, generation: generation, slot: .a, configuration: full.configuration,
                                  resolvedVariant: full.resolvedVariant, quality: .full, device: renderer.deviceStamp(), gpu: full.gpu,
                                  kernel: full.kernel, dispatch: full.dispatch, timing: nil, cost: nil, parity: summary, probe: full.probe,
                                  shape: nil, shader: full.shader, trace: nil, calibration: nil, deviceProbe: nil))
            }
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            telemetry.parity = .words("NOT CHECKED", spoken: "parity could not run: \(Self.describe(error).lowercased())")
        }
        if compare != nil { await measureCompareDifference(generation) }
        guard !Task.isCancelled, scheduler.currentGeneration == generation else { return }
        scheduler.measurementsFinished(generation: generation)
        phase = isHeld ? .preview : .idle
        refreshStatus()
    }

    /// Compare's MAX |A−B| in 8-bit encoded steps with its position (LIVE), from the two full-resolution outputs.
    private func measureCompareDifference(_ generation: UInt64) async {
        guard lastFull[.a] != nil, lastFull[.b] != nil else { return }
        let n = configuration.windowSize
        let region = PixelRegion(origin: .zero, size: .square(n))
        guard let a = try? await renderer.readTexels(slot: .a, pass: nil, region: region),
              let b = try? await renderer.readTexels(slot: .b, pass: nil, region: region),
              a.count == n * n, b.count == n * n, !Task.isCancelled else { return }
        let result = await Task.detached(priority: .utility) { () -> (Double, Int) in
            var worst = 0.0, at = 0
            for i in a.indices {
                for ch in 0..<3 {
                    let d = abs(Double(SRGB.code8(linear: Double(a[i][ch]))) - Double(SRGB.code8(linear: Double(b[i][ch]))))
                    if d > worst { worst = d; at = i }
                }
            }
            return (worst, at)
        }.value
        guard !Task.isCancelled, scheduler.currentGeneration == generation else { return }
        telemetry.maxDifference = .number(result.0, NumberStyle(precision: .decimals(0), unit: "LSB", spokenUnit: "eight-bit steps"), .live)
        telemetry.maxDifferenceAt = PixelPoint(x: result.1 % n, y: result.1 / n)
    }

    /// The Compare telemetry column for the axis (SPEC §4.2): ΔFETCHES/PX (Operator, Implementation), CPU REF TIME
    /// (B is the CPU reference), Δσ EFF (Precision, Space), the twin's mapping (Apple).
    private func refreshCompareColumns() {
        guard let state = compare, let opA = op, let opB = BlurRegistry.op(state.b.blur) else { telemetry.axisColumn = nil; return }
        let a = configuration.operatorRequest, b = state.b.operatorRequest
        switch state.axis {
        case .operator, .implementation:
            if state.b.variant.rawValue.hasPrefix(RenderCoordinator.cpuReferencePrefix) {
                if let ms = renderer.cpuReferenceMilliseconds(slot: .b) {
                    telemetry.axisColumn = LabeledValue(id: "cpuRef", label: "CPU REF TIME",
                                                        value: .number(ms, .decimals(0, unit: "ms", spokenUnit: "milliseconds"), .measured,
                                                                       device: renderer.deviceStamp()))
                }
            } else {
                let delta = opA.passPlan(a).fetchesPerPixel - opB.passPlan(b).fetchesPerPixel
                telemetry.axisColumn = LabeledValue(id: "dFetches", label: "ΔFETCHES/PX",
                                                    value: .number(delta, NumberStyle(precision: .decimals(0), explicitPlus: true), .computed))
            }
        case .precision, .space:
            if let sa = lastFull[.a]?.kernel.sigmaEff, let sb = lastFull[.b]?.kernel.sigmaEff {
                telemetry.axisColumn = LabeledValue(id: "dSigma", label: "Δσ EFF",
                                                    value: .number(sa - sb, NumberStyle(precision: .decimals(2), unit: "px", spokenUnit: "pixels",
                                                                                        explicitPlus: true), .computed))
            }
        case .apple:
            let twin = String(state.b.variant.rawValue.dropFirst(RenderCoordinator.appleTwinPrefix.count))
            if let spec = opA.entry.appleTwins.first(where: { $0.id == twin }) {
                telemetry.axisColumn = LabeledValue(id: "twin", label: "TWIN", value: .words(spec.mapping, spoken: spec.mapping, spec.provenance,
                                                                                            source: spec.source))
            }
        }
    }

    // MARK: Status row (SPEC §4.1.3: exactly one line, highest priority first)

    private func refreshStatus() {
        let t = now
        if renderTask != nil {
            status = .rendering(BadgedLine([.text("RENDERING…")]))
        } else if let n = notice, n.until > t {
            status = .notice(n.line)
        } else if let warning = warningLine() {
            status = .warning(warning)
        } else if let lesson = lessonLine {
            status = .lesson(lesson)
        } else if settings.coachingLineArmed && !isFocusPulling && started {
            status = .coaching(.words("TURN A CROWN · DRAG THE IMAGE · TAP A BLUR"))
        } else if compare != nil, let line = compareLine() {
            status = .phase(line)
        } else if let drivingB = compare?.drivingB, drivingB {
            status = .phase(.words("DRIVING B"))
        } else if let op {
            status = .phase(op.passPlan(configuration.operatorRequest).phase)
        } else {
            status = .phase(.empty)
        }
    }

    private func warningLine() -> BadgedLine? {
        if let error = lastError { return BadgedLine([.text("NOT RENDERED ·"), .literal(error)]) }
        if let reason = lastFull[.a]?.resolvedVariant.reason, lastFull[.a]?.configuration == configuration { return BadgedLine([.literal(reason)]) }
        if let op, let warning = op.statusWarning(configuration.operatorRequest) { return BadgedLine([.literal(warning)]) }
        if !RenderCoordinator.isTimeable(configuration), let ms = RenderCoordinator.modeledMilliseconds(configuration) {
            return BadgedLine([.text("TOO SLOW TO TIME · ≈"), .value(.number(ms, .decimals(0, unit: "ms", spokenUnit: "milliseconds"), .modeled)),
                               .text("MODELED")])
        }
        return nil
    }

    /// Compare's status line: `MIN H  A −0.0012 · B −0.217 · PARTS WAYS AT MATH` (COMPUTED from the kernels each slot runs),
    /// `DRIVING B` first while the crowns drive B.
    private func compareLine() -> BadgedLine? {
        guard let state = compare else { return nil }
        var segments: [BadgedSegment] = []
        if state.drivingB { segments.append(.text("DRIVING B ·")) }
        let configs = [configuration, state.b] + state.extra
        segments.append(.text("MIN H"))
        for (letter, original) in zip(["A", "B", "C", "D"], configs) {
            segments.append(.literal(letter))
            // The CPU reference runs the same kernel as its variant; an Apple twin's kernel is not ours to compute (N/A).
            var config = original
            if config.variant.rawValue.hasPrefix(RenderCoordinator.cpuReferencePrefix) {
                config.variant = VariantID(rawValue: String(config.variant.rawValue.dropFirst(RenderCoordinator.cpuReferencePrefix.count)))
            }
            if let minimum = BlurRegistry.op(config.blur)?.response(ResponseQuery(), config.operatorRequest, content: nil)?.minimum?.value,
               !RenderCoordinator.isExternal(config.variant) {
                let style: NumberStyle = minimum == 0 ? .decimals(0) : (abs(minimum) < 0.01 ? .significant(2) : .significant(3))
                segments.append(.value(.number(minimum, style, .computed)))
            } else {
                segments.append(.text("N/A"))
            }
            if letter != ["A", "B", "C", "D"][configs.count - 1] { segments.append(.text("·")) }
        }
        if let parts = railChips.compactMap(\.comparison).first(where: { $0.verdict == .partsWays }) {
            segments.append(.text("· PARTS WAYS AT \(parts.floor.title.uppercased())"))
        }
        return BadgedLine(segments)
    }

    // MARK: Clock, idle work, focus pull, persistence

    private func ensureClock() {
        guard clockTask == nil else { return }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick(now: self.clock())
                let fast = self.isInteracting || self.isFocusPulling || self.renderTask != nil || self.settlePending
                    || self.notice != nil
                let idleOutstanding = self.calibrationHooks != nil || !(self.subTexelProbeDone && self.prewarmDone)
                if !fast && !idleOutstanding { break }
                try? await Task.sleep(for: .milliseconds(fast ? 33 : 500))
            }
            self?.clockTask = nil
        }
    }

    private func startIdleWorkIfNeeded() {
        guard idleWorkTask == nil, !(subTexelProbeDone && prewarmDone) else { return }
        idleWorkTask = Task { [weak self] in
            guard let self else { return }
            if !self.subTexelProbeDone {
                // The one automatic device probe (SPEC §13.2): in-app parity of bilinear classes depends on it.
                if !self.runLog.deviceProbes.contains(where: { $0.kind == .bilinearSubTexelBits }),
                   let run = await self.renderer.runDeviceProbe(.bilinearSubTexelBits) {
                    self.runLog.append(run)
                }
                self.subTexelProbeDone = true
            }
            if !self.prewarmDone {
                _ = await self.renderer.prewarmHeroDozen(windowSize: self.configuration.windowSize) { [weak self] in
                    guard let self else { return false }
                    return !self.isInteracting
                }
                self.prewarmDone = true
            }
            self.idleWorkTask = nil
        }
    }

    /// First launch (SPEC §2, 0.0–0.6 s): the right half eases from the smallest σ to its value over 600 ms (≤ 36 renders,
    /// no timing); the hero counts up with it. Skipped under Reduce Motion. Any touch ends it at once.
    public func startFocusPull(reduceMotion: Bool) {
        guard !focusPullDone, focusPullTask == nil, let spec = entry?.primarySpec, case .continuous(let c) = spec.kind,
              let target = configuration.parameters.double(spec.key) else { focusPullDone = true; return }
        guard !reduceMotion, target > c.range.lowerBound else { focusPullDone = true; schedulePersist(); return }
        isFocusPulling = true
        let key = spec.key, start = c.range.lowerBound, began = now
        focusPullTask = Task { [weak self] in
            var frames = 0
            while let self, !Task.isCancelled {
                let t = Swift.min(1, (self.now - began) / 0.6)
                let eased = 1 - pow(1 - t, 3)
                let value = t >= 1 ? target : c.clamped(((start + (target - start) * eased) / c.fineStep).rounded() * c.fineStep)
                if self.configuration.parameters[key] != .double(value) {
                    self.configuration.parameters[key] = .double(value)
                    self.requestRender(interacting: false)
                    frames += 1
                }
                if t >= 1 || frames >= 36 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard let self, !Task.isCancelled else { return }
            if self.configuration.parameters[key] != .double(target) { self.configuration.parameters[key] = .double(target); self.requestRender(interacting: false) }
            self.isFocusPulling = false
            self.focusPullDone = true
            self.focusPullTask = nil
            self.schedulePersist()
            self.refreshStatus()
        }
    }

    private func schedulePersist() {
        guard persistsSnapshot else { return }
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    /// Writes the restorable state now (scene going to the background). Never for scenario launches.
    public func persistNow() {
        guard persistsSnapshot else { return }
        var snap = snapshot()
        snap.firstLaunchDone = focusPullDone || !isFirstLaunch
        if let data = try? JSONEncoder().encode(snap) { UserDefaults.standard.set(data, forKey: Self.snapshotKey) }
    }

    static let snapshotKey = "B2BenchSnapshot.v1"
    /// The restored snapshot (later launches show it immediately, SPEC §2), when it still names registered ids.
    public static func restoredSnapshot(windowSize n: Int, settings: SilentSettings, defaults: UserDefaults = .standard) -> BenchSnapshot {
        if let data = defaults.data(forKey: snapshotKey), let snapshot = try? JSONDecoder().decode(BenchSnapshot.self, from: data),
           BlurRegistry.op(snapshot.configuration.blur)?.entry.tier.runsLive == true,
           SpecimenRegistry.generator(snapshot.configuration.specimen) != nil {
            var s = snapshot
            if let compare = s.compare, BlurRegistry.op(compare.b.blur) == nil { s.compare = nil }
            return s
        }
        return BenchSnapshot(configuration: defaultConfiguration(windowSize: n, settings: settings), view: WindowViewState(), compare: nil,
                             firstLaunchDone: false)
    }

    // MARK: Launch scenarios that wait for a settled Run, specimen probes, input facts, LIVE content

    private func runDeferredLaunchIfReady() {
        guard !deferredLaunch.isEmpty, let full = lastFull[.a], full.configuration == configuration, pending == nil else { return }
        let actions = deferredLaunch
        deferredLaunch = []
        let delay = settleForLaunch ? scheduler.settleSeconds : 0
        Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard let self else { return }
            for action in actions { action(self) }
        }
    }

    /// Snaps the probe to the canvas's own feature probe (SPEC §11 rule 3) while it still follows the specimen default.
    private func refreshSpecimenProbe() {
        guard probeFollowsSpecimen else { return }
        let config = configuration
        Task { [weak self] in
            guard let self, let probe = await self.specimenDefaultProbe(for: config), self.probeFollowsSpecimen,
                  self.configuration.specimen == config.specimen, self.configuration.windowSize == config.windowSize else { return }
            self.probeFollowsSpecimen = false
            guard probe != self.configuration.probe else { return }
            self.configuration.probe = probe
            self.syncCompare()
            self.acceptedChange()
        }
    }

    /// The canvas's own feature probe, clamped into the window (a probe defined for 894 px may fall outside a smaller one).
    private func specimenDefaultProbe(for config: RenderConfiguration? = nil) async -> PixelPoint? {
        let c = config ?? configuration
        guard let p = await renderer.specimens.canvas(c.specimen, options: c.specimenOptions, windowSize: c.windowSize)?.defaultProbe else { return nil }
        let n = c.windowSize
        return PixelPoint(x: Swift.min(Swift.max(p.x, 0), n - 1), y: Swift.min(Swift.max(p.y, 0), n - 1))
    }

    /// The brightest input pixel and the strongest edge on the probe's row, for the Jump menu (computed off the main actor).
    private func refreshInputFacts() {
        let c = configuration
        let key = "\(c.specimen.rawValue)|\(c.specimenOptions.canvasOptions.choices.sorted { $0.key < $1.key })|\(c.pan.x),\(c.pan.y)|\(c.probe.y)|\(c.windowSize)"
        guard key != inputFactsKey else { return }
        inputFactsKey = key
        let hdr = SpecimenRegistry.generator(c.specimen)?.descriptor.isHDR ?? false
        Task { [weak self] in
            guard let self, let canvas = await self.renderer.specimens.canvas(c.specimen, options: c.specimenOptions, windowSize: c.windowSize) else { return }
            let facts = await Task.detached(priority: .utility) { () -> BenchInputFacts in BenchInputFacts(canvas: canvas, pan: c.pan, row: c.probe.y, hdr: hdr) }.value
            guard self.inputFactsKey == key else { return }
            self.inputFacts = facts
        }
    }

    private func contentKey(_ c: RenderConfiguration) -> String {
        "\(c.specimen.rawValue)|\(c.specimenOptions)|\(c.pan.x),\(c.pan.y)|\(c.windowSize)|\(c.settings)"
    }

    /// The current window after the pre-pass (half-rounded), for LIVE · CPU weight maps of data-dependent blurs.
    private func ensureContent(for config: RenderConfiguration) async {
        guard BlurRegistry.entry(config.blur)?.properties.contains(.dataDependent) == true else { return }
        let key = contentKey(config)
        guard contentCache?.key != key,
              let canvas = await renderer.specimens.canvas(config.specimen, options: config.specimenOptions, windowSize: config.windowSize) else { return }
        let pan = config.pan, ev = config.specimenOptions.exposureEV, settings = config.settings
        let content = await Task.detached(priority: .utility) { () -> OperatorContent in
            let window = canvas.window(pan: pan)
            var image = window.image.roundedToHalf()
            if ev != 0 { image = image.scaled(by: Float(pow(2.0, Double(ev)))).roundedToHalf() }
            var pre = ColourTransform.pre(image, settings)
            if ColourTransform.needsPasses(settings) { pre = pre.roundedToHalf() }
            return OperatorContent(image: pre, auxiliary: window.auxiliary)
        }.value
        contentCache = (key, content)
    }

    // MARK: Trace (the frame on screen IS the traced frame while the Trace is open)

    /// Opens the traced build for `session`: prepares the TRACE_PROBE specialization (inside `render`) and renders A
    /// traced at full resolution; returns that Run (nil when it could not render). The Bench keeps the untraced frame
    /// until the traced one is ready (`PREPARING TRACED BUILD`).
    func beginTrace(_ session: TraceSession) async -> Run? {
        activeTrace = session
        refreshInputFacts()
        while renderTask != nil { try? await Task.sleep(for: .milliseconds(15)); if Task.isCancelled { return nil } }
        return await renderTraced(kind: .trace)
    }

    /// Renders A once more at the current generation, traced or not (opening and closing the Trace is not a change).
    private func renderTraced(kind: RunKind) async -> Run? {
        let request = RenderRequest(configuration: configuration, slot: .a, quality: .full, generation: scheduler.currentGeneration,
                                    kind: kind, traced: activeTrace != nil)
        do {
            guard let run = try await renderer.render(request) else { return nil }
            accept(run)
            if run.trace != nil { runLog.append(run) }
            return run
        } catch {
            lastError = Self.describe(error)
            refreshStatus()
            return nil
        }
    }

    /// The Trace closed: back to the untraced specialization.
    func endTrace(_ session: TraceSession) {
        guard activeTrace === session || activeTrace == nil else { return }
        activeTrace = nil
        guard started else { return }
        Task { [weak self] in
            guard let self else { return }
            while self.renderTask != nil { try? await Task.sleep(for: .milliseconds(15)) }
            _ = await self.renderTraced(kind: .display)
        }
    }

    // MARK: Helpers

    static func thermalLevel(_ state: ProcessInfo.ThermalState) -> ThermalLevel {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .unknown
        }
    }
}

/// Facts about the input window for the Jump menu (computed off the main actor from the canvas).
public struct BenchInputFacts: Sendable, Hashable {
    /// The brightest input pixel (Rec. 709 luma), for `Impulse peak`.
    public var brightest: PixelPoint
    public var brightestValue: Float
    /// The strongest step along the probe's row (|Δ luma| between neighbours), for `Edge`; nil on a flat row.
    public var edge: PixelPoint?
    /// Point-light test images (HDR, a peak above 1 or an isolated maximum): `Impulse peak` applies.
    public var isPointLight: Bool

    init(canvas: SpecimenCanvas, pan: PixelPoint, row: Int, hdr: Bool) {
        let n = canvas.windowSize, m = canvas.margin, image = canvas.image
        func luma(_ x: Int, _ y: Int) -> Float {
            Luma.rec709(image[Swift.min(image.width - 1, Swift.max(0, m + pan.x + x)), Swift.min(image.height - 1, Swift.max(0, m + pan.y + y))])
        }
        var best = PixelPoint.zero, bestValue = -Float.infinity
        for y in 0..<n { for x in 0..<n { let l = luma(x, y); if l > bestValue { bestValue = l; best = PixelPoint(x: x, y: y) } } }
        brightest = best
        brightestValue = bestValue
        let y = Swift.min(Swift.max(row, 0), n - 1)
        var edgeAt: PixelPoint?, step: Float = 0.05
        for x in 0..<(n - 1) { let d = abs(luma(x + 1, y) - luma(x, y)); if d > step { step = d; edgeAt = PixelPoint(x: x + 1, y: y) } }
        edge = edgeAt
        isPointLight = hdr || bestValue > 1
    }
}
