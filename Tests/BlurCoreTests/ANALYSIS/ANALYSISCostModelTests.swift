import Foundation
import Testing
@testable import BlurCore

// OWNER: ANALYSIS. Research gpu-pipeline.md §4.1–§4.2 as tests: MODELED bytes for the Gaussian at 894² equal the §4.1
// table (separable and linear-sampled 4B per pixel, 2-D direct 2B), the §4.2 full-screen rows, the bandwidth's honesty,
// and the cost curves.

@Suite struct ANALYSIS_CostModelBytes {
    let model = CostModel()
    let window = ImageSize.square(894)
    let fullScreen = ImageSize(width: 2796, height: 1290)   // GPU §4.2: 3,606,840 px

    private func plan(_ sigma: Double, _ variant: VariantID) -> PassPlan {
        GaussianOperator().passPlan(ANALYSIS_Fixtures.gaussian(sigma, variant: variant).operatorRequest)
    }

    @Test func gaussianAt894EqualsTheSection41Table() {
        // GPU §4.1: separable (discrete taps or linear-sampled, and the compute tile) = 4B per pixel; B = 8 for rgba16Float.
        let n = Double(window.pixelCount)
        #expect(n == 799_236)
        for variant in [GaussianOperator.linearSampled, GaussianOperator.separable, GaussianOperator.computeTile] {
            let cost = model.cost(for: plan(12, variant), size: window, intermediate: .rgba16Float, bandwidth: .a17ProLeak)
            #expect(cost.bytesMoved == 25_575_552)                  // 4 × 8 B × 894²
            #expect(cost.perPassBytes == [12_787_776, 12_787_776])
            #expect(cost.bytesMoved / n == 4 * CostModel.bytesPerTexel(.rgba16Float))
            #expect(abs(cost.floorMilliseconds - 0.49952) < 1e-5)   // 25.6 MB at 51.2 GB/s
        }
        let direct = model.cost(for: plan(4, GaussianOperator.direct2D), size: window, intermediate: .rgba16Float, bandwidth: .a17ProLeak)
        #expect(direct.bytesMoved == 12_787_776)                    // 2B: one pass
        // The model is the §4.1 row for the same algorithm at the same radius and format.
        let table = CostModel.referenceTable(radius: 12)
        #expect(table.first { $0.id == "separable" }!.bytes * n == 25_575_552)
        #expect(table.first { $0.id == "direct-2d" }!.bytes * n == direct.bytesMoved)
    }

    @Test func fullScreenEqualsTheSection42Rows() {
        let separable = model.cost(for: plan(12, GaussianOperator.separable), size: fullScreen, intermediate: .rgba16Float, bandwidth: .a17ProLeak)
        #expect(separable.bytesMoved == 115_418_880)                // "115.4 MB"
        #expect(abs(separable.floorMilliseconds - 2.2543) < 1e-4)   // "2.25 ms"
        let copy = PassPlan(algorithmName: "Copy", passes: [PassDescriptor(id: 0, name: "COPY", kind: .blit, fetchesPerPixel: 1, tapsPerPixel: 1,
                                                                           traceable: false, summary: "copy")])
        let c = model.cost(for: copy, size: fullScreen, intermediate: .rgba16Float, bandwidth: .a17ProLeak)
        #expect(abs(c.bytesMoved / 1e6 - 57.7) < 0.05 && abs(c.floorMilliseconds - 1.13) < 0.005)
        // Dual Kawase, L = 4: four 2× down passes and four 2× up passes chained through the pyramid.
        let scales = [0.5, 0.25, 0.125, 0.0625, 0.125, 0.25, 0.5, 1]
        let kawase = PassPlan(algorithmName: "Dual Kawase", passes: scales.enumerated().map {
            PassDescriptor(id: $0.offset, name: $0.offset < 4 ? "↓\($0.offset + 1)" : "↑\(8 - $0.offset)", kind: .fragment,
                           fetchesPerPixel: $0.offset < 4 ? 5 : 8, tapsPerPixel: $0.offset < 4 ? 5 : 8, outputScale: $0.element,
                           traceable: true, summary: "level")
        })
        let k = model.cost(for: kawase, size: fullScreen, intermediate: .rgba16Float, bandwidth: .a17ProLeak)
        #expect(abs(k.bytesMoved / 1e6 - 95.8) < 0.05)              // "95.8 MB" (3.32B)
        #expect(abs(kawase.fetchesPerPixel - 12.285) < 1e-3)        // SPEC §7.2: ≈ 12.3 fetches per pixel
        // SAT box, RGBA fp32 table: 2B + 16 + 32 + 32 = 96 B per pixel → "≈ 346 MB", 6.8 ms.
        let sat = ANALYSIS_Fixtures.box.passPlan(ANALYSIS_Fixtures.configuration(ANALYSIS_Fixtures.box, variant: "fixture-sat-box", sigma: 12).operatorRequest)
        let s = model.cost(for: sat, size: fullScreen, intermediate: .rgba16Float, bandwidth: .a17ProLeak)
        #expect(s.bytesMoved == 96 * Double(fullScreen.pixelCount))
        #expect(abs(s.bytesMoved / 1e6 - 346.3) < 0.05 && abs(s.floorMilliseconds - 6.76) < 0.01)
    }

