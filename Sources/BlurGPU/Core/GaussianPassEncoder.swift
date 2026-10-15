import Foundation
import Metal
import BlurCore

// FROZEN — ARCHITECTURE.md §6.1 (review fix E-14). The one shared Gaussian stage: other groups (bloom, drop shadow,
// materials, Lorentzian sum of Gaussians, DoG) call this instead of FAM-F2's internals. SKEL wrote both Metal functions
// (`b2_f2_gauss_linear_fs`, `b2_f2_gauss_separable_fs`) and this helper; their names and bindings never change.

@MainActor
public enum GaussianPassEncoder {
    public enum Form: String, Sendable, Hashable {
        /// Integer taps −r … +r (`b2_f2_gauss_separable_fs`); renormalise-capable; parity class exactF32.
        case integerTaps
        /// Merged bilinear pairs (`b2_f2_gauss_linear_fs`, Rákos 2010); parity class bilinear; renormalise → clamp.
        case linearSampled
    }

    public static func functionName(_ form: Form) -> String {
        form == .integerTaps ? "b2_f2_gauss_separable_fs" : "b2_f2_gauss_linear_fs"
    }

    /// Builds both directions × {untraced, traced} for one edge mode.
    public static func prepare(_ context: GPUContext, form: Form, edgeMode: EdgeMode) async throws {
        for traced in [false, true] {
            for direction: UInt32 in [0, 1] {
                _ = try await context.renderPipeline(fragment: functionName(form), colorFormats: [.rgba16Float],
                                                     constants: FunctionConstants(traceProbe: traced, edgeMode: edgeMode, direction: direction))
            }
        }
    }

    /// The table the GPU receives for a kernel: integer weights, or the linear-sampled pair table.
    public static func tables(_ form: Form, kernel: Kernel1D) -> (weights: [Float], offsets: [Float]) {
        switch form {
        case .integerTaps: return (kernel.weights.map(Float.init), [])
        case .linearSampled:
            let t = KernelMath.linearSampledTable(kernel)
            return (t.weights.map(Float.init), t.offsets.map(Float.init))
        }
    }

    /// Encodes one pass (direction 0 = H, 1 = V) from `source` into `destination` (rgba16Float render target, no
    /// .shaderWrite). `trace` is this pass's block in a trace buffer (TraceLayout.passStride × block index).
    @discardableResult
    public static func encodePass(_ context: GPUContext, form: Form, kernel: Kernel1D, direction: UInt32, edgeMode: EdgeMode,
                                  source: any MTLTexture, destination: any MTLTexture, passIndex: Int, label: String,
                                  trace: (buffer: any MTLBuffer, offset: Int)?, recorder: GPUCommandRecorder) throws -> PassDispatch {
        let effectiveEdge: EdgeMode = (form == .linearSampled && edgeMode == .renormalise) ? .clamp : edgeMode
        let constants = FunctionConstants(traceProbe: trace != nil, edgeMode: effectiveEdge, direction: direction)
        let pso = try context.preparedRenderPipeline(fragment: functionName(form), colorFormats: [.rgba16Float], constants: constants)
        let (weights, offsets) = tables(form, kernel: kernel)
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = destination
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        let encoder = try recorder.renderEncoder(pass: passIndex, descriptor: descriptor, label: label)
        encoder.setRenderPipelineState(pso)
        encoder.setFragmentTexture(source, index: 0)
        let entries = form == .integerTaps ? weights.count : offsets.count
        var params: [UInt32] = [UInt32(entries), UInt32(source.width), UInt32(source.height), 0]
        encoder.setFragmentBytes(&params, length: 16, index: 0)
        let weightBuffer = try context.buffer(weights)
        encoder.setFragmentBuffer(weightBuffer, offset: 0, index: 1)
        if form == .linearSampled { encoder.setFragmentBuffer(try context.buffer(offsets), offset: 0, index: 2) }
        if let trace { encoder.setFragmentBuffer(trace.buffer, offset: trace.offset, index: 5) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return PassDispatch(passIndex: passIndex, name: label, encoder: .render,
                            functionNames: ["b2_common_fullscreen_vs", functionName(form)], threadsPerThreadgroup: [0, 0, 0],
                            threadgroups: [0, 0, 0], staticThreadgroupMemoryBytes: 0, dynamicThreadgroupMemoryBytes: 0,
                            threadExecutionWidth: 0, pipelineMaxThreads: 0,
                            outputSize: ImageSize(width: destination.width, height: destination.height), outputHasShaderWrite: false,
                            modeledBytes: 2 * Double(destination.width * destination.height) * 8)
    }
}
