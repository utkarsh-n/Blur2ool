import XCTest
import SwiftUI
import UIKit
@testable import Blur2ool
import BlurCore

// OWNER: METRO-COMPONENTS (PLAN §4 METRO-COMPONENTS acceptance 6). Run on the phone under the simulator hold with
// `Tools/build.sh device-build-for-testing` + `device-session "test --area METROCOMPONENTS --kind app"`.
// Covers: the crown's 7-pt centre exclusion and its step callbacks (gesture model, ± path and the view's adjustable
// action), every HonestyBadge's spoken label, the decimal Stepper's exact stepping, event-tile rows, the pill's geometry,
// blend and spoken value, every GlyphKind drawing something, haptic detent tuning, the cluster formula, and the honesty of
// every value the gallery shows.

@MainActor
final class METROCOMPONENTS_CrownTests: XCTestCase {
    private let d = 62.0
    /// A crown-local point at `radius` from the centre, at screen angle `degrees` (clockwise from +x).
    private func at(_ radius: Double, _ degrees: Double) -> CGPoint {
        let a = degrees * .pi / 180
        return CGPoint(x: d / 2 + radius * cos(a), y: d / 2 + radius * sin(a))
    }

    func testCentreExclusionIsSevenPoints() {
        let gesture = InstrumentCrownGesture(detentDegrees: 8)
        XCTAssertEqual(gesture.centreExclusion, 7)
        XCTAssertTrue(gesture.isInsideExclusion(at(0, 0)))
        XCTAssertTrue(gesture.isInsideExclusion(at(6.99, 45)))
        XCTAssertFalse(gesture.isInsideExclusion(at(7.0, 0)))          // exactly 7 pt on an axis: outside (no trig rounding)
        XCTAssertFalse(gesture.isInsideExclusion(at(7.01, 45)))
        XCTAssertFalse(gesture.isInsideExclusion(at(20, 200)))
    }

    func testTouchesInsideTheExclusionNeverBeginOrStep() {
        var gesture = InstrumentCrownGesture(detentDegrees: 8)
        var t = 0.0
        for k in 0..<72 {   // a full circle at radius 5: angles swing wildly, but nothing happens
            t += 0.1
            XCTAssertEqual(gesture.move(to: at(5, Double(k) * 5), at: t), .none)
        }
        XCTAssertFalse(gesture.isDragging)
    }

    func testFirstTouchBeginsWithoutAStep() {
        var gesture = InstrumentCrownGesture(detentDegrees: 8)
        XCTAssertEqual(gesture.move(to: at(25, 10), at: 0), .began)
        XCTAssertTrue(gesture.isDragging)
        XCTAssertEqual(gesture.move(to: at(25, 10), at: 0.1), .none)   // no travel, no step
    }

    func testClockwiseAndCounterclockwiseDetentsStepPlusAndMinus() {
        var gesture = InstrumentCrownGesture(detentDegrees: 8)
        XCTAssertEqual(gesture.move(to: at(25, 0), at: 0), .began)
        XCTAssertEqual(gesture.move(to: at(25, 7), at: 0.10), .none)      // 7° < 8°
        XCTAssertEqual(gesture.move(to: at(25, 8.5), at: 0.20), .step(1)) // past one detent: +1
        // Back the other way: a reversal needs the detent plus 18 % hysteresis (8 + 1.44 = 9.44°).
        XCTAssertEqual(gesture.move(to: at(25, -0.4), at: 0.30), .none)   // 8.9° back
        XCTAssertEqual(gesture.move(to: at(25, -1.5), at: 0.40), .step(-1))
        gesture.end()
        XCTAssertFalse(gesture.isDragging)
    }

    func testAtMostOneStepPerUpdateAndNoQueuedBurst() {
        var gesture = InstrumentCrownGesture(detentDegrees: 8)
        _ = gesture.move(to: at(25, 0), at: 0)
        XCTAssertEqual(gesture.move(to: at(25, 40), at: 0.2), .step(1))   // five detents of travel, one step
        XCTAssertEqual(gesture.move(to: at(25, 40), at: 0.4), .none)      // no catch-up notches later
    }

