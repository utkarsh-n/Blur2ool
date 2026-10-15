import Foundation
import Testing
@testable import BlurCore

// OWNER: CONTENT-VIEWS. CORE acceptance (PLAN.md CONTENT-VIEWS item 2): the fixture FloorPages cover EVERY FigureSpec case
// and EVERY ContentBlock case, carry no placeholder words, show at most six numbers per page (and per tab), and have no
// honesty violations; their COMPUTED numbers reproduce SPEC §5.3 at the printed precision. The fixtures and the pure
// content logic are the App/Content files themselves, mirrored here (CONTENTVIEWS_MirrorDrift proves the copies equal).

private typealias Fixtures = CONTENTVIEWS_Fixtures
private typealias Logic = CONTENTVIEWS_ContentLogic

@Suite struct CONTENTVIEWS_FixtureCoverage {
    @Test func everyFigureKindIsCovered() {
        let kinds = Set(Fixtures.items.flatMap { Logic.figures(in: $0.page) }.map(Logic.figureKind))
        #expect(kinds == Logic.allFigureKinds, "missing figure kinds: \(Logic.allFigureKinds.subtracting(kinds).sorted())")
    }

    @Test func everyBlockKindIsCovered() {
        let kinds = Set(Fixtures.items.flatMap { Logic.blocks(in: $0.page) }.map(Logic.blockKind))
        #expect(kinds == Logic.allBlockKinds, "missing block kinds: \(Logic.allBlockKinds.subtracting(kinds).sorted())")
    }

    @Test func everyFloorHasAFixtureAndIdsAreUnique() {
        let ids = Fixtures.items.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(Set(Fixtures.items.map(\.page.floor)) == Set(Floor.allCases))
        for item in Fixtures.items {
            #expect(item.page.eyebrow == item.page.floor.eyebrow, "\(item.id)")
            #expect(item.page.question == item.page.floor.question, "\(item.id)")
            #expect(!item.page.dominantBadges.isEmpty, "\(item.id): dominant badges")
            #expect(Fixtures.item(item.id) == item)
        }
    }

    @Test func emptyStatesTabsPairsAndLogAxesAreExercised() {
        let pages = Fixtures.items.map(\.page)
        #expect(pages.contains { $0.emptyState != nil && $0.figure == nil }, "an honest empty state")
        #expect(pages.contains { ($0.tabs?.count ?? 0) >= 2 }, "floor 6 tabs")
        let plots = pages.flatMap(Logic.figures).compactMap { f -> PlotSpec? in if case .plot(let p) = f { p } else { nil } }
        #expect(plots.contains { $0.xAxis.logarithmic && $0.yAxis.logarithmic }, "a log-log plot")
        #expect(plots.contains { Logic.hasNegative($0) && $0.showsZeroLine }, "a signed plot with negative lobes")
        #expect(plots.contains { $0.series.contains { $0.style == .stems } }, "stems")
        #expect(plots.contains { $0.series.contains { $0.role == .comparisonB && $0.style == .dashed } }, "a compare B series")
        #expect(plots.contains { $0.markers.contains { $0.kind == .regimeSwitch && $0.provenance == .inferred } }, "a hollow INFERRED regime marker")
        let heatmaps = pages.flatMap(Logic.figures).compactMap { f -> HeatmapSpec? in if case .heatmap(let h) = f { h } else { nil } }
        #expect(heatmaps.contains { $0.signed && ($0.values.min() ?? 0) < 0 } && heatmaps.contains { !$0.signed })
        let tiles = pages.flatMap(Logic.figures).compactMap { f -> PassTilesSpec? in if case .passTiles(let t) = f { t } else { nil } }
        #expect(tiles.contains { $0.passes.count > 6 }, "a pass row that wraps")
    }
}

@Suite struct CONTENTVIEWS_FixtureHonesty {
    @Test func noHonestyViolations() {
        for item in Fixtures.items {
            for value in Logic.badgedValues(in: item.page) {
                #expect(value.honestyViolations.isEmpty, "\(item.id) \(value.text): \(value.honestyViolations)")
            }
            #expect(item.context.honestyViolations.isEmpty, "\(item.id) context: \(item.context.honestyViolations)")
        }
    }

