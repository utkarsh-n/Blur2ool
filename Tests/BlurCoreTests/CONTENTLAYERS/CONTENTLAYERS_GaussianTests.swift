import Foundation
import Testing
@testable import BlurCore

// OWNER: CONTENT-LAYERS. Acceptance (3): the Gaussian rail on Night City at σ 12 and the Kernel floor's MASS CUT; the
// SPEC §5.3 A and §4.3 fixtures each floor prints (to half a unit of the last printed digit, ARCHITECTURE §7 rule 8).

@Suite struct CONTENTLAYERS_GaussianFixtures {
    typealias F = CONTENTLAYERS_Fixtures
    static let builder = FloorPageBuilder(tools: CONTENTLAYERS_FakeTools())
    static var benchConfig: RenderConfiguration { F.configuration(F.gaussian) }      // Night City, σ 12, linear-sampled, probe (447, 455)

    func number(_ page: FloorPage?, _ id: String) -> BadgedValue? {
        page.flatMap { p in (p.numbers + p.details.flatMap { if case .values(let v) = $0 { return v }; return [] }).first { $0.id == id }?.value }
    }

    @Test func railOnNightCityAtSigma12() {
        let chips = Self.builder.railChips(for: F.gaussian, context: F.context(Self.benchConfig))
        let text = Dictionary(uniqueKeysWithValues: chips.map { ($0.floor, $0.value.text) })
        #expect(text[.slide] == "≈4.4")
        #expect(text[.api] == "12.0")
        #expect(text[.math] == "G")
        #expect(text[.kernel] == "73")
        #expect(text[.algorithm] == "2×")
        #expect(text[.gpu] == "–.––")
        let slide = chips[0].value
        #expect(slide.provenance == .inferred && ContentOffscreen.isMarked(slide))           // SwiftUI-derived: OFFSCREEN everywhere
        #expect(slide.spoken.hasPrefix("about 4.44 points") && slide.spoken.contains("sigma-matched"))
        #expect(chips[1].value.provenance == .computed && chips[3].value.provenance == .computed && chips[4].value.provenance == .computed)
        #expect(chips[5].value.provenance == .measured && chips[5].value.value == nil)
        #expect(chips.allSatisfy { $0.value.text.count <= 6 && $0.comparison == nil })
        #expect(ContentLint.violations(chips).isEmpty)
        // After timing: MEASURED with the device; PIXEL LIVE at three significant digits.
        let timed = Self.builder.railChips(for: F.gaussian, context: F.context(Self.benchConfig, live: F.richLive(F.gaussian, Self.benchConfig)))
        #expect(timed[5].value.text == "0.61" && timed[5].value.device == F.phone)
        #expect(timed[6].value.text == "0.0885" && timed[6].value.provenance == .live)
        // With SEMANTICS' conventions as they are in this mirror: the same chip, or UNVER. while SEMANTICS is a seed.
        let real = FloorPageBuilder().railChips(for: F.gaussian, context: F.context(Self.benchConfig))[0].value
        if real.value != nil { #expect(real.text == "≈4.4" && ContentOffscreen.isMarked(real)) } else { #expect(real.text == "UNVER." || real.text == "—") }
        print("CONTENTLAYERS SLIDE chip with BlurServices.tools in this mirror: '\(real.text)'")
    }

    @Test func compareRailShowsComparisons() {
        let b = F.configuration(F.gaussian, variant: GaussianOperator.separable)
        let chips = Self.builder.railChips(for: F.gaussian, context: F.context(Self.benchConfig, compareB: b))
        #expect(chips.allSatisfy { $0.comparison != nil })
        #expect(chips.compactMap(\.comparison).filter { $0.verdict == .partsWays }.count == 1)
        #expect(chips.compactMap(\.comparison).allSatisfy { ["=", "≈", "≠"].contains($0.verdict.railSymbol) })
    }

    @Test func kernelFloorAtSigma12() {
        let page = Self.builder.page(.kernel, for: F.gaussian, context: F.context(Self.benchConfig))
        let perAxis = number(page, "massCut"), twoD = number(page, "massCut2D"), continuous = number(page, "massCutContinuous")
        #expect(perAxis?.text == "0.235" && perAxis?.unit == "%" && perAxis?.provenance == .computed)
        #expect(abs((twoD?.value ?? 0) - 0.47) <= 0.005 && twoD?.unit == "%")
        #expect(continuous?.text == "0.270")
        #expect(number(page, "taps")?.text == "73")
        #expect(number(page, "centre")?.text == "0.03332")
        #expect(number(page, "sigma")?.text == "11.86")
        #expect(number(page, "minH")?.text == "\u{2212}0.0012" && number(page, "minH")?.caption == "H ≥ 0 (CONTINUOUS) · TRUNCATED: RIPPLE")
        // Linear-sampled: ERROR VS SAMPLED 1.1·10⁻⁴ per tap, MODELED for eight-bit round-to-nearest (M1 Max rule).
        let error = number(page, "errorVs")
        #expect(error?.text == "1.1·10⁻⁴" && error?.provenance == .modeled && error?.unit == "per tap")
        #expect(page.governingRule == "g[n] = exp(−n²/2σ²) / Σ,  |n| ≤ ⌈3σ⌉ = 36")
        #expect(page.inThisApp.contains("pair weights and offsets") && page.inThisApp.contains("MODELED"))
        #expect(page.numbers.count == 6 && ContentLint.violations(page).isEmpty)
        // Integer-tap variant: the exact-numbers line and the 2-D mass cut in the sixth slot.
        let separable = Self.builder.page(.kernel, for: F.gaussian, context: F.context(F.configuration(F.gaussian, variant: GaussianOperator.separable)))
        #expect(separable.inThisApp == "IN THIS APP · Weights come from BlurCore (Double) and are the exact numbers the GPU receives.")
        #expect(separable.numbers.last?.id == "massCut2D" && separable.numbers.last?.value.text == "0.469")
        // This phone's measured sub-texel rule replaces the Mac's.
        let probe = DeviceProbeResult(kind: .bilinearSubTexelBits, rows: [], numbers: ["subTexelBits": 6, "roundsToNearest": 0], device: F.phone)
        let measured = Self.builder.page(.kernel, for: F.gaussian, context: F.context(Self.benchConfig, live: LiveFacts(deviceProbes: [probe])))
        #expect(number(measured, "errorVs")?.caption?.hasPrefix("6-BIT TRUNCATE · MEASURED ON THIS PHONE") == true)
        #expect((number(measured, "errorVs")?.value ?? 0) > (error?.value ?? 1))
    }

    @Test func kernelFloorDescentA() {   // SPEC §5.3 A floor 4: σ 3.963, mass cut 0.173 % / 0.346 %, ripple −0.0010
        let page = Self.builder.page(.kernel, for: F.gaussian, context: F.context(F.descentAConfiguration))
        #expect(number(page, "massCut")?.text == "0.173")
        #expect(number(page, "massCut2D")?.text == "0.346")
        #expect(abs((number(page, "sigma")?.value ?? 0) - 3.963) < 0.0005)
        #expect(number(page, "minH")?.text == "\u{2212}0.0010")
        #expect(number(page, "taps")?.text == "25")
        // The pair table the GPU receives: offsets 1.4766 … and weights 0.18500 … (SPEC §5.3 A floor 6).
        let tables = page.details.compactMap { if case .table(let t) = $0 { return t }; return nil }
        let pairs = tables.first { $0.columns == ["PAIR", "OFFSET", "WEIGHT"] }
        #expect(pairs?.rows.count == 7 && pairs?.rows[1] == ["1", "1.4766", "0.18500"] && pairs?.rows[3] == ["3", "5.4149", "0.07818"])
        #expect(pairs?.provenance == .computed)
    }

    @Test func discretisationsAndTruncationsKeepTheMassCutHonest() {
        for d in ["sampled", "integrated", "lindeberg"] {
            for k in ["2", "2.5", "3", "4"] {
                let config = F.configuration(F.gaussian, parameters: F.parameters(F.gaussian, ["sigma": .double(6), "truncation": .choice(k), "discretisation": .choice(d)]))
                let page = Self.builder.page(.kernel, for: F.gaussian, context: F.context(config))
                let cut = number(page, "massCut")?.value ?? -1
                #expect(cut > 0 && cut < 5, "\(d) k \(k): \(cut)")
                #expect(ContentLint.violations(page).isEmpty)
            }
        }
    }

    @Test func mathFloorDescentA() {   // SPEC §5.3 A floor 3: FWHM 9.42, half amplitude 0.0469 c/px, 10–90 % edge 10.25 px
        let page = Self.builder.page(.math, for: F.gaussian, context: F.context(F.descentAConfiguration))
        #expect(number(page, "fwhm")?.text == "9.42")
        // SPEC prints 0.0469; the exact value √(ln 2/(2π²σ²)) = 0.046848 prints 0.0468 at four decimals (within 3·10⁻⁶ of
        // the SPEC's rounding boundary; recorded in the progress file).
        #expect(abs((number(page, "half")?.value ?? 0) - 0.046848) < 1e-6 && number(page, "half")?.text == "0.0468")
        #expect(number(page, "db3")?.text == "0.0331")
        #expect(abs((number(page, "edge")?.value ?? 0) - 10.25) <= 0.005)
        #expect(number(page, "zero")?.text == "NONE")
        #expect(page.governingRule == "G(x) = e^(−x²/2σ²) / (σ√(2π))   ·   H(ν) = e^(−2π²σ²ν²)")
        let chips = page.details.compactMap { if case .chips(let c) = $0 { return c }; return nil }.flatMap { $0 }
        #expect(chips.contains("H ≥ 0 (CONTINUOUS)") && chips.contains("TRUNCATED: RIPPLE") && chips.contains("SEPARABLE") && chips.contains("ISOTROPIC"))
        #expect(chips.contains("TRUE BLUR") && chips.contains("LSI"))
        #expect(number(page, "minH-run")?.text == "\u{2212}0.0010")
        if case .plot(let p)? = page.figure {
            #expect(p.showsZeroLine && p.series.map(\.role) == [.reference, .primary] && p.markers.contains { $0.kind == .minus3dB })
        } else { Issue.record("math figure") }
        #expect(page.details.contains { if case .disclosure(let t, _) = $0 { return t.hasPrefix("Why only the Gaussian") }; return false })
    }

    @Test func pixelsFloorDescentA() {   // SPEC §5.3 A floor 7: OUT 0.4500 → 179/255; sRGB-encoded branch 115/255
        let page = Self.builder.page(.pixels, for: F.gaussian, context: F.context(F.descentAConfiguration, content: F.stepEdges()))
        #expect(number(page, "in")?.text == "0" || number(page, "in")?.text == "0.000")
        #expect(number(page, "out")?.text == "0.450")
        #expect(number(page, "encoded")?.text == "179")
        #expect(number(page, "branch")?.text == "115" && number(page, "branch")?.provenance == .computed)
        #expect(number(page, "cpu")?.text == "0.450")
        #expect(number(page, "diff")?.text == "–.––")
        if case .pair(.texelGrid(let a), .texelGrid(let b))? = page.figure {
            #expect(a.size == 9 && b.size == 9 && a.highlighted == [F.descentAProbe])
            #expect(a.values[4] == 0 && a.values[5] == 1)         // the step between x = 446 and 447
        } else { Issue.record("pixels figure") }
        #expect(ContentLint.violations(page).isEmpty)
    }

    @Test func gpuFloorTabsFromLiveFacts() {   // SPEC §5.3 A floor 6: compute tile, probe thread 190 of (1, 300), SIMD 5 lane 30, 2,240 B
        let config = F.configuration(F.gaussian, variant: GaussianOperator.computeTile, parameters: F.descentAParameters, specimen: "step-edges",
                                     probe: F.descentAProbe)
        let source = "#include \"B2Shared.h\"\n// @explain: cooperative load of the apron\nfragment float4 b2_f2_gauss_tile_k() {\n  if (B2_TRACE_PROBE) { b2_trace_tap(); }\n}\n"
        let sha = ContentSHA256.hex(source)
        let shader = ShaderProvenance(combinedSHA256: sha, fileName: "F2Gaussian.metal", fileSHA256: sha, functionNames: ["b2_f2_gauss_tile_k"],
                                      mathMode: "fast", languageVersion: "4.1", traced: true)
        struct Sources: ContentShaderSourceProviding { let text: String; func source(fileName: String) -> String? { fileName == "F2Gaussian.metal" ? text : nil } }
        let builder = FloorPageBuilder(tools: CONTENTLAYERS_FakeTools(), shaderSources: Sources(text: source))
        let page = builder.page(.gpu, for: F.gaussian, context: F.context(config, live: F.richLive(F.gaussian, config, shader: shader)))
        #expect(page.tabs?.map(\.id) == ["silicon", "shader"])
        let silicon = page.tabs![0], shaderTab = page.tabs![1]
        if case .dispatchOverlay(let o)? = silicon.figure {
            #expect(o.probeThreadgroup == [1, 300] && o.probeThreadInGroup == [190, 0] && o.probeSIMDGroup == 5 && o.probeLane == 30)
        } else { Issue.record("dispatch overlay") }
        #expect(silicon.numbers.first { $0.id == "probeThread" }?.value.text == "(190, 0) · (1, 300)")
        #expect(silicon.numbers.first { $0.id == "tgMemory" }?.value.text == "2,240")
        #expect(silicon.numbers.first { $0.id == "gpuMs" }?.value.provenance == .measured)
        let bytes = silicon.numbers.first { $0.id == "bytes" }?.value
        #expect(bytes?.provenance == .modeled)
        let floorRow = silicon.details.compactMap { if case .values(let v) = $0 { return v }; return nil }.flatMap { $0 }.first { $0.id == "floor" }
        #expect(floorRow?.value.qualifiers.contains(.weakSource) == true && floorRow?.value.caption == "UNVERIFIED PEAK")
        if case .code(let code)? = shaderTab.figure {
            #expect(code.sha256 == sha && code.annotations[2] == "cooperative load of the apron" && code.highlightedLines.contains(4))
        } else { Issue.record("shader listing") }
        #expect(ContentLint.violations(page).isEmpty)
        // A mismatching SHA engraves SOURCE CHECK FAILED and shows no listing.
        var bad = shader; bad.fileSHA256 = String(repeating: "0", count: 64)
        let failed = builder.page(.gpu, for: F.gaussian, context: F.context(config, live: F.richLive(F.gaussian, config, shader: bad))).tabs![1]
        #expect(failed.figure == nil && failed.details.contains { if case .note(let s, _) = $0 { return s.hasPrefix("SOURCE CHECK FAILED") }; return false })
        // No Run yet: the Silicon tab still states loads, bytes and `–.––`.
        let cold = Self.builder.page(.gpu, for: F.gaussian, context: F.context(config))
        #expect(cold.tabs?[0].numbers.first { $0.id == "gpuMs" }?.value.text == "–.––")
    }

    @Test func algorithmAndApiFloors() {
        let algo = Self.builder.page(.algorithm, for: F.gaussian, context: F.context(Self.benchConfig, live: F.richLive(F.gaussian, Self.benchConfig)))
        #expect(number(algo, "passes")?.text == "2" && number(algo, "fetches")?.text == "74")
        #expect(number(algo, "alt-gaussian-2d-direct")?.text == "DISABLED" && number(algo, "alt-gaussian-2d-direct")?.value == nil)
        #expect(number(algo, "after-0")?.provenance == .live)
        if case .passTiles(let t)? = algo.figure { #expect(t.passes.map(\.name) == ["H", "V"] && t.timings.count == 2) } else { Issue.record("pass tiles") }
        let api = Self.builder.page(.api, for: F.gaussian, context: F.context(Self.benchConfig))
        #expect(number(api, "primary")?.text == "12.0" && number(api, "primary-pt")?.text == "4.00")
        #expect(api.governingRule == "sigma = 12.0 px = 4.00 pt × 3")
        if case .code(let c)? = api.figure { #expect(c.text.contains("b2ool.gaussianBlur(") && c.text.contains("CIFilter.gaussianBlur()")) } else { Issue.record("api code") }
        let slide = Self.builder.page(.slide, for: F.gaussian, context: F.context(Self.benchConfig))
        #expect(slide.numbers.first?.label == "YOU TYPE · SWIFTUI" && ContentOffscreen.isMarked(slide.numbers[0].value))
        #expect(slide.numbers[0].value.caption?.contains("SAME σ, DIFFERENT KERNEL") == true)
        #expect(slide.numbers.first { $0.id == "tool-photoshop" }?.value.text == "UNVERIFIED")
        #expect(slide.numbers.first { $0.id == "tool-css" }?.value.text == "4.00")
        if case .toolBars(let bars)? = slide.figure { #expect(bars.homeToolID == "swiftui" && bars.rows.first?.id == "tool-swiftui") } else { Issue.record("tool bars") }
    }

    @Test func sha256KnownAnswers() {
        #expect(ContentSHA256.hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(ContentSHA256.hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(ContentSHA256.hex(String(repeating: "a", count: 1000)) == "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
    }
}
