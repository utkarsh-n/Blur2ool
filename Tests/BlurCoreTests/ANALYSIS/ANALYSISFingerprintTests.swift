import Foundation
import Testing
@testable import BlurCore

// OWNER: ANALYSIS. SPEC §7.4 fingerprint vectors at σ_equiv 4 px, LOOKS MOST LIKE, and the shared excess-kurtosis axis
// (SPEC §7.1 item 6): Gaussian 0, box −1.2, tent −0.6, disc −1.0, box³ −0.4, Laplace +3.

@Suite struct ANALYSIS_FingerprintKurtosis {
    @Test func axisLandmarksAreTheContinuousValues() {
        let landmarks = FingerprintEngine.kurtosisLandmarks
        #expect(landmarks.map(\.id) == ["box", "disc", "tent", "box3", "gaussian", "laplace"])
        let expected: [String: Double] = ["box": -1.2, "disc": -1.0, "tent": -0.6, "box3": -0.4, "gaussian": 0, "laplace": 3]
        for l in landmarks {
            #expect(abs(l.value - expected[l.id]!) < 1e-3, "\(l.label): \(l.value)")
            #expect(l.exact == expected[l.id]!)
            #expect(l.badge.provenance == .computed && l.badge.honestyViolations.isEmpty)
            #expect(l.value >= FingerprintEngine.kurtosisAxisRange.lowerBound - 1e-3 && l.value <= FingerprintEngine.kurtosisAxisRange.upperBound + 1e-3)
        }
        #expect(landmarks.map(\.badge.text) == ["\u{2212}1.2", "\u{2212}1.0", "\u{2212}0.6", "\u{2212}0.4", "0.0", "+3.0"])
        #expect(landmarks.map(\.blur.rawValue) == ["box-blur", "disc-blur", "tent-blur", "iterated-box", "gaussian-blur", "exponential-blur"])
    }

    /// The same statistics from BlurCore's own kernels: discrete box, tent and box³ converge on the landmarks.
    @Test func discreteKernelsConvergeOnTheAxis() {
        let box = AnalysisMath.moments(KernelMath.box(radius: 500))!.excessKurtosis!
        let tent = AnalysisMath.moments(KernelMath.tent(radius: 500))!.excessKurtosis!
        let b = KernelMath.box(radius: 200)
        let box3 = AnalysisMath.moments(KernelMath.convolve(KernelMath.convolve(b, b), b))!.excessKurtosis!
        let gaussian = AnalysisMath.moments(KernelMath.gaussianSampled(sigma: 64, truncation: 8))!.excessKurtosis!
        #expect(abs(box + 1.2) < 1e-4 && abs(tent + 0.6) < 1e-4 && abs(box3 + 0.4) < 1e-4 && abs(gaussian) < 1e-4)
        #expect(abs(box - KernelMath.box(radius: 500).excessKurtosis) < 1e-12)   // same convention as Kernel1D
    }
}

@Suite struct ANALYSIS_FingerprintVectors {
    let engine = FingerprintEngine()

