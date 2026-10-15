import Foundation
import Metal
import Accelerate
import BlurCore

// OWNER: APPLE-TWINS. The vImage twins. Accelerate's box and tent convolutions exist only for 8-bit pixels
// (vImageBoxConvolve_Planar8 / _ARGB8888, vImageTentConvolve_Planar8 / _ARGB8888 in the iOS 27 SDK), so the twin stores the
// window in an 8-bit RGBA buffer the way 8-bit images hold colour (sRGB-encoded, premultiplied; or linear 8-bit on request),
// convolves it on the CPU with the kernel 2·round(r) + 1 and the edge flag the caller chose (vImage has no default), and
// writes the result back to the output texture in linear light. Values outside 0…1 clip at quantisation: that is a
// property of the 8-bit API, and the run report counts the clipped texels.

/// The pure, Sendable half of the vImage twin (also used by the tests to check vImage against an exact integer box).
public enum AppleTwinVImage {
    public struct Job: Sendable, Hashable {
        public var tent: Bool
        /// Odd kernel width and height.
        public var kernel: Int
        public var edge: AppleTwinVImageEdge
        public var storage: AppleTwinVImageStorage
        public init(tent: Bool, kernel: Int, edge: AppleTwinVImageEdge, storage: AppleTwinVImageStorage) {
            self.tent = tent; self.kernel = kernel; self.edge = edge; self.storage = storage
        }
    }

    public static func flags(_ edge: AppleTwinVImageEdge) -> vImage_Flags {
        switch edge {
        case .extend: vImage_Flags(kvImageEdgeExtend)
        case .truncateKernel: vImage_Flags(kvImageTruncateKernel)
        case .backgroundFill: vImage_Flags(kvImageBackgroundColorFill)
        }
    }

    public static func flagName(_ edge: AppleTwinVImageEdge) -> String {
        switch edge {
        case .extend: "kvImageEdgeExtend"
        case .truncateKernel: "kvImageTruncateKernel"
        case .backgroundFill: "kvImageBackgroundColorFill (0, 0, 0, 0)"
        }
    }

    /// Premultiplied linear RGBA → interleaved 8-bit RGBA in `storage`, and the number of texels with a channel that clipped.
    public static func quantise(_ texels: [SIMD4<Float>], storage: AppleTwinVImageStorage) -> (bytes: [UInt8], clipped: Int) {
        var bytes = [UInt8](repeating: 0, count: texels.count * 4)
        var clipped = 0
        @inline(__always) func q(_ v: Double) -> UInt8 { UInt8(Swift.min(Swift.max(v, 0), 1) * 255 + 0.5) }
        for (i, p) in texels.enumerated() {
            let alpha = Double(p.w)
            switch storage {
            case .linear8:
                if p.x < 0 || p.y < 0 || p.z < 0 || p.w < 0 || p.x > 1 || p.y > 1 || p.z > 1 || p.w > 1 { clipped += 1 }
                bytes[4 * i] = q(Double(p.x)); bytes[4 * i + 1] = q(Double(p.y)); bytes[4 * i + 2] = q(Double(p.z)); bytes[4 * i + 3] = q(alpha)
            case .srgb8:
                let a = Swift.min(Swift.max(alpha, 0), 1)
                guard a > 0 else { if p.x != 0 || p.y != 0 || p.z != 0 { clipped += 1 }; continue }
                let straight = SIMD3<Double>(Double(p.x), Double(p.y), Double(p.z)) / a
                if straight.min() < 0 || straight.max() > 1 || alpha > 1 || alpha < 0 { clipped += 1 }
                for c in 0..<3 { bytes[4 * i + c] = q(SRGB.encode(Swift.min(Swift.max(straight[c], 0), 1)) * a) }
                bytes[4 * i + 3] = q(a)
            }
        }
        return (bytes, clipped)
    }

    /// Interleaved 8-bit RGBA in `storage` → premultiplied linear RGBA.
    public static func dequantise(_ bytes: [UInt8], storage: AppleTwinVImageStorage) -> [SIMD4<Float>] {
        let count = bytes.count / 4
        var out = [SIMD4<Float>](repeating: .zero, count: count)
        for i in 0..<count {
            let v = SIMD4<Double>(Double(bytes[4 * i]), Double(bytes[4 * i + 1]), Double(bytes[4 * i + 2]), Double(bytes[4 * i + 3])) / 255
            switch storage {
            case .linear8:
                out[i] = SIMD4<Float>(v)
            case .srgb8:
                guard v.w > 0 else { continue }
                var linear = SIMD4<Double>(0, 0, 0, v.w)
                for c in 0..<3 { linear[c] = SRGB.decode(Swift.min(v[c] / v.w, 1)) * v.w }
                out[i] = SIMD4<Float>(linear)
            }
        }
        return out
    }

