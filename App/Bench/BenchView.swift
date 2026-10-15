import SwiftUI
import BlurCore
import BlurGPU

// OWNER: UI-BENCH (entry view seed written by SKEL; frozen name and initialiser `BenchView()`, PLAN S14; SPEC §4.1).
// A minimal Bench that already follows the SPEC §4.1 frame: header; blur strip; the Metro housing around the LIVE Metal
// image window (before/after split, probe crosshair) with the readout band (unit line, hero = the requested value, serif
// meaning, the fixed status row) and the kernel well; the KERNEL and FREQ pills; the rail of seven floors (each chip pushes
// Layers); the deck (FINE + SEMANTIC crowns); the σ Stepper; telemetry; the floating group.
// TODO(UI-BENCH): SPEC §4.1 in full — strip glyph order and context menu, caption-row engravings and truncation order,
// rulers with the ±3σ bracket and SCALE engraving, decks A–E from the entry's DeckArrangement, Parameters panel, compact
// fingerprint card, AX layout (§4.1.10), first-launch focus pull, Reduce Motion / Transparency / Increased Contrast.
public struct BenchView: View {
    @Environment(BenchModel.self) private var bench
    @Environment(AppEnvironment.self) private var app
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .title) private var titleSize = 27.0

    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            let cluster = InstrumentMetrics.cluster(available: Swift.max(200, geometry.size.width - 24))
            let window = cluster.diameter - 24
            ZStack(alignment: .bottom) {
                InstrumentDesignBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        header
                        strip
                        instrument(cluster: cluster, window: window)
                        rail
                        deck
                        sigmaStepper.frame(maxWidth: 380)
                        telemetry
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, InstrumentMetrics.bottomReserve + 28)
                    .frame(maxWidth: 540)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                floatingGroup
            }
            .task(id: Int(window * displayScale)) {
                bench.configureWindow(points: window, scale: displayScale)
                bench.start()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: bench.view.split) { _, split in app.presenter?.options.split = split }
    }

    // MARK: Header and strip

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Blur2ool").font(.system(size: titleSize, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.75)
                Text("BLUR SIMULATOR · WYSIWYG → GPU").font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(2.6)
                    .foregroundStyle(.white.opacity(0.68)).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
            InstrumentGlassIconButton("book.closed", label: "Field guide and settings") {
                bench.sheet = .fieldGuide(.guide, bench.configuration.blur)
            }
        }
        .padding(.horizontal, 12)
    }

    private var strip: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(SpecimenRegistry.generators.map(\.descriptor)) { descriptor in
                    Button(descriptor.menuName) { bench.setSpecimen(descriptor.id, options: .standard) }
                }
            } label: {
                Image(systemName: "photo.on.rectangle.angled").foregroundStyle(InstrumentPalette.actionCyan)
                    .frame(width: 44, height: 44).background(InstrumentPalette.metalDark, in: .rect(cornerRadius: 8))
            }
            .accessibilityLabel("Test image")
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(BlurRegistry.stripOrder, id: \.self) { id in
                        if let entry = BlurRegistry.entry(id) {
                            Button { bench.selectBlur(id) } label: { FootprintGlyph(entry.glyph, isSelected: id == bench.configuration.blur) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(entry.displayName)
                                .accessibilityAddTraits(id == bench.configuration.blur ? .isSelected : [])
                        }
                    }
                    Button("All") { bench.sheet = .catalog(.blurs) }
                        .font(.system(.footnote, design: .monospaced)).foregroundStyle(InstrumentPalette.actionCyan).frame(height: 44)
                }
            }
            .scrollIndicators(.hidden)
        }
        .frame(height: 44)
    }

    // MARK: The instrument

    private func instrument(cluster: (pillWidth: CGFloat, diameter: CGFloat, pillHeight: CGFloat), window: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 6) {
            pill(bench.pills?.kernel, title: "KERNEL", family: .wave, width: cluster.pillWidth, height: cluster.pillHeight, window: window)
            SpecimenHousing {
                VStack(spacing: 0) {
                    captionRow.frame(width: window, height: 24)
                    specimenWindow(window)
                    readoutBand(window).padding(.top, 8)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .frame(width: cluster.diameter)
            pill(bench.pills?.freq, title: "FREQ", family: .spectrum, width: cluster.pillWidth, height: cluster.pillHeight, window: window)
        }
        .frame(maxWidth: .infinity)
    }

    private func pill(_ content: PillPlot?, title: String, family: PillFamily, width: CGFloat, height: CGFloat, window: CGFloat) -> some View {
        InstrumentSignalPill(content ?? PillPlot(title: title, plot: nil, emptyText: "RENDERING…", badge: nil), family: family)
            .frame(width: width, height: height)
            .padding(.top, 24 + (window - height) / 2)
    }

    private var captionRow: some View {
        HStack {
            Text(captionLeft).lineLimit(1).truncationMode(.tail)   // SPEC §4.1: the specimen name truncates first
            Spacer(minLength: 6)
            Text(bench.acknowledged[.a]?.quality == .full || bench.acknowledged[.a] == nil ? "LIVE · METAL" : "PREVIEW")
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.68))
    }

    private var captionLeft: String {
        let blur = bench.entry?.displayName.uppercased() ?? ""
        let specimen = SpecimenRegistry.generator(bench.configuration.specimen)?.descriptor.menuName.uppercased() ?? ""
        return bench.view.split == nil ? "\(blur) · \(specimen)" : "◀ INPUT │ \(blur) ▶ · \(specimen)"
    }

    @ViewBuilder
    private func specimenWindow(_ side: CGFloat) -> some View {
        if let presenter = app.presenter {
            MetalSpecimenView(renderer: presenter, windowPixels: bench.configuration.windowSize, handles: []) { intent in
                handle(intent)
            }
            .frame(width: side, height: side)
            .overlay { overlays(side) }
            .instrumentControlOwnsTouches(identifier: "specimen")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Image window")
            .accessibilityValue("live Metal output, \(bench.entry?.displayName ?? ""), probe at \(bench.configuration.probe.x), \(bench.configuration.probe.y)")
        } else {
            Color.black.frame(width: side, height: side)
        }
    }

    private func overlays(_ side: CGFloat) -> some View {
        let n = CGFloat(Swift.max(1, bench.configuration.windowSize))
        let probe = bench.configuration.probe
        let p = CGPoint(x: (CGFloat(probe.x) + 0.5) / n * side, y: (CGFloat(probe.y) + 0.5) / n * side)
        return Canvas { context, size in
            if let split = bench.view.split {
                var line = Path(); line.move(to: CGPoint(x: split * size.width, y: 0)); line.addLine(to: CGPoint(x: split * size.width, y: size.height))
                context.stroke(line, with: .color(.white.opacity(0.55)), lineWidth: 1)
            }
            var cross = Path()   // instrument-amber crosshair: 13-pt arms, 3-pt gap, the pixel itself never covered
            cross.move(to: CGPoint(x: p.x - 16, y: p.y)); cross.addLine(to: CGPoint(x: p.x - 3, y: p.y))
            cross.move(to: CGPoint(x: p.x + 3, y: p.y)); cross.addLine(to: CGPoint(x: p.x + 16, y: p.y))
            cross.move(to: CGPoint(x: p.x, y: p.y - 16)); cross.addLine(to: CGPoint(x: p.x, y: p.y - 3))
            cross.move(to: CGPoint(x: p.x, y: p.y + 3)); cross.addLine(to: CGPoint(x: p.x, y: p.y + 16))
            context.stroke(cross, with: .color(InstrumentPalette.instrumentAmber), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    private func handle(_ intent: GestureIntent) {
        let n = Double(bench.configuration.windowSize), side = Swift.max(1, n / displayScale)
        func pixel(_ p: SIMD2<Double>) -> PixelPoint { PixelPoint(x: Int((p.x / side * n).rounded(.down)), y: Int((p.y / side * n).rounded(.down))) }
        switch intent {
        case .placeProbe(let p): bench.setProbe(pixel(p))
        case .loupeEnded(let p): if let p { bench.setProbe(pixel(p)) }
        case .panBegan: bench.beginInteraction()
        case .panMoved(let delta):
            let pan = bench.configuration.pan
            bench.setPan(PixelPoint(x: pan.x - Int((delta.x * displayScale).rounded()), y: pan.y - Int((delta.y * displayScale).rounded())))
        case .panEnded: bench.endInteraction()
        default: break
        }
    }

    private func readoutBand(_ window: CGFloat) -> some View {
        let spec = bench.entry?.primarySpec
        let value = spec.flatMap { bench.configuration.parameters.double($0.key) }
        var meaning = ""
        if case .continuous(let c)? = spec?.kind, let value { meaning = c.band(for: value)?.name ?? "" }
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(spec?.unitLine ?? "").font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(2.2)
                    .foregroundStyle(.white.opacity(0.68))
                Text(value.map { spec?.numberStyle.text($0) ?? "" } ?? "—")
                    .font(.system(size: 44, weight: .light, design: .rounded)).monospacedDigit()
                    .foregroundStyle(InstrumentPalette.displayInk).lineLimit(1).minimumScaleFactor(0.7)
                Text(meaning).font(.system(.subheadline, design: .serif, weight: .medium)).italic()
                    .foregroundStyle(InstrumentPalette.instrumentCyan).lineLimit(1)
                Text(bench.status.text).font(.system(size: 11, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(InstrumentPalette.secondaryInk).lineLimit(1).minimumScaleFactor(0.6).frame(height: 14)
                    .accessibilityLabel(bench.status.line.spoken)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button { bench.sheet = .fingerprint(bench.configuration.blur) } label: {
                InstrumentLensSurface(diameter: 88, motionActive: false) {
                    FootprintGlyph(bench.entry?.glyph ?? GlyphSpec(.none), size: 88)
                } readout: { EmptyView() }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Kernel well. Opens the fingerprint card")
        }
        .frame(width: window, height: 104)
    }

    // MARK: Rail, deck, stepper, telemetry

    private var rail: some View {
        HStack(spacing: 4) {
            ForEach(bench.railChips.isEmpty ? Floor.allCases.map { RailChip(floor: $0, value: .notYetMeasured(), comparison: nil) } : bench.railChips) { chip in
                Button { bench.path.append(.layers(chip.floor)) } label: {
                    VStack(spacing: 4) {
                        Text(chip.floor.railLabel).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(InstrumentPalette.secondaryInk)
                        Text(BenchView.chipText(chip.value)).font(.system(size: 13, design: .monospaced)).monospacedDigit()
                            .foregroundStyle(chip.value.value == nil ? InstrumentPalette.secondaryInk : InstrumentPalette.actionCyan)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(.white.opacity(0.025), in: .rect(cornerRadius: InstrumentMetrics.tileRadius))
                    .overlay(alignment: .topTrailing) {
                        if let provenance = chip.value.provenance { HonestyBadge(provenance, style: .glyph).padding(2) }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: InstrumentMetrics.tileRadius)
                            .strokeBorder(.white.opacity(0.06), style: StrokeStyle(lineWidth: 1, dash: chip.value.provenance == .inferred ? [3, 2] : []))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Floor \(chip.floor.rawValue), \(chip.floor.title), \(chip.value.spoken)")
            }
        }
    }

    /// Chips print at most six characters and no units; words that do not fit are abbreviated (`UNVER.`).
    static func chipText(_ value: BadgedValue) -> String {
        if value.qualifiers.contains(.unverified) { return "UNVER." }
        return value.text.count <= 6 ? value.text : String(value.text.prefix(6))
    }

    private var deck: some View {
        let spec = bench.entry?.primarySpec
        let value = spec.flatMap { bench.configuration.parameters.double($0.key) } ?? 0
        let text = spec?.numberStyle.text(value) ?? ""
        var band = ""
        if case .continuous(let c)? = spec?.kind { band = c.band(for: value)?.name ?? "" }
        return HStack(spacing: 24) {
            InstrumentCrown(caption: "FINE", subcaption: "±0.1 PX", role: .fine, detentDegrees: 8,
                            accessibilityLabel: "\(spec?.spokenLabel ?? "value"), fine", accessibilityValue: "\(text) pixels") { detents in
                if let key = spec?.key { bench.step(key, by: detents, semantic: false) }
            }
            InstrumentCrown(caption: "\(spec?.label ?? "") · \(band)", subcaption: "OCTAVE STOPS", role: .semantic, detentDegrees: 20,
                            accessibilityLabel: "\(spec?.spokenLabel ?? "value"), named stops", accessibilityValue: "\(text) pixels, \(band)") { detents in
                if let key = spec?.key { bench.step(key, by: detents, semantic: true) }
            }
        }
        .frame(height: 98)
    }

    private var sigmaStepper: some View {
        let spec = bench.entry?.primarySpec
        if case .continuous(let c)? = spec?.kind, let key = spec?.key {
            return AnyView(DecimalParameterStepper(spec?.label ?? "", value: Binding(
                get: { bench.configuration.parameters.double(key) ?? c.range.lowerBound },
                set: { bench.setParameter(key, .double($0)) }),
                in: c.range, step: c.fineStep, decimals: c.decimals, unit: spec?.unit.symbol ?? "", spokenUnit: spec?.unit.spokenName ?? ""))
        }
        return AnyView(EmptyView())
    }

    private var telemetry: some View {
        InstrumentContentPanel {
            HStack(spacing: 12) {
                telemetryColumn("σ EFF", app.telemetry.sigmaEff ?? .notYetMeasured(unit: "px"))
                telemetryColumn("GPU", app.telemetry.gpu ?? .notYetMeasured(unit: "ms"))
                telemetryColumn("PARITY", app.telemetry.parity ?? .notYetMeasured())
            }
        }
    }

    private func telemetryColumn(_ label: String, _ value: BadgedValue) -> some View {
        VStack(spacing: 5) {
            Text(label).font(.system(.caption2, design: .monospaced)).tracking(1.2).foregroundStyle(InstrumentPalette.secondaryInk)
            BadgedValueText(value, layout: .telemetry)
        }
        .frame(maxWidth: .infinity)
    }

    private var floatingGroup: some View {
        let probe = bench.configuration.probe
        return InstrumentFloatingActionGroup {
            Button { bench.startCompare(nil) } label: { Image(systemName: "rectangle.split.2x1").frame(width: 62, height: 58) }
                .buttonStyle(.glass).accessibilityLabel("Compare")
        } primary: {
            Button { bench.path.append(.trace) } label: {
                Label("Descend from (\(probe.x), \(probe.y))", systemImage: "arrow.down.to.line")
                    .font(.system(size: 15, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 58)
            }
            .buttonStyle(.glassProminent).tint(InstrumentPalette.actionCyan)
        } trailing: {
            Button { bench.sheet = .catalog(.lessons) } label: { Image(systemName: "graduationcap").frame(width: 54, height: 58) }
                .buttonStyle(.glass).accessibilityLabel("Lessons")
        }
    }
}
