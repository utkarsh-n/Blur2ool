import Foundation
import SwiftUI
import MetalKit
import UIKit
import BlurCore
import BlurGPU

// OWNER: UI-SPECIMEN (ARCHITECTURE §1 `App/Bench/SpecimenWindow/`, §5.9, §8.2; SPEC §4.1.3, §4.1.9 f–g, §8.3, §14).
// The Bench's image window as one component, for UI-BENCH to place inside the housing (and UI-COMPARE to drive):
//   • the on-demand MTKView (MetalSpecimenView) presenting 1 : 1, nearest zoom to 8×, the split, the Compare views;
//   • the UIKit touch layer → SpecimenGestureArbiter → intents performed here: tap = probe, drag = pan (whole pixels,
//     rubber-banded at ±256 px) or, zoomed in, pan of the magnified view; pinch = zoom about the fingers, snapping to
//     1 · 2 · 4 · 8; long press = the opaque Metal loupe; handle drags (dividers, ⊕ centres, focus lines, iris, ramp ends);
//   • SwiftUI overlays: probe crosshair, handles, divider, loupe (never glass, never hit-tested);
//   • the Tier S slot hosting SystemExhibitView (FAM-F10) with our Metal model on its right;
//   • the image's VoiceOver element (adjustable probe, rotors Probe axis / Probe step, custom actions) and adjustable
//     handle elements.
// Requested state lives in BenchModel (ENGINE); this view only calls its intents and reads acknowledged Runs.

public struct SpecimenWindow: View {
    @Environment(BenchModel.self) private var bench
    @Environment(AppEnvironment.self) private var app
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var controller = SpecimenWindowController()
    private let side: CGFloat
    private let showingB: Bool
    private let onLineUpSlot: (@MainActor (RunSlot) -> Void)?

    /// - Parameters:
    ///   - side: the window's side in points (298 at 430 pt; the drawable is `configuration.windowSize` pixels).
    ///   - showingB: Flip view only: true while the `B` engraving is held (UI-COMPARE owns that control).
    ///   - onLineUpSlot: Line-up only: the quadrant tapped (it becomes the kernel well's subject).
    public init(side: CGFloat, showingB: Bool = false, onLineUpSlot: (@MainActor (RunSlot) -> Void)? = nil) {
        self.side = side; self.showingB = showingB; self.onLineUpSlot = onLineUpSlot
    }

    public var body: some View {
        if let presenter = app.presenter, let coordinator = app.renderer {
            window(presenter: presenter, coordinator: coordinator)
        } else {
            Color.black.frame(width: side, height: side)
                .accessibilityLabel("Image window")
                .accessibilityValue("GPU not available")
        }
    }

    // MARK: Composition

    private func window(presenter: PresentRenderer, coordinator: RenderCoordinator) -> some View {
        let geometry = controller.geometry(bench: bench, side: side)
        let handles = SpecimenHandleLayout.handles(entry: bench.entry, configuration: bench.configuration, geometry: geometry,
                                                   split: bench.view.split, compare: bench.compare)
        let options = presentOptions
        return ZStack(alignment: .topLeading) {
            imageLayer(presenter: presenter, geometry: geometry, handles: handles)
                .frame(width: side, height: side)
                .overlay(alignment: .topLeading) { overlays(geometry: geometry, handles: handles) }
            loupe(coordinator: coordinator, geometry: geometry)
        }
        .frame(width: side, height: side, alignment: .topLeading)
        .instrumentControlOwnsTouches(identifier: "specimen")
        .onChange(of: options, initial: true) { _, new in presenter.options = new }
        .onAppear {
            controller.attach(presenter: presenter)
            let amber = InstrumentPalette.instrumentAmber.resolve(in: EnvironmentValues())
            presenter.contourColour = SIMD4(amber.red, amber.green, amber.blue, 1)
        }
        .task(id: canvasKey) { await controller.loadCanvasFacts(bench: bench, app: app, presenter: presenter) }
        .task(id: loupeKey) { await controller.refreshAnchoredLoupe(bench: bench, scenario: app.launch?.scenario) }
        .onChange(of: bench.loupe) { _, reading in controller.showLoupe(reading, coordinator: coordinator) }
        .onChange(of: bench.lastFull[.a]?.generation) { _, _ in controller.announceProbeIfPending(bench: bench) }
    }

