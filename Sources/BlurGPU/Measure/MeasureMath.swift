import Foundation

// OWNER: GPU-MEASURE. Pure math behind the timing protocol and the shape measurement (SPEC §4.1.6, §7.1 item 10;
// research live-calibration §3.3). Nonisolated and Foundation-only, so the moment and response arithmetic runs off the
// main actor and is unit-tested on the CPU (Tests/BlurGPUTests/GPUMEASURE/GPUMEASURE_MathTests.swift).

/// Median and interquartile range of timing samples.
public enum MeasureStatistics {
    /// The type-7 quantile (linear interpolation between order statistics, the R/NumPy default); nil when empty.
    public static func quantile(_ values: [Double], _ q: Double) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard let first = sorted.first else { return nil }
        guard sorted.count > 1 else { return first }
        let h = Swift.min(Swift.max(q, 0), 1) * Double(sorted.count - 1)
        let lo = Int(h.rounded(.down)), hi = Swift.min(lo + 1, sorted.count - 1)
        return sorted[lo] + (h - Double(lo)) * (sorted[hi] - sorted[lo])
    }
    public static func median(_ values: [Double]) -> Double? { quantile(values, 0.5) }
    /// Q3 − Q1 (0 for a single sample).
    public static func iqr(_ values: [Double]) -> Double? {
        guard let q1 = quantile(values, 0.25), let q3 = quantile(values, 0.75) else { return nil }
        return q3 - q1
    }
}

/// Moments of a weighted 1-D distribution (a line-spread function, or a PSF projected onto one direction).
public struct MeasureProfileMoments: Sendable, Hashable {
    public var mass: Double
    public var mean: Double
    public var variance: Double
    /// μ₄ / μ₂² − 3: 0 for a Gaussian, −1.2 for a box, −0.6 for a tent, +3 for a Laplace profile.
    public var excessKurtosis: Double
    public var sigma: Double { variance.squareRoot() }

    /// Moments of `weights` at `positions` (signed weights allowed: sharpening kernels have negative lobes).
    /// nil when the mass is not usable (|mass| below `minimumMass`, or a non-positive variance).
    public init?(weights: [Double], positions: [Double], minimumMass: Double = 1e-12) {
        precondition(weights.count == positions.count)
        let m = weights.reduce(0, +)
        guard abs(m) > minimumMass else { return nil }
        var mean = 0.0
        for (w, x) in zip(weights, positions) { mean += w * x }
        mean /= m
        var m2 = 0.0, m4 = 0.0
        for (w, x) in zip(weights, positions) {
            let d = x - mean, d2 = d * d
            m2 += w * d2; m4 += w * d2 * d2
        }
        m2 /= m; m4 /= m
        guard m2 > 0, m2.isFinite, m4.isFinite else { return nil }
        self.mass = m; self.mean = mean; self.variance = m2; self.excessKurtosis = m4 / (m2 * m2) - 3
    }
}

/// Moments of a sampled 2-D PSF (row-major, `width × height`, pixel centres at i + 0.5).
public struct MeasurePSFMoments: Sendable, Hashable {
    public var mass: Double
    public var centroid: SIMD2<Double>
    /// The x marginal ("on the axis"), the y marginal, and the projections onto the 45° and 135° diagonals.
    public var x: MeasureProfileMoments
    public var y: MeasureProfileMoments
    public var diagonal45: MeasureProfileMoments
    public var diagonal135: MeasureProfileMoments
    /// σ_equiv = √((σx² + σy²) / 2): the per-axis second moment for an isotropic or separable PSF, and the equal-second-
    /// moment size (CATALOG §7 convention) for an anisotropic one.
    public var sigma: Double { ((x.variance + y.variance) / 2).squareRoot() }

    public init?(psf: [Double], width: Int, height: Int) {
        precondition(psf.count == width * height)
        var wx: [Double] = [], px: [Double] = [], wy: [Double] = [], py: [Double] = []
        var wd: [Double] = [], pd: [Double] = [], wa: [Double] = [], pa: [Double] = []
        let s = 0.5.squareRoot()
        for j in 0..<height {
            for i in 0..<width {
                let w = psf[j * width + i]
                guard w != 0 else { continue }
                let u = Double(i) + 0.5, v = Double(j) + 0.5
                wx.append(w); px.append(u); wy.append(w); py.append(v)
                wd.append(w); pd.append((u + v) * s)                 // onto (1, 1)/√2: the 45° diagonal (y down)
                wa.append(w); pa.append((u - v) * s)                 // onto (1, −1)/√2: the 135° diagonal
            }
        }
        guard let x = MeasureProfileMoments(weights: wx, positions: px), let y = MeasureProfileMoments(weights: wy, positions: py),
              let d = MeasureProfileMoments(weights: wd, positions: pd), let a = MeasureProfileMoments(weights: wa, positions: pa) else { return nil }
        self.mass = x.mass; self.centroid = SIMD2(x.mean, y.mean)
        self.x = x; self.y = y; self.diagonal45 = d; self.diagonal135 = a
    }
}

