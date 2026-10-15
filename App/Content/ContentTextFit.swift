import SwiftUI
import BlurCore

// OWNER: CONTENT-VIEWS. Text fit (review fix P-48; ARCHITECTURE §11.3 "Layout"; SPEC §4.1.10 "Text fit"): measures, with
// ImageRenderer, every slot of a floor page, every engraving and every status-row template at a Dynamic Type size and a
// screen width, and compares the measured size with the slot SPEC reserves for it. The AppTests on the phone run it at the
// default and xxxLarge sizes and at 430, 393 and 375 pt; nothing in the shipping app calls it.
//
// Widths: a floor page is the screen minus the 12-pt insets, its content the page minus the panel's 16-pt padding. The
// readout band and the housing caption are as wide as the image window (D − 24 from Metro's cluster formula: 298, 261,
// 243 pt at 430, 393, 375; SPEC §4.1.10).

@MainActor
enum ContentTextFit {
    struct Result: CustomStringConvertible {
        var subject: String
        var slot: String
        var measured: CGFloat
        var reserved: CGFloat
        var fits: Bool { measured <= reserved + 0.5 }
        var description: String {
            "\(fits ? "fits" : "OVERFLOW") \(subject) · \(slot): \(Int(measured.rounded(.up))) of \(Int(reserved.rounded(.down))) pt"
        }
    }

    static let widths: [CGFloat] = [430, 393, 375]
    static let sizes: [DynamicTypeSize] = [.large, .xxxLarge]

    static func pageWidth(_ screen: CGFloat) -> CGFloat { screen - 24 }
    static func contentWidth(_ screen: CGFloat) -> CGFloat { pageWidth(screen) - 2 * InstrumentMetrics.panelInset }
    static func windowWidth(_ screen: CGFloat) -> CGFloat { InstrumentMetrics.cluster(available: screen - 24).diameter - 24 }

    /// The natural height of `view` at `width` and `size` (ImageRenderer, scale 1).
    static func height<V: View>(_ view: V, width: CGFloat, size: DynamicTypeSize) -> CGFloat {
        renderedSize(view.frame(width: width).fixedSize(horizontal: false, vertical: true), width: width, size: size).height
    }

    /// The natural width of a one-line `view` at `size` (no width constraint).
    static func lineWidth<V: View>(_ view: V, size: DynamicTypeSize) -> CGFloat {
        renderedSize(view.fixedSize(), width: nil, size: size).width
    }

    static func renderedSize<V: View>(_ view: V, width: CGFloat?, size: DynamicTypeSize) -> CGSize {
        let renderer = ImageRenderer(content: view.environment(\.dynamicTypeSize, size).preferredColorScheme(.dark))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        guard let image = renderer.cgImage else { return .zero }
        return CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
    }

    // MARK: Floor pages

