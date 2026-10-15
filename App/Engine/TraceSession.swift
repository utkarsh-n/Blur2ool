import Foundation
import Observation
import BlurCore

// OWNER: ENGINE (frozen public API, ARCHITECTURE §5.9, §5.12; SPEC §6). The pixel walk.
// While a session is open the Bench renders the TRACED specialization, so the recorded taps and the displayed pixel come
// from one execution (SPEC §6.4 rule 2, JF G-7): `start()` asks the BenchModel for a traced full-resolution render (the
// pipeline's TRACE_PROBE specialization is prepared inside it, off the main actor; meanwhile `isPreparingTracedBuild` is
// true and the Bench keeps the untraced frame). The GPU's records are LIVE; passes without records keep BlurCore's
// reconstruction, COMPUTED and never labelled LIVE (JF M-6). When no GPU pipeline exists for the blur yet, the walk falls
// back to the reconstruction alone and says so (`isCPUOnly`). Steps come from CONTENT-LAYERS' TraceScripter (detached).
// The context card's 9 × 9 (17 × 17 magnified) grid is a blit copy of the real input window around the probe (LIVE), with
// the current pass's weights as bars. `close()` returns the Bench to the untraced build.

@MainActor @Observable
public final class TraceSession {
    public private(set) var record: TraceRecord?
    public private(set) var steps: [TraceStep] = []
    public private(set) var stepIndex: Int = 0
    public private(set) var subStepIndex: Int = 0
    public private(set) var isPlaying: Bool = false
    /// The 9 × 9 (or 17 × 17 Magnify) copy of the probe's neighbourhood for the context card.
    public private(set) var contextGrid: TexelGridSpec?

    // ENGINE additions (public, additive).
    /// True while the traced pipeline compiles and the first traced frame renders (`PREPARING TRACED BUILD`).
    public private(set) var isPreparingTracedBuild = false
    /// True when the walk is BlurCore's reconstruction only (no GPU records for this blur yet): every row is COMPUTED.
    public private(set) var isCPUOnly = false
    /// The traced Run on screen (LIVE GPU records, its probe readout, its shader provenance with `traced = true`).
    public private(set) var run: Run?
    public private(set) var isMagnified = false
    /// Why the walk could not start, when it could not.
    public private(set) var failure: String?

    @ObservationIgnored private weak var bench: BenchModel?
    @ObservationIgnored private var playTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var isOpen = false

    public init() {}
    init(bench: BenchModel) { self.bench = bench }

    public var current: TraceStep? { steps.indices.contains(stepIndex) ? steps[stepIndex] : nil }
    /// The current sub-step (fetch, tap, iteration) of the current step, when it has any.
    public var currentSubStep: TraceSubStep? {
        guard let step = current, step.subSteps.indices.contains(subStepIndex) else { return nil }
        return step.subSteps[subStepIndex]
    }
    /// The walk has reached its last step and sub-step (the primary becomes `Back to Blur2ool`).
    public var isAtEnd: Bool {
        guard let step = current else { return true }
        return stepIndex == steps.count - 1 && subStepIndex >= Swift.max(0, step.subSteps.count - 1)
    }

    public func start() async {
        guard let bench else { return }
        isOpen = true
        failure = nil
        isPreparingTracedBuild = true
        let traced = await bench.beginTrace(self)
        isPreparingTracedBuild = false
        guard isOpen else { return }
        if let traced, traced.trace != nil {
            await load(traced, cpuOnly: false)
        } else {
            await loadReconstruction(bench: bench)
        }
    }

    /// A newer traced Run arrived (the probe moved: Jump, or a change while open): restart the walk on it.
    func receive(_ newer: Run) {
        guard isOpen, newer.trace != nil, newer.id != run?.id else { return }
        if newer.configuration == run?.configuration && newer.trace?.probe == record?.probe { run = newer; return }
        loadTask?.cancel()
        loadTask = Task { [weak self] in await self?.load(newer, cpuOnly: false) }
    }

    private func load(_ traced: Run, cpuOnly: Bool) async {
        guard let bench, let record = traced.trace, let op = BlurRegistry.op(traced.configuration.blur),
              let context = bench.floorContext(slot: .a) else { return }
        let steps = await Task.detached(priority: .userInitiated) { BlurServices.traceScripts.steps(for: record, op: op, context: context) }.value
        guard isOpen, !Task.isCancelled else { return }
        self.run = traced
        self.record = record
        self.steps = steps
        self.isCPUOnly = cpuOnly
        stepIndex = 0
        subStepIndex = 0
        await refreshGrid()
    }

