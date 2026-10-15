import SwiftUI
import BlurCore

// OWNER: CONTENT-VIEWS. The Algorithm floor's pass tiles (SPEC §5.1 floor 5; METRO §C.7) through METRO-COMPONENTS'
// InstrumentEventTiles: header `PASSES` with `n / N`, one tile per pass (name, kind), at most six per row (more wrap to a
// second row), tapping a tile selects it (the periscope then shows that pass's intermediate, `PASS 1 OF 2`) and tapping it
// again clears the selection. Under the tiles, the selected pass's counts as badged numbers, and its time: MEASURED bars
// relative to the slowest pass once a settled timing run exists, otherwise the engraved `PER-PASS TIME –.––`.

struct PassTilesFigure: View {
    let spec: PassTilesSpec
    let onPassSelected: (Int?) -> Void
    /// When set, the figure fills this height and draws the pass ladder (each pass's output size) in the space the tiles
    /// leave; without it the figure takes its natural height (stacked above a plot).
    var height: CGFloat? = nil
    @State private var selection: Int??

    static let perRow = 6

    private var selected: Int? { selection ?? spec.selected }

    var body: some View {
        Group {
            if let height {
                ContentTopThenFillLayout(height: height - 16, spacing: 8, minimumFill: 48) {
                    controls.fixedSize(horizontal: false, vertical: true)
                    PassLadder(passes: spec.passes, selected: selected)
                }
            } else {
                controls
            }
        }
        .padding(8)
        .contentPlotInset()
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("PASSES").contentFont(.engraving).foregroundStyle(ContentInk.secondary)
                Spacer(minLength: 4)
                Text(selected.map { "\($0 + 1) / \(spec.passes.count)" } ?? "– / \(spec.passes.count)")
                    .contentFont(.tick).monospacedDigit().foregroundStyle(ContentInk.display)
                    .accessibilityLabel(selected.map { "pass \($0 + 1) of \(spec.passes.count) selected" } ?? "\(spec.passes.count) passes, none selected")
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                InstrumentEventTiles(row.map(tile)) { id in
                    let next: Int? = selected == id ? nil : id
                    selection = .some(next)
                    onPassSelected(next)
                }
            }
            detail
            timeline
        }
    }

    /// Up to six tiles in one row; seven to twelve split into two balanced rows; more wrap in rows of six.
    private var rows: [[PassDescriptor]] {
        let n = spec.passes.count
        let perRow = n <= PassTilesFigure.perRow ? Swift.max(1, n) : n <= 2 * PassTilesFigure.perRow ? (n + 1) / 2 : PassTilesFigure.perRow
        return stride(from: 0, to: n, by: perRow).map { Array(spec.passes[$0..<Swift.min(n, $0 + perRow)]) }
    }

    private func tile(_ p: PassDescriptor) -> EventTile {
        EventTile(id: p.id, title: p.name, caption: PassTilesFigure.kindWord(p),
                  state: p.id == selected ? .current : .idle,
                  accessibilityLabel: "Pass \(p.id + 1) of \(spec.passes.count), \(p.name), \(p.summary)")
    }

    static func kindWord(_ p: PassDescriptor) -> String {
        if p.outputScale < 1 {
            let denominator = Int((1 / p.outputScale).rounded())
            return "1/\(denominator)"
        }
        return p.kind.rawValue.uppercased()
    }

    @ViewBuilder private var detail: some View {
        if let id = selected, let p = spec.passes.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 3) {
                Text("PASS \(p.id + 1) OF \(spec.passes.count) · \(p.name) · \(p.summary.uppercased())")
                    .contentFont(.engraving).foregroundStyle(ContentInk.display).fixedSize(horizontal: false, vertical: true)
                ContentFlowLayout(spacing: 10, lineSpacing: 3) {
                    labelled("FETCHES", .number(p.fetchesPerPixel, PassTilesFigure.countStyle(p.fetchesPerPixel), .computed))
                    labelled("TAPS", .number(p.tapsPerPixel, PassTilesFigure.countStyle(p.tapsPerPixel), .computed))
                    if p.outputScale != 1 { labelled("OUTPUT", .number(p.outputScale, .significant(3), .computed)) }
                    if p.traceable { Text("TRACED").contentFont(.engraving).foregroundStyle(ContentInk.secondary) }
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("TAP A PASS TO SEE ITS INTERMEDIATE IMAGE").contentFont(.engraving).foregroundStyle(ContentInk.secondary)
        }
    }

    static func countStyle(_ v: Double) -> NumberStyle { abs(v - v.rounded()) < 1e-9 ? .integer() : .decimals(1) }

    private func labelled(_ label: String, _ value: BadgedValue) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label).contentFont(.engraving).foregroundStyle(ContentInk.secondary)
            BadgedValueText(value, layout: .inline)
        }
        .fixedSize()
    }

    /// MEASURED per-pass time as bars relative to the slowest pass (the milliseconds themselves, with their device, are the
    /// GPU floor's rows; a PassTilesSpec carries no DeviceStamp, so this figure never prints a timing number).
    @ViewBuilder private var timeline: some View {
        if spec.timings.isEmpty {
            Text("PER-PASS TIME –.–– · NOT YET MEASURED").contentFont(.engraving).foregroundStyle(ContentInk.secondary)
                .accessibilityLabel("per-pass time not yet measured")
        } else {
            let slowest = spec.timings.map(\.medianMilliseconds).max() ?? 0
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("RELATIVE PASS TIME").contentFont(.engraving).foregroundStyle(ContentInk.secondary)
                    HonestyBadge(.measured)
                }
                ForEach(spec.timings, id: \.passIndex) { t in
                    HStack(spacing: 6) {
                        Text(t.passName).contentFont(.tick).foregroundStyle(ContentInk.display).frame(width: 34, alignment: .leading)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(ContentInk.measured.opacity(t.passIndex == selected ? 0.95 : 0.6))
                                .frame(width: slowest > 0 ? Swift.max(2, geo.size.width * CGFloat(t.medianMilliseconds / slowest)) : 2)
                        }
                        .frame(height: 6)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("pass \(t.passName), \(NumberStyle.integer().spoken((100 * t.medianMilliseconds / Swift.max(slowest, 1e-12)).rounded())) percent of the slowest pass, measured")
                }
            }
        }
    }
}