    @Test func atMostSixNumbersPerPageAndTab() {
        for item in Fixtures.items {
            #expect(item.page.numbers.count <= 6, "\(item.id): \(item.page.numbers.count) numbers")
            for tab in item.page.tabs ?? [] { #expect(tab.numbers.count <= 6, "\(item.id) tab \(tab.id)") }
        }
    }

    @Test func noPlaceholderWords() {
        for item in Fixtures.items {
            for s in Logic.strings(in: item.page) {
                #expect(Logic.placeholderWords(in: s).isEmpty, "\(item.id): '\(s.prefix(60))'")
            }
        }
    }

    @Test func fixturesNeverClaimLiveAndMeasuredValuesNameTheirDevice() {
        for item in Fixtures.items {
            for value in Logic.badgedValues(in: item.page) {
                #expect(value.provenance != .live, "\(item.id) \(value.text): a CPU fixture value is never LIVE (SPEC §6.4 item 6)")
                if value.provenance == .measured, value.value != nil {
                    #expect(value.device != nil && value.qualifiers.contains(.notThisDevice), "\(item.id) \(value.text)")
                }
                if value.qualifiers.contains(.unverified) { #expect(value.value == nil && value.text == "UNVERIFIED") }
                #expect(!value.isInput, "\(item.id): page numbers are claims, not inputs")
            }
        }
    }

    @Test func proseCarriesNoBareDigits() {
        // Prose, questions and IN THIS APP lines carry no digits (numbers travel badged; SPEC §12.2 item 8). Equations, rules,
        // code, tables, chips and identifiers in notes are the allow-list.
        for item in Fixtures.items {
            var prose = [item.page.question, Logic.inThisAppSentence(item.page.inThisApp)]
            for b in Logic.blocks(in: item.page) { if case .paragraph(let p) = b { prose.append(p) } }
            for s in prose.map({ $0.replacingOccurrences(of: "Blur2ool", with: "the app") }) {
                let hasDigit = s.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) } || s.contains { $0.isNumber }
                #expect(!hasDigit, "\(item.id): '\(s.prefix(70))'")
            }
        }
    }

    @Test func inThisAppNamesWhatIsWhat() {
        for item in Fixtures.items {
            let s = item.page.inThisApp
            #expect(s.hasPrefix("IN THIS APP"), "\(item.id)")
            #expect(Provenance.allCases.contains { s.contains($0.word) }, "\(item.id): the line names at least one badge")
        }
    }
}

@Suite struct CONTENTVIEWS_FixtureMath {
    private func number(_ id: String, _ label: String) -> Double? {
        guard let page = Fixtures.item(id)?.page else { return nil }
        let rows = page.numbers + (page.tabs ?? []).flatMap(\.numbers)
        return rows.first { $0.id == label }?.value.value
    }

