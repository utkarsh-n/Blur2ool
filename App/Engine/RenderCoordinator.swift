import Foundation
import Metal
import BlurCore
import BlurGPU

// OWNER: ENGINE (frozen public API, ARCHITECTURE §5.9 / AppContract/Engine/EngineAPI.swift). Owns ALL GPU work of the app.
// Textures never leave it; it returns Runs (Sendable values).
//
// How a render goes (ARCHITECTURE §4.1, §5.8, §5.9; SPEC §4.1.6):
// 1. Canvas. The specimen canvas (window + 256-px margin, always at 0 EV) comes from SpecimenStore (generated off the main
//    actor), is converted to fp16 bytes in a detached task (`HalfImageData`) and uploaded once per canvas.
// 2. First frame. The very first time a slot gets a window, the window pass is committed on its own and the display is
//    notified, so the housing shows the sharp INPUT (a real image) while the blur pipeline is still being prepared.
// 3. Window pass. A blit at 0 EV, otherwise `b2_common_window_fs` × 2^EV (exposure at render time); re-encoded only when
//    the canvas, pan, exposure or size changed, inside the render's own recorder.
// 4. Prepare. Pipelines are specialised asynchronously (`prepare`), per instance, when the variant, edge mode or size
//    changes; the previous Run stays on screen meanwhile (the caller shows RENDERING…). `encode` never compiles.
// 5. Instances (review fix E-11). One display instance per (slot, blur, variant) for full renders and a separate one for
//    previews (so a preview never overwrites the full-resolution intermediates the periscope, Algorithm floor and Trace
//    read), and separate timing, parity and strip instances. Transient textures are recycled when that same instance
//    encodes again (`GPUContext.recycle`, review fix E-27).
// 6. Preview. `op.previewRequest` at ½ or ¼ on the frozen 2 × 2-mean input (`encodeDownsample2x`, once or twice); a blur
//    without an honest preview renders at full resolution. Previews are never timed, traced or parity-checked and carry
//    no probe readout.
// 7. Encode. `encodeFullBlur` (colour pre-pass → pipeline → post-pass), then the probe texel, the input texel and one
//    texel per pass intermediate read back INSIDE the same recorder (review fix E-26), plus 9 × 9 neighbourhoods per pass
//    for traced renders. Full renders whose MODELED time exceeds FetchBudget.bandMilliseconds (50 ms) get one command
//    buffer per pass, so the compositor keeps getting GPU time (requests/ENGINE.md item 2: row bands need a region API).
// 8. Run. Kernel summary (COMPUTED, off the main actor), dispatch, MODELED cost, shader provenance, LIVE probe readout,
//    and for traced renders a TraceRecord whose GPU passes are LIVE records merged with BlurCore's reconstruction.
// Timing (budgeted, cancellable, blur passes only on a pre-passed input), in-app parity (after timing, `.utility`,
// `ReferenceOptions.forDevice`, report-only until the sub-texel rule is measured), fingerprint strips, ON THIS PHONE
// shapes, device probes and the hero-dozen pre-warm also live here. Compare's Implementation axis can show the CPU
// reference (BlurCore, Double) and the Apple axis an in-process Apple twin, both as slot outputs.

@MainActor
public final class RenderCoordinator {
    public let gpu: GPUContext
    public let specimens: SpecimenStore
    /// Bumped whenever a display texture changes; the PresentRenderer redraws on change.
    public private(set) var displayGeneration: UInt64 = 0
    public var onDisplayChanged: (@MainActor () -> Void)?
    /// The engraving every MEASURED value carries (AppEnvironment installs the device's; this default never ships).
    public var deviceStamp: @MainActor () -> DeviceStamp = {
        DeviceStamp(deviceModel: "Unknown device", gpuName: "", gpuFamily: "", osVersion: "", osBuild: "", isSimulator: false,
                    date: Date(), thermal: .unknown, lowPowerMode: false)
    }
    /// This phone's device-probe results (the sub-texel rule for in-app parity); AppEnvironment wires the Run log.
    public var deviceProbes: @MainActor () -> [DeviceProbeResult] = { [] }
    /// `systemUptime` at launch: timing Runs note how long after launch they ran (SPEC §2: never in the first 10 s).
    public var launchUptime: Double = ProcessInfo.processInfo.systemUptime

    /// Compare › Implementation: B is the CPU reference of A's variant (`cpu-reference:<variant>`).
    public static let cpuReferencePrefix = "cpu-reference:"
    /// Compare › Apple: B is an Apple twin run in-process (`apple:<AppleTwinSpec.id>`).
    public static let appleTwinPrefix = "apple:"
    public static func cpuReferenceVariant(of variant: VariantID) -> VariantID { VariantID(rawValue: cpuReferencePrefix + variant.rawValue) }
    public static func appleTwinVariant(_ twinID: String) -> VariantID { VariantID(rawValue: appleTwinPrefix + twinID) }

    // MARK: State

    private struct CanvasTexture {
        let key: SpecimenStore.Key
        let texture: any MTLTexture
        let margin: Int
        let backdrop: SIMD4<Float>
        let hasAuxiliary: Bool
    }
    private struct WindowKey: Hashable {
        var canvas: SpecimenStore.Key
        var pan: PixelPoint
        var exposureEV: Int
        var size: Int
    }
    /// One display encode target: its output, the previous encode (for intermediates and recycling) and preview inputs.
    private final class Target {
        var output: (any MTLTexture)?
        var outputSpec: TextureSpec?
        var encoded: EncodedBlur?
        var previewInputs: [(texture: any MTLTexture, spec: TextureSpec)] = []
    }
    private final class SlotState {
        var windowKey: WindowKey?
        var window: (any MTLTexture)?
        var windowSpec: TextureSpec?
        var auxiliary = GPUAuxiliaryTextures()
        var auxiliaryKey: WindowKey?
        let full = Target()
        let preview = Target()
        /// CPU-reference or Apple-twin output (Compare B).
        let external = Target()
        /// Which target is on screen.
        var newest: Target?
        var pipelines: [String: any GPUBlurPipeline] = [:]
        var prepared: [String: String] = [:]
        var newestGeneration: UInt64 = 0
        var lastFullConfiguration: RenderConfiguration?
        var cpuReferenceMilliseconds: Double?
    }
    /// Timing, parity and strip work each own their window, pre-pass, output and pipeline instances.
    private final class Workspace {
        var window: (any MTLTexture)?
        var windowSpec: TextureSpec?
        var pre: (any MTLTexture)?
        var preSpec: TextureSpec?
        var output: (any MTLTexture)?
        var outputSpec: TextureSpec?
        var pipelines: [String: any GPUBlurPipeline] = [:]
        var prepared: [String: String] = [:]
        var encoded: EncodedBlur?
    }

    private var slots: [RunSlot: SlotState] = [:]
    private var canvasTextures: [SpecimenStore.Key: CanvasTexture] = [:]
    private var canvasRecency: [SpecimenStore.Key] = []
    private var commonPrepared = false
    private var timingWorkspaces: [String: Workspace] = [:]
    private var parityWorkspace = Workspace()
    private var stripWorkspace = Workspace()
    /// Bumped by `cancelMeasurements`; timing and parity check it between command buffers.
    private var measurementEpoch: UInt64 = 0

    public init(gpu: GPUContext, specimens: SpecimenStore) { self.gpu = gpu; self.specimens = specimens }

    private func slot(_ s: RunSlot) -> SlotState {
        if let existing = slots[s] { return existing }
        let created = SlotState(); slots[s] = created; return created
    }

    // MARK: Canvas, window and auxiliary inputs

