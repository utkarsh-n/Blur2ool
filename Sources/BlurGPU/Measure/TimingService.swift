import Foundation
import Metal
import BlurCore

// OWNER: GPU-MEASURE. The timing protocol of SPEC §4.1.6 and ARCHITECTURE §5.8 / §8.2 (review fixes E-7, E-19, E-57):
//
// - Warm-ups: `request.warmups` (3) command buffers that are not timed; the first one also discovers the pass count.
// - Samples: up to `request.samples` (15) timed blurs, stopping early once at least `minSamples` (3) exist and their
//   summed GPU time reached `maxGPUSeconds` (1 s): `stopReason` says which. `n` is always reported.
// - Cancellable between command buffers: `Task.isCancelled` is checked before and after every one, and the service
//   throws `CancellationError` (every touch cancels timing, RenderScheduler.touchBegan).
// - The BLUR PASSES only: `pipeline.encode` on an input the caller already pre-passed. The window copy and the colour /
//   alpha passes are timed once, separately, into `overheadMilliseconds`.
// - Per-pass times: stage-boundary counter samples where the GPU supports them (`.stageBoundaryCounters`, one command
//   buffer, a MeasureStageBoundarySampler on every pass descriptor), otherwise one command buffer per pass
//   (`.passIsolatedCommandBuffers`). `medianMilliseconds` is the whole blur in the form that produced the per-pass
//   bars (the single command buffer's gpuEnd − gpuStart, or the sum of the per-pass buffers).
// - Fused measurement (`measureFused`): the same blur in its least-instrumented form — one command buffer, one encoder
//   per pass (the frozen recorder's minimum; pipelines cannot be merged into fewer encoders without changing them), no
//   counter attachments — timed in alternation with the samples. The UI shows median − fused as MEASUREMENT OVERHEAD.
// - ABAB interleaving for Compare's ΔGPU; thermal state and Low Power Mode at both ends.
// - Never in the Simulator: its GPU times are meaningless (research §4.3 item 3), so every entry point returns nil.

@MainActor
public final class TimingService: GPUTimingMeasuring {
    /// Test seam (ARCHITECTURE §12.3 "Simulator honesty" on the Mac): facts used instead of `context.facts`.
    var factsOverride: GPUFacts?
    /// Test seam: called after every completed command buffer of a timing run with its running count.
    var afterCommandBuffer: (@MainActor (Int) -> Void)?

    public init() {}
    init(factsOverride: GPUFacts?) { self.factsOverride = factsOverride }

    func facts(_ context: GPUContext) -> GPUFacts { factsOverride ?? context.facts }

    public func measure(_ pipeline: any GPUBlurPipeline, inputs: GPUBlurInputs, request: TimingRequest,
                        context: GPUContext) async throws -> TimingSummary? {
        guard !facts(context).isSimulator else { return nil }       // never a number in the Simulator (SPEC §4.1.6)
        try Task.checkCancellation()
        let start = Self.environment()
        let session = MeasureTimingSession(service: self, pipeline: pipeline, inputs: inputs, request: request, context: context)
        try await session.warmUp()
        var gpuSeconds = 0.0
        var stop = TimingStopReason.samplesReached
        while session.samples < request.samples {
            gpuSeconds += try await session.sample()
            if request.measureFused { gpuSeconds += try await session.fusedSample() }
            if session.samples >= request.samples { break }
            if session.samples >= Swift.max(1, request.minSamples), gpuSeconds >= request.maxGPUSeconds { stop = .gpuTimeBudget; break }
        }
        let overhead = try await measureOverhead(inputs, context: context)
        let end = Self.environment()
        return session.summary(stop: stop, interleaved: false, start: start, end: end, overhead: overhead)
    }

