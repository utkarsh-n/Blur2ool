import Foundation
import Metal
import CoreImage
import BlurCore

// OWNER: APPLE-TWINS. AppleTwinRunner — Apple's own blur APIs run in-process on this device, on the same window texture
// our kernels blur (ARCHITECTURE §8.2 APPLE-TWINS; SPEC §8.2 Apple axis, §13.1):
//   Core Image  CIGaussianBlur, CIBoxBlur, CIDiscBlur, CIBokehBlur, CIMotionBlur, CIZoomBlur, CIMaskedVariableBlur
//               (a CIContext on our command queue renders straight into Metal textures; the API's own transparent border)
//   MPS         MPSImageGaussianBlur, MPSImageBox, MPSImageTent (MPSImageEdgeMode.zero, MPS's default)
//   vImage      box and tent convolve (8-bit ARGB8888 on the CPU; the edge flag vImage makes the caller choose)
// plus `edgeSamples` for Calibrate (CAL §3, §7) and two characterisation probes (impulse moments, edge policy).
//
// Honesty: every result here is Apple's implementation, reportOnly in parity (ARCHITECTURE §7 table), never one of our
// kernels. Mappings and edge/blend facts with their badges live in AppleTwinCatalog; `lastReport` says exactly which call
// ran, with its GPU or CPU time as measured on this device.
//
// Swift 6: the runner is @MainActor like GPUContext; textures, buffers, command buffers, CIFilter and MPS kernels never
// leave the main actor. The vImage convolution runs in a detached task on Sendable byte arrays.

/// MPS edge handling (MPSImageEdgeMode; CAL §5.3 measured both).
public enum AppleTwinMPSEdge: String, Sendable, Codable, Hashable, CaseIterable {
    /// `.zero`, MPS's default: transparent black past the border.
    case zero
    case clamp
}

/// The vImage edge flag. vImage has no default: every call names one (CAL §5.4 measured all three).
public enum AppleTwinVImageEdge: String, Sendable, Codable, Hashable, CaseIterable {
    /// `kvImageEdgeExtend`: clamp to the nearest edge pixel.
    case extend
    /// `kvImageTruncateKernel`: renormalise the kernel to the part inside the image.
    case truncateKernel
    /// `kvImageBackgroundColorFill` with transparent black.
    case backgroundFill
}

/// How the vImage twin stores the window in its 8-bit buffer (box and tent convolve exist only for 8-bit pixels).
public enum AppleTwinVImageStorage: String, Sendable, Codable, Hashable, CaseIterable {
    /// sRGB-encoded, premultiplied 8-bit (how 8-bit images hold colour): vImage then averages encoded values.
    case srgb8
    /// Linear-light 8-bit: averages linear light, with 8-bit steps in the shadows.
    case linear8
}

/// The CIMaskedVariableBlur mask when no mask texture is passed.
public enum AppleTwinMask: Sendable, Codable, Hashable {
    /// The same mask value everywhere (1 = the full radius everywhere: a stationary kernel for Calibrate).
    case uniform(Double)
    /// 0 above `start`, 1 below `end`, linear in between; both are fractions of the window height from the top.
    case verticalRamp(start: Double, end: Double)
}

/// Settings beyond the API's single parameter. Defaults are the API's own defaults (or, for vImage, the documented choice).
public struct AppleTwinOptions: Sendable, Hashable {
    /// CIMotionBlur `inputAngle` in radians, counter-clockwise on screen (Core Image convention). Default 0 (horizontal).
    public var angleRadians: Double
    /// CIZoomBlur `inputCenter` in window pixels from the top-left (texel centres at k + 0.5); nil = the window centre.
    public var centre: SIMD2<Double>?
    /// Core Image: `clampedToExtent()` before filtering. Default false: Core Image's own transparent border.
    public var coreImageClampToExtent: Bool
    /// CIMaskedVariableBlur mask when no mask texture is given.
    public var mask: AppleTwinMask
    public var mpsEdge: AppleTwinMPSEdge
    public var vImageEdge: AppleTwinVImageEdge
    public var vImageStorage: AppleTwinVImageStorage
    public init(angleRadians: Double = 0, centre: SIMD2<Double>? = nil, coreImageClampToExtent: Bool = false,
                mask: AppleTwinMask = .verticalRamp(start: 0, end: 1), mpsEdge: AppleTwinMPSEdge = .zero,
                vImageEdge: AppleTwinVImageEdge = .extend, vImageStorage: AppleTwinVImageStorage = .srgb8) {
        self.angleRadians = angleRadians; self.centre = centre; self.coreImageClampToExtent = coreImageClampToExtent
        self.mask = mask; self.mpsEdge = mpsEdge; self.vImageEdge = vImageEdge; self.vImageStorage = vImageStorage
    }
}

