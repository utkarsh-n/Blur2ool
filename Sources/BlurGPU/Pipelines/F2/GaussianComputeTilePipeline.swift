import Foundation
import Metal
import BlurCore

// OWNER: FAM-F2 (seed written by SKEL, review fix E-15). gaussian-blur / gaussian-compute-tile: two compute passes
// (rows, then columns) of `b2_f2_gauss_tile_k`, each a 256 × 1 row tile or a 1 × 256 column tile with DYNAMIC threadgroup
// memory of (256 + 2r) × 8 B (GaussianOperator.computeTileBytes) bound through GPUContext.dispatch2D — the only way compute
// work is dispatched (ARCHITECTURE §4.4). Outputs carry .shaderWrite (writesDestinationFromCompute). Both passes are
// traceable: TRACE_PROBE records every tap and ends with the flags = 2 final record.
@MainActor
public final class GaussianComputeTilePipeline: GPUBlurPipeline {
    public let blur: BlurID = GaussianOperator.id
    public let variant: VariantID = GaussianOperator.computeTile
    public let shaderFile = "F2Gaussian.metal"
    public static let function = "b2_f2_gauss_tile_k"
    public let functionNames = [GaussianComputeTilePipeline.function]
    public let writesDestinationFromCompute = true
    private var scratch: (any MTLTexture)?
    private var scratchSpec: TextureSpec?

    public init() {}

    public func prepare(_ context: GPUContext, request: OperatorRequest) async throws {
        for traced in [false, true] {
            for direction: UInt32 in [0, 1] {
                _ = try await context.computePipeline(Self.function, constants: FunctionConstants(traceProbe: traced, edgeMode: request.settings.edgeMode,
                                                                                                  direction: direction))
            }
        }
    }

    public func encode(_ context: GPUContext, _ inputs: GPUBlurInputs, trace: TraceRequest?, recorder: GPUCommandRecorder) throws -> EncodedBlur {
        let width = inputs.source.width, height = inputs.source.height
        let spec = TextureSpec(width: width, height: height, roles: [.read, .computeWrite])
        if scratchSpec != spec {
            if let old = scratch, let oldSpec = scratchSpec { context.recycle(old, spec: oldSpec) }
            scratch = try context.texture(spec)
            scratchSpec = spec
        }
        guard let mid = scratch else { throw GPUError.textureAllocationFailed("gaussian tile scratch") }
        let kernel = GaussianOperator().kernel(inputs.request)
        let radius = kernel.origin
        let tileBytes = GaussianOperator.computeTileBytes(radius: radius)
        let weights = kernel.weights.map(Float.init)
        let weightBuffer = try context.buffer(weights)
        let capacity = trace?.maxTapsPerPass ?? 0
        let traceBuffer = try trace.map { try context.traceBuffer(passes: 2, capacity: $0.maxTapsPerPass, probe: $0.probe) }
        var dispatch: [PassDispatch] = []
        for (pass, (source, destination)) in [(inputs.source, mid), (mid, inputs.destination)].enumerated() {
            let constants = FunctionConstants(traceProbe: trace != nil, edgeMode: inputs.request.settings.edgeMode, direction: UInt32(pass))
            let pso = try context.preparedComputePipeline(Self.function, constants: constants)
            let label = pass == 0 ? "H tile" : "V tile"
            let encoder = try recorder.computeEncoder(pass: pass, label: label)
            encoder.setTexture(source, index: 0)
            encoder.setTexture(destination, index: 1)
            var params: [UInt32] = [UInt32(weights.count), UInt32(width), UInt32(height), 0]
            encoder.setBytes(&params, length: 16, index: 0)
            encoder.setBuffer(weightBuffer, offset: 0, index: 1)
            if let traceBuffer { encoder.setBuffer(traceBuffer, offset: pass * TraceLayout.passStride(capacity: capacity), index: 5) }
            let preferred = pass == 0 ? MTLSize(width: 256, height: 1, depth: 1) : MTLSize(width: 1, height: 256, depth: 1)
            let geometry = try context.dispatch2D(encoder, pso: pso, width: width, height: height, preferred: preferred,
                                                  threadgroupMemory: tileBytes, label: "gaussian \(label) r\(radius)")
            encoder.endEncoding()
            dispatch.append(PassDispatch(passIndex: pass, name: pass == 0 ? "H" : "V", encoder: .compute, functionNames: functionNames,
                                         threadsPerThreadgroup: [geometry.threadsPerThreadgroup.width, geometry.threadsPerThreadgroup.height, 1],
                                         threadgroups: [geometry.threadgroups.width, geometry.threadgroups.height, 1],
                                         staticThreadgroupMemoryBytes: pso.staticThreadgroupMemoryLength,
                                         dynamicThreadgroupMemoryBytes: tileBytes, threadExecutionWidth: pso.threadExecutionWidth,
                                         pipelineMaxThreads: pso.maxTotalThreadsPerThreadgroup,
                                         outputSize: ImageSize(width: width, height: height), outputHasShaderWrite: true,
                                         modeledBytes: 2 * Double(width * height) * 8))
        }
        return EncodedBlur(dispatch: dispatch, intermediates: [mid, inputs.destination], traceBuffer: traceBuffer,
                           tracedPassIndices: trace == nil ? [] : [0, 1], uploadedWeights: weights, uploadedOffsets: nil,
                           traceCapacity: capacity)
    }