    @Test func gaussianAtSigmaEquivFourAsRun() {
        let v = engine.vector(for: GaussianOperator())
        let k = KernelMath.gaussianSampled(sigma: 4, truncation: 3)   // the held σ 4.0, default truncation 3, sampled
        let axis = AnalysisMath.moments(k)!.excessKurtosis!
        #expect(abs(axis + 0.1333) < 1e-3)                          // truncated at ±3σ: −0.133, not the continuous 0
        #expect(abs(v.excessKurtosisAxis! - axis) < 1e-9)
        #expect(abs(v.excessKurtosis45! - axis / 2) < 1e-9)         // separable: the diagonal sums two axes, κ halves
        #expect(abs(v.minResponse! + 0.0010006) < 2e-6)             // SPEC §5.3 A: −0.0010
        // Truncation ripple crosses zero before the minimum: an independent bisection of KernelMath's H puts it at 0.1457.
        var lo = 0.14, hi = 0.15
        for _ in 0..<60 { let mid = (lo + hi) / 2; if KernelMath.response(k, frequencies: [mid])[0] > 0 { lo = mid } else { hi = mid } }
        #expect(abs(v.firstZero! - lo) < 1e-9 && abs(lo - 0.1457) < 1e-4)
        #expect(abs(v.supportOverSigma! - 12 / k.sigma) < 1e-9)     // the kernel ends at r 12, above 10⁻⁴ of the peak
        #expect(v.linearity == .lsi && v.shiftVariancePx == 0)
        #expect(v.costExponent! > 0.8 && v.costExponent! < 1.1)      // linear-sampled: fetches grow with r
        let truncatedAt4 = engine.vector(for: GaussianOperator(),
                                         request: OperatorRequest(parameters: ParameterValues(["sigma": .double(4), "truncation": .choice("4"),
                                                                                              "discretisation": .choice("sampled")]),
                                                                  variant: GaussianOperator.linearSampled, size: .square(894)),
                                         probe: PixelPoint(x: 447, y: 447))
        #expect(abs(truncatedAt4.excessKurtosisAxis!) < 0.02)       // −0.014: the tails are back
    }

    @Test func separableAndIsotropicDifferAtFortyFiveDegrees() {
        let box = engine.vector(for: ANALYSIS_Fixtures.box)          // σ 4 → w 13
        #expect(abs(box.excessKurtosisAxis! + 1.2 * 170 / 168) < 1e-9)
        #expect(abs(box.excessKurtosis45! - box.excessKurtosisAxis! / 2) < 1e-9)   // a square's diagonal LSF is a triangle
        let tent = engine.vector(for: ANALYSIS_Fixtures.tent)
        #expect(abs(tent.excessKurtosisAxis! + 0.6) < 0.02 && abs(tent.excessKurtosis45! + 0.3) < 0.01)
        let disc = engine.vector(for: ANALYSIS_Fixtures.disc)        // σ 4 → R 8, round
        #expect(abs(disc.excessKurtosisAxis! + 1.0) < 0.03)
        #expect(abs(disc.excessKurtosis45! - disc.excessKurtosisAxis!) < 0.02)       // isotropic: the same at 45°
        #expect(abs(disc.minResponse! + 0.1323) < 0.01)              // the jinc's deepest lobe
    }

    @Test func costExponentsFollowTheAlgorithm() {
        let direct = OperatorRequest(parameters: ParameterValues(["sigma": .double(4), "truncation": .choice("3"), "discretisation": .choice("sampled")]),
                                     variant: GaussianOperator.direct2D, size: .square(894))
        let p2 = engine.vector(for: GaussianOperator(), request: direct, probe: PixelPoint(x: 447, y: 447)).costExponent!
        #expect(p2 > 1.8 && p2 < 2.1)                                // O(r²), fitted only where 2-D direct runs (σ ≤ 8)
        let sat = OperatorRequest(parameters: ParameterValues(["radius": .int(20)]), variant: "fixture-sat-box", size: .square(894))
        #expect(engine.vector(for: ANALYSIS_Fixtures.box, request: sat, probe: PixelPoint(x: 447, y: 447)).costExponent == 0)
        #expect(engine.vector(for: ANALYSIS_Fixtures.median).costExponent! > 1.5)   // window radius in px: O(r²)
        #expect(engine.vector(for: ANALYSIS_Fixtures.zoom).costExponent == nil)    // AMOUNT in %: no size to fit
    }

    @Test func blankCellsStayBlank() {
        let median = engine.vector(for: ANALYSIS_Fixtures.median)
        #expect(median.excessKurtosisAxis == nil && median.minResponse == nil && median.firstZero == nil && median.shiftVariancePx == nil)
        let swiftUI = engine.vector(for: ANALYSIS_Fixtures.swiftUI)   // Tier S: never our model (review fix P-31)
        #expect(swiftUI == FingerprintEngine.blank(linearity: .system))
        let zoom = engine.vector(for: ANALYSIS_Fixtures.zoom)         // LSV: local PSF at the standard probe
        #expect(zoom.excessKurtosisAxis != nil && zoom.shiftVariancePx == nil)
        #expect(engine.referenceProbe(for: .lsv) == PixelPoint(x: 670, y: 447))
    }

