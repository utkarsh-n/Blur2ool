// MeasurePSF.swift — Blur2ool live calibration, iOS-ready (SwiftUI + CoreGraphics only, Swift 6).
//
// Measures what a SwiftUI blur actually does on the device it runs on: it renders a black|white
// step edge through the caller's blur with ImageRenderer, reads the pixels back as Float, and fits the
// edge-spread function. Output is labelled MEASURED in the app.
//
//   let fit = measurePSF(parameter: 8) { $0.blur(radius: 8) }
//   fit?.sigmaPoints   // effective Gaussian sigma in points (moment of the line-spread function)
//
// Why a step edge rather than a single white pixel: on an 8-bit render the impulse response of a
// sigma = 64 blur peaks at ~4e-5, far below one code value, while a step edge spans all 256 levels
// at every sigma. The derivative of the edge (the LSF) is the PSF's marginal, which carries sigma,
// kurtosis (shape) and support.
//
// Check that it typechecks for iOS (never xcodebuild inside iCloud):
//   xcrun swiftc -typecheck -swift-version 6 \
//     -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" -target arm64-apple-ios27.0-simulator MeasurePSF.swift
// Run the self-check on a Mac (writes nothing; prints fits for SwiftUI .blur):
//   swiftc -O -parse-as-library -swift-version 6 -D MEASUREPSF_MAIN MeasurePSF.swift -o "$TMPDIR/measurepsf" && "$TMPDIR/measurepsf"

import SwiftUI
import CoreGraphics

// MARK: - Result

public struct PSFFit: Sendable, Codable {
    public enum Space: String, Sendable, Codable { case encoded, linear }
    public var parameter: Double          // the value passed to the blur (points for SwiftUI radii)
    public var scale: Double              // pixels per point used for the render
    public var space: Space               // space the profile was analysed in (= the blur's working space)
    public var sigmaPixels: Double        // sqrt(2nd central moment of the LSF), device pixels
    public var sigmaPoints: Double        // sigmaPixels / scale
    public var sigmaPerParameter: Double  // sigmaPoints / parameter (SwiftUI .blur: ~1.0 small, ~0.90 large on macOS 27.2)
    public var sigmaLSQPixels: Double     // least-squares erf fit, as sampled-equivalent sigma
    public var gaussianResidualPct: Double // RMS misfit of the erf model over +-4 sigma, % of the step
    public var kurtosis: Double           // excess: Gaussian 0, box^3 -0.4, tent -0.6, disc -1.0, box -1.2
    public var shape: String              // nearest of gaussian / box3 / tent / disc / box by kurtosis
    public var visibleExtentPixels: Double // farthest pixel from the edge centre still 1/255 off the plateau
    public var supportPixels: Double      // farthest LSF sample > 1e-3 of the LSF peak
    public var centreOffsetPixels: Double // LSF centroid minus the true edge position (registration error)
    public var phaseCentreSpreadPixels: Double // max-min centre offset over edge phases (0 = shift-invariant)
    public var phaseSigmaSpreadPct: Double     // (max-min)/mean sigma over edge phases
    public var midEncoded: Double         // sRGB-encoded value at the edge centre: 0.5 gamma-space blend, ~0.735 linear-light
    public var lsf: [Double]              // LSF samples t = -n...n around the edge (sum ~ 1), for plotting
}

// MARK: - Test pattern

