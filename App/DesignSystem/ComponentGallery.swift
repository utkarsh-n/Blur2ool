import SwiftUI
import BlurCore

// OWNER: METRO-COMPONENTS (ARCHITECTURE §5.14; PLAN §4 METRO-COMPONENTS acceptance 7). Every Blur2ool Metro component on
// one scrolling page: the `gallery` launch scenario (`-B2Scenario gallery`), shown by RootView. Frozen name and
// initialiser: `ComponentGallery()`. `-B2Param section=<badges|values|controls|pills|tiles|glyphs|housing>` scrolls to a
// section on launch so each part can be photographed on the phone.
//
// Honesty: every number on this page comes from BlurCore (KernelMath, NumberStyle) at the stated inputs and carries its
// badge (COMPUTED); MEASURED appears only as the documented Mac parity measurement (ARCHITECTURE header, with its device
// stamp and NOT THIS DEVICE) or as "–.––" (not yet measured); the one REFERENCE number cites its source; the INFERRED and
// MODELED rows say what they rest on. Inputs (the hero σ, Stepper, crowns) carry no badge. Nothing here is a Run: the
// housing's window is a SwiftUI drawing and says so.
public struct ComponentGallery: View {
    @State private var running = false
    @State private var groupHeight: CGFloat = 0

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            InstrumentDesignBackground()
            ScrollViewReader { proxy in
                ScrollView {
                    ComponentGalleryColumn(bottomReserve: FloatingGroupHeightKey.contentReserve(forGlassHeight: groupHeight))
                }
                .scrollIndicators(.hidden)
                .task {
                    guard let section = GalleryFixtures.launchSection() else { return }
                    // Twice: the first pass can land before the long column has finished its first layout.
                    try? await Task.sleep(for: .milliseconds(350))
                    proxy.scrollTo(section, anchor: .top)
                    try? await Task.sleep(for: .milliseconds(650))
                    proxy.scrollTo(section, anchor: .top)
                }
            }
            floatingGroup
        }
        .onPreferenceChange(FloatingGroupHeightKey.self) { height in
            Task { @MainActor in groupHeight = height }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Floating group

    private var floatingGroup: some View {
        InstrumentFloatingActionGroup {
            Button {} label: { Label("Compare", systemImage: "rectangle.split.2x1") }
        } primary: {
            Button { running.toggle() } label: {
                Label(running ? "Stop the descent" : "Descend from (447, 455)",
                      systemImage: running ? "stop.fill" : "arrow.down.to.line")
            }
            .tint(running ? InstrumentPalette.actionAmber : InstrumentPalette.actionCyan)
        } trailing: {
            Button {} label: { Label("Lessons", systemImage: "graduationcap") }
        }
    }
}

/// The gallery's scrolling column (every section), or one section alone (`only`) for offscreen renders.
struct ComponentGalleryColumn: View {
    var only: GallerySection? = nil
    var bottomReserve: CGFloat = 0
    @State private var sigma = 12.0
    @State private var angle = 30.0
    @State private var strength = 10.0
    @State private var passTile = 1
    @State private var kawaseTile = 2
    @State private var dualTile = 4
    @Environment(\.dynamicTypeSize) private var dynamicType
    /// The hero numeral scales at accessibility sizes (SPEC §4.1.10: the readout becomes native text there).
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize = 44.0