    func testRateLimitHoldsAPendingNotchUntilAdmitted() {
        var gesture = InstrumentCrownGesture(detentDegrees: 8)
        _ = gesture.move(to: at(25, 0), at: 0)
        XCTAssertEqual(gesture.move(to: at(25, 9), at: 1.000), .step(1))
        XCTAssertEqual(gesture.move(to: at(25, 18), at: 1.010), .none)    // 10 ms later: > 20 per second, held
        XCTAssertEqual(gesture.move(to: at(25, 18.2), at: 1.060), .step(1)) // admitted 60 ms after the last
    }

    func testCrossingTheBearingDiscardsHistory() {
        var gesture = InstrumentCrownGesture(detentDegrees: 8)
        _ = gesture.move(to: at(25, 0), at: 0)
        XCTAssertEqual(gesture.move(to: at(3, 0), at: 0.1), .none)        // through the centre
        XCTAssertEqual(gesture.move(to: at(25, 180), at: 0.2), .none)     // emerging opposite: no 180° jump
        XCTAssertEqual(gesture.move(to: at(25, 189), at: 0.3), .step(1))  // then ordinary travel steps again
    }

    func testSemanticDetentIsTwentyDegrees() {
        var gesture = InstrumentCrownGesture(detentDegrees: InstrumentMotion.coarseDetentDegrees)
        _ = gesture.move(to: at(25, 0), at: 0)
        XCTAssertEqual(gesture.move(to: at(25, 15), at: 0.1), .none)
        XCTAssertEqual(gesture.move(to: at(25, 21), at: 0.2), .step(1))
    }

    /// The step callbacks: every input path of the view (detent events, ± buttons, adjustable action) goes through
    /// `InstrumentCrown.accepted` / `dispatch`, so a turn produces exactly one `onStep(±1)` per accepted detent.
    func testGestureEventsBecomeOneStepCallbackEach() {
        var steps: [Int] = []
        var gesture = InstrumentCrownGesture(detentDegrees: 8)
        let path: [(Double, Double, Double)] = [(25, 0, 0), (25, 5, 0.1), (25, 9, 0.2), (3, 9, 0.3), (25, 190, 0.4), (25, 199, 0.5),
                                                (25, 207.5, 0.6), (25, 198, 0.7), (25, 196, 0.8)]
        for (r, a, t) in path {
            InstrumentCrown.dispatch(gesture.move(to: at(r, a), at: t), isEnabled: true) { steps.append($0) }
        }
        XCTAssertEqual(steps, [1, 1, 1, -1])
        // A disabled crown emits nothing, whatever the gesture reports.
        var silent: [Int] = []
        InstrumentCrown.dispatch(.step(1), isEnabled: false) { silent.append($0) }
        InstrumentCrown.dispatch(.began, isEnabled: true) { silent.append($0) }
        InstrumentCrown.dispatch(.none, isEnabled: true) { silent.append($0) }
        XCTAssertEqual(silent, [])
    }

    func testButtonsAndAdjustableActionsStepByExactlyOne() {
        XCTAssertEqual(InstrumentCrown.accepted(1, isEnabled: true), 1)
        XCTAssertEqual(InstrumentCrown.accepted(-1, isEnabled: true), -1)
        XCTAssertEqual(InstrumentCrown.accepted(5, isEnabled: true), 1)        // never a burst of notches
        XCTAssertEqual(InstrumentCrown.accepted(-3, isEnabled: true), -1)
        XCTAssertNil(InstrumentCrown.accepted(0, isEnabled: true))
        XCTAssertNil(InstrumentCrown.accepted(1, isEnabled: false))
    }

