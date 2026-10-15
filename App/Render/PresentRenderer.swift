import Foundation
import SwiftUI
import MetalKit
import BlurCore
import BlurGPU

// OWNER: UI-SPECIMEN (frozen public API, ARCHITECTURE §5.9 / AppContract/Render/PresentAPI.swift; body by UI-SPECIMEN).
// The present path: an on-demand MTKView whose drawable is exactly the window in device pixels, presenting the newest
// output 1 : 1 (nearest), magnified nearest up to 8×, with the before/after split, the Compare views (Wipe, Flip,
// Difference × 1/16/256, Line-up 2 × 2), pass intermediates, the periscope crop and the loupe's 14 × 14 copy.
// Shader: B2Present.metal (`b2_present_fs`); geometry: PresentGeometry (the same numbers the overlays and touches use).
// SDR: a bgra8Unorm drawable with an sRGB-tagged layer; the shader encodes and clips. EDR (Settings › Display): an
// rgba16Float drawable, extended linear sRGB, `wantsExtendedDynamicRangeContent`. Pipelines compile off the main actor.

public enum PresentMode: Sendable, Hashable {
    /// Output only, or the before/after split when `split` is set.
    case output
    /// Compare views (Wipe, Flip, Difference × gain, Line-up 2 × 2).
    case compare(CompareView)
    /// Periscope: a crop of the same output texture (or a pass intermediate) around the probe.
    case crop(PixelRegion)
}

public struct PresentOptions: Sendable, Hashable {
    public var mode: PresentMode
    /// Before/after split 0…1 (input left of the divider), nil = off.
    public var split: Double?
    public var zoom: Double
    public var zoomCentre: SIMD2<Double>
    /// Show a pass intermediate instead of the final output.
    public var pass: Int?
    /// Flip view: true while B is held.
    public var showingB: Bool
    public var displayMode: DisplayMode
    public init(mode: PresentMode = .output, split: Double? = 0.5, zoom: Double = 1, zoomCentre: SIMD2<Double> = SIMD2(447, 447),
                pass: Int? = nil, showingB: Bool = false, displayMode: DisplayMode = .sdr) {
        self.mode = mode; self.split = split; self.zoom = zoom; self.zoomCentre = zoomCentre; self.pass = pass
        self.showingB = showingB; self.displayMode = displayMode
    }
}

/// The MTKView delegate. Draws only when asked (isPaused = true, enableSetNeedsDisplay = true) and while a gesture or
/// crown is active. The drawable is bgra8Unorm with an sRGB-tagged layer; the present shader encodes and clips (SDR).
@MainActor
public final class PresentRenderer: NSObject, MTKViewDelegate {
    public let coordinator: RenderCoordinator
    public var options: PresentOptions {
        didSet {
            guard options != oldValue else { return }
            if options.displayMode != oldValue.displayMode, let view { applyDisplayMode(to: view) }
            requestRedraw()
        }
    }

    // MARK: Additions to the frozen API (UI-SPECIMEN; used by MetalSpecimenView, SpecimenWindow, the loupe, the periscope)

    /// Rubber-band display shift in drawable pixels while a pan is dragged past the canvas edge (display only).
    public var overscroll: SIMD2<Int32> = .zero { didSet { if overscroll != oldValue { requestRedraw() } } }
    /// Colour behind transparent pixels, linear premultiplied (the specimen canvas's `backdrop`; opaque black by default).
    public var backdrop: SIMD4<Float> = SIMD4(0, 0, 0, 1) { didSet { if backdrop != oldValue { requestRedraw() } } }
    /// Difference-view contours: display-encoded sRGB colour (alpha 0 = off) and spacing in 8-bit steps (LSB).
    public var contourColour: SIMD4<Float> = .zero { didSet { if contourColour != oldValue { requestRedraw() } } }
    public var contourStepLSB: Double? { didSet { if contourStepLSB != oldValue { requestRedraw() } } }
    /// The loupe's renderer presents only its texel copy: before the first reading it shows black, never a live texture.
    public var presentsTexelCopyOnly = false
    /// The view-point side of the attached view (overlays and touches share this geometry).
    public private(set) var viewPoints: Double = 0
    /// Number of presented frames (diagnostics and AppTests).
    public private(set) var presentedFrames = 0
    /// The pipelines (bgra8Unorm and, on demand, rgba16Float) exist.
    public var isReady: Bool { pipelines[MTLPixelFormat.bgra8Unorm.rawValue] != nil }

