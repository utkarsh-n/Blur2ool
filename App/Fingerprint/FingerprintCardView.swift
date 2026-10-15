import SwiftUI
import BlurCore

// OWNER: UI-ATLAS (minimal seed written by SKEL; frozen initialiser, ARCHITECTURE §5.9 / AppContract/Fingerprint).
// The fingerprint card (SPEC §7.1), full in the Fingerprint sheet and compact below the fold on the Bench. `model` nil
// shows the fixed-height skeleton with engraved "— NOT YET COMPUTED" cells (never a spinner).
// TODO(UI-ATLAS): fixed slot heights, the PSF/STAR/EDGE strip at σ 4 px with its evidence badge, response chips, the
// kurtosis axis, TELL with Show me, NEAREST, PARTS WAYS, two-line ON THIS PHONE, LOOKS MOST LIKE.
public enum FingerprintCardStyle: Sendable { case full, compact }

public struct FingerprintCardView: View {
    private let model: FingerprintCardModel?
    private let style: FingerprintCardStyle
    private let onShowMe: (TellSpec) -> Void
    private let onNeighbour: (BlurID) -> Void
    private let onFloor: (Floor) -> Void
    private let onFullCard: () -> Void
    private let onFieldGuide: () -> Void

    /// `model` nil shows the fixed-height card skeleton with engraved "— NOT YET COMPUTED" cells (never a spinner).
    public init(model: FingerprintCardModel?, style: FingerprintCardStyle,
                onShowMe: @escaping (TellSpec) -> Void = { _ in },
                onNeighbour: @escaping (BlurID) -> Void = { _ in },
                onFloor: @escaping (Floor) -> Void = { _ in },
                onFullCard: @escaping () -> Void = {},
                onFieldGuide: @escaping () -> Void = {}) {
        self.model = model; self.style = style; self.onShowMe = onShowMe; self.onNeighbour = onNeighbour; self.onFloor = onFloor
        self.onFullCard = onFullCard; self.onFieldGuide = onFieldGuide
    }

    public var body: some View {
        InstrumentContentPanel {
            VStack(alignment: .leading, spacing: 8) {
                if let model {
                    HStack {
                        Text(model.entry.displayName).font(.system(.headline, design: .rounded))
                        Spacer()
                        Text(model.entry.verdict.chip).font(.system(.caption2, design: .monospaced)).foregroundStyle(InstrumentPalette.secondaryInk)
                    }
                    Text(model.entry.signature).font(.footnote).foregroundStyle(InstrumentPalette.secondaryInk)
                    let rows = style == .compact ? Array(model.entry.card.ordered.prefix(3)) : model.entry.card.ordered
                    ForEach(rows, id: \.label) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.label).font(.system(.caption2, design: .monospaced)).foregroundStyle(InstrumentPalette.secondaryInk)
                                .frame(width: 84, alignment: .leading)
                            Text(item.row.text).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                            HonestyBadge(item.row.provenance)
                        }
                    }
                    LabeledValuesView([model.unique, LabeledValue(id: "kurtosis", label: "EXCESS KURTOSIS", value: model.excessKurtosis)])
                    HStack {
                        Text("ON THIS PHONE").font(.system(.caption2, design: .monospaced)).foregroundStyle(InstrumentPalette.secondaryInk)
                        Spacer()
                        Text("— NOT YET COMPUTED").font(.system(.caption2, design: .monospaced)).foregroundStyle(InstrumentPalette.secondaryInk)
                    }
                    if style == .compact { Button("Full card ›", action: onFullCard).font(.footnote) }
                    else { Button("Field guide ›", action: onFieldGuide).font(.footnote) }
                } else {
                    ForEach(["PSF SHAPE", "RESPONSE", "EDGES", "COST", "ARTIFACTS", "USED IN"], id: \.self) { label in
                        HStack {
                            Text(label).font(.system(.caption2, design: .monospaced)).foregroundStyle(InstrumentPalette.secondaryInk)
                            Spacer()
                            Text("— NOT YET COMPUTED").font(.system(.caption2, design: .monospaced)).foregroundStyle(InstrumentPalette.secondaryInk)
                        }
                    }
                }
            }
        }
    }
}