    public func measureInterleaved(_ a: (any GPUBlurPipeline, GPUBlurInputs), _ b: (any GPUBlurPipeline, GPUBlurInputs),
                                   request: TimingRequest, context: GPUContext) async throws -> (TimingSummary, TimingSummary)? {
        guard !facts(context).isSimulator else { return nil }
        try Task.checkCancellation()
        let start = Self.environment()
        let sa = MeasureTimingSession(service: self, pipeline: a.0, inputs: a.1, request: request, context: context)
        let sb = MeasureTimingSession(service: self, pipeline: b.0, inputs: b.1, request: request, context: context)
        // A, B, A, B … from the first warm-up on, so both see the same clocks and thermal drift.
        for round in 0..<Swift.max(1, request.warmups) {
            try await sa.warmUpRound(round)
            try await sb.warmUpRound(round)
        }
        var gpuSeconds = 0.0
        var stop = TimingStopReason.samplesReached
        while sa.samples < request.samples || sb.samples < request.samples {
            for s in [sa, sb] where s.samples < request.samples {
                gpuSeconds += try await s.sample()
                if request.measureFused { gpuSeconds += try await s.fusedSample() }
            }
            if sa.samples >= request.samples && sb.samples >= request.samples { break }
            if Swift.min(sa.samples, sb.samples) >= Swift.max(1, request.minSamples), gpuSeconds >= request.maxGPUSeconds {
                stop = .gpuTimeBudget; break
            }
        }
        let overheadA = try await measureOverhead(a.1, context: context)
        let overheadB = try await measureOverhead(b.1, context: context)
        let end = Self.environment()
        return (sa.summary(stop: stop, interleaved: true, start: start, end: end, overhead: overheadA),
                sb.summary(stop: stop, interleaved: true, start: start, end: end, overhead: overheadB))
    }

    public func makeSampler(passes: Int, context: GPUContext) -> (any PassTimestampSampling)? {
        makeStageBoundarySampler(passes: passes, context: context)
    }

    /// The concrete sampler (nil in the Simulator, under forced Apple2 limits, or without stage-boundary counters).
    public func makeStageBoundarySampler(passes: Int, context: GPUContext) -> MeasureStageBoundarySampler? {
        let f = facts(context)
        guard !f.isSimulator, f.supportsStageBoundaryCounters else { return nil }
        return MeasureStageBoundarySampler(device: context.device, passes: passes)
    }

    // MARK: Overhead (window copy + colour passes, timed once; review fix E-57)

    /// Median of 3 command buffers (after 1 warm-up) holding the 0 EV window copy (a blit of the N × N window) and, when
    /// the silent settings need them, the colour/alpha pre- and post-pass — the per-frame work around the blur that
    /// changing the colour space adds, kept out of the blur's own time. Exposure ≠ 0 replaces the blit by
    /// `b2_common_window_fs`; this service is not told the exposure, so it times the 0 EV form.
    func measureOverhead(_ inputs: GPUBlurInputs, context: GPUContext) async throws -> Double? {
        let w = inputs.source.width, h = inputs.source.height
        let needsColour = ColourTransform.needsPasses(inputs.request.settings)
        if needsColour { try await context.prepareCommonPipelines() }
        let windowFormat: TextureFormat = inputs.source.pixelFormat == .rgba8Unorm ? .rgba8Unorm : .rgba16Float
        let windowSpec = TextureSpec(width: w, height: h, format: windowFormat, roles: [.read, .renderTarget])
        let colourSpec = TextureSpec(width: w, height: h, roles: [.read, .renderTarget])
        let window = try context.texture(windowSpec), pre = try context.texture(colourSpec), post = try context.texture(colourSpec)
        defer { context.recycle(window, spec: windowSpec); context.recycle(pre, spec: colourSpec); context.recycle(post, spec: colourSpec) }
        var samples: [Double] = []
        for i in 0..<4 {
            try Task.checkCancellation()
            let recorder = GPUCommandRecorder(context: context, label: "timing overhead \(i)")
            try context.encodeWindowCopy(canvas: inputs.source, margin: 0, pan: .zero, size: Swift.min(w, h), destination: window, recorder: recorder)
            if needsColour {
                try context.encodeColourPass(post: false, settings: inputs.request.settings, source: window, destination: pre, recorder: recorder)
                try context.encodeColourPass(post: true, settings: inputs.request.settings, source: pre, destination: post, recorder: recorder)
            }
            let done = await recorder.commitAndWait()
            if let error = done.compactMap(\.error).first { throw GPUError.commandBufferFailed(error) }
            if i > 0 { samples.append(done.reduce(0) { $0 + $1.milliseconds }) }
        }
        try Task.checkCancellation()
        return MeasureStatistics.median(samples)
    }

