// calibrate.swift — Blur2ool live-calibration probe for macOS.
//
// Measures what real Apple blur APIs do to a white impulse, a vertical step edge,
// a 45-degree step edge, 1-px black/white stripes and the image border, and fits
// the effective Gaussian sigma, support, shape, working colour space, shift
// variance (evidence of downsampling) and edge mode.
//
// Self-contained: one file, Apple frameworks only.
// Build (outputs go to $TMPDIR, never into ~/Documents):
//   mkdir -p "$TMPDIR/blur2ool-calibration"
//   swiftc -O -parse-as-library -swift-version 5 calibrate.swift \
//          -o "$TMPDIR/blur2ool-calibration/calibrate"
// Run one suite at a time (a crash in one API cannot lose the others):
//   "$TMPDIR/blur2ool-calibration/calibrate" <suite> <outdir>
//   suites: swiftui, swiftui-scale, swiftui-sweep, swiftui-format, ci, ci-sweep, mps, vimage,
//           shadow, shadow-sweep, merge, selftest (all suites are independent; run them in parallel)
// `merge` combines <outdir>/*.json into <outdir>/calibration-macos.json.

import Foundation
import CoreGraphics
import CoreImage
import SwiftUI
import AppKit
import QuartzCore
import Metal
import MetalPerformanceShaders
import Accelerate

// MARK: - Float RGBA image (row 0 = top row)

struct FImage {
    let w: Int
    let h: Int
    var p: [Float]
    init(w: Int, h: Int, r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 1) {
        self.w = w; self.h = h
        p = [Float](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) { p[i*4] = r; p[i*4+1] = g; p[i*4+2] = b; p[i*4+3] = a }
    }
    init(w: Int, h: Int, p: [Float]) { self.w = w; self.h = h; self.p = p }
    @inline(__always) func i(_ x: Int, _ y: Int) -> Int { (y * w + x) * 4 }
    mutating func set(_ x: Int, _ y: Int, _ r: Float, _ g: Float, _ b: Float, _ a: Float = 1) {
        let k = i(x, y); p[k] = r; p[k+1] = g; p[k+2] = b; p[k+3] = a
    }
    /// Mean of R,G,B (premultiplied as stored).
    @inline(__always) func lum(_ x: Int, _ y: Int) -> Double {
        let k = i(x, y); return Double(p[k] + p[k+1] + p[k+2]) / 3
    }
    @inline(__always) func ch(_ x: Int, _ y: Int, _ c: Int) -> Double { Double(p[i(x, y) + c]) }
    func flippedY() -> FImage {
        var o = FImage(w: w, h: h, p: p)
        for y in 0..<h {
            let src = (h - 1 - y) * w * 4, dst = y * w * 4
            for k in 0..<(w * 4) { o.p[dst + k] = p[src + k] }
        }
        return o
    }
}

enum Space: String, Codable { case encoded, linear }

@inline(__always) func srgbDecode(_ v: Double) -> Double {
    let s = v < 0 ? -1.0 : 1.0, a = abs(v)
    return s * (a <= 0.04045 ? a / 12.92 : pow((a + 0.055) / 1.055, 2.4))
}
@inline(__always) func srgbEncode(_ v: Double) -> Double {
    let s = v < 0 ? -1.0 : 1.0, a = abs(v)
    return s * (a <= 0.0031308 ? a * 12.92 : 1.055 * pow(a, 1 / 2.4) - 0.055)
}
func decodeImage(_ im: FImage) -> FImage {
    var o = im
    for k in 0..<(im.w * im.h) {
        let a = Double(im.p[k*4+3])
        for c in 0..<3 {
            // unpremultiply, decode, premultiply
            let v = a > 1e-6 ? Double(im.p[k*4+c]) / a : 0
            o.p[k*4+c] = Float(srgbDecode(v) * a)
        }
    }
    return o
}

let csEncoded = CGColorSpace(name: CGColorSpace.extendedSRGB)!
let csLinear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
let csSRGB8 = CGColorSpace(name: CGColorSpace.sRGB)!
func cs(_ s: Space) -> CGColorSpace { s == .encoded ? csEncoded : csLinear }

// MARK: - Test images

func makeImpulse(_ n: Int, at: (Int, Int)? = nil) -> FImage {
    var im = FImage(w: n, h: n)
    let (x, y) = at ?? (n / 2, n / 2)
    im.set(x, y, 1, 1, 1)
    return im
}
/// Vertical step: pixels with x >= edge are white.
func makeStep(w: Int, h: Int, edge: Int) -> FImage {
    var im = FImage(w: w, h: h)
    for y in 0..<h { for x in edge..<w { im.set(x, y, 1, 1, 1) } }
    return im
}
/// 45-degree step: pixels with x - y >= 0 are white.
func makeDiag(_ n: Int) -> FImage {
    var im = FImage(w: n, h: n)
    for y in 0..<n { for x in 0..<n where x - y >= 0 { im.set(x, y, 1, 1, 1) } }
    return im
}
/// 1-px vertical black/white stripes.
func makeStripes(_ n: Int) -> FImage {
    var im = FImage(w: n, h: n)
    for y in 0..<n { for x in stride(from: 0, to: n, by: 2) { im.set(x, y, 1, 1, 1) } }
    return im
}
/// Edge-mode probe: uniform white (A) or white with column 0 black (B).
func makeEdgeProbe(_ n: Int, blackColumn: Bool) -> FImage {
    var im = FImage(w: n, h: n, r: 1, g: 1, b: 1, a: 1)
    if blackColumn { for y in 0..<n { im.set(0, y, 0, 0, 0) } }
    return im
}
/// Orientation probe: white top-left quadrant.
func makeOrientation(_ n: Int) -> FImage {
    var im = FImage(w: n, h: n)
    for y in 0..<(n/2) { for x in 0..<(n/2) { im.set(x, y, 1, 1, 1) } }
    return im
}

// MARK: - CGImage conversion and readback

/// 8-bit sRGB RGBA CGImage (premultipliedLast) from an FImage holding encoded values.
func makeCGImage8(_ im: FImage) -> CGImage {
    var bytes = [UInt8](repeating: 0, count: im.w * im.h * 4)
    for k in 0..<(im.w * im.h * 4) { bytes[k] = UInt8(max(0, min(255, (im.p[k] * 255).rounded()))) }
    let ctx = CGContext(data: &bytes, width: im.w, height: im.h, bitsPerComponent: 8, bytesPerRow: im.w * 4,
                        space: csSRGB8, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return ctx.makeImage()!
}

func floatContext(w: Int, h: Int, space: Space) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 32, bytesPerRow: w * 16, space: cs(space),
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue)!
}
func contextToFImage(_ ctx: CGContext) -> FImage {
    let w = ctx.width, h = ctx.height
    let ptr = ctx.data!.bindMemory(to: Float.self, capacity: w * h * 4)
    let rowFloats = ctx.bytesPerRow / 4
    var o = FImage(w: w, h: h)
    for y in 0..<h { for x in 0..<(w * 4) { o.p[y * w * 4 + x] = ptr[y * rowFloats + x] } }
    return o
}
/// Draws a CGImage 1:1 into a float context in the requested space (CG does the colour conversion).
func readback(_ img: CGImage, space: Space) -> FImage {
    let ctx = floatContext(w: img.width, h: img.height, space: space)
    ctx.setBlendMode(.copy)
    ctx.interpolationQuality = .none
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
    return contextToFImage(ctx)
}

// MARK: - 1-D analysis (ESF / marginal)

struct Fit1D: Codable {
    var mu = 0.0                 // centre (px) relative to nominal centre
    var sigmaMoment = 0.0        // sqrt of second central moment of the LSF / marginal
    var sigmaLSQ = 0.0           // least-squares Gaussian fit on the cumulative, as sampled-equivalent sigma sqrt(s^2 + 1/12)
    var kurtosis = 0.0           // excess kurtosis (Gaussian 0, box -1.2, tent -0.6, box^3 -0.4, disc -1.0)
    var bestModel = ""
    var residualPct: [String: Double] = [:]  // RMS residual of each model in % of full scale
    var widths: [String: Double] = [:]       // fitted width parameter of each model
    var r255 = 0.0               // visible extent: max distance from centre where 1/255 < ESF < 254/255
    var rHard = 0.0              // max distance from centre with LSF mass > 1e-4 * max mass
    var staircasePeriod = 0
    var staircaseScore = 0.0     // ~1 smooth, ~p for a piecewise-constant LSF with period p
    var plateauLo = 0.0
    var plateauHi = 0.0
}

