import SwiftUI
import BlurCore

// OWNER: CONTENT-VIEWS (frozen initialiser, ARCHITECTURE §5.11, §6.6). Source text shown exactly as compiled (SPEC §4.3
// floor 6 Shader: REFERENCE, "it is the code"): syntax-coloured from the Metro palette, monospaced, scrolling sideways (the
// page scrolls vertically, so this is no nested same-axis scroll), line numbers in a gutter. Lines that carry an
// explanation (the block's annotations or an `// @explain:` comment in the source) are marked `@` in cyan; tapping one shows
// its one-line explanation. Lines that mention TRACE_PROBE (traced builds) are banded amber and marked `T`. The SHA-256
// that matches the Run's provenance is printed in full under the listing.
//
// ShaderSourceView is the full listing (it grows; it lives in `All … details` and the Field guide). In a figure slot of
// fixed height the excerpt (ShaderExcerptFigure) shows the window of lines around the first marked line and keeps the
// explanation in a fixed callout under it.

public struct ShaderSourceView: View {
    private let code: CodeBlock
    public init(_ code: CodeBlock) { self.code = code }

    public var body: some View {
        ShaderListing(code: code, window: nil, inlineExplanations: true)
            .padding(10)
            .contentPlotInset()
    }
}

/// The excerpt shown in a figure slot of `height` points.
struct ShaderExcerptFigure: View {
    let code: CodeBlock
    let height: CGFloat
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        let lineHeight = ShaderListing.lineHeight(size)
        let chrome = ContentTextScale.points(.caption2, size) * 1.3 * 2 + ShaderListing.calloutHeight(size) + 18 + 20
        let count = Swift.max(3, Int(((height - chrome) / lineHeight).rounded(.down)))
        ShaderListing(code: code, window: ContentLogic.excerptWindow(code, count: count), inlineExplanations: false)
            .padding(10)
            .frame(height: height, alignment: .top)
            .contentPlotInset()
    }
}

struct ShaderListing: View {
    let code: CodeBlock
    let window: Range<Int>?
    let inlineExplanations: Bool
    @State private var openLine: Int?
    @Environment(\.dynamicTypeSize) private var size

    static func lineHeight(_ size: DynamicTypeSize) -> CGFloat { (ContentTextScale.points(.caption, size) * 1.32).rounded(.up) }
    static func calloutHeight(_ size: DynamicTypeSize) -> CGFloat { ContentTextScale.points(.caption, size) * 1.3 * 2 + 6 }

    var body: some View {
        let all = code.text.components(separatedBy: "\n")
        let shown = window ?? 0..<all.count
        let explanations = ContentLogic.explanations(code)
        let traced = ContentLogic.traceLines(code)
        let digits = String(all.count).count
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(code.language.uppercased()).contentFont(.engraving).foregroundStyle(ContentInk.display).fixedSize()
                Text(window == nil ? "\(all.count) LINES" : "LINES \(shown.lowerBound + 1)–\(shown.upperBound) OF \(all.count)")
                    .contentFont(.engraving).foregroundStyle(ContentInk.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if window == nil {
                    if !traced.isEmpty { legendChip("T", "TRACE_PROBE", ink: ContentInk.probe) }
                    if !explanations.isEmpty { legendChip("@", "EXPLAINED", ink: InstrumentPalette.actionCyan) }
                }
            }
            .accessibilityHidden(true)
            ContentHorizontalScroll {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(shown), id: \.self) { i in
                        let n = i + 1
                        ShaderLine(number: n, digits: digits, text: all[i], language: code.language,
                                   explanation: explanations[n], traced: traced.contains(n), isOpen: openLine == n,
                                   showInlineExplanation: inlineExplanations) {
                            if explanations[n] != nil { openLine = openLine == n ? nil : n }
                        }
                    }
                }
                .padding(.trailing, 8)
            }
            if !inlineExplanations {
                callout(explanations)
            }
            shaLine
        }
    }

    private func legendChip(_ glyph: String, _ text: String, ink: Color) -> some View {
        HStack(spacing: 3) {
            Text(glyph).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(ink)
            Text(text).contentFont(.engraving).foregroundStyle(ContentInk.secondary)
        }
    }

    /// The fixed callout under an excerpt: the open line's explanation, or how to get one.
    private func callout(_ explanations: [Int: String]) -> some View {
        Group {
            if let n = openLine, let e = explanations[n] {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("LINE \(n)").contentFont(.engraving).foregroundStyle(InstrumentPalette.actionCyan).fixedSize()
                    Text(e).contentFont(.caption).foregroundStyle(ContentInk.display)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if !explanations.isEmpty { legendChip("@", "TAP FOR ITS EXPLANATION", ink: InstrumentPalette.actionCyan) }
                    if !ContentLogic.traceLines(code).isEmpty { legendChip("T", "TRACE_PROBE", ink: ContentInk.probe) }
                    if explanations.isEmpty && ContentLogic.traceLines(code).isEmpty {
                        Text("NO EXPLAINED LINES IN THIS EXCERPT").contentFont(.engraving).foregroundStyle(ContentInk.secondary)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: ShaderListing.calloutHeight(size), alignment: .topLeading)
        .padding(.horizontal, 6)
        .background(Color.white.opacity(0.03), in: .rect(cornerRadius: 6))
    }

    private var shaLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("SHA-256").contentFont(.engraving).foregroundStyle(ContentInk.secondary).fixedSize()
            if let sha = code.sha256 {
                Text(sha).contentFont(.tick).foregroundStyle(ContentInk.display.opacity(0.85))
                    .lineLimit(window == nil ? nil : 1).truncationMode(.middle)
                    .textSelection(.enabled)
                    .accessibilityLabel("SHA-256 " + sha.prefix(8).map(String.init).joined(separator: " ") + " and so on")
            } else {
                Text("NOT STAMPED · EXCERPT").contentFont(.engraving).foregroundStyle(ContentInk.secondary)
            }
        }
    }
}