    @Test func gaussianDescentA() throws {
        // SPEC §5.3 A: OUT 0.4500 → 179/255; the sRGB-encoded branch 115/255; neighbours 0.353 … 0.810.
        #expect(abs(try #require(number("gaussian-pixels", "out")) - 0.4500) < 5e-5)
        #expect(try #require(number("gaussian-pixels", "encoded")) == 179)
        #expect(try #require(number("gaussian-pixels", "branch")) == 115)
        let expected = [0.353, 0.450, 0.550, 0.647, 0.735, 0.810]
        for (i, x) in (445...450).enumerated() { #expect(abs(Fixtures.outAfterH(x: x) - expected[i]) < 5e-4, "x \(x)") }
        #expect(abs(try #require(number("gaussian-kernel", "sigma")) - 3.963) < 5e-4)
        #expect(abs(try #require(number("gaussian-kernel", "cut")) - 0.173) < 5e-4)            // percent, per axis, discrete
        #expect(abs(try #require(number("gaussian-kernel", "centre")) - 0.09991) < 5e-6)
        #expect(abs(try #require(number("gaussian-kernel", "minH")) - (-0.0010)) < 5e-5)
        let error = try #require(number("gaussian-kernel", "error"))
        #expect(error > 0 && error < 1e-3, "modeled 8-bit fraction error \(error)")
        #expect(try #require(number("gaussian-algorithm", "fetches")) == 26)
        #expect(abs(try #require(number("gaussian-algorithm", "afterH")) - 0.4500) < 5e-5)
    }

    @Test func gaussianMath() throws {
        #expect(abs(try #require(number("gaussian-math", "peak")) - 0.0997) < 5e-5)
        #expect(abs(try #require(number("gaussian-math", "fwhm")) - 9.42) < 5e-3)
        // 0.046848 c/px: SPEC §5.3 A prints 0.0469 (a double rounding of 0.04685); at four decimals it is 0.0468.
        #expect(abs(try #require(number("gaussian-math", "half")) - 0.046848) < 1e-6)
        #expect(abs(try #require(number("gaussian-math", "edge")) - 10.25) < 5e-3)
        #expect(abs(try #require(number("gaussian-math", "minH")) - (-0.0010)) < 5e-5)
    }

    @Test func boxInvertsStripes() throws {
        // An 11-tap box reaches −0.2234 at 0.130 c/px; the catalog's −0.217 is the continuous box's limit.
        #expect(abs(try #require(number("box-math", "min")) - (-0.2234)) < 5e-4)
        #expect(abs(try #require(number("box-math", "at")) - 0.13) < 1e-9)
        #expect(abs(try #require(number("box-math", "zero")) - 1.0 / 11) < 1e-12)
        #expect(abs(try #require(number("box-math", "sigma")) - 10.0.squareRoot()) < 1e-9)
    }

    @Test func zoomDescentB() throws {
        // SPEC §5.3 B: streak a·r = 30 px, σ along the ray 8.66 px, spacing 0.969 px, ghost-free N 65, corner spacing 2.04 px.
        #expect(abs(try #require(number("zoom-kernel", "streak")) - 30.0) < 0.05)
        #expect(abs(try #require(number("zoom-kernel", "sigma")) - 8.66) < 0.01)
        #expect(abs(try #require(number("zoom-kernel", "spacing")) - 0.969) < 5e-4)
        #expect(try #require(number("zoom-kernel", "ghost")) == 65)
        #expect(abs(try #require(number("zoom-kernel", "corner")) - 2.04) < 5e-3)
        // The centre spot of the 7 × 7 field is (447, 447): all 32 taps land on its own pixel centre.
        guard case .psfField(let field) = Fixtures.item("zoom-kernel")?.page.figure else { Issue.record("no PSF field"); return }
        let centre = field.kernels[24]
        #expect(field.points[24] == PixelPoint(x: 447, y: 447))
        #expect(abs(centre.weights.reduce(0, +) - 1) < 1e-12)
        #expect(abs(centre[centre.originX, centre.originY] - 1) < 1e-12)
        // A corner spot is a streak along the diagonal ray.
        let m = Logic.moments(field.kernels[0])
        #expect(m.sigmaMajor > 10 * m.sigmaMinor && abs(abs(m.angleDegrees) - 45) < 1)
    }

    @Test func zoomDispatch() throws {
        guard case .dispatchOverlay(let spec) = Fixtures.item("zoom-gpu")?.page.figure else { Issue.record("no overlay"); return }
        let layout = try #require(Logic.dispatchLayout(spec))
        #expect(layout.totalGroups == 3_136 && layout.surplus == SIMD2(2, 2))
        #expect(layout.probe == SIMD2(747, 460))
        let index = Logic.probeLinearIndex(spec)
        #expect(index / 32 == spec.probeSIMDGroup && index % 32 == spec.probeLane)
    }

    @Test func computeTileDispatch() throws {
        guard case .dispatchOverlay(let spec)? = Fixtures.item("gaussian-gpu")?.page.tabs?.first(where: { $0.id == "silicon" })?.figure else {
            Issue.record("no silicon overlay"); return
        }
        let layout = try #require(Logic.dispatchLayout(spec))
        #expect(layout.probe == SIMD2(446, 300) && layout.groups == SIMD2(4, 894))
        #expect(layout.apronOrigin == SIMD2(256 - 12, 300) && layout.apronSize == SIMD2(256 + 24, 1))
        #expect(spec.dispatch.dynamicThreadgroupMemoryBytes == 2_240)
        let index = Logic.probeLinearIndex(spec)
        #expect(index == 190 && index / 32 == 5 && index % 32 == 30)
    }

    @Test func hexagonAndDisc() throws {
        #expect(abs(try #require(number("hexagon-math", "area")) - 166.3) < 0.05)
        #expect(abs(try #require(number("hexagon-math", "sigma")) - 3.65) < 5e-3)
        #expect(try #require(number("hexagon-math", "min")) < -0.05)
        guard case .heatmap(let map) = Fixtures.item("hexagon-math")?.page.figure else { Issue.record("no map"); return }
        #expect(abs(map.values[map.width * (map.height / 2) + map.width / 2] - 1) < 1e-12, "H(0, 0) = 1")
        for j in 0..<map.height { for i in 0..<map.width {          // a centrally symmetric kernel has a symmetric response
            #expect(abs(map.values[j * map.width + i] - map.values[(map.height - 1 - j) * map.width + (map.width - 1 - i)]) < 1e-9)
        } }
        let disc = Fixtures.discKernel(radius: 6)
        #expect(abs(disc.sum - 1) < 1e-12)
        #expect(abs(try #require(number("disc-kernel", "centre")) - 1 / (Double.pi * 36)) < 2e-5)
        #expect(abs(try #require(number("dual-kawase-algorithm", "fetches")) - 12.3) < 0.05)
    }
}

@Suite struct CONTENTVIEWS_LogicTests {
    @Test func signedRunsMeetOnTheZeroLine() {
        let runs = Logic.signedRuns(xs: [0, 1, 2, 3, 4], ys: [1, 0.5, -0.5, -1, 0.25])
        #expect(runs.map(\.negative) == [false, true, false])
        #expect(runs[0].xs.last == 1.5 && runs[0].ys.last == 0)
        #expect(runs[1].xs.first == 1.5 && runs[1].ys.first == 0)
        #expect(abs((runs[1].xs.last ?? 0) - 3.8) < 1e-12 && runs[2].xs.first == runs[1].xs.last)
        #expect(Logic.signedRuns(xs: [0, 1, 2], ys: [0, 0, 0]).count == 1)
        let viaZero = Logic.signedRuns(xs: [0, 1, 2], ys: [1, 0, -1])
        #expect(viaZero.map(\.negative) == [false, true] && viaZero[1].xs.first == 1)
    }

