import XCTest
import SwiftUI
import MetalKit
import UIKit
@testable import Blur2ool
import BlurCore
import BlurGPU

// OWNER: UI-SPECIMEN. Run on the PHONE under the simulator hold (`Tools/build.sh device-build-for-testing`, then
// `device-session "test --area UISPECIMEN"`; ARCHITECTURE §12.3). What only the device can show:
// 1. Review fix E-20: the MTKView's drawable is exactly N × N, autoResizeDrawable is off, contentScaleFactor equals the
//    screen's displayScale, the layer colorspace is sRGB and the format bgra8Unorm — for MetalSpecimenView alone and inside
//    the full SpecimenWindow.
// 2. The present pass on this GPU (A17 Pro): a real Gaussian render presented 1 : 1 gives SRGB.code8 of each output texel.
// 3. The Swift mirror of B2PresentParams has the shader's 144-byte layout; geometry and rubber band invariants.
// 4. The image's VoiceOver element: adjustable, rotors Probe axis / Probe step, the SPEC §14 custom actions, a value that
//    starts with the provenance; increment moves the probe.
// 5. Hosted renders of SpecimenWindow in a 430-pt housing (window, loupe, zoom 4×, AX5) kept as XCTAttachments, so they can
//    be looked at before UI-BENCH places the component on the Bench.
@MainActor
final class UISPECIMEN_AppTests: XCTestCase {

    // MARK: Helpers