    private func canvasTexture(for configuration: RenderConfiguration) async throws -> CanvasTexture {
        let key = SpecimenStore.key(configuration.specimen, options: configuration.specimenOptions, windowSize: configuration.windowSize)
        if let cached = canvasTextures[key] { touchCanvas(key); return cached }
        guard let canvas = await specimens.canvas(configuration.specimen, options: configuration.specimenOptions,
                                                  windowSize: configuration.windowSize) else {
            throw GPUError.unsupported("NO TEST IMAGE \(configuration.specimen.rawValue.uppercased())")
        }
        if let raced = canvasTextures[key] { return raced }
        let image = canvas.image
        let half = await Task.detached(priority: .userInitiated) { HalfImageData(image) }.value
        let texture = try await gpu.upload(half, roles: [.read])
        let aux = canvas.auxiliary
        let entry = CanvasTexture(key: key, texture: texture, margin: canvas.margin, backdrop: canvas.backdrop,
                                  hasAuxiliary: aux.depth != nil || aux.velocity != nil || aux.guide != nil || aux.mask != nil
                                      || !(aux.subFrames ?? []).isEmpty)
        canvasTextures[key] = entry
        touchCanvas(key)
        // A canvas texture is (N + 512)² × 8 B (15.8 MB at N = 894): keep every canvas a slot is showing, plus the two most
        // recently used others (fingerprint strips use three small ones and must not evict the Bench's).
        let inUse = Set(slots.values.compactMap { $0.windowKey?.canvas }).union([key])
        var spare = canvasRecency.filter { !inUse.contains($0) }
        while spare.count > 2 {
            let oldest = spare.removeFirst()
            canvasRecency.removeAll { $0 == oldest }
            canvasTextures[oldest] = nil
        }
        return entry
    }
    private func touchCanvas(_ key: SpecimenStore.Key) { canvasRecency.removeAll { $0 == key }; canvasRecency.append(key) }

    private func windowKey(_ configuration: RenderConfiguration) -> WindowKey {
        WindowKey(canvas: SpecimenStore.key(configuration.specimen, options: configuration.specimenOptions, windowSize: configuration.windowSize),
                  pan: configuration.pan, exposureEV: configuration.specimenOptions.exposureEV, size: configuration.windowSize)
    }

    /// Encodes the N × N window (pan, × 2^EV) into `destination` through `recorder`.
    private func encodeWindow(_ canvas: CanvasTexture, _ configuration: RenderConfiguration, into destination: any MTLTexture,
                              recorder: GPUCommandRecorder) throws {
        let m = canvas.margin
        let pan = PixelPoint(x: Swift.min(Swift.max(configuration.pan.x, -m), m), y: Swift.min(Swift.max(configuration.pan.y, -m), m))
        try gpu.encodeWindowCopy(canvas: canvas.texture, margin: m, pan: pan, size: configuration.windowSize,
                                 exposureEV: configuration.specimenOptions.exposureEV, destination: destination, recorder: recorder)
    }

    private func windowTexture(_ state: SlotState, size n: Int) throws -> any MTLTexture {
        let spec = TextureSpec(width: n, height: n, roles: [.read, .renderTarget])
        if let w = state.window, state.windowSpec == spec { return w }
        if let old = state.window, let oldSpec = state.windowSpec { gpu.recycle(old, spec: oldSpec) }
        let w = try gpu.texture(spec)
        state.window = w; state.windowSpec = spec; state.windowKey = nil
        return w
    }

    /// Uploads the window crop of the canvas's auxiliary buffers (depth, velocity, guide, mask, sub-frames) as
    /// window-sized rgba16Float textures: scalars in .r, velocity in .rg (a = 1). Only for specimens that carry them.
    private func auxiliaryTextures(_ canvasTexture: CanvasTexture, _ configuration: RenderConfiguration,
                                   state: SlotState) async throws -> GPUAuxiliaryTextures {
        let key = windowKey(configuration)
        let seed = configuration.specimenOptions.seed ?? 1
        guard canvasTexture.hasAuxiliary else { return GPUAuxiliaryTextures(noiseSeed: seed) }
        if state.auxiliaryKey == key { return state.auxiliary }
        guard let canvas = await specimens.canvas(configuration.specimen, options: configuration.specimenOptions,
                                                  windowSize: configuration.windowSize) else { return GPUAuxiliaryTextures(noiseSeed: seed) }
        let pan = configuration.pan
        let planes = await Task.detached(priority: .userInitiated) { () -> RenderCoordinatorAuxiliaryPlanes in
            RenderCoordinatorAuxiliaryPlanes(canvas.window(pan: pan).auxiliary)
        }.value
        func upload(_ plane: HalfImageData?) async throws -> (any MTLTexture)? {
            guard let plane else { return nil }
            return try await gpu.upload(plane, roles: [.read])
        }
        var aux = GPUAuxiliaryTextures(noiseSeed: seed)
        aux.depth = try await upload(planes.depth)
        aux.velocity = try await upload(planes.velocity)
        aux.guide = try await upload(planes.guide)
        aux.mask = try await upload(planes.mask)
        for frame in planes.subFrames { if let t = try await upload(frame) { aux.subFrames.append(t) } }
        state.auxiliary = aux
        state.auxiliaryKey = key
        return aux
    }

    private func ensureCommonPipelines() async throws {
        guard !commonPrepared else { return }
        try await gpu.prepareCommonPipelines()
        commonPrepared = true
    }

    /// The factory that will run `request`: the resolved variant's, or (while a family area has not registered it yet)
    /// the entry's default variant, with the reason stated.
    private func resolveFactory(for op: any BlurOperator, blur: BlurID, request: OperatorRequest) throws
        -> (factory: GPUPipelineFactory, resolution: VariantResolution, request: OperatorRequest) {
        let resolved = op.resolveVariant(request)
        if let f = GPUPipelineRegistry.factory(blur, resolved.variant) { return (f, resolved, request) }
        let fallback = op.entry.defaultVariant
        guard fallback != resolved.variant, let f = GPUPipelineRegistry.factory(blur, fallback) else {
            throw GPUError.unsupported("NO GPU PIPELINE FOR \(op.entry.displayName.uppercased()) YET")
        }
        var r = request
        r.variant = fallback
        let name = op.entry.variant(resolved.variant)?.displayName ?? resolved.variant.rawValue
        let using = op.entry.variant(fallback)?.displayName ?? fallback.rawValue
        return (f, VariantResolution(variant: fallback, reason: "\(name.uppercased()) NOT BUILT YET · USING \(using.uppercased())"), r)
    }

    private func pipeline(_ factory: GPUPipelineFactory, key: String, in table: inout [String: any GPUBlurPipeline]) -> any GPUBlurPipeline {
        if let existing = table[key] { return existing }
        let made = factory.make()
        table[key] = made
        return made
    }

    private func outputTexture(_ target: Target, width: Int, height: Int, computeWrite: Bool) throws -> any MTLTexture {
        let roles: TextureRole = computeWrite ? [.read, .renderTarget, .computeWrite] : [.read, .renderTarget]
        let spec = TextureSpec(width: width, height: height, roles: roles)
        if let t = target.output, target.outputSpec == spec { return t }
        if let old = target.output, let oldSpec = target.outputSpec { gpu.recycle(old, spec: oldSpec) }
        let t = try gpu.texture(spec)
        target.output = t; target.outputSpec = spec
        return t
    }

    // MARK: Render