/// What one twin run did, for the status line and the Run log (numbers are badged by the caller: GPU and CPU times are
/// MEASURED on this device; the call text is exact).
public struct AppleTwinRunReport: Sendable, Codable, Hashable {
    public var subject: CalibrationSubject
    public var parameter: Double
    /// The call exactly as issued ("MPSImageBox(kernelWidth: 9, kernelHeight: 9) · edgeMode .zero").
    public var call: String
    public var size: ImageSize
    /// Command-buffer GPU time (gpuEndTime − gpuStartTime) for Core Image and MPS; nil for vImage.
    public var gpuMilliseconds: Double?
    /// Wall time of the CPU convolution for vImage; nil otherwise.
    public var cpuMilliseconds: Double?
    /// vImage only: texels with a channel outside 0…1 before 8-bit quantisation (clipped by the 8-bit format).
    public var clippedTexels: Int
    public var notes: [String]
}

@MainActor
public final class AppleTwinRunner: AppleTwinRunning {
    public init() {}

    /// The last run's report (nil before the first run).
    public private(set) var lastReport: AppleTwinRunReport?

    /// One CIContext per GPUContext (it encodes into our own command buffers on our queue).
    var coreImageCache: (key: ObjectIdentifier, context: CIContext)?

    /// Every subject the runner can run (Core Image, MPS and vImage; the SwiftUI and shadow subjects are CALIBRATION's).
    public static var subjects: [CalibrationSubject] { AppleTwinCatalog.all.map(\.subject) }

    public func supports(_ subject: CalibrationSubject) -> Bool { AppleTwinCatalog.facts(subject) != nil }

    // MARK: AppleTwinRunning

    public func run(_ subject: CalibrationSubject, parameter: Double, input: any MTLTexture, output: any MTLTexture,
                    context: GPUContext) async throws {
        _ = try await run(subject, parameter: parameter, options: AppleTwinOptions(), mask: nil, input: input, output: output,
                          context: context)
    }

    /// Runs the API with its own parameter (`AppleTwinCatalog.facts(subject).parameterName`, in px) on `input`
    /// (window-sized rgba16Float or rgba32Float, linear, premultiplied) into `output` (same size and format).
    /// `mask` (CIMaskedVariableBlur only) overrides `options.mask`; its green channel scales the radius.
    @discardableResult
    public func run(_ subject: CalibrationSubject, parameter: Double, options: AppleTwinOptions, mask: (any MTLTexture)? = nil,
                    input: any MTLTexture, output: any MTLTexture, context: GPUContext) async throws -> AppleTwinRunReport {
        guard let facts = AppleTwinCatalog.facts(subject) else {
            throw GPUError.unsupported("\(subject.title) is measured through ImageRenderer (Calibrate), not as an in-process twin")
        }
        guard parameter.isFinite, parameter >= 0 else { throw GPUError.unsupported("\(subject.title): parameter \(parameter) must be finite and ≥ 0") }
        guard input.width == output.width, input.height == output.height else {
            throw GPUError.unsupported("\(subject.title): output \(output.width)×\(output.height) ≠ input \(input.width)×\(input.height)")
        }
        guard input !== output else { throw GPUError.unsupported("\(subject.title): input and output must be different textures") }
        for (role, texture) in [("input", input), ("output", output)]
        where !AppleTwinRunner.supportedFormats.contains(texture.pixelFormat) {
            throw GPUError.unsupported("\(subject.title): \(role) format \(texture.pixelFormat.rawValue) (rgba16Float or rgba32Float only)")
        }
        let report: AppleTwinRunReport
        switch facts.framework {
        case .coreImage:
            report = try await runCoreImage(subject, parameter: parameter, options: options, mask: mask, input: input,
                                            output: output, context: context)
        case .metalPerformanceShaders:
            report = try await runMPS(subject, parameter: parameter, options: options, input: input, output: output, context: context)
        case .vImage:
            report = try await runVImage(subject, parameter: parameter, options: options, input: input, output: output, context: context)
        }
        lastReport = report
        return report
    }

    static let supportedFormats: Set<MTLPixelFormat> = [.rgba16Float, .rgba32Float]

