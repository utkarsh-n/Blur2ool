import Foundation
import Testing
@testable import BlurCore

// OWNER: CONTENT-LAYERS. Acceptance (1) and (5): every entry registered in this mirror × 7 floors builds a page with ≤ 6
// numbers, the eyebrow and question from Floor, and passes HONEST including the digits-in-plain-text lint; the same for
// fake operators of every template class no family has registered yet; rail chips and pills per class.

@Suite struct CONTENTLAYERS_FloorRules {
    typealias F = CONTENTLAYERS_Fixtures
    static let builder = FloorPageBuilder(tools: CONTENTLAYERS_FakeTools())

    /// Contexts for one operator: nothing live, a full timed Run, the current image, a preview Run, and Compare.
    static func contexts(_ op: any BlurOperator, window: Int, probe: PixelPoint, content: OperatorContent?) -> [(String, FloorContext)] {
        let config = F.configuration(op, probe: probe, window: window)
        let shader = ShaderProvenance(combinedSHA256: String(repeating: "ab", count: 32), fileName: "F2Gaussian.metal",
                                      fileSHA256: String(repeating: "cd", count: 32), functionNames: ["b2_f2_gauss_linear_fs"], mathMode: "fast",
                                      languageVersion: "4.1", traced: false)
        var preview = F.richLive(op, config)
        preview.run = F.run(op, config, quality: .half)
        return [("empty", F.context(config)),
                ("timed", F.context(config, live: F.richLive(op, config, shader: shader), content: content)),
                ("content", F.context(config, content: content)),
                ("preview", F.context(config, live: preview)),
                ("css home", F.context(config, home: "css", content: content)),
                ("compare", F.context(config, compareB: F.configuration(F.gaussian, window: window)))]
    }

    static func check(_ op: any BlurOperator, window: Int, probe: PixelPoint, content: OperatorContent?, builder: FloorPageBuilder = builder) {
        for (name, ctx) in contexts(op, window: window, probe: probe, content: content) {
            let pages = builder.pages(for: op, context: ctx)
            #expect(pages.map(\.floor) == Floor.allCases, "\(op.entry.id) \(name)")
            for page in pages {
                #expect(page.numbers.count <= 6, "\(op.entry.id) \(name) \(page.eyebrow)")
                #expect(page.eyebrow == page.floor.eyebrow && page.question == page.floor.question)
                #expect(page.signature == op.entry.signature)
                let problems = ContentLint.violations(page)
                #expect(problems.isEmpty, "\(op.entry.id) [\(name)] \(problems)")
                #expect(page.inThisApp.hasPrefix("IN THIS APP · "))
            }
            let chips = builder.railChips(for: op, context: ctx)
            let chipProblems = ContentLint.violations(chips)
            #expect(chipProblems.isEmpty, "\(op.entry.id) [\(name)] rail \(chipProblems)")
            let pills = builder.pills(for: op, context: ctx)
            let pillProblems = ContentLint.violations(pills)
            #expect(pillProblems.isEmpty, "\(op.entry.id) [\(name)] pills \(pillProblems)")
        }
    }

    @Test func everyRegisteredEntryOnEveryFloor() {
        #expect(!BlurRegistry.operators.isEmpty)
        let content = F.nightCity()
        for op in BlurRegistry.operators {
            Self.check(op, window: 894, probe: PixelPoint(x: 447, y: 455), content: content)
            // With the real service locator too (SEMANTICS' conventions as they are in this mirror).
            Self.check(op, window: 894, probe: PixelPoint(x: 447, y: 455), content: nil, builder: FloorPageBuilder())
        }
        print("CONTENTLAYERS registered entries checked: \(BlurRegistry.operators.map(\.entry.id.rawValue).joined(separator: ", "))")
    }

    @Test func everyVariantOfEveryRegisteredEntry() {
        for op in BlurRegistry.operators {
            for variant in op.entry.variants {
                for sigma in [0.5, 4.0, 12.0] {
                    let params = op.holdingSigma(sigma, current: op.entry.defaultParameters).parameters
                    let config = F.configuration(op, variant: variant.id, parameters: params)
                    for page in Self.builder.pages(for: op, context: F.context(config)) {
                        #expect(ContentLint.violations(page).isEmpty, "\(variant.id) σ \(sigma) \(page.eyebrow) \(ContentLint.violations(page))")
                    }
                }
            }
        }
    }