    /// Encodes, commits and awaits one render; the probe texel is read back inside the same recorder (`encodeReadTexels`).
    /// Previews (`.half`, `.quarter`) render `op.previewRequest` from the 2 × 2-mean input and are never timed, traced or
    /// parity-checked. Throws `GPUError.notPrepared` (the previous Run stays) until `prepare` finished. Returns nil when the
    /// result was superseded (an equal-or-newer generation was already published).
    /// Pipeline instances: one per (slot, blur, variant) for display, separate ones for timing and parity, so later
    /// encodes never overwrite the intermediates the periscope, Algorithm floor and Trace show (review fix E-11).
    public func render(_ request: RenderRequest) async throws -> Run? {
        let state = slot(request.slot)
        guard request.generation >= state.newestGeneration else { return nil }
        let configuration = request.configuration
        guard let op = BlurRegistry.op(configuration.blur) else { throw GPUError.unsupported("NO OPERATOR \(configuration.blur.rawValue)") }
        if configuration.variant.rawValue.hasPrefix(Self.cpuReferencePrefix) { return try await renderCPUReference(request, op: op) }
        if configuration.variant.rawValue.hasPrefix(Self.appleTwinPrefix) { return try await renderAppleTwin(request, op: op) }

        let canvas = try await canvasTexture(for: configuration)
        try await ensureCommonPipelines()
        let n = configuration.windowSize
        let key = windowKey(configuration)
        let window = try windowTexture(state, size: n)
        var windowPending = state.windowKey != key
        if windowPending && state.newest == nil {
            // First frame (review fix E-25): the sharp INPUT goes on screen as soon as the canvas exists.
            let first = GPUCommandRecorder(context: gpu, label: "window \(request.slot.rawValue) first frame")
            try encodeWindow(canvas, configuration, into: window, recorder: first)
            let done = await first.commitAndWait()
            if let error = done.compactMap(\.error).first { throw GPUError.commandBufferFailed(error) }
            state.windowKey = key
            windowPending = false
            displayGeneration += 1
            onDisplayChanged?()
        }
        let auxiliary = try await auxiliaryTextures(canvas, configuration, state: state)

        // The request actually rendered (preview scale, resolved or fallback variant).
        var quality = request.quality
        var operatorRequest = configuration.operatorRequest
        var probe = configuration.probe
        if quality != .full {
            if let preview = op.previewRequest(operatorRequest, scale: quality.scale) {
                operatorRequest = preview
                probe = probe.previewMapped(quality.scale)
            } else {
                quality = .full
            }
        }
        let (factory, resolution, runRequest) = try resolveFactory(for: op, blur: configuration.blur, request: operatorRequest)
        operatorRequest = runRequest
        let target = quality == .full ? state.full : state.preview
        let instanceKey = "\(factory.blur.rawValue)|\(factory.variant.rawValue)|\(quality == .full ? "full" : "preview")"
        let pipeline = self.pipeline(factory, key: instanceKey, in: &state.pipelines)
        let signature = "\(operatorRequest.settings.edgeMode.rawValue)|\(operatorRequest.size.width)x\(operatorRequest.size.height)"
        if state.prepared[instanceKey] != signature {
            try await pipeline.prepare(gpu, request: operatorRequest)
            state.prepared[instanceKey] = signature
        }
        // A newer request arrived while preparing: let it render instead (latest wins).
        guard request.generation >= state.newestGeneration else { return nil }

        let plan = op.passPlan(operatorRequest)
        let modeledMilliseconds = plan.fetchesPerFrame(operatorRequest.size) / FetchBudget.modeledFetchesPerSecond * 1000
        let isolation: PassIsolation = quality == .full && modeledMilliseconds > FetchBudget.bandMilliseconds ? .commandBufferPerPass : .singleCommandBuffer
        let recorder = GPUCommandRecorder(context: gpu, isolation: isolation,
                                          label: "display \(request.slot.rawValue) g\(request.generation) \(quality.rawValue)")
        if windowPending { try encodeWindow(canvas, configuration, into: window, recorder: recorder) }

        // Preview input: the frozen 2 × 2 mean of the window, once (½) or twice (¼).
        var source: any MTLTexture = window
        if quality != .full {
            let steps = quality == .quarter ? 2 : 1
            var size = n
            for index in 0..<steps {
                size = Swift.max(1, size / 2)
                let spec = TextureSpec(width: size, height: size, roles: [.read, .renderTarget])
                while target.previewInputs.count <= index { target.previewInputs.append((try gpu.texture(spec), spec)) }
                if target.previewInputs[index].spec != spec {
                    gpu.recycle(target.previewInputs[index].texture, spec: target.previewInputs[index].spec)
                    target.previewInputs[index] = (try gpu.texture(spec), spec)
                }
                let destination = target.previewInputs[index].texture
                try gpu.encodeDownsample2x(source: source, destination: destination, recorder: recorder)
                source = destination
            }
        }
        let output = try outputTexture(target, width: operatorRequest.size.width, height: operatorRequest.size.height,
                                       computeWrite: pipeline.writesDestinationFromCompute)
        if let previous = target.encoded { gpu.recycle(previous); target.encoded = nil }
        let trace = request.traced && quality == .full ? TraceRequest.sized(probe: probe, plan: plan) : nil
        let encoded = try gpu.encodeFullBlur(pipeline, window: source, output: output, request: operatorRequest, auxiliary: auxiliary,
                                             quality: quality, trace: trace, recorder: recorder)
        // Readbacks inside the same recorder (review fix E-26).
        let w = operatorRequest.size.width, h = operatorRequest.size.height
        let inside = PixelPoint(x: Swift.min(Swift.max(probe.x, 0), w - 1), y: Swift.min(Swift.max(probe.y, 0), h - 1))
        let one = PixelRegion(origin: inside, size: .square(1))
        let outputRead = try gpu.encodeReadTexels(output, region: one, recorder: recorder)
        var inputRead: PendingReadback?
        var passReads: [PendingReadback] = []
        var neighbourhoods: [(input: PendingReadback?, output: PendingReadback?)] = []
        if quality == .full {
            inputRead = try gpu.encodeReadTexels(window, region: one, recorder: recorder)
            for texture in encoded.intermediates {
                passReads.append(try gpu.encodeReadTexels(texture, region: PixelRegion(origin: mapped(inside, from: n, to: texture), size: .square(1)),
                                                          recorder: recorder))
            }
            if trace != nil {
                let pipelineInput = ColourTransform.needsPasses(operatorRequest.settings)
                    ? (encoded.transientTextures.first?.texture ?? source) : source
                var previous: any MTLTexture = pipelineInput
                for texture in encoded.intermediates.prefix(plan.passes.count) {
                    let inRegion = PixelRegion.centred(on: mapped(inside, from: n, to: previous), side: 9,
                                                       inside: ImageSize(width: previous.width, height: previous.height))
                    let outRegion = PixelRegion.centred(on: mapped(inside, from: n, to: texture), side: 9,
                                                        inside: ImageSize(width: texture.width, height: texture.height))
                    neighbourhoods.append((try gpu.encodeReadTexels(previous, region: inRegion, recorder: recorder),
                                           try gpu.encodeReadTexels(texture, region: outRegion, recorder: recorder)))
                    previous = texture
                }
            }
        }
        // The kernel summary is COMPUTED off the main actor while the GPU works (psf can be large: σ 64 is 385² taps).
        let summaryRequest = operatorRequest, summaryProbe = probe, full = quality == .full
        let summaryTask = Task.detached(priority: .userInitiated) { () -> (Double?, Double?, Int?) in
            guard full else { return (op.sigma(summaryRequest), nil, nil) }
            let marginal = op.psf(at: summaryProbe, summaryRequest, content: nil)?.kernel.marginalX
            return (op.sigma(summaryRequest), marginal?.excessKurtosis, marginal?.tapCount)
        }
        let completions = await recorder.commitAndWait()
        let summary = await summaryTask.value
        if let error = completions.compactMap(\.error).first { throw GPUError.commandBufferFailed(error) }
        target.encoded = encoded
        state.windowKey = key
        state.newest = target
        state.newestGeneration = Swift.max(state.newestGeneration, request.generation)
        if quality == .full { state.lastFullConfiguration = configuration }
        displayGeneration += 1
        onDisplayChanged?()

        let stamp = deviceStamp()
        let kernel = KernelSummary(sigmaEff: summary.0, excessKurtosis: summary.1, fetchesPerPixel: plan.fetchesPerPixel,
                                   tapsPerAxis: summary.2, passNames: plan.passes.map(\.name),
                                   uploadedWeights: encoded.uploadedWeights, uploadedOffsets: encoded.uploadedOffsets)
        let cost = BlurServices.costModel.cost(for: plan, size: operatorRequest.size, intermediate: operatorRequest.settings.intermediate,
                                               bandwidth: .a17ProLeak)
        let shader = ShaderProvenance(combinedSHA256: gpu.manifest.combinedSHA256, fileName: pipeline.shaderFile,
                                      fileSHA256: gpu.manifest.files[pipeline.shaderFile] ?? "", functionNames: pipeline.functionNames,
                                      mathMode: gpu.mathMode, languageVersion: gpu.manifest.languageVersion, traced: trace != nil)
        var readout: ProbeReadout?
        if quality == .full, let inputRead {
            readout = ProbeReadout(probe: configuration.probe, input: SIMD4<Double>(inputRead.decode()[0]),
                                   output: SIMD4<Double>(outputRead.decode()[0]),
                                   perPass: passReads.map { SIMD4<Double>($0.decode()[0]) })
        }
        var record: TraceRecord?
        if let trace, let buffer = encoded.traceBuffer, let readout {
            record = await traceRecord(op: op, configuration: configuration, request: operatorRequest, plan: plan, trace: trace,
                                       buffer: buffer, encoded: encoded, readout: readout,
                                       neighbourhoods: neighbourhoods.map { ($0.input?.decode(), $0.output?.decode()) })
        }
        var notes: [String] = []
        if isolation == .commandBufferPerPass { notes.append("one command buffer per pass (modeled > 50 ms)") }
        return Run(kind: request.kind, generation: request.generation, slot: request.slot, configuration: configuration,
                   resolvedVariant: resolution, quality: quality, device: stamp, gpu: gpu.facts, kernel: kernel,
                   dispatch: encoded.dispatch, timing: nil, cost: cost, parity: nil, probe: readout, shape: nil, shader: shader,
                   trace: record, calibration: nil, deviceProbe: nil, notes: notes)
    }