    @Test func intermediateFormatAndCPUPasses() {
        // The window texture is always rgba16Float (ARCHITECTURE §4.1), so an rgba8Unorm chain moves 8 + 4 + 4 + 4 = 20 B
        // per pixel, not GPU §4.2's 16 B (which assumes 8-bit input too).
        let rgba8 = model.cost(for: plan(12, GaussianOperator.separable), size: window, intermediate: .rgba8Unorm, bandwidth: .a17ProLeak)
        #expect(rgba8.bytesMoved == 20 * Double(window.pixelCount))
        let cpu = PassPlan(algorithmName: "CPU", passes: [PassDescriptor(id: 0, name: "PLOT", kind: .cpu, fetchesPerPixel: 0, tapsPerPixel: 0,
                                                                         traceable: false, summary: "atlas")])
        #expect(model.cost(for: cpu, size: window, intermediate: .rgba16Float, bandwidth: .a17ProLeak).bytesMoved == 0)
    }

    @Test func referenceTableAtRadiusTwelve() {
        let t = Dictionary(uniqueKeysWithValues: CostModel.referenceTable(radius: 12).map { ($0.id, $0) })
        #expect(t.count == 9)
        #expect(t["direct-2d"]!.fetches == 625 && t["direct-2d"]!.bytes == 16 && t["direct-2d"]!.fmas == 2500)
        #expect(t["separable"]!.fetches == 50 && t["separable"]!.bytes == 32 && t["separable"]!.fmas == 200)
        #expect(t["linear-sampled"]!.fetches == 26)                  // 2(1 + 2⌈r/2⌉): SPEC §5.3 A, 13 per pass
        #expect(t["compute-tile"]!.fetches == 2 * (1 + 24.0 / 256))
        #expect(t["running-sum"]!.fetches == 6 && t["sat"]!.fetches == 7 && t["sat"]!.bytes == 96)
        #expect(abs(t["dual-kawase"]!.fetches - 12.285) < 1e-3 && abs(t["dual-kawase"]!.bytes - 3.3203125 * 8) < 1e-9)
        #expect(t["dual-kawase"]!.fetchesPerPixel.text == "12.3")
        #expect(abs(t["mip-chain"]!.bytes - (4.0 / 3 + 2) * 8) < 1e-9)
        #expect(t["gather"]!.fetches == 64 && t["gather"]!.bytes == 16)
        for row in t.values {
            for v in [row.passes, row.fetchesPerPixel, row.dramBytesPerPixel, row.fmasPerPixel] {
                #expect(v.honestyViolations.isEmpty, "\(row.id): \(v.honestyViolations)")
            }
            #expect(row.dramBytesPerPixel.provenance == .modeled)    // bytes depend on the ideal-cache assumption
        }
        let rgba8 = CostModel.referenceTable(radius: 12, format: .rgba8Unorm)
        #expect(rgba8.first { $0.id == "separable" }!.bytes == 16)
    }
}

