import Foundation

// OWNER: ANALYSIS (ARCHITECTURE §8.2). The three services behind the frozen names live beside this file:
//   DivergenceEngine.swift   SPEC §8.4: where two configurations part ways, floor by floor, with badged reasons
//   FingerprintEngine.swift  SPEC §7.4: fingerprint vectors at σ_equiv 4 px, LOOKS MOST LIKE, the excess-kurtosis axis
//   CostModel.swift          GPU §4.1–§4.2: MODELED bytes per pass, bandwidth floors, cost curves, the reference table
// This file holds the numerics they share. Everything here is pure, deterministic and Sendable (ARCHITECTURE §5.15).

/// Shared numerics of the ANALYSIS services. Internal; the names are namespaced so no other BlurCore area collides.
enum AnalysisMath {
    /// Weighted moments of a 1-D distribution (weights may be signed; `mass` is their sum).
    struct Moments: Sendable, Hashable {
        var mass: Double
        var mean: Double
        var variance: Double
        /// Fourth central moment.
        var fourth: Double
        var sigma: Double { variance.squareRoot() }
        /// m₄/σ⁴ − 3 (Gaussian 0, box −1.2; SPEC §17 item 4: always the excess convention).
        var excessKurtosis: Double? { variance > 1e-12 ? fourth / (variance * variance) - 3 : nil }
    }

    static func moments(positions: [Double], weights: [Double]) -> Moments? {
        precondition(positions.count == weights.count)
        var mass = 0.0, first = 0.0
        for i in weights.indices { mass += weights[i]; first += weights[i] * positions[i] }
        guard abs(mass) > 1e-300 else { return nil }
        let mean = first / mass
        var m2 = 0.0, m4 = 0.0
        for i in weights.indices {
            let d = positions[i] - mean, d2 = d * d
            m2 += weights[i] * d2
            m4 += weights[i] * d2 * d2
        }
        return Moments(mass: mass, mean: mean, variance: m2 / mass, fourth: m4 / mass)
    }

    static func moments(_ k: Kernel1D) -> Moments? {
        moments(positions: k.weights.indices.map { k.offset($0) }, weights: k.weights)
    }

    /// Moments of the 2-D kernel projected onto the direction `degrees` (0 = +x, 90 = +y): the line-spread function
    /// along that direction. At 45° this separates "separable" from "isotropic" (SPEC §7.2 Gaussian UNIQUE row).
    static func projectedMoments(_ k: Kernel2D, degrees: Double) -> Moments? {
        let c = cos(degrees * .pi / 180), s = sin(degrees * .pi / 180)
        var positions: [Double] = [], weights: [Double] = []
        positions.reserveCapacity(k.weights.count); weights.reserveCapacity(k.weights.count)
        for y in 0..<k.height {
            for x in 0..<k.width {
                let w = k[x, y]
                guard w != 0 else { continue }
                positions.append(Double(x - k.originX) * c + Double(y - k.originY) * s)
                weights.append(w)
            }
        }
        return moments(positions: positions, weights: weights)
    }

    /// Per-axis second-moment σ (x marginal, y marginal) of a PSF.
    static func axisSigmas(_ k: Kernel2D) -> (x: Double, y: Double)? {
        guard let mx = moments(k.marginalX), let my = moments(k.marginalY) else { return nil }
        return (mx.sigma, my.sigma)
    }

    /// The largest |a − b| over the union of two kernels' supports, aligned on their origins (cells outside a kernel
    /// count as 0). SPEC §8.4 floor 4: equal within 10⁻⁹.
    static func maxDifference(_ a: Kernel2D, _ b: Kernel2D) -> Double {
        let x0 = Swift.min(-a.originX, -b.originX), x1 = Swift.max(a.width - 1 - a.originX, b.width - 1 - b.originX)
        let y0 = Swift.min(-a.originY, -b.originY), y1 = Swift.max(a.height - 1 - a.originY, b.height - 1 - b.originY)
        func weight(_ k: Kernel2D, _ dx: Int, _ dy: Int) -> Double {
            let x = dx + k.originX, y = dy + k.originY
            return x >= 0 && y >= 0 && x < k.width && y < k.height ? k[x, y] : 0
        }
        var largest = 0.0
        for dy in y0...y1 { for dx in x0...x1 { largest = Swift.max(largest, abs(weight(a, dx, dy) - weight(b, dx, dy))) } }
        return largest
    }

    /// Value of a 1-D kernel's signed response at one frequency (KernelMath's phase-centred convention).
    static func response(_ k: Kernel1D, at nu: Double) -> Double { KernelMath.response(k, frequencies: [nu])[0] }

    /// True when `marginal` reproduces the sampled curve (an LSI response along the x axis), so it can refine it.
    private static func marginalReproduces(_ curve: ResponseCurve, _ k: Kernel1D, at i: Int) -> Bool {
        abs(response(k, at: curve.frequencies[i]) - curve.values[i]) < 1e-9
    }

