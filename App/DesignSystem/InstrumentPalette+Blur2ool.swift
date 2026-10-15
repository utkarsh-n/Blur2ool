import SwiftUI

// OWNER: METRO-COMPONENTS (ARCHITECTURE §5.14; research/metro-adaptation.md §B). The Metro Station tokens the verbatim
// starter (InstrumentDesignSystem.swift: InstrumentPalette, InstrumentMetrics) does not declare, each NAMED once here and
// referenced by name everywhere else (never re-typed as a literal in a component).
//
// Every token line carries exactly one provenance comment, and Tests/BlurCoreTests/METROCOMPONENTS/ parses this file:
//   `// manifest <path>`  the value equals Documentation/metro-station-design-tokens.json at <path> ('/' separates keys;
//                         colour keys keep their dots: `colors/surface.metalLight`). RGB doubles are canonical (sRGB).
//   `// spec <section>`   the Metro spec (design-system-spec.md) or Blur2ool's SPEC states it but the manifest has no key;
//                         the citation names the sentence. The test requires one of the two on every token line.

// MARK: - Colours (manifest `colors`; the starter already declares canvas, content, the four accents, two inks and five signals)

public extension InstrumentPalette {
    static let gaugeHousing = Color(red: 0.027, green: 0.041, blue: 0.055)     // manifest colors/surface.gaugeHousing
    static let metalLight = Color(red: 0.055, green: 0.073, blue: 0.090)       // manifest colors/surface.metalLight
    static let metalDark = Color(red: 0.021, green: 0.032, blue: 0.042)        // manifest colors/surface.metalDark
    static let pillLight = Color(red: 0.055, green: 0.069, blue: 0.095)        // manifest colors/surface.pillLight
    static let pillDark = Color(red: 0.014, green: 0.022, blue: 0.037)         // manifest colors/surface.pillDark
    static let plot = Color(red: 0.022, green: 0.036, blue: 0.047)             // manifest colors/surface.plot
    static let crownBase = Color(red: 0.12, green: 0.15, blue: 0.17)           // manifest colors/metal.crownBase
    static let crownRimLight = Color(red: 0.49, green: 0.57, blue: 0.61)       // manifest colors/metal.crownRimLight
    static let crownRimDark = Color(red: 0.10, green: 0.13, blue: 0.15)        // manifest colors/metal.crownRimDark
    static let crownRimMid = Color(red: 0.32, green: 0.39, blue: 0.43)         // manifest colors/metal.crownRimMid
    static let crownFaceLight = Color(red: 0.27, green: 0.33, blue: 0.37)      // manifest colors/metal.crownFaceLight
    static let crownFaceDark = Color(red: 0.08, green: 0.11, blue: 0.13)       // manifest colors/metal.crownFaceDark
}

// MARK: - Opacities (white ink unless the name says otherwise)

