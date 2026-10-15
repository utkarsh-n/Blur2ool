import SwiftUI
import BlurCore

// OWNER: METRO-COMPONENTS (frozen initialiser, ARCHITECTURE §5.14; SPEC §12.1–§12.2, §14; METRO §C.12). The capsule badge:
// the WORD is primary; the glyph and the ink are redundant cues (Metro §3, §17), so the badge is readable without colour.
//   .word   caption2 mono, tracking 1.2, fill white 0.06, 0.6-pt border white 0.12 (0.25 under Increased Contrast).
//           INFERRED has a DASHED border in its own ink (1 pt under Increased Contrast). Qualifiers that change what the
//           badge claims ride inside it (`LIVE · CPU`, `MEASURED · OFFSCREEN`); UNVERIFIED trails it in secondary ink with
//           no capsule, so it can never be mistaken for a seventh provenance (SPEC §12.1).
//   .glyph  only on rail chips (SPEC §12.2 item 2): the glyph at ≥ 11 pt; INFERRED adds a dashed ring; the word is spoken.
// Badges never animate. Text scales with Dynamic Type up to AX1 (SPEC §14 "Text that carries meaning scales").
public enum HonestyBadgeStyle: Sendable { case word, glyph }

public struct HonestyBadge: View {
    public let provenance: Provenance
    public let qualifiers: Qualifiers
    public let style: HonestyBadgeStyle

    public init(_ provenance: Provenance, qualifiers: Qualifiers = [], style: HonestyBadgeStyle = .word) {
        self.provenance = provenance; self.qualifiers = qualifiers; self.style = style
    }

    public var body: some View {
        HonestyBadgeFace(provenance: provenance, qualifiers: qualifiers, style: style)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(HonestyBadge.spokenLabel(provenance, qualifiers: qualifiers))
            .accessibilityHint(HonestyBadge.meaning(provenance))
            .accessibilityIdentifier("honestyBadge.\(provenance.word)")
    }

    // MARK: Vocabulary (SPEC §12.1 table), shared by every surface that shows a provenance

    /// Redundant ink per badge (SPEC §12.1): LIVE action cyan, MEASURED instrument amber, COMPUTED display ink,
    /// MODELED spectrum violet, REFERENCE secondary ink, INFERRED spectrum secondary (magenta).
    nonisolated public static func ink(_ p: Provenance) -> Color {
        switch p {
        case .live: InstrumentPalette.actionCyan
        case .measured: InstrumentPalette.instrumentAmber
        case .computed: InstrumentPalette.displayInk
        case .modeled: InstrumentPalette.spectrum
        case .reference: InstrumentPalette.secondaryInk
        case .inferred: InstrumentPalette.spectrumDepth
        }
    }

    /// The SF Symbol of each badge (SPEC §12.1). MODELED has none: SF Symbols has no `approximately` (checked on the Mac,
    /// 14 Oct 2026), so it is the text glyph `≈`; LIVE is drawn as a 5-pt dot.
    nonisolated public static func symbolName(_ p: Provenance) -> String? {
        switch p {
        case .live: "circle.fill"
        case .measured: "stopwatch"
        case .computed: "equal"
        case .modeled: nil
        case .reference: "book.closed"
        case .inferred: "questionmark"
        }
    }

    /// A one-character text form of the glyph, for plain-text contexts (Canvas engravings, logs).
    nonisolated public static func glyph(_ p: Provenance) -> String {
        switch p {
        case .live: "●"
        case .measured: "◷"
        case .computed: "="
        case .modeled: "≈"
        case .reference: "§"
        case .inferred: "?"
        }
    }

    /// The qualifier words printed inside the capsule after the provenance word (SPEC §12.1–§12.2).
    nonisolated public static func qualifierWords(_ q: Qualifiers) -> [String] {
        var words: [String] = []
        if q.contains(.cpu) { words.append("CPU") }
        if q.contains(.offscreen) { words.append("OFFSCREEN") }
        if q.contains(.simulator) { words.append("SIMULATOR") }
        if q.contains(.notThisDevice) { words.append("NOT THIS DEVICE") }
        if q.contains(.experimental) { words.append("EXPERIMENTAL") }
        return words
    }