/// Shape arithmetic for ShapeService: marginals, the signed response from a measured PSF (projection–slice theorem),
/// edge spread → line spread, the sinusoidal-star ring response and the stripes' Nyquist response.
public enum MeasureShapeMath {
    /// Projections of a PSF onto the four directions, as (weights, integer positions) on the axis grids:
    /// x, y, and the diagonals s = i + j and d = i − j. The 1-D DFT of each is the 2-D response along that slice.
    public static func slices(psf: [Double], width: Int, height: Int) -> [(weights: [Double], positions: [Double])] {
        var x = [Double](repeating: 0, count: width), y = [Double](repeating: 0, count: height)
        var s = [Double](repeating: 0, count: width + height - 1), d = [Double](repeating: 0, count: width + height - 1)
        for j in 0..<height {
            for i in 0..<width {
                let w = psf[j * width + i]
                x[i] += w; y[j] += w; s[i + j] += w; d[i - j + height - 1] += w
            }
        }
        return [(x, (0..<width).map(Double.init)), (y, (0..<height).map(Double.init)),
                (s, (0..<s.count).map(Double.init)), (d, (0..<d.count).map(Double.init))]
    }

    /// The phase-centred real part of the normalised DFT of a 1-D profile, Σ w cos(2πν(x − x̄)) / Σ w, at each ν
    /// (cycles per grid step). For a symmetric profile this is the signed response H(ν) (KernelMath.response's rule).
    public static func response(weights: [Double], positions: [Double], frequencies: [Double]) -> [Double] {
        let mass = weights.reduce(0, +)
        guard abs(mass) > 1e-12 else { return frequencies.map { _ in .nan } }
        var mean = 0.0
        for (w, x) in zip(weights, positions) { mean += w * x }
        mean /= mass
        return frequencies.map { nu in
            var sum = 0.0
            for (w, x) in zip(weights, positions) where w != 0 { sum += w * cos(2 * Double.pi * nu * (x - mean)) }
            return sum / mass
        }
    }

    /// The smallest signed response over ν ∈ [0, 0.5] cycles per pixel along x, y and both diagonals (the diagonal slices
    /// run to the corner of the Nyquist square). Projection–slice: each slice of the 2-D response is the DFT of the
    /// PSF's projection onto that direction.
    public static func minimumResponse(psf: [Double], width: Int, height: Int, steps: Int = 128) -> Double? {
        let nus = (0...steps).map { 0.5 * Double($0) / Double(steps) }
        var lowest: Double?
        for slice in slices(psf: psf, width: width, height: height) {
            for h in response(weights: slice.weights, positions: slice.positions, frequencies: nus) where h.isFinite {
                lowest = Swift.min(lowest ?? h, h)
            }
        }
        return lowest
    }

    /// Line spread from an edge spread sampled at pixel centres: lsf[i] = esf[i + 1] − esf[i], located at the pixel
    /// boundary between them (continuous position origin + i + 1).
    public static func lineSpread(esf: [Double], origin: Double) -> (weights: [Double], positions: [Double]) {
        guard esf.count > 1 else { return ([], []) }
        let w = (0..<(esf.count - 1)).map { esf[$0 + 1] - esf[$0] }
        return (w, (0..<(esf.count - 1)).map { origin + Double($0 + 1) })
    }

    /// The modulation of an output relative to a zero-mean input pattern: Σ (o − ō)·s / Σ s². For a sinusoid (or the
    /// ±½ stripes) through an LSI blur this is the signed response at the pattern's frequency; negative = inverted.
    public static func modulation(output: [Double], pattern: [Double]) -> Double? {
        guard output.count == pattern.count, !output.isEmpty else { return nil }
        let mean = output.reduce(0, +) / Double(output.count)
        var num = 0.0, den = 0.0
        for (o, s) in zip(output, pattern) { num += (o - mean) * s; den += s * s }
        return den > 0 ? num / den : nil
    }

    /// The 36-cycle sinusoidal star used for the ring response: ½ + ½ cos(36θ) about the centre of pixel `centre`
    /// (SPEC §11 rule 2: the continuous centre of radial images is c + (0.5, 0.5)). Returns the zero-mean pattern value.
    public static func starPattern(_ i: Int, _ j: Int, centreX: Int, centreY: Int, cycles: Double = 36) -> Double {
        let dx = Double(i - centreX), dy = Double(j - centreY)
        guard dx != 0 || dy != 0 else { return 0 }
        return 0.5 * cos(cycles * atan2(dy, dx))
    }

    /// Ring frequency of the star: `cycles` periods around a ring of radius r pixels = cycles / (2πr) cycles per pixel.
    public static func starFrequency(radius: Double, cycles: Double = 36) -> Double { cycles / (2 * Double.pi * radius) }
}
