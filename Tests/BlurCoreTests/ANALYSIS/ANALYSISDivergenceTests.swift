import Foundation
import Testing
@testable import BlurCore

// OWNER: ANALYSIS. SPEC §8.4: the divergence function. The 16 reference rows run against the REAL registry (rows whose
// entries this mirror does not register are listed and skipped; INTEGRATE re-runs them with every FAM area present).
// The rule suites exercise each floor's rule with the real Gaussian and the fixtures of ANALYSISFixtures.swift.

/// One reference row of SPEC §8.4: two configurations built from the registry, and the floor where they must part.
struct ANALYSIS_ReferenceRow: Sendable, CustomTestStringConvertible {
    var number: Int
    var title: String
    var expected: Floor
    var homeToolID: String = "swiftui"
    /// Entries (and variants) the row needs, for the skip list.
    var needs: [String]
    var build: @Sendable (DivergenceEngine) -> (RenderConfiguration, RenderConfiguration)?
    var testDescription: String { "row \(number): \(title)" }

    static let scale = 3.0

    /// A registered entry's configuration (defaults σ-held at `sigma`), or nil when the entry or variant is missing.
    static func config(_ id: BlurID, variant: VariantID? = nil, sigma: Double? = nil, primary: Double? = nil,
                       settings: SilentSettings = .standard) -> RenderConfiguration? {
        guard let op = BlurRegistry.op(id) else { return nil }
        if let variant, op.entry.variant(variant) == nil { return nil }
        var overrides: [ParameterKey: ParameterValue] = [:]
        if let primary, let key = op.entry.primarySpec?.key { overrides[key] = .double(primary) }
        return ANALYSIS_Fixtures.configuration(op, variant: variant, sigma: sigma, parameters: overrides, settings: settings)
    }

    /// `id` σ-held beside `a` (SPEC §8.1), or nil when it is not registered.
    static func held(_ engine: DivergenceEngine, _ id: BlurID, _ a: RenderConfiguration?) -> (RenderConfiguration, RenderConfiguration)? {
        guard let a, let b = engine.heldConfiguration(id, matching: a) else { return nil }
        return (a, b)
    }

    static func pair(_ a: RenderConfiguration?, _ b: RenderConfiguration?) -> (RenderConfiguration, RenderConfiguration)? {
        guard let a, let b else { return nil }
        return (a, b)
    }