    /// vImage box or tent convolve on interleaved 4-channel 8-bit pixels (`vImage…Convolve_ARGB8888`, which treats the
    /// four channels alike, so the RGBA order is immaterial).
    public static func convolve4(_ bytes: [UInt8], width: Int, height: Int, job: Job) throws -> [UInt8] {
        try convolve(bytes, width: width, height: height, channels: 4, job: job)
    }

    /// vImage box or tent convolve on one 8-bit plane (`vImage…Convolve_Planar8`).
    public static func convolvePlanar(_ bytes: [UInt8], width: Int, height: Int, job: Job) throws -> [UInt8] {
        try convolve(bytes, width: width, height: height, channels: 1, job: job)
    }

    static func convolve(_ bytes: [UInt8], width: Int, height: Int, channels: Int, job: Job) throws -> [UInt8] {
        guard job.kernel > 0, job.kernel % 2 == 1 else { throw GPUError.unsupported("vImage kernel \(job.kernel) must be odd") }
        guard bytes.count == width * height * channels else { throw GPUError.unsupported("vImage buffer size") }
        var source = bytes
        var destination = [UInt8](repeating: 0, count: bytes.count)
        let k = UInt32(job.kernel), flags = flags(job.edge)
        let error: vImage_Error = source.withUnsafeMutableBytes { src in
            destination.withUnsafeMutableBytes { dst in
                var s = vImage_Buffer(data: src.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width),
                                      rowBytes: width * channels)
                var d = vImage_Buffer(data: dst.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width),
                                      rowBytes: width * channels)
                if channels == 1 {
                    return job.tent ? vImageTentConvolve_Planar8(&s, &d, nil, 0, 0, k, k, 0, flags)
                                    : vImageBoxConvolve_Planar8(&s, &d, nil, 0, 0, k, k, 0, flags)
                }
                var background: [UInt8] = [0, 0, 0, 0]
                return background.withUnsafeMutableBufferPointer { bg in
                    job.tent ? vImageTentConvolve_ARGB8888(&s, &d, nil, 0, 0, k, k, bg.baseAddress, flags)
                             : vImageBoxConvolve_ARGB8888(&s, &d, nil, 0, 0, k, k, bg.baseAddress, flags)
                }
            }
        }
        guard error == kvImageNoError else { throw GPUError.unsupported("vImage convolve failed with error \(error)") }
        return destination
    }

    /// The whole CPU half of a run: quantise → convolve → dequantise. Returns texels, clipped count and wall milliseconds.
    public static func blur(_ texels: [SIMD4<Float>], width: Int, height: Int, job: Job) throws
        -> (texels: [SIMD4<Float>], clipped: Int, milliseconds: Double) {
        let q = quantise(texels, storage: job.storage)
        let start = DispatchTime.now().uptimeNanoseconds
        let blurred = try convolve4(q.bytes, width: width, height: height, job: job)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        return (dequantise(blurred, storage: job.storage), q.clipped, ms)
    }
}

extension AppleTwinRunner {
    func runVImage(_ subject: CalibrationSubject, parameter: Double, options: AppleTwinOptions, input: any MTLTexture,
                   output: any MTLTexture, context: GPUContext) async throws -> AppleTwinRunReport {
        guard subject == .vImageBox || subject == .vImageTent else { throw GPUError.unsupported("\(subject.title) is not a vImage twin") }
        let w = input.width, h = input.height
        let texels = try await context.readTexels(input, region: PixelRegion(origin: .zero, size: ImageSize(width: w, height: h)))
        let job = AppleTwinVImage.Job(tent: subject == .vImageTent, kernel: AppleTwinCatalog.kernelWidth(halfWidth: parameter),
                                      edge: options.vImageEdge, storage: options.vImageStorage)
        let result = try await Task.detached(priority: .userInitiated) {
            try AppleTwinVImage.blur(texels, width: w, height: h, job: job)
        }.value
        try await upload(result.texels, into: output, context: context)
        let function = job.tent ? "vImageTentConvolve_ARGB8888" : "vImageBoxConvolve_ARGB8888"
        var notes = [options.vImageStorage == .srgb8
                     ? "8-bit sRGB-encoded premultiplied buffer: vImage averages encoded values"
                     : "8-bit linear buffer: vImage averages linear light in 8-bit steps"]
        if result.clipped > 0 { notes.append("\(result.clipped) texels clipped to 0…1 by the 8-bit format") }
        if Double(Int(parameter.rounded())) != parameter {
            notes.append("half-width \(AppleTwinRunner.number(parameter)) rounded to \(Int(parameter.rounded())) (kernel sizes are odd integers)")
        }
        return AppleTwinRunReport(subject: subject, parameter: parameter,
                                  call: "\(function)(…, kernel_height: \(job.kernel), kernel_width: \(job.kernel), …, \(AppleTwinVImage.flagName(job.edge)))",
                                  size: ImageSize(width: w, height: h), gpuMilliseconds: nil, cpuMilliseconds: result.milliseconds,
                                  clippedTexels: result.clipped, notes: notes)
    }
}
