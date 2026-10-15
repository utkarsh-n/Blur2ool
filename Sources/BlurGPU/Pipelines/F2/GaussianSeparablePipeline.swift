import Foundation
import Metal
import BlurCore

// OWNER: FAM-F2 (seed written for the skeleton; review fix E-14). gaussian-blur / gaussian-separable: two fragment passes
// of b2_f2_gauss_separable_fs through the frozen GaussianPassEncoder (integer taps, renormalise-capable), both traceable.

@MainActor
public final class GaussianSeparablePipeline: GPUBlurPipeline {
    public let blur: BlurID = GaussianOperator.id
    public let variant: VariantID = GaussianOperator.separable
    public let shaderFile = "F2Gaussian.metal"
    public let functionNames = ["b2_common_fullscreen_vs", "b2_f2_gauss_separable_fs"]
    public let writesDestinationFromCompute = false
    private var scratch: (any MTLTexture)?
    private var scratchSize = ImageSize(width: 0, height: 0)

    public init() {}

    public func prepare(_ context: GPUContext, request: OperatorRequest) async throws {
        try await GaussianPassEncoder.prepare(context, form: .integerTaps, edgeMode: request.settings.edgeMode)
    }

    public func encode(_ context: GPUContext, _ inputs: GPUBlurInputs, trace: TraceRequest?, recorder: GPUCommandRecorder) throws -> EncodedBlur {
        let width = inputs.source.width, height = inputs.source.height
        if scratch == nil || scratchSize != ImageSize(width: width, height: height) {
            if let old = scratch { context.recycle(old, spec: TextureSpec(width: scratchSize.width, height: scratchSize.height, roles: [.read, .renderTarget])) }
            scratch = try context.texture(TextureSpec(width: width, height: height, roles: [.read, .renderTarget]))
            scratchSize = ImageSize(width: width, height: height)
        }
        guard let mid = scratch else { throw GPUError.textureAllocationFailed("gaussian scratch") }
        let kernel = GaussianOperator().kernel(inputs.request)
        let capacity = trace?.maxTapsPerPass ?? 0
        let traceBuffer = try trace.map { try context.traceBuffer(passes: 2, capacity: $0.maxTapsPerPass, probe: $0.probe) }
        var dispatch: [PassDispatch] = []
        for (pass, (source, destination)) in [(inputs.source, mid), (mid, inputs.destination)].enumerated() {
            dispatch.append(try GaussianPassEncoder.encodePass(
                context, form: .integerTaps, kernel: kernel, direction: UInt32(pass), edgeMode: inputs.request.settings.edgeMode,
                source: source, destination: destination, passIndex: pass, label: pass == 0 ? "H" : "V",
                trace: traceBuffer.map { ($0, pass * TraceLayout.passStride(capacity: capacity)) }, recorder: recorder))
        }
        return EncodedBlur(dispatch: dispatch, intermediates: [mid, inputs.destination], traceBuffer: traceBuffer,
                           tracedPassIndices: trace == nil ? [] : [0, 1], uploadedWeights: kernel.weights.map(Float.init),
                           uploadedOffsets: nil, traceCapacity: capacity)
    }

    /// σ 4 step edges (traced), σ 12 impulse at +6 EV (HDR, traced), renormalise and mirror edges.
    public nonisolated static func parityCases(_ windowSize: Int) -> [ParityCase] {
        let c = SpecimenGeometry.centre(windowSize: windowSize)
        func config(_ sigma: Double, specimen: SpecimenID, settings: SilentSettings = .standard, options: SpecimenOptions = .standard,
                    probe: PixelPoint) -> RenderConfiguration {
            RenderConfiguration(blur: GaussianOperator.id, variant: GaussianOperator.separable,
                                parameters: ParameterValues(["sigma": .double(sigma), "truncation": .choice("3"), "discretisation": .choice("sampled")]),
                                settings: settings, specimen: specimen, specimenOptions: options, pan: .zero, probe: probe, windowSize: windowSize)
        }
        let edgeProbe = PixelPoint(x: c.x - 1, y: c.y - Swift.min(147, c.y))
        let hdrProbe = PixelPoint(x: c.x + 5, y: c.y + 3)
        return [
            ParityCase(name: "gaussian separable σ4 step edges", configuration: config(4, specimen: "step-edges", probe: edgeProbe),
                       tolerance: .exactF32, bilinearPasses: 0, checkTraced: true, probes: [edgeProbe], note: "SPEC §5.3 A, integer taps"),
            ParityCase(name: "gaussian separable σ12 impulse ×100 +6 EV",
                       configuration: config(12, specimen: "impulse", options: SpecimenOptions(exposureEV: 6, choices: ["intensity": "100"]),
                                             probe: hdrProbe),
                       tolerance: .exactF32, bilinearPasses: 0, checkTraced: true, probes: [hdrProbe], note: "HDR 6,400, exposure at render time"),
            ParityCase(name: "gaussian separable σ6 renormalise",
                       configuration: config(6, specimen: "step-edges", settings: SilentSettings(edgeMode: .renormalise), probe: PixelPoint(x: 2, y: 2)),
                       tolerance: .exactF32, bilinearPasses: 0, checkTraced: true, probes: [PixelPoint(x: 2, y: 2)], note: "renormalise §4.3"),
            ParityCase(name: "gaussian separable σ6 mirror",
                       configuration: config(6, specimen: "step-edges", settings: SilentSettings(edgeMode: .mirror), probe: PixelPoint(x: 2, y: 2)),
                       tolerance: .exactF32, bilinearPasses: 0, checkTraced: false, probes: [], note: "edge mapping §4.3"),
        ]
    }
}
