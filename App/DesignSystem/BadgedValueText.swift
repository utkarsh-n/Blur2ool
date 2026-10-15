import SwiftUI
import BlurCore

// OWNER: METRO-COMPONENTS (frozen initialiser, ARCHITECTURE §5.14; SPEC §12.1–§12.2, §14; Metro §4 formatting contracts).
// A number (or its words) with its unit, its badge, its caption and its full VoiceOver phrase. The text is exactly
// `BadgedValue.text` (BlurCore's one formatter made it; this view never formats a number), set in monospaced digits in a
// reserved width, with the unit separated on the first baseline (Metro §4).
//   .row        trailing; value + unit + WORD badge on one line; wraps to value / badge when it does not fit (SPEC §12.2
//               item 2: badge words are never abbreviated); caption (UNVERIFIED PEAK, SOURCES DISAGREE …) underneath.
//   .telemetry  centred Metro telemetry column: title3 value + caption2 unit, the WORD badge under it, caption under that.
//   .chip       a rail chip's value: ≤ 6 characters, no unit (SPEC §4.1.4); the glyph badge (the one glyph use) hangs
//               above the value at the trailing edge, i.e. in the chip's label row, so it never covers a digit.
//   .inline     one line inside a sentence or status row: value + unit + a compact WORD badge.
// Inputs (`isInput`) carry no badge; words-only values (value nil) are set in secondary ink.
public enum BadgedValueLayout: Sendable { case row, telemetry, chip, inline }

public struct BadgedValueText: View {
    public let value: BadgedValue
    public let layout: BadgedValueLayout

    public init(_ value: BadgedValue, layout: BadgedValueLayout = .row) { self.value = value; self.layout = layout }

    public var body: some View {
        Group {
            switch layout {
            case .row: BadgedValueRow(value: value)
            case .telemetry: BadgedValueTelemetry(value: value)
            case .chip: BadgedValueChip(value: value)
            case .inline: BadgedValueInline(value: value)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BadgedValueText.spoken(value))
    }

    /// The VoiceOver phrase: BlurCore's `spoken` (value, unit, badge word, caption) plus the device label of a MEASURED value.
    nonisolated public static func spoken(_ value: BadgedValue) -> String {
        guard !value.spoken.isEmpty else { return value.textWithUnit }
        return value.spoken
    }

    /// The badge this value shows, or nil for inputs and claim-free words.
    nonisolated static func badge(_ value: BadgedValue) -> Provenance? { value.isInput ? nil : value.provenance }

    /// The six-character chip text (SPEC §4.1.4): no unit; an UNVERIFIED value reads `UNVER.` and speaks "unverified".
    nonisolated public static func chipText(_ value: BadgedValue) -> String {
        if value.qualifiers.contains(.unverified) { return "UNVER." }
        return value.text.count <= 6 ? value.text : String(value.text.prefix(6))
    }

    /// The ink of the value: numbers in the layout's value ink, words and placeholders in secondary ink (they make no claim).
    nonisolated static func valueInk(_ value: BadgedValue, numberInk: Color) -> Color {
        value.value == nil || value.qualifiers.contains(.unverified) ? InstrumentPalette.secondaryInk : numberInk
    }

    /// A same-width template that reserves at least four monospaced character cells, so a value that changes in place
    /// (0.61 → 12.40) does not move its unit and badge until it genuinely needs more room (Metro §4 "reserve value width").
    nonisolated static func reservedTemplate(_ text: String) -> String {
        String(repeating: "0", count: Swift.max(4, text.count))
    }
}

// MARK: - Layouts

private struct BadgedValueRow: View {
    let value: BadgedValue
    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) { number; badge }
                VStack(alignment: .trailing, spacing: 3) { number; badge }
            }
            BadgedValueCaption(value: value)
        }
    }
    private var number: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            ZStack(alignment: .trailing) {
                Text(BadgedValueText.reservedTemplate(value.text)).hidden()
                Text(value.text)
                    .foregroundStyle(BadgedValueText.valueInk(value, numberInk: InstrumentPalette.displayInk))
            }
            .font(.system(.callout, design: .monospaced))
            .monospacedDigit()
            .lineLimit(1)
            if let unit = value.unit {
                Text(unit)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(InstrumentOpacity.metadataInk))
                    .fixedSize()
            }
        }
        .fixedSize()
    }
    @ViewBuilder private var badge: some View {
        if let p = BadgedValueText.badge(value) { HonestyBadge(p, qualifiers: value.qualifiers) }
    }
}