public enum InstrumentOpacity {
    public static let panelFill: Double = 0.85                          // manifest opacity/panelFill
    public static let panelBorder: Double = 0.09                        // manifest opacity/panelBorder
    public static let panelBorderIncreasedContrast: Double = 0.20       // spec SPEC §14 Increased Contrast "Panel borders 0.20"
    public static let grid: Double = 0.025                              // manifest opacity/grid
    public static let environmentWash: Double = 0.085                   // manifest opacity/environmentWash
    public static let lensCompositeReduceTransparency: Double = 1       // manifest opacity/lensCompositeReduceTransparency
    public static let rimLightPeak: Double = 0.085                      // manifest opacity/rimLightPeak
    public static let crownGlassTint: Double = 0.08                     // manifest opacity/crownGlassTint
    public static let pillPrimaryBorder: Double = 0.36                  // manifest opacity/pillPrimaryBorder
    public static let pillPrimaryBorderIncreasedContrast: Double = 0.7  // manifest opacity/pillPrimaryBorderIncreasedContrast
    public static let pillSecondaryBorder: Double = 0.38                // manifest opacity/pillSecondaryBorder
    public static let pillWhiteBorder: Double = 0.10                    // spec Metro §11 "primary opacity 0.36, white 0.10, secondary 0.38"
    public static let metadataInk: Double = 0.68                        // spec Metro §3 "0.68 for dial metadata"
    public static let axisInk: Double = 0.74                            // spec Metro §3 "0.74–0.75 for supporting axes/captions"
    public static let captionInk: Double = 0.75                         // spec Metro §3 "0.74–0.75 for supporting axes/captions"
    public static let plotBorder: Double = 0.075                        // spec Metro §6 "Plot inset … white 0.075 border at 0.6 pt"
    public static let housingShadow: Double = 0.8                       // spec Metro §6 "black 0.8 shadow with radius 22 and y offset 16"
    public static let housingRimLight: Double = 0.36                    // spec Metro §6 "rim transitions through white 0.36, white 0.025, black and white 0.15"
    public static let housingRimMid: Double = 0.025                     // spec Metro §6 rim stop 2 (white 0.025)
    public static let housingRimLow: Double = 0.15                      // spec Metro §6 rim stop 4 (white 0.15)
    public static let housingFaceInk: Double = 0.07                     // spec Metro §6 "recessed face … white 0.07 stroke at 0.6 pt"
    public static let housingSheen: Double = 0.085                      // spec Metro GaugeView sheen (white 0.085 → clear), dropped under Reduce Transparency
    public static let crownShadow: Double = 0.75                        // spec Metro §6 "The crown uses a smaller black 0.75 shadow"
    public static let tileActiveFill: Double = 0.08                     // spec Metro §12 "Active fill is cyan 0.08"
    public static let tileActiveBorder: Double = 0.35                   // spec Metro §12 "border cyan 0.35"
    public static let tileIdleFill: Double = 0.025                      // spec Metro §12 "Idle fill is white 0.025"
    public static let tileIdleBorder: Double = 0.06                     // spec Metro §12 "border white 0.06"
    public static let telemetryDivider: Double = 0.10                   // spec Metro §12 "Dividers are 1 × 30 pt at white 0.10"
    public static let stepperBorder: Double = 0.14                      // spec Metro §9 "cyan 0.14 border at 1 pt"
    public static let badgeFill: Double = 0.06                          // spec SPEC §12.1 "fill white 0.06"
    public static let badgeBorder: Double = 0.12                        // spec SPEC §12.1 "0.6-pt border white 0.12"
    public static let badgeBorderIncreasedContrast: Double = 0.25       // spec SPEC §12.1 "(0.25 under Increased Contrast)"
    public static let disabledControl: Double = 0.4                     // spec Metro §16 "Domain limit: disable invalid action" (dimmed, still legible)
}

// MARK: - Geometry (points)

