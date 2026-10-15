import Foundation

// OWNER: CALIBRATION (ARCHITECTURE §5.13, §8.2 CALIBRATION; SPEC §13; research/live-calibration.md (CAL) §3.3).
// The pure half of live calibration: the edge-spread estimators of Tools/calibrate/MeasurePSF.swift (fitEdge), ported
// line for line so the phone and the research Mac compute the same numbers from the same samples, plus the model
// competition of SPEC §13.3 (Gaussian · Gaussian truncated at ±2.3σ · box³) and the parameter → σ law of a sweep.
//
// Conventions (identical to MeasurePSF): `esf[i]` is the value of device pixel i, whose centre is i + 0.5; the unblurred
// step lies at the continuous position `edgePosition` (pixels whose centre is beyond it are white). The line-spread sample
// k = esf[k] − esf[k − 1] sits on the boundary between pixels k − 1 and k, at t = k − edgePosition.
//
//   moment σ   second central moment of the LSF, two passes: the whole window, then ±max(12, 6σ) around the centroid,
//              which keeps 8-bit noise in the far tails out of the sum (CAL §3.3).
//   lsq σ      golden-section least squares of Φ((i + ½ − edge − μ)/s) on log s over |t − μ| ≤ max(4, 4.5σ), reported as
//              the sampled-equivalent σ = √(s² + 1/12) (Sheppard: a sampled kernel's midpoint CDF is 1/12 px² narrower).
//   kurtosis   excess kurtosis of the LSF (Gaussian 0, box³ −0.4, tent −0.6, disc −1.0, box −1.2).
//   extent     farthest pixel centre from the edge centre whose value is still 1/255 off both plateaus.
//   support    farthest LSF sample above 10⁻³ of the LSF peak.
//   spread     max − min of the fitted centre (and of σ) over whole-pixel edge phases: 0 for a full-resolution
//              shift-invariant filter, the resampling detector (CAL §5.1 item 4).
// Nothing here knows a provenance: CalibrationReadout attaches the badges (MEASURED with the device, INFERRED shape name).

public struct PSFFitter: PSFFitting {
    public init() {}

    /// The truncated-Gaussian model's cut (SDK §4's reading of SwiftUI's large-radius kernel): ±2.3σ of its parent Gaussian.
    public static let truncationSigmas = 2.3
    /// Centre spread (device px) above which an edge counts as shift-variant (the resampling signature). An LTI filter at
    /// full resolution gives 0.000 (CAL §4.18 below 5 px); SwiftUI above the switch gives 0.12–1.4 px.
    public static let shiftVariantSpreadPx = 0.05

    public func fit(_ samples: [EdgeSamples], request: CalibrationRequest) -> PSFFit {
        let fits = samples.map { PSFEdgeFit.analyse(esf: $0.esf, edge: $0.edgePosition) }
        let valid = fits.filter(\.isValid)
        guard let first = valid.first else {
            return PSFFit(sigmaPx: 0, sigmaPerParameterPixel: 0, lsqSigmaPx: 0, excessKurtosis: 0, excessKurtosis45: nil,
                          extentPx: 0, supportPx: 0, centreSpreadPx: 0, sigmaSpreadPercent: 0,
                          encodedMidpoint: samples.compactMap(\.encodedMidpoint).first, shapeName: PSFShape.noEdge,
                          models: [], lsf: [])
        }
        let centres = valid.map(\.centre), sigmas = valid.map(\.sigma)
        let meanSigma = sigmas.reduce(0, +) / Double(sigmas.count)
        let kurtosis45 = samples.lazy.compactMap { s -> Double? in
            guard let esf45 = s.esf45 else { return nil }
            let f = PSFEdgeFit.analyse(esf: esf45, edge: s.edgePosition)
            return f.isValid ? f.kurtosis : nil
        }.first
        let pixels = request.parameter * request.displayScale
        return PSFFit(sigmaPx: first.sigma,
                      sigmaPerParameterPixel: pixels > 0 ? first.sigma / pixels : 0,
                      lsqSigmaPx: first.sigmaLSQ,
                      excessKurtosis: first.kurtosis,
                      excessKurtosis45: kurtosis45,
                      extentPx: first.extent,
                      supportPx: first.support,
                      centreSpreadPx: (centres.max() ?? 0) - (centres.min() ?? 0),
                      sigmaSpreadPercent: meanSigma > 0 ? ((sigmas.max() ?? 0) - (sigmas.min() ?? 0)) / meanSigma * 100 : 0,
                      encodedMidpoint: samples.compactMap(\.encodedMidpoint).first,
                      shapeName: PSFShape.name(kurtosis: first.kurtosis),
                      models: first.models,
                      lsf: first.lsf)
    }

