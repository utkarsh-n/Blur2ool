import Foundation

// FROZEN — ARCHITECTURE.md §5.4. Kernels, PSFs, signed frequency responses and pass plans (SPEC §5).
// Vocabulary (SPEC §17 item 3): `ResponseCurve` holds the SIGNED response H(ν); "MTF" means |H| only.

/// A 1-D kernel. Weights are normalised to sum 1 unless the operator says otherwise.
public struct Kernel1D: Sendable, Codable, Hashable {
    public var weights: [Double]
    /// Index of offset 0 in `weights` (integer-offset kernels).
    public var origin: Int
    /// Fractional sample offsets in texels (linear-sampled kernels); nil for integer offsets `i − origin`.
    public var offsets: [Double]?
    public init(weights: [Double], origin: Int, offsets: [Double]? = nil) {
        precondition(offsets == nil || offsets!.count == weights.count)
        self.weights = weights; self.origin = origin; self.offsets = offsets
    }
    /// Offset of tap i in texels.
    public func offset(_ i: Int) -> Double { offsets?[i] ?? Double(i - origin) }
    public var tapCount: Int { weights.count }
    public var sum: Double { weights.reduce(0, +) }
    public var mean: Double { weights.indices.reduce(0) { $0 + weights[$1] * offset($1) } / sum }
    public var variance: Double {
        let m = mean
        return weights.indices.reduce(0) { $0 + weights[$1] * pow(offset($1) - m, 2) } / sum
    }
    /// Second-moment σ in px (the "σ of the discrete kernel").
    public var sigma: Double { variance.squareRoot() }
    /// Excess kurtosis (Gaussian 0, box −1.2 continuous; SPEC §17 item 4).
    public var excessKurtosis: Double {
        let m = mean, v = variance
        guard v > 0 else { return 0 }
        let m4 = weights.indices.reduce(0) { $0 + weights[$1] * pow(offset($1) - m, 4) } / sum
        return m4 / (v * v) - 3
    }
    public var normalised: Kernel1D { Kernel1D(weights: weights.map { $0 / sum }, origin: origin, offsets: offsets) }
}

/// A 2-D kernel sampled on the pixel grid, row-major, y down.
public struct Kernel2D: Sendable, Codable, Hashable {
    public var width: Int
    public var height: Int
    public var originX: Int
    public var originY: Int
    public var weights: [Double]
    public init(width: Int, height: Int, originX: Int, originY: Int, weights: [Double]) {
        precondition(weights.count == width * height)
        self.width = width; self.height = height; self.originX = originX; self.originY = originY; self.weights = weights
    }
    /// Outer product of two integer-offset 1-D kernels.
    public init(separable h: Kernel1D, _ v: Kernel1D) {
        var w = [Double](repeating: 0, count: h.weights.count * v.weights.count)
        for j in v.weights.indices { for i in h.weights.indices { w[j * h.weights.count + i] = h.weights[i] * v.weights[j] } }
        self.init(width: h.weights.count, height: v.weights.count, originX: h.origin, originY: v.origin, weights: w)
    }
    public subscript(x: Int, y: Int) -> Double { weights[y * width + x] }
    public var sum: Double { weights.reduce(0, +) }
    /// The x marginal (column sums): the line-spread function along x.
    public var marginalX: Kernel1D {
        var m = [Double](repeating: 0, count: width)
        for y in 0..<height { for x in 0..<width { m[x] += self[x, y] } }
        return Kernel1D(weights: m, origin: originX)
    }
    public var marginalY: Kernel1D {
        var m = [Double](repeating: 0, count: height)
        for y in 0..<height { for x in 0..<width { m[y] += self[x, y] } }
        return Kernel1D(weights: m, origin: originY)
    }
}

/// The point-spread function at a point. For LSI blurs it is the same everywhere.
public struct PSF: Sendable, Codable, Hashable {
    public var kernel: Kernel2D
    /// True for LSV and adaptive blurs: valid only at `point`.
    public var isLocal: Bool
    public var point: PixelPoint?
    /// COMPUTED for analytic kernels; LIVE (with `.cpu`) when it depends on the current image (adaptive blurs).
    public var provenance: Provenance
    public init(kernel: Kernel2D, isLocal: Bool, point: PixelPoint?, provenance: Provenance) {
        self.kernel = kernel; self.isLocal = isLocal; self.point = point; self.provenance = provenance
    }
}