/// A black | white vertical step, `size` points, with the edge at `edgeX` points from the left.
public struct CalibrationEdge: View {
    public var size: CGSize
    public var edgeX: CGFloat
    public var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            Color.white
                .frame(width: size.width - edgeX, height: size.height)
                .offset(x: edgeX)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

// MARK: - Measurement

/// Renders `CalibrationEdge` through `blur` with `ImageRenderer` and fits the edge.
/// - Parameters:
///   - parameter: the blur parameter, used only to report sigma / parameter.
///   - scale: device pixels per point; pass `displayScale` to measure what the screen gets (3 on iPhone 15 Pro Max).
///   - colorMode: ImageRenderer working colour mode. `.nonLinear` matches ordinary on-screen SwiftUI.
///   - phases: number of 1-pixel edge offsets to render (>1 tests shift invariance, the signature of downsampling).
///   - blur: applies the blur under test to the pattern, e.g. `{ $0.blur(radius: 8) }`.
@MainActor
public func measurePSF<Content: View>(parameter: CGFloat,
                                      scale: CGFloat = 1,
                                      colorMode: ColorRenderingMode = .nonLinear,
                                      phases: Int = 1,
                                      blur: (CalibrationEdge) -> Content) -> PSFFit? {
    // Canvas: wide enough that the plateaus are reached (|t| <= 6 sigma, sigma <= ~1.2 * parameter)
    // and tall enough that the top/bottom border fade (opaque: false) never reaches the centre rows.
    // `reach`: analysis half-window (points). `margin`: extra canvas beyond it, so that a blur that fades
    // to transparent at the canvas border (opaque: false) cannot reach the analysis window.
    let reach = max(8, ceil(6 * parameter) + 8)
    let margin = max(8, ceil(4 * parameter) + 8)
    let size = CGSize(width: 2 * (reach + margin) + 4, height: max(32, 2 * margin + 16))
    let space: PSFFit.Space = colorMode == .nonLinear ? .encoded : .linear
    var fits: [(centre: Double, profile: Profile)] = []
    for k in 0..<max(1, phases) {
        let edgeX = reach + margin + 2 + CGFloat(k) / scale
        let renderer = ImageRenderer(content: blur(CalibrationEdge(size: size, edgeX: edgeX)))
        renderer.scale = scale
        renderer.colorMode = colorMode
        guard var image = renderer.cgImage else { return nil }
        // macOS 27.2 measurement: .linear returns sRGB-encoded bytes tagged LinearSRGB; read them as sRGB.
        if colorMode == .linear, let srgb = CGColorSpace(name: CGColorSpace.sRGB), let t = image.copy(colorSpace: srgb) { image = t }
        guard let row = centreRows(image, space: space) else { return nil }
        fits.append((Double(edgeX * scale), row))
    }
    guard let first = fits.first else { return nil }
    let window = Double(reach * scale)
    let f0 = fitEdge(first.profile, edge: first.centre, window: window)
    var centres: [Double] = [], sigmas: [Double] = []
    for (i, phase) in fits.enumerated() {
        let f = i == 0 ? f0 : fitEdge(phase.profile, edge: phase.centre, window: window)
        centres.append(f.mu); sigmas.append(f.sigma)
    }
    let sMean = sigmas.reduce(0, +) / Double(sigmas.count)
    let sigmaPt = f0.sigma / Double(scale)
    return PSFFit(parameter: Double(parameter), scale: Double(scale), space: space,
                  sigmaPixels: f0.sigma, sigmaPoints: sigmaPt,
                  sigmaPerParameter: parameter > 0 ? sigmaPt / Double(parameter) : 0,
                  sigmaLSQPixels: f0.sigmaLSQ, gaussianResidualPct: f0.residualPct,
                  kurtosis: f0.kurtosis, shape: shapeName(kurtosis: f0.kurtosis),
                  visibleExtentPixels: f0.visibleExtent, supportPixels: f0.support,
                  centreOffsetPixels: f0.mu,
                  phaseCentreSpreadPixels: (centres.max() ?? 0) - (centres.min() ?? 0),
                  phaseSigmaSpreadPct: sMean > 0 ? ((sigmas.max() ?? 0) - (sigmas.min() ?? 0)) / sMean * 100 : 0,
                  midEncoded: space == .linear ? srgbEncode(f0.midEncoded) : f0.midEncoded, lsf: f0.lsf)
}

// MARK: - Readback

private struct Profile { var values: [Double] }

/// Draws the image so that its 16 centre rows land in a 16-row float RGBA context in the requested
/// space (CG converts colour), then averages them into one row of mean(R,G,B).
private func centreRows(_ image: CGImage, space: PSFFit.Space, rows: Int = 16) -> Profile? {
    let w = image.width, h = image.height
    let name = space == .encoded ? CGColorSpace.extendedSRGB : CGColorSpace.extendedLinearSRGB
    guard let cs = CGColorSpace(name: name),
          let ctx = CGContext(data: nil, width: w, height: rows, bitsPerComponent: 32, bytesPerRow: w * 16, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue),
          let data = ctx.data else { return nil }
    ctx.setBlendMode(.copy)
    ctx.interpolationQuality = .none
    // CG's origin is bottom-left: placing the image at y = -(h - rows)/2 puts its centre rows in the context.
    ctx.draw(image, in: CGRect(x: 0, y: -CGFloat(h - rows) / 2, width: CGFloat(w), height: CGFloat(h)))
    let p = data.bindMemory(to: Float.self, capacity: w * rows * 4)
    let stride = ctx.bytesPerRow / 4
    var out = [Double](repeating: 0, count: w)
    for y in 0..<rows {
        for x in 0..<w { let i = y * stride + x * 4; out[x] += Double(p[i] + p[i + 1] + p[i + 2]) / 3 }
    }
    return Profile(values: out.map { $0 / Double(rows) })
}

// MARK: - Fit

private struct EdgeFit {
    var mu = 0.0, sigma = 0.0, sigmaLSQ = 0.0, residualPct = 0.0, kurtosis = 0.0
    var visibleExtent = 0.0, support = 0.0, midEncoded = 0.0
    var lsf: [Double] = []
}

/// `edge` is the continuous x (pixels) of the step: pixels with centre > edge are white.
/// Only pixels within `window` of the edge are used; the plateaus are the 4 pixels at each end of it.
private func fitEdge(_ prof: Profile, edge: Double, window: Double) -> EdgeFit {
    var f = EdgeFit()
    let x0 = max(0, Int(edge - window)), x1 = min(prof.values.count, Int(edge + window))
    guard x1 - x0 > 16 else { return f }
    let v = Array(prof.values[x0..<x1]), n = v.count
    let edge = edge - Double(x0)                                    // edge position inside the window
    let lo = v.prefix(4).reduce(0, +) / 4, hi = v.suffix(4).reduce(0, +) / 4
    guard hi - lo > 1e-6 else { return f }
    let q = v.map { ($0 - lo) / (hi - lo) }                      // 0 ... 1
    // LSF sample k sits on the boundary between pixel k-1 and k: x = k, t = k - edge
    var mass = [Double](repeating: 0, count: n)
    for i in 1..<n { mass[i] = q[i] - q[i - 1] }
    func moments(centre: Double, window: Double) -> (Double, Double, Double) {
        var s0 = 0.0, s1 = 0.0
        for i in 1..<n { let t = Double(i) - edge; if abs(t - centre) <= window { s0 += mass[i]; s1 += mass[i] * t } }
        let mu = s1 / max(s0, 1e-12)
        var s2 = 0.0, s4 = 0.0
        for i in 1..<n { let t = Double(i) - edge; if abs(t - centre) <= window { let d = t - mu; s2 += mass[i] * d * d; s4 += mass[i] * d * d * d * d } }
        let m2 = s2 / max(s0, 1e-12), m4 = s4 / max(s0, 1e-12)
        return (mu, m2, m2 > 0 ? m4 / (m2 * m2) - 3 : 0)
    }
    var (mu, m2, kurt) = moments(centre: 0, window: Double(n))
    (mu, m2, kurt) = moments(centre: mu, window: max(12, 6 * m2.squareRoot()))
    f.mu = mu; f.sigma = m2.squareRoot(); f.kurtosis = kurt
    // erf least squares on the ESF: q_i = Phi((i + 0.5 - edge - mu) / s), golden section on log s
    let win = max(4, 4.5 * f.sigma)
    let idx = (0..<n).filter { abs(Double($0) + 0.5 - edge - mu) <= win }
    func sse(_ s: Double) -> Double {
        idx.reduce(0) { acc, i in
            let r = q[i] - 0.5 * erfc(-(Double(i) + 0.5 - edge - mu) / (s * 2.0.squareRoot())); return acc + r * r }
    }
    var a = log(0.05), b = log(4000.0)
    let g = (5.0.squareRoot() - 1) / 2
    var c = b - g * (b - a), d = a + g * (b - a), fc = sse(exp(c)), fd = sse(exp(d))
    for _ in 0..<60 {
        if fc < fd { b = d; d = c; fd = fc; c = b - g * (b - a); fc = sse(exp(c)) }
        else { a = c; c = d; fc = fd; d = a + g * (b - a); fd = sse(exp(d)) }
    }
    let s = exp((a + b) / 2)
    f.sigmaLSQ = (s * s + 1.0 / 12).squareRoot()
    f.residualPct = (sse(s) / Double(max(1, idx.count))).squareRoot() * 100
    // visible extent: farthest pixel whose value is >= 1/255 away from its plateau
    var ext = 0.0
    for i in 0..<n where q[i] >= 1.0 / 255 && q[i] <= 254.0 / 255 { ext = max(ext, abs(Double(i) + 0.5 - edge - mu)) }
    f.visibleExtent = ext
    let peak = mass.max() ?? 0
    var sup = 0.0
    for i in 1..<n where mass[i] > 1e-3 * peak { sup = max(sup, abs(Double(i) - edge - mu)) }
    f.support = sup
    // value at the edge centre, expressed sRGB-encoded
    let e = Int(edge.rounded())
    let mid = e > 0 && e < n ? (q[e - 1] + q[e]) / 2 : 0.5
    f.midEncoded = mid  // in the analysis space; measurePSF encodes it when the space is linear
    let half = min(n / 2 - 1, Int(ceil(ext)) + 2)
    if e - half >= 1 && e + half < n { f.lsf = (e - half...e + half).map { (mass[$0] * 1e6).rounded() / 1e6 } }
    return f
}

private func srgbEncode(_ v: Double) -> Double {
    v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
}

private func shapeName(kurtosis k: Double) -> String {
    let refs: [(String, Double)] = [("gaussian", 0), ("box3", -0.4), ("tent", -0.6), ("disc", -1.0), ("box", -1.2)]
    return refs.min { abs($0.1 - k) < abs($1.1 - k) }!.0
}

// MARK: - macOS self-check (not compiled into the app)

#if MEASUREPSF_MAIN
@main
struct MeasurePSFMain {
    @MainActor static func main() {
        print("parameter scale mode        sigma_pt  sigma/param  lsq_px  kurt  shape     extent_px  centreSpread_px  sigmaSpread%")
        for mode in [ColorRenderingMode.nonLinear, .extendedLinear] {
            for r in [1.0, 2, 4, 8, 16, 32, 64] as [CGFloat] {
                guard let f = measurePSF(parameter: r, scale: 1, colorMode: mode, phases: 4, blur: { $0.blur(radius: r) }) else { print("nil"); continue }
                print(String(format: "%6.1f  %4.1f  %-14@ %8.3f  %8.3f  %8.3f  %5.2f  %-8@  %7.1f  %10.3f  %10.2f",
                             r, f.scale, mode == .nonLinear ? "nonLinear" : "extendedLinear", f.sigmaPoints, f.sigmaPerParameter,
                             f.sigmaLSQPixels, f.kurtosis, f.shape, f.visibleExtentPixels, f.phaseCentreSpreadPixels, f.phaseSigmaSpreadPct))
            }
        }
        for s in [2.0, 3.0] as [CGFloat] {
            if let f = measurePSF(parameter: 8, scale: s, blur: { $0.blur(radius: 8) }) {
                print(String(format: "scale %.0f radius 8: sigma_px %.3f sigma_pt %.3f sigma/param %.3f", s, f.sigmaPixels, f.sigmaPoints, f.sigmaPerParameter))
            }
        }
    }
}
#endif
