import SwiftUI

// OWNER: METRO-COMPONENTS (frozen initialiser, ARCHITECTURE §5.14; Metro §6 "Metal recipe", §8; METRO §B.5, §C.1;
// SPEC §4.1 "Specimen housing"). The opaque rectangular metal housing of the primary object, built from the gauge recipe
// of Metro Station's GaugeView with Blur2ool's rectangle (radius 30):
//   • body: gauge-housing metal with the black 0.8 shadow (radius 22, y 16) and the 1.4-pt rim through white 0.36 →
//     white 0.025 → black → white 0.15 (top-leading → bottom-trailing);
//   • recessed face: metalLight → metalDark inside a 5-pt bezel, edged by the white 0.07 face stroke at 0.6 pt; the
//     bezel is narrower than the gauge's 0.038·D because the caption row is engraved in the housing's 24-pt top margin;
//   • a faint top-leading sheen (white 0.085 → clear), dropped under Reduce Transparency; Increased Contrast strengthens
//     the rim and the face edge.
// The housing is a still frame (it never moves); nothing translucent is drawn over the content (the Specimen rule,
// METRO §C.1): every layer here sits BEHIND the content.
public struct SpecimenHousing<Content: View>: View {
    private let content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    private var increased: Bool { contrast == .increased }

    public var body: some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: InstrumentMetrics.housingRadius)
                        .fill(InstrumentPalette.gaugeHousing)
                        .shadow(color: .black.opacity(InstrumentOpacity.housingShadow),
                                radius: InstrumentMetrics.housingShadowRadius, y: InstrumentMetrics.housingShadowY)
                    RoundedRectangle(cornerRadius: InstrumentMetrics.housingRadius - InstrumentMetrics.housingBezel)
                        .fill(LinearGradient(colors: [InstrumentPalette.metalLight, InstrumentPalette.metalDark],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .padding(InstrumentMetrics.housingBezel)
                    RoundedRectangle(cornerRadius: InstrumentMetrics.housingRadius - InstrumentMetrics.housingBezel)
                        .strokeBorder(.white.opacity(increased ? InstrumentOpacity.housingFaceInk * 2.5 : InstrumentOpacity.housingFaceInk),
                                      lineWidth: InstrumentMetrics.housingFaceStroke)
                        .padding(InstrumentMetrics.housingBezel)
                    if !reduceTransparency {
                        RoundedRectangle(cornerRadius: InstrumentMetrics.housingRadius - InstrumentMetrics.housingBezel)
                            .fill(RadialGradient(colors: [.white.opacity(InstrumentOpacity.housingSheen), .clear],
                                                 center: UnitPoint(x: 0.18, y: 0.04), startRadius: 0, endRadius: 360))
                            .padding(InstrumentMetrics.housingBezel)
                    }
                }
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: InstrumentMetrics.housingRadius)
                    .strokeBorder(LinearGradient(stops: [
                        .init(color: .white.opacity(increased ? 0.55 : InstrumentOpacity.housingRimLight), location: 0),
                        .init(color: .white.opacity(increased ? 0.10 : InstrumentOpacity.housingRimMid), location: 0.35),
                        .init(color: .black, location: 0.7),
                        .init(color: .white.opacity(increased ? 0.30 : InstrumentOpacity.housingRimLow), location: 1)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: InstrumentMetrics.housingRim)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}
