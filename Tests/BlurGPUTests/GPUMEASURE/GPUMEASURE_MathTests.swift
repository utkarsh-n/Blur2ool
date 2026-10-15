import Foundation
import Testing
@testable import BlurCore
@testable import BlurGPU

// OWNER: GPU-MEASURE. CPU-only checks of the measurement arithmetic: timing statistics, PSF and line-spread moments,
// the projection–slice response, the stripes/star modulation and the sub-texel analysis on synthetic hardware answers.

@Suite struct GPUMEASURE_Statistics {
    @Test func medianAndInterquartileRangeUseLinearInterpolation() {
        #expect(MeasureStatistics.median([4, 1, 3, 2]) == 2.5)
        #expect(MeasureStatistics.iqr([1, 2, 3, 4]) == 1.5)             // Q1 1.75, Q3 3.25
        #expect(MeasureStatistics.median([7]) == 7 && MeasureStatistics.iqr([7]) == 0)
        #expect(MeasureStatistics.median([]) == nil)
        #expect(MeasureStatistics.median([1, .nan, 3]) == 2)              // non-finite samples never count
    }
}

@Suite struct GPUMEASURE_Moments {
    /// A sampled Gaussian wide enough that truncation is negligible: σ and zero excess kurtosis.
    @Test func gaussianProfileHasItsSigmaAndZeroKurtosis() throws {
        let k = KernelMath.gaussianSampled(sigma: 4, truncation: 8)
        let m = try #require(MeasureProfileMoments(weights: k.weights, positions: k.weights.indices.map { Double($0 - k.origin) }))
        #expect(abs(m.sigma - 4) < 1e-6)
        #expect(abs(m.excessKurtosis) < 1e-6)
        #expect(abs(m.mean) < 1e-12)
    }

    /// Discrete uniform on n points: excess kurtosis −6(n² + 1) / (5(n² − 1)) (→ −1.2 for a continuous box).
    @Test func boxProfileKurtosis() throws {
        let n = 9.0
        let m = try #require(MeasureProfileMoments(weights: Array(repeating: 1, count: 9), positions: (0..<9).map(Double.init)))
        #expect(abs(m.excessKurtosis - (-6 * (n * n + 1) / (5 * (n * n - 1)))) < 1e-12)
    }

    /// A separable box: the 45° projection is the sum of two independent boxes, so its excess kurtosis is half the axis
    /// value (κ₄ adds, σ² adds): the separable-vs-isotropic signature of SPEC §7.4.
    @Test func separableBoxDiagonalKurtosisIsHalfTheAxis() throws {
        let side = 9
        let psf = [Double](repeating: 1.0 / 81, count: side * side)
        let m = try #require(MeasurePSFMoments(psf: psf, width: side, height: side))
        #expect(abs(m.mass - 1) < 1e-12)
        #expect(abs(m.x.excessKurtosis - m.y.excessKurtosis) < 1e-12)
        #expect(abs(m.diagonal45.excessKurtosis - m.x.excessKurtosis / 2) < 1e-9)
        #expect(abs(m.diagonal135.excessKurtosis - m.x.excessKurtosis / 2) < 1e-9)
        #expect(abs(m.sigma - (80.0 / 12).squareRoot()) < 1e-9)          // discrete uniform variance (n² − 1)/12
    }

    /// An isotropic Gaussian PSF: the same kurtosis (0) on the axis and at 45°.
    @Test func separableGaussianPSFIsIsotropicInItsMoments() throws {
        let k = KernelMath.gaussianSampled(sigma: 3, truncation: 8)
        let g = Kernel2D(separable: k, k)
        let m = try #require(MeasurePSFMoments(psf: g.weights, width: g.width, height: g.height))
        #expect(abs(m.sigma - 3) < 1e-6)
        #expect(abs(m.x.excessKurtosis) < 1e-6 && abs(m.diagonal45.excessKurtosis) < 1e-6)
        #expect(abs(m.centroid.x - (Double(g.originX) + 0.5)) < 1e-9)
    }

    @Test func zeroMassIsNotAMeasurement() {
        #expect(MeasureProfileMoments(weights: [1, -1], positions: [0, 1]) == nil)
        #expect(MeasurePSFMoments(psf: [0, 0, 0, 0], width: 2, height: 2) == nil)
    }
}

@Suite struct GPUMEASURE_Response {
    /// The 3-tap box's response (1 + 2cos 2πν)/3 has its minimum −1/3 at Nyquist, on the axis slices; the diagonal
    /// slice of the separable 2-D box is H(ν)², never negative.
    @Test func minimumResponseOfTheThreeTapBox() throws {
        let psf = [Double](repeating: 1.0 / 9, count: 9)
        let minimum = try #require(MeasureShapeMath.minimumResponse(psf: psf, width: 3, height: 3))
        #expect(abs(minimum - (-1.0 / 3)) < 1e-12)
        let slices = MeasureShapeMath.slices(psf: psf, width: 3, height: 3)
        let diagonal = MeasureShapeMath.response(weights: slices[2].weights, positions: slices[2].positions, frequencies: [0.5])
        #expect(abs(diagonal[0] - 1.0 / 9) < 1e-12)                      // (−1/3)²
    }

