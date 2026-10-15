import Foundation
import Synchronization

// OWNER: TESTIMAGES. Raster helpers shared by the generators: window-coordinate frames, row-parallel filling (pixels are
// independent, so the result is bit-identical whatever the thread count), 4 × 4 supersampled coverage (SPEC §11 rule 2), and
// the canonical byte stream whose SHA-256 the Mac and the phone compare (review fix E-22).

/// The coordinate frame of one canvas: window coordinates (y down) with the window centre c; canvas pixel (i, j) is window
/// pixel (i − margin, j − margin). Pixel values are evaluated at pixel centres (x + 0.5, y + 0.5); radial images are centred
/// on the continuous point c + (0.5, 0.5) (SPEC §11 rule 2).
public struct SpecimenFrame: Sendable, Hashable {
    public let windowSize: Int
    public let margin: Int
    public var side: Int { windowSize + 2 * margin }
    /// c = (⌊N/2⌋, ⌊N/2⌋).
    public var c: PixelPoint { SpecimenGeometry.centre(windowSize: windowSize) }
    /// The continuous centre c + (0.5, 0.5).
    public var centre: SIMD2<Double> { SIMD2(Double(c.x) + 0.5, Double(c.y) + 0.5) }
    public init(windowSize: Int, margin: Int) { self.windowSize = windowSize; self.margin = margin }

    /// Window pixel of canvas pixel (i, j).
    @inline(__always) public func window(_ i: Int, _ j: Int) -> (x: Int, y: Int) { (i - margin, j - margin) }
    /// Canvas pixel of window pixel (x, y).
    @inline(__always) public func canvas(_ x: Int, _ y: Int) -> (i: Int, j: Int) { (x + margin, y + margin) }
    /// A window point relative to c.
    public func relative(_ dx: Int, _ dy: Int) -> PixelPoint { PixelPoint(x: c.x + dx, y: c.y + dy) }
}

/// Collects the row bands computed in parallel (a Mutex, so no unchecked Sendable is needed).
final class SpecimenBandCollector<T: Sendable>: Sendable {
    private let bands: Mutex<[[T]]>
    init(count: Int) { bands = Mutex(Array(repeating: [], count: count)) }
    func store(_ rows: [T], at band: Int) { bands.withLock { $0[band] = rows } }
    func joined(capacity: Int) -> [T] {
        bands.withLock { all in
            var out = [T]()
            out.reserveCapacity(capacity)
            for b in all { out.append(contentsOf: b) }
            return out
        }
    }
}

public enum SpecimenRaster {
    /// The sixteen supersample offsets (i + 0.5)/4 inside a pixel, i = 0…3 (exact binary fractions).
    public static let subOffsets: [Double] = [0.125, 0.375, 0.625, 0.875]

    /// Evaluates `value(x, y)` (WINDOW coordinates) for every canvas pixel, row-major, in parallel row bands. Every pixel is
    /// independent and computed by the same code, so the result is bit-identical whatever the scheduling. The closure must
    /// be pure (it is Sendable: it captures only values).
    public static func rows<T: Sendable>(_ frame: SpecimenFrame, _ value: @Sendable (Int, Int) -> T) -> [T] {
        let side = frame.side, m = frame.margin
        let bandCount = Swift.min(side, 48)
        let collector = SpecimenBandCollector<T>(count: bandCount)
        DispatchQueue.concurrentPerform(iterations: bandCount) { band in
            let y0 = band * side / bandCount, y1 = (band + 1) * side / bandCount
            var local = [T]()
            local.reserveCapacity((y1 - y0) * side)
            for j in y0..<y1 { for i in 0..<side { local.append(value(i - m, j - m)) } }
            collector.store(local, at: band)
        }
        return collector.joined(capacity: side * side)
    }

    /// An RGBA canvas (linear light, premultiplied).
    public static func render(_ frame: SpecimenFrame, _ pixel: @Sendable (Int, Int) -> SIMD4<Float>) -> ImageBuffer {
        ImageBuffer(width: frame.side, height: frame.side, pixels: rows(frame, pixel))
    }

    /// A scalar canvas (depth, mask, coverage).
    public static func scalar(_ frame: SpecimenFrame, _ value: @Sendable (Int, Int) -> Float) -> ScalarBuffer {
        ScalarBuffer(width: frame.side, height: frame.side, values: rows(frame, value))
    }

    /// A two-channel canvas (velocity, px per frame).
    public static func vector(_ frame: SpecimenFrame, _ value: @Sendable (Int, Int) -> SIMD2<Float>) -> VectorBuffer {
        VectorBuffer(width: frame.side, height: frame.side, values: rows(frame, value))
    }