    private func scene() throws -> UIWindowScene {
        try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first, "a window scene")
    }

    private func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        (view as? T) ?? view.subviews.lazy.compactMap { self.find(type, in: $0) }.first
    }

    private func spin(until condition: () -> Bool, timeout: Double) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !condition() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }

    /// A full app environment (its own GPU context, coordinator, presenter and BenchModel) for a launch scenario.
    private func environment(_ arguments: [String]) throws -> (AppEnvironment, BenchModel) {
        let app = AppEnvironment.make(arguments: arguments)
        let bench = try XCTUnwrap(app.bench, "BenchModel (GPU available)")
        return (app, bench)
    }

    /// Hosts `content` full-screen in a new window on the app's scene and returns the window (call `isHidden = true` after).
    private func host<V: View>(_ content: V) throws -> (UIWindow, UIHostingController<V>) {
        let window = UIWindow(windowScene: try scene())
        let controller = UIHostingController(rootView: content)
        window.rootViewController = controller
        window.windowLevel = .alert + 1
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        return (window, controller)
    }

    // MARK: 1. E-20

    func testMetalSpecimenViewDrawableIsExactlyNByNWithScreenScaleAndSRGBLayer() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let library = try XCTUnwrap(device.makeDefaultLibrary())
        let context = try GPUContext(device: device, library: library, manifest: ShaderManifest(files: [:], combinedSHA256: ""))
        let presenter = PresentRenderer(coordinator: RenderCoordinator(gpu: context, specimens: SpecimenStore()))
        let (window, host) = try host(MetalSpecimenView(renderer: presenter, windowPixels: 894).frame(width: 298, height: 298))
        defer { window.isHidden = true }
        spin(until: { find(MTKView.self, in: host.view).map { $0.contentScaleFactor == host.traitCollection.displayScale } ?? false }, timeout: 2)
        let mtk = try XCTUnwrap(find(MTKView.self, in: host.view), "MTKView in the hierarchy")
        XCTAssertEqual(host.traitCollection.displayScale, window.screen.scale)
        XCTAssertEqual(mtk.drawableSize, CGSize(width: 894, height: 894), "the drawable is exactly N × N")
        XCTAssertFalse(mtk.autoResizeDrawable)
        XCTAssertEqual(mtk.contentScaleFactor, host.traitCollection.displayScale)
        XCTAssertEqual(mtk.bounds.size, CGSize(width: 298, height: 298))
        XCTAssertEqual((mtk.layer as? CAMetalLayer)?.colorspace?.name, CGColorSpace.sRGB)
        XCTAssertEqual(mtk.colorPixelFormat, .bgra8Unorm)
        XCTAssertTrue(mtk.isPaused && mtk.enableSetNeedsDisplay, "drawn on demand")
        print("UISPECIMEN E-20: drawable \(mtk.drawableSize), scale \(mtk.contentScaleFactor), bounds \(mtk.bounds.size), colorspace sRGB")
    }

    func testSpecimenWindowKeepsTheContractAtThePhonesOwnWindowSize() throws {
        let (app, bench) = try environment(["-B2Scenario", "bench"])
        let scale = try scene().screen.scale
        let side = 298.0
        bench.configureWindow(points: side, scale: scale)
        let n = bench.configuration.windowSize
        let (window, host) = try host(SpecimenWindow(side: side).environment(bench).environment(app).frame(width: side, height: side))
        defer { window.isHidden = true }
        spin(until: { find(MTKView.self, in: host.view).map { $0.contentScaleFactor == scale } ?? false }, timeout: 3)
        let mtk = try XCTUnwrap(find(MTKView.self, in: host.view))
        XCTAssertEqual(mtk.drawableSize, CGSize(width: n, height: n))
        XCTAssertEqual(Double(n), (side * Double(scale)).rounded(), "N = window points × displayScale")
        XCTAssertFalse(mtk.autoResizeDrawable)
        XCTAssertEqual(mtk.contentScaleFactor, scale)
        XCTAssertEqual((mtk.layer as? CAMetalLayer)?.colorspace?.name, CGColorSpace.sRGB)
    }

    // MARK: 2. The present pass on this GPU

    func testOneToOnePresentOfARealRenderGivesSRGBCode8PerPixel() async throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let library = try XCTUnwrap(device.makeDefaultLibrary())
        let context = try GPUContext(device: device, library: library, manifest: ShaderManifest(files: [:], combinedSHA256: ""))
        let coordinator = RenderCoordinator(gpu: context, specimens: SpecimenStore())
        let n = 256
        let configuration = RenderConfiguration(blur: GaussianOperator.id, variant: GaussianOperator.linearSampled,
                                                parameters: ParameterValues(["sigma": .double(4), "truncation": .choice("3"),
                                                                             "discretisation": .choice("sampled")]),
                                                settings: .standard, specimen: "step-edges", specimenOptions: .standard, pan: .zero,
                                                probe: SpecimenGeometry.centre(windowSize: n), windowSize: n)
        _ = try await coordinator.render(RenderRequest(configuration: configuration, slot: .a, quality: .full, generation: 1, kind: .display, traced: false))
        let presenter = PresentRenderer(coordinator: coordinator, options: PresentOptions(split: nil))
        let ready = await presenter.waitUntilReady()
        XCTAssertTrue(ready, "present pipeline compiled")
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: n, height: n, mipmapped: false)
        d.usage = .renderTarget; d.storageMode = .shared
        let target = try XCTUnwrap(device.makeTexture(descriptor: d))
        let drew = await presenter.render(into: target)
        XCTAssertTrue(drew)
        let texels = try await coordinator.readTexels(slot: .a, pass: nil, region: PixelRegion(origin: .zero, size: .square(n)))
        XCTAssertEqual(texels.count, n * n)
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        target.getBytes(&bytes, bytesPerRow: n * 4, from: MTLRegionMake2D(0, 0, n, n), mipmapLevel: 0)
        var compared = 0, mismatches = 0, nearBoundary = 0
        for i in 0..<(n * n) {
            let gpu = [Int(bytes[4 * i + 2]), Int(bytes[4 * i + 1]), Int(bytes[4 * i])]
            for ch in 0..<3 {
                let linear = Double(texels[i][ch])
                let e = Swift.min(Swift.max(SRGB.encode(linear), 0), 1) * 255
                if abs(e - (e.rounded(.down) + 0.5)) < 0.02 { nearBoundary += 1; continue }
                compared += 1
                if gpu[ch] != SRGB.code8(linear: linear) { mismatches += 1 }
            }
        }
        print("UISPECIMEN phone 1:1 present: \(compared) channels compared, \(nearBoundary) near a rounding boundary skipped, \(mismatches) mismatches on \(device.name)")
        XCTAssertEqual(mismatches, 0)
        XCTAssertGreaterThan(compared, n * n * 2)
    }

    // MARK: 3. Layout, geometry, rubber band

    func testPresentShaderParamsHaveTheShadersLayout() {
        XCTAssertEqual(MemoryLayout<PresentShaderParams>.stride, PresentShaderParams.expectedStride)
        XCTAssertEqual(MemoryLayout<PresentShaderParams>.offset(of: \.origin), 64)
        XCTAssertEqual(MemoryLayout<PresentShaderParams>.offset(of: \.drawableSize), 88)
        XCTAssertEqual(MemoryLayout<PresentShaderParams>.offset(of: \.shift), 96)
        XCTAssertEqual(MemoryLayout<PresentShaderParams>.offset(of: \.gain), 120)
        XCTAssertEqual(MemoryLayout<PresentShaderParams>.offset(of: \.showB), 128)
    }

    func testGeometryTapsLandOnThePixelTheCrosshairMarks() {
        for zoom in [1.0, 2, 4, 8] {
            let g = PresentGeometry(windowPixels: 894, drawablePixels: 894, viewPoints: 298, zoom: zoom, zoomCentre: SIMD2(600, 300))
            XCTAssertEqual(g.origin.x, g.origin.x.rounded(), "whole-pixel origin at \(zoom)×")
            for p in [SIMD2<Double>(0.2, 0.2), SIMD2(150.1, 77.7), SIMD2(297.9, 297.9)] {
                let pixel = g.windowPixel(atPoint: p)
                let back = g.point(ofPixelCentre: pixel)
                let half = 0.5 / g.pixelsPerPoint / g.texelsPerPixel
                XCTAssertLessThanOrEqual(abs(back.x - p.x), half + 1e-9, "zoom \(zoom): \(p) → \(pixel) → \(back)")
                XCTAssertLessThanOrEqual(abs(back.y - p.y), half + 1e-9)
            }
        }
        let one = PresentGeometry(windowPixels: 894, drawablePixels: 894, viewPoints: 298)
        XCTAssertEqual(one.texelsPerPixel, 1)
        XCTAssertEqual(one.windowPixel(atPoint: SIMD2(149, 151.7)), PixelPoint(x: 447, y: 455))
        XCTAssertEqual(one.splitColumn(0.5), 447)
        XCTAssertEqual(PresentGeometry.snappedZoom(2.7), 2)   // nearest stop in log₂: 2.83 is the 2 ↔ 4 boundary
        XCTAssertEqual(PresentGeometry.snappedZoom(3.1), 4)
        XCTAssertEqual(PresentGeometry.snappedZoom(11), 8)
        let anchored = one.zoomCentre(keeping: SIMD2(300, 200), under: SIMD2(100, 66.6667), zoom: 4)
        let zoomed = PresentGeometry(windowPixels: 894, drawablePixels: 894, viewPoints: 298, zoom: 4, zoomCentre: anchored)
        XCTAssertEqual(zoomed.windowCoordinate(atPoint: SIMD2(100, 66.6667)).x, 300, accuracy: 0.6, "the pinch keeps its pixel under the fingers")
        let lineUp = one.lineUpPixel(atPoint: SIMD2(160, 10))
        XCTAssertEqual(lineUp.slot, 1)
        XCTAssertEqual(one.lineUpCropOrigin, 223)
    }

    func testPanRubberBandsBeyondTheMargin() {
        let inside = PresentRubberBand.resolve(requested: SIMD2(120.4, -30.6))
        XCTAssertEqual(inside.pan, PixelPoint(x: 120, y: -31))
        XCTAssertEqual(inside.shift, .zero)
        let beyond = PresentRubberBand.resolve(requested: SIMD2(-400, 600))
        XCTAssertEqual(beyond.pan, PixelPoint(x: -256, y: 256))
        XCTAssertGreaterThan(beyond.shift.x, 0, "dragging right past the edge moves the image right")
        XCTAssertLessThan(beyond.shift.y, 0)
        XCTAssertLessThan(abs(Double(beyond.shift.x)), PresentRubberBand.reach)
        XCTAssertLessThan(abs(Double(PresentRubberBand.resolve(requested: SIMD2(-100_000, 0)).shift.x)), PresentRubberBand.reach + 1)
    }

    func testLoupePlacementStaysInsideAndOffTheFinger() {
        let side = 298.0
        for finger in [SIMD2<Double>(149, 250), SIMD2(5, 290), SIMD2(290, 20), SIMD2(149, 5)] {
            let o = SpecimenLoupeMetrics.origin(finger: finger, side: side)
            XCTAssertGreaterThanOrEqual(o.x, 0); XCTAssertLessThanOrEqual(o.x + SpecimenLoupeMetrics.width, side + 1e-9)
            XCTAssertGreaterThanOrEqual(o.y, -SpecimenLoupeMetrics.captionAllowance - 1e-9)
            XCTAssertLessThanOrEqual(o.y + SpecimenLoupeMetrics.height, side + 1e-9)
            let covers = finger.y >= o.y && finger.y <= o.y + SpecimenLoupeMetrics.height && finger.x >= o.x && finger.x <= o.x + SpecimenLoupeMetrics.width
            XCTAssertFalse(covers, "the loupe never sits under the finger at \(finger)")
        }
    }

    // MARK: 4. VoiceOver element

    func testImageIsOneAdjustableElementWithRotorsAndActions() throws {
        let (app, bench) = try environment(["-B2Scenario", "bench"])
        let scale = try scene().screen.scale
        bench.configureWindow(points: 298, scale: scale)
        let (window, host) = try host(SpecimenWindow(side: 298).environment(bench).environment(app).frame(width: 298, height: 298))
        defer { window.isHidden = true }
        spin(until: { find(SpecimenMTKView.self, in: host.view)?.isAccessibilityElement ?? false }, timeout: 3)
        let view = try XCTUnwrap(find(SpecimenMTKView.self, in: host.view))
        XCTAssertTrue(view.isAccessibilityElement)
        XCTAssertTrue(view.accessibilityTraits.contains(.adjustable))
        XCTAssertEqual(view.accessibilityCustomRotors?.map(\.name), ["Probe axis", "Probe step"])
        let actions = Set(view.accessibilityCustomActions?.map(\.name) ?? [])
        for name in ["Descend from this pixel", "Centre probe", "Pan left 8 pixels", "Pan right 8 pixels", "Pan up 8 pixels",
                     "Pan down 8 pixels", "Zoom in", "Zoom out", "Reset view", "Open loupe"] {
            XCTAssertTrue(actions.contains(name), "custom action \(name)")
        }
        let value = view.accessibilityValue ?? ""
        XCTAssertTrue(value.hasPrefix("Live, Metal") || value.hasPrefix("Preview"), "the value starts with the provenance: \(value)")
        XCTAssertTrue(value.contains("Probe at"))
        let before = bench.configuration.probe
        view.accessibilityIncrement()
        XCTAssertEqual(bench.configuration.probe, PixelPoint(x: before.x + 1, y: before.y))
        _ = view.accessibilityCustomRotors?[0].itemSearchBlock(UIAccessibilityCustomRotorSearchPredicate())   // axis → y
        view.accessibilityIncrement()
        XCTAssertEqual(bench.configuration.probe, PixelPoint(x: before.x + 1, y: before.y + 1))
        _ = view.accessibilityCustomRotors?[1].itemSearchBlock(UIAccessibilityCustomRotorSearchPredicate())   // step → 16
        view.accessibilityDecrement()
        XCTAssertEqual(bench.configuration.probe, PixelPoint(x: before.x + 1, y: before.y + 1 - 16))
        print("UISPECIMEN VoiceOver value: \(value)")
    }

    // MARK: 5. Hosted renders (attachments)

    private func attachHostedRender(name: String, arguments: [String], typeSize: DynamicTypeSize = .large,
                                    prepare: (BenchModel) -> Void = { _ in }, settle: Double = 2.5) throws {
        let (app, bench) = try environment(arguments)
        let scale = try scene().screen.scale
        let cluster = InstrumentMetrics.cluster(available: 430 - 24)
        let side = cluster.diameter - 24
        bench.configureWindow(points: side, scale: scale)
        bench.start()
        prepare(bench)
        let content = UISPECIMEN_HostedBench(side: side).environment(bench).environment(app).dynamicTypeSize(typeSize)
        let (window, host) = try host(content)
        defer { window.isHidden = true }
        spin(until: { bench.lastFull[.a] != nil }, timeout: 15)
        XCTAssertNotNil(bench.lastFull[.a], "\(name): a full-resolution Run arrived")
        spin(until: { false }, timeout: settle)
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            _ = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "UI-SPECIMEN-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("UISPECIMEN hosted render \(name): \(Int(image.size.width))×\(Int(image.size.height)) pt at scale \(image.scale), probe \(bench.configuration.probe), loupe \(bench.loupe != nil)")
    }

    func testHostedRenderWindow() throws {
        try attachHostedRender(name: "hosted-window", arguments: ["-B2Scenario", "bench"])
    }
    func testHostedRenderLoupe() throws {
        try attachHostedRender(name: "hosted-loupe", arguments: ["-B2Scenario", "loupe"], settle: 3.5)
    }
    func testHostedRenderZoom4() throws {
        try attachHostedRender(name: "hosted-zoom4", arguments: ["-B2Scenario", "bench"]) { bench in
            bench.setZoom(4, centre: bench.configuration.probe.centre)
        }
    }
    /// Control for the capture method: the seed Bench's composition (a bare MetalSpecimenView with a SwiftUI Canvas
    /// crosshair in `.overlay`), which the phone's real screenshot shows correctly. If drawHierarchy drops it too, a missing
    /// overlay in the hosted renders is the capture, not the view.
    func testHostedRenderControlOverlay() throws {
        let (app, bench) = try environment(["-B2Scenario", "bench"])
        let scale = try scene().screen.scale
        bench.configureWindow(points: 298, scale: scale)
        bench.start()
        let presenter = try XCTUnwrap(app.presenter)
        let control = MetalSpecimenView(renderer: presenter, windowPixels: bench.configuration.windowSize)
            .frame(width: 298, height: 298)
            .overlay {
                Canvas { context, _ in
                    var cross = Path()
                    cross.move(to: CGPoint(x: 120, y: 149)); cross.addLine(to: CGPoint(x: 178, y: 149))
                    cross.move(to: CGPoint(x: 149, y: 120)); cross.addLine(to: CGPoint(x: 149, y: 178))
                    context.stroke(cross, with: .color(InstrumentPalette.instrumentAmber), lineWidth: 3)
                }
                .allowsHitTesting(false)
            }
        let (window, host) = try host(ZStack { InstrumentDesignBackground(); control })
        defer { window.isHidden = true }
        spin(until: { bench.lastFull[.a] != nil }, timeout: 15)
        spin(until: { false }, timeout: 1.5)
        for after in [true, false] {
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                _ = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: after)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "UI-SPECIMEN-control-after\(after)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testHostedRenderAccessibilitySize() throws {
        try attachHostedRender(name: "hosted-ax5", arguments: ["-B2Scenario", "loupe"], typeSize: .accessibility5, settle: 3.5)
    }
}

/// A Bench-shaped host for the hosted renders: the Metro background, the housing with the caption row and the window,
/// at the phone's width (the real Bench is UI-BENCH's; this only frames SpecimenWindow the way SPEC §4.1 places it).
struct UISPECIMEN_HostedBench: View {
    let side: CGFloat
    var body: some View {
        ZStack {
            InstrumentDesignBackground()
            VStack(spacing: 14) {
                Text("SPECIMEN WINDOW · HOSTED BY AN APPTEST").font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(2)
                    .foregroundStyle(.white.opacity(0.6))
                SpecimenHousing {
                    VStack(spacing: 0) {
                        SpecimenCaptionRow().frame(width: side, height: 24)
                        SpecimenWindow(side: side)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
    }
}