    static let all: [ANALYSIS_ReferenceRow] = [
        ANALYSIS_ReferenceRow(number: 1, title: "gaussian-2d-direct vs gaussian-separable (σ 4)", expected: .algorithm,
                              needs: ["gaussian-blur/gaussian-2d-direct", "gaussian-blur/gaussian-separable"]) { _ in
            pair(config("gaussian-blur", variant: GaussianOperator.direct2D, sigma: 4), config("gaussian-blur", variant: GaussianOperator.separable, sigma: 4))
        },
        ANALYSIS_ReferenceRow(number: 2, title: "gaussian-separable vs gaussian-linear-sampling (σ 4)", expected: .gpu,
                              needs: ["gaussian-blur/gaussian-separable", "gaussian-blur/gaussian-linear-sampling"]) { _ in
            pair(config("gaussian-blur", variant: GaussianOperator.separable, sigma: 4), config("gaussian-blur", variant: GaussianOperator.linearSampled, sigma: 4))
        },
        ANALYSIS_ReferenceRow(number: 3, title: "gaussian-blur vs heat-equation (σ 4)", expected: .kernel,
                              needs: ["gaussian-blur", "heat-equation"]) { engine in
            held(engine, "heat-equation", config("gaussian-blur", sigma: 4))
        },
        ANALYSIS_ReferenceRow(number: 4, title: "gaussian-blur vs iir-gaussian (σ held from the IIR's moment σ)", expected: .kernel,
                              needs: ["iir-gaussian", "gaussian-blur"]) { engine in
            held(engine, "gaussian-blur", config("iir-gaussian", sigma: 12))
        },
        ANALYSIS_ReferenceRow(number: 5, title: "box-blur vs gaussian-blur (equal σ 12)", expected: .math,
                              needs: ["box-blur", "gaussian-blur"]) { engine in
            held(engine, "gaussian-blur", config("box-blur", sigma: 12))
        },
        ANALYSIS_ReferenceRow(number: 6, title: "iterated-box (n = 3) vs gaussian-blur", expected: .math,
                              needs: ["iterated-box", "gaussian-blur"]) { engine in
            held(engine, "gaussian-blur", config("iterated-box", sigma: 12))
        },
        ANALYSIS_ReferenceRow(number: 7, title: "kawase-blur vs gaussian-blur (Gaussian held at Kawase's σ)", expected: .math,
                              needs: ["kawase-blur", "gaussian-blur"]) { engine in
            held(engine, "gaussian-blur", config("kawase-blur", sigma: 12))
        },
        ANALYSIS_ReferenceRow(number: 8, title: "box-blur (separable) vs box-blur → sat-box", expected: .algorithm,
                              needs: ["box-blur/<separable variant>", "box-blur/sat-box"]) { _ in
            guard let op = BlurRegistry.op("box-blur"),
                  let separable = op.entry.variants.first(where: { $0.algorithmClass == .separableFIR && $0.id != "sat-box" })?.id else { return nil }
            return pair(config("box-blur", variant: separable, sigma: 12), config("box-blur", variant: "sat-box", sigma: 12))
        },
        ANALYSIS_ReferenceRow(number: 9, title: "CSS blur(10px) vs SwiftUI .blur(radius: 10), home tool CSS", expected: .api, homeToolID: "css",
                              needs: ["gaussian-blur", "swiftui-layer-blur"]) { _ in
            pair(config("gaussian-blur", sigma: 10 * scale), config("swiftui-layer-blur", primary: 10))
        },
        ANALYSIS_ReferenceRow(number: 10, title: "Figma layer blur 10 (σ 5 CSS px) vs CSS blur(10px), home tool CSS", expected: .slide,
                              homeToolID: "css", needs: ["gaussian-blur"]) { _ in
            pair(config("gaussian-blur", sigma: 5 * scale), config("gaussian-blur", sigma: 10 * scale))
        },
        ANALYSIS_ReferenceRow(number: 11, title: "same blur, linear light vs sRGB-encoded", expected: .api, needs: ["gaussian-blur"]) { _ in
            pair(config("gaussian-blur", sigma: 4), config("gaussian-blur", sigma: 4, settings: SilentSettings(colourSpace: .srgbEncoded)))
        },
        ANALYSIS_ReferenceRow(number: 12, title: "radial-zoom-blur vs spin-blur", expected: .math, needs: ["radial-zoom-blur", "spin-blur"]) { engine in
            held(engine, "spin-blur", config("radial-zoom-blur"))
        },
        ANALYSIS_ReferenceRow(number: 13, title: "disc-blur vs polygonal-bokeh", expected: .math, needs: ["disc-blur", "polygonal-bokeh"]) { engine in
            held(engine, "polygonal-bokeh", config("disc-blur", sigma: 12))
        },
        ANALYSIS_ReferenceRow(number: 14, title: "bilateral vs gaussian-blur", expected: .math, needs: ["bilateral", "gaussian-blur"]) { engine in
            held(engine, "gaussian-blur", config("bilateral", sigma: 12))
        },
        ANALYSIS_ReferenceRow(number: 15, title: "bilateral vs guided (σ 10: guided's whole radius stays within 3 %)", expected: .math,
                              needs: ["guided", "bilateral"]) { engine in
            held(engine, "bilateral", config("guided", sigma: 10))
        },
        ANALYSIS_ReferenceRow(number: 16, title: "median vs bilateral", expected: .math, needs: ["median", "bilateral"]) { engine in
            held(engine, "bilateral", config("median"))
        },
    ]
}

@Suite struct ANALYSIS_DivergenceReferenceRows {
    let engine = DivergenceEngine()

