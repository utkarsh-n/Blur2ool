import Foundation
import Testing
@testable import BlurCore

// OWNER: CALIBRATION. CORE acceptance of ARCHITECTURE §8.2 CALIBRATION / PLAN CALIBRATION item 2: synthetic sampled
// Gaussians σ 1, 4, 16 recovered to 4 decimal places (CAL §3's selftest, which feeds exact kernels through the estimators);
// box excess kurtosis −1.2 and box³ −0.4; shape names; model competition; phase spread; and the law fitted from a synthetic
// sweep finding the regime switch.

/// Synthetic edges: the ESF of a step at an integer `edge` blurred by a discrete kernel (pixel x = Σ_{j ≤ x − edge} w_j,
/// exactly calibrate.swift's selftest), or by a continuous kernel sampled at pixel centres with a sub-pixel `shift`.
enum CALIBRATION_Synthetic {
    static func normalised(_ w: [Double]) -> [Double] { let s = w.reduce(0, +); return w.map { $0 / s } }
    /// Weights for offsets −R…R.
    static func sampledGaussian(_ sigma: Double, truncation: Double = 8) -> [Double] {
        let r = Int((truncation * sigma).rounded(.up))
        return normalised((-r...r).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) })
    }
    static func box(_ width: Int) -> [Double] { [Double](repeating: 1 / Double(width), count: width) }
    static func convolve(_ a: [Double], _ b: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: a.count + b.count - 1)
        for i in a.indices { for j in b.indices { out[i + j] += a[i] * b[j] } }
        return out
    }
    /// ESF of a centred odd-length kernel: n pixels, the step between pixels edge − 1 and edge.
    static func esf(kernel w: [Double], n: Int = 1024, edge: Int = 512) -> EdgeSamples {
        let r = (w.count - 1) / 2
        var cumulative = [Double](repeating: 0, count: w.count + 1)
        for i in w.indices { cumulative[i + 1] = cumulative[i] + w[i] }
        let values = (0..<n).map { x -> Double in
            let upper = x - edge                       // Σ over j ≤ upper, j in −r…r
            if upper < -r { return 0 }
            if upper >= r { return 1 }
            return cumulative[upper + r + 1]
        }
        return EdgeSamples(esf: values, edgePosition: Double(edge), phase: 0, encodedMidpoint: nil)
    }
    /// ESF of a continuous CDF sampled at pixel centres, the edge displaced by `shift` px.
    static func esf(cdf: (Double) -> Double, n: Int = 1024, edge: Int = 512, shift: Double = 0, phase: Int = 0) -> EdgeSamples {
        EdgeSamples(esf: (0..<n).map { cdf(Double($0) + 0.5 - Double(edge) - shift) }, edgePosition: Double(edge), phase: phase,
                    encodedMidpoint: nil)
    }
    static func request(_ subject: CalibrationSubject = .swiftUIBlur, parameter: Double = 4, scale: Double = 1,
                        phases: Int = 1) -> CalibrationRequest {
        CalibrationRequest(subject: subject, path: subject.defaultPath, parameter: parameter, displayScale: scale,
                           colourMode: .nonLinear, phases: phases, opaque: false)
    }
    static let phone = DeviceStamp(deviceModel: "iPhone 15 Pro Max", gpuName: "Apple A17 Pro GPU", gpuFamily: "Apple9",
                                   osVersion: "iOS 27.0", osBuild: "24A5355p", isSimulator: false,
                                   date: Date(timeIntervalSince1970: 1_791_979_200), thermal: .nominal, lowPowerMode: false)
    /// Exact discrete excess kurtosis of a box of n taps.
    static func boxKurtosis(_ n: Int) -> Double { let m = Double(n * n); return -6 * (m + 1) / (5 * (m - 1)) }
}

@Suite struct CALIBRATION_SampledGaussians {
    typealias S = CALIBRATION_Synthetic
    let fitter = PSFFitter()