    /// A full-resolution window pixel mapped into a texture of another size (pass intermediates, pyramid levels).
    private func mapped(_ p: PixelPoint, from n: Int, to texture: any MTLTexture) -> PixelPoint {
        guard n > 0 else { return p }
        return PixelPoint(x: Swift.min(texture.width - 1, p.x * texture.width / Swift.max(n, 1)),
                          y: Swift.min(texture.height - 1, p.y * texture.height / Swift.max(n, 1)))
    }

    // MARK: Trace records (SPEC §6.4: GPU records are LIVE; reconstructions are COMPUTED)

    private func traceRecord(op: any BlurOperator, configuration: RenderConfiguration, request: OperatorRequest, plan: PassPlan,
                             trace: TraceRequest, buffer: any MTLBuffer, encoded: EncodedBlur, readout: ProbeReadout,
                             neighbourhoods: [([SIMD4<Float>]?, [SIMD4<Float>]?)]) async -> TraceRecord? {
        guard let canvas = await specimens.canvas(configuration.specimen, options: configuration.specimenOptions,
                                                  windowSize: configuration.windowSize) else { return nil }
        let blocks = TraceLayout.decode(buffer, passes: encoded.tracedPassIndices.count, capacity: encoded.traceCapacity)
        let gpuPasses: [RenderCoordinatorTracedPass] = zip(encoded.tracedPassIndices, blocks).map { index, block in
            RenderCoordinatorTracedPass(passIndex: index, pixel: PixelPoint(x: Int(block.header.probe.x), y: Int(block.header.probe.y)),
                                        overflow: Int(block.header.overflow),
                                        taps: block.taps.map { RenderCoordinatorTracedTap($0) })
        }
        let pan = configuration.pan, ev = configuration.specimenOptions.exposureEV, probe = configuration.probe
        let gpuOutput = readout.output
        return await Task.detached(priority: .userInitiated) { () -> TraceRecord in
            let window = canvas.window(pan: pan)
            var input = window.image.roundedToHalf()
            if ev != 0 { input = input.scaled(by: Float(pow(2.0, Double(ev)))).roundedToHalf() }
            var pre = ColourTransform.pre(input, request.settings)
            if ColourTransform.needsPasses(request.settings) { pre = pre.roundedToHalf() }
            let reconstruction = op.traceReconstruction(probe: probe, input: pre, request, auxiliary: window.auxiliary)
            return RenderCoordinator.merge(reconstruction, gpu: gpuPasses, plan: plan, gpuOutput: gpuOutput, neighbourhoods: neighbourhoods)
        }.value
    }

    /// GPU records replace the reconstruction's taps for every traced pass (source `.gpuRecord`, LIVE); the reconstruction's
    /// requested and quantized bilinear fractions and texel lists are kept beside them where the tap order matches.
    nonisolated static func merge(_ reconstruction: TraceRecord, gpu: [RenderCoordinatorTracedPass], plan: PassPlan,
                                  gpuOutput: SIMD4<Double>, neighbourhoods: [([SIMD4<Float>]?, [SIMD4<Float>]?)]) -> TraceRecord {
        var record = reconstruction
        var passes: [TracePass] = []
        for (index, descriptor) in plan.passes.enumerated() {
            let cpu = reconstruction.passes.first { $0.id == descriptor.id }
            let hood = index < neighbourhoods.count ? neighbourhoods[index] : (nil, nil)
            guard let traced = gpu.first(where: { $0.passIndex == descriptor.id }) else {
                if var cpu { cpu.neighbourhoodIn = cpu.neighbourhoodIn ?? hood.0; cpu.neighbourhoodOut = cpu.neighbourhoodOut ?? hood.1; passes.append(cpu) }
                continue
            }
            let fetches = traced.taps.filter { $0.flags != 2 }
            let final = traced.taps.last { $0.flags == 2 }
            let centre = traced.pixel.centre
            let taps: [TraceTap] = fetches.enumerated().map { i, tap in
                let twin = cpu.flatMap { i < $0.taps.count ? $0.taps[i] : nil }
                let position = SIMD2<Double>(tap.position)
                let sameSpot = twin.map { abs($0.position.x - position.x) < 1e-3 && abs($0.position.y - position.y) < 1e-3 } ?? false
                let fetched = SIMD4<Double>(tap.fetched)
                var extras = sameSpot ? (twin?.extras ?? [:]) : [:]
                for (k, v) in zip(["extra0", "extra1", "extra2", "extra3"], [tap.extra.x, tap.extra.y, tap.extra.z, tap.extra.w]) where v != 0 {
                    extras[k] = Double(v)
                }
                return TraceTap(id: i, position: position, offset: position - centre,
                                texels: sameSpot ? (twin?.texels ?? RenderCoordinator.texels(at: position)) : RenderCoordinator.texels(at: position),
                                requestedFraction: sameSpot ? twin?.requestedFraction : nil,
                                quantizedFraction: sameSpot ? twin?.quantizedFraction : nil,
                                weight: Double(tap.weight), fetched: fetched, contribution: fetched * Double(tap.weight),
                                runningSum: SIMD4<Double>(tap.runningSum), dropped: tap.flags == 1, extras: extras)
            }
            passes.append(TracePass(id: descriptor.id, descriptor: descriptor, source: .gpuRecord, pixel: traced.pixel, taps: taps,
                                    truncatedTapCount: traced.overflow,
                                    outputAtProbe: final.map { SIMD4<Double>($0.runningSum) } ?? (cpu?.outputAtProbe ?? .zero),
                                    neighbourhoodIn: hood.0 ?? cpu?.neighbourhoodIn, neighbourhoodOut: hood.1 ?? cpu?.neighbourhoodOut))
        }
        record.passes = passes
        record.gpuOutput = gpuOutput
        let cpu = reconstruction.cpuReference
        record.differenceULP16 = (0..<4).map { ch -> Double in
            let ulp = Double(HalfFloat.ulp(Float(Swift.max(abs(cpu[ch]), 1.0 / 16384))))
            return abs(gpuOutput[ch] - cpu[ch]) / ulp
        }.max()
        return record
    }

