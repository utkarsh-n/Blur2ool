import Foundation

// FROZEN — ARCHITECTURE.md §7. GPU↔CPU parity tolerances and the per-pixel check used by blur-gpucheck and by the
// app's PARITY telemetry. A pixel channel passes when
//   |gpu − cpu| ≤ ulp16 · ulp₁₆(max(|cpu|, 2⁻¹⁴)) + (absolute + perBilinearPass · bilinearPasses) · scale,
// where scale(p) = max(1, max |input| over p's support) — LOCAL, a running max over the radius the plan declares
// (PassPlan.supportRadius); global operators (FFT, IIR) use the window maximum (review fix E-5).

public struct ParityTolerance: Sendable, Codable, Hashable {
    public var name: String
    /// Allowed fp16 ulps of the reference value.
    public var ulp16: Double
    /// Absolute allowance in linear units, multiplied by `scale`.
    public var absolute: Double
    /// Extra absolute allowance per pass that uses hardware bilinear filtering (8-bit sub-texel weights), × `scale`.
    public var perBilinearPass: Double
    /// Rank and selection filters: outputs must equal the reference bit for bit.
    public var bitExact: Bool
    /// Lessons and models: difference is shown, never pass/fail.
    public var reportOnly: Bool
    public init(name: String, ulp16: Double, absolute: Double, perBilinearPass: Double = 0, bitExact: Bool = false,
                reportOnly: Bool = false) {
        self.name = name; self.ulp16 = ulp16; self.absolute = absolute; self.perBilinearPass = perBilinearPass
        self.bitExact = bitExact; self.reportOnly = reportOnly
    }

    /// Integer-tap FIR with fp32 fma accumulation and fp16 storage (box, tent, Gaussian separable/2-D, binomial, USM).
    /// 2 ulps: an fp16 intermediate rounded differently by fp32 and Double accumulation adds one ulp to the final
    /// rounding (MEASURED: separable Gaussian, M1 Max, 2 ulp16 on step edges and mirror/renormalise; review round 1).
    public static let exactF32 = ParityTolerance(name: "exactF32", ulp16: 2, absolute: 0x1p-20)
    /// Kernels that merge taps with hardware bilinear fetches (linear-sampled Gaussian, Kawase, dual Kawase, gathers).
    public static let bilinear = ParityTolerance(name: "bilinear", ulp16: 2, absolute: 0x1p-20, perBilinearPass: 0x1p-10)
    /// In-shader transcendentals under fast math (bilateral range weights, radial/spin trig, sRGB pre/post).
    public static let fastMath = ParityTolerance(name: "fastMath", ulp16: 2, absolute: 0x1p-11)
    /// Recursions and running sums in fp32 (IIR, exponential, stack blur, sliding-window box, PDE iterations).
    public static let recursiveF32 = ParityTolerance(name: "recursiveF32", ulp16: 2, absolute: 0x1p-12)
    /// fp32 FFT round-off (P ≤ 1024).
    public static let fft = ParityTolerance(name: "fft", ulp16: 2, absolute: 0x1p-13)
    /// Median, min/max morphology, Kuwahara sector choice, frosted-glass single realization.
    public static let rankExact = ParityTolerance(name: "rankExact", ulp16: 0, absolute: 0, bitExact: true)
    /// Models, fp16-accumulation lessons, rgba8Unorm intermediates, Apple twins: shown, not judged.
    public static let reportOnly = ParityTolerance(name: "reportOnly", ulp16: .infinity, absolute: .infinity, reportOnly: true)
    /// Plain fp32 summed-area tables: four corner reads, each rounded by two scans (CAT E11, GPU §3.4).
    public static func sat(cornerMagnitude: Double, boxArea: Double) -> ParityTolerance {
        let ulp32 = Double(Float(Swift.max(cornerMagnitude, 1)).ulp)
        return ParityTolerance(name: "satSpacing", ulp16: 2, absolute: 8 * ulp32 / Swift.max(boxArea, 1))
    }

    /// The sum of two tolerances (a bilinear kernel with in-shader transcendentals: `.bilinear.plus(.fastMath)`).
    public func plus(_ other: ParityTolerance) -> ParityTolerance {
        ParityTolerance(name: name + "+" + other.name, ulp16: Swift.max(ulp16, other.ulp16), absolute: absolute + other.absolute,
                        perBilinearPass: perBilinearPass + other.perBilinearPass, bitExact: bitExact && other.bitExact,
                        reportOnly: reportOnly || other.reportOnly)
    }

    /// True for classes whose allowance depends on the hardware sub-texel rule (in-app parity reports them as
    /// reportOnly, `SUB-TEXEL RULE NOT YET MEASURED`, until This phone's probe has run; review fix E-6).
    public var dependsOnSubTexelRule: Bool { perBilinearPass > 0 }

    /// The class actually applied for these settings (review fix E-18): with a colour or alpha pre-pass, a bit-exact
    /// rank class becomes `fastMath` (the pre-pass differs from the CPU by up to 1 fp16 ulp, so selection may pick a
    /// neighbouring value).
    public func adjusted(for settings: SilentSettings) -> ParityTolerance {
        guard bitExact, ColourTransform.needsPasses(settings) else { return self }
        return ParityTolerance(name: name + "→fastMath(colour pass)", ulp16: ParityTolerance.fastMath.ulp16,
                               absolute: ParityTolerance.fastMath.absolute)
    }

    /// The allowance for one channel value.
    public func allowance(reference c: Double, scale: Double, bilinearPasses: Int) -> Double {
        if bitExact { return 0 }
        let u = Double(HalfFloat.ulp(Float(Swift.max(abs(c), 1.0 / 16384))))
        return ulp16 * u + (absolute + perBilinearPass * Double(bilinearPasses)) * Swift.max(1, scale)
    }
}

