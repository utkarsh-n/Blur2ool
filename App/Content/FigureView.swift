import SwiftUI
import BlurCore

// OWNER: CONTENT-VIEWS (frozen initialiser, ARCHITECTURE §5.11 / AppContract/Content). Any figure in a reserved slot of
// `height` points (plot inset 374 × 140 by default on floor pages, SPEC §4.3). Every kind has a spoken equivalent with the
// same numbers (SPEC §14): plots carry an AXChartDescriptor and a DisclosureGroup data table; heat maps, texel grids and
// PSF fields carry tables; colour is never the only cue (hatching, dashes, outlines, words).
//
// Kinds: .plot (Swift Charts, PlotFigure), .heatmap (HeatmapFigure), .texelGrid (TexelGridFigure), .dispatchOverlay
// (DispatchOverlayFigure, over a COPY of the output), .passTiles (PassTilesFigure via InstrumentEventTiles), .psfField
// (PSFFieldFigure), .toolBars (ToolBarsFigure), .code (ShaderExcerptFigure) and .pair. A pair of square figures sits side
// by side; any other pair stacks (pass tiles above the cost plot). In a pair of texel grids the first is IN, the second OUT.
public struct FigureView: View {
    private let figure: FigureSpec
    private let height: CGFloat
    private let onPassSelected: (Int?) -> Void
    @Environment(\.figureDataTableInline) private var tableInline

    public init(_ figure: FigureSpec, height: CGFloat = 140, onPassSelected: @escaping (Int?) -> Void = { _ in }) {
        self.figure = figure; self.height = height; self.onPassSelected = onPassSelected
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ContentSpacing.group) {
            FigureSlotContent(figure: figure, height: height, role: nil, onPassSelected: onPassSelected)
            if tableInline && FigureDataTable.hasTable(figure) {
                FigureDataTable(figure: figure)
            }
        }
    }
}

/// Whether FigureView shows its own data-table disclosure under the figure (true), or a host (the floor page) lists it in
/// `All … details` instead (false).
struct FigureDataTableInlineKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    var figureDataTableInline: Bool {
        get { self[FigureDataTableInlineKey.self] }
        set { self[FigureDataTableInlineKey.self] = newValue }
    }
}

/// The role a texel grid plays inside a pair (floor 7 IN | OUT).
enum TexelGridRole: String { case input = "IN", output = "OUT" }

/// One figure drawn into a slot of `height` points (nil: the figure takes the height its parent proposes). Graphic figures
/// fill the slot; text-led figures (tool bars, pass tiles) take their natural height and the slot grows if they need more
/// (they never draw over the rows below).
struct FigureSlotContent: View {
    let figure: FigureSpec
    let height: CGFloat?
    let role: TexelGridRole?
    let onPassSelected: (Int?) -> Void

    var body: some View {
        switch figure {
        case .plot(let plot): graphic(PlotFigure(plot: plot))
        case .heatmap(let spec): graphic(HeatmapFigure(spec: spec))
        case .texelGrid(let spec): graphic(TexelGridFigure(spec: spec, role: role))
        case .dispatchOverlay(let spec): graphic(DispatchOverlayFigure(spec: spec))
        case .psfField(let spec): graphic(PSFFieldFigure(spec: spec))
        case .passTiles(let spec):
            if let height {
                PassTilesFigure(spec: spec, onPassSelected: onPassSelected, height: height).fixedSize(horizontal: false, vertical: true)
            } else {
                natural(PassTilesFigure(spec: spec, onPassSelected: onPassSelected))
            }
        case .toolBars(let spec): natural(ToolBarsFigure(spec: spec))
        case .code(let code): ShaderExcerptFigure(code: code, height: height ?? 200)
        case .pair(let a, let b): FigurePairView(a: a, b: b, height: height ?? 200, onPassSelected: onPassSelected)
        }
    }

    @Environment(\.dynamicTypeSize) private var size

