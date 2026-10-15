import Foundation

// FROZEN — ARCHITECTURE.md §5.4. Shared kernel math, implemented once (the skeleton copies this file verbatim) and
// pinned by the SPEC §5.3 fixtures in Tests/BlurCoreTests/SKEL/. Family-specific math lives in the family's folder.

/// One side of a symmetric linear-sampled table (Rákos 2010): index 0 is the centre tap, then one entry per merged pair.
public struct LinearSampledTable: Sendable, Codable, Hashable {
    public var offsets: [Double]
    public var weights: [Double]
    public init(offsets: [Double], weights: [Double]) { self.offsets = offsets; self.weights = weights }
    /// Texture fetches per output pixel per pass: the centre plus two per entry.
    public var fetchesPerPass: Int { 1 + 2 * Swift.max(0, offsets.count - 1) }
}

public enum KernelMath {
    /// Radius of a truncated Gaussian: max(3, ⌈k·σ⌉) taps on each side (k = truncation, default 3).
    public static func gaussianRadius(sigma: Double, truncation k: Double = 3) -> Int {
        Swift.max(3, Int((k * sigma - 1e-9).rounded(.up)))
    }

    /// Sampled Gaussian exp(−n²/2σ²), cut at the radius and renormalised to sum 1 (SPEC §5.3 A, `Sampled`).
    public static func gaussianSampled(sigma: Double, truncation k: Double = 3) -> Kernel1D {
        let r = gaussianRadius(sigma: sigma, truncation: k)
        let w = (-r...r).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        return Kernel1D(weights: w, origin: r).normalised
    }

    /// Pixel-integrated Gaussian Φ((n+½)/σ) − Φ((n−½)/σ), cut and renormalised (`Integrated`).
    public static func gaussianIntegrated(sigma: Double, truncation k: Double = 3) -> Kernel1D {
        let r = gaussianRadius(sigma: sigma, truncation: k)
        let w = (-r...r).map { normalCDF((Double($0) + 0.5) / sigma) - normalCDF((Double($0) - 0.5) / sigma) }
        return Kernel1D(weights: w, origin: r).normalised
    }

    /// Lindeberg's discrete Gaussian e^(−t)·I_n(t) with t = σ² (its variance is exactly t before the cut),
    /// cut and renormalised (`Lindeberg`). Scaled Bessel values by Miller's backward recurrence.
    public static func gaussianLindeberg(sigma: Double, truncation k: Double = 3) -> Kernel1D {
        let r = gaussianRadius(sigma: sigma, truncation: k)
        let scaled = scaledBesselI(upTo: r, t: sigma * sigma)
        let w = (-r...r).map { scaled[abs($0)] }
        return Kernel1D(weights: w, origin: r).normalised
    }

    /// Box of 2r + 1 equal taps.
    public static func box(radius r: Int) -> Kernel1D {
        Kernel1D(weights: Array(repeating: 1 / Double(2 * r + 1), count: 2 * r + 1), origin: r)
    }

    /// Tent (triangle) of half-width r + 1: weights ∝ (r + 1 − |n|), |n| ≤ r; σ² = r(r + 2)/6 (SPEC §8.1).
    public static func tent(radius r: Int) -> Kernel1D {
        Kernel1D(weights: (-r...r).map { Double(r + 1 - abs($0)) }, origin: r).normalised
    }

    /// Binomial (Pascal) kernel of order n (n + 1 taps, σ² = n/4); n must be even for a centred kernel.
    public static func binomial(order n: Int) -> Kernel1D {
        var row = [1.0]
        for _ in 0..<n { row = zip(row + [0], [0] + row).map { $0 + $1 } }
        return Kernel1D(weights: row, origin: n / 2).normalised
    }

    /// Discrete convolution of two integer-offset kernels.
    public static func convolve(_ a: Kernel1D, _ b: Kernel1D) -> Kernel1D {
        var w = [Double](repeating: 0, count: a.tapCount + b.tapCount - 1)
        for i in a.weights.indices { for j in b.weights.indices { w[i + j] += a.weights[i] * b.weights[j] } }
        return Kernel1D(weights: w, origin: a.origin + b.origin)
    }