    /// Every reserved slot of a page (and of each of its tabs): measured content against its reserve.
    static func pageResults(_ page: FloorPage, id: String, screen: CGFloat, size: DynamicTypeSize) -> [Result] {
        let w = contentWidth(screen)
        func fit(_ slot: String, _ content: some View, _ reserve: some View) -> Result {
            Result(subject: id, slot: slot, measured: height(content, width: w, size: size), reserved: height(reserve, width: w, size: size))
        }
        var out: [Result] = []
        let tabs: [FloorTab?] = (page.tabs?.isEmpty == false) ? page.tabs!.map { Optional($0) } : [nil]
        out.append(fit("signature", FloorSignatureContent(signature: page.signature), FloorSignatureReserve()))
        out.append(fit("governing rule", FloorRuleContent(rule: page.governingRule), FloorRuleReserve()))
        out.append(fit("IN THIS APP", FloorInThisAppContent(text: page.inThisApp), FloorInThisAppReserve()))
        let figureSlot = FloorSlots.figureHeight(page.floor, size)
        for tab in tabs {
            let suffix = tab.map { " [\($0.title)]" } ?? ""
            let badges = (tab?.dominantBadges.isEmpty == false ? tab?.dominantBadges : nil) ?? page.dominantBadges
            out.append(fit("header" + suffix, FloorHeaderContent(eyebrow: page.eyebrow, badges: badges), FloorHeaderReserve(eyebrow: page.eyebrow)))
            let numbers = (tab?.numbers.isEmpty == false ? tab?.numbers : nil) ?? page.numbers
            for row in numbers {
                out.append(fit("number \(row.label)" + suffix, FloorNumberSlotContent(row: row), FloorNumberReserve()))
            }
            let figure = tab?.figure ?? page.figure
            switch figure {
            case .toolBars(let spec)?:
                out.append(Result(subject: id, slot: "tool bars" + suffix, measured: height(ToolBarsFigure(spec: spec), width: w, size: size),
                                  reserved: Swift.max(figureSlot, height(ToolBarsFigure(spec: FloorSlots.toolBarsExemplar), width: w, size: size))))
            case .passTiles(let spec)?:
                out.append(Result(subject: id, slot: "pass tiles" + suffix,
                                  measured: height(PassTilesFigure(spec: spec, onPassSelected: { _ in }), width: w, size: size), reserved: figureSlot))
            case .pair(.passTiles(let spec), _)?:
                out.append(Result(subject: id, slot: "pass tiles above the plot" + suffix,
                                  measured: height(PassTilesFigure(spec: spec, onPassSelected: { _ in }), width: w, size: size),
                                  reserved: figureSlot - 150 - ContentSpacing.group))
            case nil:
                if let empty = page.emptyState {
                    out.append(Result(subject: id, slot: "empty state", measured: height(EngravedLineMeasure(text: empty), width: w, size: size), reserved: figureSlot))
                }
            default:
                break
            }
        }
        return out
    }

    // MARK: Engravings (SPEC §5.0 rule 4, §12.2 item 3 and 4, and the figures' own engraved lines)

    struct Engraving { var text: String; var slot: Slot }
    enum Slot { case floorFigure(Floor), housingCaption, figureLine }

    static let engravings: [Engraving] = [
        Engraving(text: "N/A · NONLINEAR", slot: .floorFigure(.math)),
        Engraving(text: "N/A · RANK", slot: .floorFigure(.math)),
        Engraving(text: "NO SINGLE RESPONSE · SPACE-VARIANT", slot: .floorFigure(.math)),
        Engraving(text: "NO PIXEL FOOTPRINT · GLOBAL (FFT)", slot: .floorFigure(.kernel)),
        Engraving(text: "SYSTEM INTERNALS · INFERRED", slot: .floorFigure(.gpu)),
        Engraving(text: "CPU ONLY IN THIS APP · TIER 3", slot: .floorFigure(.algorithm)),
        Engraving(text: "CPU ONLY IN THIS APP · TIER 3", slot: .floorFigure(.gpu)),
        Engraving(text: "NOT CAPTURABLE · INFERRED", slot: .floorFigure(.pixels)),
        Engraving(text: "LIVE · METAL", slot: .housingCaption),
        Engraving(text: "PREVIEW ½", slot: .housingCaption),
        Engraving(text: "SYSTEM · ON SCREEN · NOT READ BACK", slot: .housingCaption),
        Engraving(text: "SYSTEM · MEASURED (OFFSCREEN)", slot: .housingCaption),
        Engraving(text: "MODELED · METAL", slot: .housingCaption),
        Engraving(text: "INFERRED · NATIVE GLASS", slot: .housingCaption),
        Engraving(text: "CPU · 128² CROP · COMPUTED", slot: .housingCaption),
        Engraving(text: "PASS 1 OF 2 · INTERMEDIATE", slot: .housingCaption),
        Engraving(text: "TRACED BUILD", slot: .housingCaption),
        Engraving(text: "PHOTO · RESAMPLED ×3 (BOX)", slot: .housingCaption),
        Engraving(text: "PER-PASS TIME –.–– · NOT YET MEASURED", slot: .figureLine),
        Engraving(text: "TAP A PASS TO SEE ITS INTERMEDIATE IMAGE", slot: .figureLine),
        Engraving(text: "TAP A LINE MARKED @ FOR ITS EXPLANATION", slot: .figureLine),
    ]

