import Foundation

// OWNER: SEMANTICS. Forward (typed value → σ px) and inverse (σ px → typed value) for every law in SemanticsLaw, the
// piecewise inverse of a CalibrationLaw, and the 10–90 % edge width of the kernel shapes STACK §8 compares.
// All of it is COMPUTED from the documented or measured laws; nothing here measures anything.

/// The result of asking "what would I type to get this σ?".
public struct SemanticsInverse: Sendable, Hashable {
    public enum Status: String, Sendable, Hashable {
        /// The typed value gives exactly the requested σ.
        case exact
        /// The tool's steps (odd widths, integer box sizes, regime gaps) give the nearest σ instead (`achievedSigmaPx`).
        case nearest
        /// The requested σ is smaller than the tool's smallest non-zero blur.
        case belowRange
        /// The requested σ is beyond the tool's largest blur.
        case aboveRange
    }
    public var typed: Double?
    public var status: Status
    /// The σ the typed value actually gives (device px).
    public var achievedSigmaPx: Double?
    public init(typed: Double?, status: Status, achievedSigmaPx: Double?) {
        self.typed = typed; self.status = status; self.achievedSigmaPx = achievedSigmaPx
    }
}

public enum SemanticsMath {
    /// √(2·ln 255) = 3.3290: GIMP 2.8's Gaussian falls to 1/255 of its peak at r + 1 (STACK §4.6).
    public static let gimp28Divisor = (2 * log(255.0)).squareRoot()
    /// Skia's kBLUR_SIGMA_SCALE (1/√3 rounded), shared by Android hwui and Flutter's Shadow (STACK §2.1).
    public static let skiaSigmaScale = 0.57735
    /// 3·√(2π)/4 = 1.8800: the SVG three-box width per unit σ (matches peak height, not variance; STACK §1.2).
    public static let svgBoxFactor = 3 * (2 * Double.pi).squareRoot() / 4
    /// The SwiftUI regime switch on the research Mac, in device pixels (CAL §5.1 item 2: "≈ 5 px").
    public static let swiftUISwitchDevicePx = 5.0
    /// z at the 90th percentile of the unit normal: a Gaussian edge rises 10 → 90 % over 2·z·σ = 2.5631σ.
    public static let gaussianEdgeFactor = 2 * 1.2815515655446004

    // MARK: Discrete widths

    /// σ of a box of w taps: √((w² − 1)/12).
    public static func boxSigma(width w: Double) -> Double { ((w * w - 1) / 12).squareRoot().nanToZero }
    /// σ of a tent of width w (two boxes of (w + 1)/2): √((((w + 1)/2)² − 1)/6).
    public static func tentSigma(width w: Double) -> Double { let a = (w + 1) / 2; return ((a * a - 1) / 6).squareRoot().nanToZero }
    /// CIBoxBlur's width for an `inputRadius` (CAL §5.2: W = 2⌈r/2⌉ − 1, radii ≤ 2 do nothing).
    public static func ciBoxWidth(radius r: Double) -> Double { max(1, 2 * (r / 2).rounded(.up) - 1) }
    /// Nearest odd integer ≥ 1.
    public static func nearestOdd(_ x: Double) -> Double { max(1, 2 * ((x - 1) / 2).rounded() + 1) }

    /// σ of the SVG three-box cascade for d (odd: three boxes of d; even: d, d and d + 1).
    public static func svgThreeBoxSigma(d: Double) -> Double {
        let isOdd = Int(d) % 2 != 0
        let v = isOdd ? 3 * (d * d - 1) : 2 * (d * d - 1) + ((d + 1) * (d + 1) - 1)
        return (v / 12).squareRoot().nanToZero
    }
    /// The box width d the SVG rule uses for stdDeviation s (≥ 2).
    public static func svgThreeBoxWidth(stdDeviation s: Double) -> Double { (s * svgBoxFactor + 0.5).rounded(.down) }