    @Test(arguments: ANALYSIS_ReferenceRow.all)
    func firstDifference(_ row: ANALYSIS_ReferenceRow) {
        guard let (a, b) = row.build(engine) else {
            print("ANALYSIS reference row \(row.number) SKIPPED (not registered in this mirror: \(row.needs.joined(separator: ", "))): \(row.title)")
            return
        }
        let rows = engine.rows(a, b, homeToolID: row.homeToolID, displayScale: ANALYSIS_ReferenceRow.scale)
        #expect(rows.map(\.floor) == Floor.allCases)
        let first = DivergenceEngine.firstDifference(rows.map(\.comparison))
        #expect(first?.floor == row.expected, "row \(row.number): \(rows.map { "\($0.floor.railLabel) \($0.verdict.railSymbol) \($0.line.text)" })")
        #expect(ANALYSIS_Fixtures.violations(rows).isEmpty, "\(ANALYSIS_Fixtures.violations(rows))")
        print("ANALYSIS reference row \(row.number) RAN: parts ways at \(first?.floor.tileLabel ?? "none") · \(first?.reason ?? "")")
        for r in rows { print("    \(r.floor.railLabel.padding(toLength: 5, withPad: " ", startingAt: 0)) \(r.verdict.railSymbol)\(r.verdict == .partsWays ? "▶" : " ") \(r.line.text)") }
    }

    /// The rows only the Gaussian needs always run (SKEL registers it), so the table is never vacuous in any mirror.
    @Test func summaryListsRanAndSkipped() {
        var ran: [Int] = [], skipped: [String] = []
        for row in ANALYSIS_ReferenceRow.all {
            if row.build(engine) != nil { ran.append(row.number) } else { skipped.append("\(row.number) (\(row.needs.joined(separator: ", ")))") }
        }
        print("ANALYSIS reference rows: ran \(ran.count) \(ran) · skipped \(skipped.count): \(skipped.joined(separator: "; "))")
        #expect(ran.count + skipped.count == 16)
        #expect(Set([1, 2, 10, 11]).isSubset(of: Set(ran)))
    }

    @Test func row1NamesTheTaps() {   // "625 vs 50 taps at σ 4"
        let a = ANALYSIS_Fixtures.gaussian(4, variant: GaussianOperator.direct2D), b = ANALYSIS_Fixtures.gaussian(4, variant: GaussianOperator.separable)
        let algorithm = engine.rows(a, b, homeToolID: "swiftui", displayScale: 3)[Floor.algorithm.rawValue - 1]
        #expect(algorithm.verdict == .partsWays)
        #expect(algorithm.line.values.compactMap(\.value) == [1, 625, 2, 50])
        let pixels = engine.rows(a, b, homeToolID: "swiftui", displayScale: 3)[Floor.pixels.rawValue - 1]
        #expect(pixels.verdict == .approximatelySame)   // same kernel, not yet compared on pixels
    }

    @Test func row2NamesTheFetches() {   // "25 integer vs 13 bilinear fetches per pass"
        let a = ANALYSIS_Fixtures.gaussian(4, variant: GaussianOperator.separable), b = ANALYSIS_Fixtures.gaussian(4)
        let rows = engine.rows(a, b, homeToolID: "swiftui", displayScale: 3)
        #expect(rows[Floor.algorithm.rawValue - 1].verdict == .same)
        let gpu = rows[Floor.gpu.rawValue - 1]
        #expect(gpu.verdict == .partsWays)
        #expect(gpu.line.values.compactMap(\.value) == [25, 13])
        #expect(gpu.line.text.contains("integer") && gpu.line.text.contains("bilinear"))
    }
}

@Suite struct ANALYSIS_DivergenceRules {
    let engine = ANALYSIS_Fixtures.engine()

    private func rows(_ a: RenderConfiguration, _ b: RenderConfiguration, home: String = "swiftui",
                      pixels: DivergenceEngine.PixelEvidence? = nil) -> [DivergenceEngine.Row] {
        engine.rows(a, b, homeToolID: home, displayScale: 3, pixels: pixels)
    }
    private func first(_ rows: [DivergenceEngine.Row]) -> Floor? { DivergenceEngine.firstDifference(rows.map(\.comparison))?.floor }
    private func row(_ rows: [DivergenceEngine.Row], _ floor: Floor) -> DivergenceEngine.Row { rows[floor.rawValue - 1] }

    @Test func sevenRowsInFloorOrderAndNothingForUnknownBlurs() {
        let r = rows(ANALYSIS_Fixtures.gaussian(12), ANALYSIS_Fixtures.gaussian(4))
        #expect(r.map(\.floor) == Floor.allCases)
        #expect(r.filter { $0.verdict == .partsWays }.count == 1)
        var unknown = ANALYSIS_Fixtures.gaussian(4); unknown.blur = "no-such-blur"
        #expect(engine.compare(unknown, ANALYSIS_Fixtures.gaussian(4), homeToolID: "swiftui", displayScale: 3).isEmpty)
    }