    func testRolesHaveTheirInksSymbolsAndHaptics() {
        XCTAssertEqual(InstrumentCrown.accent(.fine), InstrumentPalette.instrumentCyan)
        XCTAssertEqual(InstrumentCrown.accent(.semantic), InstrumentPalette.instrumentAmber)
        XCTAssertEqual(InstrumentCrown.accent(.angle), InstrumentPalette.instrumentCyan)
        XCTAssertEqual(InstrumentCrown.accent(.second), InstrumentPalette.instrumentAmber)
        for role in [CrownRole.fine, .semantic, .angle, .second] {
            XCTAssertNotNil(UIImage(systemName: InstrumentCrown.symbol(role)), "missing SF Symbol \(InstrumentCrown.symbol(role))")
        }
        XCTAssertEqual(InstrumentDetentKind(role: .fine, direction: 1), .fineUp)
        XCTAssertEqual(InstrumentDetentKind(role: .angle, direction: -1), .fineDown)
        XCTAssertEqual(InstrumentDetentKind(role: .semantic, direction: 1), .semanticUp)
        XCTAssertEqual(InstrumentDetentKind(role: .semantic, direction: -1), .semanticDown)
        XCTAssertEqual(InstrumentDetentKind.fineUp.intensity, 0.78); XCTAssertEqual(InstrumentDetentKind.fineUp.sharpness, 0.95)
        XCTAssertEqual(InstrumentDetentKind.fineDown.intensity, 0.82); XCTAssertEqual(InstrumentDetentKind.fineDown.sharpness, 0.2)
        XCTAssertEqual(InstrumentDetentKind.semanticUp.intensity, 1); XCTAssertEqual(InstrumentDetentKind.semanticUp.sharpness, 0.6)
        XCTAssertEqual(InstrumentDetentKind.semanticDown.intensity, 1); XCTAssertEqual(InstrumentDetentKind.semanticDown.sharpness, 0.05)
    }

    /// The A17 Pro has a Taptic Engine: Core Haptics is supported and a detent plays (the feel itself is L5, hands-on).
    func testDetentHapticsPlayOnThisPhone() {
        let haptics = InstrumentDetentHaptics.shared
        XCTAssertTrue(haptics.isSupported)
        haptics.prepare()
        let before = haptics.playedCount
        haptics.play(.fineUp)
        XCTAssertEqual(haptics.playedCount, before + 1)
        haptics.play(.fineDown)                       // within 50 ms: skipped, never queued (Metro §15)
        XCTAssertEqual(haptics.playedCount, before + 1)
    }
}

@MainActor
final class METROCOMPONENTS_BadgeTests: XCTestCase {
    func testEveryBadgeSpeaksItsWord() {
        let expected: [Provenance: String] = [.live: "live", .measured: "measured", .computed: "computed", .modeled: "modeled",
                                              .reference: "reference", .inferred: "inferred"]
        var spoken = Set<String>()
        for p in Provenance.allCases {
            let label = HonestyBadge.spokenLabel(p)
            XCTAssertEqual(label, expected[p], "\(p.word) speaks '\(label)'")
            XCTAssertEqual(label, p.word.lowercased())
            XCTAssertFalse(HonestyBadge.meaning(p).isEmpty)
            spoken.insert(label)
        }
        XCTAssertEqual(spoken.count, 6)
    }

    func testQualifiersAreSpokenAndPrinted() {
        XCTAssertEqual(HonestyBadge.spokenLabel(.live, qualifiers: .cpu), "live, on the CPU")
        XCTAssertEqual(HonestyBadge.spokenLabel(.measured, qualifiers: .offscreen), "measured, offscreen")
        XCTAssertEqual(HonestyBadge.spokenLabel(.measured, qualifiers: [.offscreen, .experimental]), "measured, offscreen, experimental")
        XCTAssertEqual(HonestyBadge.spokenLabel(.measured, qualifiers: .notThisDevice), "measured, not on this device")
        XCTAssertEqual(HonestyBadge.spokenLabel(.modeled, qualifiers: .weakSource), "modeled, weak source")
        XCTAssertEqual(HonestyBadge.spokenLabel(.reference, qualifiers: .unverified), "reference, unverified")
        XCTAssertEqual(HonestyBadge.qualifierWords(.cpu), ["CPU"])
        XCTAssertEqual(HonestyBadge.qualifierWords([.offscreen, .simulator]), ["OFFSCREEN", "SIMULATOR"])
        XCTAssertEqual(HonestyBadge.qualifierWords([.unverified, .weakSource, .sourcesDisagree]), [])   // never inside the capsule
    }

