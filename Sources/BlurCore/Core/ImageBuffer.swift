import Foundation

// FROZEN — ARCHITECTURE.md §5.4. CPU image buffers for references, specimens and measurement (ARCHITECTURE §4.1).
// Requires arm64 (Float16). BlurCore never imports CoreGraphics, Metal or UI frameworks.

/// Linear light, premultiplied RGBA, row-major, y down. Values above 1 are allowed (HDR lights).
public struct ImageBuffer: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var pixels: [SIMD4<Float>]

    public init(width: Int, height: Int, fill: SIMD4<Float> = .zero) {
        precondition(width > 0 && height > 0)
        self.width = width; self.height = height
        pixels = Array(repeating: fill, count: width * height)
    }
    public init(width: Int, height: Int, pixels: [SIMD4<Float>]) {
        precondition(width > 0 && height > 0 && pixels.count == width * height)
        self.width = width; self.height = height; self.pixels = pixels
    }

    public var size: ImageSize { ImageSize(width: width, height: height) }

    public subscript(x: Int, y: Int) -> SIMD4<Float> {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }

    /// Integer fetch with the shared edge mapping (`b2_fetch`). `renormalise` and `zero` return transparent black here;
    /// FIR operators implement weight renormalisation themselves.
    public func fetch(_ x: Int, _ y: Int, edge: EdgeMode) -> SIMD4<Float> {
        guard let mx = edge.map(x, count: width), let my = edge.map(y, count: height) else { return .zero }
        return self[mx, my]
    }

    /// Bilinear sample at texel coordinates (texel centres at i + 0.5), computed in Double, matching `b2_sample`.
    /// `subTexelBits` and `rounding` emulate the hardware's fraction quantization (8 bits, nearest: MEASURED on the
    /// M1 Max only; ReferenceOptions.forDevice supplies this phone's rule); nil = exact fractions. `renormalise`
    /// behaves as `clamp` for filtered fetches (ARCHITECTURE §4.3).
    public func bilinear(_ u: Double, _ v: Double, edge: EdgeMode, subTexelBits: Int? = nil,
                         rounding: SubTexelRounding = .nearest) -> SIMD4<Double> {
        let mode: EdgeMode = edge == .renormalise ? .clamp : edge
        let x = u - 0.5, y = v - 0.5
        let x0 = Int(floor(x)), y0 = Int(floor(y))
        var fx = x - Double(x0), fy = y - Double(y0)
        if let bits = subTexelBits {
            let scale = Double(1 << bits)
            let rule: FloatingPointRoundingRule = rounding == .nearest ? .toNearestOrAwayFromZero : .towardZero
            fx = (fx * scale).rounded(rule) / scale
            fy = (fy * scale).rounded(rule) / scale
        }
        func f(_ i: Int, _ j: Int) -> SIMD4<Double> { SIMD4<Double>(fetch(i, j, edge: mode)) }
        let top = f(x0, y0) * (1 - fx) + f(x0 + 1, y0) * fx
        let bottom = f(x0, y0 + 1) * (1 - fx) + f(x0 + 1, y0 + 1) * fx
        return top * (1 - fy) + bottom * fy
    }

    /// Emulates `rgba16Float` storage: every channel rounded to the nearest half (what the GPU stores and samples).
    public func roundedToHalf() -> ImageBuffer {
        ImageBuffer(width: width, height: height, pixels: pixels.map { p in
            SIMD4<Float>(HalfFloat.round(p.x), HalfFloat.round(p.y), HalfFloat.round(p.z), HalfFloat.round(p.w))
        })
    }

    /// A region copied with the given edge mapping for out-of-range pixels.
    public func crop(_ region: PixelRegion, edge: EdgeMode = .clamp) -> ImageBuffer {
        var out = ImageBuffer(width: region.size.width, height: region.size.height)
        for y in 0..<region.size.height {
            for x in 0..<region.size.width { out[x, y] = fetch(region.origin.x + x, region.origin.y + y, edge: edge) }
        }
        return out
    }

    public func map(_ transform: (SIMD4<Float>) -> SIMD4<Float>) -> ImageBuffer {
        ImageBuffer(width: width, height: height, pixels: pixels.map(transform))
    }

    /// Every channel × `gain` (exposure 2^EV at render time; exact in fp16 for powers of two away from subnormals).
    public func scaled(by gain: Float) -> ImageBuffer { map { $0 * gain } }

    /// The CPU twin of the frozen preview downsample `b2_common_downsample2x_fs`: output (x, y) = mean of input
    /// (2x…2x+1, 2y…2y+1), edge-clamped for odd sizes; output size ⌊w/2⌋ × ⌊h/2⌋ (review fix E-4).
    public func downsampled2x() -> ImageBuffer {
        let w = Swift.max(1, width / 2), h = Swift.max(1, height / 2)
        var out = ImageBuffer(width: w, height: h)
        for y in 0..<h {
            for x in 0..<w {
                let a = fetch(2 * x, 2 * y, edge: .clamp), b = fetch(2 * x + 1, 2 * y, edge: .clamp)
                let c = fetch(2 * x, 2 * y + 1, edge: .clamp), d = fetch(2 * x + 1, 2 * y + 1, edge: .clamp)
                out[x, y] = ((a + b) + (c + d)) * 0.25
            }
        }
        return out
    }

    /// Largest channel magnitude of each pixel (for the local parity scale, ARCHITECTURE §7 rule 1).
    public var magnitudes: [Float] { pixels.map { Swift.max(Swift.max(abs($0.x), abs($0.y)), Swift.max(abs($0.z), abs($0.w))) } }
}

