import Foundation
import Metal
import Testing
import BlurCore
@testable import BlurGPU

// OWNER: APPLE-TWINS. Core Image twins on the Mac GPU, reproducing research CAL §5.2 with the runner's own code path
// (CIContext into Metal textures, Core Image's default border and working space). Every number is MEASURED (Mac).

@Suite struct APPLETWINS_CoreImage {
    typealias S = APPLETWINS_Support

    /// CAL §5.2: CIGaussianBlur σ = inputRadius; acceptance: within 1.5 % (r ≥ 2). At r = 1 the moment σ of the pixel-
    /// sampled kernel is 1.037, exactly CAL's raw record (calibration-macos.json: 1.0369) although CAL's prose quotes
    /// 0.994–1.007 "for r ≥ 1"; it is checked against that record. Gaussian along the axis and along the diagonal
    /// (|kurtosis| < 0.15). The small edge-centre offset at r 32 and 64 is CAL's too (0.10 and 0.14 px in the JSON).
    @MainActor @Test func gaussianSigmaEqualsRadius() async throws {
        guard let context = try S.context() else { return }
        let runner = AppleTwinRunner(), stamp = S.stamp(context)
        for r in [1.0, 2, 4, 8, 16, 32, 64] {
            let e = try await S.edge(runner, .ciGaussianBlur, r, context: context)
            let ratio = e.fit.sigma / r
            if r >= 2 { #expect(abs(ratio - 1) <= 0.015, "CIGaussianBlur r \(r): σ/r \(ratio)") }
            else { #expect(abs(e.fit.sigma - 1.0369) < 0.01, "CIGaussianBlur r 1: σ \(e.fit.sigma) vs CAL's raw 1.0369") }
            #expect(abs(e.fit.excessKurtosis) < 0.15, "CIGaussianBlur r \(r): kurtosis \(e.fit.excessKurtosis)")
            #expect(abs(e.fit.centreOffset) < 0.25, "CIGaussianBlur r \(r): centre \(e.fit.centreOffset)")
            if let k45 = e.fit45?.excessKurtosis { #expect(abs(k45) < 0.15, "r \(r): 45° kurtosis \(k45)") }
            S.record("CIGaussianBlur r \(Int(r))", [("σ", e.fit.sigma, S.px3), ("σ/r", ratio, S.three),
                                                    ("centre", e.fit.centreOffset, S.px3), ("kurtosis", e.fit.excessKurtosis, S.two),
                                                    ("kurtosis 45°", e.fit45?.excessKurtosis ?? .nan, S.two)], stamp: stamp)
        }
    }

    /// CAL §5.2: CIBoxBlur is a separable square box of width W = 2⌈r/2⌉ − 1 (r ≤ 2 → no blur). The LSF of a box is W
    /// equal steps, so its support is exactly W samples and σ = √((W² − 1)/12); the ESF climbs in steps of 1/W.
    @MainActor @Test func boxWidthRule() async throws {
        guard let context = try S.context() else { return }
        let runner = AppleTwinRunner(), stamp = S.stamp(context)
        for radius in 1...16 {
            let r = Double(radius)
            let expected = AppleTwinCatalog.coreImageBoxWidth(radius: r)
            #expect(expected == 2 * Int((r / 2).rounded(.up)) - 1)
            let e = try await S.edge(runner, .ciBoxBlur, r, context: context)
            #expect(e.fit.supportSamples == expected, "CIBoxBlur r \(radius): support \(e.fit.supportSamples) ≠ W \(expected)")
            let sigma = AppleTwinAnalysis.boxSigma(width: expected)
            #expect(abs(e.fit.sigma - sigma) <= 0.01 * Swift.max(sigma, 1), "CIBoxBlur r \(radius): σ \(e.fit.sigma) vs \(sigma)")
            // The ESF itself: (number of box taps on the bright side) / W, in half-float precision.
            let sample = try #require(e.samples.first)
            let reach = Int(sample.edgePosition), h = (expected - 1) / 2
            var worst = 0.0
            for (i, v) in sample.esf.enumerated() {
                let ideal = Double(Swift.min(Swift.max(i - reach + h + 1, 0), expected)) / Double(expected)
                worst = Swift.max(worst, abs(v - ideal))
            }
            #expect(worst < 2e-3, "CIBoxBlur r \(radius): ESF departs from k/W by \(worst)")
            S.record("CIBoxBlur r \(radius)", [("W", Double(e.fit.supportSamples), S.integer), ("σ", e.fit.sigma, S.px3),
                                               ("kurtosis", e.fit.excessKurtosis, S.two),
                                               ("kurtosis 45°", e.fit45?.excessKurtosis ?? .nan, S.two),
                                               ("max |ESF − k/W|", worst, NumberStyle.significant(2))], stamp: stamp)
        }
    }

    /// CAL §5.2: CIDiscBlur is a uniform disc of radius R: σ = R/2, marginal kurtosis −1 (semicircle), isotropic.
    @MainActor @Test func discSigmaIsHalfRadius() async throws {
        guard let context = try S.context() else { return }
        let runner = AppleTwinRunner(), stamp = S.stamp(context)
        for r in [5.0, 8, 16, 32] {
            let e = try await S.edge(runner, .ciDiscBlur, r, context: context)
            let ratio = e.fit.sigma / (r / 2)
            #expect(abs(ratio - 1) <= 0.02, "CIDiscBlur R \(r): σ/(R/2) \(ratio)")
            #expect(abs(e.fit.excessKurtosis + 1) < 0.12, "CIDiscBlur R \(r): kurtosis \(e.fit.excessKurtosis)")
            if let k45 = e.fit45?.excessKurtosis { #expect(abs(k45 - e.fit.excessKurtosis) < 0.12, "R \(r): 45° kurtosis \(k45)") }
            S.record("CIDiscBlur R \(Int(r))", [("σ", e.fit.sigma, S.px3), ("σ/R", e.fit.sigma / r, S.three),
                                                 ("kurtosis", e.fit.excessKurtosis, S.two),
                                                 ("kurtosis 45°", e.fit45?.excessKurtosis ?? .nan, S.two)], stamp: stamp)
        }
    }

    /// CAL §5.2: CIBokehBlur at its default ring and softness is bit-identical to CIDiscBlur.
    @MainActor @Test func bokehEqualsDiscAtDefaults() async throws {
        guard let context = try S.context() else { return }
        let runner = AppleTwinRunner(), stamp = S.stamp(context)
        let size = ImageSize.square(128)
        let input = try await runner.makeTexture(S.pattern(width: 128, height: 128), size: size, format: .rgba16Float, context: context)
        let disc = try runner.makeOutput(size: size, format: .rgba16Float, context: context)
        let bokeh = try runner.makeOutput(size: size, format: .rgba16Float, context: context)
        for r in [4.0, 16] {
            try await runner.run(.ciDiscBlur, parameter: r, input: input, output: disc, context: context)
            try await runner.run(.ciBokehBlur, parameter: r, input: input, output: bokeh, context: context)
            let a = try await context.readTexels(disc, region: PixelRegion(origin: .zero, size: size))
            let b = try await context.readTexels(bokeh, region: PixelRegion(origin: .zero, size: size))
            let worst = zip(a, b).map { S.maxAbs($0 - $1) }.max() ?? .infinity
            #expect(worst <= 1e-3, "CIBokehBlur vs CIDiscBlur r \(r): max |diff| \(worst)")
            S.record("CIBokehBlur vs CIDiscBlur r \(Int(r))", [("max |diff|", Double(worst), NumberStyle.significant(2))], stamp: stamp)
        }
    }

    /// CAL §5.2: CIMotionBlur is a 1-px line with GAUSSIAN weights of σ = inputRadius along inputAngle, centred and
    /// two-sided (acceptance: |excess kurtosis| < 0.15). Its angle turns counter-clockwise on screen.
    @MainActor @Test func motionBlurIsGaussianLine() async throws {
        guard let context = try S.context() else { return }
        let runner = AppleTwinRunner(), stamp = S.stamp(context)
        for r in [4.0, 8, 16, 32] {
            let e = try await S.edge(runner, .ciMotionBlur, r, context: context)
            #expect(abs(e.fit.excessKurtosis) < 0.15, "CIMotionBlur r \(r): kurtosis \(e.fit.excessKurtosis)")
            #expect(abs(e.fit.sigma / r - 1) <= 0.03, "CIMotionBlur r \(r): σ/r \(e.fit.sigma / r)")
            #expect(abs(e.fit.centreOffset) < 0.1, "CIMotionBlur r \(r): centre \(e.fit.centreOffset) (two-sided)")
            let size = ImageSize.square(256), impulse = PixelPoint(x: 128, y: 128)
            let line = try await runner.impulseResponse(.ciMotionBlur, parameter: r, size: size, impulse: impulse, context: context)
            #expect(line.sigmaY < 0.5, "CIMotionBlur r \(r): across-motion σ \(line.sigmaY) (a 1-px line)")
            #expect(abs(line.centroidOffset.x) < 0.25, "CIMotionBlur r \(r): centroid \(line.centroidOffset.x)")
            S.record("CIMotionBlur r \(Int(r)) angle 0", [("σ along", e.fit.sigma, S.px3), ("σ/r", e.fit.sigma / r, S.three),
                                                          ("kurtosis", e.fit.excessKurtosis, S.two), ("σ across", line.sigmaY, S.px3),
                                                          ("impulse sum", line.sum, S.three)], stamp: stamp)
        }
        // Orientation: inputAngle = 45° runs up-right on screen (Core Image's counter-clockwise convention).
        let diagonal = try await runner.impulseResponse(.ciMotionBlur, parameter: 12, options: AppleTwinOptions(angleRadians: .pi / 4),
                                                        size: .square(256), impulse: PixelPoint(x: 128, y: 128), context: context)
        #expect(abs(diagonal.majorAxisDegrees - 45) < 2, "CIMotionBlur angle π/4: major axis \(diagonal.majorAxisDegrees)°")
        #expect(diagonal.covarianceXY < 0, "up-right on screen means y falls as x grows (texture rows grow downwards)")
        S.record("CIMotionBlur r 12 angle π/4", [("major axis", diagonal.majorAxisDegrees, NumberStyle.decimals(1, unit: "°", spokenUnit: "degrees")),
                                                 ("σ major", diagonal.sigmaMajor, S.px3), ("σ minor", diagonal.sigmaMinor, S.px3)], stamp: stamp)
    }

    /// CAL §5.2: CIZoomBlur smears every point into a streak pointing AWAY from inputCenter, with length ∝ distance:
    /// length/distance ≈ 0.079 at amount 4 and ≈ 0.357 at amount 16 (acceptance ± 10 %), the same at d = 100, 200, 300.
    @MainActor @Test func zoomBlurOutwardStreaks() async throws {
        guard let context = try S.context() else { return }
        let runner = AppleTwinRunner(), stamp = S.stamp(context)
        let n = 1024
        let options = AppleTwinOptions(centre: SIMD2(Double(n) / 2, Double(n) / 2))
        for (amount, reference) in [(4.0, 0.079), (16.0, 0.357)] {
            for d in [100, 200, 300] {
                let impulse = PixelPoint(x: n / 2 + d, y: n / 2)
                let m = try await runner.impulseResponse(.ciZoomBlur, parameter: amount, options: options, size: .square(n),
                                                         impulse: impulse, context: context)
                let ratio = m.uniformStreakLength / Double(d)
                #expect(abs(ratio / reference - 1) <= 0.10, "CIZoomBlur amount \(amount) d \(d): ratio \(ratio) vs \(reference)")
                #expect(m.centroidOffset.x > 0, "CIZoomBlur amount \(amount) d \(d): streak must point outward")
                #expect(abs(m.majorAxisDegrees) < 2, "CIZoomBlur: streak along the radius (horizontal here), got \(m.majorAxisDegrees)°")
                S.record("CIZoomBlur amount \(Int(amount)) d \(d)", [("length/d", ratio, S.three),
                                                                     ("centroid outward", m.centroidOffset.x, S.px3),
                                                                     ("kurtosis along", m.majorAxisExcessKurtosis, S.two)], stamp: stamp)
            }
        }
    }

    /// CIMaskedVariableBlur: with a white mask the whole image gets the full radius (a stationary kernel, measured here);
    /// with the default ramp the top row is untouched and the bottom is blurred.
    @MainActor @Test func maskedVariableBlurFollowsMask() async throws {
        guard let context = try S.context() else { return }
        let runner = AppleTwinRunner(), stamp = S.stamp(context)
        for r in [4.0, 16] {
            let e = try await S.edge(runner, .ciMaskedVariableBlur, r, context: context)
            #expect(e.fit.sigma > 0.25 * r && e.fit.sigma < 1.5 * r, "CIMaskedVariableBlur r \(r): σ \(e.fit.sigma)")
            S.record("CIMaskedVariableBlur r \(Int(r)) mask 1", [("σ", e.fit.sigma, S.px3), ("σ/r", e.fit.sigma / r, S.three),
                                                                 ("kurtosis", e.fit.excessKurtosis, S.two),
                                                                 ("kurtosis 45°", e.fit45?.excessKurtosis ?? .nan, S.two)],
                     stamp: stamp, note: "kernel not in CAL; first measurement")
        }
        // Ramp: vertical 1-px stripes; mask 0 at the top row, 1 at the bottom.
        let n = 128, size = ImageSize.square(n)
        let stripes = (0..<(n * n)).map { i -> SIMD4<Float> in (i % n) % 2 == 0 ? SIMD4(1, 1, 1, 1) : SIMD4(0, 0, 0, 1) }
        let input = try await runner.makeTexture(stripes, size: size, format: .rgba16Float, context: context)
        let output = try runner.makeOutput(size: size, format: .rgba16Float, context: context)
        let report = try await runner.run(.ciMaskedVariableBlur, parameter: 8, options: AppleTwinOptions(), input: input,
                                          output: output, context: context)
        #expect(report.call.contains("ramp"))
        let rows = [0, 2, 4, 6, 8, 12, 16, 32, 64, n - 1]
        var contrasts: [Double] = []
        for row in rows {
            let t = try await context.readTexels(output, region: PixelRegion(origin: PixelPoint(x: 32, y: row), size: ImageSize(width: 64, height: 1)))
            let v = t.map { AppleTwinAnalysis.luminance($0) }
            contrasts.append((v.max() ?? 0) - (v.min() ?? 0))
        }
        let top = contrasts[0], bottom = contrasts[contrasts.count - 1]
        #expect(top > 0.95, "top row (mask 0) should stay sharp: stripe contrast \(top)")
        #expect(bottom < 0.1, "bottom row (mask 1, r 8) should be blurred flat: stripe contrast \(bottom)")
        #expect(zip(contrasts, contrasts.dropFirst()).allSatisfy { $1 <= $0 + 0.02 }, "contrast should fall down the ramp: \(contrasts)")
        #expect(contrasts.contains { $0 > 0.1 && $0 < 0.95 }, "the ramp should pass through partial blur: \(contrasts)")
        S.record("CIMaskedVariableBlur r 8 ramp", zip(rows, contrasts).map { ("contrast row \($0)", $1, S.three) }, stamp: stamp)
    }
}