    func testGlyphsExistAndWordsAreWiderThanGlyphs() throws {
        for p in Provenance.allCases {
            if let name = HonestyBadge.symbolName(p) { XCTAssertNotNil(UIImage(systemName: name), "missing SF Symbol \(name)") }
            let word = ImageRenderer(content: HonestyBadge(p).environment(\.colorScheme, .dark))
            let glyph = ImageRenderer(content: HonestyBadge(p, style: .glyph).environment(\.colorScheme, .dark))
            word.scale = 3; glyph.scale = 3
            let w = try XCTUnwrap(word.uiImage?.size), g = try XCTUnwrap(glyph.uiImage?.size)
            XCTAssertGreaterThan(w.width, g.width * 2, "\(p.word): word badge \(w) vs glyph \(g)")
            XCTAssertGreaterThanOrEqual(g.height, 11, "\(p.word): glyph badge below 11 pt")
        }
        XCTAssertNil(HonestyBadge.symbolName(.modeled))   // SF Symbols has no `approximately`; the text ≈ stands in
    }

    func testBadgesStopGrowingAtAX1() throws {
        func width(_ size: DynamicTypeSize) throws -> CGFloat {
            let r = ImageRenderer(content: HonestyBadge(.reference).environment(\.dynamicTypeSize, size))
            return try XCTUnwrap(r.uiImage?.size.width)
        }
        let large = try width(.large), ax1 = try width(.accessibility1), ax5 = try width(.accessibility5)
        XCTAssertGreaterThan(ax1, large)
        XCTAssertEqual(ax5, ax1, accuracy: 0.5)
    }

    func testBadgedValueChipTextAndCaptions() {
        XCTAssertEqual(BadgedValueText.chipText(.unverified("x")), "UNVER.")
        XCTAssertEqual(BadgedValueText.chipText(.number(0.0885, .significant(3), .live)), "0.0885")
        XCTAssertEqual(BadgedValueText.chipText(.words("LINEAR-SAMPLED", .computed)), "LINEAR")
        XCTAssertEqual(BadgedValueText.reservedTemplate("0.61"), "0000")
        XCTAssertEqual(BadgedValueText.reservedTemplate("12.40"), "00000")
        XCTAssertNil(BadgedValueText.badge(.input(12, .decimals(1))))
        XCTAssertEqual(BadgedValueText.badge(.number(1, .integer(), .computed)), .computed)
    }
}

@MainActor
final class METROCOMPONENTS_ControlTests: XCTestCase {
    func testDecimalStepperStepsExactlyOnTheGrid() {
        var v = 0.3
        for _ in 0..<100 { v = DecimalParameterStepper.stepped(v, direction: 1, step: 0.1, decimals: 1, in: 0.3...64) ?? v }
        XCTAssertEqual(v, 10.3)                                     // no drift after 100 steps of 0.1
        XCTAssertNil(DecimalParameterStepper.stepped(64, direction: 1, step: 0.1, decimals: 1, in: 0.3...64))   // range end: no event
        XCTAssertNil(DecimalParameterStepper.stepped(0.3, direction: -1, step: 0.1, decimals: 1, in: 0.3...64))
        XCTAssertEqual(DecimalParameterStepper.stepped(12.04, direction: 1, step: 0.1, decimals: 1, in: 0.3...64), 12.1)
        XCTAssertEqual(DecimalParameterStepper.stepped(179, direction: -1, step: 1, decimals: 0, in: 0...179), 178)
        XCTAssertEqual(DecimalParameterStepper.stepped(10, direction: 1, step: 0.5, decimals: 1, in: 0...50), 10.5)
    }

    func testEventTileRowsWrapAboveSix() {
        XCTAssertEqual(InstrumentEventTiles.rows(count: 0), [])
        XCTAssertEqual(InstrumentEventTiles.rows(count: 2), [0..<2])
        XCTAssertEqual(InstrumentEventTiles.rows(count: 6), [0..<6])
        XCTAssertEqual(InstrumentEventTiles.rows(count: 7), [0..<4, 4..<7])
        XCTAssertEqual(InstrumentEventTiles.rows(count: 12), [0..<6, 6..<12])
        XCTAssertEqual(InstrumentEventTiles.rows(count: 13), [0..<5, 5..<9, 9..<13])
    }

