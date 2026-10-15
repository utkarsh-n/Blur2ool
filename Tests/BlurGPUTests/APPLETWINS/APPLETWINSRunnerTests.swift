import Foundation
import Metal
import Testing
import BlurCore
@testable import BlurGPU

// OWNER: APPLE-TWINS. The AppleTwinRunning contract the app relies on (ENGINE's Compare › Apple, CALIBRATION's Calibrate):
// which subjects run, running on the window texture exactly as RenderCoordinator does (private rgba16Float in, compute-
// writable out), honest refusals, the EdgeSamples shape, and the facts table's sources and badges.

@Suite struct APPLETWINS_Runner {
    typealias S = APPLETWINS_Support

    static let twins: [CalibrationSubject] = [.ciGaussianBlur, .ciBoxBlur, .ciDiscBlur, .ciBokehBlur, .ciMotionBlur, .ciZoomBlur,
                                              .ciMaskedVariableBlur, .mpsGaussianBlur, .mpsBox, .mpsTent, .vImageBox, .vImageTent]

    @MainActor @Test func supportsExactlyTheInProcessTwins() {
        let runner = AppleTwinRunner()
        for subject in CalibrationSubject.allCases {
            #expect(runner.supports(subject) == APPLETWINS_Runner.twins.contains(subject), "\(subject.title)")
            #expect(runner.supports(subject) != subject.isMainActorRendered, "\(subject.title): ImageRenderer subjects belong to Calibrate")
        }
        #expect(Set(AppleTwinRunner.subjects) == Set(APPLETWINS_Runner.twins))
    }

    /// Every fact carries a source; its mapping badge is one the brief allows for an Apple API (MEASURED, COMPUTED, REFERENCE),
    /// and the words it would print are honest BadgedValues.
    @Test func factsAreSourcedAndBadged() {
        #expect(AppleTwinCatalog.all.count == APPLETWINS_Runner.twins.count)
        #expect(Set(AppleTwinCatalog.all.map(\.subject)).count == AppleTwinCatalog.all.count, "one entry per subject")
        let mac = S.macStamp(gpuName: "Apple M1 Max", gpuFamily: "Apple7")
        for f in AppleTwinCatalog.all {
            #expect(!f.source.citation.isEmpty && !f.call.isEmpty && !f.mapping.isEmpty && !f.edgePolicy.isEmpty, "\(f.subject.title)")
            #expect([.measured, .computed, .reference].contains(f.mappingProvenance), "\(f.subject.title)")
            let word = BadgedValue.words(f.mapping, f.mappingProvenance, source: f.source,
                                         device: f.mappingProvenance == .measured ? mac : nil)
            #expect(word.honestyViolations.isEmpty, "\(f.subject.title): \(word.honestyViolations)")
        }
        // The laws the facts state, as numbers (COMPUTED from the mappings).
        #expect(AppleTwinCatalog.coreImageBoxWidth(radius: 10) == 9)       // CAL: default 10 → W 9
        #expect(AppleTwinCatalog.coreImageBoxWidth(radius: 2) == 1)        // r ≤ 2: no blur
        #expect(AppleTwinCatalog.kernelWidth(halfWidth: 4) == 9)
        #expect(abs((AppleTwinCatalog.expectedSigma(.mpsTent, parameter: 3) ?? 0) - (15.0 / 6).squareRoot()) < 1e-12)
        #expect(AppleTwinCatalog.expectedSigma(.ciZoomBlur, parameter: 16) == nil)
    }

    /// The window path RenderCoordinator uses: a private rgba16Float window in, a compute-writable output out. Every twin
    /// runs, changes the image, stays finite, and reports the call it made with a measured time.
    @MainActor @Test func runsEveryTwinOnTheWindow() async throws {
        guard let context = try S.context() else { return }
        let runner = AppleTwinRunner()
        let n = 96, size = ImageSize.square(n)
        let texels = S.pattern(width: n, height: n, seed: 3)
        let staging = try await runner.makeTexture(texels, size: size, format: .rgba16Float, context: context)
        let window = try context.texture(TextureSpec(width: n, height: n, roles: [.read, .renderTarget]))
        let copy = try runner.makeCommandBuffer(context, label: "window")
        try runner.encodeCopy(from: staging, to: window, commandBuffer: copy)
        _ = try await runner.commitChecked(copy, context: context)
        let output = try context.texture(TextureSpec(width: n, height: n, roles: [.read, .renderTarget, .computeWrite]))
        for subject in APPLETWINS_Runner.twins {
            let parameter = subject == .ciZoomBlur ? 12.0 : 6.0
            try await runner.run(subject, parameter: parameter, input: window, output: output, context: context)
            let report = try #require(runner.lastReport)
            #expect(report.subject == subject && report.parameter == parameter && !report.call.isEmpty)
            #expect((report.gpuMilliseconds ?? report.cpuMilliseconds ?? -1) >= 0, "\(subject.title): no measured time")
            let out = try await context.readTexels(output, region: PixelRegion(origin: .zero, size: size))
            #expect(out.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.w.isFinite }, "\(subject.title): non-finite output")
            let centre = PixelRegion.centred(on: PixelPoint(x: n / 2, y: n / 2 + 20), side: 16, inside: size)
            var change = 0.0
            for y in centre.origin.y..<(centre.origin.y + centre.size.height) {
                for x in centre.origin.x..<(centre.origin.x + centre.size.width) {
                    change = Swift.max(change, Double(S.maxAbs(out[y * n + x] - SIMD4<Float>(SIMD4<Float16>(texels[y * n + x])))))
                }
            }
            #expect(change > 0.05, "\(subject.title): the twin did not blur the window (max change \(change))")
        }
    }

