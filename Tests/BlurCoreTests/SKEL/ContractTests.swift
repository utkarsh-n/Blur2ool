import Foundation
import Testing
@testable import BlurCore

// OWNER: SKEL. Pins the frozen contract and the SPEC §5.3 A fixtures (Gaussian) so every later change is caught.

@Suite struct SKEL_KernelFixtures {
    @Test func gaussianSigma4Weights() {
        let k = KernelMath.gaussianSampled(sigma: 4)
        #expect(k.origin == 12 && k.tapCount == 25)
        let expected = [0.09991, 0.09683, 0.08817, 0.07541, 0.06060, 0.04574, 0.03244, 0.02161, 0.01352, 0.00795, 0.00439, 0.00228, 0.00111]
        for (n, w) in expected.enumerated() { #expect(abs(k.weights[12 + n] - w) < 5e-6, "w[\(n)]") }
        #expect(abs(k.sigma - 3.963) < 5e-4)                                              // discrete σ 3.963
        let h = KernelMath.response(k, frequencies: ResponseQuery(samples: 2001).frequencies)
        #expect(abs((h.min() ?? 0) - (-0.0010)) < 5e-5)                                   // discrete min H −0.0010
        #expect(abs((h.last ?? 0) - 7.1e-4) < 5e-6)                                       // H(0.5) = 7.1·10⁻⁴
    }

    @Test func gaussianSigma4LinearSampledTable() {
        let t = KernelMath.linearSampledTable(KernelMath.gaussianSampled(sigma: 4))
        let offsets = [0, 1.4766, 3.4455, 5.4149, 7.3849, 9.3558, 11.3277]
        let weights = [0.09991, 0.18500, 0.13601, 0.07818, 0.03513, 0.01234, 0.00339]
        #expect(t.offsets.count == 7 && t.fetchesPerPass == 13)
        for i in 0..<7 {
            #expect(abs(t.offsets[i] - offsets[i]) < 5e-5, "offset \(i)")
            #expect(abs(t.weights[i] - weights[i]) < 5e-6, "weight \(i)")
        }
    }

    @Test func benchDefaultSigma12() {
        let k = KernelMath.gaussianSampled(sigma: 12)
        #expect(k.origin == 36 && k.tapCount == 73)
        #expect(abs(k.weights[36] - 0.03332) < 5e-6)
        #expect(abs(k.weights[48] - 0.02021) < 5e-6 && abs(k.weights[60] - 0.00451) < 5e-6 && abs(k.weights[72] - 0.00037) < 5e-6)
        #expect(abs(k.sigma - 11.86) < 5e-3)
        let t = KernelMath.linearSampledTable(k)
        #expect(t.fetchesPerPass == 37)
        #expect(abs(t.offsets[1] - 1.4974) < 5e-5 && abs(t.offsets[2] - 3.4939) < 5e-5 && abs(t.offsets[3] - 5.4905) < 5e-5)
        #expect(abs(t.weights[1] - 0.06607) < 5e-6 && abs(t.weights[2] - 0.06382) < 5e-6 && abs(t.weights[3] - 0.05996) < 5e-6)
        #expect(abs(KernelMath.gaussianMassBeyond(radius: 36, sigma: 12) - 0.0027) < 1e-5)    // mass dropped 0.27 %
        #expect(abs(KernelMath.gaussianMassBeyond(radius: 12, sigma: 4) - 0.0027) < 1e-5)
    }

    @Test func nyquistAtSigma1() {   // SPEC §17 item 8 / P8
        let f = [0.5]
        #expect(abs(KernelMath.response(KernelMath.gaussianSampled(sigma: 1), frequencies: f)[0] - 0.0141) < 2e-4)
        #expect(abs(KernelMath.response(KernelMath.gaussianIntegrated(sigma: 1, truncation: 4), frequencies: f)[0] - 0.0092) < 1e-4)
        #expect(abs(KernelMath.response(KernelMath.gaussianIntegrated(sigma: 1), frequencies: f)[0] - 0.0087) < 1e-4)  // k = 3
        #expect(abs(KernelMath.response(KernelMath.gaussianLindeberg(sigma: 1), frequencies: f)[0] - 0.1353) < 2e-3)
        #expect(abs(KernelMath.response(KernelMath.binomial(order: 4), frequencies: f)[0]) < 1e-12)  // binomial: exactly 0
    }

    @Test func smallSigmaDiscretisations() {   // P9: sampled σ 0.3 → 0.088; Lindeberg 0.300
        #expect(abs(KernelMath.gaussianSampled(sigma: 0.3).sigma - 0.088) < 5e-4)
        #expect(abs(KernelMath.gaussianLindeberg(sigma: 0.3).sigma - 0.300) < 5e-4)
    }

    @Test func boxTentMoments() {
        #expect(abs(KernelMath.box(radius: 20).sigma - 11.83) < 5e-3)                      // w 41, σ 11.83
        #expect(abs(KernelMath.tent(radius: 28).sigma - 11.83) < 5e-3)                     // σ² = r(r+2)/6
        #expect(abs(Kernel1D(weights: [1, 1, 1, 1, 1].map { $0 / 5 }, origin: 2).excessKurtosis - (-1.3)) < 1e-12)
    }
}

@Suite struct SKEL_GaussianDescentA {
    /// Step edges at N = 894 (only 9 rows: the step is vertical, so V changes nothing), σ 4, probe (446, 300).
    func run(_ settings: SilentSettings) throws -> ImageBuffer {
        let canvas = StepEdgesGenerator().canvas(windowSize: 894, margin: 0, options: .standard, text: nil)
        let rows = canvas.image.crop(PixelRegion(origin: PixelPoint(x: 0, y: 296), size: ImageSize(width: 894, height: 9)))
        let request = OperatorRequest(parameters: ParameterValues(["sigma": .double(4), "truncation": .choice("3"), "discretisation": .choice("sampled")]),
                                      variant: GaussianOperator.separable, settings: settings, size: rows.size)
        return try BlurReference.run(GaussianOperator(), input: rows, request, options: .parity).output
    }