func Phi(_ x: Double) -> Double { 0.5 * erfc(-x / 2.0.squareRoot()) }

/// CDFs of unit-mass 1-D shape models with width parameter s.
let models: [(String, (Double, Double) -> Double)] = [
    ("gaussian", { x, s in Phi(x / s) }),
    ("box", { x, a in min(1, max(0, (x + a) / (2 * a))) }),
    ("tent", { x, a in
        let y = x / a
        if y <= -2 { return 0 }; if y <= 0 { return (y + 2) * (y + 2) / 8 }
        if y < 2 { return 1 - (2 - y) * (2 - y) / 8 }; return 1 }),
    ("box3", { x, a in
        let z = (x / a + 3) / 2
        if z <= 0 { return 0 }; if z < 1 { return z * z * z / 6 }
        if z < 2 { return (-2 * z * z * z + 9 * z * z - 9 * z + 3) / 6 }
        if z < 3 { return 1 - (3 - z) * (3 - z) * (3 - z) / 6 }; return 1 }),
    ("disc", { x, r in
        if x <= -r { return 0 }; if x >= r { return 1 }
        return 0.5 + (x * (r * r - x * x).squareRoot()) / (Double.pi * r * r) + asin(x / r) / Double.pi }),
]

func goldenMin(_ lo0: Double, _ hi0: Double, iters: Int = 70, _ f: (Double) -> Double) -> Double {
    // minimise in log space
    var a = log(lo0), b = log(hi0)
    let g = (5.0.squareRoot() - 1) / 2
    var c = b - g * (b - a), d = a + g * (b - a)
    var fc = f(exp(c)), fd = f(exp(d))
    for _ in 0..<iters {
        if fc < fd { b = d; d = c; fd = fc; c = b - g * (b - a); fc = f(exp(c)) }
        else { a = c; c = d; fc = fd; d = a + g * (b - a); fd = f(exp(d)) }
    }
    return exp((a + b) / 2)
}

/// q: cumulative profile sampled at integer t = t0 ..< t0+q.count, already normalised so that
/// far-left -> 0 and far-right -> 1. Q_t is the CDF of the kernel at t + 0.5 (binned model).
func analyzeCumulative(_ q: [Double], t0: Int, lo: Double = 0, hi: Double = 1) -> Fit1D {
    var f = Fit1D(); f.plateauLo = lo; f.plateauHi = hi
    let n = q.count
    guard n > 4 else { return f }
    // mass at t (t0+1 ... t0+n-1)
    var mass = [Double](repeating: 0, count: n)
    for k in 1..<n { mass[k] = q[k] - q[k-1] }
    func moments(window: Double, centre: Double) -> (Double, Double, Double) {
        var s0 = 0.0, s1 = 0.0
        for k in 1..<n { let t = Double(t0 + k); if abs(t - centre) <= window { s0 += mass[k]; s1 += mass[k] * t } }
        let mu = s1 / max(s0, 1e-12)
        var s2 = 0.0, s4 = 0.0
        for k in 1..<n { let t = Double(t0 + k); if abs(t - centre) <= window { let d = t - mu; s2 += mass[k] * d * d; s4 += mass[k] * d * d * d * d } }
        let v = s2 / max(s0, 1e-12), m4 = s4 / max(s0, 1e-12)
        return (mu, v, v > 0 ? m4 / (v * v) - 3 : 0)
    }
    var (mu, v, kurt) = moments(window: Double(n), centre: Double(t0) + Double(n) / 2)
    // second pass: window = 6 sigma (min 12 px) around mu, to keep quantisation noise in far tails out
    let win = max(12.0, 6 * v.squareRoot())
    (mu, v, kurt) = moments(window: win, centre: mu)
    f.mu = mu; f.sigmaMoment = v.squareRoot(); f.kurtosis = kurt
    // model fits on the cumulative within |t - mu| <= max(4 sigma, 4)
    let fitWin = max(4.0, 4.5 * f.sigmaMoment)
    var idx: [Int] = []
    for k in 0..<n { let t = Double(t0 + k); if abs(t - mu) <= fitWin { idx.append(k) } }
    var bestRes = Double.infinity
    for (name, F) in models {
        func sse(_ s: Double) -> Double {
            var e = 0.0
            for k in idx { let t = Double(t0 + k); let r = q[k] - F(t + 0.5 - mu, s); e += r * r }
            return e
        }
        let s = goldenMin(0.05, 2000, sse)
        let rms = (sse(s) / Double(max(idx.count, 1))).squareRoot() * 100
        f.widths[name] = s; f.residualPct[name] = rms
        if name == "gaussian" { f.sigmaLSQ = (s * s + 1.0 / 12).squareRoot() }  // pixel-integrated s -> sampled-equivalent sigma
        if rms < bestRes { bestRes = rms; f.bestModel = name }
    }
    // visible extent (1/255 thresholds on the ESF)
    var tlo = Double.nan, thi = Double.nan
    for k in 0..<n where q[k] >= 1.0 / 255 { tlo = Double(t0 + k); break }
    for k in stride(from: n - 1, through: 0, by: -1) where q[k] <= 254.0 / 255 { thi = Double(t0 + k) + 1; break }
    f.r255 = max(mu - tlo, thi - mu)
    if f.r255.isNaN { f.r255 = 0 }
    // hard support from mass
    let mmax = mass.max() ?? 0
    var rh = 0.0
    for k in 1..<n where mass[k] > 1e-4 * mmax { rh = max(rh, abs(Double(t0 + k) - mu)) }
    f.rHard = rh
    // staircase: periodicity of |second difference| of the cumulative (= first diff of LSF)
    var dd: [Double] = []
    for k in 2..<n { let t = Double(t0 + k); if abs(t - mu) <= max(3 * f.sigmaMoment, 6) { dd.append(abs(mass[k] - mass[k-1])) } }
    if dd.count >= 16 {
        let mean = dd.reduce(0, +) / Double(dd.count)
        var bestP = 0, bestS = 0.0
        var scores: [Int: Double] = [:]
        for p in 2...16 where dd.count >= 2 * p {
            var best = 0.0
            for ph in 0..<p {
                var s = 0.0, c = 0
                var k = ph; while k < dd.count { s += dd[k]; c += 1; k += p }
                best = max(best, s / Double(max(c, 1)))
            }
            scores[p] = mean > 0 ? best / mean : 0
        }
        let top = scores.values.max() ?? 0
        for p in 2...16 { if let s = scores[p], s >= 0.9 * top { bestP = p; bestS = s; break } }
        f.staircasePeriod = bestP; f.staircaseScore = bestS
    }
    return f
}

/// ESF from a vertical step whose edge is between pixels edge-1 and edge.
func analyzeStep(_ im: FImage, edge: Int, window: Int = 400, rowBand: Int = 8, channel: Int? = nil) -> Fit1D {
    let y0 = im.h / 2 - rowBand, y1 = im.h / 2 + rowBand
    let xa = max(0, edge - window), xb = min(im.w, edge + window)
    var prof = [Double](repeating: 0, count: xb - xa)
    for x in xa..<xb {
        var s = 0.0
        for y in y0..<y1 { s += channel.map { im.ch(x, y, $0) } ?? im.lum(x, y) }
        prof[x - xa] = s / Double(y1 - y0)
    }
    let lo = prof.prefix(8).reduce(0, +) / 8, hi = prof.suffix(8).reduce(0, +) / 8
    let q = prof.map { ($0 - lo) / (hi - lo) }
    // q index k <-> pixel x = xa + k <-> t = x - edge
    return analyzeCumulative(q, t0: xa - edge, lo: lo, hi: hi)
}

/// ESF across the 45-degree edge (white where x - y >= 0); profile indexed by d = x - y.
/// Returns sigma along the diagonal direction (variance of (i-j) / 2) and kurtosis of i - j.
func analyzeDiag(_ im: FImage, half: Int = 400, band: Int = 48) -> Fit1D {
    let n = im.w, c = n / 2
    var sum = [Double](repeating: 0, count: 2 * half + 1), cnt = [Double](repeating: 0, count: 2 * half + 1)
    for y in 0..<im.h { for x in 0..<n {
        let d = x - y, s = x + y - (2 * c - 1)
        if abs(d) <= half && abs(s) <= band { sum[d + half] += im.lum(x, y); cnt[d + half] += 1 }
    } }
    var prof = [Double](repeating: 0, count: 2 * half + 1)
    for k in 0..<prof.count { prof[k] = cnt[k] > 0 ? sum[k] / cnt[k] : 0 }
    let lo = prof.prefix(8).reduce(0, +) / 8, hi = prof.suffix(8).reduce(0, +) / 8
    // q_d = CDF of (i - j) at d -> mass at t=d is q_d - q_{d-1}; same convention as the step with t = d
    let q = prof.map { ($0 - lo) / (hi - lo) }
    var f = analyzeCumulative(q, t0: -half, lo: lo, hi: hi)
    // convert from units of (i - j) to distance along the diagonal: divide sigma by sqrt(2)
    let r2 = 2.0.squareRoot()
    f.sigmaMoment /= r2; f.sigmaLSQ /= r2; f.r255 /= r2; f.rHard /= r2; f.mu /= r2
    return f
}