    /// An output that compute cannot write (render target only) still works: the runner renders into scratch and blits.
    @MainActor @Test func renderTargetOnlyOutput() async throws {
        guard let context = try S.context() else { return }
        let runner = AppleTwinRunner()
        let size = ImageSize.square(32)
        let input = try await runner.makeTexture(S.pattern(width: 32, height: 32), size: size, format: .rgba16Float, context: context)
        let output = try context.texture(TextureSpec(width: 32, height: 32, roles: [.read, .renderTarget]))
        for subject in [CalibrationSubject.ciGaussianBlur, .mpsGaussianBlur, .vImageBox] {
            try await runner.run(subject, parameter: 2, input: input, output: output, context: context)
            let a = try await context.readTexels(output, region: PixelRegion(origin: PixelPoint(x: 16, y: 16), size: .square(1)))
            #expect(a[0].w > 0.99 && a[0].x > 0, "\(subject.title) through scratch: \(a[0])")
        }
    }

    @MainActor @Test func refusesHonestly() async throws {
        guard let context = try S.context() else { return }
        let runner = AppleTwinRunner()
        let a = try runner.makeOutput(size: .square(16), format: .rgba16Float, context: context)
        let b = try runner.makeOutput(size: .square(16), format: .rgba16Float, context: context)
        let small = try runner.makeOutput(size: .square(8), format: .rgba16Float, context: context)
        await #expect(throws: GPUError.self) { try await runner.run(.swiftUIBlur, parameter: 4, input: a, output: b, context: context) }
        await #expect(throws: GPUError.self) { try await runner.run(.ciGaussianBlur, parameter: 4, input: a, output: small, context: context) }
        await #expect(throws: GPUError.self) { try await runner.run(.ciGaussianBlur, parameter: -1, input: a, output: b, context: context) }
        await #expect(throws: GPUError.self) { try await runner.run(.ciGaussianBlur, parameter: 4, input: a, output: a, context: context) }
        await #expect(throws: GPUError.self) {
            _ = try await runner.edgeSamples(S.request(.caLayerShadow, 4), context: context)
        }
    }

    /// EdgeSamples for Calibrate: one per phase, normalised 0 → 1 around `edgePosition`, the 45° twin at phase 0, and the
    /// blend-space midpoint MEASURED: Core Image's default context blends linear light (encoded midpoint ≈ 0.735, CAL §5.2).
    @MainActor @Test func edgeSamplesContract() async throws {
        guard let context = try S.context() else { return }
        let runner = AppleTwinRunner(), stamp = S.stamp(context)
        let samples = try await runner.edgeSamples(S.request(.ciGaussianBlur, 6, phases: 4, colourMode: .nonLinear), context: context)
        #expect(samples.count == 4)
        #expect(samples.map(\.phase) == [0, 1, 2, 3])
        for s in samples {
            #expect(s.esf.count == 2 * Int(s.edgePosition))
            #expect(abs((s.esf.first ?? 1)) < 1e-3 && abs((s.esf.last ?? 0) - 1) < 1e-3)
            #expect(abs((s.encodedMidpoint ?? 0) - 0.7354) < 0.01, "Core Image midpoint \(s.encodedMidpoint ?? -1)")
        }
        #expect(samples[0].esf45 != nil && samples[1].esf45 == nil)
        let fits = samples.map { AppleTwinAnalysis.edgeFit(esf: $0.esf, edgePosition: $0.edgePosition) }
        let spread = (fits.map(\.centreOffset).max() ?? 0) - (fits.map(\.centreOffset).min() ?? 0)
        #expect(spread < 0.15, "CIGaussianBlur r 6: centre spread over 4 phases \(spread) px")
        S.record("CIGaussianBlur r 6 · 4 phases", [("centre spread", spread, S.px3),
                                                   ("encoded midpoint", samples[0].encodedMidpoint ?? .nan, S.three)],
                 stamp: stamp, note: "blend space: linear light")
        // MPS blends the stored numbers: with sRGB-encoded numbers the midpoint is the gamma-space 0.5.
        let mps = try await runner.edgeSamples(S.request(.mpsGaussianBlur, 6, colourMode: .nonLinear), context: context)
        #expect(abs((mps.first?.encodedMidpoint ?? 0) - 0.5) < 0.01)
        // Core Image's default border is transparent.
        let border = try await runner.edgePolicy(.ciGaussianBlur, parameter: 8, context: context)
        #expect(border.verdict == .transparent, "\(border)")
        let clamped = try await runner.edgePolicy(.ciGaussianBlur, parameter: 8, options: AppleTwinOptions(coreImageClampToExtent: true),
                                                  context: context)
        #expect(clamped.verdict == .clamp, "\(clamped)")
        S.record("CIGaussianBlur r 8 border", [("white border", border.whiteBorderValue, S.three), ("alpha", border.whiteBorderAlpha, S.three),
                                               ("clamped: black column border", clamped.blackColumnBorderValue, S.three)],
                 stamp: stamp, note: "default \(border.verdict.rawValue); clampedToExtent \(clamped.verdict.rawValue)")
    }
}