    /// Graphic figures fill a fixed slot; at accessibility sizes the fixed height is removed (Metro §12 signal lab) and
    /// their labels stack at full size, the slot height becoming a minimum.
    @ViewBuilder private func graphic(_ v: some View) -> some View {
        if let height {
            if size.isAccessibilitySize {
                v.frame(minHeight: height, alignment: .top).fixedSize(horizontal: false, vertical: true)
            } else {
                v.frame(height: height)
            }
        } else {
            v.frame(maxHeight: .infinity)
        }
    }

    private func natural(_ v: some View) -> some View {
        v.fixedSize(horizontal: false, vertical: true).frame(minHeight: height ?? 0, alignment: .top)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Two figures: side by side when both are square fields, otherwise stacked: the first at its natural height and the
/// second filling the rest of the slot (at least 110 pt; the slot grows rather than overlap).
struct FigurePairView: View {
    let a: FigureSpec
    let b: FigureSpec
    let height: CGFloat
    let onPassSelected: (Int?) -> Void

    static func isSquare(_ f: FigureSpec) -> Bool {
        switch f {
        case .texelGrid, .heatmap, .psfField: true
        default: false
        }
    }

    var body: some View {
        let grids = { if case .texelGrid = a, case .texelGrid = b { return true } else { return false } }()
        if FigurePairView.isSquare(a) && FigurePairView.isSquare(b) {
            // Side by side when both fit; stacked (each in its own full-width slot) at narrow widths and large text.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: ContentSpacing.group) {
                    FigureSlotContent(figure: a, height: height, role: grids ? .input : nil, onPassSelected: onPassSelected)
                        .frame(maxWidth: .infinity)
                    FigureSlotContent(figure: b, height: height, role: grids ? .output : nil, onPassSelected: onPassSelected)
                        .frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: ContentSpacing.group) {
                    FigureSlotContent(figure: a, height: height, role: grids ? .input : nil, onPassSelected: onPassSelected)
                    FigureSlotContent(figure: b, height: height, role: grids ? .output : nil, onPassSelected: onPassSelected)
                }
            }
        } else {
            ContentTopThenFillLayout(height: height, spacing: ContentSpacing.group, minimumFill: 150) {
                FigureSlotContent(figure: a, height: nil, role: nil, onPassSelected: onPassSelected)
                    .fixedSize(horizontal: false, vertical: true)
                FigureSlotContent(figure: b, height: nil, role: nil, onPassSelected: onPassSelected)
            }
        }
    }
}

/// Places its first subview at its natural height and gives the second the rest of `height` (never less than
/// `minimumFill`, in which case the whole layout grows).
struct ContentTopThenFillLayout: Layout {
    var height: CGFloat
    var spacing: CGFloat
    var minimumFill: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 320
        let top = subviews.first?.sizeThatFits(ProposedViewSize(width: w, height: nil)).height ?? 0
        return CGSize(width: w, height: Swift.max(height, top + spacing + minimumFill))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let first = subviews.first else { return }
        let w = bounds.width
        let top = first.sizeThatFits(ProposedViewSize(width: w, height: nil)).height
        first.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: w, height: top))
        if subviews.count > 1 {
            let fill = Swift.max(minimumFill, bounds.height - top - spacing)
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + top + spacing), anchor: .topLeading,
                              proposal: ProposedViewSize(width: w, height: fill))
        }
    }
}

// MARK: - Data tables (SPEC §14: every plot has a DisclosureGroup data table with the same numbers)

struct FigureDataTable: View {
    let figure: FigureSpec

    static func hasTable(_ f: FigureSpec) -> Bool {
        switch f {
        case .plot, .heatmap, .texelGrid, .psfField, .passTiles: true
        case .pair(let a, let b): hasTable(a) || hasTable(b)
        case .dispatchOverlay, .toolBars, .code: false
        }
    }