    @Test func probeValueAndEncodings() throws {
        let out = try run(.standard)
        let p = Double(out[446, 4].x)
        #expect(abs(p - 0.4500) < 5e-4)                                                    // OUT 0.4500 linear
        #expect(SRGB.code8(linear: p) == 179)                                              // 179/255
        let neighbours = [0.353, 0.450, 0.550, 0.647, 0.735, 0.810]
        for (i, v) in neighbours.enumerated() { #expect(abs(Double(out[445 + i, 4].x) - v) < 1.5e-3, "x \(445 + i)") }
        let encoded = try run(SilentSettings(colourSpace: .srgbEncoded))
        #expect(SRGB.code8(linear: Double(encoded[446, 4].x)) == 115)                      // branch: 115/255
    }
}

@Suite struct SKEL_ContractRules {
    @Test func edgeMapping() {
        #expect(EdgeMode.mirror.map(-1, count: 5) == 0 && EdgeMode.mirror.map(-2, count: 5) == 1 && EdgeMode.mirror.map(5, count: 5) == 4)
        #expect(EdgeMode.wrap.map(-1, count: 5) == 4 && EdgeMode.clamp.map(9, count: 5) == 4 && EdgeMode.zero.map(-1, count: 5) == nil)
        #expect(EdgeMode.allCases.map(\.shaderIndex) == [0, 1, 2, 3, 4])
    }

    @Test func formatting() {
        #expect(NumberStyle.decimals(3).text(-0.217) == "\u{2212}0.217")
        #expect(NumberStyle.integer(noun: CountNoun("sample", "samples")).spoken(32) == "32 samples")
        #expect(NumberStyle.integer().text(2401) == "2,401")
        #expect(NumberStyle.significant(2).text(7.1e-4) == "7.1·10⁻⁴")
        #expect(NumberStyle.significant(2).spoken(7.1e-4) == "7.1 times 10 to the minus 4")
        #expect(NumberStyle.decimals(1).text(-0.04) == "0.0")
        #expect(NumberStyle.decimals(1).text(.infinity) == "∞")
    }

    @Test func honestyInvariants() {
        #expect(!BadgedValue(value: 1, text: "1", provenance: .measured, spoken: "x").honestyViolations.isEmpty)
        #expect(!BadgedValue(value: 1, text: "1", provenance: nil, spoken: "x").honestyViolations.isEmpty)
        #expect(BadgedValue.input(12, .decimals(1)).honestyViolations.isEmpty)
        #expect(BadgedValue.unverified("Photoshop radius").honestyViolations.isEmpty)
        #expect(BadgedValue.notYetMeasured().honestyViolations.isEmpty)
        #expect(BadgedValue.number(0.61, .decimals(2, unit: "ms"), .computed).honestyViolations.isEmpty)
        #expect(!BadgedValue.words("TODO", .computed).honestyViolations.isEmpty)
    }

    @Test func stepping() {
        let spec = ContinuousSpec(range: 0.3...64, fineStep: 0.1, decimals: 1, semanticStops: [0.5, 1, 2, 4, 8, 16, 32, 64].map { SemanticStop($0) })
        #expect(spec.stepped(from: 12.0, by: 1) == 12.1)
        #expect(spec.stepped(from: 64.0, by: 1) == 64.0)
        #expect(spec.semanticStepped(from: 12.0, by: 1) == 16 && spec.semanticStepped(from: 12.0, by: -1) == 8)
        let k = ContinuousSpec(range: 1e-4...1e-1, fineStep: 1e-4, decimals: 4, scale: .oneTwoFive)
        #expect(abs(k.stepped(from: 0.01, by: 1) - 0.02) < 1e-12 && abs(k.stepped(from: 0.02, by: 1) - 0.05) < 1e-12)
        let f = ContinuousSpec(range: 1.4...22, fineStep: 0.1, decimals: 1, scale: .thirdStops)
        #expect(f.nominalLabel(for: f.stepped(from: 2.0, by: 3)) == "f/2.8")
        #expect(IntegerSpec(range: 5...31, step: 2, parity: .odd).stepped(from: 15, by: 1) == 17)
    }

