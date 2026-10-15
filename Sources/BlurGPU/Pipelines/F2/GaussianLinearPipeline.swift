import Foundation
import Metal
import BlurCore

// OWNER: FAM-F2 (seed written for the skeleton). gaussian-blur / gaussian-linear-sampling: two fragment passes (H, V)
// of b2_f2_gauss_linear_fs, render targets WITHOUT .shaderWrite (compressible on Apple9), both passes traceable.

@MainActor
public final class GaussianLinearPipeline: GPUBlurPipeline {
    public let blur: BlurID = GaussianOperator.id
    public let variant: VariantID = GaussianOperator.linearSampled
    public let shaderFile = "F2Gaussian.metal"
    public let functionNames = ["b2_common_fullscreen_vs", "b2_f2_gauss_linear_fs"]
    public let writesDestinationFromCompute = false
    private var scratch: (any MTLTexture)?
    private var scratchSize = ImageSize(width: 0, height: 0)

    public init() {}

    public func prepare(_ context: GPUContext, request: OperatorRequest) async throws {
        try await GaussianPassEncoder.prepare(context, form: .linearSampled, edgeMode: request.settings.edgeMode)
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
                context, form: .linearSampled, kernel: kernel, direction: UInt32(pass), edgeMode: inputs.request.settings.edgeMode,
                source: source, destination: destination, passIndex: pass, label: pass == 0 ? "H" : "V",
                trace: traceBuffer.map { ($0, pass * TraceLayout.passStride(capacity: capacity)) }, recorder: recorder))
        }
        let tables = GaussianPassEncoder.tables(.linearSampled, kernel: kernel)
        return EncodedBlur(dispatch: dispatch, intermediates: [mid, inputs.destination], traceBuffer: traceBuffer,
                           tracedPassIndices: trace == nil ? [] : [0, 1], uploadedWeights: tables.weights, uploadedOffsets: tables.offsets,
                           traceCapacity: capacity)
    }

    /// SPEC §5.3 A (step edges, σ 4, probe (446, 300) at N = 894), the Bench default (σ 12, impulse), and edge modes.
    public nonisolated static func parityCases(_ windowSize: Int) -> [ParityCase] {
        let c = SpecimenGeometry.centre(windowSize: windowSize)
        func config(_ sigma: Double, specimen: SpecimenID, settings: SilentSettings = .standard, probe: PixelPoint) -> RenderConfiguration {
            RenderConfiguration(blur: GaussianOperator.id, variant: GaussianOperator.linearSampled,
                                parameters: ParameterValues(["sigma": .double(sigma), "truncation": .choice("3"), "discretisation": .choice("sampled")]),
                                settings: settings, specimen: specimen, specimenOptions: .standard, pan: .zero, probe: probe, windowSize: windowSize)
        }
        let edgeProbe = PixelPoint(x: c.x - 1, y: c.y - Swift.min(147, c.y))
        var cases = [
            ParityCase(name: "gaussian linear σ4 step edges", configuration: config(4, specimen: "step-edges", probe: edgeProbe),
                       tolerance: .bilinear, bilinearPasses: 2, checkTraced: true, probes: [edgeProbe], note: "SPEC §5.3 A"),
            ParityCase(name: "gaussian linear σ12 impulse", configuration: config(12, specimen: "impulse", probe: PixelPoint(x: c.x, y: c.y + 8)),
                       tolerance: .bilinear, bilinearPasses: 2, checkTraced: true, probes: [PixelPoint(x: c.x, y: c.y + 8)], note: "Bench default σ"),
        ]
        for edge in [EdgeMode.mirror, .wrap, .zero] {
            cases.append(ParityCase(name: "gaussian linear σ6 \(edge.rawValue)",
                                    configuration: config(6, specimen: "step-edges", settings: SilentSettings(edgeMode: edge), probe: PixelPoint(x: 2, y: 2)),
                                    tolerance: .bilinear, bilinearPasses: 2, checkTraced: false, probes: [], note: "edge mapping §4.3"))
        }
        cases.append(ParityCase(name: "gaussian linear σ4 sRGB-encoded",
                                configuration: config(4, specimen: "step-edges", settings: SilentSettings(colourSpace: .srgbEncoded), probe: edgeProbe),
                                tolerance: ParityTolerance.bilinear.plus(.fastMath), bilinearPasses: 2, checkTraced: false, probes: [],
                                note: "SPEC §5.3 A branch 115/255"))
        return cases
    }
}