public extension InstrumentMetrics {
    // Radii
    static let plotRadius: CGFloat = 10                          // manifest radii/plot
    static let tileRadius: CGFloat = 8                           // manifest radii/beatTile
    static let housingRadius: CGFloat = 30                       // spec SPEC §4.1 "SpecimenHousing: radius 30" (METRO §C.1)
    // Strokes
    static let panelStroke: CGFloat = 1                          // manifest strokes/panel
    static let plotStroke: CGFloat = 0.6                         // manifest strokes/plot
    static let gridStroke: CGFloat = 0.5                         // manifest strokes/grid
    static let pillStroke: CGFloat = 0.8                         // manifest strokes/pill
    static let housingRim: CGFloat = 1.4                         // manifest strokes/housingRim
    static let glassRimLight: CGFloat = 0.9                      // manifest strokes/glassRimLight
    static let housingFaceStroke: CGFloat = 0.6                  // spec Metro §6 "white 0.07 stroke at 0.6 pt"
    static let badgeStroke: CGFloat = 0.6                        // spec SPEC §12.1 "0.6-pt border"
    static let badgeStrokeIncreasedContrast: CGFloat = 1         // spec SPEC §14 "INFERRED badge's dashed border 1 pt"
    static let subdivisionMark: CGFloat = 2                      // spec Metro §12 "Subdivision markers are 2-point-high capsules"
    // Layout (manifest `layout`, `componentSpacing`, `gauge`)
    static let portraitContentMax: CGFloat = 540                 // manifest layout/portraitContentMax
    static let clusterMax: CGFloat = 490                         // manifest layout/clusterMax
    static let gaugeMax: CGFloat = 360                           // manifest layout/gaugeMax
    static let pillWidthCompact: CGFloat = 30                    // manifest layout/pillWidthCompact
    static let pillWidthRegular: CGFloat = 36                    // manifest layout/pillWidthRegular
    static let pillWidthBreakpoint: CGFloat = 350                // manifest layout/pillWidthBreakpoint
    static let clusterGap: CGFloat = 6                           // manifest layout/clusterGap
    static let pillHeightMax: CGFloat = 218                      // manifest layout/pillHeightMax
    static let pillHeightRatio: CGFloat = 0.66                   // manifest layout/pillHeightRatio
    static let controlRowMax: CGFloat = 380                      // manifest layout/controlRowMax
    static let crownDiameter: CGFloat = 62                       // manifest layout/crownDiameter
    static let transportLabelMinHeight: CGFloat = 58             // manifest layout/transportLabelMinHeight
    static let bottomReserve: CGFloat = 98                       // manifest layout/bottomContentReserve
    static let screenInset: CGFloat = 12                         // manifest componentSpacing/screenInset
    static let headerInset: CGFloat = 24                         // manifest componentSpacing/headerInset
    static let mainStack: CGFloat = 12                           // manifest componentSpacing/mainStack
    static let transportInset: CGFloat = 22                      // manifest componentSpacing/transportInset
    static let transportBottom: CGFloat = 12                     // manifest componentSpacing/transportBottom
    static let metalInsetRatio: CGFloat = 0.038                  // manifest gauge/metalInsetRatio
    static let transportTop: CGFloat = 10                        // spec Metro §5 "Floating transport: Horizontal inset 22; top 10; bottom 12"
    static let transportLeadingWidth: CGFloat = 62               // spec Metro §12 "62 × 58 for Tap"
    static let transportTrailingWidth: CGFloat = 54              // spec Metro §12 "54 × 58 for settings"
    static let transportRowSpacing: CGFloat = 12                 // spec Metro §12 "Row spacing is 12"
    static let glassContainerSpacing: CGFloat = 14               // spec Metro §12 "glass-container spacing is 14"
    static let floatingContentGap: CGFloat = 28                  // spec SPEC §4.1.7 "bottom reserve = measured height + 28"
    static let tileHeight: CGFloat = 37                          // spec Metro §5 "Beat tile: Height 37"
    static let tileGap: CGFloat = 7                              // spec Metro §5 "Beat tile … row gap 7"
    static let tileRowsBreak: Int = 6                            // spec METRO §C.7 "More than about 6 passes wrap to a second row"
    static let crownCentreExclusion: CGFloat = 7                 // spec Metro §10 "The center has a 7-point exclusion radius"
    static let crownSymbol: CGFloat = 13                         // spec Metro §10 "Symbol: 13 pt semibold"
    static let crownGlassSpacing: CGFloat = 6                    // spec Metro TempoCrownsView GlassEffectContainer(spacing: 6)
    static let captionRowHeight: CGFloat = 14                    // spec Metro §10 "caption rows reserve a scaled 14-point base height"
    static let crownShadowRadius: CGFloat = 6                    // spec Metro §6 "resting radius 6/y 5"
    static let crownShadowY: CGFloat = 5                         // spec Metro §6 "resting radius 6/y 5"
    static let crownPressedShadowRadius: CGFloat = 3             // spec Metro §6 "pressed radius 3/y 2"
    static let crownPressedShadowY: CGFloat = 2                  // spec Metro §6 "pressed radius 3/y 2"
    static let crownKnurls: Int = 40                             // spec Metro §6 "40 knurls and concentric grooves"
    static let housingShadowRadius: CGFloat = 22                 // spec Metro §6 "radius 22 and y offset 16"
    static let housingShadowY: CGFloat = 16                      // spec Metro §6 "radius 22 and y offset 16"
    static let housingBezel: CGFloat = 5                         // spec SPEC §4.1 caption row lives in the 24-pt top margin, so the face lip sits 5 pt inside the rim
    static let pillHorizontalPadding: CGFloat = 5                // spec Metro §11 "horizontal padding 5"
    static let pillVerticalPadding: CGFloat = 10                 // spec Metro §11 "vertical padding 10"
    static let pillInternalGap: CGFloat = 3                      // spec Metro §11 "internal gaps 3"
    static let telemetryDividerHeight: CGFloat = 30              // spec Metro §12 "Dividers are 1 × 30 pt"