    @ViewBuilder
    private func imageLayer(presenter: PresentRenderer, geometry: PresentGeometry, handles: [SpecimenHandle]) -> some View {
        if let entry = bench.entry, entry.tier == .system {
            SystemExhibitView(entry: entry, configuration: bench.configuration, specimenImage: controller.specimenImage,
                              displayScale: displayScale, split: bench.view.split ?? 0.5) {
                metalView(presenter: presenter, geometry: geometry, handles: handles)
            }
        } else {
            metalView(presenter: presenter, geometry: geometry, handles: handles)
        }
    }

    private func metalView(presenter: PresentRenderer, geometry: PresentGeometry, handles: [SpecimenHandle]) -> some View {
        let controller = self.controller, bench = self.bench, side = Double(self.side), reduceMotion = self.reduceMotion
        let lineUpSlot = onLineUpSlot
        var view = MetalSpecimenView(renderer: presenter, windowPixels: bench.configuration.windowSize,
                                     handles: handles.filter { $0.line == nil }.map { HandleTarget(id: $0.id, centre: $0.point) }) { intent in
            controller.perform(intent, bench: bench, presenter: presenter, side: side, reduceMotion: reduceMotion, onLineUpSlot: lineUpSlot)
        }
        view.lineHandles = handles.compactMap(\.line)
        view.onTouchActivity = { active in
            if active { bench.beginInteraction() } else { bench.endInteraction() }
        }
        view.accessibilityModel = controller.accessibilityModel(bench: bench, app: app, presenter: presenter, side: side)
        return view
    }