    @Test(arguments: [1.0, 4.0, 16.0])
    func momentSigmaRecoveredToFourDecimals(sigma: Double) {
        let fit = fitter.fit([S.esf(kernel: S.sampledGaussian(sigma))], request: S.request(parameter: sigma))
        #expect(abs(fit.sigmaPx - sigma) < 5e-5, "σ \(sigma): moment \(fit.sigmaPx)")
        #expect(String(format: "%.4f", fit.sigmaPx) == String(format: "%.4f", sigma))
        #expect(abs(fit.lsqSigmaPx - sigma) < 1e-3, "σ \(sigma): least squares \(fit.lsqSigmaPx) (CAL §3.3: agrees to 10⁻³)")
        #expect(abs(fit.excessKurtosis) < 0.01, "kurtosis \(fit.excessKurtosis)")
        #expect(fit.shapeName == PSFShape.gaussian)
        #expect(fit.models.first?.model == .gaussian, "\(fit.models)")
        #expect(abs(fit.sigmaPerParameterPixel - 1) < 1e-4)
        #expect(abs(fit.centreSpreadPx) < 1e-12 && fit.sigmaSpreadPercent == 0)
    }

    @Test(arguments: [4.0, 16.0])
    func visibleExtentIsTwoPointSixSixSigma(sigma: Double) {
        let fit = fitter.fit([S.esf(kernel: S.sampledGaussian(sigma))], request: S.request(parameter: sigma))
        #expect(abs(fit.extentPx / sigma - 2.66) < 0.1, "extent \(fit.extentPx) = \(fit.extentPx / sigma) σ")
        #expect(fit.supportPx > 3.5 * sigma && fit.supportPx < 4.5 * sigma, "support \(fit.supportPx)")
    }

    @Test func fourWholePixelPhasesAreShiftInvariant() {
        let w = S.sampledGaussian(6)
        let samples = (0..<4).map { k -> EdgeSamples in
            var s = S.esf(kernel: w, edge: 500 + k); s.phase = k; return s
        }
        let fit = fitter.fit(samples, request: S.request(parameter: 6, phases: 4))
        #expect(fit.centreSpreadPx < 1e-9 && fit.sigmaSpreadPercent < 1e-9)
    }

    @Test func eightBitQuantisationStaysWithinOnePercent() {
        var s = S.esf(kernel: S.sampledGaussian(6))
        s.esf = s.esf.map { ($0 * 255).rounded() / 255 }
        let fit = fitter.fit([s], request: S.request(parameter: 6))
        #expect(abs(fit.sigmaPx / 6 - 1) < 0.01, "σ \(fit.sigmaPx)")
        #expect(abs(fit.lsqSigmaPx / 6 - 1) < 0.01, "lsq \(fit.lsqSigmaPx)")
    }

    @Test func affineScaledInputIsRenormalised() {
        var s = S.esf(kernel: S.sampledGaussian(3))
        s.esf = s.esf.map { 0.2 + 0.5 * $0 }          // dark plateau 0.2, bright 0.7 (e.g. an un-normalised readback)
        let fit = fitter.fit([s], request: S.request(parameter: 3))
        #expect(abs(fit.sigmaPx - 3) < 5e-5)
    }

    @Test func flatInputIsNoEdgeNotACrash() {
        let fit = fitter.fit([EdgeSamples(esf: [Double](repeating: 0.4, count: 200), edgePosition: 100, phase: 0, encodedMidpoint: 0.5)],
                             request: S.request())
        #expect(fit.sigmaPx == 0 && fit.shapeName == PSFShape.noEdge && fit.models.isEmpty)
        #expect(PSFFitter().fit([], request: S.request()).shapeName == PSFShape.noEdge)
    }
}

@Suite struct CALIBRATION_ShapesAndModels {
    typealias S = CALIBRATION_Synthetic
    let fitter = PSFFitter()

    @Test func boxExcessKurtosisIsMinusOnePointTwo() {
        let fit = fitter.fit([S.esf(kernel: S.box(61))], request: S.request(parameter: 30))
        #expect(abs(fit.excessKurtosis - S.boxKurtosis(61)) < 1e-6, "discrete box of 61: \(fit.excessKurtosis)")
        #expect(abs(fit.excessKurtosis + 1.2) < 0.01)
        #expect(fit.shapeName == PSFShape.box)
        #expect(abs(fit.sigmaPx - ((61.0 * 61 - 1) / 12).squareRoot()) < 1e-6)
    }