    /// The texels a sample at `position` (texel coordinates, centres at i + 0.5) blends, with bilinear fractions.
    nonisolated static func texels(at position: SIMD2<Double>) -> [TexelContribution] {
        let u = position.x - 0.5, v = position.y - 0.5
        let x0 = Int(u.rounded(.down)), y0 = Int(v.rounded(.down))
        let fx = u - Double(x0), fy = v - Double(y0)
        let candidates = [(x0, y0, (1 - fx) * (1 - fy)), (x0 + 1, y0, fx * (1 - fy)), (x0, y0 + 1, (1 - fx) * fy), (x0 + 1, y0 + 1, fx * fy)]
        return candidates.filter { $0.2 > 1e-9 }.map { TexelContribution(texel: PixelPoint(x: $0.0, y: $0.1), fraction: $0.2) }
    }

    // MARK: Compare › Implementation (CPU reference) and Apple (in-process twin) outputs

    private func renderCPUReference(_ request: RenderRequest, op: any BlurOperator) async throws -> Run? {
        let state = slot(request.slot)
        var configuration = request.configuration
        let realVariant = VariantID(rawValue: String(configuration.variant.rawValue.dropFirst(Self.cpuReferencePrefix.count)))
        configuration.variant = realVariant
        guard let canvas = await specimens.canvas(configuration.specimen, options: configuration.specimenOptions,
                                                  windowSize: configuration.windowSize) else { throw GPUError.unsupported("NO TEST IMAGE") }
        let options = ReferenceOptions.forDevice(deviceProbes()) ?? ReferenceOptions(emulateHalfStorage: true, subTexelBits: nil)
        let operatorRequest = configuration.operatorRequest, pan = configuration.pan, ev = configuration.specimenOptions.exposureEV
        let started = ProcessInfo.processInfo.systemUptime
        let output = try await Task.detached(priority: .userInitiated) { () -> ImageBuffer in
            let window = canvas.window(pan: pan)
            return try BlurReference.run(op, input: window.image, operatorRequest, auxiliary: window.auxiliary, options: options,
                                         exposureEV: ev).output
        }.value
        let milliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1000
        guard request.generation >= state.newestGeneration else { return nil }
        let half = await Task.detached(priority: .userInitiated) { HalfImageData(output) }.value
        let uploaded = try await gpu.upload(half, roles: [.read, .renderTarget])
        if let old = state.external.output, let oldSpec = state.external.outputSpec { gpu.recycle(old, spec: oldSpec) }
        state.external.output = uploaded
        state.external.outputSpec = TextureSpec(width: output.width, height: output.height, roles: [.read, .renderTarget])
        state.newest = state.external
        state.newestGeneration = Swift.max(state.newestGeneration, request.generation)
        state.cpuReferenceMilliseconds = milliseconds
        displayGeneration += 1
        onDisplayChanged?()
        let probe = configuration.probe
        let plan = op.passPlan(operatorRequest)
        let inputValue = canvas.image[Swift.min(canvas.image.width - 1, canvas.margin + pan.x + probe.x),
                                      Swift.min(canvas.image.height - 1, canvas.margin + pan.y + probe.y)] * Float(pow(2.0, Double(ev)))
        let readout = ProbeReadout(probe: probe, input: SIMD4<Double>(inputValue),
                                   output: SIMD4<Double>(output[Swift.min(probe.x, output.width - 1), Swift.min(probe.y, output.height - 1)]))
        return Run(kind: request.kind, generation: request.generation, slot: request.slot, configuration: request.configuration,
                   resolvedVariant: VariantResolution(variant: request.configuration.variant, reason: "CPU REFERENCE · BLURCORE (DOUBLE)"),
                   quality: .full, device: deviceStamp(), gpu: nil,
                   kernel: KernelSummary(sigmaEff: op.sigma(operatorRequest), excessKurtosis: nil, fetchesPerPixel: plan.fetchesPerPixel,
                                         tapsPerAxis: nil, passNames: plan.passes.map(\.name)),
                   dispatch: [], timing: nil, cost: nil, parity: nil, probe: readout, shape: nil, shader: nil, trace: nil,
                   calibration: nil, deviceProbe: nil,
                   notes: ["cpuMilliseconds=\(NumberStyle.decimals(1).text(milliseconds))"])
    }

    private func renderAppleTwin(_ request: RenderRequest, op: any BlurOperator) async throws -> Run? {
        let state = slot(request.slot)
        let configuration = request.configuration
        let twinID = String(configuration.variant.rawValue.dropFirst(Self.appleTwinPrefix.count))
        guard let twin = op.entry.appleTwins.first(where: { $0.id == twinID }), let subject = twin.subject,
              let runner = GPUServices.appleTwins, runner.supports(subject) else {
            throw GPUError.unsupported("\(twinID.uppercased()) DOES NOT RUN ON THIS PHONE YET")
        }
        let canvas = try await canvasTexture(for: configuration)
        try await ensureCommonPipelines()
        let window = try windowTexture(state, size: configuration.windowSize)
        let key = windowKey(configuration)
        if state.windowKey != key {
            let recorder = GPUCommandRecorder(context: gpu, label: "window \(request.slot.rawValue) twin")
            try encodeWindow(canvas, configuration, into: window, recorder: recorder)
            _ = await recorder.commitAndWait()
            state.windowKey = key
        }
        let n = configuration.windowSize
        let output = try outputTexture(state.external, width: n, height: n, computeWrite: true)
        let parameter = configuration.parameters.double(op.entry.primary) ?? 0
        try await runner.run(subject, parameter: parameter, input: window, output: output, context: gpu)
        guard request.generation >= state.newestGeneration else { return nil }
        state.newest = state.external
        state.newestGeneration = Swift.max(state.newestGeneration, request.generation)
        displayGeneration += 1
        onDisplayChanged?()
        let probe = PixelPoint(x: Swift.min(configuration.probe.x, n - 1), y: Swift.min(configuration.probe.y, n - 1))
        let texel = try await gpu.readTexels(output, region: PixelRegion(origin: probe, size: .square(1)))
        let input = try await gpu.readTexels(window, region: PixelRegion(origin: probe, size: .square(1)))
        return Run(kind: request.kind, generation: request.generation, slot: request.slot, configuration: configuration,
                   resolvedVariant: VariantResolution(variant: configuration.variant, reason: "\(twin.id) · \(twin.mapping)"),
                   quality: .full, device: deviceStamp(), gpu: gpu.facts,
                   kernel: KernelSummary(sigmaEff: nil, excessKurtosis: nil, fetchesPerPixel: 0, tapsPerAxis: nil, passNames: [twin.id]),
                   dispatch: [], timing: nil, cost: nil, parity: nil,
                   probe: ProbeReadout(probe: configuration.probe, input: SIMD4<Double>(input[0]), output: SIMD4<Double>(texel[0])),
                   shape: nil, shader: nil, trace: nil, calibration: nil, deviceProbe: nil, notes: ["appleTwin=\(twin.id)", twin.call])
    }

    /// The CPU reference's last wall time for a slot (Compare's CPU REF TIME column, MEASURED).
    public func cpuReferenceMilliseconds(slot: RunSlot) -> Double? { slots[slot]?.cpuReferenceMilliseconds }

    // MARK: Workspaces (timing, parity, strips)