    private func overlays(geometry: PresentGeometry, handles: [SpecimenHandle]) -> some View {
        let increased = contrast == .increased
        let probe = geometry.point(ofPixelCentre: bench.configuration.probe)
        let pixelPoints = 1 / geometry.texelsPerPixel / geometry.pixelsPerPoint
        let lineUp = bench.compare?.view == .lineUp
        return ZStack(alignment: .topLeading) {
            ForEach(handles) { handle in
                SpecimenHandleMark(handle: handle, side: side, increasedContrast: increased)
            }
            if lineUp {
                ForEach(0..<4, id: \.self) { q in
                    let p = controller.lineUpPoint(bench.configuration.probe, quadrant: q, geometry: geometry)
                    SpecimenProbeCrosshair(point: CGPoint(x: p.x, y: p.y), pixelPoints: pixelPoints, increasedContrast: increased)
                }
            } else if geometry.contains(probe) {
                SpecimenProbeCrosshair(point: CGPoint(x: probe.x, y: probe.y), pixelPoints: pixelPoints, increasedContrast: increased)
                    .id(bench.configuration.probe)
                    .transition(.opacity.animation(reduceMotion ? nil : .easeOut(duration: 0.12)))   // the 120-ms probe fade
            }
            ForEach(handles) { handle in handleElement(handle, geometry: geometry) }
        }
        .frame(width: side, height: side, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
    }

    /// Each handle as an adjustable VoiceOver element (SPEC §14): ±8 px (dividers ±10 %), Centre on probe / image, Reset.
    private func handleElement(_ handle: SpecimenHandle, geometry: PresentGeometry) -> some View {
        let controller = self.controller, bench = self.bench, side = Double(self.side)
        return Color.clear
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .position(x: handle.point.x, y: handle.point.y)
            .accessibilityElement()
            .accessibilityLabel(handle.label)
            .accessibilityValue(handle.value + (handle.adjustsBothAxes ? ", adjusting \(controller.handleAxis(handle.id).rawValue)" : ""))
            .accessibilityAdjustableAction { direction in
                controller.adjustHandle(handle, direction: direction == .increment ? 1 : -1, bench: bench, side: side)
            }
            .accessibilityActions {
                if handle.adjustsBothAxes {
                    Button(controller.handleAxis(handle.id) == .x ? "Adjust y" : "Adjust x") { controller.toggleHandleAxis(handle.id) }
                }
                if handle.shape == .divider {
                    Button("Reset to 50 percent") { controller.setDivider(handle.id, 0.5, bench: bench) }
                    if handle.id == "split" { Button("Hide input") { bench.setSplit(nil) } }
                } else {
                    Button("Centre on probe") { controller.centreHandle(handle, onProbe: true, bench: bench, side: side) }
                    Button("Centre on image") { controller.centreHandle(handle, onProbe: false, bench: bench, side: side) }
                    Button("Reset") { controller.resetHandle(handle, bench: bench) }
                }
            }
    }

    @ViewBuilder
    private func loupe(coordinator: RenderCoordinator, geometry: PresentGeometry) -> some View {
        if let anchor = controller.loupeAnchor(bench: bench, geometry: geometry), let renderer = controller.loupeRenderer {
            let origin = SpecimenLoupeMetrics.origin(finger: anchor, side: Double(side))
            let reading = bench.loupe
            let centre = reading?.centre ?? bench.configuration.probe
            let region = PixelRegion.centred(on: centre, side: SpecimenLoupeMetrics.texels, inside: .square(bench.configuration.windowSize))
            SpecimenLoupe(renderer: renderer, reading: reading,
                          centreTexel: SIMD2(centre.x - region.origin.x, centre.y - region.origin.y),
                          held: bench.acknowledged[.a]?.quality.publishesMeasurements == false)
                .offset(x: origin.x, y: origin.y)
                .transition(.opacity.animation(reduceMotion ? nil : .easeOut(duration: 0.12)))
        }
    }

    // MARK: Derived state

    private var presentOptions: PresentOptions {
        var options = PresentOptions(mode: .output, split: bench.view.split, zoom: bench.view.zoom, zoomCentre: bench.view.zoomCentre,
                                     pass: bench.view.shownPass, showingB: showingB, displayMode: app.settings.displayMode)
        if let compare = bench.compare {
            options.mode = .compare(compare.view)
            options.split = compare.split
        }
        return options
    }

    private var canvasKey: String {
        let c = bench.configuration
        let tierS = bench.entry?.tier == .system
        return "\(c.specimen.rawValue)|\(c.windowSize)|\(c.specimenOptions.canvasOptions.choices.sorted { $0.key < $1.key })|\(tierS ? "\(c.pan.x),\(c.pan.y)" : "")"
    }
    private var loupeKey: String {
        "\(bench.lastFull[.a]?.generation ?? 0)|\(controller.loupeAtProbe)|\(bench.configuration.probe.x),\(bench.configuration.probe.y)"
    }
}

// MARK: - Controller

/// Interaction state of one image window and the intents it performs. Main-actor only; holds no textures.
@MainActor @Observable
final class SpecimenWindowController {
    enum PanMode { case content(start: SIMD2<Double>), view(startCentre: SIMD2<Double>) }

    /// The finger while the loupe is held (view points); nil when the loupe is closed or anchored at the probe.
    private(set) var loupeFinger: SIMD2<Double>?
    /// The loupe opened without a finger (VoiceOver `Open loupe`, the `loupe` launch scenario): it sits over the probe.
    private(set) var loupeAtProbe = false
    /// The loupe's own present renderer (crop mode over its 14 × 14 texel copy).
    private(set) var loupeRenderer: PresentRenderer?
    /// Tier S: the specimen window as a CGImage for SystemExhibitView (extended linear sRGB).
    private(set) var specimenImage: CGImage?

    @ObservationIgnored private var presenter: PresentRenderer?
    @ObservationIgnored private var panMode: PanMode?
    @ObservationIgnored private var panTotal = SIMD2<Double>.zero
    @ObservationIgnored private var pinchAnchor = SIMD2<Double>.zero
    @ObservationIgnored private var pinchStartZoom = 1.0
    @ObservationIgnored private var pinchLastCentre = SIMD2<Double>.zero
    @ObservationIgnored private var loupePixel: PixelPoint?
    @ObservationIgnored private var springTask: Task<Void, Never>?
    @ObservationIgnored private var axes: [String: SpecimenAccessibilityModel.Axis] = [:]
    @ObservationIgnored private var pendingProbeAnnouncement = false
    @ObservationIgnored private var pendingLoupeAnnouncement = false
    @ObservationIgnored private var scenarioLoupeOpened = false
    @ObservationIgnored private let accessibility = SpecimenAccessibilityModel()

