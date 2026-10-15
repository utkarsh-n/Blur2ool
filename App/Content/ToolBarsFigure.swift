import SwiftUI
import BlurCore

// OWNER: CONTENT-VIEWS. Floor 1 tool bars (SPEC §5.1 floor 1): the value each tool needs typed for the current blur, the
// home tool first and in action cyan, the others quiet; `You typed ⇄ What you get` (reverse mode) shows σ per tool for one
// typed value instead. A bar's length is the number relative to the largest row (bars compare numbers, the units stay
// printed). A tool whose mapping is unknown shows the word UNVERIFIED and no bar (an UNVERIFIED figure is never a number,
// SPEC §12.1). Captions such as `SAME σ, DIFFERENT KERNEL` sit under the value. Each row is one VoiceOver element.

struct ToolBarsFigure: View {
    let spec: ToolBarsSpec
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        let peak = spec.rows.compactMap(\.value.value).map(abs).max() ?? 0
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(spec.reverseMode ? "YOU TYPED ⇄ WHAT YOU GET" : "WHAT YOU WOULD TYPE, PER TOOL")
                    .contentFont(.engraving).foregroundStyle(ContentInk.secondary)
                Spacer(minLength: 0)
                Text(spec.reverseMode ? "σ PER TOOL" : "HOME TOOL FIRST").contentFont(.engraving).foregroundStyle(ContentInk.secondary.opacity(0.8))
            }
            .accessibilityHidden(true)
            ForEach(spec.rows) { row in
                ToolBarRow(row: row, isHome: row.id == spec.homeToolID, peak: peak, stacked: size >= .xLarge)
            }
        }
        .padding(10)
        .contentPlotInset()
    }
}

struct ToolBarRow: View {
    let row: LabeledValue
    let isHome: Bool
    let peak: Double
    let stacked: Bool

    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 3) {
                    labelBar
                    HStack(spacing: 0) { Spacer(minLength: 0); value }
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    labelBar.frame(maxWidth: .infinity, alignment: .leading)
                    value
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((isHome ? "home tool, " : "") + ContentValueRow.spokenLabel(row.label))
        .accessibilityValue(row.value.spoken)
    }

    /// The label drawn over its bar: the bar's length is the value relative to the largest row, its end a solid edge.
    private var labelBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if isHome { Image(systemName: "house").font(.system(size: 8, weight: .semibold)).foregroundStyle(InstrumentPalette.actionCyan) }
            Text(row.label).contentFont(.label).foregroundStyle(isHome ? ContentInk.display : ContentInk.display.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 6)
        .padding(.top, 3)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) {
            GeometryReader { geo in
                if let v = row.value.value, peak > 0 {
                    let w = Swift.max(3, geo.size.width * CGFloat(abs(v) / peak))
                    // A quiet band behind the label and a solid rule along its bottom edge: the rule's length is the value.
                    ZStack(alignment: .bottomLeading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isHome ? InstrumentPalette.actionCyan.opacity(0.14) : Color.white.opacity(0.05))
                        Capsule().fill(isHome ? InstrumentPalette.actionCyan : ContentInk.secondary.opacity(0.85)).frame(height: 2.5)
                    }
                    .frame(width: w)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(ContentInk.hairline, style: StrokeStyle(lineWidth: 0.6, dash: [2, 2]))
                }
            }
        }
    }

    private var value: some View {
        ContentValueText(value: row.value).fixedSize()
    }
}