    /// Fraction of the 4 × 4 supersample points of window pixel (x, y) for which `inside(px, py)` holds (exactly k/16).
    @inline(__always)
    public static func coverage(_ x: Int, _ y: Int, _ inside: (Double, Double) -> Bool) -> Float {
        var hits = 0
        for sy in subOffsets {
            let py = Double(y) + sy
            for sx in subOffsets where inside(Double(x) + sx, py) { hits += 1 }
        }
        return Float(hits) * (1.0 / 16.0)
    }

    /// Mean of `value(px, py)` over the 4 × 4 supersample points (the star, the aerial checker).
    @inline(__always)
    public static func supersample(_ x: Int, _ y: Int, _ value: (Double, Double) -> Double) -> Double {
        var sum = 0.0
        for sy in subOffsets {
            let py = Double(y) + sy
            for sx in subOffsets { sum += value(Double(x) + sx, py) }
        }
        return sum * (1.0 / 16.0)
    }

    /// Coverage of a disc of `radius` about the continuous point `centre`, with a fast path: pixels whose centre is more than
    /// 0.75 px from the rim (the supersample points lie within 0.53 px of it) are fully in or out, so the result equals the
    /// full 4 × 4 supersample bit for bit.
    @inline(__always)
    public static func discCoverage(_ x: Int, _ y: Int, centre: SIMD2<Double>, radius: Double) -> Float {
        let dx = Double(x) + 0.5 - centre.x, dy = Double(y) + 0.5 - centre.y
        let d = (dx * dx + dy * dy).squareRoot()
        if d < radius - 0.75 { return 1 }
        if d > radius + 0.75 { return 0 }
        let r2 = radius * radius
        return coverage(x, y) { px, py in
            let ex = px - centre.x, ey = py - centre.y
            return ex * ex + ey * ey <= r2
        }
    }

    /// A linear value of an SDR test image for storage: clipped to [0, 1] like a sensor (light is never negative, and only
    /// the HDR images carry values above 1).
    @inline(__always) public static func sdr(_ v: Double) -> Float { Float(Swift.min(1, Swift.max(0, v))) }
    /// An opaque grey pixel.
    @inline(__always) public static func grey(_ v: Float) -> SIMD4<Float> { SIMD4(v, v, v, 1) }
}

// MARK: - Canonical bytes (the SHA-256 the phone AppTest compares with the Mac, review fix E-22)

public extension SpecimenCanvas {
    /// The canvas as a canonical byte stream, chunk by chunk: a UTF-8 header (id, window size, margin, default probe,
    /// backdrop and caption), then the image's Float32 RGBA bit patterns little-endian, row-major, then every auxiliary
    /// buffer that is present in the fixed order depth, velocity, guide, mask, sub-frames, noise seed. Both targets
    /// (arm64 macOS and arm64 iOS) are little-endian, so the in-memory bytes are the canonical ones. Callers feed the chunks
    /// to SHA-256 (CryptoKit in the tests; BlurCore stays Foundation-only).
    func forEachCanonicalChunk(_ body: (UnsafeRawBufferPointer) -> Void) {
        func bits(_ f: Float) -> String { String(f.bitPattern, radix: 16) }
        let b = backdrop
        let header = "B2CANVAS v1|\(id.rawValue)|N=\(windowSize)|m=\(margin)|probe=\(defaultProbe.x),\(defaultProbe.y)|"
            + "backdrop=\(bits(b.x)),\(bits(b.y)),\(bits(b.z)),\(bits(b.w))|caption=\(caption ?? "")|"
            + "image=\(image.width)x\(image.height)|"
            + "depth=\(auxiliary.depth != nil)|velocity=\(auxiliary.velocity != nil)|guide=\(auxiliary.guide != nil)|"
            + "mask=\(auxiliary.mask != nil)|subFrames=\(auxiliary.subFrames?.count ?? 0)|seed=\(auxiliary.noiseSeed)"
        Array(header.utf8).withUnsafeBytes(body)
        image.pixels.withUnsafeBytes(body)
        auxiliary.depth?.values.withUnsafeBytes(body)
        auxiliary.velocity?.values.withUnsafeBytes(body)
        auxiliary.guide?.pixels.withUnsafeBytes(body)
        auxiliary.mask?.values.withUnsafeBytes(body)
        for frame in auxiliary.subFrames ?? [] { frame.pixels.withUnsafeBytes(body) }
    }

    /// Total length of the canonical stream (for logs).
    var canonicalByteCount: Int {
        var n = 0
        forEachCanonicalChunk { n += $0.count }
        return n
    }
}
