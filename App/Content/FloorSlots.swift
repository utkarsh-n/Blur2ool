import SwiftUI
import BlurCore

// OWNER: CONTENT-VIEWS. Fixed slot heights per floor (SPEC §5.0 rule 7; METRO §F.1 item 2): every slot of a floor page
// reserves the height of the LARGEST content any blur puts on that floor at the current Dynamic Type size and width, so
// switching blurs moves nothing. A slot is a reserve drawn hidden underneath its content (a ZStack), so the reserve grows
// with Dynamic Type exactly as the text does, and content that would not fit grows the slot instead of being cut
// (nothing is ever truncated; the text-fit AppTests catch any content that exceeds its reserve).
//
// What each slot reserves:
// - header: the eyebrow plus the three widest badge words (a page shows its dominant badges there);
// - signature: the longest catalog signatures in the registry (plus the page's own);
// - rule: two lines of the rule font (three from xLarge);
// - figure: a per-floor height (the largest figure kind any blur uses there), grown with the caption size up to 1.6×;
// - numbers: six row slots, each one row with a caption line (SPEC §5.0 rule 2: at most six numbers);
// - IN THIS APP: five lines of the caption font (seven from xLarge).
// `All … details` is the only element that grows (SPEC §5.0 rule 2).

enum FloorSlotKind: String, CaseIterable, Sendable { case header, question, signature, tabs, rule, figure, numbers, inThisApp }

enum FloorSlots {
    /// Figure slot height at the default size: the largest figure kind any blur puts on the floor (SPEC §5.1, §5.2).
    static func figureBaseHeight(_ floor: Floor) -> CGFloat {
        switch floor {
        case .slide: 200        // tool bars: reserved by their exemplar (nine tools, captions), see figure slot
        case .api: 176          // the call as code, or the measured-law plot
        case .math: 184         // signed H plot with legend, or a signed 2-D H map with its legend
        case .kernel: 216       // stems, a 2-D weight map, or a 7 × 7 PSF field
        case .algorithm: 340    // pass tiles in up to two rows + the cost plot
        case .gpu: 264          // shader excerpt, or the dispatch overlay (200 pt copy) with its mode picker
        case .pixels: 236       // IN | OUT texel grids
        }
    }

    static func figureHeight(_ floor: Floor, _ size: DynamicTypeSize) -> CGFloat {
        // The tool bars are rows of text: their slot grows with the label size up to 2×, the graphic figures' up to 1.6×.
        let cap: CGFloat = floor == .slide ? 2 : 1.6
        return (figureBaseHeight(floor) * ContentTextScale.figureFactor(size, cap: cap)).rounded()
    }

    static let numberSlots = 6

    /// Rows switch to two lines (label above value) from xLarge, so every row slot on a page has one height.
    static func stackedRows(_ size: DynamicTypeSize) -> Bool { size >= .xLarge }

    static func ruleLines(_ size: DynamicTypeSize) -> Int { size >= .xLarge ? 3 : 2 }
    static func inThisAppLines(_ size: DynamicTypeSize) -> Int { size >= .xLarge ? 7 : 5 }

    /// The row every number slot reserves: a long label, a grouped value with a unit, the longest badge word, a caption.
    static let numberExemplar = LabeledValue(
        id: "reserve", label: "THREADGROUP MEMORY",
        value: .number(32_768, NumberStyle.integer(unit: "B", spokenUnit: "bytes"), .reference,
                       source: SourceRef("reserve"), caption: "TWO PASSES · READ ONCE, WRITE ONCE"))

    /// A row whose words fill the line, so it takes two lines without a caption.
    static let wideNumberExemplar = LabeledValue(id: "reserve-wide", label: "FUNCTION",
                                                 value: .words("b2_f2_gauss_linear_fs", .reference, source: SourceRef("reserve")))