    func attach(presenter: PresentRenderer) { self.presenter = presenter }

    func geometry(bench: BenchModel, side: Double) -> PresentGeometry {
        let n = bench.configuration.windowSize
        return PresentGeometry(windowPixels: n, drawablePixels: n, viewPoints: side, zoom: bench.view.zoom, zoomCentre: bench.view.zoomCentre)
    }

    // MARK: Intents (SPEC §4.1.3 gesture table)

    func perform(_ intent: GestureIntent, bench: BenchModel, presenter: PresentRenderer, side: Double, reduceMotion: Bool,
                 onLineUpSlot: (@MainActor (RunSlot) -> Void)?) {
        let g = geometry(bench: bench, side: side)
        let lineUp = bench.compare?.view == .lineUp
        switch intent {
        case .placeProbe(let p):
            if lineUp {
                let hit = g.lineUpPixel(atPoint: p)
                bench.setProbe(hit.pixel)
                onLineUpSlot?(RunSlot.allCases[Swift.min(hit.slot, RunSlot.allCases.count - 1)])
            } else {
                bench.setProbe(g.windowPixel(atPoint: p))
            }
        case .handleBegan:
            break
        case .handleMoved(let id, let p):
            switch id {
            case "split": bench.setSplit(Swift.min(Swift.max(p.x / side, 0), 1))
            case "compare": setDivider("compare", p.x / side, bench: bench)
            default:
                guard let entry = bench.entry else { return }
                for (kind, key, value) in SpecimenHandleLayout.drag(id, to: p, entry: entry, configuration: bench.configuration, geometry: g) {
                    bench.moveHandle(kind, parameter: key, to: value)
                }
            }
        case .handleEnded:
            break
        case .panBegan:
            panTotal = .zero
            springTask?.cancel()
            if bench.view.zoom > 1.001 {
                panMode = .view(startCentre: bench.view.zoomCentre)
            } else {
                // A pan that starts while the band is still springing back continues from where the image is shown.
                let shift = presenter.overscroll
                let pan = bench.configuration.pan
                panMode = .content(start: SIMD2(Double(pan.x) - Double(shift.x), Double(pan.y) - Double(shift.y)))
            }
        case .panMoved(let delta):
            panTotal += delta
            switch panMode {
            case .view(let startCentre):
                let centre = startCentre - panTotal * g.pixelsPerPoint * g.texelsPerPixel
                bench.setZoom(bench.view.zoom, centre: clampedCentre(centre, zoom: bench.view.zoom, n: g.windowPixels))
            case .content(let start):
                // At 1×: whole specimen pixels under the fixed window; beyond ±256 px the image rubber-bands.
                let requested = start - panTotal * g.pixelsPerPoint
                let resolved = PresentRubberBand.resolve(requested: requested)
                bench.setPan(resolved.pan)
                presenter.overscroll = resolved.shift
            case nil:
                break
            }
        case .panEnded:
            panMode = nil
            springBack(presenter, reduceMotion: reduceMotion)
        case .zoomBegan(let c):
            pinchAnchor = g.windowCoordinate(atPoint: c)
            pinchStartZoom = bench.view.zoom
            pinchLastCentre = c
            springTask?.cancel()
            presenter.overscroll = .zero
        case .zoomChanged(let scale, let c):
            let z = PresentGeometry.clampedZoom(pinchStartZoom * scale)
            pinchLastCentre = c
            bench.setZoom(z, centre: clampedCentre(g.zoomCentre(keeping: pinchAnchor, under: c, zoom: z), zoom: z, n: g.windowPixels))
        case .zoomEnded:
            let z = PresentGeometry.snappedZoom(bench.view.zoom)
            let centre = z == 1 ? SIMD2(repeating: Double(g.windowPixels) / 2)
                                : clampedCentre(g.zoomCentre(keeping: pinchAnchor, under: pinchLastCentre, zoom: z), zoom: z, n: g.windowPixels)
            bench.setZoom(z, centre: centre)
        case .loupeBegan(let p), .loupeMoved(let p):
            loupeAtProbe = false
            loupeFinger = p
            let pixel = lineUp ? g.lineUpPixel(atPoint: p).pixel : g.windowPixel(atPoint: p)
            ensureLoupeRenderer(presenter.coordinator)
            if pixel != loupePixel {
                loupePixel = pixel
                Task { await bench.setLoupe(pixel) }
            }
        case .loupeEnded(let placeAt):
            loupeFinger = nil
            loupePixel = nil
            Task { await bench.setLoupe(nil) }
            if let placeAt { bench.setProbe(lineUp ? g.lineUpPixel(atPoint: placeAt).pixel : g.windowPixel(atPoint: placeAt)) }
        case .cancelled:
            panMode = nil
            if loupeFinger != nil {
                loupeFinger = nil
                loupePixel = nil
                Task { await bench.setLoupe(nil) }
            }
            springBack(presenter, reduceMotion: reduceMotion)
        }
    }