    func testClusterFormulaAndFloatingReserve() {
        let c = InstrumentMetrics.cluster(available: 406)
        XCTAssertEqual(c.pillWidth, 36); XCTAssertEqual(c.diameter, 322); XCTAssertEqual(c.pillHeight, 212.52, accuracy: 1e-9)
        XCTAssertEqual(InstrumentMetrics.cluster(available: 300).pillWidth, 30)
        XCTAssertEqual(FloatingGroupHeightKey.contentReserve(forGlassHeight: 58), 86)
        var v: CGFloat = 0
        FloatingGroupHeightKey.reduce(value: &v) { 58 }
        FloatingGroupHeightKey.reduce(value: &v) { 40 }
        XCTAssertEqual(v, 58)
    }

    /// Text fit at 430 pt: the crown's group is 44 + 6 + 62 + 6 + 44 = 162 pt and its captions never truncate at AX XXXL.
    func testCrownGeometryAtDefaultAndAccessibilitySizes() throws {
        func size(_ dynamicType: DynamicTypeSize) throws -> CGSize {
            let crown = InstrumentCrown(caption: "SIGMA · Backdrop", subcaption: "Frosted ⇆ Fog", role: .semantic, detentDegrees: 20,
                                        accessibilityLabel: "Sigma", accessibilityValue: "12.0 pixels") { _ in }
            let r = ImageRenderer(content: crown.environment(\.dynamicTypeSize, dynamicType).frame(width: 406))
            r.proposedSize = ProposedViewSize(width: 406, height: nil)
            return try XCTUnwrap(r.uiImage?.size)
        }
        let normal = try size(.large), ax5 = try size(.accessibility5)
        XCTAssertGreaterThanOrEqual(normal.height, 62 + 2 * 14)
        XCTAssertGreaterThan(ax5.height, normal.height)
    }
}

@MainActor
final class METROCOMPONENTS_PillAndGlyphTests: XCTestCase {
    private func plot(_ xs: [Double], _ ys: [Double], unit: String = "px", range: ClosedRange<Double>? = nil) -> PlotSpec {
        PlotSpec(xAxis: PlotAxis(label: "offset", unit: unit, range: range), yAxis: PlotAxis(label: "weight", normalized: true),
                 series: [PlotSeries(name: "taps", xs: xs, ys: ys, style: .stems, role: .primary, provenance: .computed)],
                 accessibilitySummary: "taps")
    }

    func testTitlesAxesAndSpokenDirections() {
        XCTAssertEqual(InstrumentSignalPill.titleRow("KERNEL", family: .wave), "KERNEL")
        XCTAssertEqual(InstrumentSignalPill.titleRow("LOCAL @ PROBE", family: .wave), "KERNEL")
        XCTAssertEqual(InstrumentSignalPill.titleRow("T(ν, A 0.20)", family: .spectrum), "FREQ")
        let wave = PillAxisLabels(plot: plot([-36, 0, 36], [0.1, 1, 0.1], range: -36...36), family: .wave)
        XCTAssertEqual(wave.upper, "\u{2212}36"); XCTAssertEqual(wave.lower, "+36")
        let freq = PillAxisLabels(plot: plot([0, 0.25, 0.5], [1, 0.5, 0], unit: "c/px", range: 0...0.5), family: .spectrum)
        XCTAssertEqual(freq.upper, "NYQ"); XCTAssertEqual(freq.lower, "DC")
        let kernel = PillPlot(title: "KERNEL", plot: plot([-1, 0, 1], [0.5, 1, 0.5]), emptyText: nil, badge: .words("COMPUTED", .computed))
        XCTAssertTrue(InstrumentSignalPill.spokenValue(kernel, family: .wave).contains("runs downward"))
        XCTAssertTrue(InstrumentSignalPill.spokenValue(kernel, family: .wave).hasSuffix("computed"))
        XCTAssertTrue(InstrumentSignalPill.spokenValue(kernel, family: .spectrum).contains("runs upward"))
        let empty = PillPlot(title: "FREQ", plot: nil, emptyText: "INFERRED — NOT EXPOSED", badge: .words("INFERRED", .inferred))
        XCTAssertEqual(InstrumentSignalPill.spokenValue(empty, family: .spectrum), "inferred — not exposed. inferred")
    }