    /// The tool bars the SLIDE floor reserves room for: nine tools, five with captions (SPEC §5.1 floor 1).
    static let toolBarsExemplar: ToolBarsSpec = {
        let px = NumberStyle.decimals(2, unit: "px")
        let names = ["SwiftUI .blur", "CSS blur()", "Figma layer blur", "CIGaussianBlur", "MPSImageGaussianBlur",
                     "Android RenderEffect", "GIMP legacy blur", "Photoshop Gaussian", "After Effects blurriness"]
        let rows = names.enumerated().map { i, name in
            LabeledValue(id: "t\(i)", label: name,
                         value: .number(12.34, px, .measured, qualifiers: .notThisDevice, source: SourceRef("reserve"),
                                        device: DeviceStamp(deviceModel: "reserve", gpuName: "", gpuFamily: "", osVersion: "", osBuild: "",
                                                            isSimulator: false, date: Date(timeIntervalSince1970: 0), thermal: .nominal,
                                                            lowPowerMode: false),
                                        caption: i % 2 == 0 ? "SAME σ, DIFFERENT KERNEL" : nil))
        }
        return ToolBarsSpec(rows: rows, homeToolID: "t0", reverseMode: false)
    }()

    /// The badges the header reserves room for (the three widest words).
    static let headerBadgeExemplar: [Provenance] = [.reference, .measured, .computed]

    /// The longest catalog signatures (by characters), the signature slot's reserve candidates.
    static let signatureCandidates: [String] = {
        // The registry's signatures, plus the catalog signatures the fixtures quote (verbatim CATALOG §2 text).
        let all = BlurRegistry.operators.map(\.entry.signature) + ContentFixtures.catalogSignatures
        return Array(all.sorted { $0.count > $1.count }.prefix(3))
    }()
}

/// Draws `reserve` hidden underneath `content`: the slot is as tall as the taller of the two.
/// At accessibility sizes there is no reserve: sections simply grow with their text (SPEC §4.1.10, §4.3).
struct ContentReservedSlot<Content: View, Reserve: View>: View {
    let content: Content
    let reserve: Reserve
    @Environment(\.dynamicTypeSize) private var size
    init(@ViewBuilder content: () -> Content, @ViewBuilder reserve: () -> Reserve) {
        self.content = content(); self.reserve = reserve()
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            if !size.isAccessibilitySize { reserve.hidden().accessibilityHidden(true) }
            content.frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)       // rigid: its height is always the taller of the two
    }
}