    /// Flutter Impeller's rescaled σ′ (STACK §2.4, `sigma.cc`).
    public static func impellerScaledSigma(_ sigma: Double) -> Double {
        let s = min(max(sigma, 0), 500)
        return s * (1 - 3.4e-3 * s + 3.4e-6 * s * s)
    }
    /// Effective σ of Impeller's kernel: σ′ sampled at integer taps out to ⌊√3·(σ′ − 0.5)⌋, renormalised.
    /// COMPUTED; Impeller's exact tap rounding and its down/up-sampling are not modelled (STACK §2.4).
    public static func impellerEffectiveSigma(_ sigma: Double) -> Double {
        guard sigma > 0 else { return 0 }
        let sp = impellerScaledSigma(sigma)
        let n = max(1, Int((3.0.squareRoot() * (sp - 0.5)).rounded(.down)))
        var sum = 0.0, second = 0.0
        for i in -n...n {
            let w = exp(-Double(i * i) / (2 * sp * sp))
            sum += w; second += w * Double(i * i)
        }
        return (second / sum).squareRoot()
    }

    /// OpenCV's σ for `ksize = 2r + 1` with sigmaX ≤ 0: fixed tables for ksize 3…9, else 0.3·(r − 1) + 0.8 (STACK §6.1).
    public static func opencvSigma(kernelRadius r: Double) -> Double {
        switch Int(r.rounded()) {
        case ..<1: return 0
        case 1: return 0.5.squareRoot()            // ¼ ½ ¼
        case 2: return 1                            // 1 4 6 4 1 / 16
        case 3: return (60.0 / 32).squareRoot()     // 1 3.5 7 9 7 3.5 1 / 32
        case 4: return (704.0 / 256).squareRoot()   // 4 13 30 51 60 51 30 13 4 / 256
        default: return 0.3 * (r - 1) + 0.8
        }
    }

    // MARK: Forward

    /// σ in device px for a typed value. `law` is used for every case except `.swiftUIBlur`, which needs `calibration`.
    public static func sigmaPx(_ law: SemanticsLaw, typed v: Double, unitScale u: Double, calibration: CalibrationLaw? = nil) -> Double? {
        guard v.isFinite else { return nil }
        switch law {
        case .linear(let slope, let offset, let offsetScales):
            return v > 0 ? slope * v * u + offset * (offsetScales ? u : 1) : 0
        case .swiftUIBlur:
            guard let calibration else { return nil }
            return v > 0 ? calibration.sigmaPx(parameter: v, displayScale: u) : 0
        case .ciBoxWidth:
            return boxSigma(width: ciBoxWidth(radius: v)) * u
        case .boxWidth:
            let w = v.rounded()
            guard w >= 1, Int(w) % 2 == 1 else { return nil }
            return boxSigma(width: w) * u
        case .tentWidth:
            let w = v.rounded()
            guard w >= 1, Int(w) % 2 == 1 else { return nil }
            return tentSigma(width: w) * u
        case .svgThreeBox:
            guard v > 0 else { return 0 }
            return (v < 2 ? v : svgThreeBoxSigma(d: svgThreeBoxWidth(stdDeviation: v))) * u
        case .impeller:
            return impellerEffectiveSigma(v) * u
        case .opencvKernelRadius:
            return opencvSigma(kernelRadius: v) * u
        case .constant(let c):
            return c * u
        }
    }

    // MARK: Inverse