/// The LSF (first difference of the normalised ESF) around the edge, t = -n...n, n = ceil(r255) + 2.
func lsfSamples(_ im: FImage, edge: Int, f: Fit1D, rowBand: Int = 8) -> [Double] {
    let n = min(400, Int(ceil(max(f.r255, f.rHard))) + 2)
    var prof: [Double] = []
    for x in (edge - n - 1)...(edge + n) {
        var s = 0.0
        for y in (im.h / 2 - rowBand)..<(im.h / 2 + rowBand) { s += im.lum(x, y) }
        prof.append((s / Double(2 * rowBand) - f.plateauLo) / max(1e-12, f.plateauHi - f.plateauLo))
    }
    var out: [Double] = []
    for k in 1..<prof.count { out.append(prof[k] - prof[k - 1]) }
    return out.map { ($0 * 1e6).rounded() / 1e6 }
}

// MARK: - 2-D PSF analysis

struct PSF2D: Codable {
    var cx = 0.0, cy = 0.0            // centroid relative to the impulse pixel
    var sum = 0.0, peak = 0.0
    var sigmaX = 0.0, sigmaY = 0.0, sigmaMoment = 0.0
    var sigmaMajor = 0.0, sigmaMinor = 0.0, angleDeg = 0.0
    var sigmaLSQ = 0.0, lsqResidualPct = 0.0   // isotropic 2-D Gaussian fit, RMS residual % of peak
    var r255 = 0.0          // max distance from centroid with value >= peak/255
    var r1e4 = 0.0          // max distance from centroid with value >= 1e-4 * peak (hard support)
    var halfMaxAxis = 0.0, halfMaxDiag = 0.0, tenthMaxAxis = 0.0, tenthMaxDiag = 0.0
    var marginalX = Fit1D()
    var negativeLobePct = 0.0  // most negative value as % of peak (ringing)
    var diagSigma = 0.0        // sigma of the PSF projected on the 45-degree direction
    var diagKurtosis = 0.0     // excess kurtosis of that projection (= axis kurtosis if isotropic; half of it if separable)
}

func bilinear(_ im: FImage, _ x: Double, _ y: Double) -> Double {
    let x0 = Int(floor(x)), y0 = Int(floor(y))
    guard x0 >= 0, y0 >= 0, x0 + 1 < im.w, y0 + 1 < im.h else { return 0 }
    let fx = x - Double(x0), fy = y - Double(y0)
    return im.lum(x0, y0) * (1 - fx) * (1 - fy) + im.lum(x0 + 1, y0) * fx * (1 - fy)
        + im.lum(x0, y0 + 1) * (1 - fx) * fy + im.lum(x0 + 1, y0 + 1) * fx * fy
}

func analyzePSF(_ im: FImage, impulse: (Int, Int)) -> PSF2D {
    var r = PSF2D()
    var s0 = 0.0, sx = 0.0, sy = 0.0, pk = -Double.infinity, mn = 0.0
    for y in 0..<im.h { for x in 0..<im.w {
        let v = im.lum(x, y); if v == 0 { continue }
        s0 += v; sx += v * Double(x); sy += v * Double(y); pk = max(pk, v); mn = min(mn, v)
    } }
    guard s0 > 0 else { return r }
    let cx = sx / s0, cy = sy / s0
    var vxx = 0.0, vyy = 0.0, vxy = 0.0
    var r255 = 0.0, r1e4 = 0.0
    for y in 0..<im.h { for x in 0..<im.w {
        let v = im.lum(x, y); if v == 0 { continue }
        let dx = Double(x) - cx, dy = Double(y) - cy
        vxx += v * dx * dx; vyy += v * dy * dy; vxy += v * dx * dy
        let d = (dx * dx + dy * dy).squareRoot()
        if v >= pk / 255 { r255 = max(r255, d) }
        if v >= pk * 1e-4 { r1e4 = max(r1e4, d) }
    } }
    vxx /= s0; vyy /= s0; vxy /= s0
    r.cx = cx - Double(impulse.0); r.cy = cy - Double(impulse.1)
    r.sum = s0; r.peak = pk
    r.sigmaX = vxx.squareRoot(); r.sigmaY = vyy.squareRoot(); r.sigmaMoment = ((vxx + vyy) / 2).squareRoot()
    let tr = vxx + vyy, det = vxx * vyy - vxy * vxy
    let disc = max(0, tr * tr / 4 - det).squareRoot()
    r.sigmaMajor = max(0, tr / 2 + disc).squareRoot(); r.sigmaMinor = max(0, tr / 2 - disc).squareRoot()
    r.angleDeg = 0.5 * atan2(2 * vxy, vxx - vyy) * 180 / Double.pi
    r.r255 = r255; r.r1e4 = r1e4
    r.negativeLobePct = mn < 0 ? -mn / pk * 100 : 0
    // isotropic Gaussian LSQ fit (amplitude closed form), window radius
    let R = min(Double(min(im.w, im.h)) / 2 - 1, max(6, 5 * r.sigmaMoment + 3))
    let xa = max(0, Int(cx - R)), xb = min(im.w - 1, Int(cx + R)), ya = max(0, Int(cy - R)), yb = min(im.h - 1, Int(cy + R))
    func fit(_ s: Double) -> (Double, Double) {
        var sig = 0.0, gg = 0.0
        for y in ya...yb { for x in xa...xb {
            let dx = Double(x) - cx, dy = Double(y) - cy
            let g = exp(-(dx * dx + dy * dy) / (2 * s * s)); sig += g * im.lum(x, y); gg += g * g
        } }
        let A = sig / max(gg, 1e-30)
        var e = 0.0
        for y in ya...yb { for x in xa...xb {
            let dx = Double(x) - cx, dy = Double(y) - cy
            let d = im.lum(x, y) - A * exp(-(dx * dx + dy * dy) / (2 * s * s)); e += d * d
        } }
        return (e, A)
    }
    let s = goldenMin(0.1, 1000, iters: 50) { fit($0).0 }
    let (e, _) = fit(s)
    let npx = Double((xb - xa + 1) * (yb - ya + 1))
    r.sigmaLSQ = s; r.lsqResidualPct = (e / npx).squareRoot() / pk * 100
    // contour radii along +x axis and along the (1,1) diagonal, by bilinear sampling
    func radius(level: Double, dir: (Double, Double)) -> Double {
        var t = 0.0
        while t < R * 2 { if bilinear(im, cx + dir.0 * t, cy + dir.1 * t) < level * pk { return t }; t += 0.05 }
        return t
    }
    let rs = 1 / 2.0.squareRoot()
    r.halfMaxAxis = radius(level: 0.5, dir: (1, 0)); r.halfMaxDiag = radius(level: 0.5, dir: (rs, rs))
    r.tenthMaxAxis = radius(level: 0.1, dir: (1, 0)); r.tenthMaxDiag = radius(level: 0.1, dir: (rs, rs))
    // projection on the diagonal: distribution of (dx + dy)/sqrt(2)
    do {
        var m2 = 0.0, m4 = 0.0
        for y in 0..<im.h { for x in 0..<im.w {
            let v = im.lum(x, y); if v == 0 { continue }
            let u = ((Double(x) - cx) + (Double(y) - cy)) / 2.0.squareRoot()
            m2 += v * u * u; m4 += v * u * u * u * u
        } }
        m2 /= s0; m4 /= s0
        r.diagSigma = m2.squareRoot(); r.diagKurtosis = m2 > 0 ? m4 / (m2 * m2) - 3 : 0
    }
    // marginal along x -> cumulative -> 1-D shape fit
    var marg = [Double](repeating: 0, count: im.w)
    for y in 0..<im.h { for x in 0..<im.w { marg[x] += im.lum(x, y) } }
    var q = [Double](repeating: 0, count: im.w), acc = 0.0
    for x in 0..<im.w { acc += marg[x]; q[x] = acc / s0 }
    // Q_x = CDF at x + 0.5 relative to impulse pixel centre: t = x - impulse.x
    r.marginalX = analyzeCumulative(q, t0: -impulse.0)
    return r
}