    @Test func boxCubedExcessKurtosisIsMinusPointFour() {
        let b = S.box(31)
        let fit = fitter.fit([S.esf(kernel: S.convolve(S.convolve(b, b), b))], request: S.request(parameter: 15))
        #expect(abs(fit.excessKurtosis - S.boxKurtosis(31) / 3) < 1e-6, "Irwin–Hall: a third of the box's: \(fit.excessKurtosis)")
        #expect(abs(fit.excessKurtosis + 0.4) < 0.01)
        #expect(fit.shapeName == PSFShape.boxCubedLike)
        #expect(fit.models.first?.model == .boxCubed, "\(fit.models)")
    }

    @Test func tentDiscAndPeakedShapes() {
        let b = S.box(41)
        let tent = fitter.fit([S.esf(kernel: S.convolve(b, b))], request: S.request(parameter: 20))
        #expect(abs(tent.excessKurtosis + 0.6) < 0.01 && tent.shapeName == PSFShape.tentLike)
        let radius = 40.0
        let disc = fitter.fit([S.esf(kernel: S.normalised((-40...40).map { x in (1 - Double(x * x) / (radius * radius) + 1e-12).squareRoot() }))],
                              request: S.request(parameter: radius))
        #expect(abs(disc.excessKurtosis + 1.0) < 0.03 && disc.shapeName == PSFShape.disc, "disc \(disc.excessKurtosis)")
        #expect(abs(disc.sigmaPx - radius / 2) < 0.3, "disc σ = R/2: \(disc.sigmaPx)")
        let laplace = fitter.fit([S.esf(kernel: S.normalised((-200...200).map { exp(-abs(Double($0)) / 6) }))], request: S.request(parameter: 6))
        #expect(laplace.excessKurtosis > 2 && laplace.shapeName == PSFShape.peaked, "laplace \(laplace.excessKurtosis)")
    }

    @Test func shapeNamesByKurtosis() {
        #expect(PSFShape.name(kurtosis: 0) == "gaussian")
        #expect(PSFShape.name(kurtosis: -0.06) == "gaussian")
        #expect(PSFShape.name(kurtosis: -0.45) == "box³-like")      // SwiftUI's large-radius kernel (CAL §5.1 item 3)
        #expect(PSFShape.name(kurtosis: -0.5) == "box³-like")       // a tie goes to the earlier reference, as in MeasurePSF
        #expect(PSFShape.name(kurtosis: -0.58) == "tent-like")
        #expect(PSFShape.name(kurtosis: -1.0) == "disc")
        #expect(PSFShape.name(kurtosis: -1.21) == "box")
        #expect(PSFShape.name(kurtosis: 1.72) == "peaked")         // the 3-tap kernel at r = 0.5 (CAL §4.18)
        #expect(PSFShape.name(kurtosis: .nan) == PSFShape.noEdge)
    }

    @Test func truncatedGaussianWinsOnItsOwnKernel() {
        let sigma = 10.0, cut = Int((PSFFitter.truncationSigmas * sigma).rounded())
        let w = S.normalised((-cut...cut).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) })
        let fit = fitter.fit([S.esf(kernel: w)], request: S.request(parameter: sigma))
        #expect(fit.models.first?.model == .truncatedGaussian, "\(fit.models)")
        #expect(fit.models.first!.rmsResidualPercent < fit.models.last!.rmsResidualPercent)
        let truncated = fit.models.first { $0.model == .truncatedGaussian }!
        #expect(abs(truncated.sigmaPx - fit.sigmaPx) / fit.sigmaPx < 0.02, "model σ \(truncated.sigmaPx) vs moment \(fit.sigmaPx)")
    }

    @Test func modelCDFsHaveUnitMassAndTheirSigma() {
        for model in PSFModel.allCases {
            let w = 3.0, dx = 0.001
            var mean = 0.0, variance = 0.0, previous = PSFModelCDF.cdf(model, -40, width: w)
            for i in 1...80_000 {
                let x = -40 + Double(i) * dx, c = PSFModelCDF.cdf(model, x, width: w)
                let m = c - previous; previous = c
                mean += m * (x - dx / 2); variance += m * (x - dx / 2) * (x - dx / 2)
            }
            #expect(abs(previous - 1) < 1e-9, "\(model) mass")
            #expect(abs(variance - mean * mean - pow(PSFModelCDF.continuousSigma(model, width: w), 2)) < 1e-4, "\(model) σ²")
        }
    }

    @Test func fortyFiveDegreeKurtosisIsReported() {
        let b = S.box(21)
        var s = S.esf(kernel: S.convolve(S.convolve(b, b), b))
        s.esf45 = S.esf(kernel: S.convolve(S.convolve(S.convolve(b, b), b), S.convolve(S.convolve(b, b), b))).esf
        let fit = fitter.fit([s], request: S.request(parameter: 10))
        #expect(fit.excessKurtosis45 != nil)
        #expect(abs((fit.excessKurtosis45 ?? 0) - fit.excessKurtosis / 2) < 0.01, "six boxes: half the kurtosis of three")
    }
}