    @Test func measuredVectorCarriesOnlyWhatWasMeasured() {
        let shape = ShapeMeasurement(sigmaPx: 4.01, excessKurtosisAxis: -0.45, excessKurtosis45: -0.40, shiftSpreadPx: 0.12,
                                     minResponse: -0.02, millisecondsPerMegapixel: 0.8)
        let v = engine.vector(measured: shape, linearity: .system)
        #expect(v.excessKurtosisAxis == -0.45 && v.excessKurtosis45 == -0.40 && v.minResponse == -0.02 && v.shiftVariancePx == 0.12)
        #expect(v.firstZero == nil && v.supportOverSigma == nil && v.costExponent == nil && v.linearity == .system)
        let nan = ShapeMeasurement(sigmaPx: 4, excessKurtosisAxis: .nan, excessKurtosis45: 0, shiftSpreadPx: 0, minResponse: 0,
                                   millisecondsPerMegapixel: nil)
        #expect(engine.vector(measured: nan, linearity: .lsi).excessKurtosisAxis == nil)
    }
}

@Suite struct ANALYSIS_FingerprintNearest {
    let engine = FingerprintEngine()
    let candidates: [any BlurOperator] = [GaussianOperator(), ANALYSIS_Fixtures.box, ANALYSIS_Fixtures.tent, ANALYSIS_Fixtures.disc,
                                          ANALYSIS_Fixtures.median, ANALYSIS_Fixtures.swiftUI]

    @Test func distanceIsANormalisedRMSOverSharedCells() {
        let g = engine.vector(for: GaussianOperator())
        #expect(FingerprintEngine.distance(g, g)?.distance == 0)
        let onlyKurtosis = FingerprintVector(excessKurtosisAxis: g.excessKurtosisAxis! + 0.42, excessKurtosis45: nil, minResponse: nil,
                                             firstZero: nil, supportOverSigma: nil, linearity: .system, costExponent: nil, shiftVariancePx: nil)
        let d = FingerprintEngine.distance(onlyKurtosis, g)!
        #expect(d.sharedCells == 1)
        #expect(abs(d.distance - 0.1) < 1e-12)                       // 0.42 / 4.2, linearity skipped for .system
        var otherClass = onlyKurtosis; otherClass.linearity = .nonlinear
        #expect(abs(FingerprintEngine.distance(otherClass, g)!.distance - (0.01 + 1) .squareRoot() / 2.0.squareRoot()) < 1e-12)
        let empty = FingerprintEngine.blank(linearity: .lsi)
        #expect(FingerprintEngine.distance(empty, g) == nil)         // nothing shared: not a match
        #expect(FingerprintEngine.distance(g, onlyKurtosis)!.distance == d.distance)
    }

    @Test func looksMostLikeFindsTheGaussianFromAMeasuredShape() {
        let g = engine.vector(for: GaussianOperator())
        let shape = ShapeMeasurement(sigmaPx: 3.97, excessKurtosisAxis: g.excessKurtosisAxis! + 0.01, excessKurtosis45: g.excessKurtosis45! - 0.01,
                                     shiftSpreadPx: 0, minResponse: -0.0011, millisecondsPerMegapixel: 0.8)
        let measured = engine.vector(measured: shape, linearity: .lsi)
        let ranked = engine.ranked(to: measured, among: candidates)
        #expect(ranked.first?.blur == "gaussian-blur")
        #expect(ranked.first!.distance < 0.01)
        #expect(!ranked.contains { $0.blur == "fixture-swiftui" })    // Tier S: blank, never compared with itself
        #expect(!ranked.contains { $0.blur == "fixture-median" })     // no cell in common with a measured shape
        #expect(engine.nearest(to: measured, among: candidates)?.blur == "gaussian-blur")
    }