    /// The zoom centre limited so the magnified view stays inside the window (drags past the edge do not accumulate).
    private func clampedCentre(_ c: SIMD2<Double>, zoom: Double, n: Int) -> SIMD2<Double> {
        let half = Double(n) / PresentGeometry.clampedZoom(zoom) / 2
        func axis(_ v: Double) -> Double { Swift.min(Swift.max(v, half), Double(n) - half) }
        return SIMD2(axis(c.x), axis(c.y))
    }

    /// The rubber band springs back (ease-out, 0.28 s; at once under Reduce Motion).
    private func springBack(_ presenter: PresentRenderer, reduceMotion: Bool) {
        let start = presenter.overscroll
        guard start != .zero else { return }
        springTask?.cancel()
        if reduceMotion { presenter.overscroll = .zero; return }
        springTask = Task { @MainActor [weak presenter] in
            let t0 = ProcessInfo.processInfo.systemUptime, duration = 0.28
            while !Task.isCancelled {
                let t = (ProcessInfo.processInfo.systemUptime - t0) / duration
                if t >= 1 { break }
                let k = 1 - pow(1 - t, 3)
                presenter?.overscroll = SIMD2(Int32((Double(start.x) * (1 - k)).rounded()), Int32((Double(start.y) * (1 - k)).rounded()))
                try? await Task.sleep(for: .milliseconds(8))
            }
            if !Task.isCancelled { presenter?.overscroll = .zero }
        }
    }

    // MARK: Dividers and handles (also the VoiceOver adjustable actions)

    func setDivider(_ id: String, _ value: Double, bench: BenchModel) {
        let v = Swift.min(Swift.max(value, 0), 1)
        if id == "compare", var state = bench.compare {
            state.split = v
            bench.updateCompare(state)
        } else {
            bench.setSplit(v)
        }
    }

    func handleAxis(_ id: String) -> SpecimenAccessibilityModel.Axis { axes[id] ?? .x }
    func toggleHandleAxis(_ id: String) {
        axes[id] = handleAxis(id) == .x ? .y : .x
        UIAccessibility.post(notification: .announcement, argument: "Adjusting \(axes[id]?.rawValue ?? "x")")
    }

    func adjustHandle(_ handle: SpecimenHandle, direction: Int, bench: BenchModel, side: Double) {
        let g = geometry(bench: bench, side: side)
        if handle.shape == .divider {
            let current = handle.id == "compare" ? (bench.compare?.split ?? 0.5) : (bench.view.split ?? 0.5)
            setDivider(handle.id, current + 0.1 * Double(direction), bench: bench)
            return
        }
        guard let entry = bench.entry else { return }
        let step = 8.0 * Double(direction)
        let d: SIMD2<Double>
        switch handle.shape {
        case .line, .bandGrip: d = SIMD2(0, step)
        case .knob: d = SIMD2(step, 0)
        default: d = handleAxis(handle.id) == .x ? SIMD2(step, 0) : SIMD2(0, step)
        }
        let target = SpecimenHandleLayout.nudged(handle, by: d, geometry: g)
        for (kind, key, value) in SpecimenHandleLayout.drag(handle.id, to: target, entry: entry, configuration: bench.configuration, geometry: g) {
            bench.moveHandle(kind, parameter: key, to: value)
        }
    }

