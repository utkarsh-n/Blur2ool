import Foundation
import Testing
@testable import BlurCore

// OWNER: CONTENT-LAYERS. Acceptance (4) lessons resolve to registered ids (missing ones listed and skipped for INTEGRATE),
// the lesson numbers BlurCore computes, `.offscreen` on every SwiftUI-derived value, the field guide, status lines and
// the lint itself (it must catch what it is meant to catch).

@Suite struct CONTENTLAYERS_Lessons {
    typealias F = CONTENTLAYERS_Fixtures

    @Test func libraryShape() {
        let all = LessonLibrary.all
        #expect(all.count == 34)
        #expect(Set(all.map(\.id)).count == 34)
        #expect(all.filter { $0.kind == .guidedDescent }.map(\.id) == ["descent-A", "descent-B", "descent-C", "descent-D"])
        #expect(all.filter { $0.kind == .pair }.map(\.id) == (1...30).map { "P\($0)" })
        #expect(BlurServices.lessons.count == 34)
        for lesson in all {
            #expect(!lesson.configurations.isEmpty && !lesson.lookFor.isEmpty, "\(lesson.id)")
            #expect(lesson.kind == .guidedDescent ? lesson.configurations.count == 1 : lesson.configurations.count >= 2, "\(lesson.id)")
            #expect(Set(lesson.configurations.map(\.specimen)).count == 1 && Set(lesson.configurations.map(\.probe)).count == 1, "\(lesson.id)")
            if lesson.view == .lineUp { #expect((3...4).contains(lesson.configurations.count), "\(lesson.id) line-up") }
            let problems = ContentLint.violations(lesson)
            #expect(problems.isEmpty, "\(lesson.id): \(problems)")
        }
        // Line-up lessons are exactly the catalog's triads and tetrads (SPEC §8.3).
        #expect(Set(all.filter { $0.view == .lineUp }.map(\.id)) == ["P2", "P3", "P7", "P11", "P14", "P25", "P29", "P30"])
    }

    @Test func everyLessonResolvesOrListsWhatIsMissing() {
        var missingReport: [String] = []
        for lesson in LessonLibrary.all {
            let missing = LessonLibrary.unresolved(lesson)
            if !missing.isEmpty { missingReport.append("\(lesson.id): \(missing.joined(separator: ", "))"); continue }
            for c in lesson.configurations {
                let op = BlurRegistry.op(c.blur)
                #expect(op != nil, "\(lesson.id) \(c.blur)")
                #expect(op?.entry.variant(c.variant) != nil, "\(lesson.id) \(c.variant)")
                #expect(SpecimenRegistry.generator(c.specimen) != nil)
            }
        }
        print("CONTENTLAYERS lessons not yet resolvable in this mirror (for INTEGRATE to re-check):\n  " + missingReport.joined(separator: "\n  "))
        // Registered entries are resolved with σ-hold: descent A runs the Gaussian at σ 4, linear-sampled, on step edges.
        let a = LessonLibrary.all[0].configurations[0]
        #expect(a.blur == "gaussian-blur" && a.variant == GaussianOperator.linearSampled && a.parameters.double("sigma") == 4)
        #expect(a.specimen == "step-edges" && a.probe == PixelPoint(x: 446, y: 300))
        let p9 = LessonLibrary.all.first { $0.id == "P9" }!
        #expect(p9.configurations.map { $0.parameters.choice("discretisation") } == ["sampled", "lindeberg"])
        let p4 = LessonLibrary.all.first { $0.id == "P4" }!
        #expect(p4.configurations.map(\.variant) == [GaussianOperator.direct2D, GaussianOperator.separable] && p4.view == .difference256)
        #expect(LessonLibrary.resolved(p4) == p4)
    }

    @Test func numbersBlurCoreComputes() {
        func value(_ id: String, _ row: String) -> BadgedValue? { LessonLibrary.all.first { $0.id == id }?.lookFor.first { $0.id == row }?.value }
        // The 13-tap box σ-hold picks at σ 4, as run: −0.220 (the continuous sinc's −0.217 is the limit of wide boxes).
        let box = value("P1", "boxMin")?.value ?? 0
        #expect(box < -0.21 && box > -0.23 && value("P1", "boxMin")?.text == NumberStyle.significant(3).text(box))
        #expect(value("P4", "direct")?.text == "2,401" && value("P4", "sep")?.text == "98")
        #expect(value("P5", "sep")?.text == "61" && value("P5", "lin")?.text == "31")
        #expect(value("P8", "binomial")?.text == "0" && value("P8", "gauss")?.text == "1.41")
        #expect(value("P9", "sampled")?.text == "0.088" && value("P9", "lindeberg")?.text == "0.300")
        #expect(value("P16", "t3")?.text == "4.0000" && value("P16", "t0")?.text == "1.4142")
        #expect(value("P18", "linear")?.text == "0.735" && value("P18", "srgb")?.text == "0.500")
        #expect(value("descent-A", "fetches")?.text == "26")
        #expect(value("descent-D", "area")?.text == "665.1" && value("descent-D", "sigma")?.text == "7.30")
        #expect(value("P3", "discrete")?.qualifiers.contains(.unverified) == true && value("P3", "discrete")?.value == nil)
        #expect(value("P21", "discrete")?.qualifiers.contains(.unverified) == true)
        #expect(value("P27", "calayer")?.qualifiers.contains(.sourcesDisagree) == true)
        // Status lines carry every number as a badged value.
        for lesson in LessonLibrary.all {
            #expect(lesson.statusLine.honestyViolations.isEmpty, "\(lesson.id) \(lesson.statusLine.honestyViolations)")
            #expect(!lesson.statusLine.values.isEmpty, "\(lesson.id)")
        }
    }
}

@Suite struct CONTENTLAYERS_Honesty {
    typealias F = CONTENTLAYERS_Fixtures
    static let builder = FloorPageBuilder(tools: CONTENTLAYERS_FakeTools())

