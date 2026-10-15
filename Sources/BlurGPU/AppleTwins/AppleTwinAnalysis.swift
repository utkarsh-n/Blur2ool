import Foundation
import BlurCore

// OWNER: APPLE-TWINS. Pure, Sendable estimators for what an Apple blur API did to a known pattern (research CAL §3.3):
// the edge-spread → line-spread moments (two-pass σ inside ±6σ, excess kurtosis), the support of the LSF, and the
// 2-D moments of an impulse response (centroid, covariance, principal axes, kurtosis along the major axis).
// These are the twin's own characterisation numbers; the Calibrate fit (erf least squares, model competition) stays
// CALIBRATION's PSFFitter. Nothing here touches Metal, so it runs off the main actor and in `swift test`.

/// The moment fit of one edge-spread function (CAL §3.3 "Moment σ (ESF)").
public struct AppleTwinEdgeFit: Sendable, Codable, Hashable {
    /// LSF centroid relative to the unblurred edge, in pixels (0 for a centred, symmetric kernel).
    public var centreOffset: Double
    /// √(second central moment) of the LSF inside ±max(12, 6σ) of the centroid, in pixels.
    public var sigma: Double
    /// Excess kurtosis of the LSF (Gaussian 0, box³ −0.4, tent −0.6, disc −1.0, box −1.2).
    public var excessKurtosis: Double
    /// LSF samples whose mass exceeds `supportThreshold` × the peak: the kernel's width in whole pixels for a box.
    public var supportSamples: Int
    /// Mass of the LSF that lies on the bright side of the edge (0.5 for a symmetric kernel, 1 for an outward streak).
    public var massBeyondEdge: Double
    /// The line-spread function (first difference of the normalised ESF); sample k sits at t = k + 1 − edgePosition.
    public var lsf: [Double]
}

/// 2-D moments of an impulse response read back from a texture (CAL §3.3 "2-D PSF").
public struct AppleTwinImpulseMoments: Sendable, Codable, Hashable {
    /// Σ of the (mean-RGB) response: 1 for a normalised kernel whose support stayed inside the image.
    public var sum: Double
    public var peak: Double
    /// Centroid minus the impulse pixel's centre (x right, y down), in pixels.
    public var centroidOffset: SIMD2<Double>
    public var sigmaX: Double
    public var sigmaY: Double
    /// Covariance term ⟨dx·dy⟩ (negative when the response runs up-right on screen, since y grows downwards).
    public var covarianceXY: Double
    public var sigmaMajor: Double
    public var sigmaMinor: Double
    /// Angle of the major axis in degrees, counter-clockwise on screen from +x (−90…90).
    public var majorAxisDegrees: Double
    /// Excess kurtosis of the response projected on the major axis (uniform streak −1.2, Gaussian 0).
    public var majorAxisExcessKurtosis: Double
    /// Length of a uniform segment with the same major-axis σ: σ_major · √12 (CAL's streak-length estimator).
    public var uniformStreakLength: Double { sigmaMajor * 12.0.squareRoot() }
}

public enum AppleTwinAnalysis {
    /// Threshold (fraction of the LSF peak) for `supportSamples`.
    public static let supportThreshold = 1e-3

    /// Normalises a raw profile so its first and last `plateau` samples average to 0 and 1.
    public static func normalise(_ profile: [Double], plateau: Int = 4) -> [Double] {
        guard profile.count >= 2 * plateau else { return profile }
        let lo = profile.prefix(plateau).reduce(0, +) / Double(plateau)
        let hi = profile.suffix(plateau).reduce(0, +) / Double(plateau)
        let span = hi - lo
        guard abs(span) > 1e-12 else { return profile.map { _ in 0 } }
        return profile.map { ($0 - lo) / span }
    }

    /// Moment fit of a normalised ESF whose unblurred edge sits `edgePosition` pixels after esf[0]'s left boundary
    /// (pixel k is white when k ≥ edgePosition). Two passes: all samples, then ±max(12, 6σ) around the centroid, which
    /// keeps quantisation noise in the far tails out of σ (CAL §3.3).
    public static func edgeFit(esf: [Double], edgePosition: Double) -> AppleTwinEdgeFit {
        let n = esf.count
        guard n > 4 else {
            return AppleTwinEdgeFit(centreOffset: 0, sigma: 0, excessKurtosis: 0, supportSamples: 0, massBeyondEdge: 0, lsf: [])
        }
        // mass[k] = esf[k] − esf[k−1] sits on the boundary between pixels k−1 and k: t = k − edgePosition.
        var mass = [Double](repeating: 0, count: n)
        for k in 1..<n { mass[k] = esf[k] - esf[k - 1] }
        func moments(centre: Double, window: Double) -> (mu: Double, variance: Double, kurtosis: Double) {
            var s0 = 0.0, s1 = 0.0
            for k in 1..<n {
                let t = Double(k) - edgePosition
                if abs(t - centre) <= window { s0 += mass[k]; s1 += mass[k] * t }
            }
            let mu = s1 / Swift.max(s0, 1e-12)
            var s2 = 0.0, s4 = 0.0
            for k in 1..<n {
                let t = Double(k) - edgePosition
                if abs(t - centre) <= window { let d = t - mu; s2 += mass[k] * d * d; s4 += mass[k] * d * d * d * d }
            }
            let v = s2 / Swift.max(s0, 1e-12), m4 = s4 / Swift.max(s0, 1e-12)
            return (mu, v, v > 0 ? m4 / (v * v) - 3 : 0)
        }
        var m = moments(centre: 0, window: Double(n))
        m = moments(centre: m.mu, window: Swift.max(12, 6 * m.variance.squareRoot()))
        let lsf = Array(mass.dropFirst())
        let peak = lsf.max() ?? 0
        let support = lsf.filter { $0 > supportThreshold * peak }.count
        var beyond = 0.0, total = 0.0
        for k in 1..<n {
            let t = Double(k) - edgePosition
            total += mass[k]
            if t > 0 { beyond += mass[k] } else if t == 0 { beyond += mass[k] / 2 }
        }
        return AppleTwinEdgeFit(centreOffset: m.mu, sigma: m.variance.squareRoot(), excessKurtosis: m.kurtosis,
                                supportSamples: support, massBeyondEdge: total != 0 ? beyond / total : 0, lsf: lsf)
    }

