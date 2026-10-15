import Foundation
import Testing
@testable import BlurCore

// OWNER: SKEL. Pins the contract changes of design review round 1 (ARCHITECTURE "Review log").

@Suite struct SKEL_ReviewFixes {
    /// E-5: the van Herk running max equals a brute-force window max.
    @Test func localScaleMatchesBruteForce() {
        var image = ImageBuffer(width: 23, height: 17, fill: SIMD4(0.02, 0.03, 0.04, 1))
        image[3, 4] = SIMD4(100, 100, 100, 1); image[20, 15] = SIMD4(6, 2, 1, 1); image[11, 0] = SIMD4(-9, 0, 0, 1)
        for r in [0, 1, 3, 8] {
            let fast = ParityEvaluation.localScale(image, radius: r), mags = image.magnitudes
            for y in 0..<17 {
                for x in 0..<23 {
                    var m: Float = -.infinity
                    for j in max(0, y - r)...min(16, y + r) { for i in max(0, x - r)...min(22, x + r) { m = max(m, mags[j * 23 + i]) } }
                    #expect(fast[y * 23 + x] == m, "r \(r) at (\(x), \(y))")
                }
            }
        }
    }

    /// E-5 (the review's case): on an HDR image (one light of 6,400 = 100 at +6 EV) a kernel that drops half its taps
    /// passes the `bilinear` class with the old global scale and fails with the local scale, away from the light.
    @Test func localScaleCatchesDroppedTapsOnHDR() {
        var input = ImageBuffer(width: 96, height: 96, fill: SIMD4(0.02, 0.02, 0.02, 1))
        for y in 0..<96 { for x in 48..<96 { input[x, y] = SIMD4(0.8, 0.8, 0.8, 1) } }      // a lit sign edge at x = 48
        input[6, 6] = SIMD4(6400, 6400, 6400, 1)                                             // a light far from the edge
        func blur(_ k: Kernel1D) -> ImageBuffer {
            GaussianOperator.integerPass(GaussianOperator.integerPass(input, kernel: k, horizontal: true, edge: .clamp),
                                         kernel: k, horizontal: false, edge: .clamp).roundedToHalf()
        }
        let full = KernelMath.gaussianSampled(sigma: 4)
        var half = full                                                     // every second tap dropped, renormalised
        for i in half.weights.indices where (i - half.origin) % 2 != 0 { half.weights[i] = 0 }
        let s = half.sum; half.weights = half.weights.map { $0 / s }
        // Compare the buildings only (≥ 30 px from the light); the global scale is still the window maximum.
        let region = PixelRegion(origin: PixelPoint(x: 30, y: 30), size: .square(66))
        let reference = blur(full).crop(region), mutated = blur(half).crop(region)
        let scales = ParityEvaluation.localScale(input, radius: full.origin + 1)
        let regionScales = (30..<96).flatMap { y in (30..<96).map { x in scales[y * 96 + x] } }
        let global = ParityEvaluation.evaluate(gpu: mutated, cpu: reference, tolerance: .bilinear, inputScale: 6400, bilinearPasses: 2)
        let local = ParityEvaluation.evaluate(gpu: mutated, cpu: reference, tolerance: .bilinear, inputScale: 6400,
                                              localScale: regionScales, bilinearPasses: 2)
        #expect(global.passed)          // the defect the review found
        #expect(!local.passed)
    }

    /// E-4 / P-36: the default preview request scales px values, keeps counts, halves the size; rank filters opt out.
    @Test func previewRequestDefault() throws {
        let op = GaussianOperator()
        let request = OperatorRequest(parameters: ParameterValues(["sigma": .double(12), "truncation": .choice("3")]),
                                      variant: GaussianOperator.linearSampled, size: .square(894))
        let half = try #require(op.previewRequest(request, scale: 0.5))
        #expect(half.parameters.double("sigma") == 6 && half.parameters.choice("truncation") == "3")
        #expect(half.size == .square(447) && half.pixelScale == 0.5)
        #expect(PixelPoint(x: 447, y: 301).previewMapped(0.5) == PixelPoint(x: 223, y: 150))
        #expect(op.previewScale(request) == nil)          // light entry: full resolution while moving
    }