    @Test func notInTheHomeToolIsShownButSkipped() {   // SPEC §8.4 floor 1; §4.2 "SLIDE ≠ · NOT IN SWIFTUI"
        let box = ANALYSIS_Fixtures.configuration(ANALYSIS_Fixtures.box, sigma: 12)
        let gauss = engine.heldConfiguration("gaussian-blur", matching: box)!
        let r = rows(box, gauss)
        #expect(row(r, .slide).verdict == .differs)
        #expect(row(r, .slide).isSkippedForFirstDifference)
        #expect(row(r, .slide).comparison.reason == "NOT IN SWIFTUI")
        #expect(row(r, .api).verdict == .same)                    // w 41 → σ 11.83 vs the held Gaussian, within 3 %
        #expect(first(r) == .math)                                // rect vs bell
        #expect(row(r, .math).line.text == "rect vs bell")
        #expect(DivergenceEngine.statusLine(r.map(\.comparison)).text == "PARTS WAYS AT MATH")
    }

    @Test func slideComparesTypedValuesAtDisplayPrecision() {   // Figma 10 vs CSS 10 → σ 5 vs 10 CSS px
        let figma = ANALYSIS_Fixtures.gaussian(15), css = ANALYSIS_Fixtures.gaussian(30)
        let r = rows(figma, css, home: "css")
        #expect(row(r, .slide).verdict == .partsWays)
        #expect(row(r, .slide).line.values.map(\.text) == ["5.0", "10.0"])
        #expect(row(r, .slide).line.values.allSatisfy { $0.provenance == .reference })
        let same = rows(ANALYSIS_Fixtures.gaussian(15), ANALYSIS_Fixtures.gaussian(15, variant: GaussianOperator.separable), home: "css")
        #expect(row(same, .slide).verdict == .same)
    }

    @Test func unverifiedMappingsDecideByTheBlursOwnInputs() {   // Photoshop: UNVERIFIED for everything
        let r = rows(ANALYSIS_Fixtures.gaussian(4), ANALYSIS_Fixtures.gaussian(8), home: "photoshop")
        #expect(row(r, .slide).verdict == .partsWays)              // one blur, different σ: types differently
        #expect(row(r, .slide).line.text.contains("mapping unverified"))
        let box = ANALYSIS_Fixtures.configuration(ANALYSIS_Fixtures.box, sigma: 12)
        let other = rows(box, engine.heldConfiguration("gaussian-blur", matching: box)!, home: "photoshop")
        #expect(row(other, .slide).isSkippedForFirstDifference)    // two blurs, unknown mapping: not a claim
        #expect(row(other, .slide).comparison.reason == "UNVERIFIED IN PHOTOSHOP")
        #expect(first(other) == .math)
    }

    @Test func apiNormalisesToSigmaWithinThreePercent() {
        let close = rows(ANALYSIS_Fixtures.gaussian(12), ANALYSIS_Fixtures.gaussian(12.3), home: "photoshop")
        #expect(row(close, .api).verdict == .same)                 // 2.5 %: the σ-hold residual
        #expect(first(close) == .slide || first(close) == .math)
        let far = rows(ANALYSIS_Fixtures.gaussian(12), ANALYSIS_Fixtures.gaussian(12.5), home: "css")
        #expect(row(far, .api).verdict == .differs)               // 4.2 %
        let srgb = rows(ANALYSIS_Fixtures.gaussian(4), ANALYSIS_Fixtures.gaussian(4, settings: SilentSettings(colourSpace: .srgbEncoded)))
        #expect(first(srgb) == .api)
        #expect(row(srgb, .api).line.text.contains("LINEAR LIGHT vs sRGB-ENCODED"))
        let edges = rows(ANALYSIS_Fixtures.gaussian(4), ANALYSIS_Fixtures.gaussian(4, settings: SilentSettings(edgeMode: .mirror)))
        #expect(first(edges) == .api && row(edges, .api).line.text.contains("CLAMP EDGES vs MIRROR EDGES"))
        let alpha = rows(ANALYSIS_Fixtures.gaussian(4), ANALYSIS_Fixtures.gaussian(4, settings: SilentSettings(alphaMode: .straight)))
        #expect(first(alpha) == .api)
    }