// MARK: - Records

struct EdgeProbe: Codable {
    var whiteEdgeValue = 0.0      // lum at column 0 of an all-white input (premultiplied)
    var whiteEdgeAlpha = 0.0
    var blackColEdgeValue = 0.0   // lum at column 0 when input column 0 is black
    var whiteCentre = 0.0
    var outside4Alpha: Double? = nil  // alpha 4 px outside the original bounds (if the API can draw there)
    var verdict = ""
}

struct Record: Codable {
    var api: String
    var variant: String
    var paramName: String
    var param: Double
    var readSpace: String = ""
    var stripesEncoded: Double? = nil    // mean encoded value of blurred 1-px B/W stripes (0.5 gamma-space, 0.735 linear)
    var stripesFlat: Double? = nil       // std-dev over the probe area (small = fully averaged)
    var colourVerdict: String? = nil
    var stepMidEncoded: Double? = nil    // encoded value of the two pixels at the step edge (0.5 gamma, ~0.735 linear)
    var esf: Fit1D? = nil
    var esfDiag: Fit1D? = nil
    var shiftCentroidErrPx: Double? = nil
    var shiftSigmaSpreadPct: Double? = nil
    var shiftSigmas: [Double]? = nil
    var shiftMus: [Double]? = nil         // fitted edge centre relative to the edge, per phase
    var lsf: [Double]? = nil              // measured line-spread function at phase 0, t = -n...n (sums to ~1)
    var psf: PSF2D? = nil
    var edge: EdgeProbe? = nil
    var outputBitDepth: String = ""
    var ms: Double? = nil                // wall time of one ESF render (indicative only)
    var notes: [String] = []
}

struct Machine: Codable { var os: String; var build: String; var model: String; var chip: String; var date: String; var swift: String }

// MARK: - Pipeline abstraction

struct Pipeline {
    var api: String
    var variant: String
    var paramName: String
    var bitDepth: String
    var canPad: Bool
    /// Run the blur on `input` (encoded sRGB values) with `param`, read back in `space`.
    /// If `pad` > 0 and the API can draw outside the input, the output is padded on every side.
    var run: (_ input: FImage, _ param: Double, _ space: Space, _ pad: Int) -> FImage?
    var tests: Set<String> = ["colour", "esf", "shift", "diag", "impulse", "edge"]
    var impulseAt: ((Int) -> (Int, Int))? = nil
    var notes: [String] = []
}

func now() -> Double { CFAbsoluteTimeGetCurrent() }

/// ESF canvas: wide enough that a zero-padded border is > 10 sigma away from the measurement window at sigma = 64.
let esfW = 2048, esfH = 512, esfEdge = 1024, stripesN = 768
let shiftPhases = 16

func mean(_ im: FImage, x0: Int, y0: Int, n: Int) -> (Double, Double) {
    var s = 0.0, s2 = 0.0
    for y in y0..<(y0 + n) { for x in x0..<(x0 + n) { let v = im.lum(x, y); s += v; s2 += v * v } }
    let m = s / Double(n * n)
    return (m, max(0, s2 / Double(n * n) - m * m).squareRoot())
}

func measure(_ pl: Pipeline, params: [Double], log: (String) -> Void) -> [Record] {
    var out: [Record] = []
    // orientation check (once)
    var flip = false
    if let o = pl.run(makeOrientation(128), 2, .encoded, 0) {
        let top = mean(o, x0: 8, y0: 8, n: 40).0, bottom = mean(o, x0: 8, y0: 80, n: 40).0
        flip = bottom > top
        if flip { log("  [orientation] \(pl.api) \(pl.variant): output is vertically flipped; correcting") }
    }
    func run(_ im: FImage, _ p: Double, _ s: Space, _ pad: Int = 0) -> FImage? {
        guard let o = pl.run(im, p, s, pad) else { return nil }
        return flip ? o.flippedY() : o
    }
    for p in params {
        var rec = Record(api: pl.api, variant: pl.variant, paramName: pl.paramName, param: p)
        rec.outputBitDepth = pl.bitDepth
        rec.notes = pl.notes
        var space = Space.encoded
        if pl.tests.contains("colour"), let o = run(makeStripes(stripesN), p, .encoded) {
            let (m, sd) = mean(o, x0: stripesN / 2 - 32, y0: stripesN / 2 - 32, n: 64)
            rec.stripesEncoded = m; rec.stripesFlat = sd
            if sd > 0.05 { rec.colourVerdict = "not flat at this parameter (stripes not averaged)" }
            else if m < 0.56 { rec.colourVerdict = "gamma-encoded (sRGB values averaged directly)" }
            else if m > 0.70 { rec.colourVerdict = "linear-light (decoded, averaged, re-encoded)" }
            else { rec.colourVerdict = "intermediate (\(String(format: "%.3f", m)))" }
            if m > 0.62 && sd <= 0.05 { space = .linear }
        }
        rec.readSpace = space.rawValue
        if pl.tests.contains("esf") {
            var sigmas: [Double] = [], mus: [Double] = []
            let shifts = pl.tests.contains("shift") ? Array(0..<shiftPhases) : [0]
            for k in shifts {
                let t = now()
                guard let o = run(makeStep(w: esfW, h: esfH, edge: esfEdge + k), p, space) else { continue }
                if k == 0 { rec.ms = (now() - t) * 1000 }
                let f = analyzeStep(o, edge: esfEdge + k)
                if k == 0 {
                    rec.esf = f
                    rec.lsf = lsfSamples(o, edge: esfEdge, f: f)
                    // step midpoint in encoded terms
                    var mid = 0.0
                    for y in (o.h/2 - 4)..<(o.h/2 + 4) { mid += o.lum(esfEdge - 1, y) + o.lum(esfEdge, y) }
                    mid /= 16
                    let norm = (mid - f.plateauLo) / max(1e-9, f.plateauHi - f.plateauLo)
                    rec.stepMidEncoded = space == .linear ? srgbEncode(norm) : norm
                }
                sigmas.append(f.sigmaMoment); mus.append(f.mu - Double(0))
            }
            if sigmas.count > 1 {
                var err = 0.0
                for k in 0..<mus.count { err = max(err, abs(mus[k] - mus[0])) }  // edge moves with k, t is relative to edge
                rec.shiftCentroidErrPx = err
                let smean = sigmas.reduce(0, +) / Double(sigmas.count)
                rec.shiftSigmaSpreadPct = smean > 0 ? ((sigmas.max()! - sigmas.min()!) / smean * 100) : 0
                rec.shiftSigmas = sigmas
                rec.shiftMus = mus
            }
        }
        if pl.tests.contains("diag"), let o = run(makeDiag(1024), p, space) {
            rec.esfDiag = analyzeDiag(o)
        }
        if pl.tests.contains("impulse") {
            let n = 1024
            let at = pl.impulseAt?(n) ?? (n / 2, n / 2)
            if let o = run(makeImpulse(n, at: at), p, space) {
                let psf = analyzePSF(o, impulse: at)
                // An 8-bit impulse response is only meaningful while its peak spans enough code values.
                if pl.bitDepth == "8-bit" && psf.peak < 32.0 / 255 {
                    rec.notes.append(String(format: "8-bit impulse peak %.1f/255 too low for a 2-D PSF fit; PSF omitted (use ESF).", psf.peak * 255))
                } else { rec.psf = psf }
            }
        }
        if pl.tests.contains("edge") {
            let pad = pl.canPad ? 16 : 0
            if let a = run(makeEdgeProbe(256, blackColumn: false), p, space, pad),
               let b = run(makeEdgeProbe(256, blackColumn: true), p, space, pad) {
                var e = EdgeProbe()
                let ym = a.h / 2
                e.whiteEdgeValue = a.lum(pad, ym); e.whiteEdgeAlpha = a.ch(pad, ym, 3)
                e.blackColEdgeValue = b.lum(pad, ym); e.whiteCentre = a.lum(a.w / 2, ym)
                if pad >= 4 { e.outside4Alpha = a.ch(pad - 4, ym, 3) }
                if e.whiteEdgeAlpha < 0.9 || e.whiteEdgeValue < 0.9 {
                    e.verdict = "transparent/zero outside: border darkens and loses alpha"
                } else if e.blackColEdgeValue < 0.75 {
                    e.verdict = "clamp (edge pixels extended)"
                } else {
                    e.verdict = "border preserved; outside not edge-clamped (mirror or renormalised kernel)"
                }
                if let o4 = e.outside4Alpha { e.verdict += o4 > 0.01 ? "; blur spills outside the original bounds" : "; nothing drawn outside the original bounds" }
                rec.edge = e
            }
        }
        out.append(rec)
        let e = rec.esf, ps = rec.psf
        log(String(format: "  %@ [%@] p=%g  esfσ=%.3f lsq=%.3f σ/p=%.3f r255=%.1f shape=%@ k=%.2f | psfσ=%.3f | stripes=%.3f | shiftErr=%.3f σspread=%.1f%% stair=%d/%.1f",
                   pl.api, pl.variant, p, e?.sigmaMoment ?? .nan, e?.sigmaLSQ ?? .nan, (e?.sigmaMoment ?? .nan) / p,
                   e?.r255 ?? .nan, e?.bestModel ?? "-", e?.kurtosis ?? .nan, ps?.sigmaMoment ?? .nan,
                   rec.stripesEncoded ?? .nan, rec.shiftCentroidErrPx ?? .nan, rec.shiftSigmaSpreadPct ?? .nan,
                   e?.staircasePeriod ?? 0, e?.staircaseScore ?? 0))
    }
    return out
}