    @Test func everyTemplateClassWithFakeOperators() {
        let content = F.smallImage()
        for kind in CONTENTLAYERS_Kind.allCases {
            Self.check(CONTENTLAYERS_FakeOperator(kind: kind), window: 128, probe: PixelPoint(x: 70, y: 60), content: content)
        }
    }

    @Test func classTemplatesShowWhatSPEC52Says() {
        let content = F.smallImage()
        func pages(_ kind: CONTENTLAYERS_Kind, content: OperatorContent? = content) -> [Floor: FloorPage] {
            let op = CONTENTLAYERS_FakeOperator(kind: kind)
            let ctx = F.context(F.configuration(op, probe: PixelPoint(x: 70, y: 60), window: 128), content: content)
            return Dictionary(uniqueKeysWithValues: Self.builder.pages(for: op, context: ctx).map { ($0.floor, $0) })
        }
        // Rank: no response; a sorted window on the Kernel floor.
        let rank = pages(.rank)
        #expect(rank[.math]?.emptyState == "N/A · RANK")
        if case .plot(let p)? = rank[.kernel]?.figure { #expect(p.series.first?.style == .points) } else { Issue.record("rank kernel figure") }
        // Adaptive: T(ν, A) and a LIVE · CPU weight map; without the image an honest empty state.
        let adaptive = pages(.adaptive)
        if case .plot(let p)? = adaptive[.math]?.figure { #expect(p.series.count == 4) } else { Issue.record("adaptive math figure") }
        if case .heatmap(let h)? = adaptive[.kernel]?.figure { #expect(h.provenance == .live) } else { Issue.record("adaptive weight map") }
        #expect(adaptive[.kernel]?.numbers.first { $0.id == "effective" }?.value.qualifiers.contains(.cpu) == true)
        #expect(pages(.adaptive, content: nil)[.kernel]?.emptyState == "LIVE WEIGHT MAP · NEEDS THE CURRENT IMAGE")
        // Space-variant: local PSF heat map, the global-H note, a 7 × 7 PSF field.
        let lsv = pages(.spaceVariant)
        if case .psfField(let f)? = lsv[.kernel]?.figure { #expect(f.gridSize == 7 && f.kernels.count == 49) } else { Issue.record("PSF field") }
        #expect(lsv[.math]?.details.contains { if case .note(let s, _) = $0 { return s.hasPrefix("NO SINGLE RESPONSE · SPACE-VARIANT") }; return false } == true)
        // Non-separable LSI: the signed 2-D H heat map is the MATH figure.
        if case .heatmap(let h)? = pages(.gather2D)[.math]?.figure { #expect(h.signed && h.width == 33) } else { Issue.record("2-D H heat map") }
        // FFT: no pixel footprint on the Kernel floor.
        #expect(pages(.globalFFT)[.kernel]?.emptyState == "NO PIXEL FOOTPRINT · GLOBAL (FFT)")
        // Tier S: the INFERRED lane on floors 5 and 6; Tier 3: CPU only.
        let system = pages(.system)
        #expect(system[.algorithm]?.emptyState == "SYSTEM INTERNALS · INFERRED" && system[.gpu]?.emptyState == "SYSTEM INTERNALS · INFERRED")
        #expect(system[.gpu]?.dominantBadges.contains(.inferred) == true || system[.gpu]?.numbers.isEmpty == false)
        let atlas = pages(.atlas)
        #expect(atlas[.algorithm]?.emptyState == "CPU ONLY IN THIS APP · TIER 3" && atlas[.gpu]?.emptyState == "CPU ONLY IN THIS APP · TIER 3")
        // Contrast entries: the failed test.
        #expect(pages(.derived)[.math]?.details.contains { if case .paragraph(let s) = $0 { return s.hasPrefix("Fails") }; return false } == true)
        // Sparse chains: ALGO counts levels.
        let sparse = CONTENTLAYERS_FakeOperator(kind: .sparse)
        let algo = Self.builder.railChips(for: sparse, context: F.context(F.configuration(sparse, window: 128))).first { $0.floor == .algorithm }
        #expect(algo?.value.text == "L2")
    }

    @Test func pillsPerClass() {
        let content = F.smallImage()
        func pills(_ kind: CONTENTLAYERS_Kind, content: OperatorContent? = content) -> PillContent {
            let op = CONTENTLAYERS_FakeOperator(kind: kind)
            return Self.builder.pills(for: op, context: F.context(F.configuration(op, probe: PixelPoint(x: 70, y: 60), window: 128), content: content))
        }
        let rank = pills(.rank)
        #expect(rank.freq.emptyText == "N/A · RANK" && rank.freq.plot == nil)
        #expect(rank.kernel.title == "SORTED WINDOW" && rank.kernel.plot != nil)
        let adaptive = pills(.adaptive)
        #expect(adaptive.kernel.title == "LOCAL @ PROBE" && adaptive.kernel.badge?.provenance == .live)
        #expect(adaptive.freq.title.hasPrefix("T(ν, A ") && adaptive.freq.badge?.provenance == .live)
        #expect(pills(.adaptive, content: nil).freq.title == "T(ν, A 0.20)")
        let lsv = pills(.spaceVariant)
        #expect(lsv.kernel.title == "LOCAL @ PROBE" && lsv.freq.title == "LOCAL @ PROBE" && lsv.kernel.badge?.provenance == .computed)
        let system = pills(.system)
        #expect(system.freq.emptyText == "INFERRED — NOT EXPOSED" && system.freq.badge?.provenance == .inferred)
        #expect(system.kernel.plot?.series.first?.style == .dashed && system.kernel.plot?.series.first?.provenance == .modeled)
        #expect(pills(.globalFFT).kernel.emptyText == "NO PIXEL FOOTPRINT · GLOBAL (FFT)")
        let sparse = pills(.sparse)
        #expect(sparse.kernel.plot?.series.last?.role == .depth)
        // LSI Gaussian: COMPUTED pills, −3 dB tick, signed H with the ripple stated.
        let g = F.gaussian
        let gp = Self.builder.pills(for: g, context: F.context(F.configuration(g)))
        #expect(gp.kernel.title == "KERNEL" && gp.freq.title == "FREQ")
        #expect(gp.freq.plot?.showsZeroLine == true && gp.freq.plot?.markers.map(\.kind) == [.minus3dB])
        #expect(gp.freq.badge?.caption == "H ≥ 0 (CONTINUOUS) · TRUNCATED: RIPPLE" && (gp.freq.badge?.value ?? 0) < 0)
        // Compare: B dashed in both pills.
        let compare = Self.builder.pills(for: g, context: F.context(F.configuration(g), compareB: F.configuration(CONTENTLAYERS_FakeOperator(kind: .gather2D), window: 894)))
        #expect(gp.kernel.plot?.series.contains { $0.role == .comparisonB } == false)
        _ = compare
        let compareSame = Self.builder.pills(for: g, context: F.context(F.configuration(g), compareB: F.configuration(g, variant: GaussianOperator.separable)))
        #expect(compareSame.kernel.plot?.series.contains { $0.role == .comparisonB && $0.style == .dashed } == true)
        #expect(compareSame.freq.plot?.series.contains { $0.role == .comparisonB && $0.style == .dashed } == true)
    }

    @Test func mergeKeepsSixAndMovesTheRestToDetails() {
        let rows = (0..<9).map { LabeledValue(id: "r\($0)", label: "ROW", value: .number(Double($0), .integer(), .computed)) }
        let draft = ContentFloorDraft(numbers: Array(rows.prefix(4)), inThisApp: "IN THIS APP · test.")
        let page = FloorPageBuilder.merge(floor: .kernel, draft: draft, facts: FloorFacts(numbers: Array(rows.suffix(5))), entry: F.gaussian.entry)
        #expect(page.numbers.count == 6)
        #expect(page.numbers.first?.id == "r4")                 // the operator's facts come first
        if case .values(let overflow)? = page.details.first { #expect(overflow.count == 3) } else { Issue.record("overflow not in details") }
        let empty = FloorPageBuilder.merge(floor: .math, draft: ContentFloorDraft(inThisApp: "IN THIS APP · test."), facts: .empty,
                                           entry: CONTENTLAYERS_FakeOperator(kind: .rank).entry)
        #expect(empty.emptyState == "N/A · NONLINEAR")
        let op = FloorPageBuilder.merge(floor: .math, draft: draft, facts: FloorFacts(emptyReason: "N/A · TEST"), entry: F.gaussian.entry)
        #expect(op.emptyState == "N/A · TEST" && op.numbers.isEmpty)
    }
}