/// The pure estimators against exact kernels (no GPU).
@Suite struct APPLETWINS_Analysis {
    /// Step responses of exact sampled kernels: the two-pass moment σ, kurtosis and support recover the kernel.
    @Test func recoversExactKernels() {
        let reach = 120
        /// esf[k] = Σ_j w[j]·[k + j ≥ reach] for taps j = −R…R (pixel k is white when k ≥ reach).
        func stepResponse(_ weights: [Double]) -> [Double] {
            let r = weights.count / 2, total = weights.reduce(0, +)
            return (0..<(2 * reach)).map { k in (-r...r).reduce(0.0) { $0 + (k + $1 >= reach ? weights[$1 + r] / total : 0) } }
        }
        for sigma in [1.0, 4, 16] {
            let r = Int(6 * sigma) + 1
            let fit = AppleTwinAnalysis.edgeFit(esf: stepResponse((-r...r).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }),
                                                edgePosition: Double(reach))
            #expect(abs(fit.sigma - sigma) < 1e-3 * sigma, "σ \(sigma): \(fit.sigma)")
            #expect(abs(fit.excessKurtosis) < 0.02, "σ \(sigma): kurtosis \(fit.excessKurtosis)")
            #expect(abs(fit.centreOffset) < 1e-9 && abs(fit.massBeyondEdge - 0.5) < 1e-9)
        }
        for width in [3, 9, 17] {
            let fit = AppleTwinAnalysis.edgeFit(esf: stepResponse([Double](repeating: 1, count: width)), edgePosition: Double(reach))
            let w2 = Double(width * width)
            #expect(fit.supportSamples == width)
            #expect(abs(fit.sigma - AppleTwinAnalysis.boxSigma(width: width)) < 1e-9)
            #expect(abs(fit.excessKurtosis - (-6 * (w2 + 1) / (5 * (w2 - 1)))) < 1e-9, "discrete box kurtosis, W \(width)")
            #expect(abs(fit.centreOffset) < 1e-9 && abs(fit.massBeyondEdge - 0.5) < 1e-9)
        }
    }

    /// Impulse moments of an exact horizontal uniform segment: σ_major·√12 is its length, angle 0, kurtosis ≈ −1.2.
    @Test func impulseMomentsOfASegment() {
        let w = 64, h = 32, length = 21
        var texels = [SIMD4<Float>](repeating: SIMD4(0, 0, 0, 1), count: w * h)
        for k in 0..<length { texels[16 * w + 20 + k] = SIMD4(1 / Float(length), 1 / Float(length), 1 / Float(length), 1) }
        let m = AppleTwinAnalysis.impulseMoments(texels, width: w, height: h, impulse: PixelPoint(x: 20, y: 16))
        #expect(abs(m.sum - 1) < 1e-5)
        #expect(abs(m.uniformStreakLength - (Double(length * length - 1)).squareRoot()) < 1e-6)
        #expect(abs(m.centroidOffset.x - 10) < 1e-6 && abs(m.centroidOffset.y) < 1e-9)
        #expect(abs(m.majorAxisDegrees) < 1e-6 && m.sigmaMinor < 1e-9)
        #expect(m.majorAxisExcessKurtosis < -1.1)
    }
}