    func testInteriorBlendsOnASharedGridAndCrossFadesOtherwise() throws {
        let a = PillScene(content: PillPlot(title: "FREQ", plot: plot([0, 0.25, 0.5], [1, 0.5, 0]), emptyText: nil, badge: nil), comparisons: [])
        let b = PillScene(content: PillPlot(title: "FREQ", plot: plot([0, 0.25, 0.5], [1, 0.1, -0.2]), emptyText: nil, badge: nil), comparisons: [])
        let mid = try XCTUnwrap(PillScene.blend(a, b, t: 0.5))
        XCTAssertEqual(mid.plot?.series[0].ys ?? [], [1, 0.3, -0.1], accuracy: 1e-12)
        let c = PillScene(content: PillPlot(title: "FREQ", plot: plot([0, 0.5], [1, 0]), emptyText: nil, badge: nil), comparisons: [])
        XCTAssertNil(PillScene.blend(a, c, t: 0.5))
        XCTAssertEqual(InstrumentMotion.pillInteriorEase, 0.15)
    }

    func testEveryGlyphKindDrawsInk() throws {
        let kinds = Set(GalleryFixtures.glyphs.map(\.kind))
        XCTAssertEqual(kinds, Set(GlyphKind.allCases), "the gallery must show every GlyphKind")
        for spec in GalleryFixtures.glyphs {
            let renderer = ImageRenderer(content: FootprintGlyph(spec))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage, "\(spec.kind)")
            let lit = Self.litPixels(image)
            XCTAssertGreaterThan(lit, spec.kind == .none ? 4 : 40, "\(spec.kind) drew only \(lit) bright pixels")
        }
    }

    /// Pixels clearly brighter than the recessed metal (any channel above 0.3).
    static func litPixels(_ image: CGImage) -> Int {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var count = 0
        for i in stride(from: 0, to: data.count, by: 4) where Swift.max(data[i], data[i + 1], data[i + 2]) > 77 { count += 1 }
        return count
    }
}

@MainActor
final class METROCOMPONENTS_GalleryHonestyTests: XCTestCase {
    func testEveryGalleryValueIsHonest() {
        let values = GalleryFixtures.allValues
        XCTAssertGreaterThanOrEqual(values.count, 20)
        for v in values { XCTAssertEqual(v.honestyViolations, [], "\(v.text): \(v.honestyViolations)") }
        XCTAssertTrue(values.contains { $0.provenance == .measured && $0.device != nil && $0.value != nil })
        XCTAssertTrue(values.contains { $0.provenance == .reference && $0.source != nil })
        XCTAssertTrue(values.contains { $0.qualifiers.contains(.unverified) && $0.value == nil })
    }

    func testGalleryNumbersAreBlurCoresAtTheStatedInputs() {
        let chips = GalleryFixtures.railChips(sigma: 12)
        XCTAssertEqual(chips.first { $0.floor == .kernel }?.value.text, "73")        // SPEC §5.3 fixture: 73 taps at σ 12
        XCTAssertEqual(chips.first { $0.floor == .api }?.value.text, "12.0")
        let box = GalleryFixtures.rows.first { $0.label.hasPrefix("MIN H") }?.value.value ?? 0
        XCTAssertEqual(box, -0.2265, accuracy: 0.0005)                               // nine-tap box: minimum H −0.2265 (1/512 grid)
        XCTAssertEqual(GalleryFixtures.octaveStop(from: 12, direction: 1), 16)
        XCTAssertEqual(GalleryFixtures.octaveStop(from: 12, direction: -1), 8)
        XCTAssertEqual(GalleryFixtures.octaveStop(from: 64, direction: 1), 64)
        XCTAssertEqual(GalleryFixtures.band(for: 12), "Backdrop")
        XCTAssertEqual(GalleryFixtures.band(for: 0.4), "Sub-pixel")
        XCTAssertEqual(GalleryFixtures.pills(sigma: 12).count, 7)
    }
}

private func XCTAssertEqual(_ a: [Double], _ b: [Double], accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, file: file, line: line)
    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line) }
}