    public static func typed(_ law: SemanticsLaw, sigmaPx sigma: Double, unitScale u: Double, calibration: CalibrationLaw? = nil,
                             integerValued: Bool = false) -> SemanticsInverse {
        guard sigma.isFinite, sigma >= 0, u > 0 else { return SemanticsInverse(typed: nil, status: .aboveRange, achievedSigmaPx: nil) }
        if sigma == 0 { return SemanticsInverse(typed: 0, status: .exact, achievedSigmaPx: 0) }
        let t = sigma / u
        switch law {
        case .linear(let slope, let offset, let offsetScales):
            let floor = offset * (offsetScales ? u : 1)
            guard slope > 0 else { return SemanticsInverse(typed: nil, status: .aboveRange, achievedSigmaPx: nil) }
            if sigma <= floor { return SemanticsInverse(typed: nil, status: .belowRange, achievedSigmaPx: floor) }
            return SemanticsInverse(typed: (sigma - floor) / (slope * u), status: .exact, achievedSigmaPx: sigma)
        case .swiftUIBlur:
            guard let calibration else { return SemanticsInverse(typed: nil, status: .aboveRange, achievedSigmaPx: nil) }
            return inverse(calibration, sigmaPx: sigma, unitScale: u)
        case .ciBoxWidth, .boxWidth:
            let w = nearestOdd((12 * t * t + 1).squareRoot())
            return nearestResult(typed: w, achieved: boxSigma(width: w) * u, requested: sigma)
        case .tentWidth:
            let w = nearestOdd(2 * (6 * t * t + 1).squareRoot() - 1)
            return nearestResult(typed: w, achieved: tentSigma(width: w) * u, requested: sigma)
        case .svgThreeBox:
            if t < 2 { return SemanticsInverse(typed: t, status: .exact, achievedSigmaPx: sigma) }
            let centre = (2 * t).rounded()
            var best = (d: 4.0, err: Double.infinity)
            for d in stride(from: max(4, centre - 4), through: centre + 4, by: 1) {
                let err = abs(svgThreeBoxSigma(d: d) - t)
                if err < best.err { best = (d, err) }
            }
            let s = max(2, best.d / svgBoxFactor)
            return nearestResult(typed: s, achieved: svgThreeBoxSigma(d: svgThreeBoxWidth(stdDeviation: s)) * u, requested: sigma)
        case .impeller:
            // σ_eff rises with σ up to the peak of σ′ (σ ≈ 219); search there by bisection.
            let peak = 219.0
            if t > impellerEffectiveSigma(peak) { return SemanticsInverse(typed: nil, status: .aboveRange, achievedSigmaPx: nil) }
            var lo = 0.0, hi = peak
            for _ in 0..<80 { let mid = (lo + hi) / 2; if impellerEffectiveSigma(mid) < t { lo = mid } else { hi = mid } }
            return nearestResult(typed: hi, achieved: impellerEffectiveSigma(hi) * u, requested: sigma)
        case .opencvKernelRadius:
            let r = max(1, ((t - 0.8) / 0.3 + 1).rounded())
            return nearestResult(typed: r, achieved: opencvSigma(kernelRadius: r) * u, requested: sigma)
        case .constant(let c):
            return abs(c - t) < 1e-9 ? SemanticsInverse(typed: 0, status: .exact, achievedSigmaPx: sigma)
                                     : SemanticsInverse(typed: nil, status: t < c ? .belowRange : .aboveRange, achievedSigmaPx: c * u)
        }
    }

    /// The parameter that gives σ under a piecewise-ratio CalibrationLaw (small ratio up to the switch, large above).
    /// When σ falls in a gap between the two regimes, the switch parameter is the nearest reachable value.
    public static func inverse(_ law: CalibrationLaw, sigmaPx sigma: Double, unitScale u: Double) -> SemanticsInverse {
        guard sigma > 0 else { return SemanticsInverse(typed: 0, status: .exact, achievedSigmaPx: 0) }
        let large = law.largeRatio, small = law.smallRatio ?? law.largeRatio
        guard let sw = law.switchParameter else {
            guard large > 0 else { return SemanticsInverse(typed: nil, status: .aboveRange, achievedSigmaPx: nil) }
            return SemanticsInverse(typed: sigma / (large * u), status: .exact, achievedSigmaPx: sigma)
        }
        if small > 0 {
            let p = sigma / (small * u)
            if p <= sw { return SemanticsInverse(typed: p, status: .exact, achievedSigmaPx: sigma) }
        }
        if large > 0 {
            let p = sigma / (large * u)
            if p > sw { return SemanticsInverse(typed: p, status: .exact, achievedSigmaPx: sigma) }
        }
        return SemanticsInverse(typed: sw, status: .nearest, achievedSigmaPx: law.sigmaPx(parameter: sw, displayScale: u))
    }

    private static func nearestResult(typed: Double, achieved: Double, requested: Double) -> SemanticsInverse {
        let close = abs(achieved - requested) <= 1e-6 * max(1, requested)
        return SemanticsInverse(typed: typed, status: close ? .exact : .nearest, achievedSigmaPx: achieved)
    }

    // MARK: Edge widths (STACK §8 "Edge 10–90 %")