public enum ResponseKind: Sendable, Codable, Hashable {
    /// Signed transfer function H(ν) of an LSI kernel along an axis (continuous or of the discrete taps).
    case signedTransfer
    /// Local signed transfer at a point (LSV blurs), along the local PSF's axis.
    case local(PixelPoint)
    /// Amplitude-dependent transfer T(ν, A) of an adaptive blur (NL §0).
    case amplitudeTransfer(amplitude: Double)
}

public struct ResponseQuery: Sendable, Codable, Hashable {
    /// Direction of the frequency axis in degrees (0 = horizontal).
    public var axisDegrees: Double
    public var samples: Int
    /// Highest frequency in cycles per pixel (Nyquist = 0.5).
    public var maxFrequency: Double
    /// For `.local`: the probe; for adaptive blurs: where the local contrast is measured.
    public var point: PixelPoint?
    /// For adaptive blurs: the amplitude A of T(ν, A).
    public var amplitude: Double?
    /// The continuous response (quiet trace) instead of the discrete taps' DFT (primary trace).
    public var continuous: Bool
    public init(axisDegrees: Double = 0, samples: Int = 129, maxFrequency: Double = 0.5, point: PixelPoint? = nil,
                amplitude: Double? = nil, continuous: Bool = false) {
        self.axisDegrees = axisDegrees; self.samples = samples; self.maxFrequency = maxFrequency
        self.point = point; self.amplitude = amplitude; self.continuous = continuous
    }
    /// The evenly spaced frequencies 0 … maxFrequency.
    public var frequencies: [Double] {
        (0..<Swift.max(2, samples)).map { Double($0) * maxFrequency / Double(Swift.max(2, samples) - 1) }
    }
}

public struct ResponseCurve: Sendable, Codable, Hashable {
    public var kind: ResponseKind
    /// Spatial frequency in cycles per pixel.
    public var frequencies: [Double]
    /// Signed H(ν) (or T(ν, A)); 1 at DC for a normalised blur.
    public var values: [Double]
    public var provenance: Provenance
    public init(kind: ResponseKind, frequencies: [Double], values: [Double], provenance: Provenance = .computed) {
        precondition(frequencies.count == values.count)
        self.kind = kind; self.frequencies = frequencies; self.values = values; self.provenance = provenance
    }
    public var minimum: (frequency: Double, value: Double)? {
        guard let i = values.indices.min(by: { values[$0] < values[$1] }) else { return nil }
        return (frequencies[i], values[i])
    }
    public var nyquistValue: Double? { values.last }
    /// First frequency where the curve falls to `level` (linear interpolation): 0.5 → half amplitude,
    /// 1/√2 → −3 dB, 0 → first zero. nil if it never does inside the sampled range.
    public func firstCrossing(of level: Double) -> Double? {
        for i in 1..<values.count where values[i - 1] > level && values[i] <= level {
            let t = (values[i - 1] - level) / (values[i - 1] - values[i])
            return frequencies[i - 1] + t * (frequencies[i] - frequencies[i - 1])
        }
        return nil
    }
}

/// A continuous profile (the pills' and floors' quiet reference trace).
public struct ProfileCurve: Sendable, Codable, Hashable {
    public var label: String
    public var xs: [Double]
    public var ys: [Double]
    public init(label: String, xs: [Double], ys: [Double]) {
        precondition(xs.count == ys.count)
        self.label = label; self.xs = xs; self.ys = ys
    }
}

public enum PassKind: String, Sendable, Codable, Hashable, CaseIterable {
    case fragment, compute, blit, fft, mps, coreImage, cpu
}