/// fp16 RGBA texel bytes ready for upload (review fix E-9): the conversion runs in BlurCore, off the main actor
/// (in the canvas task), and only this Sendable value reaches `GPUContext.upload`.
public struct HalfImageData: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// width × height × 4 Float16 values, row-major (8 bytes per texel).
    public let bytes: Data
    public init(_ image: ImageBuffer) {
        width = image.width; height = image.height
        let halves = image.pixels.map { SIMD4<Float16>($0) }
        bytes = halves.withUnsafeBytes { Data($0) }
    }
    public var bytesPerRow: Int { width * MemoryLayout<SIMD4<Float16>>.stride }
}

/// Single-channel buffers for masks, depth and text coverage.
public struct ScalarBuffer: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var values: [Float]
    public init(width: Int, height: Int, values: [Float]) {
        precondition(values.count == width * height)
        self.width = width; self.height = height; self.values = values
    }
    public subscript(x: Int, y: Int) -> Float { values[y * width + x] }
}

/// Two-channel buffers for velocity fields (px per frame).
public struct VectorBuffer: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var values: [SIMD2<Float>]
    public init(width: Int, height: Int, values: [SIMD2<Float>]) {
        precondition(values.count == width * height)
        self.width = width; self.height = height; self.values = values
    }
}

/// Extra inputs some blurs need (depth, velocity, guide image, mask, sub-frames, noise seed). Window-sized.
public struct AuxiliaryInputs: Sendable, Equatable {
    public var depth: ScalarBuffer?
    public var velocity: VectorBuffer?
    public var guide: ImageBuffer?
    public var mask: ScalarBuffer?
    public var subFrames: [ImageBuffer]?
    public var noiseSeed: UInt32
    public init(depth: ScalarBuffer? = nil, velocity: VectorBuffer? = nil, guide: ImageBuffer? = nil, mask: ScalarBuffer? = nil,
                subFrames: [ImageBuffer]? = nil, noiseSeed: UInt32 = 1) {
        self.depth = depth; self.velocity = velocity; self.guide = guide; self.mask = mask
        self.subFrames = subFrames; self.noiseSeed = noiseSeed
    }
    public static let none = AuxiliaryInputs()
}

/// GPU-vs-CPU and A-vs-B difference statistics over all four channels.
public struct DifferenceStats: Sendable, Codable, Hashable {
    public var maxAbs: Double
    public var rms: Double
    /// Pixel (in the compared region's own coordinates) where |a − b| is largest.
    public var argmax: PixelPoint
    /// The largest difference in 8-bit sRGB code steps (both values clipped to 0…1 and encoded).
    public var maxLSB8: Double
    /// The largest difference in fp16 ulps of the reference value (ulp floor at 2⁻¹⁴).
    public var maxULP16: Double
    public var count: Int
    public init(maxAbs: Double, rms: Double, argmax: PixelPoint, maxLSB8: Double, maxULP16: Double, count: Int) {
        self.maxAbs = maxAbs; self.rms = rms; self.argmax = argmax; self.maxLSB8 = maxLSB8; self.maxULP16 = maxULP16; self.count = count
    }

    /// Compares `measured` against `reference` (same size) over the whole image.
    public static func compare(_ measured: ImageBuffer, _ reference: ImageBuffer) -> DifferenceStats {
        precondition(measured.width == reference.width && measured.height == reference.height)
        var maxAbs = 0.0, sumSq = 0.0, maxLSB = 0.0, maxULP = 0.0
        var arg = PixelPoint.zero
        for y in 0..<reference.height {
            for x in 0..<reference.width {
                let a = measured[x, y], b = reference[x, y]
                for c in 0..<4 {
                    let d = abs(Double(a[c]) - Double(b[c]))
                    sumSq += d * d
                    if d > maxAbs { maxAbs = d; arg = PixelPoint(x: x, y: y) }
                    if c < 3 { maxLSB = Swift.max(maxLSB, Double(abs(SRGB.code8(linear: Double(a[c])) - SRGB.code8(linear: Double(b[c]))))) }
                    maxULP = Swift.max(maxULP, d / Double(HalfFloat.ulp(Swift.max(abs(b[c]), 1.0 / 16384))))
                }
            }
        }
        let n = reference.width * reference.height * 4
        return DifferenceStats(maxAbs: maxAbs, rms: (sumSq / Double(n)).squareRoot(), argmax: arg, maxLSB8: maxLSB,
                               maxULP16: maxULP, count: reference.width * reference.height)
    }
}