    func centreHandle(_ handle: SpecimenHandle, onProbe: Bool, bench: BenchModel, side: Double) {
        guard let entry = bench.entry else { return }
        let g = geometry(bench: bench, side: side)
        let n = bench.configuration.windowSize
        let pixel = onProbe ? bench.configuration.probe : SpecimenGeometry.centre(windowSize: n)
        let target = g.point(ofWindowCoordinate: SIMD2(Double(pixel.x), Double(pixel.y)) + 0.5)
        for (kind, key, value) in SpecimenHandleLayout.drag(handle.id, to: target, entry: entry, configuration: bench.configuration, geometry: g) {
            bench.moveHandle(kind, parameter: key, to: value)
        }
    }

    func resetHandle(_ handle: SpecimenHandle, bench: BenchModel) {
        guard let entry = bench.entry else { return }
        for spec in entry.handles {
            for key in spec.parameters { if let d = entry.spec(key)?.defaultValue { bench.moveHandle(spec.kind, parameter: key, to: d) } }
        }
    }

    /// The probe's view point inside Line-up quadrant q (each quadrant shows the central crop).
    func lineUpPoint(_ probe: PixelPoint, quadrant q: Int, geometry g: PresentGeometry) -> SIMD2<Double> {
        let qPx = Double(g.lineUpQuadrantPixels)
        let local = (probe.centre - SIMD2(repeating: Double(g.lineUpCropOrigin))) / (Double(g.windowPixels) / Double(g.drawablePixels))
        return (SIMD2(Double(q % 2), Double(q / 2)) * qPx + local) / g.pixelsPerPoint
    }

    // MARK: Loupe

    private func ensureLoupeRenderer(_ coordinator: RenderCoordinator) {
        guard loupeRenderer == nil else { return }
        let n = SpecimenLoupeMetrics.texels
        let renderer = PresentRenderer(coordinator: coordinator,
                                       options: PresentOptions(mode: .crop(PixelRegion(origin: .zero, size: .square(n))), split: nil))
        renderer.presentsTexelCopyOnly = true
        loupeRenderer = renderer
    }

    /// Where the loupe is anchored: the finger, or (opened without one) the probe's view point.
    func loupeAnchor(bench: BenchModel, geometry: PresentGeometry) -> SIMD2<Double>? {
        if let loupeFinger { return loupeFinger }
        if loupeAtProbe { return geometry.point(ofPixelCentre: bench.configuration.probe) }
        return nil
    }

    func showLoupe(_ reading: LoupeReading?, coordinator: RenderCoordinator) {
        ensureLoupeRenderer(coordinator)
        guard let reading, reading.texels.count == SpecimenLoupeMetrics.texels * SpecimenLoupeMetrics.texels else { return }
        loupeRenderer?.showTexels(reading.texels, width: SpecimenLoupeMetrics.texels, height: SpecimenLoupeMetrics.texels)
        if pendingLoupeAnnouncement {
            pendingLoupeAnnouncement = false
            UIAccessibility.post(notification: .announcement,
                                 argument: "Loupe at \(reading.centre.x), \(reading.centre.y): \(reading.centreLinear.spoken), 8-bit code \(reading.centreCode8.text) of 255")
        }
    }

    /// Opens the loupe over the probe without a finger (VoiceOver `Open loupe`; the `loupe` launch scenario).
    func openLoupeAtProbe(bench: BenchModel, announce: Bool) {
        guard let presenter else { return }
        ensureLoupeRenderer(presenter.coordinator)
        loupeAtProbe = true
        pendingLoupeAnnouncement = announce
        let probe = bench.configuration.probe
        Task { await bench.setLoupe(probe) }
    }
    func closeLoupe(bench: BenchModel) {
        loupeAtProbe = false
        loupeFinger = nil
        Task { await bench.setLoupe(nil) }
    }

