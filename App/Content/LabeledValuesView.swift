import SwiftUI
import BlurCore

// OWNER: CONTENT-VIEWS (frozen initialiser, ARCHITECTURE §5.11 / AppContract/Content). A column of LabeledValues: the
// ALL-CAPS mono label on the leading edge, the number with its unit and ONE badge at the trailing edge (SPEC §12.2 rule 1),
// its caption ("OFFSCREEN · MAC", "UNVERIFIED PEAK") under the number. A row that does not fit on one line becomes two lines
// (label, then value), never a shortened badge word (review fix P-48); at accessibility sizes every row is two lines.
// Each row is one VoiceOver element: "centre weight, 0.09991, computed".
public struct LabeledValuesView: View {
    private let rows: [LabeledValue]
    public init(_ rows: [LabeledValue]) { self.rows = rows }

    public var body: some View {
        VStack(alignment: .leading, spacing: ContentValueRow.spacing) {
            ForEach(rows) { ContentValueRow(row: $0) }
        }
    }
}

/// One LabeledValue row (shared by LabeledValuesView, the floor page's reserved number slots and the text-fit tests).
struct ContentValueRow: View {
    let row: LabeledValue
    /// Forces the two-line layout (the floor page decides it per Dynamic Type size so every row slot has one height).
    var stacked: Bool? = nil
    @Environment(\.dynamicTypeSize) private var dynamicType

    static let spacing: CGFloat = 6

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if stacked ?? dynamicType.isAccessibilitySize {
                twoLine
            } else {
                ViewThatFits(in: .horizontal) {
                    oneLine
                    twoLine
                }
            }
            // The caption spans the row under the number (it never widens the number's column).
            if let caption = row.value.caption {
                Text(caption).contentFont(.engraving).foregroundStyle(ContentInk.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ContentValueRow.spokenLabel(row.label))
        .accessibilityValue(row.value.spoken)
    }

    private var label: some View {
        Text(row.label)
            .contentFont(.label)
            .foregroundStyle(ContentInk.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var oneLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: ContentSpacing.group) {
            label.fixedSize()
            Spacer(minLength: ContentSpacing.group)
            ContentValueText(value: row.value, showsCaption: false).fixedSize()
        }
    }

    private var twoLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            label
            HStack(spacing: 0) {
                Spacer(minLength: ContentSpacing.section)
                ContentValueText(value: row.value, showsCaption: false).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "CENTRE WEIGHT" → "centre weight"; symbols VoiceOver reads badly are spelled out.
    static func spokenLabel(_ label: String) -> String {
        label.lowercased()
            .replacingOccurrences(of: "σ", with: "sigma")
            .replacingOccurrences(of: "|gpu − cpu|", with: "GPU minus CPU")
            .replacingOccurrences(of: "−3 db", with: "minus 3 decibels")
            .replacingOccurrences(of: "−", with: "minus ")
    }
}

/// A number (or its words) with its unit, its ONE badge and its caption, right-aligned. Display precision is the
/// BadgedValue's own text (BlurCore's NumberStyle). The badge word is never compressed or broken: when the value and badge
/// do not fit on one line, the badge moves under the value. Values that are words (UNVERIFIED, –.––) are secondary ink.
struct ContentValueText: View {
    let value: BadgedValue
    var showsCaption = true

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 4) { number; badge }
                VStack(alignment: .trailing, spacing: 2) { number; badge }
            }
            if showsCaption, let caption = value.caption {
                Text(caption).contentFont(.engraving).foregroundStyle(ContentInk.secondary)
                    .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.spoken)
    }

    /// The number and its unit on one line, or the unit under the number when they do not fit (accessibility sizes);
    /// the number itself is never shrunk or cut.
    private var number: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 3) { numberText; unitText }.fixedSize()
            VStack(alignment: .trailing, spacing: 0) { numberText; unitText }
        }
    }

    private var numberText: some View {
        Text(value.text)
            .contentFont(.value).monospacedDigit()
            .foregroundStyle(value.value == nil ? ContentInk.secondary : InstrumentPalette.actionCyan)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var unitText: some View {
        if let unit = value.unit {
            Text(unit).contentFont(.tick).foregroundStyle(Color.white.opacity(0.68))
        }
    }

    @ViewBuilder private var badge: some View {
        if let provenance = value.provenance, !value.isInput {
            HonestyBadge(provenance, qualifiers: value.qualifiers).fixedSize()
        }
    }
}