    /// No GPU records (no pipeline for this blur, or Tier 3/S): BlurCore's reconstruction of the probe, COMPUTED.
    private func loadReconstruction(bench: BenchModel) async {
        let config = bench.configuration
        guard let op = BlurRegistry.op(config.blur),
              let canvas = await bench.renderer.specimens.canvas(config.specimen, options: config.specimenOptions, windowSize: config.windowSize) else {
            failure = bench.lastError ?? "NO TRACE FOR THIS BLUR"
            return
        }
        let request = config.operatorRequest, probe = config.probe, pan = config.pan, ev = config.specimenOptions.exposureEV
        let record = await Task.detached(priority: .userInitiated) { () -> TraceRecord in
            let window = canvas.window(pan: pan)
            var input = window.image.roundedToHalf()
            if ev != 0 { input = input.scaled(by: Float(pow(2.0, Double(ev)))).roundedToHalf() }
            var pre = ColourTransform.pre(input, request.settings)
            if ColourTransform.needsPasses(request.settings) { pre = pre.roundedToHalf() }
            return op.traceReconstruction(probe: probe, input: pre, request, auxiliary: window.auxiliary)
        }.value
        guard isOpen, let context = bench.floorContext(slot: .a) else { return }
        let steps = await Task.detached(priority: .userInitiated) { BlurServices.traceScripts.steps(for: record, op: op, context: context) }.value
        guard isOpen else { return }
        self.record = record
        self.steps = steps
        self.isCPUOnly = true
        stepIndex = 0
        subStepIndex = 0
        await refreshGrid()
    }

    // MARK: Navigation (a step never changes the specimen's parameters; it only reveals)

    public func next() {
        guard let step = current else { return }
        if subStepIndex + 1 < step.subSteps.count { subStepIndex += 1 }
        else if stepIndex + 1 < steps.count { stepIndex += 1; subStepIndex = 0 }
        else { pause() }
        gridFollowsStep()
    }
    public func back() {
        if subStepIndex > 0 { subStepIndex -= 1 }
        else if stepIndex > 0 {
            stepIndex -= 1
            subStepIndex = Swift.max(0, (current?.subSteps.count ?? 1) - 1)
        }
        gridFollowsStep()
    }
    public func restart() { pause(); stepIndex = 0; subStepIndex = 0; gridFollowsStep() }
    /// Long press on the primary (SPEC §6.2 item 4): the current pass completes; the walk stands on its last unit.
    public func finishPass() {
        guard let pass = current?.passIndex else { next(); return }
        while stepIndex + 1 < steps.count, steps[stepIndex + 1].passIndex == pass { stepIndex += 1 }
        subStepIndex = Swift.max(0, (current?.subSteps.count ?? 1) - 1)
        gridFollowsStep()
    }
    /// The floor selector (floors ahead are allowed: the walk is not a gate).
    public func jump(to floor: Floor) {
        if let i = steps.firstIndex(where: { $0.floor == floor }) { stepIndex = i; subStepIndex = 0; gridFollowsStep() }
    }
    /// `Play` (inside `All … details`): one sub-step every 250 ms until the end or a pause.
    public func play() {
        guard !isPlaying, !steps.isEmpty else { return }
        if isAtEnd { stepIndex = 0; subStepIndex = 0 }
        isPlaying = true
        playTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled, self.isPlaying else { return }
                if self.isAtEnd { self.pause(); return }
                self.next()
            }
        }
    }
    public func pause() { isPlaying = false; playTask?.cancel(); playTask = nil }
    public func setMagnified(_ on: Bool) {
        guard on != isMagnified else { return }
        isMagnified = on
        Task { await refreshGrid() }
    }
    public func close() {
        pause()
        loadTask?.cancel()
        guard isOpen else { return }
        isOpen = false
        steps = []; record = nil; contextGrid = nil; run = nil
        bench?.endTrace(self)
    }

    // MARK: The context card's grid

    /// Reads the probe's neighbourhood from the real input window (a blit copy, LIVE).
    private func refreshGrid() async {
        guard let bench, let record else { return }
        let size = isMagnified ? 17 : 9
        let n = bench.configuration.windowSize
        let region = PixelRegion.centred(on: record.probe, side: size, inside: .square(n))
        let texels = (try? await bench.renderer.readInputTexels(slot: .a, region: region)) ?? []
        let values: [Double]
        let provenance: Provenance
        if texels.count == size * size {
            values = texels.map { Double(Luma.rec709($0)) }
            provenance = .live
        } else {
            values = Array(repeating: 0, count: size * size)
            provenance = .computed
        }
        contextGrid = TexelGridSpec(size: size, origin: region.origin, channel: .luma, values: values, weights: nil,
                                    highlighted: [record.probe], provenance: provenance)
        gridFollowsStep()
    }

    /// The current pass's weights as bars under each texel, and the current tap's texels highlighted.
    private func gridFollowsStep() {
        guard var grid = contextGrid, let record else { return }
        let passIndex = current?.passIndex ?? 0
        guard let pass = record.passes.first(where: { $0.id == passIndex }) ?? record.passes.first else { return }
        var weights = [Double](repeating: 0, count: grid.size * grid.size)
        var any = false
        for tap in pass.taps {
            for texel in tap.texels {
                let gx = texel.texel.x - grid.origin.x, gy = texel.texel.y - grid.origin.y
                guard gx >= 0, gy >= 0, gx < grid.size, gy < grid.size else { continue }
                weights[gy * grid.size + gx] += tap.weight * texel.fraction
                any = true
            }
        }
        grid.weights = any ? weights : nil
        var highlighted = [record.probe]
        if let tapIndex = currentSubStep?.tapIndex, pass.taps.indices.contains(tapIndex) {
            highlighted += pass.taps[tapIndex].texels.map(\.texel)
        }
        grid.highlighted = highlighted
        contextGrid = grid
    }
}