@Suite struct CALIBRATION_Resampling {
    typealias S = CALIBRATION_Synthetic

    @Test func subPixelPhaseShiftsShowAsCentreSpread() {
        let cdf = { (x: Double) in PSFModelCDF.cdf(.boxCubed, x, width: 7.2) }
        let samples = [0.0, 0.3, 0.6, 0.9].enumerated().map { S.esf(cdf: cdf, shift: $0.element, phase: $0.offset) }
        let fit = PSFFitter().fit(samples, request: S.request(parameter: 8, phases: 4))
        #expect(abs(fit.centreSpreadPx - 0.9) < 0.01, "spread \(fit.centreSpreadPx)")
        #expect(fit.centreSpreadPx > PSFFitter.shiftVariantSpreadPx)
        // σ of a continuous kernel sampled at pixel centres: √(w² + 1/12) (the pixel-integrated LSF).
        #expect(abs(fit.sigmaPx - (7.2 * 7.2 + 1.0 / 12).squareRoot()) < 1e-3, "σ \(fit.sigmaPx)")
        #expect(abs(fit.excessKurtosis + 0.4) < 0.02)
    }
}

/// A synthetic SwiftUI-like sweep at display scale 3: a sampled Gaussian σ = r·s up to 5 device px, above it a box³-like
/// kernel of σ 0.90·r·s on a resampled grid (the edge centre moves with the phase), as CAL §4.18 measured on the Mac.
enum CALIBRATION_SweepFixture {
    typealias S = CALIBRATION_Synthetic
    static func result(radius: Double, scale: Double = 3, phases: Int = 4, minute: Double = 0) -> CalibrationResult {
        let px = radius * scale
        let n = Int(2 * (12 * px + 40))
        let edge = n / 2
        let samples: [EdgeSamples]
        if px <= 5 {
            samples = (0..<phases).map { k in var s = S.esf(kernel: S.sampledGaussian(px), n: n, edge: edge + k); s.phase = k; return s }
        } else {
            let w = (pow(0.90 * px, 2) - 1.0 / 12).squareRoot()
            samples = (0..<phases).map { k in
                S.esf(cdf: { PSFModelCDF.cdf(.boxCubed, $0, width: w) }, n: n, edge: edge, shift: 0.3 * Double(k), phase: k)
            }
        }
        let request = CalibrationRequest(subject: .swiftUIBlur, path: .imageRendererCGImage, parameter: radius, displayScale: scale,
                                         colourMode: .nonLinear, phases: phases, opaque: false)
        var device = S.phone
        device.date = device.date.addingTimeInterval(minute * 60 + radius)
        return CalibrationResult(request: request, fit: PSFFitter().fit(samples, request: request), device: device, durationMilliseconds: 12)
    }
}

@Suite struct CALIBRATION_Laws {
    typealias F = CALIBRATION_SweepFixture
    let fitter = PSFFitter()