    // MARK: Environment

    struct Environment { var thermal: ThermalLevel; var lowPower: Bool }
    static func environment() -> Environment {
        Environment(thermal: level(ProcessInfo.processInfo.thermalState), lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    public static func level(_ state: ProcessInfo.ThermalState) -> ThermalLevel {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .unknown
        }
    }
}

/// One pipeline's timing run: warm-ups, mode choice, samples, fused samples and the summary.
@MainActor
final class MeasureTimingSession {
    enum Mode { case counters(MeasureStageBoundarySampler), isolated, wholeOnly }

    let service: TimingService
    let pipeline: any GPUBlurPipeline
    let inputs: GPUBlurInputs
    let request: TimingRequest
    let context: GPUContext
    private(set) var mode: Mode = .wholeOnly
    private(set) var whole: [Double] = []
    private(set) var perPass: [Int: [Double]] = [:]
    private(set) var fused: [Double] = []
    private(set) var passNames: [Int: String] = [:]
    private(set) var passCount = 0
    private(set) var warmupsRun = 0
    private var commandBuffersRun = 0
    /// Set for the shape service's ms/MP: whole-blur times only, no per-pass instrumentation.
    let wholeOnly: Bool

    init(service: TimingService, pipeline: any GPUBlurPipeline, inputs: GPUBlurInputs, request: TimingRequest, context: GPUContext,
         wholeOnly: Bool = false) {
        self.service = service; self.pipeline = pipeline; self.inputs = inputs; self.request = request; self.context = context
        self.wholeOnly = wholeOnly
    }

    var samples: Int { whole.count }

    var method: TimingMethod {
        switch mode {
        case .counters: .stageBoundaryCounters
        case .isolated: .passIsolatedCommandBuffers
        case .wholeOnly: .commandBuffer
        }
    }

    /// Runs `max(1, warmups)` untimed command buffers: the first in one plain command buffer (it discovers the passes),
    /// then the measurement form; the last counter-sampled warm-up must resolve every attached pass, or the session
    /// falls back to one command buffer per pass.
    func warmUp() async throws {
        for round in 0..<Swift.max(1, request.warmups) { try await warmUpRound(round) }
    }

    func warmUpRound(_ round: Int) async throws {
        if round == 0 {
            let first = try await run(isolation: .singleCommandBuffer, sampler: nil)
            passCount = (first.recorder.encodeLog.map(\.pass).filter { $0 >= 0 }.max() ?? -1) + 1
            chooseMode()
            if case .counters(let sampler) = mode { _ = await sampler.clock.calibrated() }
        } else {
            switch mode {
            case .counters(let sampler):
                let result = try await run(isolation: .stageBoundaryCounters, sampler: sampler)
                let resolved = result.recorder.passMilliseconds(result.completions) ?? [:]
                let attached = Set(sampler.attachedPasses)
                if attached.isEmpty || !attached.allSatisfy({ (resolved[$0] ?? 0) > 0 }) { mode = .isolated }
            case .isolated:
                _ = try await run(isolation: .commandBufferPerPass, sampler: nil)
            case .wholeOnly:
                _ = try await run(isolation: .singleCommandBuffer, sampler: nil)
            }
        }
        warmupsRun += 1
    }