@Suite struct ANALYSIS_CostModelHonesty {
    let model = CostModel()

    @Test func assumedBandwidthIsModeledWithWeakSource() {
        let plan = GaussianOperator().passPlan(ANALYSIS_Fixtures.gaussian(12).operatorRequest)
        let cost = model.cost(for: plan, size: .square(894), intermediate: .rgba16Float, bandwidth: .a17ProLeak)
        #expect(cost.bandwidth.provenance == .modeled && cost.bandwidth.qualifiers.contains(.weakSource))
        let rows = model.readout(cost)
        #expect(rows.map(\.id) == ["bytesMoved", "floorMilliseconds", "bandwidth"])
        #expect(rows.allSatisfy { $0.value.honestyViolations.isEmpty })
        #expect(rows[0].value.text == "25.6" && rows[0].value.unit == "MB" && rows[0].value.provenance == .modeled)
        #expect(!rows[0].value.qualifiers.contains(.weakSource))     // bytes do not depend on the bandwidth
        #expect(rows[1].value.text == "0.50" && rows[1].value.provenance == .modeled && rows[1].value.qualifiers.contains(.weakSource))
        #expect(rows[1].value.caption == "UNVERIFIED PEAK")
        #expect(rows[2].value.text == "51.2" && rows[2].value.provenance == .modeled && rows[2].value.qualifiers.contains(.weakSource))
        #expect(CostModel.bandwidth(from: []).assumption == .a17ProLeak && CostModel.bandwidth(from: []).device == nil)
        #expect(model.passReadout(plan, size: .square(894), intermediate: .rgba16Float).allSatisfy {
            $0.value.honestyViolations.isEmpty && $0.value.provenance == .modeled })
    }

    @Test func aMeasuredCopyRateReplacesTheLeak() {
        let probes = [DeviceProbeResult(kind: .copyBandwidthBlit, rows: [], numbers: ["gigabytesPerSecond": 41.0], device: ANALYSIS_Fixtures.device),
                      DeviceProbeResult(kind: .copyBandwidthCompute, rows: [], numbers: ["gigabytesPerSecond": 31.2], device: ANALYSIS_Fixtures.device)]
        let (bandwidth, device) = CostModel.bandwidth(from: probes)
        #expect(bandwidth.gigabytesPerSecond == 31.2 && bandwidth.provenance == .measured && bandwidth.qualifiers.isEmpty)
        #expect(device == ANALYSIS_Fixtures.device)
        #expect(CostModel.bandwidth(from: [probes[0]]).assumption.gigabytesPerSecond == 41)   // blit only: used, labelled as blit
        let plan = GaussianOperator().passPlan(ANALYSIS_Fixtures.gaussian(12).operatorRequest)
        let cost = model.cost(for: plan, size: .square(894), intermediate: .rgba16Float, bandwidth: bandwidth)
        let rows = model.readout(cost, bandwidthDevice: device)
        #expect(rows.allSatisfy { $0.value.honestyViolations.isEmpty })
        #expect(rows[1].value.provenance == .modeled && !rows[1].value.qualifiers.contains(.weakSource))   // a model on a measured rate
        #expect(rows[2].value.provenance == .measured && rows[2].value.device == device)
        #expect(abs(cost.floorMilliseconds - 25_575_552 / 31.2e9 * 1000) < 1e-9)
        // A measured assumption without its device is not shown as MEASURED.
        #expect(model.readout(cost).allSatisfy { $0.value.honestyViolations.isEmpty && $0.value.provenance != .measured })
    }

    @Test func tooSlowToTimeIsAModeledLine() {
        let direct8 = GaussianOperator().passPlan(ANALYSIS_Fixtures.gaussian(8, variant: GaussianOperator.direct2D).operatorRequest)
        #expect(direct8.fetchesPerFrame(.square(894)) < FetchBudget.full)       // 2,401 × 894² = 1.92·10⁹
        #expect(model.tooSlowToTimeLine(direct8, size: .square(894)) == nil)
        let heavy = PassPlan(algorithmName: "Gather", passes: [PassDescriptor(id: 0, name: "GATHER", kind: .fragment, fetchesPerPixel: 4000,
                                                                               tapsPerPixel: 4000, traceable: true, summary: "huge")])
        let line = model.tooSlowToTimeLine(heavy, size: .square(894))!
        #expect(line.text == "TOO SLOW TO TIME · ≈ 213 ms")          // 3.2·10⁹ fetches at 15·10⁹ per second
        #expect(line.honestyViolations.isEmpty)
        #expect(line.values.allSatisfy { $0.provenance == .modeled && $0.qualifiers.contains(.weakSource) })
    }
}

