import SwiftUI

// OWNER: METRO-COMPONENTS (frozen initialiser, ARCHITECTURE §5.14; Metro §12 "Floating action group"; METRO §C.9;
// SPEC §4.1.7, §14). Three native glass controls over the page in ONE GlassEffectContainer(spacing: 14), row spacing 12,
// horizontal inset 22, top 10, bottom 12, and no backing strip (Metro: "It has no black backing strip").
//   • Label frames (Metro §12): leading 62 × 58, primary flexible × ≥ 58, trailing 54 × 58. Hosts usually pass Buttons
//     with Labels; the group lays a `Label` out as icon-over-title in the side slots and icon + title in the primary,
//     defaults the side buttons to `.glass` and the primary to `.glassProminent` tinted action cyan (a host's own
//     `.buttonStyle`/`.tint` closer to its Button wins, e.g. amber while running).
//   • Accessibility sizes: icon-only labels with the full title still spoken (SPEC §4.1.7; METRO §F.1 item 10).
//   • Reduce Transparency: an opaque canvas strip behind the row (SPEC §14 "falls back to an opaque safeAreaInset strip").
//   • `FloatingGroupHeightKey` reports the MEASURED height of the glass row (the buttons with their native glass padding,
//     not the label frames); the scroll content reserves height + 28 (SPEC §4.1.7).

/// Reports the floating group's measured glass height (the scroll content's bottom reserve = height + 28).
public struct FloatingGroupHeightKey: PreferenceKey {
    public static let defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = Swift.max(value, nextValue()) }

    /// The bottom reserve scrolled content needs above a group of measured glass height `height` (SPEC §4.1.7: + 28).
    public static func contentReserve(forGlassHeight height: CGFloat) -> CGFloat {
        height + InstrumentMetrics.floatingContentGap
    }
}

public struct InstrumentFloatingActionGroup<Leading: View, Primary: View, Trailing: View>: View {
    private let leading: Leading
    private let primary: Primary
    private let trailing: Trailing
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(@ViewBuilder leading: () -> Leading, @ViewBuilder primary: () -> Primary, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading(); self.primary = primary(); self.trailing = trailing()
    }

    public var body: some View {
        let iconOnly = dynamicType.isAccessibilitySize
        GlassEffectContainer(spacing: InstrumentMetrics.glassContainerSpacing) {
            HStack(spacing: InstrumentMetrics.transportRowSpacing) {
                leading
                    .labelStyle(FloatingGroupLabelStyle(slot: .side(InstrumentMetrics.transportLeadingWidth), iconOnly: iconOnly))
                    .buttonStyle(.glass)
                primary
                    .labelStyle(FloatingGroupLabelStyle(slot: .primary, iconOnly: iconOnly))
                    .buttonStyle(.glassProminent)
                    .tint(InstrumentPalette.actionCyan)
                    .frame(maxWidth: .infinity)
                trailing
                    .labelStyle(FloatingGroupLabelStyle(slot: .side(InstrumentMetrics.transportTrailingWidth), iconOnly: iconOnly))
                    .buttonStyle(.glass)
            }
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: FloatingGroupHeightKey.self, value: geo.size.height)
                }
            }
        }
        .padding(.horizontal, InstrumentMetrics.transportInset)
        .padding(.top, InstrumentMetrics.transportTop)
        .padding(.bottom, InstrumentMetrics.transportBottom)
        .background {
            if reduceTransparency {
                InstrumentPalette.canvas.ignoresSafeArea(edges: .bottom)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

/// Lays out the Labels hosts pass: icon over a caption title in the side slots (label frame 62 × 58 / 54 × 58), icon and
/// title side by side in the primary (flexible × ≥ 58), and icon-only at accessibility sizes (the title stays the spoken
/// label because the Label's own accessibility is preserved by `.iconOnly`).
private struct FloatingGroupLabelStyle: LabelStyle {
    enum Slot { case side(CGFloat), primary }
    let slot: Slot
    let iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if iconOnly {
                Label(configuration).labelStyle(.iconOnly)
                    .font(.system(size: 20, weight: .medium))
                    .frame(minWidth: sideWidth, minHeight: InstrumentMetrics.transportLabelMinHeight)
            } else {
                switch slot {
                case .side(let width):
                    VStack(spacing: 3) {
                        configuration.icon.font(.system(size: 17, weight: .medium))
                        configuration.title
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(width: width, height: InstrumentMetrics.transportLabelMinHeight)
                case .primary:
                    HStack(spacing: 8) {
                        configuration.icon.font(.system(size: 17, weight: .semibold))
                        configuration.title
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: InstrumentMetrics.transportLabelMinHeight)
                }
            }
        }
    }

    private var sideWidth: CGFloat {
        if case .side(let width) = slot { return width }
        return InstrumentMetrics.transportLeadingWidth
    }
}