    private var accessible: Bool { dynamicType.isAccessibilitySize }
    private func shows(_ section: GallerySection) -> Bool {
        only == nil || only == section || (section == .controls && only == .crowns)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if only == nil { header }
            if shows(.badges) { badges.id(GallerySection.badges) }
            if shows(.values) { values.id(GallerySection.values) }
            if shows(.controls) { controls.id(GallerySection.controls) }
            if shows(.pills) { pills.id(GallerySection.pills) }
            if shows(.tiles) { tiles.id(GallerySection.tiles) }
            if shows(.glyphs) { glyphs.id(GallerySection.glyphs) }
            if shows(.housing) { housing.id(GallerySection.housing) }
        }
        .frame(maxWidth: InstrumentMetrics.portraitContentMax)
        .padding(.horizontal, InstrumentMetrics.screenInset)
        .padding(.top, 10)
        .padding(.bottom, bottomReserve)
        .frame(maxWidth: .infinity)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Components")
                .font(.system(size: InstrumentTypeScale.appTitle, weight: .semibold, design: .rounded))
                .foregroundStyle(InstrumentPalette.displayInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if !accessible {
                Text("BLUR2OOL · METRO STATION KIT")
                    .font(.system(size: InstrumentTypeScale.captionMinimum, weight: .medium, design: .monospaced))
                    .tracking(InstrumentTypeScale.appSubtitleTracking)
                    .foregroundStyle(.white.opacity(InstrumentOpacity.metadataInk))
            }
        }
        .padding(.horizontal, InstrumentMetrics.screenInset)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func sectionTitle(_ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(InstrumentPalette.actionCyan)
                .accessibilityAddTraits(.isHeader)
            Rectangle().fill(.white.opacity(InstrumentOpacity.panelBorder)).frame(height: InstrumentMetrics.panelStroke)
            Text(note)
                .font(.subheadline)
                .foregroundStyle(InstrumentPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced, weight: .medium))
            .tracking(InstrumentTypeScale.labelTracking)
            .foregroundStyle(InstrumentPalette.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Badges

    private var badges: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("HONESTY BADGES", "The word is primary; the glyph and the ink repeat it. INFERRED alone has a dashed border.")
            InstrumentContentPanel {
                VStack(alignment: .leading, spacing: 14) {
                    label("SIX WORDS")
                    GalleryFlow(spacing: 8) { ForEach(Provenance.allCases, id: \.self) { HonestyBadge($0) } }
                    label("QUALIFIERS RIDE INSIDE · UNVERIFIED TRAILS")
                    GalleryFlow(spacing: 8) {
                        HonestyBadge(.live, qualifiers: .cpu)
                        HonestyBadge(.measured, qualifiers: .offscreen)
                        HonestyBadge(.measured, qualifiers: .notThisDevice)
                        HonestyBadge(.reference, qualifiers: .unverified)
                    }
                    label("RAIL CHIPS · THE ONE GLYPH-ONLY USE")
                    railChips
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var railChips: some View {
        let chips = GalleryFixtures.railChips(sigma: 12)
        return Group {
            if accessible {
                VStack(spacing: 4) {
                    ForEach(chips) { chip in
                        HStack {
                            Text(chip.floor.railLabel).font(.system(.caption, design: .monospaced))
                                .foregroundStyle(InstrumentPalette.secondaryInk)
                            Spacer()
                            BadgedValueText(chip.value, layout: .row)
                        }
                        .frame(minHeight: InstrumentMetrics.controlTarget)
                        .accessibilityElement(children: .combine)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(chips) { chip in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(chip.floor.railLabel)
                                .font(.system(size: InstrumentTypeScale.captionMinimum, weight: .medium, design: .monospaced))
                                .foregroundStyle(InstrumentPalette.secondaryInk)
                                .lineLimit(1).minimumScaleFactor(0.7)
                                .frame(height: 15)
                            BadgedValueText(chip.value, layout: .chip).frame(height: 22)
                        }
                        .padding(.top, 6)
                        .padding(.leading, 4)
                        .padding(.trailing, 2)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(.white.opacity(InstrumentOpacity.tileIdleFill), in: .rect(cornerRadius: InstrumentMetrics.tileRadius))
                        .overlay {
                            RoundedRectangle(cornerRadius: InstrumentMetrics.tileRadius)
                                .strokeBorder(chip.value.provenance == .inferred ? HonestyBadge.ink(.inferred).opacity(0.7)
                                                                                : .white.opacity(InstrumentOpacity.tileIdleBorder),
                                              style: StrokeStyle(lineWidth: InstrumentMetrics.panelStroke,
                                                                 dash: chip.value.provenance == .inferred ? [3, 2] : []))
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Floor \(chip.floor.rawValue), \(chip.floor.title), \(chip.value.spoken)")
                    }
                }
                .padding(.horizontal, -8)   // the rail uses most of the panel's width, as on the Bench (54-pt chips)
            }
        }
    }

    // MARK: Values

    private var values: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("VALUES", "Every number travels with its unit, its badge and its spoken phrase; captions say what a badge rests on.")
            InstrumentContentPanel {
                VStack(alignment: .leading, spacing: 14) {
                    label("TELEMETRY · σ 12 PX GAUSSIAN")
                    telemetryRow
                    Rectangle().fill(.white.opacity(InstrumentOpacity.panelBorder)).frame(height: 1)
                    label("ROWS")
                    VStack(spacing: 10) {
                        ForEach(GalleryFixtures.rows) { row in
                            if accessible {
                                VStack(alignment: .leading, spacing: 4) {
                                    label(row.label)
                                    BadgedValueText(row.value).frame(maxWidth: .infinity, alignment: .trailing)
                                }
                            } else {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    label(row.label).frame(maxWidth: .infinity, alignment: .leading)
                                    BadgedValueText(row.value)
                                }
                            }
                        }
                    }
                    Rectangle().fill(.white.opacity(InstrumentOpacity.panelBorder)).frame(height: 1)
                    label("INLINE · STATUS ROW")
                    GalleryFlow(spacing: 10) {
                        ForEach(GalleryFixtures.inline.indices, id: \.self) { i in
                            BadgedValueText(GalleryFixtures.inline[i], layout: .inline)
                                .font(.system(.footnote, design: .monospaced))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var telemetryRow: some View {
        let columns = GalleryFixtures.telemetry(sigma: 12)
        return Group {
            if accessible {
                VStack(spacing: 12) {
                    ForEach(columns.indices, id: \.self) { i in
                        VStack(spacing: 5) { label(columns[i].label); BadgedValueText(columns[i].value, layout: .telemetry) }
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(columns.indices, id: \.self) { i in
                        if i > 0 {
                            Rectangle().fill(.white.opacity(InstrumentOpacity.telemetryDivider))
                                .frame(width: 1, height: InstrumentMetrics.telemetryDividerHeight).padding(.top, 14)
                        }
                        VStack(spacing: 5) { label(columns[i].label); BadgedValueText(columns[i].value, layout: .telemetry) }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    // MARK: Controls

    private var band: String { GalleryFixtures.band(for: sigma) }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("CONTROLS", "Inputs carry no badge. Fine and semantic crowns, the angle and a second crown, with the native Stepper twin.")
            InstrumentContentPanel {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SIGMA · PX")
                            .font(.system(size: InstrumentTypeScale.heroUnit, weight: .medium, design: .monospaced))
                            .tracking(InstrumentTypeScale.heroUnitTracking)
                            .foregroundStyle(.white.opacity(InstrumentOpacity.metadataInk))
                        Text(NumberStyle.decimals(1).text(sigma))
                            .font(.system(size: Swift.min(heroSize, 96), weight: .light, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(InstrumentPalette.displayInk)
                            .contentTransition(.identity)
                        Text(band)
                            .font(.system(.subheadline, design: .serif, weight: .medium)).italic()
                            .foregroundStyle(InstrumentPalette.instrumentCyan)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Sigma")
                    .accessibilityValue("\(NumberStyle.decimals(1, spokenUnit: "pixels").spoken(sigma)), \(band)")

                    DecimalParameterStepper("SIGMA", value: $sigma, in: GalleryFixtures.sigmaRange, step: 0.1, decimals: 1,
                                            unit: "px", spokenUnit: "pixels")
                        .frame(maxWidth: InstrumentMetrics.controlRowMax)

                    VStack(spacing: 16) {
                        crownPair(fineCrown, semanticCrown)
                        crownPair(angleCrown, secondCrown)
                    }
                    .id(GallerySection.crowns)
                }
            }
        }
    }

    @ViewBuilder private func crownPair(_ a: some View, _ b: some View) -> some View {
        if accessible {
            VStack(spacing: 18) { a; b }
        } else {
            HStack(alignment: .top, spacing: 24) { a; b }.frame(maxWidth: .infinity)
        }
    }

    private var fineCrown: some View {
        InstrumentCrown(caption: "FINE", subcaption: "±0.1 PX", role: .fine, detentDegrees: InstrumentMotion.fineDetentDegrees,
                        accessibilityLabel: "Sigma, fine",
                        accessibilityValue: NumberStyle.decimals(1, spokenUnit: "pixels").spoken(sigma)) { step in
            sigma = DecimalParameterStepper.stepped(sigma, direction: step, step: 0.1, decimals: 1, in: GalleryFixtures.sigmaRange) ?? sigma
        }
    }

    private var semanticCrown: some View {
        let neighbours = GalleryFixtures.neighbourBands(sigma)
        return InstrumentCrown(caption: "SIGMA · \(band)", subcaption: "\(neighbours.0) ⇆ \(neighbours.1)", role: .semantic,
                               detentDegrees: InstrumentMotion.coarseDetentDegrees, accessibilityLabel: "Sigma, named stops",
                               accessibilityValue: "\(NumberStyle.decimals(1, spokenUnit: "pixels").spoken(sigma)), \(band)") { step in
            sigma = GalleryFixtures.octaveStop(from: sigma, direction: step)
        }
    }

    private var angleCrown: some View {
        InstrumentCrown(caption: "ANGLE · \(NumberStyle.integer().text(angle))°", subcaption: "±1°", role: .angle,
                        detentDegrees: InstrumentMotion.fineDetentDegrees, accessibilityLabel: "Direction",
                        accessibilityValue: NumberStyle.integer(spokenUnit: "degrees").spoken(angle)) { step in
            angle = DecimalParameterStepper.stepped(angle, direction: step, step: 1, decimals: 0, in: 0...179) ?? angle
        }
    }

    private var secondCrown: some View {
        InstrumentCrown(caption: "STRENGTH · \(NumberStyle.decimals(1).text(strength)) %", subcaption: "±0.5 %", role: .second,
                        detentDegrees: InstrumentMotion.fineDetentDegrees, accessibilityLabel: "Zoom strength",
                        accessibilityValue: NumberStyle.decimals(1, spokenUnit: "percent").spoken(strength)) { step in
            strength = DecimalParameterStepper.stepped(strength, direction: step, step: 0.5, decimals: 1, in: 0...50) ?? strength
        }
    }

    // MARK: Pills

    private var pills: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("SIGNAL PILLS", "KERNEL runs downward, FREQ runs upward. Comparisons: B dashed, C dotted, D dash-dot. Negative lobes are shaded and dashed. Turn a σ crown: only the interiors ease.")
            InstrumentContentPanel {
                let fixtures = GalleryFixtures.pills(sigma: sigma)
                HStack(alignment: .top, spacing: 9) {
                    ForEach(fixtures) { fixture in
                        VStack(spacing: 6) {
                            InstrumentSignalPill(fixture.content, family: fixture.family, comparisons: fixture.comparisons)
                                .frame(width: InstrumentMetrics.pillWidthRegular,
                                       height: InstrumentMetrics.cluster(available: 406).pillHeight)
                            Text(fixture.caption)
                                .font(.system(size: InstrumentTypeScale.pillAxis, weight: .medium, design: .monospaced))
                                .foregroundStyle(InstrumentPalette.secondaryInk)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(width: 44)
                                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Tiles

    private var tiles: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("EVENT TILES", "Staged processing: done tiles amber with a short mark, the current tile cyan with an underline. More than six tiles wrap.")
            InstrumentContentPanel {
                VStack(alignment: .leading, spacing: 12) {
                    label("SEPARABLE PASSES")
                    InstrumentEventTiles(GalleryFixtures.tiles(["H", "V"], captions: ["HORIZONTAL", "VERTICAL"], current: passTile,
                                                               spoken: ["Pass one, horizontal", "Pass two, vertical"])) { passTile = $0 }
                    label("KAWASE OFFSETS")
                    InstrumentEventTiles(GalleryFixtures.tiles(["0", "1", "2", "2", "3"], captions: nil, current: kawaseTile,
                                                               spoken: (0..<5).map { "Kawase pass \($0 + 1)" })) { kawaseTile = $0 }
                    label("DUAL KAWASE LEVELS")
                    InstrumentEventTiles(GalleryFixtures.tiles(["↓1", "↓2", "↓3", "↓4", "↓5", "↓6", "↑6", "↑5", "↑4", "↑3", "↑2", "↑1"],
                                                               captions: nil, current: dualTile,
                                                               spoken: (0..<12).map { $0 < 6 ? "Down sample to level \($0 + 1)" : "Up sample to level \(12 - $0)" })) {
                        dualTile = $0
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Glyphs

    private var glyphs: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("FOOTPRINT GLYPHS", "Every GlyphKind: a blur's 2-D footprint in instrument cyan on recessed metal.")
            InstrumentContentPanel {
                VStack(alignment: .leading, spacing: 14) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: accessible ? 3 : 6), spacing: 10) {
                        ForEach(GalleryFixtures.glyphs, id: \.kind) { spec in
                            VStack(spacing: 4) {
                                FootprintGlyph(spec)
                                Text(FootprintGlyph.name(spec.kind))
                                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(InstrumentPalette.secondaryInk)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Glyph \(FootprintGlyph.name(spec.kind).lowercased())")
                        }
                    }
                    HStack(alignment: .center, spacing: 18) {
                        VStack(spacing: 4) {
                            FootprintGlyph(GlyphSpec(.rings, [1, 2, 3]), isSelected: true)
                            label("SELECTED")
                        }
                        VStack(spacing: 4) {
                            InstrumentLensSurface(diameter: 88, motionActive: false) {
                                FootprintGlyph(GlyphSpec(.polygon, [6, 0]), size: 88)
                            } readout: { EmptyView() }
                            label("KERNEL WELL · GLASS")
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Kernel well: a hexagon footprint under the fixed glass lens")
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: Housing

    private var housing: some View {
        let cluster = InstrumentMetrics.cluster(available: 406)
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle("HOUSING", "Opaque metal around the image window: radius 30, four-stop rim, black shadow. Nothing translucent covers the window.")
            SpecimenHousing {
                VStack(spacing: 0) {
                    HStack {
                        Text("SIEMENS STAR").lineLimit(1)
                        Spacer(minLength: 6)
                        Text("SWIFTUI CANVAS · NOT A RUN").lineLimit(1).fixedSize()
                    }
                    .font(.system(size: InstrumentTypeScale.captionMinimum, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(InstrumentOpacity.metadataInk))
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .frame(height: 24)
                    GallerySiemensStar()
                        .frame(height: 200)
                        .clipShape(.rect)
                        .accessibilityLabel("A Siemens star drawn by SwiftUI, not a blur run")
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SIGMA · PX")
                                .font(.system(size: InstrumentTypeScale.heroUnit, weight: .medium, design: .monospaced))
                                .tracking(InstrumentTypeScale.heroUnitTracking)
                                .foregroundStyle(.white.opacity(InstrumentOpacity.metadataInk))
                            Text(NumberStyle.decimals(1).text(sigma))
                                .font(.system(size: 44, weight: .light, design: .rounded)).monospacedDigit()
                                .foregroundStyle(InstrumentPalette.displayInk)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text(band)
                                .font(.system(.subheadline, design: .serif, weight: .medium)).italic()
                                .foregroundStyle(InstrumentPalette.instrumentCyan)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        InstrumentLensSurface(diameter: 88, motionActive: false) {
                            FootprintGlyph(GlyphSpec(.rings, [1, 2, 3]), size: 88)
                        } readout: { EmptyView() }
                        .accessibilityHidden(true)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .frame(width: cluster.diameter)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Sections and fixtures

enum GallerySection: String, CaseIterable, Hashable { case badges, values, controls, crowns, pills, tiles, glyphs, housing }

struct GalleryPillFixture: Identifiable {
    var id: String
    var content: PillPlot
    var family: PillFamily
    var comparisons: [PillPlot]
    var caption: String
}

struct GalleryRow: Identifiable {
    var id: String { label }
    var label: String
    var value: BadgedValue
}

/// The gallery's data: real BlurCore numbers at stated inputs, each with its badge (tested for honesty on the phone).
enum GalleryFixtures {
    static let sigmaRange: ClosedRange<Double> = 0.3...64
    static let octaveStops: [Double] = [0.5, 1, 2, 4, 8, 16, 32, 64]
    /// SPEC §9.2 σ bands (Blur2ool's own descriptive words, not a standard).
    static let bands: [(upper: Double, name: String)] = [(0.5, "Sub-pixel"), (1.5, "Anti-alias"), (4, "Softened"), (12, "Frosted"),
                                                          (32, "Backdrop"), (.infinity, "Fog")]

    static func launchSection() -> GallerySection? {
        LaunchScenario.parse(ProcessInfo.processInfo.arguments)?.parameters["section"].flatMap(GallerySection.init(rawValue:))
    }

    static func band(for sigma: Double) -> String { bands.first { sigma < $0.upper }?.name ?? "Fog" }

    static func neighbourBands(_ sigma: Double) -> (String, String) {
        let index = bands.firstIndex { sigma < $0.upper } ?? bands.count - 1
        return (index > 0 ? bands[index - 1].name : "—", index + 1 < bands.count ? bands[index + 1].name : "—")
    }

    /// The semantic crown's next or previous octave stop (strictly above or below the current σ).
    static func octaveStop(from sigma: Double, direction: Int) -> Double {
        if direction > 0 { return octaveStops.first { $0 > sigma + 1e-9 } ?? sigma }
        return octaveStops.last { $0 < sigma - 1e-9 } ?? sigma
    }

    static func tiles(_ titles: [String], captions: [String]?, current: Int, spoken: [String]) -> [EventTile] {
        titles.indices.map { i in
            EventTile(id: i, title: titles[i], caption: captions?[i], state: i < current ? .done : i == current ? .current : .idle,
                      accessibilityLabel: spoken[i])
        }
    }

    // Values (COMPUTED by BlurCore at the stated σ).
    static func railChips(sigma: Double) -> [RailChip] {
        let k = KernelMath.gaussianSampled(sigma: sigma)
        let swiftUIPoints = sigma / (0.90 * 3)
        return [
            RailChip(floor: .slide, value: .number(swiftUIPoints, .decimals(1, unit: "pt", spokenUnit: "points"), .inferred,
                                                   caption: "MACOS LAW · NOT YET MEASURED ON THIS PHONE"), comparison: nil),
            RailChip(floor: .api, value: .number(sigma, .decimals(1, unit: "px", spokenUnit: "pixels"), .computed), comparison: nil),
            RailChip(floor: .math, value: .words("G", spoken: "Gaussian", .computed), comparison: nil),
            RailChip(floor: .kernel, value: .number(Double(k.tapCount), .integer(noun: CountNoun("tap", "taps")), .computed), comparison: nil),
            RailChip(floor: .algorithm, value: .words("2×", spoken: "two passes", .computed), comparison: nil),
            RailChip(floor: .gpu, value: .notYetMeasured(unit: "ms"), comparison: nil),
            RailChip(floor: .pixels, value: .words("—", spoken: "no output: the gallery renders no image", .live), comparison: nil),
        ]
    }

    static func telemetry(sigma: Double) -> [(label: String, value: BadgedValue)] {
        let k = KernelMath.gaussianSampled(sigma: sigma)
        return [
            ("σ EFF", .number(k.sigma, .decimals(2, unit: "px", spokenUnit: "pixels"), .computed)),
            ("TAPS", .number(Double(k.tapCount), .integer(noun: CountNoun("tap", "taps")), .computed)),
            ("GPU", .notYetMeasured(unit: "ms")),
        ]
    }

    static var rows: [GalleryRow] {
        let freqs = stride(from: 0.0, through: 0.5, by: 1.0 / 512).map { $0 }
        let boxMin = KernelMath.response(KernelMath.box(radius: 4), frequencies: freqs).min() ?? 0
        let nyquist = KernelMath.response(KernelMath.gaussianSampled(sigma: 1), frequencies: [0.5])[0]
        let mac = DeviceStamp(deviceModel: "Mac (Apple M1 Max)", gpuName: "Apple M1 Max", gpuFamily: "Apple7", osVersion: "macOS 27.2",
                              osBuild: "26B5101f", isSimulator: false, date: galleryDate, thermal: .nominal, lowPowerMode: false)
        return [
            GalleryRow(label: "MIN H · BOX R 4", value: .number(boxMin, .significant(3), .computed)),
            GalleryRow(label: "H(0.5) · GAUSSIAN σ 1", value: .number(nyquist, .significant(2), .computed)),
            GalleryRow(label: "LENS OPACITY · METRO", value: .number(0.48, .decimals(2), .reference,
                                                                     source: SourceRef("Metro Station design-system-spec §6, opacity.lensComposite"))),
            GalleryRow(label: "COPY BANDWIDTH · A17 PRO", value: .number(51.2, .decimals(1, unit: "GB/s", spokenUnit: "gigabytes per second"),
                                                                         .modeled, qualifiers: .weakSource,
                                                                         source: SourceRef("research/gpu-pipeline.md"), caption: "UNVERIFIED PEAK")),
            GalleryRow(label: "SWIFTUI .blur σ 12 PX", value: .number(12 / (0.90 * 3), .decimals(1, unit: "pt", spokenUnit: "points"),
                                                                       .inferred, caption: "MACOS LAW · NOT YET MEASURED HERE")),
            GalleryRow(label: "PARITY · GAUSSIAN SEEDS", value: .number(9.77e-4, .significant(3), .measured, qualifiers: .notThisDevice,
                                                                        device: mac)),
            GalleryRow(label: "PHOTOSHOP GAUSSIAN RADIUS", value: .unverified("Photoshop Gaussian radius")),
        ]
    }

    /// 14 October 2026, the day ARCHITECTURE.md recorded the Mac parity measurement.
    static var galleryDate: Date {
        var parts = DateComponents(); parts.year = 2026; parts.month = 10; parts.day = 14; parts.hour = 12
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    static var inline: [BadgedValue] {
        let k = KernelMath.gaussianSampled(sigma: 12)
        let table = KernelMath.linearSampledTable(k)
        return [
            .number(Double(2 * table.fetchesPerPass), .integer(noun: CountNoun("fetch", "fetches")), .computed),
            .number(2, .integer(noun: CountNoun("pass", "passes")), .computed),
        ]
    }

    // Pills (COMPUTED by BlurCore; the local zoom PSF at a stated distance).
    static func pills(sigma: Double) -> [GalleryPillFixture] {
        let freqs = stride(from: 0.0, through: 0.5, by: 1.0 / 256).map { $0 }
        let computed = BadgedValue.words("COMPUTED", .computed)
        let gauss = KernelMath.gaussianSampled(sigma: sigma)
        let box = KernelMath.box(radius: 4)
        let box3 = KernelMath.convolve(KernelMath.convolve(box, box), box)
        let boxSigma = box.sigma
        let gaussMatch = KernelMath.gaussianSampled(sigma: boxSigma)

        func stems(_ k: Kernel1D, name: String) -> PlotSeries {
            let peak = k.weights.map(abs).max() ?? 1
            return PlotSeries(name: name, xs: k.weights.indices.map { k.offset($0) }, ys: k.weights.map { $0 / peak },
                              style: .stems, role: .primary, provenance: .computed)
        }
        func curve(_ k: Kernel1D, role: SeriesRole = .primary, style: SeriesStyle = .solid, name: String) -> PlotSeries {
            let peak = k.weights.map(abs).max() ?? 1
            return PlotSeries(name: name, xs: k.weights.indices.map { k.offset($0) }, ys: k.weights.map { $0 / peak },
                              style: style, role: role, provenance: .computed)
        }
        func response(_ k: Kernel1D, name: String, role: SeriesRole = .primary) -> PlotSeries {
            PlotSeries(name: name, xs: freqs, ys: KernelMath.response(k.normalised, frequencies: freqs), style: .solid, role: role,
                       provenance: .computed)
        }
        func minus3dB(_ ys: [Double]) -> Double? {
            let target = 1 / 2.0.squareRoot()
            for i in 1..<ys.count where ys[i - 1] >= target && ys[i] < target {
                let t = (ys[i - 1] - target) / (ys[i - 1] - ys[i])
                return freqs[i - 1] + (freqs[i] - freqs[i - 1]) * t
            }
            return nil
        }
        func kernelAxes(_ extent: Double) -> (PlotAxis, PlotAxis) {
            (PlotAxis(label: "offset", unit: "px", range: -extent...extent), PlotAxis(label: "weight", normalized: true))
        }
        let freqAxes = (PlotAxis(label: "frequency", unit: "c/px", range: 0...0.5), PlotAxis(label: "H", normalized: true))

        // 1 · KERNEL: Gaussian σ taps with the continuous kernel as the quiet reference.
        let r = Double(KernelMath.gaussianRadius(sigma: sigma))
        let continuousXs = stride(from: -r, through: r, by: Swift.max(0.25, r / 48)).map { $0 }
        let continuous = PlotSeries(name: "continuous", xs: continuousXs, ys: continuousXs.map { exp(-$0 * $0 / (2 * sigma * sigma)) },
                                    style: .quiet, role: .reference, provenance: .computed)
        let kAxes = kernelAxes(r)
        let gaussKernel = PillPlot(title: "KERNEL", plot: PlotSpec(xAxis: kAxes.0, yAxis: kAxes.1, series: [continuous, stems(gauss, name: "taps")],
                                                                   accessibilitySummary: "Gaussian taps, sigma \(NumberStyle.decimals(1).spoken(sigma)) pixels, normalized to the peak"),
                                   emptyText: nil, badge: computed)
        // 2 · FREQ: the DFT of those taps (signed) over the analytic response, with the −3 dB marker.
        let gResponse = response(gauss, name: "DFT of the taps")
        let analytic = PlotSeries(name: "continuous", xs: freqs, ys: freqs.map { KernelMath.gaussianResponse(sigma: sigma, frequency: $0) },
                                  style: .quiet, role: .reference, provenance: .computed)
        let gMarkers = minus3dB(gResponse.ys).map { [PlotMarker(x: $0, label: "minus 3 dB", kind: .minus3dB, provenance: .computed)] } ?? []
        let gaussFreq = PillPlot(title: "FREQ", plot: PlotSpec(xAxis: freqAxes.0, yAxis: freqAxes.1, series: [analytic, gResponse],
                                                               markers: gMarkers, showsZeroLine: true,
                                                               accessibilitySummary: "Gaussian response: the DFT of the taps over the continuous curve"),
                                 emptyText: nil, badge: computed)
        // 3 · KERNEL: box r 4 with the effective kernel of three passes (depth) and a σ-matched Gaussian (B, dashed).
        let bAxes = kernelAxes(12)
        let boxKernel = PillPlot(title: "KERNEL", plot: PlotSpec(xAxis: bAxes.0, yAxis: bAxes.1,
                                                                 series: [curve(box3, role: .depth, name: "three passes"), stems(box, name: "box taps")],
                                                                 accessibilitySummary: "Box of radius 4, nine equal taps; three passes approach a bell"),
                                 emptyText: nil, badge: computed)
        let boxKernelB = PillPlot(title: "GAUSSIAN", plot: PlotSpec(xAxis: bAxes.0, yAxis: bAxes.1, series: [curve(gaussMatch, name: "Gaussian")],
                                                                    accessibilitySummary: "sigma-matched Gaussian"), emptyText: nil, badge: computed)
        // 4 · FREQ: the box's signed response (negative lobes) against B Gaussian, C tent, D binomial.
        let boxResponse = response(box, name: "box H")
        let boxFreq = PillPlot(title: "FREQ", plot: PlotSpec(xAxis: freqAxes.0, yAxis: freqAxes.1, series: [boxResponse],
                                                             markers: [PlotMarker(x: 1.0 / 9, label: "first zero", kind: .firstZero, provenance: .computed)],
                                                             showsZeroLine: true,
                                                             accessibilitySummary: "Box response, signed: it goes below zero, so fine stripes invert"),
                               emptyText: nil, badge: computed)
        func comparison(_ k: Kernel1D, _ title: String) -> PillPlot {
            PillPlot(title: title, plot: PlotSpec(xAxis: freqAxes.0, yAxis: freqAxes.1, series: [response(k, name: title)], showsZeroLine: true,
                                                  accessibilitySummary: title), emptyText: nil, badge: computed)
        }
        // 5 · LOCAL @ PROBE: radial zoom, strength 10 % at 120 px from the centre → a 12-px box along the radius.
        let zoomTaps = (0...12).map { -Double($0) }
        let zoomPlot = PlotSpec(xAxis: PlotAxis(label: "offset along the radius", unit: "px", range: -12...12),
                                yAxis: PlotAxis(label: "weight", normalized: true),
                                series: [PlotSeries(name: "local taps", xs: zoomTaps, ys: zoomTaps.map { _ in 1 }, style: .stems,
                                                    role: .primary, provenance: .computed)],
                                accessibilitySummary: "Local kernel of a radial zoom at strength 10 percent, 120 pixels from the centre: a 12 pixel line toward the centre")
        let local = PillPlot(title: "LOCAL @ PROBE", plot: zoomPlot, emptyText: nil, badge: computed)
        // 6 · rank filter: no transfer function. 7 · system material: not exposed.
        let rank = PillPlot(title: "FREQ", plot: nil, emptyText: "N/A · RANK", badge: computed)
        let system = PillPlot(title: "FREQ", plot: nil, emptyText: "INFERRED — NOT EXPOSED", badge: .words("INFERRED", .inferred))

        return [
            GalleryPillFixture(id: "g-kernel", content: gaussKernel, family: .wave, comparisons: [], caption: "GAUSS σ"),
            GalleryPillFixture(id: "g-freq", content: gaussFreq, family: .spectrum, comparisons: [], caption: "GAUSS σ"),
            GalleryPillFixture(id: "b-kernel", content: boxKernel, family: .wave, comparisons: [boxKernelB], caption: "BOX · B"),
            GalleryPillFixture(id: "b-freq", content: boxFreq, family: .spectrum,
                               comparisons: [comparison(gaussMatch, "Gaussian"), comparison(KernelMath.tent(radius: 4), "tent"),
                                             comparison(KernelMath.binomial(order: 8), "binomial")], caption: "BOX · BCD"),
            GalleryPillFixture(id: "local", content: local, family: .wave, comparisons: [], caption: "ZOOM"),
            GalleryPillFixture(id: "rank", content: rank, family: .spectrum, comparisons: [], caption: "MEDIAN"),
            GalleryPillFixture(id: "system", content: system, family: .spectrum, comparisons: [], caption: "GLASS"),
        ]
    }

    /// One representative GlyphSpec per GlyphKind (every case, `none` included).
    static var glyphs: [GlyphSpec] {
        GlyphKind.allCases.map { kind in
            switch kind {
            case .rings: GlyphSpec(.rings, [1, 2, 3])
            case .polygon: GlyphSpec(.polygon, [6, 0])
            case .rays: GlyphSpec(.rays, [12])
            case .arcs: GlyphSpec(.arcs, [3])
            case .segment: GlyphSpec(.segment, [30])
            case .ellipse: GlyphSpec(.ellipse, [0.45, -20])
            case .diagonalTaps: GlyphSpec(.diagonalTaps, [0, 1, 2, 2, 3])
            case .pyramid: GlyphSpec(.pyramid, [4])
            case .grid: GlyphSpec(.grid, [4])
            case .comet: GlyphSpec(.comet, [-30])
            case .dots: GlyphSpec(.dots, [22])
            default: GlyphSpec(kind)
            }
        }
    }

    /// Every badged value the gallery shows (the AppTests run `honestyViolations` over all of them).
    static var allValues: [BadgedValue] {
        railChips(sigma: 12).map(\.value) + telemetry(sigma: 12).map(\.value) + rows.map(\.value) + inline
            + pills(sigma: 12).flatMap { [$0.content.badge] + $0.comparisons.map(\.badge) }.compactMap { $0 }
    }
}

// MARK: - Small helpers

/// Wraps its children into rows (badges, inline values) so nothing truncates at accessibility sizes.
private struct GalleryFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(Swift.max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: Swift.min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = Swift.max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

/// A Siemens star (36 cycles) drawn by SwiftUI for the housing demonstration: crisp, high contrast, no numbers.
private struct GallerySiemensStar: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = hypot(size.width, size.height)
            for k in 0..<36 {
                let a0 = Double(k) * 2 * .pi / 36, a1 = a0 + .pi / 36
                var wedge = Path()
                wedge.move(to: c)
                wedge.addLine(to: CGPoint(x: c.x + r * cos(a0), y: c.y + r * sin(a0)))
                wedge.addLine(to: CGPoint(x: c.x + r * cos(a1), y: c.y + r * sin(a1)))
                wedge.closeSubpath()
                context.fill(wedge, with: .color(InstrumentPalette.displayInk.opacity(0.92)))
            }
            var cross = Path()
            cross.move(to: CGPoint(x: c.x - 13, y: c.y)); cross.addLine(to: CGPoint(x: c.x - 3, y: c.y))
            cross.move(to: CGPoint(x: c.x + 3, y: c.y)); cross.addLine(to: CGPoint(x: c.x + 13, y: c.y))
            cross.move(to: CGPoint(x: c.x, y: c.y - 13)); cross.addLine(to: CGPoint(x: c.x, y: c.y - 3))
            cross.move(to: CGPoint(x: c.x, y: c.y + 3)); cross.addLine(to: CGPoint(x: c.x, y: c.y + 13))
            context.stroke(cross, with: .color(InstrumentPalette.instrumentAmber), lineWidth: 1)
        }
    }
}