    @Test func ticksAndTickStyles() {
        #expect(Logic.niceTicks(0...0.5, count: 5) == [0, 0.1, 0.2, 0.3, 0.4, 0.5])
        #expect(Logic.niceTicks(-13...13, count: 4) == [-10, -5, 0, 5, 10])
        #expect(Logic.logTicks(1...1e5) == [1, 10, 100, 1_000, 10_000, 100_000])
        #expect(Logic.logTicks(0.8...80) == [1, 2, 5, 10, 20, 50])
        #expect(Logic.niceTicks(1...1e5, count: 4) == [20_000, 40_000, 60_000, 80_000, 100_000])
        #expect(Logic.tickStyle([0, 0.1, 0.2]).text(0.1) == "0.1")
        #expect(Logic.tickStyle([0, 0.025, 0.05]).text(0.025) == "0.025")
        #expect(Logic.tickStyle([-10, -5, 0, 5]).text(-10) == "\u{2212}10")
        #expect(Logic.tickStyle([1, 10, 100_000]).text(100_000) == "100,000")
        let log = Logic.tickStyle([0.5, 1, 2, 5, 10, 20], logarithmic: true)
        #expect([0.5, 1, 20, 100_000].map(log.text) == ["0.5", "1", "20", "100,000"])
        #expect(Logic.axisTitle(PlotAxis(label: "H(ν)", normalized: true)) == "H(ν) · normalized")
        #expect(Logic.spokenAxisTitle(PlotAxis(label: "offset", unit: "px")) == "offset in px")
    }

    @Test func stemWidths() {
        #expect(Logic.stemWidth(count: 25, plotWidth: 374) == 2)
        #expect(Logic.stemWidth(count: 400, plotWidth: 374) == 0.75)
        let mid = Logic.stemWidth(count: 200, plotWidth: 374)
        #expect(mid > 0.75 && mid < 2)
    }

