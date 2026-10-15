import SwiftUI
import BlurCore

// OWNER: CONTENT-VIEWS. A texel grid (SPEC §5.1 floor 7, §6.2): a COPY of the 9 × 9 (or 17 × 17) linear-light values
// around the probe, never drawn on the specimen. Each cell shows its value as the grey an SDR display would show, the
// current pass's weight as an amber bar along its bottom edge, and the probe outlined amber (other highlighted taps
// dashed). Numbers are printed in the cells when they are large enough, and the probe's value is always printed under the
// grid with its badge. For VoiceOver the grid is a table: one element per cell ("x 446, y 300, input 0.000, weight
// 0.0999") with Rows and Columns rotors; the data table lists every value.

struct TexelGridFigure: View {
    let spec: TexelGridSpec
    let role: TexelGridRole?
    @Namespace private var cells

    private var title: String { role?.rawValue ?? "TEXELS" }
    private var word: String {
        switch role {
        case .input: "input"
        case .output: "output"
        case nil: "value"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(title) · \(spec.channel.rawValue.uppercased())").contentFont(.engraving).foregroundStyle(ContentInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 2)
                HonestyBadge(spec.provenance).fixedSize()
            }
            .accessibilityHidden(true)
            GeometryReader { geo in
                let side = Swift.min(geo.size.width - 22, geo.size.height - 14)
                let cell = Swift.max(4, side / CGFloat(spec.size))
                VStack(alignment: .leading, spacing: 2) {
                    columnLabels(cell: cell).padding(.leading, 22)
                    HStack(alignment: .top, spacing: 2) {
                        rowLabels(cell: cell).frame(width: 20)
                        grid(cell: cell)
                            .frame(width: cell * CGFloat(spec.size), height: cell * CGFloat(spec.size))
                    }
                }
            }
            probeLine
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentPlotInset()
    }

    private var probe: PixelPoint? { spec.highlighted.first }

    private func value(_ i: Int, _ j: Int) -> Double { spec.values[j * spec.size + i] }
    private func weight(_ i: Int, _ j: Int) -> Double? { spec.weights.map { $0[j * spec.size + i] } }

    private func grid(cell: CGFloat) -> some View {
        let maxWeight = spec.weights?.map(abs).max() ?? 0
        let printValues = cell >= 27
        return Canvas { context, _ in
            for j in 0..<spec.size {
                for i in 0..<spec.size {
                    let r = CGRect(x: CGFloat(i) * cell, y: CGFloat(j) * cell, width: cell, height: cell)
                    let grey = ContentLogic.displayGrey(linear: value(i, j))
                    context.fill(Path(r.insetBy(dx: 0.5, dy: 0.5)), with: .color(Color(white: grey)))
                    if let w = weight(i, j), maxWeight > 0, w != 0 {
                        let h = Swift.max(1.5, r.height * 0.32 * CGFloat(abs(w) / maxWeight))
                        let bar = CGRect(x: r.minX + r.width * 0.2, y: r.maxY - h - 1, width: r.width * 0.6, height: h)
                        context.fill(Path(bar), with: .color(w < 0 ? ContentInk.negative : ContentInk.probe))
                    }
                    if printValues {
                        let text = Text(NumberStyle.decimals(2).text(value(i, j)))
                            .font(.system(size: Swift.min(11, cell * 0.3), design: .monospaced)).monospacedDigit()
                            .foregroundStyle(grey > 0.55 ? Color.black.opacity(0.8) : Color.white.opacity(0.85))
                        context.draw(text, at: CGPoint(x: r.midX, y: r.midY - (spec.weights == nil ? 0 : r.height * 0.1)))
                    }
                }
            }
            for (k, p) in spec.highlighted.enumerated() {
                let i = p.x - spec.origin.x, j = p.y - spec.origin.y
                guard i >= 0, j >= 0, i < spec.size, j < spec.size else { continue }
                let r = CGRect(x: CGFloat(i) * cell, y: CGFloat(j) * cell, width: cell, height: cell).insetBy(dx: 0.75, dy: 0.75)
                context.stroke(Path(r), with: .color(ContentInk.probe),
                               style: StrokeStyle(lineWidth: k == 0 ? 1.6 : 1, dash: k == 0 ? [] : [2, 1.5]))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) texels, \(spec.size) by \(spec.size), \(spec.provenance.spokenPhrase(device: nil))")
        .accessibilityChildren {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(0..<spec.size, id: \.self) { j in
                    GridRow {
                        ForEach(0..<spec.size, id: \.self) { i in
                            Color.clear.frame(width: cell, height: cell)
                                .accessibilityElement()
                                .accessibilityLabel(cellLabel(i, j))
                                .accessibilityAddTraits(probe == PixelPoint(x: spec.origin.x + i, y: spec.origin.y + j) ? .isSelected : [])
                                .accessibilityRotorEntry(id: j * spec.size + i, in: cells)
                        }
                    }
                }
            }
        }
        .accessibilityRotor("Rows") {
            ForEach(0..<spec.size, id: \.self) { j in
                AccessibilityRotorEntry("Row y \(spec.origin.y + j)", id: j * spec.size, in: cells)
            }
        }
        .accessibilityRotor("Columns") {
            ForEach(0..<spec.size, id: \.self) { i in
                AccessibilityRotorEntry("Column x \(spec.origin.x + i)", id: i, in: cells)
            }
        }
    }