    // MARK: Shared GPU helpers

    /// `output` itself when the API can write it, otherwise a pooled scratch texture to be blitted into `output`.
    func writableTarget(for output: any MTLTexture, context: GPUContext) throws -> (texture: any MTLTexture, scratch: TextureSpec?) {
        if output.usage.contains(.shaderWrite) && output.usage.contains(.renderTarget) && output.storageMode != .memoryless {
            return (output, nil)
        }
        let format: TextureFormat = output.pixelFormat == .rgba32Float ? .rgba32Float : .rgba16Float
        let spec = TextureSpec(width: output.width, height: output.height, format: format, roles: [.read, .computeWrite, .renderTarget])
        return (try context.texture(spec), spec)
    }

    func makeCommandBuffer(_ context: GPUContext, label: String) throws -> any MTLCommandBuffer {
        guard let cb = context.queue.makeCommandBuffer() else { throw GPUError.encoderUnavailable("command buffer for \(label)") }
        cb.label = label
        return cb
    }

    func encodeCopy(from source: any MTLTexture, to destination: any MTLTexture, commandBuffer: any MTLCommandBuffer) throws {
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { throw GPUError.encoderUnavailable("blit") }
        blit.label = "Apple twin copy"
        blit.copy(from: source, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: source.width, height: source.height, depth: 1), to: destination,
                  destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
    }

    /// Commits and waits; throws the command buffer's error. Returns GPU milliseconds.
    func commitChecked(_ commandBuffer: any MTLCommandBuffer, context: GPUContext) async throws -> Double {
        let done = await context.commit(commandBuffer)
        if let error = done.error { throw GPUError.commandBufferFailed(error) }
        return done.milliseconds
    }

    /// Writes Float RGBA texels into `texture` (rgba16Float or rgba32Float) through a shared staging buffer and a blit.
    func upload(_ texels: [SIMD4<Float>], into texture: any MTLTexture, context: GPUContext) async throws {
        let w = texture.width, h = texture.height
        guard texels.count == w * h else { throw GPUError.unsupported("upload: \(texels.count) texels for \(w)×\(h)") }
        let staging: (any MTLBuffer)?
        let bytesPerPixel: Int
        switch texture.pixelFormat {
        case .rgba32Float:
            bytesPerPixel = 16
            staging = texels.withUnsafeBytes { raw in raw.baseAddress.flatMap { context.device.makeBuffer(bytes: $0, length: raw.count, options: .storageModeShared) } }
        case .rgba16Float:
            bytesPerPixel = 8
            let half = texels.map { SIMD4<Float16>($0) }
            staging = half.withUnsafeBytes { raw in raw.baseAddress.flatMap { context.device.makeBuffer(bytes: $0, length: raw.count, options: .storageModeShared) } }
        default:
            throw GPUError.unsupported("upload: format \(texture.pixelFormat.rawValue)")
        }
        guard let buffer = staging else { throw GPUError.bufferAllocationFailed }
        let cb = try makeCommandBuffer(context, label: "Apple twin upload")
        guard let blit = cb.makeBlitCommandEncoder() else { throw GPUError.encoderUnavailable("blit") }
        blit.copy(from: buffer, sourceOffset: 0, sourceBytesPerRow: w * bytesPerPixel, sourceBytesPerImage: w * h * bytesPerPixel,
                  sourceSize: MTLSize(width: w, height: h, depth: 1), to: texture, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        _ = try await commitChecked(cb, context: context)
    }

    /// A new texture holding `texels` (rgba32Float unless `format` says otherwise), readable by every API.
    func makeTexture(_ texels: [SIMD4<Float>], size: ImageSize, format: TextureFormat = .rgba32Float,
                     context: GPUContext) async throws -> any MTLTexture {
        let texture = try context.texture(TextureSpec(width: size.width, height: size.height, format: format,
                                                      roles: [.read, .computeWrite, .renderTarget]))
        try await upload(texels, into: texture, context: context)
        return texture
    }

    /// A blank output texture for the measurement probes.
    func makeOutput(size: ImageSize, format: TextureFormat = .rgba32Float, context: GPUContext) throws -> any MTLTexture {
        try context.texture(TextureSpec(width: size.width, height: size.height, format: format, roles: [.read, .computeWrite, .renderTarget]))
    }

    static func number(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e9 ? String(Int(value)) : String(format: "%.3g", value)
    }
}