    /// E-4: the CPU twin of the frozen 2 × 2 mean.
    @Test func downsample2x() {
        var image = ImageBuffer(width: 5, height: 3)
        for y in 0..<3 { for x in 0..<5 { image[x, y] = SIMD4(Float(x + 10 * y), 0, 0, 1) } }
        let d = image.downsampled2x()
        #expect(d.width == 2 && d.height == 1)
        #expect(d[0, 0].x == (0 + 1 + 10 + 11) / 4 && d[1, 0].x == (2 + 3 + 12 + 13) / 4)
    }

    /// E-10: exposure 2^EV commutes with fp16 rounding for in-range values (so parity is unchanged).
    @Test func exposureCommutesWithHalfRounding() {
        let image = ImageBuffer(width: 4, height: 1, pixels: [SIMD4(0.1234, 3.21, 100, 1), SIMD4(0.02, 0.5, 0.75, 1),
                                                              SIMD4(1e-3, 7, 9, 1), SIMD4(0, 0, 0, 0)])
        let a = image.roundedToHalf().scaled(by: 64).roundedToHalf()
        let b = image.roundedToHalf().scaled(by: 64)
        #expect(a == b)
    }

    /// E-51: digits in plain text segments are a lint violation; badged values and literals are not.
    @Test func badgedLineLint() {
        #expect(!BadgedLine.words("σ HELD 12.0 px").honestyViolations.isEmpty)
        let ok = BadgedLine([.text("σ HELD"), .value(.input(12, .decimals(1, unit: "px"))), .text("→"), .literal("(447, 455)")])
        #expect(ok.honestyViolations.isEmpty)
        let hold = GaussianOperator().holdingSigma(12, current: ParameterValues())
        #expect(hold.statusLine.honestyViolations.isEmpty && !hold.isClamped)
        #expect(GaussianOperator().holdingSigma(80, current: ParameterValues()).isClamped)
    }

    /// E-6: the device rule is read from the probe; absent probe → nil (bilinear parity reportOnly in the app).
    @Test func referenceOptionsForDevice() {
        #expect(ReferenceOptions.forDevice([]) == nil)
        let stamp = DeviceStamp(deviceModel: "iPhone 15 Pro Max", gpuName: "Apple A17 Pro GPU", gpuFamily: "Apple9", osVersion: "iOS 27.0",
                                osBuild: "x", isSimulator: false, date: Date(timeIntervalSince1970: 0), thermal: .nominal, lowPowerMode: false)
        let probe = DeviceProbeResult(kind: .bilinearSubTexelBits, rows: [], numbers: ["subTexelBits": 8, "roundsToNearest": 0], device: stamp)
        #expect(ReferenceOptions.forDevice([probe]) == ReferenceOptions(emulateHalfStorage: true, subTexelBits: 8, subTexelRounding: .truncate))
        #expect(ParityTolerance.bilinear.dependsOnSubTexelRule && !ParityTolerance.exactF32.dependsOnSubTexelRule)
        #expect(!ParityTolerance.rankExact.adjusted(for: SilentSettings(colourSpace: .srgbEncoded)).bitExact)
    }

    /// E-13: trace capacity comes from the plan (taps + the final record).
    @Test func traceCapacityFromPlan() {
        let op = GaussianOperator()
        let r = OperatorRequest(parameters: ParameterValues(["sigma": .double(8), "truncation": .choice("3")]),
                                variant: GaussianOperator.direct2D, size: .square(894))
        #expect(op.passPlan(r).traceCapacity == 49 * 49 + 1)   // 2,401 taps at σ 8, r 24
    }
}