    /// A one-dimensional line-spread shape whose 10–90 % edge width is COMPUTED numerically.
    public enum KernelShape: Sendable, Hashable {
        case gaussian(sigma: Double)
        /// A Gaussian of σ₀ cut at ±halfWidth and renormalised.
        case truncatedGaussian(sigma0: Double, halfWidth: Double)
        /// The continuous convolution of boxes of these widths (one box, a tent, box-cubed …).
        case boxes([Double])
        /// The projection of a uniform disc of this radius (a semicircle).
        case disc(radius: Double)
    }

    /// σ of a shape (second moment of its line-spread function).
    public static func sigma(of shape: KernelShape) -> Double {
        switch shape {
        case .gaussian(let s): return s
        case .truncatedGaussian(let s0, let h):
            guard s0 > 0, h > 0 else { return 0 }
            let a = h / s0
            let phi = exp(-a * a / 2) / (2 * Double.pi).squareRoot()
            return s0 * max(0, 1 - 2 * a * phi / erf(a / 2.0.squareRoot())).squareRoot()
        case .boxes(let ws): return ws.reduce(0) { $0 + $1 * $1 / 12 }.squareRoot()
        case .disc(let r): return r / 2
        }
    }

    /// The Gaussian σ₀ whose truncation at ±cut·σ_eff has second moment σ_eff (Sketch's ±2.5σ kernel, STACK §4.2).
    public static func truncatedGaussian(effectiveSigma s: Double, cutInSigmas c: Double) -> KernelShape {
        var s0 = s
        for _ in 0..<60 {
            let e = sigma(of: .truncatedGaussian(sigma0: s0, halfWidth: c * s))
            guard e > 0 else { break }
            s0 *= s / e
        }
        return .truncatedGaussian(sigma0: s0, halfWidth: c * s)
    }

    /// 10–90 % rise of a hard edge through the shape, in the shape's own units.
    public static func edgeWidth(_ shape: KernelShape) -> Double {
        switch shape {
        case .gaussian(let s):
            return gaussianEdgeFactor * s
        case .truncatedGaussian(let s0, let h):
            guard s0 > 0, h > 0 else { return 0 }
            let n = 3000, step = 2 * h / Double(n)
            let lsf = (0...n).map { i -> Double in let x = -h + Double(i) * step; return exp(-x * x / (2 * s0 * s0)) }
            return crossingWidth(lsf, step: step)
        case .disc(let r):
            guard r > 0 else { return 0 }
            let n = 3000, step = 2 * r / Double(n)
            let lsf = (0...n).map { i -> Double in let x = -r + Double(i) * step; return max(0, r * r - x * x).squareRoot() }
            return crossingWidth(lsf, step: step)
        case .boxes(let widths):
            let ws = widths.filter { $0 > 0 }
            guard !ws.isEmpty else { return 0 }
            let step = ws.reduce(0, +) / 2400
            var lsf: [Double] = [1]
            for w in ws { lsf = boxConvolve(lsf, taps: max(1, Int((w / step).rounded()))) }
            return crossingWidth(lsf, step: step)
        }
    }

    /// Convolution with a run of `taps` ones (moving sum), output length n + taps − 1.
    static func boxConvolve(_ a: [Double], taps m: Int) -> [Double] {
        var out = [Double](repeating: 0, count: a.count + m - 1)
        var running = 0.0
        for i in 0..<out.count {
            if i < a.count { running += a[i] }
            if i - m >= 0, i - m < a.count { running -= a[i - m] }
            out[i] = running
        }
        return out
    }

    /// Distance between the 10 % and 90 % points of the cumulative sum of `lsf` sampled every `step`.
    static func crossingWidth(_ lsf: [Double], step: Double) -> Double {
        let total = lsf.reduce(0, +)
        guard total > 0, lsf.count > 1 else { return 0 }
        func crossing(_ target: Double) -> Double {
            var acc = 0.0
            for (i, v) in lsf.enumerated() {
                let next = acc + v
                if next / total >= target {
                    let f = v > 0 ? (target * total - acc) / v : 0
                    return (Double(i) + f) * step
                }
                acc = next
            }
            return Double(lsf.count) * step
        }
        return crossing(0.9) - crossing(0.1)
    }
}

fileprivate extension Double {
    /// 0 for NaN (σ of a one-tap kernel computed through a square root of a tiny negative).
    var nanToZero: Double { isNaN ? 0 : self }
}