/// ESF-only sweep over many parameter values (phase 0 plus 4 phases for shift variance).
func sweep(_ pl: Pipeline, params: [Double], phases: Int = 4, space: Space = .encoded, log: (String) -> Void) -> [Record] {
    var out: [Record] = []
    for p in params {
        var rec = Record(api: pl.api, variant: pl.variant + " [sweep]", paramName: pl.paramName, param: p)
        rec.outputBitDepth = pl.bitDepth; rec.readSpace = space.rawValue
        var sig: [Double] = [], mus: [Double] = []
        for k in 0..<phases {
            guard let o = pl.run(makeStep(w: esfW, h: esfH, edge: esfEdge + k), p, space, 0) else { continue }
            let f = analyzeStep(o, edge: esfEdge + k)
            if k == 0 { rec.esf = f; rec.lsf = lsfSamples(o, edge: esfEdge, f: f) }
            sig.append(f.sigmaMoment); mus.append(f.mu)
        }
        if sig.count > 1 {
            rec.shiftSigmas = sig; rec.shiftMus = mus
            rec.shiftCentroidErrPx = mus.map { abs($0 - mus[0]) }.max()
            let m = sig.reduce(0, +) / Double(sig.count)
            rec.shiftSigmaSpreadPct = (sig.max()! - sig.min()!) / m * 100
        }
        if let e = rec.esf {
            log(String(format: "  %@ [%@] p=%g  σ=%.3f lsq=%.3f σ/p=%.3f k=%.2f best=%@ r255=%.1f shiftErr=%.3f spread=%.2f%% mus=%@", pl.api, pl.variant, p, e.sigmaMoment, e.sigmaLSQ, e.sigmaMoment / p, e.kurtosis, e.bestModel, e.r255, rec.shiftCentroidErrPx ?? 0, rec.shiftSigmaSpreadPct ?? 0, (rec.shiftMus ?? []).map { String(format: "%.2f", $0) }.joined(separator: ",")))
        }
        out.append(rec)
    }
    return out
}

// MARK: - SwiftUI pipelines

@MainActor
func swiftUIPipeline(opaque: Bool, mode: ColorRenderingMode, modeName: String, cgContextPath: Bool = false, scale: CGFloat = 1, retagAsSRGB: Bool = false) -> Pipeline {
    var pl = Pipeline(api: "SwiftUI .blur(radius:)",
                      variant: "opaque=\(opaque) colorMode=\(modeName)" + (cgContextPath ? " path=render(into CGContext)" : " path=.cgImage") + (scale != 1 ? " scale=\(scale)" : "") + (retagAsSRGB ? " (output re-tagged sRGB)" : ""),
                      paramName: "radius (pt)", bitDepth: cgContextPath ? "float32 CGContext" : (modeName == "extendedLinear" ? "float16" : "8-bit"),
                      canPad: true, run: { _, _, _, _ in nil })
    pl.run = { input, p, space, pad in
        let cg = makeCGImage8(input)
        let W = CGFloat(input.w + 2 * pad), H = CGFloat(input.h + 2 * pad)
        let view = Image(decorative: cg, scale: 1)
            .interpolation(.none)
            .frame(width: CGFloat(input.w), height: CGFloat(input.h))
            .blur(radius: CGFloat(p), opaque: opaque)
            .frame(width: W, height: H)
        let r = ImageRenderer(content: view)
        r.scale = scale
        r.colorMode = mode
        r.isOpaque = false
        if cgContextPath {
            var result: FImage? = nil
            r.render(rasterizationScale: scale) { size, draw in
                let ctx = floatContext(w: Int(size.width * scale), h: Int(size.height * scale), space: space)
                ctx.scaleBy(x: scale, y: scale)
                draw(ctx)
                result = contextToFImage(ctx)
            }
            return result
        }
        guard var img = r.cgImage else { return nil }
        if retagAsSRGB, let t = img.copy(colorSpace: csSRGB8) { img = t }
        return readback(img, space: space)
    }
    return pl
}

// MARK: - Core Image pipelines

let ciContext = CIContext(options: [.cacheIntermediates: false])

func ciInput(_ im: FImage) -> CIImage {
    let data = im.p.withUnsafeBufferPointer { Data(buffer: $0) }
    return CIImage(bitmapData: data, bytesPerRow: im.w * 16, size: CGSize(width: im.w, height: im.h), format: .RGBAf, colorSpace: csSRGB8)
}
func ciRender(_ img: CIImage, rect: CGRect, space: Space) -> FImage {
    let w = Int(rect.width), h = Int(rect.height)
    var buf = [Float](repeating: 0, count: w * h * 4)
    buf.withUnsafeMutableBytes { ptr in
        ciContext.render(img, toBitmap: ptr.baseAddress!, rowBytes: w * 16, bounds: rect, format: .RGBAf, colorSpace: cs(space))
    }
    return FImage(w: w, h: h, p: buf)
}

func ciPipeline(_ name: String, variant: String = "", paramName: String = "inputRadius", clamp: Bool = false,
                configure: @escaping (CIFilter, Double, FImage) -> Void) -> Pipeline {
    var pl = Pipeline(api: name, variant: variant.isEmpty ? "default CIContext (linear working space, RGBAh)" : variant,
                      paramName: paramName, bitDepth: "float32 readback", canPad: true, run: { _, _, _, _ in nil })
    pl.run = { input, p, space, pad in
        guard let f = CIFilter(name: name) else { return nil }
        var src = ciInput(input)
        if clamp { src = src.clampedToExtent() }
        f.setValue(src, forKey: kCIInputImageKey)
        configure(f, p, input)
        guard var out = f.outputImage else { return nil }
        let rect = CGRect(x: -pad, y: -pad, width: input.w + 2 * pad, height: input.h + 2 * pad)
        out = out.cropped(to: rect)
        return ciRender(out, rect: rect, space: space)
    }
    return pl
}

// MARK: - MPS pipelines

let mtlDevice = MTLCreateSystemDefaultDevice()!
let mtlQueue = mtlDevice.makeCommandQueue()!

func mpsPipeline(_ name: String, paramName: String, edgeMode: MPSImageEdgeMode, edgeName: String,
                 make: @escaping (Double) -> MPSUnaryImageKernel) -> Pipeline {
    var pl = Pipeline(api: name, variant: "rgba32Float textures, edgeMode=\(edgeName)", paramName: paramName,
                      bitDepth: "float32", canPad: false, run: { _, _, _, _ in nil })
    pl.run = { input, p, space, _ in
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: input.w, height: input.h, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]; d.storageMode = .shared
        guard let src = mtlDevice.makeTexture(descriptor: d), let dst = mtlDevice.makeTexture(descriptor: d) else { return nil }
        input.p.withUnsafeBytes { src.replace(region: MTLRegionMake2D(0, 0, input.w, input.h), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: input.w * 16) }
        let k = make(p); k.edgeMode = edgeMode
        let cb = mtlQueue.makeCommandBuffer()!
        k.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: dst)
        cb.commit(); cb.waitUntilCompleted()
        var o = FImage(w: input.w, h: input.h)
        o.p.withUnsafeMutableBytes { dst.getBytes($0.baseAddress!, bytesPerRow: input.w * 16, from: MTLRegionMake2D(0, 0, input.w, input.h), mipmapLevel: 0) }
        // MPS works on raw stored values. Our inputs are encoded sRGB, so raw = encoded.
        return space == .linear ? decodeImage(o) : o
    }
    pl.notes = ["MPS filters raw texture values; with an rgba32Float texture holding sRGB-encoded numbers the blur is in encoded space. An *_srgb pixel format would linearise on read (Metal texture semantics, REFERENCE)."]
    return pl
}