    /// The law of a sweep (SPEC §13.3): σ/(parameter·scale) below and above the regime switch, and the switch itself.
    /// Uses the newest result's (subject, path, colour mode, scale, opaque) group only, the newest result per parameter,
    /// and needs at least three measured points. The switch is found from the centre spread when the sweep stepped the
    /// edge through phases (the resampling signature is binary: 0 below, ≥ 0.1 px above), otherwise from a two-level
    /// split of the ratios; it sits halfway between the last point of the small regime and the first of the large one.
    public func law(_ sweep: [CalibrationResult]) -> CalibrationLaw? {
        guard let newest = sweep.max(by: { $0.device.date < $1.device.date }) else { return nil }
        let key = PSFLawKey(newest.request)
        var byParameter: [Double: CalibrationResult] = [:]
        for result in sweep where PSFLawKey(result.request) == key && result.request.parameter > 0 && result.fit.sigmaPx > 0 {
            if let kept = byParameter[result.request.parameter], kept.device.date > result.device.date { continue }
            byParameter[result.request.parameter] = result
        }
        let results = byParameter.values.sorted { $0.request.parameter < $1.request.parameter }
        guard results.count >= 3 else { return nil }
        let points = results.map { CalibrationPoint(parameter: $0.request.parameter, sigmaPx: $0.fit.sigmaPx,
                                                    centreSpreadPx: $0.fit.centreSpreadPx) }
        let ratios = results.map { $0.fit.sigmaPx / ($0.request.parameter * $0.request.displayScale) }
        let phased = results.allSatisfy { $0.request.phases > 1 }
        let split = (phased ? PSFLawSplit.fromSpread(points.map(\.centreSpreadPx)) : nil) ?? PSFLawSplit.fromRatios(ratios)
        guard let k = split else {
            return CalibrationLaw(subject: key.subject, smallRatio: nil, largeRatio: PSFStatistics.median(ratios),
                                  switchParameter: nil, points: points, device: newest.device)
        }
        return CalibrationLaw(subject: key.subject, smallRatio: PSFStatistics.median(Array(ratios[..<k])),
                              largeRatio: PSFStatistics.median(Array(ratios[k...])),
                              switchParameter: (points[k - 1].parameter + points[k].parameter) / 2,
                              points: points, device: newest.device)
    }
}

/// The analysis of one rendered edge (one phase): MeasurePSF's `fitEdge` plus the model competition.
public struct PSFEdgeFit: Sendable, Hashable {
    /// LSF centroid relative to the unblurred edge (device px); the registration error of this phase.
    public var centre: Double = 0
    public var sigma: Double = 0
    /// Sampled-equivalent σ of the erf least-squares fit.
    public var sigmaLSQ: Double = 0
    /// RMS misfit of the erf model inside the fit window, % of the step.
    public var gaussianResidualPercent: Double = 0
    public var kurtosis: Double = 0
    public var extent: Double = 0
    public var support: Double = 0
    /// The normalised value at the edge centre, in the analysis space (MeasurePSF `midEncoded` before encoding).
    public var midpoint: Double = 0.5
    /// LSF samples around the edge centre, rounded to 10⁻⁶ (for plotting beside the theory).
    public var lsf: [Double] = []
    /// Model competition, sorted by residual (lowest first).
    public var models: [ModelFit] = []
    public var isValid = false