    @Test func blursWithoutSigmaPartAtMath() {   // rows 12 and 16 with fixtures
        let zoom = ANALYSIS_Fixtures.configuration(ANALYSIS_Fixtures.zoom)
        let spin = engine.heldConfiguration("fixture-spin", matching: zoom)!
        let r = rows(zoom, spin)
        #expect(row(r, .api).verdict == .same)
        #expect(first(r) == .math)
        #expect(row(r, .math).line.text == "scaling about the centre vs rotation about the centre")
        let median = ANALYSIS_Fixtures.configuration(ANALYSIS_Fixtures.median)
        let m = rows(median, engine.heldConfiguration("gaussian-blur", matching: median)!)
        #expect(row(m, .api).verdict == .same && row(m, .api).line.text.contains("σ NOT DEFINED"))
        #expect(first(m) == .math)
        var wider = median; wider.parameters["radius"] = .int(3)
        #expect(first(rows(median, wider)) == .api)               // same blur without σ: its primary, in its own unit
    }

    @Test func kernelFloorComparesTheEffectivePSF() {   // row 3 with the explicit 5-point fixture: same bell, different kernel
        let gauss = ANALYSIS_Fixtures.gaussian(4)
        let heat = engine.heldConfiguration("fixture-heat", matching: gauss)!
        #expect(heat.parameters.double("time") == 7.75)           // t = σ²/2 of the discrete σ 3.963, in whole λ = ¼ steps
        let r = rows(gauss, heat)
        #expect(row(r, .api).verdict == .same)
        #expect(row(r, .math).verdict == .same)
        #expect(first(r) == .kernel)
        let delta = row(r, .kernel).line.values.first?.value ?? 0
        #expect(delta > 1e-3)                                     // the explicit PSF lives on even-parity pixels
        let same = rows(ANALYSIS_Fixtures.gaussian(4, variant: GaussianOperator.direct2D), ANALYSIS_Fixtures.gaussian(4, variant: GaussianOperator.separable))
        #expect(row(same, .kernel).verdict == .same)
        let truncated = ANALYSIS_Fixtures.configuration(GaussianOperator(), sigma: 4, parameters: ["truncation": .choice("4")])
        #expect(first(rows(ANALYSIS_Fixtures.gaussian(4), truncated)) == .kernel)   // same σ within 3 %, same bell, more taps
    }

    @Test func algorithmFloorReadsThePassGraph() {   // row 8 with the fixture box
        let separable = ANALYSIS_Fixtures.configuration(ANALYSIS_Fixtures.box, variant: "fixture-box-separable", sigma: 12)
        var sat = separable; sat.variant = "fixture-sat-box"
        let r = rows(separable, sat)
        #expect(first(r) == .algorithm)
        #expect(row(r, .algorithm).line.text.contains("SCAN ROWS"))
        let tile = rows(ANALYSIS_Fixtures.gaussian(4, variant: GaussianOperator.separable), ANALYSIS_Fixtures.gaussian(4, variant: GaussianOperator.computeTile))
        #expect(row(tile, .algorithm).verdict == .same)
        #expect(first(tile) == .gpu)
        #expect(row(tile, .gpu).line.text.contains("compute") && row(tile, .gpu).line.text.contains("fragment"))
    }

    @Test func gpuFloorIncludesPrecisionSettings() {
        let fp16 = SilentSettings(accumulator: .fp16)
        let r = rows(ANALYSIS_Fixtures.gaussian(4), ANALYSIS_Fixtures.gaussian(4, settings: fp16))
        #expect(first(r) == .gpu)
        #expect(row(r, .gpu).line.text.contains("fp32 vs fp16 accumulator"))
        #expect(row(r, .pixels).verdict == .differs)              // lower precision: not predicted equal
        let rgba8 = rows(ANALYSIS_Fixtures.gaussian(4), ANALYSIS_Fixtures.gaussian(4, settings: SilentSettings(intermediate: .rgba8Unorm)))
        #expect(first(rgba8) == .gpu && row(rgba8, .gpu).line.text.contains("rgba8Unorm"))
        // SAT centring matters only to summed-area tables.
        let centred = rows(ANALYSIS_Fixtures.gaussian(4), ANALYSIS_Fixtures.gaussian(4, settings: SilentSettings(satCentring: .meanCentred)))
        #expect(row(centred, .gpu).verdict == .same)
    }