    /// Keeps an anchored loupe reading the probe of the newest full Run; opens it once for the `loupe` scenario.
    func refreshAnchoredLoupe(bench: BenchModel, scenario: LaunchScenario?) async {
        if scenario == .loupe, !scenarioLoupeOpened, bench.lastFull[.a] != nil {
            scenarioLoupeOpened = true
            openLoupeAtProbe(bench: bench, announce: false)
            return
        }
        if loupeAtProbe, bench.lastFull[.a] != nil { await bench.setLoupe(bench.configuration.probe) }
    }

    // MARK: Canvas facts (backdrop, Tier S image)

    func loadCanvasFacts(bench: BenchModel, app: AppEnvironment, presenter: PresentRenderer) async {
        let configuration = bench.configuration
        guard let canvas = await app.specimens.canvas(configuration.specimen, options: configuration.specimenOptions,
                                                      windowSize: configuration.windowSize) else { return }
        presenter.backdrop = canvas.backdrop
        guard bench.entry?.tier == .system else { specimenImage = nil; return }
        let window = await Task.detached(priority: .userInitiated) { canvas.window(pan: configuration.pan).image }.value
        guard !Task.isCancelled else { return }
        specimenImage = SpecimenPlatform.cgImage(window)
    }

    // MARK: VoiceOver (SPEC §14)

    func accessibilityModel(bench: BenchModel, app: AppEnvironment, presenter: PresentRenderer, side: Double) -> SpecimenAccessibilityModel {
        let model = accessibility
        model.label = "Image window"
        model.value = { [weak bench] in bench.map(SpecimenWindowController.spokenValue) ?? "" }
        model.moveProbe = { [weak self, weak bench] dx, dy in
            guard let self, let bench else { return }
            let p = bench.configuration.probe
            self.pendingProbeAnnouncement = true
            bench.setProbe(PixelPoint(x: p.x + dx, y: p.y + dy))
        }
        var actions: [(name: String, handler: () -> Bool)] = []
        actions.append(("Descend from this pixel", { [weak bench] in bench?.path.append(.trace); return bench != nil }))
        actions.append(("Centre probe", { [weak self, weak bench] in
            guard let bench else { return false }
            self?.pendingProbeAnnouncement = true
            bench.setProbe(SpecimenGeometry.centre(windowSize: bench.configuration.windowSize)); return true }))
        let jumps = bench.availableJumps()
        if jumps.contains(.brightestOutput) {
            actions.append(("Probe to brightest pixel", { [weak self, weak bench] in
                guard let bench else { return false }
                self?.pendingProbeAnnouncement = true
                Task { await bench.jumpProbe(.brightestOutput) }; return true }))
        }
        if jumps.contains(.featureProbe) {
            actions.append(("Probe to feature", { [weak self, weak bench] in
                guard let bench else { return false }
                self?.pendingProbeAnnouncement = true
                Task { await bench.jumpProbe(.featureProbe) }; return true }))
        }
        for (name, d) in [("Pan left 8 pixels", PixelPoint(x: -8, y: 0)), ("Pan right 8 pixels", PixelPoint(x: 8, y: 0)),
                          ("Pan up 8 pixels", PixelPoint(x: 0, y: -8)), ("Pan down 8 pixels", PixelPoint(x: 0, y: 8))] {
            actions.append((name, { [weak bench] in
                guard let bench else { return false }
                let pan = bench.configuration.pan
                bench.setPan(PixelPoint(x: pan.x + d.x, y: pan.y + d.y)); return true }))
        }
        actions.append(("Zoom in", { [weak bench] in
            guard let bench else { return false }
            let z = PresentGeometry.snappedZoom(Swift.min(bench.view.zoom * 2, PresentGeometry.maximumZoom))
            bench.setZoom(z, centre: bench.configuration.probe.centre)
            UIAccessibility.post(notification: .announcement, argument: "Zoom \(Int(z)) times, nearest"); return true }))
        actions.append(("Zoom out", { [weak bench] in
            guard let bench else { return false }
            let z = PresentGeometry.snappedZoom(Swift.max(bench.view.zoom / 2, 1))
            bench.setZoom(z, centre: z == 1 ? SIMD2(repeating: Double(bench.configuration.windowSize) / 2) : bench.view.zoomCentre)
            UIAccessibility.post(notification: .announcement, argument: z == 1 ? "Zoom 1 times, pixels one to one" : "Zoom \(Int(z)) times, nearest")
            return true }))
        actions.append(("Reset view", { [weak bench, weak presenter] in
            guard let bench else { return false }
            presenter?.overscroll = .zero
            bench.setZoom(1, centre: SIMD2(repeating: Double(bench.configuration.windowSize) / 2))
            bench.setPan(.zero); return true }))
        if loupeAtProbe || loupeFinger != nil {
            actions.append(("Close loupe", { [weak self, weak bench] in
                guard let self, let bench else { return false }
                self.closeLoupe(bench: bench); return true }))
        } else {
            actions.append(("Open loupe", { [weak self, weak bench] in
                guard let self, let bench else { return false }
                self.openLoupeAtProbe(bench: bench, announce: true); return true }))
        }
        if bench.compare == nil {
            actions.append(bench.view.split == nil
                ? ("Show input beside output", { [weak bench] in bench?.setSplit(0.5); return bench != nil })
                : ("Hide input", { [weak bench] in bench?.setSplit(nil); return bench != nil }))
        } else {
            actions.append(("Drive A", { [weak bench] in bench?.setDrivingB(false); return bench != nil }))
            actions.append(("Drive B", { [weak bench] in bench?.setDrivingB(true); return bench != nil }))
        }
        model.actions = actions
        return model
    }