/// `n` lines of a role's font, for reserves.
struct ContentReservedLines: View {
    let role: ContentRole
    let lines: Int
    var body: some View {
        // Tall glyphs (σ, ², ⌈, √, Σ, ∩) come from fallback fonts with taller lines: every reserved line carries them.
        Text(Array(repeating: "Mg⌈σ²√Σ∩÷", count: Swift.max(1, lines)).joined(separator: "\n")).contentFont(role)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Slot contents and reserves (separate views so the text-fit AppTests can measure each)

/// Eyebrow and dominant badges.
struct FloorHeaderContent: View {
    let eyebrow: String
    let badges: [Provenance]
    @Environment(\.dynamicTypeSize) private var size

    /// The eyebrow on its own line and the dominant badges on the next (two fixed lines: up to three badge words never
    /// squeeze the eyebrow, and a page with one badge has the same geometry as a page with three).
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            eyebrowText
            badgeFlow(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eyebrowText: some View {
        Text(eyebrow)
            .contentFont(.eyebrow)
            .foregroundStyle(ContentInk.eyebrow)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    /// Badges wrap into rows in the width the eyebrow leaves; a badge word is never compressed or broken.
    private func badgeFlow(_ alignment: HorizontalAlignment) -> some View {
        ContentFlowLayout(spacing: 4, lineSpacing: 4, alignment: alignment) {
            ForEach(badges, id: \.self) { HonestyBadge($0).fixedSize() }
        }
    }
}

struct FloorHeaderReserve: View {
    let eyebrow: String
    var body: some View { FloorHeaderContent(eyebrow: eyebrow, badges: FloorSlots.headerBadgeExemplar) }
}

struct FloorQuestionContent: View {
    let question: String
    var body: some View {
        Text(question)
            .contentFont(.question)
            .foregroundStyle(ContentInk.display)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FloorSignatureContent: View {
    let signature: String
    var body: some View {
        Text(signature)
            .contentFont(.signature)
            .foregroundStyle(ContentInk.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FloorSignatureReserve: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(FloorSlots.signatureCandidates, id: \.self) { FloorSignatureContent(signature: $0) }
        }
    }
}

struct FloorRuleContent: View {
    let rule: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("GOVERNING RULE").contentFont(.engraving).foregroundStyle(ContentInk.secondary)
            if let rule {
                Text(rule)
                    .contentFont(.rule)
                    .foregroundStyle(ContentInk.rule)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(ContentAccessibility.spokenEquation(rule))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct FloorRuleReserve: View {
    @Environment(\.dynamicTypeSize) private var size
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("GOVERNING RULE").contentFont(.engraving)
            ContentReservedLines(role: .rule, lines: FloorSlots.ruleLines(size))
        }
    }
}

struct FloorInThisAppContent: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("IN THIS APP").contentFont(.engraving).foregroundStyle(ContentInk.secondary)
            Text(ContentLogic.inThisAppSentence(text))
                .contentFont(.caption)
                .foregroundStyle(ContentInk.display.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

struct FloorInThisAppReserve: View {
    @Environment(\.dynamicTypeSize) private var size
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("IN THIS APP").contentFont(.engraving)
            ContentReservedLines(role: .caption, lines: FloorSlots.inThisAppLines(size))
        }
    }
}

/// One of the six number slots: a row over the exemplar reserve, or an empty channel (a faint engraved baseline).
struct FloorNumberSlot: View {
    let row: LabeledValue?
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        ContentReservedSlot {
            if let row {
                ContentValueRow(row: row, stacked: FloorSlots.stackedRows(size))
            } else {
                VStack {
                    Spacer(minLength: 0)
                    ContentHairline().stroke(ContentInk.hairline.opacity(0.6), style: StrokeStyle(lineWidth: 0.6, dash: [1, 3])).frame(height: 1)
                    Spacer(minLength: 0)
                }
                .accessibilityHidden(true)
            }
        } reserve: {
            FloorNumberReserve()
        }
    }
}

struct FloorNumberReserve: View {
    @Environment(\.dynamicTypeSize) private var size
    var body: some View {
        // The taller of a captioned row and an uncaptioned row whose number is too wide to sit beside its label.
        ZStack(alignment: .topLeading) {
            ContentValueRow(row: FloorSlots.numberExemplar, stacked: FloorSlots.stackedRows(size))
            ContentValueRow(row: FloorSlots.wideNumberExemplar, stacked: true)
        }
    }
}

/// A horizontal hairline through the middle of its frame (an unused number channel).
struct ContentHairline: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: rect.minX, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)); return p
    }
}

enum ContentAccessibility {
    /// An equation as VoiceOver should read it: operators and Greek letters spelled out.
    static func spokenEquation(_ s: String) -> String {
        var t = s
        for (a, b) in [("σ", " sigma "), ("ν", " nu "), ("π", " pi "), ("Σ", " sum of "), ("√", " square root of "), ("−", " minus "),
                       ("×", " times "), ("÷", " divided by "), ("≤", " at most "), ("≥", " at least "), ("≈", " about "),
                       ("→", " becomes "), ("⇒", " implies "), ("∪", " union "), ("∗", " convolved with "), ("²", " squared "),
                       ("⌈", " ceiling of "), ("⌉", " "), ("⌊", " floor of "), ("⌋", " "), ("·", " times ")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        return t.replacingOccurrences(of: "  +", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
}
