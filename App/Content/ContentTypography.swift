import SwiftUI

// OWNER: CONTENT-VIEWS. The type roles of every content renderer (Metro §4): rounded numerals belong to the instruments,
// monospaced labels carry units and engineering context, a serif italic line carries meaning. One place decides every font
// App/Content uses, so slot reservations (FloorSlots) and the text-fit AppTests measure exactly what is drawn.
//
// `ContentTextScale` is Apple's Dynamic Type table (points per text style and size category, HIG "Dynamic Type sizes").
// The renderers use it for the few graphic dimensions that must grow with text (figure heights, stem tips, texel labels),
// so a figure's text and its frame scale together. Fonts themselves are the system text styles.

/// The type roles of App/Content.
enum ContentRole: CaseIterable, Sendable {
    /// "FLOOR 4 · KERNEL": caption, monospaced, semibold, tracking 1.4, instrument cyan.
    case eyebrow
    /// The floor's question (SPEC §4.3: body semibold).
    case question
    /// The catalog signature: footnote serif italic (the human register, quiet because it repeats on every floor).
    case signature
    /// Small engraved labels: "GOVERNING RULE", "IN THIS APP", axis titles, legends (caption2 mono, tracking 1.2).
    case engraving
    /// A governing rule or equation: callout monospaced (Metro §4 "Equation").
    case rule
    /// LabeledValue labels: caption monospaced, tracking 1.0.
    case label
    /// Explanation prose: subheadline.
    case prose
    /// The `IN THIS APP` sentence and captions under figures: caption.
    case caption
    /// Shader source and code blocks: caption monospaced.
    case code
    /// Table header cells: caption2 monospaced semibold, tracking 1.0.
    case tableHeader
    /// Table body cells: caption monospaced, monospaced digits.
    case tableCell
    /// Tick labels and in-figure numerals: caption2 monospaced, monospaced digits.
    case tick
    /// A badged number in a row: callout monospaced (the value), with its unit in `tick`.
    case value

    var textStyle: Font.TextStyle {
        switch self {
        case .eyebrow, .label, .caption, .code, .tableCell: .caption
        case .question: .body
        case .signature: .footnote
        case .engraving, .tableHeader, .tick: .caption2
        case .rule, .value: .callout
        case .prose: .subheadline
        }
    }
    var design: Font.Design {
        switch self {
        case .question, .prose, .caption: .default
        case .signature: .serif
        default: .monospaced
        }
    }
    var weight: Font.Weight {
        switch self {
        case .eyebrow, .question, .tableHeader: .semibold
        default: .regular
        }
    }
    var tracking: CGFloat {
        switch self {
        case .eyebrow: 1.4
        case .engraving: 1.2
        case .label, .tableHeader: 1.0
        default: 0
        }
    }
    var italic: Bool { self == .signature }

    /// The font this role draws with at `size` (the system text style; `size` matters only for harness builds).
    func font(_ size: DynamicTypeSize) -> Font {
        #if B2_CONTENT_HARNESS
        var f = Font.system(size: ContentTextScale.points(textStyle, size), weight: weight, design: design)
        #else
        var f = Font.system(textStyle, design: design, weight: weight)
        #endif
        if italic { f = f.italic() }
        return f
    }
}

private struct ContentRoleModifier: ViewModifier {
    let role: ContentRole
    @Environment(\.dynamicTypeSize) private var size
    func body(content: Content) -> some View {
        content.font(role.font(size)).tracking(role.tracking)
    }
}

extension View {
    /// Applies a content type role (font and tracking).
    func contentFont(_ role: ContentRole) -> some View { modifier(ContentRoleModifier(role: role)) }
}

/// Apple's Dynamic Type table (points), used for graphic dimensions that grow with text.
enum ContentTextScale {
    private static let order: [DynamicTypeSize] = [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
                                                   .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5]
    private static let table: [Font.TextStyle: [CGFloat]] = [
        .largeTitle: [31, 32, 33, 34, 36, 38, 40, 44, 48, 52, 56, 60],
        .title: [25, 26, 27, 28, 30, 32, 34, 38, 43, 48, 53, 58],
        .title2: [19, 20, 21, 22, 24, 26, 28, 34, 39, 44, 50, 56],
        .title3: [17, 18, 19, 20, 22, 24, 26, 31, 37, 43, 49, 55],
        .headline: [14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53],
        .body: [14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53],
        .callout: [13, 14, 15, 16, 18, 20, 22, 26, 32, 38, 44, 51],
        .subheadline: [12, 13, 14, 15, 17, 19, 21, 25, 30, 36, 42, 49],
        .footnote: [12, 12, 12, 13, 15, 17, 19, 23, 27, 33, 38, 44],
        .caption: [11, 11, 11, 12, 14, 16, 18, 22, 26, 32, 37, 43],
        .caption2: [11, 11, 11, 11, 13, 15, 17, 20, 24, 29, 34, 40],
    ]

    static func points(_ style: Font.TextStyle, _ size: DynamicTypeSize) -> CGFloat {
        let row = table[style] ?? table[.body] ?? [17]
        let i = order.firstIndex(of: size) ?? 3
        return row[Swift.min(i, row.count - 1)]
    }

    /// The factor `style` grows by at `size` relative to the default (Large) size.
    static func factor(_ style: Font.TextStyle, _ size: DynamicTypeSize) -> CGFloat {
        points(style, size) / points(style, .large)
    }

    /// The same factor, capped (figures grow with their labels up to `cap`, then their labels reflow instead).
    static func figureFactor(_ size: DynamicTypeSize, cap: CGFloat = 1.6) -> CGFloat {
        Swift.min(cap, Swift.max(1, factor(.caption2, size)))
    }
}

/// Metro's 4-point spacing family (Metro §5) as used by the content renderers.
enum ContentSpacing {
    static let inline: CGFloat = 4
    static let group: CGFloat = 8
    static let section: CGFloat = 12
    static let block: CGFloat = 16
}

/// Ink roles of the content renderers, all from the Metro palette (never re-typed literals).
enum ContentInk {
    static let display = InstrumentPalette.displayInk
    static let secondary = InstrumentPalette.secondaryInk
    static let rule = InstrumentPalette.instrumentCyan
    static let eyebrow = InstrumentPalette.instrumentCyan
    static let primary = InstrumentPalette.wave
    static let depth = InstrumentPalette.waveDepth
    static let negative = InstrumentPalette.spectrumDepth
    /// Compare B, C, D differ by stroke (dashed, dotted, dash-dot) first; their inks stay clear of the negative-lobe
    /// magenta so a dashed B never reads as a negative lobe.
    static let comparisonB = InstrumentPalette.displayInk.opacity(0.78)
    static let comparisonC = InstrumentPalette.carrier
    static let comparisonD = InstrumentPalette.waveDepth
    static let measured = InstrumentPalette.instrumentAmber
    static let probe = InstrumentPalette.instrumentAmber
    static let marker = InstrumentPalette.carrier
    /// Quiet reference traces, grid lines and engraved strokes (Metro's white-opacity ink system).
    static let quiet = Color.white.opacity(0.38)
    static let grid = Color.white.opacity(0.07)
    static let hairline = Color.white.opacity(0.12)
}