    static func swiftUICalibration(sigmaPerPx: Double) -> CalibrationResult {
        let request = CalibrationRequest(subject: .swiftUIBlur, path: .imageRendererCGImage, parameter: 4, displayScale: 3, colourMode: .nonLinear, phases: 4)
        let fit = PSFFit(sigmaPx: 10.8, sigmaPerParameterPixel: sigmaPerPx, lsqSigmaPx: 10.8, excessKurtosis: -0.45, excessKurtosis45: nil, extentPx: 30,
                         supportPx: 40, centreSpreadPx: 0.1, sigmaSpreadPercent: 1, encodedMidpoint: nil, shapeName: "box cubed", models: [],
                         lsf: (0..<41).map { exp(-pow(Double($0 - 20), 2) / 200) })
        return CalibrationResult(request: request, fit: fit, device: F.phone, durationMilliseconds: 12)
    }

    /// Every SwiftUI-derived value carries `.offscreen`, the OFFSCREEN caption and the spoken word, on every surface.
    @Test func swiftUIDerivedValuesAreOffscreen() {
        let config = F.configuration(F.gaussian)
        let ctx = F.context(config)
        // Rail SLIDE and floor 1 rows with SwiftUI as the home tool.
        let slide = Self.builder.railChips(for: F.gaussian, context: ctx)[0].value
        #expect(ContentOffscreen.isMarked(slide))
        let page1 = Self.builder.page(.slide, for: F.gaussian, context: ctx)
        for row in page1.numbers where row.id.contains("swiftui") || row.id == "you-type" { #expect(ContentOffscreen.isMarked(row.value), "\(row.label)") }
        let reverse = page1.details.compactMap { if case .disclosure(_, let b) = $0 { return b }; return nil }.flatMap { $0 }
            .compactMap { if case .values(let v) = $0 { return v }; return nil }.flatMap { $0 }
        for row in reverse where row.id == "reverse-swiftui" { #expect(ContentOffscreen.isMarked(row.value)) }
        // A system entry measured by Calibrate (ImageRenderer): every fitted number marked.
        let system = CONTENTLAYERS_FakeOperator(kind: .system)
        let live = LiveFacts(calibrations: [Self.swiftUICalibration(sigmaPerPx: 0.9)])
        let sctx = F.context(F.configuration(system, window: 128), live: live)
        for floor in [Floor.math, .kernel, .algorithm, .pixels] {
            let page = Self.builder.page(floor, for: system, context: sctx)
            for row in page.numbers where row.value.provenance == .measured && row.value.value != nil {
                #expect(ContentOffscreen.isMarked(row.value), "\(page.eyebrow) \(row.label)")
            }
            #expect(ContentLint.violations(page).isEmpty, "\(ContentLint.violations(page))")
        }
        // The API floor's measured twin law for a SwiftUI subject.
        let twin = Self.builder.page(.api, for: system, context: sctx).numbers.first { $0.id == "law" }
        #expect(twin.map { ContentOffscreen.isMarked($0.value) } == true)
        // The flagship lesson's macOS values.
        let p26 = LessonLibrary.all.first { $0.id == "P26" }!
        for row in p26.lookFor where row.value.provenance == .measured { #expect(ContentOffscreen.isMarked(row.value), "\(row.label)") }
        // Field guide tool rows.
        let guide = FieldGuideLibrary(tools: CONTENTLAYERS_FakeTools()).page(for: F.gaussian, context: ctx)
        let rows = guide.blocks.compactMap { if case .disclosure(_, let b) = $0 { return b }; return nil }.flatMap { $0 }
            .compactMap { if case .values(let v) = $0 { return v }; return nil }.flatMap { $0 }
        #expect(rows.first { $0.id == "tool-swiftui" }.map { ContentOffscreen.isMarked($0.value) } == true)
    }

    @Test func fieldGuideLegendAndLens() {
        for op in BlurRegistry.operators + CONTENTLAYERS_Kind.allCases.map({ CONTENTLAYERS_FakeOperator(kind: $0) as any BlurOperator }) {
            for library in [FieldGuideLibrary(tools: CONTENTLAYERS_FakeTools()), FieldGuideLibrary()] {
                let page = library.page(for: op, context: F.context(F.configuration(op, window: 128)))
                #expect(page.blur == op.entry.id && page.title == op.entry.displayName)
                #expect(page.blocks.contains { if case .sources(let s) = $0 { return !s.isEmpty }; return false })
                #expect(ContentLint.violations(page).isEmpty, "\(op.entry.id): \(ContentLint.violations(page))")
            }
        }
        let legend = BlurServices.fieldGuide.honestyLegend
        let titles = legend.compactMap { if case .disclosure(let t, _) = $0 { return t }; return nil }
        #expect(titles == Provenance.allCases.map(\.word))
        #expect(legend.flatMap { ContentLint.violations($0, context: "legend") }.isEmpty)
        #expect(legend.contains { if case .note(let s, _) = $0 { return s.hasPrefix("UNVERIFIED is not a seventh label") }; return false })
        let lens = BlurServices.fieldGuide.lensNote
        #expect(lens.count >= 4 && lens.flatMap { ContentLint.violations($0, context: "lens") }.isEmpty)
        #expect(lens.contains { if case .sources(let s) = $0 { return s.contains { $0.citation.contains("WWDC25 session 219") } }; return false })
    }

    @Test func statusLines() {
        for op in BlurRegistry.operators {
            for variant in op.entry.variants {
                let params = op.holdingSigma(4, current: op.entry.defaultParameters).parameters
                let plan = op.passPlan(OperatorRequest(parameters: params, variant: variant.id, size: .square(894)))
                let line = ContentStatusLines.phase(plan)
                #expect(line.honestyViolations.isEmpty, "\(variant.id)")      // the variant name sits in a literal
                #expect(line.text.hasSuffix(plan.algorithmName.uppercased()))
            }
            #expect(ContentStatusLines.sigmaNotDefined(op.entry).honestyViolations.isEmpty)
            #expect(ContentStatusLines.tooSlowToTime(op.passPlan(OperatorRequest(parameters: op.entry.defaultParameters, variant: op.entry.defaultVariant,
                                                                                  size: .square(894))), size: .square(894)).honestyViolations.isEmpty)
        }
        #expect(ContentStatusLines.phase(F.gaussian.passPlan(F.configuration(F.gaussian).operatorRequest)).text == "74 FETCHES · 2 PASSES · LINEAR-SAMPLED")
        #expect(ContentStatusLines.rendering(pass: 2, of: 2).text == "RENDERING… PASS 2/2" && ContentStatusLines.rendering(pass: 2, of: 2).honestyViolations.isEmpty)
        #expect(ContentStatusLines.operatorNotice("2-D DIRECT ABOVE σ 8 · USING SEPARABLE").honestyViolations.isEmpty)
        #expect(ContentStatusLines.difference(max: 6, rms: 0.8, gain: 16).text == "MAX 6 LSB · RMS 0.8 LSB · ×16")
        #expect(ContentStatusLines.difference(max: 6, rms: 0.8, gain: 16).honestyViolations.isEmpty)
        let lineUp = ContentStatusLines.minimumResponses([F.configuration(F.gaussian), F.configuration(F.gaussian, variant: GaussianOperator.separable)])
        #expect(lineUp.honestyViolations.isEmpty && lineUp.values.count == 2)
        #expect(ContentStatusLines.coaching.honestyViolations.isEmpty)
        let parts = ContentStatusLines.partsWays([FloorComparison(floor: .math, verdict: .partsWays, reason: "rect vs bell")])
        #expect(parts.text == "PARTS WAYS AT MATH")
    }