    /// Prepares a workspace's window (and colour pre-pass when the settings need one) for `configuration` at full
    /// resolution and returns the pipeline instance, the pre-passed input and the request it runs.
    private func prepareWorkspace(_ space: Workspace, configuration: RenderConfiguration, op: any BlurOperator, instance: String,
                                  prePass: Bool) async throws
        -> (pipeline: any GPUBlurPipeline, source: any MTLTexture, output: any MTLTexture, request: OperatorRequest,
            resolution: VariantResolution, auxiliary: GPUAuxiliaryTextures, window: any MTLTexture) {
        let canvas = try await canvasTexture(for: configuration)
        try await ensureCommonPipelines()
        let (factory, resolution, request) = try resolveFactory(for: op, blur: configuration.blur, request: configuration.operatorRequest)
        let key = "\(instance)|\(factory.blur.rawValue)|\(factory.variant.rawValue)"
        let pipeline = self.pipeline(factory, key: key, in: &space.pipelines)
        let signature = "\(request.settings.edgeMode.rawValue)|\(request.size.width)"
        if space.prepared[key] != signature {
            try await pipeline.prepare(gpu, request: request)
            space.prepared[key] = signature
        }
        let n = configuration.windowSize
        let spec = TextureSpec(width: n, height: n, roles: [.read, .renderTarget])
        if space.windowSpec != spec || space.window == nil {
            if let old = space.window, let oldSpec = space.windowSpec { gpu.recycle(old, spec: oldSpec) }
            space.window = try gpu.texture(spec); space.windowSpec = spec
        }
        let outputRoles: TextureRole = pipeline.writesDestinationFromCompute ? [.read, .renderTarget, .computeWrite] : [.read, .renderTarget]
        let outputSpec = TextureSpec(width: n, height: n, roles: outputRoles)
        if space.outputSpec != outputSpec || space.output == nil {
            if let old = space.output, let oldSpec = space.outputSpec { gpu.recycle(old, spec: oldSpec) }
            space.output = try gpu.texture(outputSpec); space.outputSpec = outputSpec
        }
        guard let window = space.window, let output = space.output else { throw GPUError.textureAllocationFailed("workspace") }
        let recorder = GPUCommandRecorder(context: gpu, label: "\(instance) input")
        try encodeWindow(canvas, configuration, into: window, recorder: recorder)
        var source: any MTLTexture = window
        if prePass && ColourTransform.needsPasses(request.settings) {
            let preSpec = TextureSpec(width: n, height: n, roles: outputRoles)
            if space.preSpec != preSpec || space.pre == nil {
                if let old = space.pre, let oldSpec = space.preSpec { gpu.recycle(old, spec: oldSpec) }
                space.pre = try gpu.texture(preSpec); space.preSpec = preSpec
            }
            if let pre = space.pre {
                try gpu.encodeColourPass(post: false, settings: request.settings, source: window, destination: pre, recorder: recorder)
                source = pre
            }
        }
        let done = await recorder.commitAndWait()
        if let error = done.compactMap(\.error).first { throw GPUError.commandBufferFailed(error) }
        let throwaway = SlotState()
        let auxiliary = try await auxiliaryTextures(canvas, configuration, state: throwaway)
        return (pipeline, source, output, request, resolution, auxiliary, window)
    }

    private func checkMeasurement(_ epoch: UInt64) throws {
        if Task.isCancelled || epoch != measurementEpoch { throw CancellationError() }
    }

    // MARK: Measurements

    /// Budgeted timing (TimingRequest: 3 warm-ups, up to 15 samples or 1 s of GPU time, minimum 3), ABAB with `other`
    /// in Compare; skipped above FetchBudget.full (`TOO SLOW TO TIME`). Cancelled by `cancelMeasurements` (any touch).
    /// Never in the Simulator. Times the blur passes only, on an already pre-passed input (the colour/copy overhead is
    /// the timing service's separate number). Returns [A] or [A, B]; [] when skipped.
    public func time(_ configuration: RenderConfiguration, slot: RunSlot, interleavedWith other: RenderConfiguration?) async throws -> [Run] {
        guard let timing = GPUServices.timing, !gpu.facts.isSimulator, let op = BlurRegistry.op(configuration.blur) else { return [] }
        guard !Self.isExternal(configuration.variant), Self.isTimeable(configuration) else { return [] }
        let epoch = measurementEpoch
        let spaceA = timingWorkspace("\(slot.rawValue)")
        let a = try await prepareWorkspace(spaceA, configuration: configuration, op: op, instance: "timing", prePass: true)
        try checkMeasurement(epoch)
        let inputsA = GPUBlurInputs(source: a.source, destination: a.output, request: a.request, auxiliary: a.auxiliary)
        var summaries: [(RenderConfiguration, VariantResolution, OperatorRequest, TimingSummary)] = []
        if let other, let opB = BlurRegistry.op(other.blur), !Self.isExternal(other.variant), Self.isTimeable(other) {
            let spaceB = timingWorkspace("\(slot.rawValue)-other")
            let b = try await prepareWorkspace(spaceB, configuration: other, op: opB, instance: "timing", prePass: true)
            try checkMeasurement(epoch)
            let inputsB = GPUBlurInputs(source: b.source, destination: b.output, request: b.request, auxiliary: b.auxiliary)
            if let pair = try await timing.measureInterleaved((a.pipeline, inputsA), (b.pipeline, inputsB), request: TimingRequest(), context: gpu) {
                summaries = [(configuration, a.resolution, a.request, pair.0), (other, b.resolution, b.request, pair.1)]
            } else {
                // The service has no ABAB yet: time A, then B (`interleaved` stays false, so ΔGPU says so).
                guard let sa = try await timing.measure(a.pipeline, inputs: inputsA, request: TimingRequest(), context: gpu) else { return [] }
                try checkMeasurement(epoch)
                guard let sb = try await timing.measure(b.pipeline, inputs: inputsB, request: TimingRequest(), context: gpu) else { return [] }
                summaries = [(configuration, a.resolution, a.request, sa), (other, b.resolution, b.request, sb)]
            }
        } else {
            guard let s = try await timing.measure(a.pipeline, inputs: inputsA, request: TimingRequest(), context: gpu) else { return [] }
            summaries = [(configuration, a.resolution, a.request, s)]
        }
        try checkMeasurement(epoch)
        let sinceLaunch = ProcessInfo.processInfo.systemUptime - launchUptime
        let stamp = deviceStamp()
        return summaries.enumerated().map { index, item in
            let (config, resolution, request, summary) = item
            let operation = BlurRegistry.op(config.blur) ?? op
            let plan = operation.passPlan(request)
            var notes = ["launch+\(NumberStyle.decimals(1).text(sinceLaunch)) s"]
            if summary.thermalChanged { notes.append("THERMAL CHANGED") }
            return Run(kind: .timing, generation: slots[slot]?.newestGeneration ?? 0, slot: index == 0 ? slot : .b, configuration: config,
                       resolvedVariant: resolution, quality: .full, device: stamp, gpu: gpu.facts,
                       kernel: KernelSummary(sigmaEff: operation.sigma(request), excessKurtosis: nil, fetchesPerPixel: plan.fetchesPerPixel,
                                             tapsPerAxis: nil, passNames: plan.passes.map(\.name)),
                       dispatch: [], timing: summary, cost: nil, parity: nil, probe: nil, shape: nil, shader: nil, trace: nil,
                       calibration: nil, deviceProbe: nil, notes: notes)
        }
    }

    private func timingWorkspace(_ key: String) -> Workspace {
        if let existing = timingWorkspaces[key] { return existing }
        let created = Workspace(); timingWorkspaces[key] = created; return created
    }

    static func isExternal(_ variant: VariantID) -> Bool {
        variant.rawValue.hasPrefix(cpuReferencePrefix) || variant.rawValue.hasPrefix(appleTwinPrefix)
    }

    /// False above FetchBudget.full: such a configuration is never timed (`TOO SLOW TO TIME`, SPEC §4.1.6).
    public static func isTimeable(_ configuration: RenderConfiguration) -> Bool {
        guard let op = BlurRegistry.op(configuration.blur) else { return false }
        let request = configuration.operatorRequest
        return op.passPlan(request).fetchesPerFrame(request.size) <= FetchBudget.full
    }

    /// MODELED full-resolution time (fetches ÷ FetchBudget.modeledFetchesPerSecond), for `TOO SLOW TO TIME · ≈ x ms`.
    public static func modeledMilliseconds(_ configuration: RenderConfiguration) -> Double? {
        guard let op = BlurRegistry.op(configuration.blur) else { return nil }
        let request = configuration.operatorRequest
        return op.passPlan(request).fetchesPerFrame(request.size) / FetchBudget.modeledFetchesPerSecond * 1000
    }