    /// "Live, Metal. Test image, Night City, blurred with Gaussian, sigma 12.0 pixels. Probe at 447, 455, output 0.0885
    /// linear, live." The provenance comes first (SPEC §4.1, §14).
    static func spokenValue(_ bench: BenchModel) -> String {
        let caption = SpecimenCaption.make(bench: bench)
        let specimen = SpecimenRegistry.generator(bench.configuration.specimen)?.descriptor.menuName ?? bench.configuration.specimen.rawValue
        var parts = [caption.spokenProvenance]
        var subject = "Test image, \(specimen)"
        if let entry = bench.entry {
            subject += ", blurred with \(entry.displayName)"
            if let spec = entry.primarySpec, let v = bench.configuration.parameters.double(spec.key) {
                subject += ", \(spec.spokenLabel) \(spec.numberStyle.spoken(v))"
            }
        }
        parts.append(subject)
        let probe = bench.configuration.probe
        var probeLine = "Probe at \(probe.x), \(probe.y)"
        if let chip = bench.railChips.first(where: { $0.floor == .pixels }), chip.value.value != nil, bench.lastFull[.a]?.configuration.probe == probe {
            probeLine += ", output \(chip.value.spoken)"
        } else if let run = bench.lastFull[.a], run.configuration.probe == probe, let out = run.probe?.output {
            probeLine += ", output " + BadgedValue.number(out.x, .significant(3, unit: "linear"), .live).spoken
        } else {
            probeLine += ", output updating"
        }
        if bench.acknowledged[.a]?.quality.publishesMeasurements == false { probeLine += ", held from the last full-resolution frame" }
        parts.append(probeLine)
        if bench.view.zoom > 1.001 { parts.append("Magnified \(Int(bench.view.zoom.rounded())) times, nearest neighbour") }
        return parts.joined(separator: ". ") + "."
    }

    /// After a probe move from VoiceOver, speak the new output once the full Run for that probe has arrived.
    func announceProbeIfPending(bench: BenchModel) {
        guard pendingProbeAnnouncement, let run = bench.lastFull[.a], run.configuration.probe == bench.configuration.probe else { return }
        pendingProbeAnnouncement = false
        let probe = bench.configuration.probe
        let output = run.probe.map { BadgedValue.number($0.output.x, .significant(3, unit: "linear"), .live).spoken } ?? "not read"
        UIAccessibility.post(notification: .announcement, argument: "Probe \(probe.x), \(probe.y), output \(output)")
    }
}