    /// Housing-caption engravings: one line at the default size, at most two from xLarge (the caption row grows with Dynamic
    /// Type; at accessibility sizes it moves into the native text block, SPEC §4.1.10). Figure lines: two lines at most.
    static func engravingResults(screen: CGFloat, size: DynamicTypeSize) -> [Result] {
        engravings.map { e in
            switch e.slot {
            case .floorFigure(let floor):
                return Result(subject: e.text, slot: "floor \(floor.rawValue) figure slot",
                              measured: height(EngravedLineMeasure(text: e.text), width: contentWidth(screen), size: size),
                              reserved: FloorSlots.figureHeight(floor, size))
            case .housingCaption:
                let lines = size >= .xLarge ? 2 : 1
                return Result(subject: e.text, slot: "housing caption (\(lines) line\(lines > 1 ? "s" : ""))",
                              measured: height(Text(e.text).contentFont(.engraving), width: windowWidth(screen), size: size),
                              reserved: height(ContentReservedLines(role: .engraving, lines: lines), width: 200, size: size))
            case .figureLine:
                return Result(subject: e.text, slot: "figure line (2 lines)",
                              measured: height(Text(e.text).contentFont(.engraving), width: contentWidth(screen) - 16, size: size),
                              reserved: height(ContentReservedLines(role: .engraving, lines: 2), width: 200, size: size))
            }
        }
    }

    // MARK: Status-row templates (SPEC §4.1.3: one line, 11 pt mono scaled up to 15 pt; trailing qualifiers truncate
    // first, never a number or a badge word)

    static func statusTemplates() -> [BadgedLine] {
        let px1 = NumberStyle.decimals(1, unit: "px", spokenUnit: "pixels"), px2 = NumberStyle.decimals(2, unit: "px", spokenUnit: "pixels")
        return [
            BadgedLine([.text("RENDERING… PASS"), .literal("2/2")]),
            BadgedLine([.text("σ HELD"), .value(.input(12, px1)), .text("→ R"), .value(.number(26.3, px1, .computed))]),
            BadgedLine([.text("σ HELD"), .value(.input(12, px1)), .text("→ σs"), .value(.number(8, px1, .computed)), .text("(MAX) · Δσ"),
                        .value(.number(-4, px1, .computed))]),
            BadgedLine([.text("σ HELD"), .value(.input(12, px1)), .text("→ a"), .value(.number(16, .integer(), .computed)), .text("(MAX) · σ"),
                        .value(.number(9.52, px2, .computed))]),
            BadgedLine([.text("σ HELD"), .value(.input(4, px1)), .text("→ r"), .value(.number(3, .integer(), .computed)), .text("(w"),
                        .value(.number(7, .integer(), .computed)), .text(", σ"), .value(.number(2, px2, .computed)), .text(")")]),
            BadgedLine.words("σ NOT DEFINED · RANK FILTER"),
            BadgedLine.words("σ NOT DEFINED · SYSTEM MATERIAL"),
            BadgedLine([.value(.number(32, .integer(noun: CountNoun("SAMPLE", "SAMPLES")), .computed)), .text("· CORNER GAP"),
                        .value(.number(4.08, NumberStyle.decimals(2, unit: "PX", spokenUnit: "pixels"), .computed)), .text("· GHOSTS")]),
            BadgedLine([.literal("2-D"), .text("DIRECT ABOVE σ"), .value(.number(8, .integer(), .computed)), .text("· USING SEPARABLE")]),
            BadgedLine([.value(.number(5, .integer(noun: CountNoun("BLADE", "BLADES")), .computed)), .text("· NOT CENTRALLY SYMMETRIC →"),
                        .literal("2-D"), .text("GATHER")]),
            BadgedLine([.text("TOO SLOW TO TIME · ≈"), .value(.number(700, NumberStyle.integer(unit: "ms", spokenUnit: "milliseconds"), .modeled))]),
            BadgedLine.words("TURN A CROWN · DRAG THE IMAGE · TAP A BLUR"),
            BadgedLine([.value(.number(74, .integer(), .computed)), .text("FETCHES ·"), .value(.number(2, .integer(), .computed)),
                        .text("PASSES · LINEAR-SAMPLED")]),
            BadgedLine([.text("MIN H  A"), .value(.number(-0.0012, .decimals(4), .computed)), .text("· B"),
                        .value(.number(-0.217, .decimals(3), .computed)), .text("· PARTS WAYS AT MATH")]),
            BadgedLine([.text("MAX"), .value(.number(6, NumberStyle.integer(unit: "LSB"), .live)), .text("· RMS"),
                        .value(.number(0.8, NumberStyle.decimals(1, unit: "LSB"), .live)), .literal("· ×16")]),
            BadgedLine.words("DRIVING B"),
            BadgedLine([.text("w"), .value(.number(41, .integer(), .computed)), .text("· σ"), .value(.number(11.83, px2, .computed))]),
            BadgedLine([.text("σ"), .value(.number(5.34, px2, .computed)), .text("·"), .value(.number(20, .integer(noun: CountNoun("FETCH", "FETCHES")), .computed))]),
        ]
    }

