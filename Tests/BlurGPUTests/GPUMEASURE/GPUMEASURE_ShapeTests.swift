import Foundation
import Metal
import Testing
@testable import BlurCore
@testable import BlurGPU

// OWNER: GPU-MEASURE. ShapeService on the Mac GPU (ARCHITECTURE §8.2 acceptance): the Gaussian σ 4 shape measurement
// gives σ 4.00 ± 0.03 and |excess kurtosis| < 0.05; at the default truncation (k = 3) the measurement equals the
// operator's COMPUTED discrete kernel (σ 3.963, kurtosis −0.17, minimum H −0.0010: what the GPU really runs); no shift
// spread for an LSI blur; ms/MP measured (never in the Simulator).

@MainActor
private func GPUMEASURE_shape(_ context: GPUContext, variant: VariantID, sigma: Double = 4, truncation: String, n: Int = 256,
                              service: ShapeService = ShapeService()) async throws -> MeasureShapeReport {
    let factory = try #require(GPUPipelineRegistry.factory("gaussian-blur", variant))
    let pipeline = factory.make()
    let request = OperatorRequest(parameters: ParameterValues(["sigma": .double(sigma), "truncation": .choice(truncation),
                                                               "discretisation": .choice("sampled")]),
                                  variant: variant, settings: .standard, size: .square(n))
    let report = try await service.measureReport(pipeline, request: request, context: context)
    let m = report.measurement
    print("GPUMEASURE shape \(variant.rawValue) σ\(sigma) k\(truncation) @\(n): σ \(m.sigmaPx) kurt \(m.excessKurtosisAxis) / \(m.excessKurtosis45) "
          + "shift \(m.shiftSpreadPx) minH \(m.minResponse) ms/MP \(m.millisecondsPerMegapixel ?? -1) · edge σ \(report.edgeSigmas) "
          + "edge kurt \(report.edgeKurtosisAxis ?? .nan)/\(report.edgeKurtosis45 ?? .nan) stripes \(report.stripesResponse ?? .nan)")
    return report
}

@Suite(.serialized) struct GPUMEASURE_Shape {
    /// σ 4 with truncation 4σ (the continuous Gaussian to within 0.1 %): σ 4.00 ± 0.03, |kurtosis| < 0.05 on the axis and
    /// at 45°, for the integer-tap, linear-sampled and compute-tile forms.
    @MainActor @Test(arguments: ["gaussian-separable", "gaussian-linear-sampling", "gaussian-compute-tile"] as [VariantID])
    func gaussianSigmaFourMeasuresSigmaFourAndZeroKurtosis(variant: VariantID) async throws {
        guard let context = try GPUMEASURE_context() else { return }
        let report = try await GPUMEASURE_shape(context, variant: variant, truncation: "4")
        let m = report.measurement
        #expect(report.usedImpulseResponse)
        #expect(abs(m.sigmaPx - 4) <= 0.03, "σ \(m.sigmaPx)")
        let kernel = KernelMath.gaussianSampled(sigma: 4, truncation: 4)
        #expect(abs(m.sigmaPx - kernel.sigma) < 0.005 && abs(m.excessKurtosisAxis - kernel.excessKurtosis) < 0.01,
                "the GPU's PSF is the COMPUTED discrete kernel (σ \(kernel.sigma), kurtosis \(kernel.excessKurtosis))")
        #expect(abs(m.excessKurtosisAxis) < 0.05 && abs(m.excessKurtosis45) < 0.05, "kurtosis \(m.excessKurtosisAxis) / \(m.excessKurtosis45)")
        #expect(m.shiftSpreadPx < 0.01, "an LSI blur has no shift variance (\(report.edgeCentreOffsets))")
        #expect(m.minResponse > -0.002 && m.minResponse < 0.01)
        #expect((m.millisecondsPerMegapixel ?? 0) > 0)
        #expect(report.edgeSigmas.count == 4 && report.edgeSigmas.allSatisfy { abs($0 - m.sigmaPx) < 0.02 }, "ESF σ agrees with the PSF σ")
        #expect(abs((report.edgeKurtosis45 ?? 1) - m.excessKurtosis45) < 0.05, "the 45° edge agrees with the PSF's diagonal")
        // Nyquist: a σ 4 Gaussian leaves nothing of 1-px stripes; the outer star ring (0.095 c/px) keeps ≈ 0.06.
        #expect(abs(report.stripesResponse ?? 1) < 0.002)
        #expect(report.rings.count > 30 && (report.rings.first?.frequency ?? 0) > 0.45 && (report.rings.last?.frequency ?? 1) < 0.12)
        let outer = try #require(report.rings.last)
        #expect(abs(outer.response - exp(-2 * pow(Double.pi * 4 * outer.frequency, 2))) < 0.06, "ring \(outer)")
    }

    /// At the default truncation the GPU runs the discrete truncated kernel; the measurement must equal its COMPUTED
    /// moments, not the continuous σ (SPEC §5.3 A: σ_discrete 3.963, minimum H −0.0010).
    @MainActor @Test func defaultTruncationMeasuresTheDiscreteKernel() async throws {
        guard let context = try GPUMEASURE_context() else { return }
        let report = try await GPUMEASURE_shape(context, variant: "gaussian-separable", truncation: "3")
        let kernel = KernelMath.gaussianSampled(sigma: 4, truncation: 3)
        let m = report.measurement
        #expect(abs(m.sigmaPx - kernel.sigma) < 0.005, "measured \(m.sigmaPx) vs COMPUTED \(kernel.sigma)")
        #expect(abs(m.excessKurtosisAxis - kernel.excessKurtosis) < 0.02, "measured \(m.excessKurtosisAxis) vs COMPUTED \(kernel.excessKurtosis)")
        // Separable: the 45° projection is the sum of two independent copies → half the axis kurtosis.
        #expect(abs(m.excessKurtosis45 - kernel.excessKurtosis / 2) < 0.02)
        let computedMin = KernelMath.response(kernel, frequencies: (0...256).map { 0.5 * Double($0) / 256 }).min() ?? 0
        #expect(computedMin < 0 && abs(m.minResponse - computedMin) < 5e-4, "measured min H \(m.minResponse) vs COMPUTED \(computedMin)")
    }

    /// A 128 × 128 window (one impulse) and the Simulator branch (no ms/MP).
    @MainActor @Test func smallWindowAndSimulatorBranch() async throws {
        guard let context = try GPUMEASURE_context() else { return }
        let small = try await GPUMEASURE_shape(context, variant: "gaussian-separable", truncation: "4", n: 128)
        #expect(abs(small.measurement.sigmaPx - 4) <= 0.03)
        let simulated = try await GPUMEASURE_shape(context, variant: "gaussian-separable", truncation: "4",
                                                   service: ShapeService(factsOverride: GPUMEASURE_simulatorFacts()))
        #expect(simulated.measurement.millisecondsPerMegapixel == nil)
        #expect(abs(simulated.measurement.sigmaPx - 4) <= 0.03, "the numbers themselves are still measured")
    }

    @Test func impulseGridGeometry() {
        let c = PixelPoint(x: 447, y: 447)
        let grid = MeasureShapeInputs.impulsePositions(size: .square(894), centre: c, side: 128)
        #expect(grid.count == 4 && grid.contains(PixelPoint(x: 383, y: 383)) && grid.contains(PixelPoint(x: 511, y: 511)))
        #expect(MeasureShapeInputs.impulsePositions(size: .square(128), centre: PixelPoint(x: 64, y: 64), side: 128) == [PixelPoint(x: 64, y: 64)])
    }
}