    @Test func sweepFindsTheRegimeSwitch() throws {
        let sweep = CalibrationPlan.swiftUISweepRadii.filter { $0 >= 0.5 }.map { F.result(radius: $0) }
        let law = try #require(fitter.law(sweep))
        let s = try #require(law.switchParameter)
        #expect(s > 1.5 && s <= 2.0, "switch \(s) pt: between 4.5 and 6 device px at scale 3")
        #expect(abs((law.smallRatio ?? 0) - 1.00) < 0.01, "small \(String(describing: law.smallRatio))")
        #expect(abs(law.largeRatio - 0.90) < 0.01, "large \(law.largeRatio)")
        #expect(law.points.count == sweep.count && law.subject == .swiftUIBlur)
        #expect(abs(law.sigmaPx(parameter: 1, displayScale: 3) - 3 * (law.smallRatio ?? 0)) < 1e-12)
        #expect(abs(law.sigmaPx(parameter: 8, displayScale: 3) - 24 * law.largeRatio) < 1e-12)
    }

    @Test func basicSetAloneFindsTheSwitch() throws {
        let law = try #require(fitter.law(CalibrationPlan.basicSetRadii.map { F.result(radius: $0) }))
        #expect(law.switchParameter == 1.5, "between 1 pt (3 px) and 2 pt (6 px): \(String(describing: law.switchParameter))")
    }

    @Test func withoutPhasesTheRatiosFindTheSwitch() throws {
        let sweep = CalibrationPlan.swiftUISweepRadii.filter { $0 >= 0.5 }.map { F.result(radius: $0, phases: 1) }
        let law = try #require(fitter.law(sweep))
        let s = try #require(law.switchParameter)
        #expect(s > 1.5 && s <= 2.0, "switch \(s)")
    }

    @Test func noSwitchWhenTheRatioIsFlat() throws {
        let results = [1.0, 2, 4, 8, 16, 32].map { r -> CalibrationResult in
            let request = CalibrationRequest(subject: .ciGaussianBlur, path: .coreImageContext, parameter: r, displayScale: 1, phases: 4)
            let fit = PSFFitter().fit([CALIBRATION_Synthetic.esf(kernel: CALIBRATION_Synthetic.sampledGaussian(r), n: Int(30 * r + 64), edge: Int(15 * r + 32))],
                                      request: request)
            return CalibrationResult(request: request, fit: fit, device: CALIBRATION_Synthetic.phone, durationMilliseconds: 3)
        }
        let law = try #require(fitter.law(results))
        #expect(law.switchParameter == nil && law.smallRatio == nil)
        #expect(abs(law.largeRatio - 1) < 1e-3)
    }

    @Test func fewerThanThreePointsGiveNoLaw() {
        #expect(fitter.law([]) == nil)
        #expect(fitter.law([F.result(radius: 1), F.result(radius: 4)]) == nil)
        #expect(fitter.law([F.result(radius: 4), F.result(radius: 4, minute: 1), F.result(radius: 4, minute: 2)]) == nil,
                "repeats of one radius are one point")
    }

    @Test func lawUsesTheNewestGroupOnly() throws {
        var sweep = CalibrationPlan.basicSetRadii.map { F.result(radius: $0) }
        // An older linear-space sweep must not mix into the newest (non-linear) group.
        sweep += [0.5, 1, 2, 3].map { r -> CalibrationResult in
            var x = F.result(radius: r, minute: -60); x.request.colourMode = .extendedLinear; return x
        }
        let law = try #require(fitter.law(sweep))
        #expect(law.points.count == CalibrationPlan.basicSetRadii.count)
    }

    @Test func splitHelpers() {
        #expect(PSFLawSplit.fromSpread([0, 0, 0, 0.4, 1.0, 0.12, 1.1]) == 3)
        #expect(PSFLawSplit.fromSpread([0.3, 0.4]) == nil, "nothing below the switch")
        #expect(PSFLawSplit.fromSpread([0, 0.2, 0, 0, 0, 0]) == nil, "one stray point is not a regime")
        #expect(PSFLawSplit.fromRatios([1.0, 0.99, 1.0, 0.9, 0.905, 0.9]) == 3)
        #expect(PSFLawSplit.fromRatios([1.0, 0.99, 1.0, 1.0, 0.995, 1.0]) == nil)
    }
}