    @Test func looksMostLikeSeparatesBoxTentAndDisc() {
        for (op, id) in [(ANALYSIS_Fixtures.box, "fixture-box"), (ANALYSIS_Fixtures.tent, "fixture-tent"), (ANALYSIS_Fixtures.disc, "fixture-disc")] as [(any BlurOperator, BlurID)] {
            let v = engine.vector(for: op)
            let shape = ShapeMeasurement(sigmaPx: 4, excessKurtosisAxis: v.excessKurtosisAxis!, excessKurtosis45: v.excessKurtosis45!,
                                         shiftSpreadPx: 0, minResponse: v.minResponse!, millisecondsPerMegapixel: nil)
            #expect(engine.nearest(to: engine.vector(measured: shape, linearity: .system), among: candidates)?.blur == id)
        }
        // "box³ or truncated Gaussian?" (SPEC §7.1 item 11): kurtosis −0.45 on both axes is not a separable box.
        let swiftUILike = engine.vector(measured: ShapeMeasurement(sigmaPx: 9, excessKurtosisAxis: -0.45, excessKurtosis45: -0.45,
                                                                   shiftSpreadPx: 0.1, minResponse: -0.01, millisecondsPerMegapixel: nil),
                                        linearity: .system)
        #expect(engine.nearest(to: swiftUILike, among: candidates)?.blur != "fixture-box")
    }

    @Test func cellsAndDistanceAreHonest() {
        let g = engine.vector(for: GaussianOperator())
        let computed = engine.cells(for: g, evidence: .computed)
        #expect(computed.map(\.id) == ["kurtosisAxis", "kurtosis45", "minResponse", "firstZero", "supportOverSigma", "linearity",
                                       "costExponent", "shiftVariancePx"])
        #expect(computed.allSatisfy { $0.value.honestyViolations.isEmpty })
        #expect(computed[0].value.text == "\u{2212}0.13" && computed[0].value.provenance == .computed)
        #expect(computed[2].value.text == "\u{2212}0.0010")
        let shape = ShapeMeasurement(sigmaPx: 4, excessKurtosisAxis: -0.45, excessKurtosis45: -0.40, shiftSpreadPx: 0.12, minResponse: -0.02,
                                     millisecondsPerMegapixel: nil)
        let evidence = FingerprintEngine.Evidence.measured(ANALYSIS_Fixtures.device, .offscreen)
        let measured = engine.cells(for: engine.vector(measured: shape, linearity: .system), evidence: evidence)
        #expect(measured.allSatisfy { $0.value.honestyViolations.isEmpty })
        #expect(measured[0].value.provenance == .measured && measured[0].value.device != nil && measured[0].value.caption == "OFFSCREEN")
        #expect(measured[3].value.text == "— NOT YET COMPUTED" && measured[3].value.value == nil)
        #expect(measured.allSatisfy { $0.value.provenance != .live })   // no Tier S field is LIVE (SPEC §7.1 item 11)
        let delta = engine.distanceValue(0.0712, evidence: evidence)
        #expect(delta.text == "0.07" && delta.provenance == .measured && delta.honestyViolations.isEmpty)
        let line = engine.looksMostLikeLine(FingerprintEngine.Match(blur: "gaussian-blur", distance: 0.0712, sharedCells: 4),
                                            displayName: "Gaussian blur", evidence: evidence)
        #expect(line.text == "Gaussian blur · Δ 0.07" && line.honestyViolations.isEmpty)
        #expect(engine.looksMostLikeLine(nil, displayName: nil, evidence: .computed).honestyViolations.isEmpty)
        for op in candidates { #expect(engine.cells(for: engine.vector(for: op), evidence: .computed).allSatisfy { $0.value.honestyViolations.isEmpty }) }
    }
}