    @Test func pixelFloorUsesOneFP16Ulp() {   // SPEC §8.4 floor 7
        let a = ANALYSIS_Fixtures.gaussian(4)
        let identical = rows(a, a, pixels: .init(stats: ANALYSIS_Fixtures.stats(maxAbs: 0, ulp: 0, lsb: 0)))
        #expect(row(identical, .pixels).verdict == .same)
        #expect(DivergenceEngine.statusLine(identical.map(\.comparison)).text == "SAME AT EVERY FLOOR")
        let lastBit = rows(a, a, pixels: .init(stats: ANALYSIS_Fixtures.stats(maxAbs: 4.9e-4, ulp: 1, lsb: 0)))
        #expect(row(lastBit, .pixels).verdict == .approximatelySame)
        #expect(row(lastBit, .pixels).verdict.railSymbol == "≈")
        #expect(first(lastBit) == nil)
        let worse = rows(a, a, pixels: .init(stats: ANALYSIS_Fixtures.stats(maxAbs: 3.9e-3, ulp: 3, lsb: 1)))
        #expect(first(worse) == .pixels)                          // every other floor equal: the pixels part ways
        #expect(row(worse, .pixels).line.values.compactMap(\.value) == [1, 3])
        #expect(row(worse, .pixels).line.values.allSatisfy { $0.provenance == .live })
        let parity = rows(a, a, pixels: .init(stats: ANALYSIS_Fixtures.stats(maxAbs: 3.9e-3, ulp: 3, lsb: 1), provenance: .measured,
                                              device: ANALYSIS_Fixtures.device))
        #expect(ANALYSIS_Fixtures.violations(parity).isEmpty)
        #expect(row(parity, .pixels).line.values.allSatisfy { $0.provenance == .measured && $0.device != nil })
        // Without pixels: identical configurations are the same pixels; different kernels are not yet compared.
        #expect(row(rows(a, a), .pixels).verdict == .same)
        #expect(row(rows(a, ANALYSIS_Fixtures.gaussian(8)), .pixels).line.text.contains("not yet compared"))
    }

    @Test func cssVersusSwiftUIPartsAtAPI() {   // row 9 with the SwiftUI fixture, home tool CSS
        let css = ANALYSIS_Fixtures.gaussian(30)
        let swiftUI = ANALYSIS_Fixtures.configuration(ANALYSIS_Fixtures.swiftUI, parameters: ["radius": .double(10)])
        let r = rows(css, swiftUI, home: "css")
        #expect(row(r, .slide).comparison.reason == "NOT IN CSS")
        #expect(row(r, .slide).isSkippedForFirstDifference)
        #expect(first(r) == .api)                                 // σ 30 vs 27 device px
        #expect(row(r, .api).line.values.compactMap(\.value).map { ($0 * 10).rounded() / 10 } == [29.6, 27])   // discrete σ at k 3
    }

    @Test func partsWaysForTheCardsNeighbours() {   // SPEC §7.1 item 9
        let gauss = ANALYSIS_Fixtures.gaussian(12)   // at σ 4 a whole-width box misses σ by 5.6 % and parts at API
        let map = engine.partsWays(from: gauss, to: ["fixture-box", "fixture-heat", "fixture-median", "not-registered", "gaussian-blur"],
                                   homeToolID: "swiftui", displayScale: 3)
        #expect(map["fixture-box"]?.floor == .math)
        #expect(map["fixture-heat"]?.floor == .kernel)
        #expect(map["fixture-median"]?.floor == .math)
        #expect(map["not-registered"] == nil && map["gaussian-blur"] == nil)
        let line = engine.partsWaysLine(map, order: ["fixture-box", "fixture-heat", "fixture-median"])
        #expect(line.text == "Box blur (fixture) at MATH · Heat equation (fixture) at KERNEL · Median (fixture) at MATH")
        #expect(line.honestyViolations.isEmpty)
    }