    /// Mean of R, G and B.
    @inline(__always) public static func luminance(_ p: SIMD4<Float>) -> Double { Double(p.x + p.y + p.z) / 3 }

    /// One profile along x: the mean over `rows` rows of mean-RGB (rows are consecutive in `texels`, width `width`).
    public static func columnProfile(_ texels: [SIMD4<Float>], width: Int, rows: Int) -> [Double] {
        var out = [Double](repeating: 0, count: width)
        guard rows > 0, texels.count >= width * rows else { return out }
        for y in 0..<rows { for x in 0..<width { out[x] += luminance(texels[y * width + x]) } }
        return out.map { $0 / Double(rows) }
    }

    /// The profile across a 45° edge (white where x − y ≥ 0): sample j holds the mean of every pixel with
    /// x − y = j − halfWidth inside a band |x + y − (2c − 1)| ≤ band around the image centre c. Samples are one
    /// anti-diagonal apart, i.e. 1/√2 px along the edge normal; the edge sits at index `halfWidth`.
    public static func diagonalProfile(_ texels: [SIMD4<Float>], size n: Int, halfWidth: Int, band: Int) -> [Double] {
        let c = n / 2
        var sum = [Double](repeating: 0, count: 2 * halfWidth), count = [Double](repeating: 0, count: 2 * halfWidth)
        for y in 0..<n {
            for x in 0..<n {
                let d = x - y, s = x + y - (2 * c - 1)
                guard d >= -halfWidth, d < halfWidth, abs(s) <= band else { continue }
                sum[d + halfWidth] += luminance(texels[y * n + x]); count[d + halfWidth] += 1
            }
        }
        return zip(sum, count).map { $1 > 0 ? $0 / $1 : 0 }
    }

    /// 2-D moments of an impulse response (mean RGB) around the impulse pixel's centre.
    public static func impulseMoments(_ texels: [SIMD4<Float>], width: Int, height: Int, impulse: PixelPoint) -> AppleTwinImpulseMoments {
        var s0 = 0.0, sx = 0.0, sy = 0.0, peak = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let v = luminance(texels[y * width + x])
                guard v != 0 else { continue }
                s0 += v; sx += v * Double(x); sy += v * Double(y); peak = Swift.max(peak, v)
            }
        }
        guard s0 > 0 else {
            return AppleTwinImpulseMoments(sum: 0, peak: 0, centroidOffset: .zero, sigmaX: 0, sigmaY: 0, covarianceXY: 0,
                                           sigmaMajor: 0, sigmaMinor: 0, majorAxisDegrees: 0, majorAxisExcessKurtosis: 0)
        }
        let cx = sx / s0, cy = sy / s0
        var vxx = 0.0, vyy = 0.0, vxy = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let v = luminance(texels[y * width + x])
                guard v != 0 else { continue }
                let dx = Double(x) - cx, dy = Double(y) - cy
                vxx += v * dx * dx; vyy += v * dy * dy; vxy += v * dx * dy
            }
        }
        vxx /= s0; vyy /= s0; vxy /= s0
        let trace = vxx + vyy, det = vxx * vyy - vxy * vxy
        let disc = Swift.max(0, trace * trace / 4 - det).squareRoot()
        let major = Swift.max(0, trace / 2 + disc).squareRoot(), minor = Swift.max(0, trace / 2 - disc).squareRoot()
        // Principal angle in image coordinates (y down), then flipped to counter-clockwise on screen.
        let thetaImage = 0.5 * atan2(2 * vxy, vxx - vyy)
        let ux = cos(thetaImage), uy = sin(thetaImage)
        var m2 = 0.0, m4 = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let v = luminance(texels[y * width + x])
                guard v != 0 else { continue }
                let u = (Double(x) - cx) * ux + (Double(y) - cy) * uy
                m2 += v * u * u; m4 += v * u * u * u * u
            }
        }
        m2 /= s0; m4 /= s0
        return AppleTwinImpulseMoments(sum: s0, peak: peak,
                                       centroidOffset: SIMD2(cx - (Double(impulse.x)), cy - (Double(impulse.y))),
                                       sigmaX: vxx.squareRoot(), sigmaY: vyy.squareRoot(), covarianceXY: vxy,
                                       sigmaMajor: major, sigmaMinor: minor, majorAxisDegrees: -thetaImage * 180 / .pi,
                                       majorAxisExcessKurtosis: m2 > 0 ? m4 / (m2 * m2) - 3 : 0)
    }

    /// σ of a discrete box of `width` taps: √((W² − 1)/12) (COMPUTED).
    public static func boxSigma(width: Int) -> Double { (Double(width * width - 1) / 12).squareRoot() }
    /// σ of the separable tent made of two boxes of `r + 1` taps (kernel 2r + 1): √(((r + 1)² − 1)/6) (COMPUTED).
    public static func tentSigma(halfWidth r: Int) -> Double { (Double((r + 1) * (r + 1) - 1) / 6).squareRoot() }
}