/// Each pass's output size as a bar (the window is the full width), in pass order: a pyramid's ↓ passes shrink and its ↑
/// passes grow back, a separable pair stays at full size. Decorative geometry over the data table's OUTPUT SCALE column.
struct PassLadder: View {
    let passes: [PassDescriptor]
    let selected: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("OUTPUT SIZE OF EACH PASS · WINDOW = FULL WIDTH").contentFont(.engraving).foregroundStyle(ContentInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Canvas { context, size in
                guard !passes.isEmpty else { return }
                let labelW: CGFloat = 30
                let rowH = Swift.min(16, size.height / CGFloat(passes.count))
                let barW = size.width - labelW
                for (i, p) in passes.enumerated() {
                    let y = CGFloat(i) * rowH
                    let w = Swift.max(2, barW * CGFloat(Swift.min(1, p.outputScale)))
                    let r = CGRect(x: labelW + (barW - w) / 2, y: y + 1.5, width: w, height: Swift.max(2, rowH - 3))
                    let isSelected = p.id == selected
                    context.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(InstrumentPalette.actionCyan.opacity(isSelected ? 0.4 : 0.14)))
                    if isSelected {
                        context.stroke(Path(roundedRect: r, cornerRadius: 2), with: .color(InstrumentPalette.actionCyan.opacity(0.7)), lineWidth: 0.8)
                    }
                    context.draw(Text(p.name).font(.system(size: Swift.min(10, rowH * 0.75), design: .monospaced))
                                    .foregroundStyle(isSelected ? InstrumentPalette.actionCyan : ContentInk.secondary),
                                 at: CGPoint(x: 2, y: y + rowH / 2), anchor: .leading)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