@Suite struct ANALYSIS_CostCurves {
    let model = CostModel()

    @Test func gaussianCurvesPerVariant() {
        let request = ANALYSIS_Fixtures.gaussian(12).operatorRequest
        let series = model.costCurve(for: GaussianOperator(), request: request, sizes: CostModel.standardSizes)
        #expect(series.map(\.name) == ["Linear-sampled", "2-D direct", "Separable", "Compute tile"])
        #expect(series[0].role == .primary && series[0].style == .solid)
        #expect(series.dropFirst().map(\.role) == [.comparisonB, .comparisonC, .comparisonD])
        #expect(series.allSatisfy { $0.provenance == .computed })
        let direct = series[1]
        #expect(direct.xs.max()! <= 8)                                 // disabled above σ 8 (resolves to separable)
        #expect(direct.xs.last == 8 && direct.ys.last == 2401)         // (2·24 + 1)²
        let separable = series[2]
        #expect(separable.xs.count == CostModel.standardSizes.count)
        #expect(separable.ys[separable.xs.firstIndex(of: 4)!] == 50)
        #expect(series[0].ys[series[0].xs.firstIndex(of: 4)!] == 26)   // 13 fetches per pass at σ 4
        let plot = model.costPlot(for: GaussianOperator(), request: request)!
        #expect(plot.xAxis.label == "σ" && plot.xAxis.unit == "px" && plot.yAxis.logarithmic)
        #expect(plot.accessibilitySummary.contains("computed") && plot.accessibilitySummary.contains("Linear-sampled"))
    }

    @Test func entriesWithoutSigmaUseTheirPrimaryInPx() {
        let median = model.costCurve(for: ANALYSIS_Fixtures.median, request: ANALYSIS_Fixtures.configuration(ANALYSIS_Fixtures.median).operatorRequest,
                                     sizes: [1, 2, 4, 8])
        #expect(median.count == 1 && median[0].xs == [1, 2, 4, 8] && median[0].ys == [9, 25, 81, 289])
        #expect(model.costPlot(for: ANALYSIS_Fixtures.median, request: ANALYSIS_Fixtures.configuration(ANALYSIS_Fixtures.median).operatorRequest)?
                    .xAxis.label == "RADIUS")
        #expect(model.costCurve(for: ANALYSIS_Fixtures.zoom, request: ANALYSIS_Fixtures.configuration(ANALYSIS_Fixtures.zoom).operatorRequest,
                                sizes: [1, 2]).isEmpty)                     // AMOUNT in %: no size axis
    }

    /// The live service seam the RenderCoordinator calls is this model.
    @Test func registryServiceIsThisModel() {
        let plan = GaussianOperator().passPlan(ANALYSIS_Fixtures.gaussian(12).operatorRequest)
        #expect(BlurServices.costModel.cost(for: plan, size: .square(894), intermediate: .rgba16Float, bandwidth: .a17ProLeak).bytesMoved == 25_575_552)
        #expect(BlurServices.fingerprints.vector(for: GaussianOperator()).excessKurtosisAxis != nil)
        #expect(BlurServices.divergence.compare(ANALYSIS_Fixtures.gaussian(4), ANALYSIS_Fixtures.gaussian(8), homeToolID: "swiftui",
                                                displayScale: 3).count == 7)
    }
}