// MARK: - vImage pipelines

func vImagePipeline(_ name: String, tent: Bool, flags: vImage_Flags, flagName: String) -> Pipeline {
    var pl = Pipeline(api: name, variant: "Planar8, kernel = 2*param+1, \(flagName)", paramName: "half-width r (kernel 2r+1)",
                      bitDepth: "8-bit", canPad: false, run: { _, _, _, _ in nil })
    pl.run = { input, p, space, _ in
        let w = input.w, h = input.h
        var srcBytes = [UInt8](repeating: 0, count: w * h), dstBytes = [UInt8](repeating: 0, count: w * h)
        for k in 0..<(w * h) { srcBytes[k] = UInt8(max(0, min(255, (input.p[k*4+1] * 255).rounded()))) }
        let ks = UInt32(2 * Int(p) + 1)
        let err: vImage_Error = srcBytes.withUnsafeMutableBytes { sp in
            dstBytes.withUnsafeMutableBytes { dp in
                var s = vImage_Buffer(data: sp.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w)
                var d = vImage_Buffer(data: dp.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w)
                return tent ? vImageTentConvolve_Planar8(&s, &d, nil, 0, 0, ks, ks, 0, flags)
                            : vImageBoxConvolve_Planar8(&s, &d, nil, 0, 0, ks, ks, 0, flags)
            }
        }
        guard err == kvImageNoError else { return nil }
        var o = FImage(w: w, h: h)
        for k in 0..<(w * h) { let v = Float(dstBytes[k]) / 255; o.p[k*4] = v; o.p[k*4+1] = v; o.p[k*4+2] = v; o.p[k*4+3] = 1 }
        return space == .linear ? decodeImage(o) : o
    }
    pl.notes = ["vImage convolves raw 8-bit values (no colour management): blur is in whatever encoding the buffer holds."]
    return pl
}

// MARK: - Shadow suite (alpha-mask blurs)

/// Draws a white band x in [100, 700) spanning the full height, with a shadow offset by +1100 px in x,
/// into a transparent 2048 x 512 canvas; returns the canvas. The shadow's rising edge is at x = 1200.
let shadowW = 2048, shadowH = 512, shadowOffset = 1100.0, shadowEdge = 1200

func cgShadow(_ blur: Double, float: Bool) -> FImage {
    let ctx: CGContext
    if float { ctx = floatContext(w: shadowW, h: shadowH, space: .encoded) }
    else {
        ctx = CGContext(data: nil, width: shadowW, height: shadowH, bitsPerComponent: 8, bytesPerRow: shadowW * 4,
                        space: csSRGB8, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
    ctx.setShadow(offset: CGSize(width: shadowOffset, height: 0), blur: blur, color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 100, y: -2000, width: 600, height: 6000))
    if float { return contextToFImage(ctx) }
    return readback(ctx.makeImage()!, space: .encoded)
}

func nsShadow(_ blur: Double) -> FImage {
    let ctx = CGContext(data: nil, width: shadowW, height: shadowH, bitsPerComponent: 8, bytesPerRow: shadowW * 4,
                        space: csSRGB8, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let g = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = g
    let s = NSShadow()
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: shadowOffset, height: 0)
    s.shadowColor = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    s.set()
    NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 100, y: -2000, width: 600, height: 6000)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return readback(ctx.makeImage()!, space: .encoded)
}

func caLayerShadow(_ radius: Double) -> FImage {
    let root = CALayer()
    root.frame = CGRect(x: 0, y: 0, width: shadowW, height: shadowH)
    root.contentsScale = 1
    let band = CALayer()
    band.frame = CGRect(x: 100, y: -2000, width: 600, height: 6000)
    band.contentsScale = 1
    band.backgroundColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    band.shadowColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    band.shadowOpacity = 1
    band.shadowRadius = radius
    band.shadowOffset = CGSize(width: shadowOffset, height: 0)
    root.addSublayer(band)
    let ctx = CGContext(data: nil, width: shadowW, height: shadowH, bitsPerComponent: 8, bytesPerRow: shadowW * 4,
                        space: csSRGB8, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    root.render(in: ctx)
    return readback(ctx.makeImage()!, space: .encoded)
}

@MainActor
func swiftUIShadow(_ radius: Double) -> FImage? {
    let view = ZStack(alignment: .topLeading) {
        Color.clear
        Rectangle().fill(Color.white)
            .frame(width: 600, height: CGFloat(shadowH))
            .shadow(color: .white, radius: CGFloat(radius), x: CGFloat(shadowOffset), y: 0)
            .offset(x: 100)
    }.frame(width: CGFloat(shadowW), height: CGFloat(shadowH))
    let r = ImageRenderer(content: view)
    r.scale = 1; r.isOpaque = false
    guard let img = r.cgImage else { return nil }
    return readback(img, space: .encoded)
}

func shadowRecord(api: String, variant: String, paramName: String, p: Double, im: FImage, notes: [String] = []) -> Record {
    var rec = Record(api: api, variant: variant, paramName: paramName, param: p)
    rec.readSpace = "alpha channel"
    rec.esf = analyzeStep(im, edge: shadowEdge, window: 300, rowBand: 8, channel: 3)
    // LSF from the alpha channel
    var a = im; for k in 0..<(im.w * im.h) { let v = im.p[k*4+3]; a.p[k*4] = v; a.p[k*4+1] = v; a.p[k*4+2] = v }
    rec.lsf = lsfSamples(a, edge: shadowEdge, f: rec.esf!)
    rec.outputBitDepth = variant.contains("float") ? "float32" : "8-bit"
    rec.colourVerdict = "n/a (alpha-mask blur; colour is a single shadow colour composited over the destination)"
    rec.notes = notes
    return rec
}

// MARK: - Main

func machine() -> Machine {
    func sh(_ cmd: String, _ args: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: cmd); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; try? p.run(); p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    return Machine(os: "macOS " + sh("/usr/bin/sw_vers", ["-productVersion"]), build: sh("/usr/bin/sw_vers", ["-buildVersion"]),
                   model: sh("/usr/sbin/sysctl", ["-n", "hw.model"]), chip: sh("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"]),
                   date: ISO8601DateFormatter().string(from: Date()), swift: "compiled with swiftc (see doc)")
}

func write(_ recs: [Record], to path: String) {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    enc.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
    try! enc.encode(recs).write(to: URL(fileURLWithPath: path))
}