    /// The part of a status line that must stay visible: every segment up to the last badged number, plus the words that
    /// follow it up to the next ` · ` (its noun or unit). What comes after is a trailing qualifier and may truncate. Literal
    /// identifiers such as "2-D" are not numbers. A line without numbers keeps its first ` · ` part.
    static func essentialPrefix(_ line: BadgedLine) -> String {
        guard let last = line.segments.lastIndex(where: { if case .value = $0 { return true } else { return false } }) else {
            return line.text.components(separatedBy: " · ").first ?? line.text
        }
        var parts = line.segments[...last].map(\.text)
        if last + 1 < line.segments.count, case .text(let next) = line.segments[last + 1] {
            let noun = next.components(separatedBy: "·").first?.trimmingCharacters(in: .whitespaces) ?? ""
            if !noun.isEmpty { parts.append(noun) }
        }
        return parts.joined(separator: " ")
    }

    /// The status row's font size: 11 pt at the default size, scaled like caption2, capped at 15 pt.
    static func statusPoints(_ size: DynamicTypeSize) -> CGFloat { Swift.min(15, 11 * ContentTextScale.factor(.caption2, size)) }

    static func statusResults(screen: CGFloat, size: DynamicTypeSize) -> [Result] {
        let font = Font.system(size: statusPoints(size), design: .monospaced)
        return statusTemplates().map { line in
            let essential = essentialPrefix(line)
            return Result(subject: line.text, slot: essential == line.text ? "status row" : "status row (keeps '\(essential)')",
                          measured: lineWidth(Text(essential).font(font), size: size), reserved: windowWidth(screen))
        }
    }
}

/// A number slot's content alone (FloorNumberSlot's row, for measuring).
struct FloorNumberSlotContent: View {
    let row: LabeledValue
    @Environment(\.dynamicTypeSize) private var size
    var body: some View { ContentValueRow(row: row, stacked: FloorSlots.stackedRows(size)) }
}

/// An empty-state engraving measured at its natural height (the slot centres it).
struct EngravedLineMeasure: View {
    let text: String
    var body: some View {
        Text(text).contentFont(.engraving).multilineTextAlignment(.center).padding(ContentSpacing.section)
            .frame(maxWidth: .infinity)
    }
}
