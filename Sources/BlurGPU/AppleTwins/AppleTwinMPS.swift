import Foundation
import Metal
import MetalPerformanceShaders
import BlurCore

// OWNER: APPLE-TWINS. The Metal Performance Shaders twins: MPSImageGaussianBlur(sigma:), MPSImageBox and MPSImageTent
// encoded straight onto the window texture. MPS filters the numbers stored in the texture (no colour management), so on
// our linear rgba16Float window it averages linear light. Edge mode defaults to `.zero`, MPS's own default (CAL §5.3).
// Box and tent take the half-width r as their parameter and build kernelWidth = kernelHeight = 2·round(r) + 1 (MPS
// requires odd sizes), the convention CAL measured.

extension AppleTwinRunner {
    func runMPS(_ subject: CalibrationSubject, parameter: Double, options: AppleTwinOptions, input: any MTLTexture,
                output: any MTLTexture, context: GPUContext) async throws -> AppleTwinRunReport {
        guard MPSSupportsMTLDevice(context.device) else {
            throw GPUError.unsupported("Metal Performance Shaders do not support \(context.device.name)")
        }
        let edge: MPSImageEdgeMode = options.mpsEdge == .clamp ? .clamp : .zero
        let edgeText = " · edgeMode .\(options.mpsEdge.rawValue)"
        let target = try writableTarget(for: output, context: context)
        let cb = try makeCommandBuffer(context, label: "Apple twin · \(subject.title)")
        let call: String
        var notes = ["MPS filters the stored numbers: linear light on this window (no colour management)"]
        switch subject {
        case .mpsGaussianBlur:
            if parameter > 0 {
                let kernel = MPSImageGaussianBlur(device: context.device, sigma: Float(parameter))
                kernel.edgeMode = edge
                kernel.label = "MPSImageGaussianBlur"
                kernel.encode(commandBuffer: cb, sourceTexture: input, destinationTexture: target.texture)
                call = "MPSImageGaussianBlur(device:sigma: \(AppleTwinRunner.number(parameter)))" + edgeText
            } else {
                try encodeCopy(from: input, to: target.texture, commandBuffer: cb)
                call = "sigma 0: identity copy (MPSImageGaussianBlur needs sigma > 0)"
                notes.append("no MPS kernel ran")
            }
        case .mpsBox, .mpsTent:
            let width = AppleTwinCatalog.kernelWidth(halfWidth: parameter)
            let kernel: MPSUnaryImageKernel = subject == .mpsBox
                ? MPSImageBox(device: context.device, kernelWidth: width, kernelHeight: width)
                : MPSImageTent(device: context.device, kernelWidth: width, kernelHeight: width)
            kernel.edgeMode = edge
            kernel.label = subject.title
            kernel.encode(commandBuffer: cb, sourceTexture: input, destinationTexture: target.texture)
            call = "\(subject.title)(device:kernelWidth: \(width), kernelHeight: \(width))" + edgeText
            if Double(Int(parameter.rounded())) != parameter {
                notes.append("half-width \(AppleTwinRunner.number(parameter)) rounded to \(Int(parameter.rounded())) (kernel sizes are odd integers)")
            }
        default:
            throw GPUError.unsupported("\(subject.title) is not an MPS twin")
        }
        if target.scratch != nil { try encodeCopy(from: target.texture, to: output, commandBuffer: cb) }
        let ms = try await commitChecked(cb, context: context)
        if let spec = target.scratch { context.recycle(target.texture, spec: spec) }
        return AppleTwinRunReport(subject: subject, parameter: parameter, call: call,
                                  size: ImageSize(width: input.width, height: input.height), gpuMilliseconds: ms,
                                  cpuMilliseconds: nil, clippedTexels: 0, notes: notes)
    }
}