    /// GPU vs BlurCore on a 128 × 128 crop around the probe (ParityRunner semantics, `referenceCrop`), with
    /// `ReferenceOptions.forDevice(probes)`; runs after timing at background priority; cancellable. Until this phone's
    /// sub-texel rule is measured, classes with a bilinear term come back report-only, named
    /// `SUB-TEXEL RULE NOT YET MEASURED` (ARCHITECTURE §4.3, §7 rule 7).
    public func parity(_ configuration: RenderConfiguration, slot: RunSlot) async throws -> ParitySummary? {
        guard let op = BlurRegistry.op(configuration.blur), !Self.isExternal(configuration.variant) else { return nil }
        let epoch = measurementEpoch
        let space = parityWorkspace
        let prepared = try await prepareWorkspace(space, configuration: configuration, op: op, instance: "parity-\(slot.rawValue)", prePass: false)
        try checkMeasurement(epoch)
        let n = configuration.windowSize
        let region = PixelRegion.centred(on: configuration.probe, side: 128, inside: .square(n))
        let recorder = GPUCommandRecorder(context: gpu, label: "parity \(slot.rawValue)")
        if let previous = space.encoded { gpu.recycle(previous); space.encoded = nil }
        let encoded = try gpu.encodeFullBlur(prepared.pipeline, window: prepared.window, output: prepared.output, request: prepared.request,
                                             auxiliary: prepared.auxiliary, quality: .full, trace: nil, recorder: recorder)
        let readback = try gpu.encodeReadTexels(prepared.output, region: region, recorder: recorder)
        let done = await recorder.commitAndWait()
        space.encoded = encoded
        if let error = done.compactMap(\.error).first { throw GPUError.commandBufferFailed(error) }
        try checkMeasurement(epoch)
        let gpuCrop = ImageBuffer(width: region.size.width, height: region.size.height, pixels: readback.decode())

        // The tolerance class this variant publishes (its parity cases), for these colour settings.
        let request = prepared.request
        let factory = GPUPipelineRegistry.factory(configuration.blur, request.variant)
        let cases = factory?.parityCases(n) ?? []
        let matching = cases.first { $0.configuration.settings.colourSpace == request.settings.colourSpace
            && $0.configuration.settings.alphaMode == request.settings.alphaMode } ?? cases.first
        var tolerance = (matching?.tolerance ?? ParityTolerance(name: "NO PARITY CLASS DECLARED", ulp16: .infinity, absolute: .infinity,
                                                                 reportOnly: true)).adjusted(for: request.settings)
        let bilinearPasses = matching?.bilinearPasses ?? 0
        let measured = ReferenceOptions.forDevice(deviceProbes())
        if tolerance.dependsOnSubTexelRule && measured == nil {
            tolerance = ParityTolerance(name: Self.subTexelPendingName, ulp16: tolerance.ulp16, absolute: tolerance.absolute,
                                        perBilinearPass: tolerance.perBilinearPass, reportOnly: true)
        }
        let options = measured ?? ReferenceOptions(emulateHalfStorage: true, subTexelBits: nil)
        guard let canvas = await specimens.canvas(configuration.specimen, options: configuration.specimenOptions, windowSize: n) else { return nil }
        let pan = configuration.pan, ev = configuration.specimenOptions.exposureEV
        let radius = op.passPlan(request).supportRadius, edge = request.settings.edgeMode
        let domain: ParityDomain = request.settings.colourSpace == .srgbEncoded ? .encoded : .linear
        let finalTolerance = tolerance
        let evaluation = try await Task.detached(priority: .utility) { () throws -> ParityEvaluation in
            let window = canvas.window(pan: pan)
            let cpu = try BlurReference.runCrop(op, input: window.image, request, region: region, auxiliary: window.auxiliary,
                                                options: options, exposureEV: ev)
            try Task.checkCancellation()
            var exposed = window.image.roundedToHalf()
            if ev != 0 { exposed = exposed.scaled(by: Float(pow(2.0, Double(ev)))).roundedToHalf() }
            let global = Double(exposed.pixels.reduce(Float(1)) { Swift.max($0, $1.max()) })
            var local: [Float]?
            if let radius, edge != .wrap {
                let scales = ParityEvaluation.localScale(exposed, radius: radius)
                local = (region.origin.y..<(region.origin.y + region.size.height)).flatMap { y in
                    (region.origin.x..<(region.origin.x + region.size.width)).map { x in scales[y * exposed.width + x] }
                }
            }
            return ParityEvaluation.evaluate(gpu: gpuCrop, cpu: cpu, tolerance: finalTolerance, inputScale: global, localScale: local,
                                             bilinearPasses: bilinearPasses, domain: domain)
        }.value
        try checkMeasurement(epoch)
        return ParitySummary(stats: evaluation.stats, region: region, tolerance: tolerance, passed: evaluation.passed)
    }

    /// The tolerance name in-app parity uses while this phone's sub-texel rule is unmeasured (report-only).
    public static let subTexelPendingName = "SUB-TEXEL RULE NOT YET MEASURED"

    /// Cancels timing and parity in flight for a slot (between command buffers); called on every touch.
    public func cancelMeasurements(slot: RunSlot?) { measurementEpoch &+= 1 }

    // MARK: Textures for presenting and readback

    /// The newest output for a slot, or a pass intermediate (Algorithm floor, periscope), or the input window. Valid until
    /// the next display encode of that slot's pipeline instance (readbacks for Trace and periscope happen before it).
    /// Pass intermediates always come from the newest FULL-resolution encode (measurement-derived, held during previews).
    public func displayTexture(slot: RunSlot, pass: Int?) -> (any MTLTexture)? {
        guard let state = slots[slot] else { return nil }
        if let pass {
            guard let encoded = state.full.encoded, encoded.intermediates.indices.contains(pass) else { return nil }
            return encoded.intermediates[pass]
        }
        return state.newest?.output
    }
    public func inputTexture(slot: RunSlot) -> (any MTLTexture)? { slots[slot]?.window }

    /// Blit readback of a region of a slot's output or pass intermediate (Float RGBA, linear). `pass: nil` reads the newest
    /// FULL-resolution output (loupe, MAX |A−B|, jumps): readouts never come from a preview.
    public func readTexels(slot: RunSlot, pass: Int?, region: PixelRegion) async throws -> [SIMD4<Float>] {
        guard let state = slots[slot] else { return [] }
        let texture: (any MTLTexture)?
        if let pass { texture = displayTexture(slot: slot, pass: pass) }
        else { texture = state.newest === state.external ? state.external.output : state.full.output }
        guard let texture, region.origin.x >= 0, region.origin.y >= 0, region.origin.x + region.size.width <= texture.width,
              region.origin.y + region.size.height <= texture.height else { return [] }
        return try await gpu.readTexels(texture, region: region)
    }

    /// Blit readback of the slot's input window (the Trace's 9 × 9 / 17 × 17 context card, Jump › brightest input).
    public func readInputTexels(slot: RunSlot, region: PixelRegion) async throws -> [SIMD4<Float>] {
        guard let window = slots[slot]?.window, region.origin.x >= 0, region.origin.y >= 0,
              region.origin.x + region.size.width <= window.width, region.origin.y + region.size.height <= window.height else { return [] }
        return try await gpu.readTexels(window, region: region)
    }

    /// The configuration of the newest full-resolution render in a slot.
    public func lastFullConfiguration(slot: RunSlot) -> RenderConfiguration? { slots[slot]?.lastFullConfiguration }

    /// Forget a slot's textures (Compare ended): its next render starts from a fresh window.
    public func releaseSlot(_ s: RunSlot) {
        guard s != .a, let state = slots[s] else { return }
        for target in [state.full, state.preview] { if let e = target.encoded { gpu.recycle(e) } }
        slots[s] = nil
    }