    @Test func contourOfACircle() {
        let n = 21
        var field = [Double](repeating: 0, count: n * n)
        for j in 0..<n { for i in 0..<n { field[j * n + i] = (pow(Double(i) - 10, 2) + pow(Double(j) - 10, 2)).squareRoot() } }
        let segments = Logic.contour(field, width: n, height: n, level: 6)
        #expect(segments.count > 20)
        for s in segments {
            for p in [s.a, s.b] {
                let r = ((p.x - 10.5) * (p.x - 10.5) + (p.y - 10.5) * (p.y - 10.5)).squareRoot()
                #expect(abs(r - 6) < 0.15, "\(p) r \(r)")
            }
        }
        #expect(Logic.contour([1, 1, 1, 1], width: 2, height: 2, level: 0).isEmpty)
    }

    @Test func rampsNeverRelyOnColourAlone() {
        #expect(Logic.rampPosition(0, limit: 1, signed: true) == 0)
        #expect(Logic.rampPosition(1, limit: 1, signed: true) == 1 && Logic.rampPosition(-1, limit: 1, signed: true) == -1)
        #expect(Logic.rampPosition(-0.25, limit: 1, signed: true) == -0.5)          // square-root mapped
        #expect(Logic.rampPosition(-0.25, limit: 1, signed: false) == 0 && Logic.rampPosition(4, limit: 1, signed: false) == 1)
        #expect(Logic.hatchSpacing(cellSize: 1) == 3 && Logic.hatchSpacing(cellSize: 100) == 6)
        #expect(abs(Logic.displayGrey(linear: 0.45005) - 0.7015) < 1e-3 && Logic.displayGrey(linear: 4) == 1)
    }

    @Test func momentsOfAnisotropicKernels() {
        func gaussian(sx: Double, sy: Double, angle: Double) -> Kernel2D {
            let h = 15, c = cos(angle * .pi / 180), s = sin(angle * .pi / 180)
            var w = [Double]()
            for y in -h...h { for x in -h...h {
                let u = Double(x) * c + Double(y) * s, v = -Double(x) * s + Double(y) * c
                w.append(exp(-u * u / (2 * sx * sx) - v * v / (2 * sy * sy)))
            } }
            return Kernel2D(width: 2 * h + 1, height: 2 * h + 1, originX: h, originY: h, weights: w)
        }
        let a = Logic.moments(gaussian(sx: 4, sy: 1.5, angle: 0))
        #expect(abs(a.sigmaMajor - 4) < 0.01 && abs(a.sigmaMinor - 1.5) < 0.01 && abs(a.angleDegrees) < 0.01)
        let b = Logic.moments(gaussian(sx: 4, sy: 1.5, angle: 45))
        #expect(abs(b.angleDegrees - 45) < 0.5 && abs(b.sigmaMajor - 4) < 0.05)
        let c = Logic.moments(gaussian(sx: 1.5, sy: 4, angle: 0))
        #expect(abs(c.angleDegrees - 90) < 0.01)
    }

    @Test func shaderTokensAnnotationsAndTraceLines() {
        let tokens = Logic.tokenize("    float4 sum = fma(a, float4(w[1]), sum);  // @explain: explicit fma", language: "metal")
        #expect(tokens.contains { $0.kind == .type && $0.text == "float4" })
        #expect(tokens.contains { $0.kind == .function && $0.text == "fma" })
        #expect(tokens.contains { $0.kind == .number && $0.text == "1" })
        #expect(tokens.last?.kind == .explain)
        #expect(tokens.map(\.text).joined() == "    float4 sum = fma(a, float4(w[1]), sum);  // @explain: explicit fma")
        let attr = Logic.tokenize("texture2d<float, access::sample> src [[texture(B2_TEX_SRC)]],", language: "metal")
        #expect(attr.contains { $0.kind == .attribute && $0.text == "[[texture(B2_TEX_SRC)]]" })
        #expect(Logic.tokenize("#include \"B2Shared.h\"", language: "metal").first?.kind == .preprocessor)
        #expect(Logic.tokenize("    return 0.5f;", language: "metal").contains { $0.kind == .number && $0.text == "0.5f" })
        #expect(Logic.tokenize("let x = 1.33 // note", language: "swift").last?.kind == .comment)

        let code = CodeBlock(language: "metal", text: "a;\nb; // @explain: two\nif (B2_TRACE_PROBE) t();\nc;", highlightedLines: [4],
                             annotations: [1: "one", 2: "override"])
        #expect(Logic.explanations(code) == [1: "one", 2: "override"])
        #expect(Logic.traceLines(code) == [3, 4])
        #expect(Logic.codeWithoutExplain("b; // @explain: two") == "b;")
        #expect(Logic.codeWithoutExplain("b; // plain") == "b; // plain")
        let long = CodeBlock(language: "metal", text: (1...40).map { $0 == 30 ? "x; // @explain: here" : "line" }.joined(separator: "\n"))
        let window = Logic.excerptWindow(long, count: 12)
        #expect(window.count == 12 && window.contains(29))
    }