private struct BadgedValueTelemetry: View {
    let value: BadgedValue
    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                ZStack(alignment: .trailing) {
                    Text(BadgedValueText.reservedTemplate(value.text)).hidden()
                    Text(value.text)
                        .foregroundStyle(BadgedValueText.valueInk(value, numberInk: InstrumentPalette.actionCyan))
                }
                .font(.system(.title3, design: .monospaced))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                if let unit = value.unit {
                    Text(unit)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(InstrumentOpacity.metadataInk))
                        .fixedSize()
                }
            }
            if let p = BadgedValueText.badge(value) {
                HonestyBadge(p, qualifiers: value.qualifiers)
            }
            BadgedValueCaption(value: value, alignment: .center)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BadgedValueChip: View {
    let value: BadgedValue
    @ScaledMetric(relativeTo: .footnote) private var size = InstrumentTypeScale.chipValue
    var body: some View {
        Text(BadgedValueText.chipText(value))
            .font(.system(size: Swift.min(size, InstrumentTypeScale.chipValueMaximum), design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(BadgedValueText.valueInk(value, numberInk: InstrumentPalette.actionCyan))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                // The glyph hangs ABOVE the value line, at the chip's top-trailing corner beside the floor label
                // (SPEC §4.1.4 "badge glyph 11 pt top-trailing"), so it never covers a digit. The guide sits on the
                // unconditional wrapper: SwiftUI ignores alignment guides set inside an `if` in an overlay.
                glyph
                    .alignmentGuide(.top) { $0[.bottom] + 1 }
                    .alignmentGuide(.trailing) { $0[.trailing] - 2 }
            }
    }
    @ViewBuilder private var glyph: some View {
        if let p = BadgedValueText.badge(value) {
            HonestyBadge(p, qualifiers: value.qualifiers, style: .glyph)
        }
    }
}

private struct BadgedValueInline: View {
    let value: BadgedValue
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value.textWithUnit)
                .monospacedDigit()
                .foregroundStyle(BadgedValueText.valueInk(value, numberInk: InstrumentPalette.displayInk))
                .fixedSize()
            if let p = BadgedValueText.badge(value) { HonestyBadge(p, qualifiers: value.qualifiers) }
        }
    }
}

/// The trailing caption in secondary ink with no capsule (UNVERIFIED PEAK, SOURCES DISAGREE, OFFSCREEN, the MEASURED
/// device engraving). It wraps instead of truncating (SPEC §4.1.10 "a row that does not fit wraps").
private struct BadgedValueCaption: View {
    let value: BadgedValue
    var alignment: TextAlignment = .trailing
    var body: some View {
        let lines = BadgedValueCaption.lines(value)
        if !lines.isEmpty {
            Text(lines.joined(separator: " · "))
                .font(.system(.caption2, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(InstrumentPalette.secondaryInk)
                .multilineTextAlignment(alignment)
                .fixedSize(horizontal: false, vertical: true)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
    }
    static func lines(_ value: BadgedValue) -> [String] {
        var out: [String] = []
        if let caption = value.caption { out.append(caption) }
        if value.provenance == .measured, value.value != nil, let device = value.device { out.append(device.label) }
        if value.qualifiers.contains(.sourcesDisagree), !(value.caption ?? "").uppercased().contains("DISAGREE") {
            out.append("SOURCES DISAGREE")
        }
        return out
    }
}