    private var pipelines: [MTLPixelFormat.RawValue: any MTLRenderPipelineState] = [:]
    private var compiling: Set<MTLPixelFormat.RawValue> = []
    private weak var view: MTKView?
    private var placeholder: (any MTLTexture)?
    /// The loupe's texel copy (SPEC §4.1.3): when set, a `.crop` presents this texture instead of the coordinator's.
    private var texelCopy: (texture: any MTLTexture, width: Int, height: Int)?

    public init(coordinator: RenderCoordinator, options: PresentOptions = PresentOptions()) {
        self.coordinator = coordinator; self.options = options
        super.init()
        compilePipeline(.bgra8Unorm)
        if options.displayMode == .edr { compilePipeline(.rgba16Float) }
    }

    /// The view this renderer draws into (set by MetalSpecimenView and the loupe).
    public func attach(_ view: MTKView) {
        self.view = view
        applyDisplayMode(to: view)
        PresentRenderer.register(self, with: coordinator)
    }
    /// Ask for one on-demand draw (the coordinator calls it whenever a display texture changes).
    public func requestRedraw() { view?.setNeedsDisplay() }

    /// Present a texel copy (the loupe's 14 × 14 reading, `LoupeReading.texels`, row-major) instead of a coordinator
    /// texture. The values came from an rgba16Float readback, so storing them as fp16 again is exact. nil clears it.
    public func showTexels(_ texels: [SIMD4<Float>]?, width: Int, height: Int) {
        guard let texels, texels.count == width * height, width > 0, height > 0 else { texelCopy = nil; requestRedraw(); return }
        let device = coordinator.gpu.device
        var texture = texelCopy?.texture
        if texture == nil || texelCopy?.width != width || texelCopy?.height != height {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
            d.usage = .shaderRead
            d.storageMode = .shared
            texture = device.makeTexture(descriptor: d)
        }
        guard let texture else { texelCopy = nil; return }
        var halves = texels.flatMap { [Float16($0.x), Float16($0.y), Float16($0.z), Float16($0.w)] }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: &halves, bytesPerRow: width * 8)
        texelCopy = (texture, width, height)
        requestRedraw()
    }

    /// Configures the attached view for the display mode: SDR = bgra8Unorm + sRGB layer (never an _srgb format: the
    /// Simulator forbids sRGB writes, SDK §15 rule 7); EDR = rgba16Float + extended linear sRGB + EDR content.
    public func applyDisplayMode(to view: MTKView) {
        let layer = view.layer as? CAMetalLayer
        switch options.displayMode {
        case .sdr:
            view.colorPixelFormat = .bgra8Unorm
            layer?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            layer?.wantsExtendedDynamicRangeContent = false
        case .edr:
            compilePipeline(.rgba16Float)
            view.colorPixelFormat = .rgba16Float
            layer?.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
            layer?.wantsExtendedDynamicRangeContent = true
        }
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { requestRedraw() }

    public func draw(in view: MTKView) {
        viewPoints = Double(view.bounds.width)
        guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
              let commandBuffer = coordinator.gpu.queue.makeCommandBuffer() else { return }
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "present"
        encodePresent(encoder, width: drawable.texture.width, height: drawable.texture.height, format: view.colorPixelFormat)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        presentedFrames += 1
    }

    /// Renders one present pass into `target` (AppTests on the phone: the same encode the MTKView uses, read back).
    public func render(into target: any MTLTexture) async -> Bool {
        guard let commandBuffer = coordinator.gpu.queue.makeCommandBuffer() else { return false }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        let drew = encodePresent(encoder, width: target.width, height: target.height, format: target.pixelFormat)
        encoder.endEncoding()
        let completion = await coordinator.gpu.commit(commandBuffer)
        return drew && completion.error == nil
    }

    // MARK: Encoding

    /// The geometry of this view: the window side comes from the coordinator's input window (always full resolution,
    /// N × N), so previews and pass intermediates of other sizes map through their own ratio.
    public func geometry(drawablePixels: Int, viewPoints points: Double? = nil) -> PresentGeometry {
        let n = coordinator.inputTexture(slot: .a)?.width ?? drawablePixels
        var crop: PixelRegion?
        if case .crop(let region) = options.mode {
            crop = texelCopy.map { PixelRegion(origin: .zero, size: ImageSize(width: $0.width, height: $0.height)) } ?? region
        }
        return PresentGeometry(windowPixels: n, drawablePixels: drawablePixels, viewPoints: points ?? viewPoints,
                               zoom: options.zoom, zoomCentre: options.zoomCentre, crop: crop)
    }

    @discardableResult
    func encodePresent(_ encoder: any MTLRenderCommandEncoder, width: Int, height: Int, format: MTLPixelFormat) -> Bool {
        guard let pipeline = pipelines[format.rawValue] else {
            compilePipeline(format)
            return false
        }
        let geometry = self.geometry(drawablePixels: width)
        let n = Float(geometry.windowPixels)
        var params = PresentShaderParams()
        params.backdrop = backdrop
        params.drawableSize = SIMD2(Float(width), Float(height))
        params.edr = format == .rgba16Float ? 1 : 0
        params.origin = SIMD2<Float>(geometry.origin)
        params.texelsPerPixel = SIMD2(repeating: Float(geometry.texelsPerPixel))
        params.shift = overscroll
        var slots: [(any MTLTexture)?] = [nil, nil, nil, nil]

        switch options.mode {
        case .output:
            let output = coordinator.displayTexture(slot: .a, pass: options.pass)
            let input = coordinator.inputTexture(slot: .a)
            if output == nil, let input {
                // First frame (review fix E-25): the sharp INPUT window until the first Run arrives; no divider.
                slots[0] = input
            } else {
                slots[0] = output
                slots[1] = input
                params.splitColumn = Int32(geometry.splitColumn(options.split) ?? -1)
            }
            params.mode = PresentShaderParams.Mode.output.rawValue
        case .compare(let view):
            slots[0] = coordinator.displayTexture(slot: .a, pass: options.pass)
            slots[1] = coordinator.displayTexture(slot: .b, pass: nil)
            switch view {
            case .wipe:
                params.mode = PresentShaderParams.Mode.wipe.rawValue
                params.splitColumn = Int32(geometry.splitColumn(options.split ?? 0.5) ?? -1)
            case .flip:
                params.mode = PresentShaderParams.Mode.flip.rawValue
                params.showB = options.showingB ? 1 : 0
            case .difference1, .difference16, .difference256:
                params.mode = PresentShaderParams.Mode.difference.rawValue
                params.gain = Float(view.differenceGain ?? 1)
                let step = contourStepLSB ?? PresentRenderer.defaultContourStepLSB(gain: view.differenceGain ?? 1)
                params.contour = contourColour
                params.contourStep = Float(step / 255)
            case .lineUp:
                params.mode = PresentShaderParams.Mode.lineUp.rawValue
                slots[2] = coordinator.displayTexture(slot: .c, pass: nil)
                slots[3] = coordinator.displayTexture(slot: .d, pass: nil)
                params.texelsPerPixel = SIMD2(repeating: Float(Double(geometry.windowPixels) / Double(width)))
                params.lineUpOrigin = SIMD2(repeating: Float(geometry.lineUpCropOrigin))
                params.origin = .zero
                params.shift = .zero
            }
        case .crop:
            params.mode = PresentShaderParams.Mode.crop.rawValue
            params.shift = .zero
            if let copy = texelCopy {
                slots[0] = copy.texture
            } else if presentsTexelCopyOnly {
                slots[0] = nil
            } else {
                slots[0] = coordinator.displayTexture(slot: .a, pass: options.pass)
            }
        }

        // Ratios: texture texels per window pixel (1 for full-size outputs; ½ and ≈ ¼ for previews; 1 for the texel copy).
        func ratio(_ t: (any MTLTexture)?) -> SIMD2<Float> {
            guard let t else { return SIMD2(1, 1) }
            if case .crop = options.mode, texelCopy != nil { return SIMD2(1, 1) }
            return SIMD2(Float(t.width) / n, Float(t.height) / n)
        }
        let ra = ratio(slots[0]), rb = ratio(slots[1]), rc = ratio(slots[2]), rd = ratio(slots[3])
        params.ratioAB = SIMD4(ra.x, ra.y, rb.x, rb.y)
        params.ratioCD = SIMD4(rc.x, rc.y, rd.x, rd.y)
        params.available = (slots[0] != nil ? PresentShaderParams.hasA : 0) | (slots[1] != nil ? PresentShaderParams.hasB : 0)
            | (slots[2] != nil ? PresentShaderParams.hasC : 0) | (slots[3] != nil ? PresentShaderParams.hasD : 0)

        guard let placeholder = placeholderTexture() else { return false }
        encoder.setRenderPipelineState(pipeline)
        for (index, texture) in slots.enumerated() { encoder.setFragmentTexture(texture ?? placeholder, index: index) }
        encoder.setFragmentBytes(&params, length: MemoryLayout<PresentShaderParams>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        return true
    }

    /// Contour spacing per gain: every 64 LSB at × 1, 4 LSB at × 16, ¼ LSB at × 256 (four contours across the ramp).
    public static func defaultContourStepLSB(gain: Double) -> Double { 64 / Swift.max(gain, 1) }

    /// A 1 × 1 texture bound to unused slots (Metal validation wants every declared texture bound); never sampled,
    /// because `available` marks the slot missing.
    private func placeholderTexture() -> (any MTLTexture)? {
        if let placeholder { return placeholder }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 1, height: 1, mipmapped: false)
        d.usage = .shaderRead
        d.storageMode = .shared
        guard let t = coordinator.gpu.device.makeTexture(descriptor: d) else { return nil }
        var black: [Float16] = [0, 0, 0, 1]
        t.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &black, bytesPerRow: 8)
        placeholder = t
        return t
    }

    /// Builds the present pipeline for one drawable format in a detached task (never on the main actor, §5.8).
    private func compilePipeline(_ format: MTLPixelFormat) {
        guard pipelines[format.rawValue] == nil, !compiling.contains(format.rawValue) else { return }
        compiling.insert(format.rawValue)
        let device = coordinator.gpu.device, library = coordinator.gpu.library
        let raw = format.rawValue
        Task { [weak self] in
            let state = await Task.detached(priority: .userInitiated) { () -> (any MTLRenderPipelineState)? in
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.label = "b2_present_fs"
                descriptor.vertexFunction = library.makeFunction(name: "b2_common_fullscreen_vs")
                descriptor.fragmentFunction = library.makeFunction(name: "b2_present_fs")
                descriptor.colorAttachments[0].pixelFormat = MTLPixelFormat(rawValue: raw) ?? .bgra8Unorm
                return try? device.makeRenderPipelineState(descriptor: descriptor)
            }.value
            guard let self else { return }
            self.compiling.remove(raw)
            if let state { self.pipelines[raw] = state }
            self.requestRedraw()
        }
    }

    /// Waits until the SDR pipeline exists (AppTests).
    public func waitUntilReady(timeout: Double = 5) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !isReady && ProcessInfo.processInfo.systemUptime < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        return isReady
    }

    // MARK: Redraw fan-out

    /// RenderCoordinator has one `onDisplayChanged` closure (AppEnvironment points it at the Bench's renderer). Every other
    /// renderer of the same coordinator (the periscope) registers here on attach; the first registration chains the
    /// existing closure, so a new display texture redraws every attached view. Hubs remember their coordinator weakly, so
    /// a new coordinator at a reused address starts a fresh hub.
    private final class RedrawHub {
        weak var coordinator: RenderCoordinator?
        var renderers: [WeakRenderer] = []
        init(coordinator: RenderCoordinator) { self.coordinator = coordinator }
    }
    private struct WeakRenderer { weak var renderer: PresentRenderer? }
    private static var hubs: [ObjectIdentifier: RedrawHub] = [:]
    private static func register(_ renderer: PresentRenderer, with coordinator: RenderCoordinator) {
        let key = ObjectIdentifier(coordinator)
        if let hub = hubs[key], hub.coordinator === coordinator {
            hub.renderers.removeAll { $0.renderer == nil }
            if !hub.renderers.contains(where: { $0.renderer === renderer }) { hub.renderers.append(WeakRenderer(renderer: renderer)) }
            return
        }
        hubs = hubs.filter { $0.value.coordinator != nil }
        let hub = RedrawHub(coordinator: coordinator)
        hub.renderers = [WeakRenderer(renderer: renderer)]
        hubs[key] = hub
        let previous = coordinator.onDisplayChanged
        coordinator.onDisplayChanged = { [weak hub] in
            previous?()
            for entry in hub?.renderers ?? [] { entry.renderer?.requestRedraw() }
        }
    }
}