/// One source line: gutter number, marker, coloured code; tap toggles its explanation.
struct ShaderLine: View {
    let number: Int
    let digits: Int
    let text: String
    let language: String
    let explanation: String?
    let traced: Bool
    let isOpen: Bool
    let showInlineExplanation: Bool
    let toggle: () -> Void
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(String(number)).contentFont(.code).monospacedDigit().foregroundStyle(ContentInk.secondary.opacity(0.6))
                    .frame(width: CGFloat(digits) * ContentTextScale.points(.caption, size) * 0.62 + 4, alignment: .trailing)
                Text(marker).font(.system(size: ContentTextScale.points(.caption2, size), weight: .bold, design: .monospaced))
                    .foregroundStyle(traced ? ContentInk.probe : InstrumentPalette.actionCyan)
                    .frame(width: ContentTextScale.points(.caption, size) * 1.1)
                Text(ShaderLine.attributed(text, language: language)).contentFont(.code).fixedSize()
            }
            .frame(minHeight: ShaderListing.lineHeight(size), alignment: .leading)
            .background(alignment: .leading) {
                if traced || isOpen {
                    Rectangle().fill(traced ? ContentInk.probe.opacity(0.11) : InstrumentPalette.actionCyan.opacity(0.08))
                }
            }
            if showInlineExplanation, isOpen, let explanation {
                Text("↳ " + explanation).contentFont(.caption).foregroundStyle(InstrumentPalette.actionCyan)
                    .padding(.leading, CGFloat(digits) * ContentTextScale.points(.caption, size) * 0.62 + 4 + ContentTextScale.points(.caption, size) * 1.1)
                    .padding(.vertical, 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Line \(number)\(traced ? ", trace probe" : ""): " + ContentLogic.codeWithoutExplain(text).trimmingCharacters(in: .whitespaces))
        .accessibilityValue(explanation.map { "Explanation: \($0)" } ?? "")
        .accessibilityAction(named: "Show explanation") { toggle() }
    }

    private var marker: String {
        if traced { return "T" }
        return explanation == nil ? " " : "@"
    }

    static func attributed(_ line: String, language: String) -> AttributedString {
        var out = AttributedString()
        for token in ContentLogic.tokenize(line, language: language) {
            var part = AttributedString(token.text)
            part.foregroundColor = ShaderLine.ink(token.kind)
            out += part
        }
        return out
    }

    static func ink(_ kind: ContentLogic.TokenKind) -> Color {
        switch kind {
        case .plain: ContentInk.display.opacity(0.9)
        case .keyword: InstrumentPalette.spectrum
        case .type: InstrumentPalette.wave
        case .number: InstrumentPalette.carrier
        case .comment: ContentInk.secondary.opacity(0.75)
        case .explain: InstrumentPalette.instrumentCyan.opacity(0.8)
        case .string: InstrumentPalette.actionAmber
        case .preprocessor: InstrumentPalette.spectrumDepth
        case .attribute: ContentInk.secondary
        case .function: ContentInk.display
        }
    }
}