    /// Memory warning: drop every cache that can be rebuilt (canvas textures not on screen, timing/parity/strip work).
    public func releaseCaches() {
        let inUse = Set(slots.values.compactMap { $0.windowKey?.canvas })
        for key in canvasTextures.keys where !inUse.contains(key) { canvasTextures[key] = nil }
        canvasRecency.removeAll { !inUse.contains($0) }
        timingWorkspaces = [:]
        parityWorkspace = Workspace()
        stripWorkspace = Workspace()
    }

    // MARK: Fingerprint strip, shapes, device probes, pre-warm

    /// 128 × 128 renders for the fingerprint strip (PSF / STAR / EDGE inputs) at σ_equiv 4 px, LIVE from our Metal
    /// implementation. Never called for Tier S entries (their strip comes from `SystemOffscreen.renderStrip`).
    /// Returns [] when one of the three test images is not available, so the card never shows a partial strip.
    public func renderStrip(_ configuration: RenderConfiguration) async throws -> [ImageBuffer] {
        guard let op = BlurRegistry.op(configuration.blur), op.entry.tier != .system, op.entry.tier.runsLive else { return [] }
        let specimens: [SpecimenID] = ["impulse", "siemens-star", "step-edges"]
        guard specimens.allSatisfy({ SpecimenRegistry.generator($0) != nil }) else { return [] }
        let held = op.holdingSigma(4, current: configuration.parameters).parameters
        var images: [ImageBuffer] = []
        for specimen in specimens {
            let n = 128, c = SpecimenGeometry.centre(windowSize: n)
            let strip = RenderConfiguration(blur: configuration.blur, variant: configuration.variant, parameters: held,
                                            settings: configuration.settings, specimen: specimen, specimenOptions: .standard,
                                            pan: .zero, probe: c, windowSize: n)
            let prepared = try await prepareWorkspace(stripWorkspace, configuration: strip, op: op, instance: "strip", prePass: false)
            let recorder = GPUCommandRecorder(context: gpu, label: "strip \(specimen.rawValue)")
            if let previous = stripWorkspace.encoded { gpu.recycle(previous); stripWorkspace.encoded = nil }
            let encoded = try gpu.encodeFullBlur(prepared.pipeline, window: prepared.window, output: prepared.output, request: prepared.request,
                                                 auxiliary: prepared.auxiliary, quality: .full, trace: nil, recorder: recorder)
            let read = try gpu.encodeReadTexels(prepared.output, region: PixelRegion(origin: .zero, size: .square(n)), recorder: recorder)
            let done = await recorder.commitAndWait()
            stripWorkspace.encoded = encoded
            if let error = done.compactMap(\.error).first { throw GPUError.commandBufferFailed(error) }
            images.append(ImageBuffer(width: n, height: n, pixels: read.decode()))
        }
        return images
    }

    /// ON THIS PHONE (SPEC §7.1 item 10): GPU-MEASURE's shape measurement of our Metal implementation at `configuration`.
    public func measureShape(_ configuration: RenderConfiguration) async throws -> ShapeMeasurement? {
        guard let shapes = GPUServices.shapes, let op = BlurRegistry.op(configuration.blur), op.entry.tier != .system else { return nil }
        try await ensureCommonPipelines()
        let (factory, _, request) = try resolveFactory(for: op, blur: configuration.blur, request: configuration.operatorRequest)
        let pipeline = factory.make()
        try await pipeline.prepare(gpu, request: request)
        return try await shapes.measure(pipeline, request: request, context: gpu)
    }

    /// One This-phone probe (SPEC §4.7) as a Run of kind `.probe`; nil when the service cannot run it yet.
    public func runDeviceProbe(_ kind: DeviceProbeKind) async -> Run? {
        guard let probes = GPUServices.probes else { return nil }
        let stamp = deviceStamp()
        guard let result = try? await probes.run(kind, context: gpu, device: stamp) else { return nil }
        let empty = RenderConfiguration(blur: "device-probe", variant: VariantID(rawValue: kind.rawValue), parameters: ParameterValues(),
                                        settings: .standard, specimen: "none", specimenOptions: .standard, pan: .zero, probe: .zero,
                                        windowSize: 0)
        return Run(kind: .probe, generation: 0, slot: .a, configuration: empty, resolvedVariant: VariantResolution(variant: empty.variant),
                   quality: .full, device: stamp, gpu: gpu.facts,
                   kernel: KernelSummary(sigmaEff: nil, excessKurtosis: nil, fetchesPerPixel: 0, tapsPerAxis: nil, passNames: []),
                   dispatch: [], timing: nil, cost: nil, parity: nil, probe: nil, shape: nil, shader: nil, trace: nil, calibration: nil,
                   deviceProbe: result)
    }

    /// After the idle gate, once per launch (ARCHITECTURE §5.8 rule 6): the hero dozen's default variants × {clamp} ×
    /// {untraced, traced} are specialised in the background (each `prepare` builds both TRACE_PROBE forms), so the first
    /// tap on a strip glyph does not wait for a compile. Returns how many pipelines were prepared. Throwaway instances are
    /// used: the specialisations land in GPUContext's cache, the scratch textures are freed.
    public func prewarmHeroDozen(windowSize: Int, shouldContinue: @MainActor () -> Bool) async -> Int {
        try? await ensureCommonPipelines()
        var prepared = 0
        let heroes = BlurRegistry.operators.filter { $0.entry.heroOrder != nil && $0.entry.tier.runsLive }
            .sorted { ($0.entry.heroOrder ?? 0) < ($1.entry.heroOrder ?? 0) }
        for op in heroes {
            guard shouldContinue() else { break }
            let entry = op.entry
            guard let factory = GPUPipelineRegistry.factory(entry.id, entry.defaultVariant) else { continue }
            let request = OperatorRequest(parameters: entry.defaultParameters, variant: entry.defaultVariant,
                                          settings: SilentSettings(edgeMode: .clamp), size: .square(windowSize))
            if (try? await factory.make().prepare(gpu, request: request)) != nil { prepared += 1 }
        }
        return prepared
    }
}

// MARK: - Sendable carriers for detached work

/// The window crop of a canvas's auxiliary buffers as fp16 RGBA planes (scalars in .r, velocity in .rg).
struct RenderCoordinatorAuxiliaryPlanes: Sendable {
    var depth: HalfImageData?
    var velocity: HalfImageData?
    var guide: HalfImageData?
    var mask: HalfImageData?
    var subFrames: [HalfImageData]
    init(_ aux: AuxiliaryInputs) {
        func scalar(_ b: ScalarBuffer?) -> HalfImageData? {
            b.map { HalfImageData(ImageBuffer(width: $0.width, height: $0.height, pixels: $0.values.map { SIMD4($0, 0, 0, 1) })) }
        }
        depth = scalar(aux.depth)
        mask = scalar(aux.mask)
        velocity = aux.velocity.map { HalfImageData(ImageBuffer(width: $0.width, height: $0.height, pixels: $0.values.map { SIMD4($0.x, $0.y, 0, 1) })) }
        guide = aux.guide.map { HalfImageData($0) }
        subFrames = (aux.subFrames ?? []).map { HalfImageData($0) }
    }
}

/// One decoded TRACE_PROBE tap (TraceLayout.Tap), Sendable for the detached merge.
struct RenderCoordinatorTracedTap: Sendable {
    var position: SIMD2<Float>
    var weight: Float
    var flags: Float
    var fetched: SIMD4<Float>
    var runningSum: SIMD4<Float>
    var extra: SIMD4<Float>
    init(_ tap: TraceLayout.Tap) {
        position = tap.position; weight = tap.weight; flags = tap.flags; fetched = tap.fetched; runningSum = tap.runningSum; extra = tap.extra
    }
}

/// One traced pass's GPU block: the pixel the pass computed for the probe, its taps and overflow count.
struct RenderCoordinatorTracedPass: Sendable {
    var passIndex: Int
    var pixel: PixelPoint
    var overflow: Int
    var taps: [RenderCoordinatorTracedTap]
}