    @Test func plotDataTables() {
        let plot = PlotSpec(xAxis: PlotAxis(label: "offset", unit: "px"), yAxis: PlotAxis(label: "weight"),
                            series: [PlotSeries(name: "taps", xs: [-1, 0, 1], ys: [0.25, 0.5, 0.25], style: .stems, role: .primary, provenance: .computed),
                                     PlotSeries(name: "curve", xs: [-1, 0, 1], ys: [0.2, 0.6, 0.2], style: .solid, role: .reference, provenance: .computed),
                                     PlotSeries(name: "other", xs: [5], ys: [0.001], style: .points, role: .measured, provenance: .measured)],
                            accessibilitySummary: "three taps")
        let t = Logic.dataTable(plot)
        #expect(t.columns == ["OFFSET · PX", "TAPS · COMPUTED", "CURVE · COMPUTED", "OTHER · MEASURED"])
        #expect(t.rows.count == 4)
        #expect(t.rows[0] == ["\u{2212}1", "0.2500", "0.2000", ""])
        #expect(t.rows[3][0] == "5" && t.rows[3][3] == "0.001000")
        #expect(t.spokenRows[0].contains("minus 1 px") && t.spokenRows[0].contains("computed"))
        #expect(Logic.valueStyle([0.09991, 0.00111], unit: nil).text(0.00111) == "0.00111")
        #expect(Logic.valueStyle([12, 625], unit: nil).text(625) == "625")
    }

    @Test func pageText() {
        #expect(Logic.inThisAppSentence("IN THIS APP  Weights come from BlurCore.") == "Weights come from BlurCore.")
        #expect(Logic.inThisAppSentence("Weights come from BlurCore.") == "Weights come from BlurCore.")
        #expect(Logic.detailsTitle(.kernel, tabTitle: nil) == "All kernel details")
        #expect(Logic.detailsTitle(.gpu, tabTitle: nil) == "All GPU details")
        #expect(Logic.detailsTitle(.gpu, tabTitle: "Silicon") == "All silicon details")
        #expect(Logic.detailsTitle(.pixels, tabTitle: nil) == "All pixel details")
        #expect(Logic.placeholderWords(in: "TODO: later") == ["todo"])
        #expect(Logic.placeholderWords(in: "Lorem ipsum, TBD").sorted() == ["lorem", "tbd"])
        #expect(Logic.placeholderWords(in: "Photoshop Gaussian radius is unverified").isEmpty)
    }
}

/// The two mirrored files must equal their App/Content sources (namespace renamed), so the Mac tests test what ships.
@Suite struct CONTENTVIEWS_MirrorDrift {
    private func region(_ text: String) -> String? {
        guard let a = text.range(of: "// BEGIN MIRRORED"), let b = text.range(of: "// END MIRRORED") else { return nil }
        return String(text[a.lowerBound..<b.upperBound])
    }
    private func renamed(_ s: String) -> String {
        s.replacingOccurrences(of: "CONTENTVIEWS_ContentLogic", with: "ContentLogic")
            .replacingOccurrences(of: "CONTENTVIEWS_Fixtures", with: "ContentFixtures")
    }

    @Test(arguments: [("ContentLogic.swift", "CONTENTVIEWS_ContentLogic.swift"), ("ContentFixtures.swift", "CONTENTVIEWS_Fixtures.swift")])
    func mirrorEqualsTheAppFile(app: String, mirror: String) throws {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repo = here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let appText = try String(contentsOf: repo.appendingPathComponent("App/Content/\(app)"), encoding: .utf8)
        let mirrorText = try String(contentsOf: here.appendingPathComponent(mirror), encoding: .utf8)
        let a = try #require(region(appText)), m = try #require(region(mirrorText))
        #expect(a == renamed(m), "Tests/BlurCoreTests/CONTENTVIEWS/\(mirror) drifted from App/Content/\(app): regenerate the mirror")
    }
}