    /// The response of a symmetric kernel equals KernelMath.response (the COMPUTED curve the floors print).
    @Test func responseMatchesKernelMath() {
        let k = KernelMath.gaussianSampled(sigma: 4, truncation: 3)
        let nus = (0...32).map { Double($0) / 64 }
        let ours = MeasureShapeMath.response(weights: k.weights, positions: k.weights.indices.map(Double.init), frequencies: nus)
        let theirs = KernelMath.response(k, frequencies: nus)
        #expect(zip(ours, theirs).allSatisfy { abs($0 - $1) < 1e-12 })
    }

    @Test func lineSpreadOfAStepIsAnImpulseAtTheBoundary() throws {
        let esf: [Double] = [0, 0, 0, 1, 1, 1]
        let lsf = MeasureShapeMath.lineSpread(esf: esf, origin: 10)
        #expect(lsf.weights == [0, 0, 1, 0, 0])
        let m = MeasureProfileMoments(weights: lsf.weights, positions: lsf.positions)
        #expect(m == nil)                                                 // a perfect step has zero variance
        #expect(lsf.positions[2] == 13)                                   // between pixels 12 and 13: continuous x = 13
    }

    @Test func modulationIsTheSignedGainOfAPattern() throws {
        let pattern = (0..<64).map { $0 % 2 == 0 ? 0.5 : -0.5 }
        #expect(abs(try #require(MeasureShapeMath.modulation(output: pattern.map { 0.5 + 0.3 * $0 }, pattern: pattern)) - 0.3) < 1e-12)
        #expect(abs(try #require(MeasureShapeMath.modulation(output: pattern.map { 0.5 - 0.2 * $0 }, pattern: pattern)) + 0.2) < 1e-12)
        #expect(abs(MeasureShapeMath.starFrequency(radius: 36 / (2 * Double.pi) / 0.5) - 0.5) < 1e-12)
    }
}

@Suite struct GPUMEASURE_SubTexelAnalysis {
    static func synthetic(bits: Int, nearest: Bool, count: Int = 65_536) -> [Float] {
        let q = pow(2.0, Double(bits))
        return (0..<count).map { i in
            let x = Double(i) / Double(count) * q
            return Float((nearest ? (x + 0.5).rounded(.down) : x.rounded(.down)) / q)
        }
    }

    @Test func eightBitsRoundedToNearest() {
        let a = MeasureSubTexelAnalysis(samples: Self.synthetic(bits: 8, nearest: true), count: 65_536)
        #expect(a.bits == 8 && a.distinct == 257 && a.roundsToNearest)
        #expect(a.nearestFraction == 1)
        #expect(abs(a.maxError - 1.0 / 512) < 1e-12)
    }

    @Test func sixBitsTruncated() {
        let a = MeasureSubTexelAnalysis(samples: Self.synthetic(bits: 6, nearest: false), count: 65_536)
        #expect(a.bits == 6 && a.distinct == 64 && !a.roundsToNearest)
        #expect(a.truncateFraction == 1)
    }

    /// The number ReferenceOptions.forDevice reads turns into the parity rule.
    @Test func probeNumbersBecomeTheReferenceRule() {
        let stamp = GPUMEASURE_macStamp()
        let result = DeviceProbeResult(kind: .bilinearSubTexelBits, rows: [], numbers: ["subTexelBits": 8, "roundsToNearest": 1], device: stamp)
        #expect(ReferenceOptions.forDevice([result]) == .parity)
        let truncating = DeviceProbeResult(kind: .bilinearSubTexelBits, rows: [], numbers: ["subTexelBits": 6, "roundsToNearest": 0], device: stamp)
        #expect(ReferenceOptions.forDevice([truncating]) == ReferenceOptions(emulateHalfStorage: true, subTexelBits: 6, subTexelRounding: .truncate))
    }
}

/// The Mac's stamp for MEASURED rows in these tests.
func GPUMEASURE_macStamp(simulator: Bool = false) -> DeviceStamp {
    DeviceStamp(deviceModel: simulator ? "Simulator" : "Mac (Apple M1 Max)", gpuName: "Apple M1 Max", gpuFamily: "Apple7",
                osVersion: "macOS 27.2", osBuild: "test", isSimulator: simulator, date: Date(timeIntervalSince1970: 1_791_936_000),
                thermal: .nominal, lowPowerMode: false)
}