    /// `esf`: one value per device pixel (any affine scale; it is re-normalised by its first and last four pixels, as
    /// MeasurePSF does). `edge`: the continuous position of the unblurred step in pixels from esf[0].
    public static func analyse(esf: [Double], edge: Double) -> PSFEdgeFit {
        var f = PSFEdgeFit()
        let n = esf.count
        guard n > 16, edge.isFinite else { return f }
        let lo = esf.prefix(4).reduce(0, +) / 4, hi = esf.suffix(4).reduce(0, +) / 4
        guard hi - lo > 1e-6 else { return f }
        let q = esf.map { ($0 - lo) / (hi - lo) }
        var mass = [Double](repeating: 0, count: n)
        for i in 1..<n { mass[i] = q[i] - q[i - 1] }
        func moments(centre: Double, window: Double) -> (mu: Double, m2: Double, kurt: Double) {
            var s0 = 0.0, s1 = 0.0
            for i in 1..<n { let t = Double(i) - edge; if abs(t - centre) <= window { s0 += mass[i]; s1 += mass[i] * t } }
            let mu = s1 / Swift.max(s0, 1e-12)
            var s2 = 0.0, s4 = 0.0
            for i in 1..<n {
                let t = Double(i) - edge
                if abs(t - centre) <= window { let d = t - mu; s2 += mass[i] * d * d; s4 += mass[i] * d * d * d * d }
            }
            let m2 = s2 / Swift.max(s0, 1e-12), m4 = s4 / Swift.max(s0, 1e-12)
            return (mu, m2, m2 > 0 ? m4 / (m2 * m2) - 3 : 0)
        }
        var m = moments(centre: 0, window: Double(n))
        m = moments(centre: m.mu, window: Swift.max(12, 6 * m.m2.squareRoot()))
        let mu = m.mu
        f.centre = mu; f.sigma = m.m2.squareRoot(); f.kurtosis = m.kurt
        guard f.sigma.isFinite, f.sigma > 0 else { return f }

        // Least squares and model competition on the ESF inside ±max(4, 4.5σ) of the centre.
        let window = Swift.max(4, 4.5 * f.sigma)
        let idx = (0..<n).filter { abs(Double($0) + 0.5 - edge - mu) <= window }
        let xs = idx.map { Double($0) + 0.5 - edge - mu }, ys = idx.map { q[$0] }
        var models: [ModelFit] = []
        for model in PSFModel.allCases {
            let (width, sse) = PSFModelCDF.bestWidth(model, xs: xs, ys: ys)
            let rms = (sse / Double(Swift.max(1, xs.count))).squareRoot() * 100
            let sampled = (PSFModelCDF.continuousSigma(model, width: width).squared + 1.0 / 12).squareRoot()
            models.append(ModelFit(model: model, sigmaPx: sampled, rmsResidualPercent: rms))
            if model == .gaussian { f.sigmaLSQ = sampled; f.gaussianResidualPercent = rms }
        }
        f.models = models.sorted { $0.rmsResidualPercent < $1.rmsResidualPercent }

        var extent = 0.0
        for i in 0..<n where q[i] >= 1.0 / 255 && q[i] <= 254.0 / 255 { extent = Swift.max(extent, abs(Double(i) + 0.5 - edge - mu)) }
        f.extent = extent
        let peak = mass.max() ?? 0
        var support = 0.0
        for i in 1..<n where mass[i] > 1e-3 * peak { support = Swift.max(support, abs(Double(i) - edge - mu)) }
        f.support = support
        let e = Int(edge.rounded())
        f.midpoint = e > 0 && e < n ? (q[e - 1] + q[e]) / 2 : 0.5
        let half = Swift.min(n / 2 - 1, Int(extent.rounded(.up)) + 2)
        if half > 0, e - half >= 1, e + half < n { f.lsf = (e - half...e + half).map { (mass[$0] * 1e6).rounded() / 1e6 } }
        f.isValid = true
        return f
    }
}

/// Cumulative distribution functions of the three competing models (unit mass, centred, width parameter `w`).
public enum PSFModelCDF {
    public static func cdf(_ model: PSFModel, _ x: Double, width w: Double) -> Double {
        switch model {
        case .gaussian:
            return PSFStatistics.phi(x / w)
        case .truncatedGaussian:
            let c = PSFFitter.truncationSigmas
            if x <= -c * w { return 0 }
            if x >= c * w { return 1 }
            let lower = PSFStatistics.phi(-c), mass = PSFStatistics.phi(c) - lower
            return (PSFStatistics.phi(x / w) - lower) / mass
        case .boxCubed:
            // Irwin–Hall n = 3 on [−3w, 3w]: three boxes of width 2w; σ = w.
            let z = (x / w + 3) / 2
            if z <= 0 { return 0 }
            if z < 1 { return z * z * z / 6 }
            if z < 2 { return (-2 * z * z * z + 9 * z * z - 9 * z + 3) / 6 }
            if z < 3 { let r = 3 - z; return 1 - r * r * r / 6 }
            return 1
        }
    }

    /// σ of the continuous model at width `w`.
    public static func continuousSigma(_ model: PSFModel, width w: Double) -> Double {
        switch model {
        case .gaussian, .boxCubed:
            return w
        case .truncatedGaussian:
            let c = PSFFitter.truncationSigmas
            let mass = PSFStatistics.phi(c) - PSFStatistics.phi(-c)
            return w * (1 - 2 * c * PSFStatistics.normalDensity(c) / mass).squareRoot()
        }
    }