    @Test func registryAndStrip() {
        #expect(BlurRegistry.op("gaussian-blur") != nil)
        #expect(BlurRegistry.stripOrder.first == "gaussian-blur")
        #expect(SpecimenRegistry.generator("step-edges") != nil)
    }

    @Test func runRoundTripsThroughJSON() throws {
        let config = RenderConfiguration(blur: "gaussian-blur", variant: "gaussian-linear-sampling",
                                         parameters: ParameterValues(["sigma": .double(12)]), settings: .standard, specimen: "night-city",
                                         specimenOptions: .standard, pan: .zero, probe: PixelPoint(x: 447, y: 455), windowSize: 894)
        let data = try JSONEncoder().encode(config)
        #expect(String(decoding: data, as: UTF8.self).contains("\"sigma\""))
        #expect(try JSONDecoder().decode(RenderConfiguration.self, from: data) == config)
    }
}

@Suite struct SKEL_InteractionLogic {
    @Test func tapPlacesProbe() {
        var a = SpecimenGestureArbiter(bounds: SIMD2(298, 298))
        _ = a.handle(TouchEvent(phase: .began, touches: [TouchPoint(id: 1, location: SIMD2(100, 100))], time: 0), handles: [])
        #expect(a.handle(TouchEvent(phase: .ended, touches: [TouchPoint(id: 1, location: SIMD2(101, 100))], time: 0.1), handles: []) == [.placeProbe(SIMD2(101, 100))])
    }
    @Test func handleBeatsPan() {
        var a = SpecimenGestureArbiter(bounds: SIMD2(298, 298))
        let h = [HandleTarget(id: "centre", centre: SIMD2(149, 149))]
        #expect(a.handle(TouchEvent(phase: .began, touches: [TouchPoint(id: 1, location: SIMD2(160, 150))], time: 0), handles: h) == [.handleBegan("centre")])
        #expect(a.handle(TouchEvent(phase: .moved, touches: [TouchPoint(id: 1, location: SIMD2(200, 150))], time: 0.1), handles: h) == [.handleMoved("centre", SIMD2(200, 150))])
    }
    @Test func dragPansAndLongPressOpensLoupe() {
        var a = SpecimenGestureArbiter(bounds: SIMD2(298, 298))
        _ = a.handle(TouchEvent(phase: .began, touches: [TouchPoint(id: 1, location: SIMD2(50, 50))], time: 0), handles: [])
        #expect(a.handle(TouchEvent(phase: .moved, touches: [TouchPoint(id: 1, location: SIMD2(70, 50))], time: 0.1), handles: []) == [.panBegan, .panMoved(delta: SIMD2(20, 0))])
        var b = SpecimenGestureArbiter(bounds: SIMD2(298, 298))
        _ = b.handle(TouchEvent(phase: .began, touches: [TouchPoint(id: 1, location: SIMD2(50, 50))], time: 0), handles: [])
        #expect(b.tick(time: 0.36) == [.loupeBegan(SIMD2(50, 50))])
    }
    @Test func schedulerTimesOnlyAfterSettle() {
        var s = RenderScheduler()
        #expect(s.requestChanged(at: 0, preview: .half, interacting: true) == [.render(quality: .half, generation: 1)])
        s.interactionEnded(at: 0.05)
        #expect(s.tick(at: 0.2).isEmpty)
        #expect(s.tick(at: 0.36) == [.render(quality: .full, generation: 1), .startTiming(generation: 1)])
        #expect(s.tick(at: 1.0).isEmpty)
        #expect(s.acknowledge(1) && !s.acknowledge(0))
        #expect(s.touchBegan() == [.cancelMeasurements])                       // E-7: timing is cancellable
        #expect(s.requestChanged(at: 2, preview: .quarter, interacting: true) == [.render(quality: .quarter, generation: 2)])
    }
    @Test func calibrationWaitsForIdle() {
        var c = CalibrationIdleScheduler(launchTime: 0)
        #expect(!c.mayRun(at: 9, thermal: .nominal))
        c.noteTouch(at: 9)
        #expect(!c.mayRun(at: 11, thermal: .nominal) && c.mayRun(at: 12.1, thermal: .fair) && !c.mayRun(at: 12.1, thermal: .serious))
    }
    @Test func crownFirstTouchNeverSteps() {
        var t = CrownDetentTracker(detentDegrees: 8)
        t.begin(angleDegrees: 10)
        #expect(t.update(angleDegrees: 17) == 0 && t.update(angleDegrees: 19) == 1)
    }
}