    @Test func theLintCatchesWhatItShould() {
        #expect(!ContentLint.digitViolations("σ 12.0 px", context: "t").isEmpty)
        #expect(!ContentLint.digitViolations("min H −0.217", context: "t").isEmpty)
        #expect(!ContentLint.digitViolations("74 FETCHES", context: "t").isEmpty)
        for allowed in ["2-D DIRECT", "fp16 ACCUMULATE", "rgba16Float", "PROBE (447, 455)", "H ≥ 0 (CONTINUOUS)", "Apple9 · A17 Pro", "SHA-256",
                        "λ = 0.125", "−3 dB", "10–90 % EDGE", "8-BIT ROUND TO NEAREST", "Difference ×16", "TIER 1 · LIVE", "FLOOR 4 · KERNEL",
                        "iOS 27.0", "macOS 27.2", "WWDC 2014", "PARITY · 128² CROP", "P21 and F6", "3×3 window", "↓1 then ↑2"] {
            #expect(ContentLint.digitViolations(allowed, context: "t").isEmpty, "\(allowed)")
        }
        #expect(ContentLint.violations(.number(1, .decimals(0), .measured), context: "t").contains { $0.contains("DeviceStamp") })
        #expect(!ContentLint.violations(.words("about 12 px"), context: "t").isEmpty)
        #expect(ContentLint.violations(.paragraph("The pass took 0.31 ms."), context: "t").count == 1)
        #expect(ContentLint.violations(.equation("σ = √(2t) = 4.00 px"), context: "t").isEmpty)
        #expect(ContentLint.violations(.note("min H −0.217", .computed), context: "t").isEmpty)          // a badged note
        #expect(!ContentLint.violations(.table(TableBlock(columns: ["A"], rows: [["0.5"]])), context: "t").isEmpty)   // unbadged table
        // Trace narration: decimals need a badged twin.
        let step = TraceStep(id: 0, floor: .gpu, completed: "Pass H written: 0.4500", next: "x", primaryLabel: "Next pass", subSteps: [], passIndex: nil,
                             panel: FloorFacts(), branchValues: [], phaseLine: "Step 1 / 1", closingLesson: nil, announcement: "Completed.")
        #expect(ContentLint.violations([step]).count == 1)
        var twin = step
        twin.panel.numbers = [LabeledValue(id: "out", label: "OUT", value: .number(0.45, .decimals(4), .computed))]
        #expect(ContentLint.violations([twin]).isEmpty)
    }
}