    /// The minimum of a signed response. The curve's own samples locate it; when the x-axis line-spread function is
    /// known and reproduces the curve, a golden-section search between the neighbouring samples refines it, so the
    /// printed digits do not depend on the sampling grid.
    static func minimum(of curve: ResponseCurve, refineWith marginal: Kernel1D?) -> (frequency: Double, value: Double)? {
        guard let i = curve.values.indices.min(by: { curve.values[$0] < curve.values[$1] }) else { return nil }
        var best = (frequency: curve.frequencies[i], value: curve.values[i])
        guard let k = marginal, curve.values.count > 2, marginalReproduces(curve, k, at: i) else { return best }
        var lo = curve.frequencies[Swift.max(0, i - 1)], hi = curve.frequencies[Swift.min(curve.values.count - 1, i + 1)]
        let g = (5.0.squareRoot() - 1) / 2
        var c = hi - g * (hi - lo), d = lo + g * (hi - lo)
        var fc = response(k, at: c), fd = response(k, at: d)
        for _ in 0..<80 {
            if fc < fd { hi = d; d = c; fd = fc; c = hi - g * (hi - lo); fc = response(k, at: c) }
            else { lo = c; c = d; fc = fd; d = lo + g * (hi - lo); fd = response(k, at: d) }
        }
        let nu = (lo + hi) / 2, value = response(k, at: nu)
        if value < best.value { best = (nu, value) }
        return best
    }

    /// The first frequency where the signed response reaches 0, refined by bisection on the line-spread function when it
    /// reproduces the curve. nil when it never does below `maxFrequency`.
    static func firstZero(of curve: ResponseCurve, refineWith marginal: Kernel1D?) -> Double? {
        guard let coarse = curve.firstCrossing(of: 0) else { return nil }
        guard let k = marginal, let j = curve.frequencies.firstIndex(where: { $0 >= coarse }), j > 0,
              marginalReproduces(curve, k, at: j) else { return coarse }
        var lo = curve.frequencies[j - 1], hi = curve.frequencies[j]
        guard response(k, at: lo) > 0, response(k, at: hi) <= 0 else { return coarse }
        for _ in 0..<80 {
            let mid = (lo + hi) / 2
            if response(k, at: mid) > 0 { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// Support radius of a line-spread function at `level` × its peak (|w| ≥ level·peak), measured from its centroid
    /// and divided by its σ (SPEC §7.4 "support at 10⁻⁴ of peak over σ").
    static func supportOverSigma(_ k: Kernel1D, level: Double = 1e-4) -> Double? {
        guard let m = moments(k), m.variance > 1e-12, let peak = k.weights.map(abs).max(), peak > 0 else { return nil }
        let threshold = level * peak
        var radius = 0.0
        for i in k.weights.indices where abs(k.weights[i]) >= threshold { radius = Swift.max(radius, abs(k.offset(i) - m.mean)) }
        return radius / m.sigma
    }

    /// Least-squares slope of ln y against ln x (fetches ∝ r^p). nil with fewer than two usable, distinct points.
    static func logLogSlope(_ xs: [Double], _ ys: [Double]) -> Double? {
        let pairs = zip(xs, ys).filter { $0.0 > 0 && $0.1 > 0 }.map { (log($0.0), log($0.1)) }
        guard pairs.count >= 2 else { return nil }
        let mx = pairs.map(\.0).reduce(0, +) / Double(pairs.count), my = pairs.map(\.1).reduce(0, +) / Double(pairs.count)
        let sxx = pairs.reduce(0) { $0 + ($1.0 - mx) * ($1.0 - mx) }
        guard sxx > 1e-12 else { return nil }
        let sxy = pairs.reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let slope = sxy / sxx
        return abs(slope) < 1e-12 ? 0 : slope
    }

    /// The parameters that give `op` the size `size`: σ-held when the entry defines a σ (SPEC §8.1; x = the achieved
    /// σ), otherwise the primary parameter set to `size` in its own unit when that unit is px or texels (x = the value).
    static func parameters(for op: any BlurOperator, entry: CatalogEntry, size: Double,
                           base: ParameterValues) -> (parameters: ParameterValues, x: Double, isSigma: Bool)? {
        let hold = op.holdingSigma(size, current: base)
        if let achieved = hold.achievedSigma, achieved.isFinite, achieved > 0 { return (hold.parameters, achieved, true) }
        guard let spec = entry.primarySpec, spec.unit == .px || spec.unit == .texels else { return nil }
        var values = base
        switch spec.kind {
        case .continuous(let c):
            let v = c.clamped(size)
            values[spec.key] = .double(v)
            return (values, v, false)
        case .integer(let i):
            let v = i.clamped(Int(size.rounded()))
            values[spec.key] = .int(v)
            return (values, Double(v), false)
        default:
            return nil
        }
    }

    /// A request with other parameters (and optionally another variant), keeping settings, size and scale.
    static func request(_ base: OperatorRequest, parameters: ParameterValues, variant: VariantID? = nil) -> OperatorRequest {
        OperatorRequest(parameters: parameters, variant: variant ?? base.variant, settings: base.settings, size: base.size,
                        pixelScale: base.pixelScale)
    }

    /// Whole numbers print as integers with their noun; fractional ones with two decimals (Metro contract A.6).
    static func countStyle(_ value: Double, noun: CountNoun) -> NumberStyle {
        abs(value - value.rounded()) < 1e-9 ? .integer(noun: noun)
            : NumberStyle(precision: .decimals(2), noun: noun)
    }

    static let px2 = NumberStyle.decimals(2, unit: "px", spokenUnit: "pixels")
}