    var body: some View {
        switch figure {
        case .pair(let a, let b):
            VStack(alignment: .leading, spacing: ContentSpacing.group) {
                if FigureDataTable.hasTable(a) { FigureDataTable(figure: a) }
                if FigureDataTable.hasTable(b) { FigureDataTable(figure: b) }
            }
        default:
            let t = FigureDataTable.table(figure)
            ContentDisclosure(isDataTable: true) {
                Text("Data table · \(t.title)").contentFont(.label).foregroundStyle(InstrumentPalette.actionCyan)
            } content: {
                ContentTableView(columns: t.columns, rows: t.rows, spoken: t.spoken, caption: t.caption, provenance: t.provenance)
            }
        }
    }

    struct Table {
        var title: String
        var columns: [String]
        var rows: [[String]]
        var spoken: [String]
        var caption: String?
        var provenance: Provenance?
    }

    static func table(_ f: FigureSpec) -> Table {
        switch f {
        case .plot(let p):
            let t = ContentLogic.dataTable(p)
            return Table(title: p.yAxis.label, columns: t.columns, rows: t.rows, spoken: t.spokenRows, caption: nil,
                         provenance: p.series.first?.provenance)
        case .heatmap(let h):
            let style = ContentLogic.valueStyle(h.values, unit: nil)
            let cy = h.centre?.y ?? h.height / 2, cx = h.centre?.x ?? h.width / 2
            var rows: [[String]] = [], spoken: [String] = []
            for i in 0..<Swift.max(h.width, h.height) {
                let along = i < h.width ? style.text(h.values[cy * h.width + i]) : ""
                let down = i < h.height ? style.text(h.values[i * h.width + cx]) : ""
                rows.append([NumberStyle.integer().text(Double(i - (i < h.width ? cx : 0))), along, down])
                spoken.append("offset \(i - cx): row \(along), column \(down)")
            }
            let minV = h.values.min() ?? 0, maxV = h.values.max() ?? 0
            return Table(title: "centre row and column",
                         columns: ["OFFSET", "CENTRE ROW · \(h.provenance.word)", "CENTRE COLUMN · \(h.provenance.word)"],
                         rows: rows, spoken: spoken,
                         caption: "MINIMUM \(style.text(minV)) · MAXIMUM \(style.text(maxV)) · \(h.width) × \(h.height) VALUES",
                         provenance: h.provenance)
        case .texelGrid(let g):
            let style = NumberStyle.decimals(3)
            var rows: [[String]] = [], spoken: [String] = []
            for j in 0..<g.size {
                var r = ["y \(g.origin.y + j)"]
                for i in 0..<g.size { r.append(style.text(g.values[j * g.size + i])) }
                rows.append(r)
                spoken.append("row y \(g.origin.y + j): " + (0..<g.size).map { "x \(g.origin.x + $0) \(style.spoken(g.values[j * g.size + $0]))" }.joined(separator: ", "))
            }
            return Table(title: "\(g.size) × \(g.size) texels", columns: [g.channel.rawValue.uppercased()] + (0..<g.size).map { "x \(g.origin.x + $0)" },
                         rows: rows, spoken: spoken, caption: "LINEAR LIGHT", provenance: g.provenance)
        case .psfField(let f):
            let px = NumberStyle.decimals(2, unit: "px", spokenUnit: "pixels"), deg = NumberStyle.integer(unit: "°", spokenUnit: "degrees")
            var rows: [[String]] = [], spoken: [String] = []
            for (p, k) in zip(f.points, f.kernels) {
                let m = ContentLogic.moments(k)
                rows.append(["(\(p.x), \(p.y))", px.text(m.sigmaMajor), px.text(m.sigmaMinor), deg.text(m.angleDegrees)])
                spoken.append("at \(p.x), \(p.y): sigma along \(px.spoken(m.sigmaMajor)), across \(px.spoken(m.sigmaMinor)), axis \(deg.spoken(m.angleDegrees))")
            }
            return Table(title: "local PSFs", columns: ["POINT", "σ ALONG · PX", "σ ACROSS · PX", "AXIS · °"], rows: rows, spoken: spoken,
                         caption: "SECOND MOMENTS OF EACH LOCAL PSF", provenance: .computed)
        case .passTiles(let t):
            let rows = t.passes.map { [$0.name, $0.kind.rawValue, NumberStyle.decimals(fractional($0.fetchesPerPixel) ? 1 : 0).text($0.fetchesPerPixel),
                                       NumberStyle.decimals(fractional($0.tapsPerPixel) ? 1 : 0).text($0.tapsPerPixel),
                                       NumberStyle.significant(3).text($0.outputScale)] }
            let spoken = t.passes.map { "pass \($0.name), \($0.kind.rawValue), \(NumberStyle.significant(3).spoken($0.fetchesPerPixel)) fetches per pixel" }
            return Table(title: "passes", columns: ["PASS", "KIND", "FETCHES", "TAPS", "OUTPUT SCALE"], rows: rows, spoken: spoken,
                         caption: "PER OUTPUT PIXEL OF EACH PASS", provenance: .computed)
        default:
            return Table(title: "", columns: [], rows: [], spoken: [], caption: nil, provenance: nil)
        }
    }