    private func chooseMode() {
        if wholeOnly { mode = .wholeOnly; return }
        if request.isolation != .commandBufferPerPass, passCount > 0,
           let sampler = service.makeStageBoundarySampler(passes: passCount, context: context) {
            mode = .counters(sampler)
        } else {
            mode = .isolated
        }
    }

    /// One timed blur. Returns the GPU seconds it consumed (for the budget).
    func sample() async throws -> Double {
        let result: (recorder: GPUCommandRecorder, completions: [GPUCompletion])
        switch mode {
        case .counters(let sampler):
            result = try await run(isolation: .stageBoundaryCounters, sampler: sampler)
        case .isolated:
            result = try await run(isolation: .commandBufferPerPass, sampler: nil)
        case .wholeOnly:
            result = try await run(isolation: .singleCommandBuffer, sampler: nil)
        }
        let total = result.completions.reduce(0) { $0 + $1.milliseconds }
        whole.append(total)
        if let passes = result.recorder.passMilliseconds(result.completions) {
            for (pass, ms) in passes where pass >= 0 && ms.isFinite && ms >= 0 { perPass[pass, default: []].append(ms) }
        }
        return total / 1000
    }

    /// One fused (least-instrumented) blur: one command buffer, no counter attachments.
    func fusedSample() async throws -> Double {
        let result = try await run(isolation: .singleCommandBuffer, sampler: nil)
        let total = result.completions.reduce(0) { $0 + $1.milliseconds }
        fused.append(total)
        return total / 1000
    }

    private func run(isolation: PassIsolation, sampler: MeasureStageBoundarySampler?) async throws
        -> (recorder: GPUCommandRecorder, completions: [GPUCompletion]) {
        try Task.checkCancellation()
        sampler?.reset()
        let recorder = GPUCommandRecorder(context: context, isolation: isolation, label: "timing \(pipeline.variant.rawValue)", sampler: sampler)
        let encoded = try pipeline.encode(context, inputs, trace: nil, recorder: recorder)
        let completions = await recorder.commitAndWait()
        context.recycle(encoded)
        for d in encoded.dispatch where passNames[d.passIndex] == nil { passNames[d.passIndex] = d.name }
        if let error = completions.compactMap(\.error).first { throw GPUError.commandBufferFailed(error) }
        commandBuffersRun += completions.count
        service.afterCommandBuffer?(commandBuffersRun)
        try Task.checkCancellation()
        return (recorder, completions)
    }

    /// The pass's tile label: from the encode's PassDispatch, else the operator's plan ("H", "V", "↓1").
    private func passName(_ pass: Int) -> String {
        if let name = passNames[pass] { return name }
        if let op = BlurRegistry.op(pipeline.blur), let d = op.passPlan(inputs.request).passes.first(where: { $0.id == pass }) { return d.name }
        return "UNNAMED PASS"
    }

    func summary(stop: TimingStopReason, interleaved: Bool, start: TimingService.Environment, end: TimingService.Environment,
                 overhead: Double?) -> TimingSummary {
        let passes: [PassTiming] = perPass.keys.sorted().compactMap { pass in
            guard let values = perPass[pass], let median = MeasureStatistics.median(values) else { return nil }
            return PassTiming(passIndex: pass, passName: passName(pass), medianMilliseconds: median,
                              iqrMilliseconds: MeasureStatistics.iqr(values) ?? 0, samples: values.count)
        }
        return TimingSummary(method: passes.isEmpty && !wholeOnly ? .commandBuffer : method, warmups: warmupsRun, samples: whole.count,
                             medianMilliseconds: MeasureStatistics.median(whole) ?? 0, iqrMilliseconds: MeasureStatistics.iqr(whole) ?? 0,
                             perPass: passes, fusedMedianMilliseconds: MeasureStatistics.median(fused), interleaved: interleaved,
                             thermalAtStart: start.thermal, thermalAtEnd: end.thermal, lowPowerMode: start.lowPower || end.lowPower,
                             overheadMilliseconds: overhead, stopReason: stop)
    }
}