/// Where values are compared: the domain the blur ran in. sRGB-encoded blurs are compared after encoding both outputs,
/// because the decode post-pass amplifies encoded-space differences by up to 2.3× (ARCHITECTURE §7 rule 3).
public enum ParityDomain: String, Sendable, Codable, Hashable { case linear, encoded }

/// The result of one parity evaluation.
public struct ParityEvaluation: Sendable, Codable, Hashable {
    public var stats: DifferenceStats
    /// max over channels of |gpu − cpu| − allowance (≤ 0 means pass).
    public var worstExcess: Double
    public var failingChannels: Int
    public var passed: Bool
    public init(stats: DifferenceStats, worstExcess: Double, failingChannels: Int, passed: Bool) {
        self.stats = stats; self.worstExcess = worstExcess; self.failingChannels = failingChannels; self.passed = passed
    }

    /// Per-pixel scale for the absolute terms: max(1, max channel magnitude of `input` over the (2r + 1)² square around
    /// each pixel), by a separable van Herk running max (O(1) per pixel). Out-of-image texels are ignored (clamp and
    /// mirror reach only in-image texels); callers use the global maximum for `wrap` and for global operators.
    public static func localScale(_ input: ImageBuffer, radius: Int) -> [Float] {
        let r = Swift.max(0, radius), w = input.width, h = input.height
        func runningMax(_ a: [Float]) -> [Float] {
            let n = a.count, win = 2 * r + 1
            if r == 0 { return a }
            var p = [Float](repeating: -.infinity, count: n + 2 * r)
            for i in 0..<n { p[i + r] = a[i] }
            let m = p.count
            var g = p, hh = p
            for i in 0..<m where i % win != 0 { g[i] = Swift.max(g[i - 1], p[i]) }
            var i = m - 2
            while i >= 0 { if (i + 1) % win != 0 { hh[i] = Swift.max(hh[i + 1], p[i]) }; i -= 1 }
            return (0..<n).map { Swift.max(hh[$0], g[Swift.min(m - 1, $0 + win - 1)]) }
        }
        let mags = input.magnitudes
        var rows = [Float](repeating: 0, count: w * h)
        for y in 0..<h { let out = runningMax(Array(mags[(y * w)..<((y + 1) * w)])); for x in 0..<w { rows[y * w + x] = out[x] } }
        var result = [Float](repeating: 0, count: w * h)
        for x in 0..<w {
            let out = runningMax((0..<h).map { rows[$0 * w + x] })
            for y in 0..<h { result[y * w + x] = out[y] }
        }
        return result
    }

    /// `localScale` (one value per pixel of the compared images) replaces `inputScale` when given.
    public static func evaluate(gpu rawGPU: ImageBuffer, cpu rawCPU: ImageBuffer, tolerance: ParityTolerance, inputScale: Double,
                                localScale: [Float]? = nil, bilinearPasses: Int, domain: ParityDomain = .linear) -> ParityEvaluation {
        let encode: (ImageBuffer) -> ImageBuffer = { image in
            image.map { p in
                let s = ColourTransform.unpremultiply(p)
                return ColourTransform.premultiply(SIMD4(Float(SRGB.encode(Double(s.x))), Float(SRGB.encode(Double(s.y))),
                                                         Float(SRGB.encode(Double(s.z))), s.w))
            }
        }
        let gpu = domain == .encoded ? encode(rawGPU) : rawGPU
        let cpu = domain == .encoded ? encode(rawCPU) : rawCPU
        let stats = DifferenceStats.compare(rawGPU, rawCPU)
        var worst = -Double.infinity, failing = 0
        for i in cpu.pixels.indices {
            let g = gpu.pixels[i], c = cpu.pixels[i]
            for ch in 0..<4 {
                let d = abs(Double(g[ch]) - Double(c[ch]))
                let scale = localScale.map { Double($0[i]) } ?? inputScale
                let excess = d - tolerance.allowance(reference: Double(c[ch]), scale: scale, bilinearPasses: bilinearPasses)
                worst = Swift.max(worst, excess)
                if tolerance.bitExact ? g[ch].bitPattern != c[ch].bitPattern : excess > 0 { failing += 1 }
            }
        }
        return ParityEvaluation(stats: stats, worstExcess: worst, failingChannels: failing,
                                passed: tolerance.reportOnly || failing == 0)
    }
}

/// One GPU↔CPU parity case, published next to its pipeline factory and run by blur-gpucheck (ARCHITECTURE §3.2).
public struct ParityCase: Sendable, Hashable {
    public var name: String
    public var configuration: RenderConfiguration
    public var tolerance: ParityTolerance
    /// Passes that sample with hardware bilinear filtering (for the tolerance's per-pass term).
    public var bilinearPasses: Int
    /// Assert traced == untraced bit for bit and trace final sum == output at each probe (all Tier 1 kernels).
    public var checkTraced: Bool
    public var probes: [PixelPoint]
    /// Why this case exists / which SPEC fixture it reproduces ("SPEC §5.3 A").
    public var note: String
    public init(name: String, configuration: RenderConfiguration, tolerance: ParityTolerance, bilinearPasses: Int,
                checkTraced: Bool, probes: [PixelPoint], note: String) {
        self.name = name; self.configuration = configuration; self.tolerance = tolerance; self.bilinearPasses = bilinearPasses
        self.checkTraced = checkTraced; self.probes = probes; self.note = note
    }
}