    /// σ 4 step edges (SPEC §5.3 A compute-tile fixture: r 12 → 2,240 B) and the impulse ×100 at +6 EV (HDR), traced;
    /// renormalise (traced), mirror and wrap edges: the separable seed's cases, so the tile is proven at the same level.
    /// A Night City case is deliberately absent until INTEGRATE applies Documentation/build/requests/SKEL.md item 1: this
    /// Mac's GPU stores fp16 by rounding toward zero (MEASURED), while the frozen CPU model rounds to nearest, so the frozen
    /// `final=out` check and `exactF32` (2 ulps) misjudge it (Tests/BlurGPUTests/SKELSeeds reproduces it as a known issue).
    public nonisolated static func parityCases(_ windowSize: Int) -> [ParityCase] {
        let c = SpecimenGeometry.centre(windowSize: windowSize)
        func config(_ sigma: Double, specimen: SpecimenID, settings: SilentSettings = .standard, options: SpecimenOptions = .standard,
                    probe: PixelPoint) -> RenderConfiguration {
            RenderConfiguration(blur: GaussianOperator.id, variant: GaussianOperator.computeTile,
                                parameters: ParameterValues(["sigma": .double(sigma), "truncation": .choice("3"), "discretisation": .choice("sampled")]),
                                settings: settings, specimen: specimen, specimenOptions: options, pan: .zero, probe: probe, windowSize: windowSize)
        }
        let edgeProbe = PixelPoint(x: c.x - 1, y: c.y - Swift.min(147, c.y))
        let hdrProbe = PixelPoint(x: c.x + 5, y: c.y + 3)
        return [
            ParityCase(name: "gaussian tile σ4 step edges", configuration: config(4, specimen: "step-edges", probe: edgeProbe),
                       tolerance: .exactF32, bilinearPasses: 0, checkTraced: true, probes: [edgeProbe],
                       note: "SPEC §5.3 A compute-tile fixture: 256 × 1 tile, (256 + 2·12) × 8 B = 2,240 B"),
            ParityCase(name: "gaussian tile σ12 impulse ×100 +6 EV",
                       configuration: config(12, specimen: "impulse", options: SpecimenOptions(exposureEV: 6, choices: ["intensity": "100"]),
                                             probe: hdrProbe),
                       tolerance: .exactF32, bilinearPasses: 0, checkTraced: true, probes: [hdrProbe], note: "HDR 6,400, exposure at render time"),
            ParityCase(name: "gaussian tile σ6 renormalise",
                       configuration: config(6, specimen: "step-edges", settings: SilentSettings(edgeMode: .renormalise), probe: PixelPoint(x: 2, y: 2)),
                       tolerance: .exactF32, bilinearPasses: 0, checkTraced: true, probes: [PixelPoint(x: 2, y: 2)], note: "renormalise §4.3"),
            ParityCase(name: "gaussian tile σ6 mirror",
                       configuration: config(6, specimen: "step-edges", settings: SilentSettings(edgeMode: .mirror), probe: PixelPoint(x: 2, y: 2)),
                       tolerance: .exactF32, bilinearPasses: 0, checkTraced: false, probes: [], note: "edge mapping §4.3"),
            ParityCase(name: "gaussian tile σ6 wrap",
                       configuration: config(6, specimen: "step-edges", settings: SilentSettings(edgeMode: .wrap), probe: PixelPoint(x: 2, y: 2)),
                       tolerance: .exactF32, bilinearPasses: 0, checkTraced: false, probes: [], note: "edge mapping §4.3"),
        ]
    }
}