    @Test func minimumResponseFromTheKernelsEachSlotRuns() {   // SPEC §8.3 Line-up status row
        let real = DivergenceEngine()
        let g4 = real.minimumResponse(ANALYSIS_Fixtures.gaussian(4))
        #expect(abs((g4.value ?? 0) + 0.0010006) < 2e-6)          // SPEC §5.3 A: minimum H −0.0010
        #expect(g4.text == "\u{2212}0.0010" && g4.provenance == .computed)
        #expect(real.minimumResponse(ANALYSIS_Fixtures.gaussian(12)).text == "\u{2212}0.0012")   // SPEC §7.1 card, k 3
        let box = engine.minimumResponse(ANALYSIS_Fixtures.configuration(ANALYSIS_Fixtures.box, sigma: 12))
        #expect(abs((box.value ?? 0) + 0.2177) < 5e-4)            // w 41: −0.218, the continuous sinc's −0.217 + discreteness
        let tent = engine.minimumResponse(ANALYSIS_Fixtures.configuration(ANALYSIS_Fixtures.tent, sigma: 12))
        #expect(tent.text == "0")                                 // sinc² ≥ 0: zeros, never inversion
        let median = engine.minimumResponse(ANALYSIS_Fixtures.configuration(ANALYSIS_Fixtures.median))
        #expect(median.value == nil && median.text == "N/A · RANK")
        let line = engine.minimumResponseLine([(.a, ANALYSIS_Fixtures.gaussian(12)),
                                               (.b, ANALYSIS_Fixtures.configuration(ANALYSIS_Fixtures.box, sigma: 12)),
                                               (.c, ANALYSIS_Fixtures.configuration(ANALYSIS_Fixtures.tent, sigma: 12)),
                                               (.d, ANALYSIS_Fixtures.configuration(ANALYSIS_Fixtures.median))])
        #expect(line.text == "MIN H A \u{2212}0.0012 · B \u{2212}0.218 · C 0 · D N/A · RANK")
        #expect(line.honestyViolations.isEmpty)
    }

    /// HONEST: every line the engine produces, over every pair of fixture and Gaussian configurations, three home tools,
    /// with and without pixel evidence, with the stub conventions and with the real `BlurServices.tools`.
    @Test func everyProducedLineIsHonest() {
        var configs = [ANALYSIS_Fixtures.gaussian(4), ANALYSIS_Fixtures.gaussian(12, variant: GaussianOperator.separable),
                       ANALYSIS_Fixtures.gaussian(4, variant: GaussianOperator.direct2D), ANALYSIS_Fixtures.gaussian(4, variant: GaussianOperator.computeTile),
                       ANALYSIS_Fixtures.gaussian(4, settings: SilentSettings(colourSpace: .srgbEncoded, alphaMode: .straight, accumulator: .fp16)),
                       ANALYSIS_Fixtures.configuration(ANALYSIS_Fixtures.median), ANALYSIS_Fixtures.configuration(ANALYSIS_Fixtures.zoom),
                       ANALYSIS_Fixtures.configuration(ANALYSIS_Fixtures.swiftUI)]
        configs += [ANALYSIS_Fixtures.box, ANALYSIS_Fixtures.tent, ANALYSIS_Fixtures.disc].map { ANALYSIS_Fixtures.configuration($0, sigma: 4) }
        let engines = [engine, ANALYSIS_Fixtures.engine(tools: nil)]
        var problems: [String] = [], checked = 0
        for e in engines {
            for a in configs { for b in configs { for home in ["swiftui", "css", "photoshop"] {
                for pixels in [nil, DivergenceEngine.PixelEvidence(stats: ANALYSIS_Fixtures.stats(maxAbs: 0.002, ulp: 4, lsb: 1))] {
                    let r = e.rows(a, b, homeToolID: home, displayScale: 3, pixels: pixels)
                    #expect(r.count == 7)
                    #expect(r.filter { $0.verdict == .partsWays }.count <= 1)
                    problems += ANALYSIS_Fixtures.violations(r)
                    for row in r where row.comparison.reason.isEmpty { problems.append("empty reason at \(row.floor)") }
                    checked += 1
                }
            } } }
            problems += e.minimumResponseLine(configs.enumerated().map { (RunSlot.allCases[$0.offset % 4], $0.element) }).honestyViolations
        }
        #expect(checked == 2 * 11 * 11 * 3 * 2)
        #expect(problems.isEmpty, "\(Array(Set(problems)).sorted().prefix(12))")
    }
}
