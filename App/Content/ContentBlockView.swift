import SwiftUI
import BlurCore

// OWNER: CONTENT-VIEWS (frozen initialiser, ARCHITECTURE §5.11). Any content block of SPEC §5 `All … details`, the Field
// guide and the Trace panels: paragraph (readable prose), equation (callout mono, instrument cyan, units next to it, spoken
// with its symbols spelled out), values (LabeledValuesView), table (engraved header, mono cells, its badge), code
// (ShaderSourceView), figure (FigureView with its own data table), note (one engraved line with its badge), chips
// (wrapping capsules), sources (each citation, with a link when it has a URL) and disclosure (nested, closed by default).
public struct ContentBlockView: View {
    private let block: ContentBlock
    public init(_ block: ContentBlock) { self.block = block }

    public var body: some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .contentFont(.prose)
                .foregroundStyle(ContentInk.display.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .equation(let text):
            ContentHorizontalScroll {
                Text(text).contentFont(.rule).foregroundStyle(ContentInk.rule).fixedSize().padding(.vertical, 2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Equation: " + ContentAccessibility.spokenEquation(text))
        case .values(let rows):
            LabeledValuesView(rows)
        case .table(let table):
            ContentTableView(columns: table.columns, rows: table.rows, caption: table.caption, provenance: table.provenance)
        case .code(let code):
            ShaderSourceView(code)
        case .figure(let figure):
            FigureView(figure, height: 150)
        case .note(let text, let provenance):
            HStack(alignment: .firstTextBaseline, spacing: ContentSpacing.group) {
                Rectangle().fill(ContentInk.secondary.opacity(0.5)).frame(width: 2, height: 10)
                Text(text).contentFont(.engraving).foregroundStyle(ContentInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let provenance { HonestyBadge(provenance) }
            }
            .accessibilityElement(children: .combine)
        case .chips(let chips):
            ContentFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                    Text(chip)
                        .contentFont(.engraving)
                        .foregroundStyle(ContentInk.display.opacity(0.85))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.white.opacity(0.05), in: .capsule)
                        .overlay { Capsule().strokeBorder(ContentInk.hairline, lineWidth: 0.6) }
                        .fixedSize()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(chips.map { $0.lowercased() }.joined(separator: ", "))
        case .sources(let sources):
            VStack(alignment: .leading, spacing: 5) {
                Text("SOURCES").contentFont(.engraving).foregroundStyle(ContentInk.secondary)
                ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                    ContentSourceRow(source: source)
                }
            }
        case .disclosure(let title, let blocks):
            ContentDisclosure {
                Text(title).contentFont(.label).foregroundStyle(InstrumentPalette.actionCyan)
            } content: {
                VStack(alignment: .leading, spacing: ContentSpacing.section) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { ContentBlockView($0.element) }
                }
            }
        }
    }
}

/// One citation: the book glyph of REFERENCE, the text, and a link out when the source has a URL.
struct ContentSourceRow: View {
    let source: SourceRef
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("§").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(ContentInk.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(source.citation).contentFont(.caption).foregroundStyle(ContentInk.display.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                if let link = source.url, let url = URL(string: link) {
                    Link(destination: url) {
                        HStack(spacing: 3) {
                            Text(url.host() ?? link).contentFont(.engraving)
                            Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .semibold))
                        }
                        .foregroundStyle(InstrumentPalette.actionCyan)
                    }
                    .accessibilityLabel("Open \(url.host() ?? "source") in Safari")
                }
            }
        }
    }
}