/// One pass as the floors, the rail and the cost model describe it (COMPUTED from the operator).
public struct PassDescriptor: Sendable, Codable, Hashable, Identifiable {
    /// Index in the plan (0-based); equals the index of the GPU pass that implements it.
    public var id: Int
    /// Tile label: "H", "V", "↓1", "↑2", "SCAN ROWS", "FFT ROWS".
    public var name: String
    public var kind: PassKind
    /// Texture reads per output pixel after merging (COMPUTED).
    public var fetchesPerPixel: Double
    /// Logical taps per output pixel before merging.
    public var tapsPerPixel: Double
    /// Output resolution relative to the window (1, 0.5, 0.25 …).
    public var outputScale: Double
    /// True when the GPU pass writes TRACE_PROBE records.
    public var traceable: Bool
    public var summary: String
    public init(id: Int, name: String, kind: PassKind, fetchesPerPixel: Double, tapsPerPixel: Double, outputScale: Double = 1,
                traceable: Bool, summary: String) {
        self.id = id; self.name = name; self.kind = kind; self.fetchesPerPixel = fetchesPerPixel; self.tapsPerPixel = tapsPerPixel
        self.outputScale = outputScale; self.traceable = traceable; self.summary = summary
    }
}

public struct PassPlan: Sendable, Codable, Hashable {
    /// The running variant's display name ("Linear-sampled").
    public var algorithmName: String
    public var passes: [PassDescriptor]
    public var notes: [String]
    /// Chebyshev radius in window pixels of everything the whole chain reads for one output pixel (bilinear fetches
    /// add 1), or nil for global operators (FFT, IIR, unbounded iterations). Drives the local parity scale (§7 rule 1)
    /// and the reference-crop apron (§5.5).
    public var supportRadius: Int?
    public init(algorithmName: String, passes: [PassDescriptor], notes: [String] = [], supportRadius: Int? = nil) {
        self.algorithmName = algorithmName; self.passes = passes; self.notes = notes; self.supportRadius = supportRadius
    }
    /// Texture fetches for one frame at `size` (COMPUTED; the budget of review fix E-7).
    public func fetchesPerFrame(_ size: ImageSize) -> Double { fetchesPerPixel * Double(size.pixelCount) }
    /// Logical taps one traced pass can record for one pixel, plus the final (flags = 2) record: the trace capacity.
    public var traceCapacity: Int {
        Swift.max(16, Int((passes.filter(\.traceable).map(\.tapsPerPixel).max() ?? 0).rounded(.up)) + 1)
    }
    /// The status-row phase line with badged numbers ("74 FETCHES · 2 PASSES · LINEAR-SAMPLED").
    public var phase: BadgedLine {
        BadgedLine([.value(.number(fetchesPerPixel.rounded(), .integer(), .computed)), .text("FETCHES ·"),
                    .value(.number(Double(passes.count), .integer(), .computed)),
                    .text((passes.count == 1 ? "PASS · " : "PASSES · ") + algorithmName.uppercased())])
    }
    /// Σ over passes of fetches per output pixel, weighted by each pass's pixel count relative to the window.
    public var fetchesPerPixel: Double { passes.reduce(0) { $0 + $1.fetchesPerPixel * $1.outputScale * $1.outputScale } }
    /// The status-row phase line: "74 FETCHES · 2 PASSES · LINEAR-SAMPLED".
    public var phaseLine: String {
        let f = NumberStyle.integer().text(fetchesPerPixel.rounded())
        let p = passes.count == 1 ? "1 PASS" : "\(passes.count) PASSES"
        return "\(f) FETCHES · \(p) · \(algorithmName.uppercased())"
    }
}

/// Fetches-per-frame budgets (review fix E-7; MODELED from research's M1 Max gather rate scaled to the A17 Pro,
/// UNVERIFIED until This phone measures it). Above `preview`, the preview drops to quarter resolution; above `full`,
/// `resolveVariant` switches to a cheaper variant with its reason, or the parameter range ends there; timing is skipped
/// above `full` (`TOO SLOW TO TIME`). Full renders whose MODELED time exceeds `bandMilliseconds` are split into row
/// bands, one command buffer each.
public enum FetchBudget {
    public static let preview: Double = 2e8
    public static let full: Double = 2e9
    public static let bandMilliseconds: Double = 50
    /// MODELED A17 Pro gather rate (fetches per second), `weakSource`.
    public static let modeledFetchesPerSecond: Double = 15e9
}