    /// Least-squares width: golden-section search on log w over [0.05, 4000] px. The Gaussian SSE is unimodal (this is
    /// MeasurePSF's 60-step search); the compact models are first bracketed on a 96-point log grid, because their SSE has
    /// flat shoulders where the support stops reaching the samples.
    public static func bestWidth(_ model: PSFModel, xs: [Double], ys: [Double]) -> (width: Double, sse: Double) {
        func sse(_ w: Double) -> Double {
            var e = 0.0
            for i in xs.indices { let r = ys[i] - cdf(model, xs[i], width: w); e += r * r }
            return e
        }
        var a = log(0.05), b = log(4000.0)
        if model != .gaussian {
            let steps = 96
            var best = 0, bestValue = Double.infinity
            for k in 0...steps {
                let value = sse(exp(a + (b - a) * Double(k) / Double(steps)))
                if value < bestValue { bestValue = value; best = k }
            }
            let step = (b - a) / Double(steps)
            let centre = a + step * Double(best)
            (a, b) = (Swift.max(log(0.05), centre - step), Swift.min(log(4000.0), centre + step))
        }
        let g = (5.0.squareRoot() - 1) / 2
        var c = b - g * (b - a), d = a + g * (b - a), fc = sse(exp(c)), fd = sse(exp(d))
        for _ in 0..<60 {
            if fc < fd { b = d; d = c; fd = fc; c = b - g * (b - a); fc = sse(exp(c)) }
            else { a = c; c = d; fc = fd; d = a + g * (b - a); fd = sse(exp(d)) }
        }
        let w = exp((a + b) / 2)
        return (w, sse(w))
    }
}

/// Shape names by excess kurtosis (CAL §3.3): an interpretation, always shown with the INFERRED badge.
public enum PSFShape {
    public static let gaussian = "gaussian"
    public static let boxCubedLike = "box³-like"
    public static let tentLike = "tent-like"
    public static let disc = "disc"
    public static let box = "box"
    /// Heavier tails than a Gaussian (a 3-tap kernel, a Laplace or Lorentzian-like PSF).
    public static let peaked = "peaked"
    public static let noEdge = "no edge found"

    /// The reference kurtoses, in MeasurePSF's order (ties go to the earlier entry).
    public static let references: [(name: String, kurtosis: Double)] = [
        (gaussian, 0), (boxCubedLike, -0.4), (tentLike, -0.6), (disc, -1.0), (box, -1.2), (peaked, 3.0),
    ]
    public static func name(kurtosis k: Double) -> String {
        guard k.isFinite else { return noEdge }
        var best = references[0]
        for r in references.dropFirst() where abs(r.kurtosis - k) < abs(best.kurtosis - k) { best = r }
        return best.name
    }
}

/// The group a law is fitted over: one subject, one render path, one working space, one scale, one border setting.
struct PSFLawKey: Hashable {
    var subject: CalibrationSubject
    var path: CalibrationPath
    var colourMode: CalibrationColourMode
    var displayScale: Double
    var opaque: Bool?
    init(_ r: CalibrationRequest) {
        subject = r.subject; path = r.path; colourMode = r.colourMode; displayScale = r.displayScale; opaque = r.opaque
    }
}

/// Regime-switch detection for `PSFFitter.law`: the index k of the first point of the large regime, or nil.
public enum PSFLawSplit {
    /// The first point whose centre spread exceeds `PSFFitter.shiftVariantSpreadPx`, when every point before it is
    /// shift-invariant and at least 60 % of the points from it on are shift-variant.
    public static func fromSpread(_ spreads: [Double]) -> Int? {
        let tau = PSFFitter.shiftVariantSpreadPx
        guard let k = spreads.firstIndex(where: { $0 > tau }), k >= 1 else { return nil }
        let after = spreads[k...]
        guard Double(after.filter { $0 > tau }.count) >= 0.6 * Double(after.count) else { return nil }
        return k
    }

    /// The two-level split of the ratios with the lowest L1 cost (at least two points each side), accepted when the two
    /// levels differ by ≥ 3 % and the split removes ≥ 40 % of the one-level cost.
    public static func fromRatios(_ ratios: [Double]) -> Int? {
        guard ratios.count >= 4 else { return nil }
        func cost(_ xs: ArraySlice<Double>) -> Double {
            let m = PSFStatistics.median(Array(xs))
            return xs.reduce(0) { $0 + abs($1 - m) }
        }
        let single = cost(ratios[...])
        var best: (k: Int, cost: Double)?
        for k in 2...(ratios.count - 2) {
            let c = cost(ratios[..<k]) + cost(ratios[k...])
            if best == nil || c < best!.cost { best = (k, c) }
        }
        guard let b = best else { return nil }
        let left = PSFStatistics.median(Array(ratios[..<b.k])), right = PSFStatistics.median(Array(ratios[b.k...]))
        guard abs(left - right) >= 0.03 * Swift.max(abs(left), abs(right)), b.cost <= 0.6 * single else { return nil }
        return b.k
    }
}

public enum PSFStatistics {
    /// Standard normal CDF.
    public static func phi(_ x: Double) -> Double { 0.5 * erfc(-x / 2.0.squareRoot()) }
    public static func normalDensity(_ x: Double) -> Double { exp(-0.5 * x * x) / (2 * Double.pi).squareRoot() }
    public static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted(), m = s.count / 2
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
    }
}

private extension Double {
    var squared: Double { self * self }
}