    private static func fractional(_ v: Double) -> Bool { abs(v - v.rounded()) > 1e-9 }
}

/// A table of pre-formatted cells: header in engraved caps, body in mono with monospaced digits, scrolling sideways when
/// it is wider than the panel (the page scrolls vertically, so this is not a nested same-axis scroll). Each row is one
/// VoiceOver element that speaks its cells with their column names.
struct ContentTableView: View {
    let columns: [String]
    let rows: [[String]]
    var spoken: [String]? = nil
    var caption: String? = nil
    var provenance: Provenance? = nil

    /// Columns whose every cell is a number (right-aligned, so digits line up); words stay left-aligned.
    private var numericColumns: Set<Int> {
        let width = rows.map(\.count).max() ?? 0
        return Set((0..<width).filter { c in
            let cells = rows.compactMap { $0.count > c ? $0[c] : nil }.filter { !$0.isEmpty }
            return !cells.isEmpty && cells.allSatisfy { cell in
                guard let f = cell.first else { return false }
                return f.isNumber || "−-+.".contains(f) || cell.hasPrefix("(")
            }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ContentSpacing.inline) {
            ContentHorizontalScroll {
                Grid(alignment: .leading, horizontalSpacing: ContentSpacing.block, verticalSpacing: 5) {
                    GridRow {
                        ForEach(Array(columns.enumerated()), id: \.offset) { _, c in
                            Text(c).contentFont(.tableHeader).foregroundStyle(ContentInk.secondary).fixedSize()
                        }
                    }
                    .accessibilityHidden(true)
                    Divider().overlay(ContentInk.hairline).gridCellUnsizedAxes(.horizontal)
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { i, cell in
                                Text(cell).contentFont(.tableCell).monospacedDigit()
                                    .foregroundStyle(i == 0 ? ContentInk.secondary : ContentInk.display)
                                    .fixedSize()
                                    .gridColumnAlignment(numericColumns.contains(i) ? .trailing : .leading)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(spoken?[safe: index] ?? zip(columns, row).map { "\($0.lowercased()) \($1)" }.joined(separator: ", "))
                    }
                }
                .padding(.vertical, 2)
            }
            if caption != nil || provenance != nil {
                HStack(spacing: ContentSpacing.group) {
                    if let caption { Text(caption).contentFont(.engraving).foregroundStyle(ContentInk.secondary).fixedSize(horizontal: false, vertical: true) }
                    Spacer(minLength: 0)
                    if let provenance { HonestyBadge(provenance) }
                }
            }
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