    /// What VoiceOver says for the badge: the word, then every qualifier, in plain language ("measured, offscreen").
    nonisolated public static func spokenLabel(_ p: Provenance, qualifiers q: Qualifiers = []) -> String {
        var parts = [p.spokenPhrase(device: nil)]
        if q.contains(.cpu) { parts.append("on the CPU") }
        if q.contains(.offscreen) { parts.append("offscreen") }
        if q.contains(.simulator) { parts.append("in the Simulator") }
        if q.contains(.notThisDevice) { parts.append("not on this device") }
        if q.contains(.experimental) { parts.append("experimental") }
        if q.contains(.weakSource) { parts.append("weak source") }
        if q.contains(.sourcesDisagree) { parts.append("sources disagree") }
        if q.contains(.unverified) { parts.append("unverified") }
        return parts.joined(separator: ", ")
    }

    /// The badge's meaning, spoken as the hint (SPEC §12.1 "Means" column, shortened).
    nonisolated public static func meaning(_ p: Provenance) -> String {
        switch p {
        case .live: "Computed now from the current image and parameters."
        case .measured: "Timed or fitted on a named device."
        case .computed: "An exact consequence of the math."
        case .modeled: "An estimate from a stated model."
        case .reference: "Documented by a cited spec or vendor source."
        case .inferred: "About internals the vendor does not expose."
        }
    }
}

/// The drawn badge; a separate view so its scaled metrics read the capped Dynamic Type size.
private struct HonestyBadgeFace: View {
    let provenance: Provenance
    let qualifiers: Qualifiers
    let style: HonestyBadgeStyle
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .caption2) private var glyphSize = InstrumentTypeScale.badgeGlyphMinimum
    @ScaledMetric(relativeTo: .caption2) private var liveDot = 5.0

    private var ink: Color { HonestyBadge.ink(provenance) }
    private var increased: Bool { contrast == .increased }
    private var dashed: Bool { provenance == .inferred }

    var body: some View {
        switch style {
        case .word: word
        case .glyph: glyphOnly
        }
    }

    private var word: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            HStack(alignment: .center, spacing: 3) {
                glyph(size: glyphSize * 0.82)
                Text(([provenance.word] + HonestyBadge.qualifierWords(qualifiers)).joined(separator: " · "))
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                    .tracking(InstrumentTypeScale.labelTracking)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.white.opacity(InstrumentOpacity.badgeFill), in: .capsule)
            .overlay {
                Capsule().strokeBorder(dashed ? ink.opacity(increased ? 1 : 0.7)
                                              : .white.opacity(increased ? InstrumentOpacity.badgeBorderIncreasedContrast
                                                                         : InstrumentOpacity.badgeBorder),
                                       style: StrokeStyle(lineWidth: dashed && increased ? InstrumentMetrics.badgeStrokeIncreasedContrast
                                                                                         : InstrumentMetrics.badgeStroke,
                                                          dash: dashed ? [3, 2] : []))
            }
            if qualifiers.contains(.unverified) {
                Text("UNVERIFIED")
                    .font(.system(.caption2, design: .monospaced))
                    .tracking(InstrumentTypeScale.labelTracking)
                    .foregroundStyle(InstrumentPalette.secondaryInk)
                    .fixedSize()
            }
        }
    }

    private var glyphOnly: some View {
        glyph(size: glyphSize)
            .foregroundStyle(ink)
            .frame(minWidth: glyphSize + (dashed ? 2.5 : 1), minHeight: glyphSize + (dashed ? 2.5 : 1))
            .overlay {
                if dashed {
                    Circle().strokeBorder(ink.opacity(increased ? 1 : 0.85),
                                          style: StrokeStyle(lineWidth: increased ? InstrumentMetrics.badgeStrokeIncreasedContrast
                                                                                  : InstrumentMetrics.badgeStroke + 0.2,
                                                             dash: [2, 1.6]))
                }
            }
    }

    @ViewBuilder private func glyph(size: CGFloat) -> some View {
        switch provenance {
        case .live:
            Circle().frame(width: liveDot, height: liveDot).frame(width: size, height: size)
        case .modeled:
            Text("≈").font(.system(size: size * 1.1, weight: .bold, design: .rounded)).frame(minWidth: size, minHeight: size)
        default:
            Image(systemName: HonestyBadge.symbolName(provenance) ?? "questionmark")
                .font(.system(size: size * (provenance == .inferred ? 0.92 : 0.82), weight: .semibold))
                .frame(minWidth: size, minHeight: size)
        }
    }
}
