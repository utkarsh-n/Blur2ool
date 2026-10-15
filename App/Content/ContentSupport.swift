import SwiftUI
import BlurCore

// OWNER: CONTENT-VIEWS. Small shared pieces of the content renderers: a wrapping flow layout (chips, badges), the
// disclosure default (the gallery opens every disclosure for its screenshots), the figure backdrop (the screen that owns
// the output texture hands floor 6 a COPY of it to draw the dispatch overlay over), the plot-inset frame, and a renderer
// for BadgedLine (every number in it badged, digits elsewhere only as literals).

/// Lays its subviews out in rows, wrapping to the next row when one does not fit (chips, badge groups).
struct ContentFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(Swift.max(0, rows.count - 1))
        return CGSize(width: proposal.width.map { Swift.min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(bounds.width, subviews) {
            var x = alignment == .trailing ? bounds.maxX - row.width : bounds.minX
            for (index, size) in row.items {
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), anchor: .topLeading,
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var items: [(Int, CGSize)] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, view) in subviews.enumerated() {
            var size = view.sizeThatFits(.unspecified)
            if size.width > maxWidth { size = view.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil)) }
            let extra = rows[rows.count - 1].items.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > maxWidth + 0.5 && !rows[rows.count - 1].items.isEmpty { rows.append(Row()) }
            let last = rows.count - 1
            rows[last].width += rows[last].items.isEmpty ? size.width : size.width + spacing
            rows[last].height = Swift.max(rows[last].height, size.height)
            rows[last].items.append((i, size))
        }
        return rows.filter { !$0.items.isEmpty }
    }
}

/// Whether the content renderers' disclosures (`All … details`, data tables, nested disclosures) start open. The
/// `content-gallery` scenario opens them so its screenshots show every block kind; everywhere else they start closed.
struct ContentDisclosureDefaultKey: EnvironmentKey { static let defaultValue = false }

/// Whether the figures' data tables start open (they are long; the gallery opens them only with `-B2Param tables=open`).
struct ContentDataTablesOpenKey: EnvironmentKey { static let defaultValue = false }

/// A copy of the output the dispatch overlay is drawn over (SPEC §5.1 floor 6: never drawn on the specimen itself). The
/// screen that holds the output texture sets it; without it the overlay draws the dispatch geometry on the plot inset.
struct FigureBackdropKey: EnvironmentKey { static let defaultValue: CGImage? = nil }

extension EnvironmentValues {
    var contentDisclosuresOpen: Bool {
        get { self[ContentDisclosureDefaultKey.self] }
        set { self[ContentDisclosureDefaultKey.self] = newValue }
    }
    var contentDataTablesOpen: Bool {
        get { self[ContentDataTablesOpenKey.self] }
        set { self[ContentDataTablesOpenKey.self] = newValue }
    }
    /// A copy of the current output image for the floor 6 dispatch overlay (public so UI-LAYERS can set it).
    public var figureBackdrop: CGImage? {
        get { self[FigureBackdropKey.self] }
        set { self[FigureBackdropKey.self] = newValue }
    }
}

extension View {
    /// Hands the floor 6 dispatch overlay a COPY of the output to draw over (UI-LAYERS; never the specimen texture itself).
    public func figureBackdrop(_ image: CGImage?) -> some View { environment(\.figureBackdrop, image) }
}

/// A DisclosureGroup whose initial state follows `contentDisclosuresOpen`, styled for content panels.
struct ContentDisclosure<Label: View, Body: View>: View {
    private let label: Label
    private let content: () -> Body
    private let isDataTable: Bool
    @Environment(\.contentDisclosuresOpen) private var openByDefault
    @Environment(\.contentDataTablesOpen) private var tablesOpenByDefault
    @State private var expanded: Bool?

    init(isDataTable: Bool = false, @ViewBuilder label: () -> Label, @ViewBuilder content: @escaping () -> Body) {
        self.label = label(); self.content = content; self.isDataTable = isDataTable
    }

    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { expanded ?? (isDataTable ? tablesOpenByDefault : openByDefault) },
                                            set: { expanded = $0 })) {
            content().padding(.top, ContentSpacing.group)
        } label: {
            label
        }
        .tint(InstrumentPalette.actionCyan)
    }
}

extension ContentDisclosure where Label == Text {
    init(_ title: String, @ViewBuilder content: @escaping () -> Body) {
        self.init(label: { Text(title) }, content: content)
    }
}

/// Content wider than the panel scrolls sideways (code, tables, equations); the page scrolls vertically, so this is never
/// a nested same-axis scroll. The scroll view owns the touches that begin on it.
struct ContentHorizontalScroll<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        #if B2_CONTENT_HARNESS
        // The Mac preview harness renders with ImageRenderer, which cannot draw a UIScrollView: show the leading part.
        ContentLeadingClipLayout { content.fixedSize() }.clipped()
        #else
        ScrollView(.horizontal, showsIndicators: false) { content }
            .instrumentControlOwnsTouches(identifier: "contentHorizontalScroll")
        #endif
    }
}

#if B2_CONTENT_HARNESS
/// Harness only: takes the offered width and shows its content's leading part.
struct ContentLeadingClipLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: proposal.width ?? ideal.width, height: ideal.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let first = subviews.first else { return }
        first.place(at: bounds.origin, anchor: .topLeading, proposal: .unspecified)
    }
}
#endif

/// The quiet plot inset every figure sits on (Metro §6: plot colour, radius 10, white 0.075 border at 0.6 pt).
struct ContentPlotInset: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content
            .background(InstrumentPalette.plot, in: .rect(cornerRadius: InstrumentMetrics.plotRadius))
            .overlay {
                RoundedRectangle(cornerRadius: InstrumentMetrics.plotRadius)
                    .strokeBorder(.white.opacity(contrast == .increased ? 0.2 : 0.075), lineWidth: InstrumentMetrics.plotStroke)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func contentPlotInset() -> some View { modifier(ContentPlotInset()) }
}

/// One engraved line, centred in its slot: honest empty states ("N/A · RANK") and figure notes.
struct ContentEngravedLine: View {
    let text: String
    var dashed = true
    var body: some View {
        Text(text)
            .contentFont(.engraving)
            .foregroundStyle(ContentInk.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(ContentSpacing.section)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if dashed {
                    RoundedRectangle(cornerRadius: InstrumentMetrics.plotRadius)
                        .strokeBorder(ContentInk.hairline, style: StrokeStyle(lineWidth: 0.6, dash: [3, 3]))
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel(text.lowercased())
    }
}

/// A BadgedLine as text: words in secondary ink, literals and badged values in display ink, one badge per number (the
/// glyph-free word form would not fit a line; the full phrase is spoken).
struct ContentBadgedLineText: View {
    let line: BadgedLine
    var role: ContentRole = .engraving

    var body: some View {
        ContentFlowLayout(spacing: 5, lineSpacing: 3) {
            ForEach(Array(line.segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let s):
                    Text(s).contentFont(role).foregroundStyle(ContentInk.secondary)
                case .literal(let s):
                    Text(s).contentFont(role).foregroundStyle(ContentInk.display).monospacedDigit()
                case .value(let v):
                    BadgedValueText(v, layout: .inline).fixedSize()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.spoken)
    }
}