    private func cellLabel(_ i: Int, _ j: Int) -> String {
        var s = "x \(spec.origin.x + i), y \(spec.origin.y + j), \(word) \(NumberStyle.decimals(3).spoken(value(i, j)))"
        if let w = weight(i, j), w != 0 { s += ", weight \(NumberStyle.significant(3).spoken(w))" }
        if probe == PixelPoint(x: spec.origin.x + i, y: spec.origin.y + j) { s += ", probe" }
        return s
    }

    /// Coordinates of the first, probe and last columns (window pixels; coordinates are literals, not claims).
    private func columnLabels(cell: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(labelIndices(), id: \.self) { i in
                Text("\(spec.origin.x + i)").contentFont(.tick).foregroundStyle(i == (probe.map { $0.x - spec.origin.x } ?? -1) ? ContentInk.probe : ContentInk.secondary)
                    .fixedSize()
                    .frame(width: cell * 3, alignment: .center)
                    .offset(x: CGFloat(i) * cell - cell)
            }
        }
        .frame(height: 12, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func rowLabels(cell: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            ForEach(labelIndices(vertical: true), id: \.self) { j in
                Text("\(spec.origin.y + j)").contentFont(.tick).foregroundStyle(j == (probe.map { $0.y - spec.origin.y } ?? -1) ? ContentInk.probe : ContentInk.secondary)
                    .fixedSize()
                    .frame(width: 20, height: cell, alignment: .trailing)
                    .offset(y: CGFloat(j) * cell)
            }
        }
        .frame(width: 20, height: cell * CGFloat(spec.size), alignment: .topTrailing)
        .accessibilityHidden(true)
    }

    private func labelIndices(vertical: Bool = false) -> [Int] {
        let p = probe.map { vertical ? $0.y - spec.origin.y : $0.x - spec.origin.x }
        var out = [0, spec.size - 1]
        if let p, p > 1, p < spec.size - 2 { out.append(p) }
        return out
    }

    /// The probe's value under the grid, with its badge (always readable, whatever the cell size).
    @ViewBuilder private var probeLine: some View {
        if let p = probe {
            let i = p.x - spec.origin.x, j = p.y - spec.origin.y
            if i >= 0, j >= 0, i < spec.size, j < spec.size {
                // The probe's value (a grid value: the header's badge covers it), linear light.
                ContentFlowLayout(spacing: 6, lineSpacing: 2) {
                    Text("(\(p.x), \(p.y))").contentFont(.tick).foregroundStyle(ContentInk.probe).fixedSize()
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(NumberStyle.decimals(3).text(value(i, j))).contentFont(.value).monospacedDigit()
                            .foregroundStyle(InstrumentPalette.actionCyan)
                        Text("LIN").contentFont(.engraving).foregroundStyle(ContentInk.secondary)
                    }
                    .fixedSize()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("probe \(p.x), \(p.y), \(word) \(NumberStyle.decimals(3).spoken(value(i, j))) linear, \(spec.provenance.spokenPhrase(device: nil))")
            }
        }
    }
}