    /// Rákos pairing of a symmetric, integer-offset kernel: taps (1,2), (3,4), … merge into one bilinear fetch each at
    /// offset (k·w_k + (k+1)·w_(k+1)) / (w_k + w_(k+1)) with weight w_k + w_(k+1); an odd last tap stays alone.
    public static func linearSampledTable(_ k: Kernel1D) -> LinearSampledTable {
        let r = k.origin
        precondition(k.offsets == nil && k.tapCount == 2 * r + 1, "linearSampledTable needs a centred integer-offset kernel")
        var offsets = [0.0], weights = [k.weights[r]]
        var n = 1
        while n <= r {
            let w1 = k.weights[r + n], w2 = n + 1 <= r ? k.weights[r + n + 1] : 0
            let sum = w1 + w2
            offsets.append(sum > 0 ? (Double(n) * w1 + Double(n + 1) * w2) / sum : Double(n))
            weights.append(sum)
            n += 2
        }
        return LinearSampledTable(offsets: offsets, weights: weights)
    }

    /// Signed response of a 1-D kernel, phase-centred on its centroid: Re Σ wᵢ e^(−2πiν(xᵢ − x̄)).
    /// Equals H(ν) for symmetric kernels; for asymmetric kernels it is the zero-phase real part (state so on screen).
    public static func response(_ k: Kernel1D, frequencies: [Double]) -> [Double] {
        let m = k.mean, s = k.sum
        return frequencies.map { nu in
            k.weights.indices.reduce(0) { $0 + k.weights[$1] * cos(2 * .pi * nu * (k.offset($1) - m)) } / s
        }
    }

    /// Signed response of a 2-D kernel along an axis (degrees), phase-centred on the centroid.
    public static func response(_ k: Kernel2D, axisDegrees: Double, frequencies: [Double]) -> [Double] {
        let c = cos(axisDegrees * .pi / 180), s = sin(axisDegrees * .pi / 180)
        var mx = 0.0, my = 0.0
        let total = k.sum
        for y in 0..<k.height { for x in 0..<k.width {
            mx += k[x, y] * Double(x - k.originX); my += k[x, y] * Double(y - k.originY)
        } }
        mx /= total; my /= total
        return frequencies.map { nu in
            var acc = 0.0
            for y in 0..<k.height { for x in 0..<k.width {
                let d = (Double(x - k.originX) - mx) * c + (Double(y - k.originY) - my) * s
                acc += k[x, y] * cos(2 * .pi * nu * d)
            } }
            return acc / total
        }
    }

    /// "MASS CUT" on the Kernel floor: the continuous Gaussian's mass outside the window ±r, erfc(r / (σ√2))
    /// (0.27 % at r = 3σ: the SPEC §5.3 fixtures).
    public static func gaussianMassBeyond(radius r: Int, sigma: Double) -> Double { erfc(Double(r) / (sigma * 2.0.squareRoot())) }

    /// Continuous Gaussian response e^(−2π²σ²ν²).
    public static func gaussianResponse(sigma: Double, frequency nu: Double) -> Double { exp(-2 * .pi * .pi * sigma * sigma * nu * nu) }

    public static func normalCDF(_ x: Double) -> Double { 0.5 * (1 + erf(x / 2.0.squareRoot())) }

    /// e^(−t)·I_n(t) for n = 0…upTo (Miller's backward recurrence, normalised by I₀ + 2ΣIₙ = e^t).
    private static func scaledBesselI(upTo nMax: Int, t: Double) -> [Double] {
        guard t > 0 else { return [1] + Array(repeating: 0, count: nMax) }
        let start = Swift.max(nMax, Int((10 * t.squareRoot()).rounded(.up))) + 60
        var values = [Double](repeating: 0, count: start + 2)
        var next = 0.0, current = 1e-300
        values[start] = current
        var n = start
        while n > 0 {
            let previous = (2 * Double(n) / t) * current + next
            next = current; current = previous
            n -= 1
            values[n] = current
            if current > 1e250 { for i in n...start { values[i] /= 1e250 }; current /= 1e250; next /= 1e250 }
        }
        let norm = values[0] + 2 * values[1...start].reduce(0, +)
        return (0...nMax).map { values[$0] / norm }
    }
}
