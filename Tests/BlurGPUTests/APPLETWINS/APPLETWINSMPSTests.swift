import Foundation
import Metal
import Testing
import BlurCore
@testable import BlurGPU

// OWNER: APPLE-TWINS. Metal Performance Shaders twins on the Mac GPU (CAL §5.3): MPSImageGaussianBlur σ = sigma within 1 %;
// MPSImageBox and MPSImageTent with kernel 2r + 1 are the exact separable box and tent, under both edge modes.

@Suite struct APPLETWINS_MPS {
    typealias S = APPLETWINS_Support

    /// CAL §5.3: σ = sigma (0.993–0.998 for σ ≥ 4); acceptance: within 1 %. Isotropic, centred, shift-invariant.
    @MainActor @Test func gaussianSigmaWithinOnePercent() async throws {
        guard let context = try S.context() else { return }
        let runner = AppleTwinRunner(), stamp = S.stamp(context)
        for sigma in [1.0, 2, 4, 8, 16, 32] {
            let e = try await S.edge(runner, .mpsGaussianBlur, sigma, phases: 4, context: context)
            let ratio = e.fit.sigma / sigma
            let centres = e.samples.map { AppleTwinAnalysis.edgeFit(esf: $0.esf, edgePosition: $0.edgePosition).centreOffset }
            let spread = (centres.max() ?? 0) - (centres.min() ?? 0)
            if sigma >= 4 {
                #expect(abs(ratio - 1) <= 0.01, "MPSImageGaussianBlur σ \(sigma): measured/σ \(ratio)")
                // "approximate Gaussian" (Apple): CAL's raw kurtosis −0.05 to −0.11; Gaussian-shaped means |k| < 0.15.
                #expect(abs(e.fit.excessKurtosis) < 0.15, "σ \(sigma): kurtosis \(e.fit.excessKurtosis)")
            }
            #expect(spread < 0.01, "MPSImageGaussianBlur σ \(sigma): centre spread over 4 phases \(spread) px")
            if let k45 = e.fit45?.excessKurtosis { #expect(abs(k45) < 0.15, "σ \(sigma): 45° kurtosis \(k45)") }
            S.record("MPSImageGaussianBlur sigma \(Int(sigma))", [("σ", e.fit.sigma, S.px3), ("σ/sigma", ratio, S.three),
                                                                  ("kurtosis", e.fit.excessKurtosis, S.two),
                                                                  ("centre spread", spread, S.px3)], stamp: stamp,
                     note: sigma < 4 ? "below CAL's σ ≥ 4 range: a pixel-sampled narrow kernel has extra variance" : nil)
        }
    }

    /// Exact box and tent: MPS output equals a Double-precision separable convolution with the same kernel and edge mode.
    @MainActor @Test func boxAndTentAreExact() async throws {
        guard let context = try S.context() else { return }
        let runner = AppleTwinRunner(), stamp = S.stamp(context)
        let w = 72, h = 56, size = ImageSize(width: w, height: h)
        let image = S.pattern(width: w, height: h, seed: 11)
        let input = try await runner.makeTexture(image, size: size, context: context)
        let output = try runner.makeOutput(size: size, context: context)
        for subject in [CalibrationSubject.mpsBox, .mpsTent] {
            for r in [1, 2, 5, 9] {
                for edge in AppleTwinMPSEdge.allCases {
                    let report = try await runner.run(subject, parameter: Double(r), options: AppleTwinOptions(mpsEdge: edge),
                                                      input: input, output: output, context: context)
                    #expect(report.call.contains("kernelWidth: \(2 * r + 1)"))
                    let got = try await context.readTexels(output, region: PixelRegion(origin: .zero, size: size))
                    let weights = subject == .mpsBox ? APPLETWINS_Reference.box(halfWidth: r) : APPLETWINS_Reference.tent(halfWidth: r)
                    let want = APPLETWINS_Reference.separable(image, width: w, height: h, weights: weights, clamp: edge == .clamp)
                    var worst = 0.0
                    for i in 0..<(w * h) { for c in 0..<4 { worst = Swift.max(worst, abs(Double(got[i][c]) - want[i][c])) } }
                    #expect(worst <= 2e-5, "\(subject.title) r \(r) edge \(edge): max |MPS − exact| \(worst)")
                    S.record("\(subject.title) r \(r) edge \(edge.rawValue)", [("max |MPS − exact|", worst, NumberStyle.significant(2))],
                             stamp: stamp)
                }
            }
            // σ from the step edge equals the closed form (CAL: "match to 4 decimals").
            for r in [2, 8] {
                let e = try await S.edge(runner, subject, Double(r), context: context)
                let exact = subject == .mpsBox ? AppleTwinAnalysis.boxSigma(width: 2 * r + 1) : AppleTwinAnalysis.tentSigma(halfWidth: r)
                #expect(abs(e.fit.sigma - exact) < 1e-3, "\(subject.title) r \(r): σ \(e.fit.sigma) vs exact \(exact)")
                #expect(e.fit.supportSamples == 2 * r + 1, "\(subject.title) r \(r): support \(e.fit.supportSamples)")
                S.record("\(subject.title) r \(r) step", [("σ", e.fit.sigma, NumberStyle.decimals(4, unit: "px", spokenUnit: "pixels")),
                                                          ("exact", exact, NumberStyle.decimals(4, unit: "px", spokenUnit: "pixels")),
                                                          ("kurtosis", e.fit.excessKurtosis, S.two)], stamp: stamp)
            }
        }
    }

    /// CAL §5.3: `.zero` (MPS's default) pads with transparent black; `.clamp` clamps.
    @MainActor @Test func edgeModes() async throws {
        guard let context = try S.context() else { return }
        let runner = AppleTwinRunner(), stamp = S.stamp(context)
        let zero = try await runner.edgePolicy(.mpsGaussianBlur, parameter: 8, context: context)
        #expect(zero.verdict == .transparent, "MPS default edge: \(zero)")
        let clamp = try await runner.edgePolicy(.mpsGaussianBlur, parameter: 8, options: AppleTwinOptions(mpsEdge: .clamp), context: context)
        #expect(clamp.verdict == .clamp, "MPS .clamp: \(clamp)")
        for (name, p) in [("zero", zero), ("clamp", clamp)] {
            S.record("MPSImageGaussianBlur sigma 8 edge \(name)", [("white border", p.whiteBorderValue, S.three),
                                                                   ("alpha", p.whiteBorderAlpha, S.three),
                                                                   ("black column border", p.blackColumnBorderValue, S.three)],
                     stamp: stamp, note: "verdict \(p.verdict.rawValue)")
        }
    }
}

/// Double-precision references for the exactness checks.
enum APPLETWINS_Reference {
    static func box(halfWidth r: Int) -> [Double] { [Double](repeating: 1 / Double(2 * r + 1), count: 2 * r + 1) }
    /// Two boxes of r + 1 taps: (r + 1 − |j|)/(r + 1)².
    static func tent(halfWidth r: Int) -> [Double] { (-r...r).map { Double(r + 1 - abs($0)) / Double((r + 1) * (r + 1)) } }

    /// Separable 2-D convolution with zero padding (MPS `.zero`) or clamping.
    static func separable(_ image: [SIMD4<Float>], width w: Int, height h: Int, weights: [Double], clamp: Bool) -> [SIMD4<Double>] {
        let r = weights.count / 2
        func fetch(_ data: [SIMD4<Double>], _ x: Int, _ y: Int) -> SIMD4<Double> {
            if clamp { return data[Swift.min(Swift.max(y, 0), h - 1) * w + Swift.min(Swift.max(x, 0), w - 1)] }
            return x < 0 || y < 0 || x >= w || y >= h ? .zero : data[y * w + x]
        }
        let source = image.map { SIMD4<Double>($0) }
        var horizontal = [SIMD4<Double>](repeating: .zero, count: w * h)
        for y in 0..<h { for x in 0..<w { for (k, wt) in weights.enumerated() { horizontal[y * w + x] += wt * fetch(source, x + k - r, y) } } }
        var out = [SIMD4<Double>](repeating: .zero, count: w * h)
        for y in 0..<h { for x in 0..<w { for (k, wt) in weights.enumerated() { out[y * w + x] += wt * fetch(horizontal, x, y + k - r) } } }
        return out
    }
}