    /// Metro §5 cluster formula (layout.clusterMax 490, pillWidthBreakpoint 350, clusterGap 6, gaugeMax 360, pill height
    /// min(218, 0.66·D)). At 430 pt (406 available): pill 36, D 322, pill height 212.5, image window D − 24 = 298 pt.
    static func cluster(available: CGFloat) -> (pillWidth: CGFloat, diameter: CGFloat, pillHeight: CGFloat) {
        let clusterWidth = Swift.min(available, clusterMax)
        let pill = clusterWidth < pillWidthBreakpoint ? pillWidthCompact : pillWidthRegular
        let diameter = Swift.max(120, Swift.min(gaugeMax, clusterWidth - 2 * pill - 2 * clusterGap))
        return (pill, diameter, Swift.min(pillHeightMax, pillHeightRatio * diameter))
    }
}

// MARK: - Type scale (points; scaled with @ScaledMetric relative to caption2 where Metro says so)

public enum InstrumentTypeScale {
    public static let appTitle: CGFloat = 27                            // manifest typography/appTitle/sizePt
    public static let appSubtitleTracking: CGFloat = 2.6                // manifest typography/appSubtitle/trackingPt
    public static let heroUnit: CGFloat = 11                            // manifest typography/heroUnit/baseSizePt
    public static let heroUnitTracking: CGFloat = 2.2                   // manifest typography/heroUnit/trackingPt
    public static let stepperValue: CGFloat = 18                        // manifest typography/stepperValue/sizePt
    public static let stepperLabel: CGFloat = 10                        // manifest typography/stepperLabel/sizePt
    public static let stepperLabelTracking: CGFloat = 1.5               // manifest typography/stepperLabel/trackingPt
    public static let pillTitle: CGFloat = 10                           // manifest typography/pillTitle/baseSizePt
    public static let pillAxis: CGFloat = 9                             // manifest typography/pillAxis/baseSizePt
    public static let captionMinimum: CGFloat = 11                      // manifest typography/reuseCaptionMinimum/baseSizePt
    public static let labelTracking: CGFloat = 1.2                      // spec Metro §4 "Telemetry label: Caption2, mono; tracking 1.2"
    public static let badgeGlyphMinimum: CGFloat = 11                   // spec SPEC §14 "badge glyphs never below 11 pt"
    public static let chipValue: CGFloat = 13                           // spec SPEC §4.1 rail "value 13 pt mono monospaced digits"
    public static let chipValueMaximum: CGFloat = 16                    // spec SPEC §14 "rail values up to 16 pt"
}

// MARK: - Motion and detents

public enum InstrumentMotion {
    public static let detentMaxHz: Double = 20                          // manifest motion/detentMaxHz
    public static let fineDetentDegrees: Double = 8                     // manifest motion/fineDetentDegrees
    public static let coarseDetentDegrees: Double = 20                  // manifest motion/coarseDetentDegrees
    public static let reversalHysteresisRatio: Double = 0.18            // manifest motion/reversalHysteresisRatio
    public static let pillInteriorEase: Double = 0.15                   // spec SPEC §4.1.3 "interiors ease ≤ 150 ms on an accepted change"
    public static let crownTremorDegrees: Double = 0.5                  // spec Metro TempoCrownsView "Sub-half-degree tremor leaves the pending detent calm"
}

/// Core Haptics transient tuning per accepted detent (Metro §15 detent vocabulary).
public enum InstrumentHapticDetent {
    public static let fineUpIntensity: Float = 0.78                     // manifest hapticDetents/fineUp/intensity
    public static let fineUpSharpness: Float = 0.95                     // manifest hapticDetents/fineUp/sharpness
    public static let fineDownIntensity: Float = 0.82                   // manifest hapticDetents/fineDown/intensity
    public static let fineDownSharpness: Float = 0.2                    // manifest hapticDetents/fineDown/sharpness
    public static let semanticUpIntensity: Float = 1                    // manifest hapticDetents/semanticUp/intensity
    public static let semanticUpSharpness: Float = 0.6                  // manifest hapticDetents/semanticUp/sharpness
    public static let semanticDownIntensity: Float = 1                  // manifest hapticDetents/semanticDown/intensity
    public static let semanticDownSharpness: Float = 0.05               // manifest hapticDetents/semanticDown/sharpness
}