@main
struct Calibrate {
    @MainActor static func main() {
        let args = CommandLine.arguments
        let suite = args.count > 1 ? args[1] : "selftest"
        let outDir = args.count > 2 ? args[2] : NSTemporaryDirectory() + "blur2ool-calibration"
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let params: [Double] = [1, 2, 4, 8, 16, 32, 64]
        let log: (String) -> Void = { print($0); fflush(stdout) }
        var recs: [Record] = []
        switch suite {
        case "selftest":
            // Exact sampled Gaussian through the analysers: must return sigma.
            for s in [1.0, 4, 16] {
                var im = FImage(w: 1024, h: 512)
                let R = Int(ceil(5 * s))
                var k = [Double](repeating: 0, count: 2 * R + 1); var sum = 0.0
                for i in -R...R { k[i + R] = exp(-Double(i * i) / (2 * s * s)); sum += k[i + R] }
                for x in 0..<1024 {
                    var v = 0.0
                    for i in -R...R where x - i >= 512 { v += k[i + R] / sum }
                    for y in 0..<512 { im.set(x, y, Float(v), Float(v), Float(v)) }
                }
                let f = analyzeStep(im, edge: 512)
                log(String(format: "selftest gaussian σ=%g: moment %.4f lsq %.4f kurt %.3f best %@ r255 %.2f (expect %.2f)", s, f.sigmaMoment, f.sigmaLSQ, f.kurtosis, f.bestModel, f.r255, 2.66 * s))
                // box of half-width r
            }
            for r in [2, 8] {
                var im = FImage(w: 1024, h: 512)
                for x in 0..<1024 { let v = Double(min(max(x - 512 + r + 1, 0), 2 * r + 1)) / Double(2 * r + 1); for y in 0..<512 { im.set(x, y, Float(v), Float(v), Float(v)) } }
                let f = analyzeStep(im, edge: 512)
                log(String(format: "selftest box r=%d: moment %.4f (expect %.4f) kurt %.3f best %@", r, f.sigmaMoment, (Double((2*r+1)*(2*r+1) - 1) / 12).squareRoot(), f.kurtosis, f.bestModel))
            }
            return
        case "swiftui":
            let variants: [Pipeline] = [
                swiftUIPipeline(opaque: false, mode: .nonLinear, modeName: "nonLinear"),
                swiftUIPipeline(opaque: true, mode: .nonLinear, modeName: "nonLinear"),
                swiftUIPipeline(opaque: false, mode: .extendedLinear, modeName: "extendedLinear"),
                swiftUIPipeline(opaque: false, mode: .linear, modeName: "linear"),
                swiftUIPipeline(opaque: false, mode: .linear, modeName: "linear", retagAsSRGB: true),
                swiftUIPipeline(opaque: false, mode: .nonLinear, modeName: "nonLinear", cgContextPath: true),
            ]
            for v in variants { recs += measure(v, params: params, log: log) }
        case "swiftui-scale":
            for sc in [2.0, 3.0] {
                var v = swiftUIPipeline(opaque: false, mode: .nonLinear, modeName: "nonLinear", scale: CGFloat(sc))
                v.tests = ["esf"]
                // the step is rendered at scale sc: edge moves to 512*sc in device pixels
                let inner = v.run
                v.run = { im, p, s, pad in inner(im, p, s, pad) }
                for p in [4.0, 8, 16] {
                    if let o = v.run(makeStep(w: 1024, h: 512, edge: 512), p, .encoded, 0) {
                        var rec = Record(api: v.api, variant: v.variant, paramName: v.paramName, param: p)
                        rec.esf = analyzeStep(o, edge: Int(512 * sc), window: 400)
                        rec.readSpace = "encoded"; rec.outputBitDepth = "8-bit"
                        rec.notes = ["ImageRenderer.scale = \(sc); sigma reported in output (device) pixels"]
                        log(String(format: "  scale %g p=%g  σ_px=%.3f  σ_px/(p*scale)=%.3f", sc, p, rec.esf!.sigmaMoment, rec.esf!.sigmaMoment / (p * sc)))
                        recs.append(rec)
                    }
                }
            }
        case "swiftui-sweep":
            let ps: [Double] = [0.25, 0.5, 0.75, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5, 5.5, 6, 6.5, 7, 7.5, 8, 9, 10, 11, 12, 14, 16, 20, 24, 28, 32, 40, 48, 56, 64, 80, 96]
            recs += sweep(swiftUIPipeline(opaque: true, mode: .nonLinear, modeName: "nonLinear"), params: ps, log: log)
            recs += sweep(swiftUIPipeline(opaque: true, mode: .nonLinear, modeName: "nonLinear", cgContextPath: true), params: ps, log: log)
        case "swiftui-format":
            // What CGImage does ImageRenderer hand back in each colour mode? Render a flat 50% sRGB grey with no blur.
            for (name, mode) in [("nonLinear", ColorRenderingMode.nonLinear), ("linear", .linear), ("extendedLinear", .extendedLinear)] {
                let view = Color(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1).frame(width: 8, height: 8)
                let r = ImageRenderer(content: view); r.scale = 1; r.colorMode = mode
                guard let img = r.cgImage else { log("\(name): nil"); continue }
                let data = img.dataProvider!.data! as Data
                let bpc = img.bitsPerComponent
                var raw = ""
                if bpc == 8 { raw = data.prefix(4).map { String($0) }.joined(separator: ",") }
                else if bpc == 16 { raw = data.withUnsafeBytes { p in (0..<4).map { String(format: "%.4f", Float(p.load(fromByteOffset: $0 * 2, as: Float16.self))) }.joined(separator: ",") } }
                else if bpc == 32 { raw = data.withUnsafeBytes { p in (0..<4).map { String(format: "%.4f", p.load(fromByteOffset: $0 * 4, as: Float.self)) }.joined(separator: ",") } }
                let enc = readback(img, space: .encoded).ch(4, 4, 0), lin = readback(img, space: .linear).ch(4, 4, 0)
                log("colorMode=\(name): colorSpace=\(img.colorSpace?.name as String? ?? "nil") bpc=\(bpc) bpp=\(img.bitsPerPixel) alphaInfo=\(img.alphaInfo.rawValue) bitmapInfo=\(img.bitmapInfo.rawValue) raw[0..3]=\(raw) -> CG readback encoded=\(String(format: "%.4f", enc)) linear=\(String(format: "%.4f", lin))")
                var rec = Record(api: "ImageRenderer output format", variant: "colorMode=\(name)", paramName: "-", param: 0)
                rec.notes = ["colorSpace=\(img.colorSpace?.name as String? ?? "nil") bitsPerComponent=\(bpc) bitsPerPixel=\(img.bitsPerPixel) alphaInfo=\(img.alphaInfo.rawValue) bitmapInfo=\(img.bitmapInfo.rawValue)",
                             "input sRGB 0.5 grey; raw first pixel = \(raw); CG-converted readback encoded=\(String(format: "%.4f", enc)) linear=\(String(format: "%.4f", lin)) (expected encoded 0.5000, linear 0.2140)"]
                recs.append(rec)
            }
        case "ci-sweep":
            let ps: [Double] = [0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5, 5.5, 6, 6.5, 7, 7.5, 8, 9, 10, 11, 12, 13, 14, 15, 16, 20, 24, 32, 48, 64]
            for name in ["CIBoxBlur", "CIDiscBlur", "CIGaussianBlur"] {
                recs += sweep(ciPipeline(name, clamp: true) { f, p, _ in f.setValue(p, forKey: kCIInputRadiusKey) }, params: ps, space: .linear, log: log)
            }
            // CIBokehBlur vs CIDiscBlur: pixel-level comparison at defaults
            for p in [4.0, 16, 40] {
                let im = makeImpulse(256)
                let a = ciPipeline("CIDiscBlur") { f, p, _ in f.setValue(p, forKey: kCIInputRadiusKey) }.run(im, p, .linear, 0)!
                let b = ciPipeline("CIBokehBlur") { f, p, _ in f.setValue(p, forKey: kCIInputRadiusKey) }.run(im, p, .linear, 0)!
                var md = 0.0; for k in 0..<a.p.count { md = max(md, Double(abs(a.p[k] - b.p[k]))) }
                let peak = Double(a.p.max() ?? 1)
                log(String(format: "  CIBokehBlur vs CIDiscBlur r=%g: max |diff| = %.3g (peak %.3g)", p, md, peak))
                var rec = Record(api: "CIBokehBlur vs CIDiscBlur", variant: "defaults, impulse 256²", paramName: "inputRadius", param: p)
                rec.notes = [String(format: "max abs pixel difference %.3g; PSF peak %.3g", md, peak)]
                recs.append(rec)
            }
            // CIZoomBlur streak length vs distance from centre
            for dist in [100, 200, 300] {
                for amt in [4.0, 16] {
                    let n = 1024
                    let pl = ciPipeline("CIZoomBlur", paramName: "inputAmount") { f, p, im in
                        f.setValue(CIVector(x: CGFloat(im.w) / 2, y: CGFloat(im.h) / 2), forKey: kCIInputCenterKey); f.setValue(p, forKey: "inputAmount") }
                    let at = (n / 2 + dist, n / 2)
                    let o = pl.run(makeImpulse(n, at: at), amt, .linear, 0)!
                    let ps = analyzePSF(o, impulse: at)
                    var rec = Record(api: "CIZoomBlur", variant: "impulse \(dist) px right of centre", paramName: "inputAmount", param: amt)
                    rec.psf = ps
                    rec.notes = [String(format: "streak centroid +%.2f px (outward), sigma along streak %.2f px -> uniform streak length ~ %.1f px = %.4f x distance", ps.cx, ps.sigmaMajor, ps.sigmaMajor * 12.0.squareRoot(), ps.sigmaMajor * 12.0.squareRoot() / Double(dist))]
                    log("  CIZoomBlur dist=\(dist) amount=\(amt): " + rec.notes[0])
                    recs.append(rec)
                }
            }
        case "shadow-sweep":
            let ps: [Double] = [0.5, 1, 1.5, 2, 3, 4, 5, 6, 8, 10, 12, 16, 20, 24, 32, 48, 64, 96, 128]
            for p in ps {
                let a = shadowRecord(api: "CGContext.setShadow(blur:)", variant: "8-bit sRGB context [sweep]", paramName: "blur", p: p, im: cgShadow(p, float: false))
                let c = shadowRecord(api: "CALayer.shadowRadius", variant: "render(in:) [sweep]", paramName: "shadowRadius", p: p, im: caLayerShadow(p))
                var all = [a, c]
                if let s = swiftUIShadow(p) { all.append(shadowRecord(api: "SwiftUI .shadow(radius:)", variant: "ImageRenderer scale=1 [sweep]", paramName: "radius (pt)", p: p, im: s)) }
                for r in all { let e = r.esf!; log(String(format: "  %@ p=%g σ=%.3f σ/p=%.3f k=%.2f best=%@ r255=%.1f", r.api, p, e.sigmaMoment, e.sigmaMoment / p, e.kurtosis, e.bestModel, e.r255)) }
                recs += all
            }
        case "ci":
            var vs: [Pipeline] = [
                ciPipeline("CIGaussianBlur") { f, p, _ in f.setValue(p, forKey: kCIInputRadiusKey) },
                ciPipeline("CIGaussianBlur", variant: "input.clampedToExtent()", clamp: true) { f, p, _ in f.setValue(p, forKey: kCIInputRadiusKey) },
                ciPipeline("CIBoxBlur") { f, p, _ in f.setValue(p, forKey: kCIInputRadiusKey) },
                ciPipeline("CIDiscBlur") { f, p, _ in f.setValue(p, forKey: kCIInputRadiusKey) },
                ciPipeline("CIMotionBlur", variant: "inputAngle=0 (horizontal)") { f, p, _ in f.setValue(p, forKey: kCIInputRadiusKey); f.setValue(0.0, forKey: kCIInputAngleKey) },
                ciPipeline("CIBokehBlur", variant: "ringAmount=0 ringSize=0.1 softness=1 (defaults)") { f, p, _ in f.setValue(p, forKey: kCIInputRadiusKey) },
            ]
            var zoom = ciPipeline("CIZoomBlur", variant: "inputCenter=image centre; impulse 200 px right of centre", paramName: "inputAmount") { f, p, im in
                f.setValue(CIVector(x: CGFloat(im.w) / 2, y: CGFloat(im.h) / 2), forKey: kCIInputCenterKey)
                f.setValue(p, forKey: "inputAmount")
            }
            zoom.tests = ["impulse"]
            zoom.impulseAt = { n in (n / 2 + 200, n / 2) }
            vs.append(zoom)
            for v in vs { recs += measure(v, params: params, log: log) }
        case "mps":
            let vs: [Pipeline] = [
                mpsPipeline("MPSImageGaussianBlur", paramName: "sigma", edgeMode: .zero, edgeName: "zero (default)") { MPSImageGaussianBlur(device: mtlDevice, sigma: Float($0)) },
                mpsPipeline("MPSImageGaussianBlur", paramName: "sigma", edgeMode: .clamp, edgeName: "clamp") { MPSImageGaussianBlur(device: mtlDevice, sigma: Float($0)) },
                mpsPipeline("MPSImageBox", paramName: "half-width r (kernel 2r+1)", edgeMode: .zero, edgeName: "zero (default)") { MPSImageBox(device: mtlDevice, kernelWidth: 2 * Int($0) + 1, kernelHeight: 2 * Int($0) + 1) },
                mpsPipeline("MPSImageTent", paramName: "half-width r (kernel 2r+1)", edgeMode: .zero, edgeName: "zero (default)") { MPSImageTent(device: mtlDevice, kernelWidth: 2 * Int($0) + 1, kernelHeight: 2 * Int($0) + 1) },
            ]
            for v in vs { recs += measure(v, params: params, log: log) }
        case "vimage":
            var vs: [Pipeline] = [
                vImagePipeline("vImageBoxConvolve_Planar8", tent: false, flags: vImage_Flags(kvImageEdgeExtend), flagName: "kvImageEdgeExtend"),
                vImagePipeline("vImageTentConvolve_Planar8", tent: true, flags: vImage_Flags(kvImageEdgeExtend), flagName: "kvImageEdgeExtend"),
                vImagePipeline("vImageBoxConvolve_Planar8", tent: false, flags: vImage_Flags(kvImageTruncateKernel), flagName: "kvImageTruncateKernel"),
                vImagePipeline("vImageBoxConvolve_Planar8", tent: false, flags: vImage_Flags(kvImageBackgroundColorFill), flagName: "kvImageBackgroundColorFill (0)"),
            ]
            for k in 2..<vs.count { vs[k].tests = ["edge"] }
            for v in vs { recs += measure(v, params: params, log: log) }
        case "shadow":
            for p in params {
                let a = shadowRecord(api: "CGContext.setShadow(blur:)", variant: "8-bit sRGB context", paramName: "blur", p: p, im: cgShadow(p, float: false))
                let b = shadowRecord(api: "CGContext.setShadow(blur:)", variant: "float32 context", paramName: "blur", p: p, im: cgShadow(p, float: true))
                let c = shadowRecord(api: "NSShadow.shadowBlurRadius", variant: "8-bit sRGB context", paramName: "shadowBlurRadius", p: p, im: nsShadow(p))
                let d = shadowRecord(api: "CALayer.shadowRadius", variant: "render(in:) into 8-bit sRGB context", paramName: "shadowRadius", p: p, im: caLayerShadow(p),
                                     notes: ["CALayer.render(in:) is the software renderer; on-screen shadows are drawn by the render server and may differ (INFERRED)."])
                var all = [a, b, c, d]
                if let s = swiftUIShadow(p) { all.append(shadowRecord(api: "SwiftUI .shadow(radius:)", variant: "ImageRenderer scale=1 .cgImage", paramName: "radius (pt)", p: p, im: s)) }
                for r in all {
                    let e = r.esf!
                    log(String(format: "  %@ [%@] p=%g  σ=%.3f lsq=%.3f σ/p=%.3f r255=%.1f shape=%@ k=%.2f mu=%.2f", r.api, r.variant, p, e.sigmaMoment, e.sigmaLSQ, e.sigmaMoment / p, e.r255, e.bestModel, e.kurtosis, e.mu))
                }
                recs += all
            }
        case "merge":
            struct Out: Codable { var machine: Machine; var units: [String: String]; var records: [Record] }
            var all: [Record] = []
            for s in ["swiftui", "swiftui-scale", "swiftui-sweep", "swiftui-format", "ci", "ci-sweep", "mps", "vimage", "shadow", "shadow-sweep"] {
                let path = outDir + "/\(s).json"
                if let d = FileManager.default.contents(atPath: path) {
                    let dec = JSONDecoder()
                    dec.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
                    if let r = try? dec.decode([Record].self, from: d) { all += r } else { log("could not decode \(path)") }
                }
            }
            let units = [
                "sigma*": "pixels at scale 1 (one image pixel = one point)",
                "esf": "1-D fit of the line-spread function from a vertical black->white step (marginal of the PSF along x)",
                "esfDiag": "same across a 45-degree edge; sigma is along the diagonal direction",
                "psf": "2-D fit of the impulse response of a single white pixel on black",
                "r255": "visible extent: largest distance from the edge centre where the blurred edge is between 1/255 and 254/255 of the step (Gaussian: 2.66 sigma)",
                "psf.r255": "largest distance from the centroid where the PSF >= peak/255 (Gaussian: 3.33 sigma)",
                "psf.r1e4": "largest distance where the PSF >= 1e-4 * peak (Gaussian: 4.29 sigma); a smaller value means the kernel is truncated",
                "kurtosis": "excess kurtosis of the 1-D marginal: Gaussian 0, box^3 -0.4, tent -0.6, disc -1.0, box -1.2",
                "residualPct": "RMS residual of the best fit of each 1-D model to the cumulative profile, % of full scale",
                "stripesEncoded": "sRGB-encoded mean of blurred 1-px black/white stripes: 0.500 = blur in gamma-encoded space, 0.735 = blur in linear light",
                "shiftCentroidErrPx": "max change of the fitted edge position (relative to the edge) as the step moves by 0..7 px; 0 for a shift-invariant filter",
                "shiftSigmaSpreadPct": "(max-min)/mean of sigma across the 8 edge positions; 0 for a shift-invariant filter",
            ]
            let o = Out(machine: machine(), units: units, records: all)
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            enc.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
            try! enc.encode(o).write(to: URL(fileURLWithPath: outDir + "/calibration-macos.json"))
            log("merged \(all.count) records -> \(outDir)/calibration-macos.json")
            return
        default:
            log("unknown suite \(suite)"); return
        }
        write(recs, to: outDir + "/\(suite).json")
        log("wrote \(recs.count) records -> \(outDir)/\(suite).json")
    }
}
