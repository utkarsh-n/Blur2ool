import Foundation
import SwiftUI
import MetalKit
import UIKit
import BlurCore
import BlurGPU

// OWNER: UI-SPECIMEN (frozen public API, ARCHITECTURE §5.9 / AppContract/Render/PresentAPI.swift; body by UI-SPECIMEN).
// SwiftUI host of the MTKView plus the UIKit touch layer that feeds SpecimenGestureArbiter (BlurCore/Interaction): raw
// touches in, prioritised GestureIntents out (handle > pinch > long-press loupe > pan > tap), with a 30 Hz tick while one
// finger rests so the long press fires without movement. Line handles (the split and compare dividers, tilt-shift focus
// lines) are hit along their whole length: at touch-down each becomes a 44-pt target at the touch's projection onto it.
// The MTKView is also the image's VoiceOver element when the host supplies a `SpecimenAccessibilityModel` (SPEC §14):
// adjustable (probe ±step along the chosen axis), custom rotors `Probe axis` and `Probe step`, custom actions.

/// SwiftUI host of the MTKView plus the UIKit touch layer that feeds SpecimenGestureArbiter (BlurCore/Interaction).
/// The whole frame is wrapped in `instrumentControlOwnsTouches(identifier: "specimen")` by the Bench (Metro A.16).
public struct MetalSpecimenView: UIViewRepresentable {
    public let renderer: PresentRenderer
    /// Handle hit targets in window points (44-pt targets); empty for the periscope.
    public var handles: [HandleTarget]
    /// Gesture intents from the arbiter, already prioritised (handle > pinch > loupe > pan > tap).
    public var onIntent: @MainActor (GestureIntent) -> Void
    /// Window side in device pixels (894 on the 15 Pro Max): the drawable is exactly this, never auto-resized.
    public var windowPixels: Int

    // Additions to the frozen API (UI-SPECIMEN).
    /// Handles that are lines, hit anywhere within 22 pt of the line (the split and compare dividers, focus lines).
    public var lineHandles: [SpecimenLineHandle] = []
    /// Called with true when the first finger lands and false when the last lifts (before that touch's final intents),
    /// so every touch cancels timing and parity (RenderScheduler.touchBegan, SPEC §4.1.6).
    public var onTouchActivity: (@MainActor (Bool) -> Void)?
    /// The image's VoiceOver element (SPEC §14); nil leaves accessibility to the host's SwiftUI modifiers.
    public var accessibilityModel: SpecimenAccessibilityModel?

    public init(renderer: PresentRenderer, windowPixels: Int = 894, handles: [HandleTarget] = [],
                onIntent: @escaping @MainActor (GestureIntent) -> Void = { _ in }) {
        self.renderer = renderer; self.windowPixels = windowPixels; self.handles = handles; self.onIntent = onIntent
    }

    public func makeCoordinator() -> SpecimenTouchRecognizer { SpecimenTouchRecognizer() }

    /// Review fix E-20: a fixed N × N drawable (no autoResizeDrawable, so fractional layout cannot make it 893 px and
    /// silently resample the 1 : 1 present), the screen's scale, and an sRGB-tagged layer. A phone AppTest asserts it.
    public func makeUIView(context: Context) -> MTKView {
        let view = SpecimenMTKView(frame: .zero, device: renderer.coordinator.gpu.device)
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.autoResizeDrawable = false
        view.framebufferOnly = true
        view.isOpaque = true
        view.backgroundColor = .black
        let scale = context.environment.displayScale
        if scale.isFinite && scale > 0 { view.contentScaleFactor = scale }   // re-applied in updateUIView once in a window
        view.delegate = renderer
        renderer.attach(view)            // the display mode: SDR = bgra8Unorm + sRGB-tagged layer (EDR on request)
        // Last, and re-asserted by the view whenever MTKView recomputes it (a pixel-format or scale change resets it).
        view.fixedDrawableSize = CGSize(width: windowPixels, height: windowPixels)
        let recognizer = context.coordinator
        configure(recognizer)
        view.addGestureRecognizer(recognizer)
        view.accessibilityModel = accessibilityModel
        return view
    }

    public func updateUIView(_ view: MTKView, context: Context) {
        let scale = context.environment.displayScale
        if scale.isFinite && scale > 0 && view.contentScaleFactor != scale { view.contentScaleFactor = scale }
        let size = CGSize(width: windowPixels, height: windowPixels)
        if let fixed = view as? FixedDrawableMTKView { fixed.fixedDrawableSize = size } else if view.drawableSize != size { view.drawableSize = size }
        configure(context.coordinator)
        (view as? SpecimenMTKView)?.accessibilityModel = accessibilityModel
        view.setNeedsDisplay()
    }

    private func configure(_ recognizer: SpecimenTouchRecognizer) {
        recognizer.handles = handles
        recognizer.lineHandles = lineHandles
        recognizer.onIntent = onIntent
        recognizer.onTouchActivity = onTouchActivity
    }
}

/// A handle that is a line (SPEC §4.1.3: the split divider is a 44 × 298 handle; focus-band lines). Vertical lines are
/// hit within `hitRadius` of `position` along x, horizontal ones along y; `extent` limits the other axis (nil = whole view).
public struct SpecimenLineHandle: Sendable, Hashable {
    public enum Axis: Sendable, Hashable { case vertical, horizontal }
    public var id: String
    public var axis: Axis
    /// x of a vertical line or y of a horizontal one, in view points.
    public var position: Double
    public var extent: ClosedRange<Double>?
    public var hitRadius: Double
    public init(id: String, axis: Axis, position: Double, extent: ClosedRange<Double>? = nil, hitRadius: Double = 22) {
        self.id = id; self.axis = axis; self.position = position; self.extent = extent; self.hitRadius = hitRadius
    }
    /// The point handle this line becomes for a touch at `p`: its projection onto the line (the arbiter then hits it
    /// exactly when |distance to the line| ≤ hitRadius).
    public func target(for p: SIMD2<Double>) -> HandleTarget? {
        switch axis {
        case .vertical:
            if let extent, !extent.contains(p.y) { return nil }
            return HandleTarget(id: id, centre: SIMD2(position, p.y), hitRadius: hitRadius)
        case .horizontal:
            if let extent, !extent.contains(p.x) { return nil }
            return HandleTarget(id: id, centre: SIMD2(p.x, position), hitRadius: hitRadius)
        }
    }
}

/// The UIKit touch layer: forwards raw touches to SpecimenGestureArbiter and performs nothing itself.
@MainActor
public final class SpecimenTouchRecognizer: UIGestureRecognizer {
    var handles: [HandleTarget] = []
    var lineHandles: [SpecimenLineHandle] = []
    var onIntent: @MainActor (GestureIntent) -> Void = { _ in }
    var onTouchActivity: (@MainActor (Bool) -> Void)?
    private var arbiter = SpecimenGestureArbiter(bounds: SIMD2(298, 298))
    private var ticker: Timer?
    private var active = false

    public init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    private func points(_ touches: Set<UITouch>) -> [TouchPoint] {
        touches.map { touch in
            let p = touch.location(in: view)
            return TouchPoint(id: ObjectIdentifier(touch).hashValue, location: SIMD2(Double(p.x), Double(p.y)))
        }
    }
    private func deliver(_ intents: [GestureIntent]) { for intent in intents { onIntent(intent) } }
    private func setActive(_ on: Bool) {
        guard on != active else { return }
        active = on
        onTouchActivity?(on)
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let size = view?.bounds.size { arbiter.bounds = SIMD2(Double(size.width), Double(size.height)) }
        let down = points(touches)
        // Line handles become point targets at the first touch's projection (only a one-finger touch can grab a handle).
        var targets = handles
        if let first = down.first { targets += lineHandles.compactMap { $0.target(for: first.location) } }
        setActive(true)
        deliver(arbiter.handle(TouchEvent(phase: .began, touches: down, time: event.timestamp), handles: targets))
        if state == .possible { state = .began }
        if ticker == nil {
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.deliver(self.arbiter.tick(time: ProcessInfo.processInfo.systemUptime))
                }
            }
            RunLoop.main.add(timer, forMode: .common)   // keeps ticking while a scroll view tracks
            ticker = timer
        }
    }
    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        deliver(arbiter.handle(TouchEvent(phase: .moved, touches: points(touches), time: event.timestamp), handles: handles))
        state = .changed
    }
    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        let intents = arbiter.handle(TouchEvent(phase: .ended, touches: points(touches), time: event.timestamp), handles: handles)
        let allLifted = (event.touches(for: self) ?? []).allSatisfy { touches.contains($0) }
        if allLifted { setActive(false) }   // the interaction ends first, so a tap's probe renders at full resolution
        deliver(intents)
        if allLifted { finish(.ended) }
    }
    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        let intents = arbiter.handle(TouchEvent(phase: .cancelled, touches: points(touches), time: event.timestamp), handles: handles)
        setActive(false)
        deliver(intents)
        finish(.cancelled)
    }
    public override func reset() {
        super.reset()
        ticker?.invalidate(); ticker = nil
        if active { setActive(false) }
    }
    private func finish(_ final: UIGestureRecognizer.State) {
        ticker?.invalidate(); ticker = nil
        arbiter.reset()
        state = final
    }
}

// MARK: - The image's VoiceOver element (SPEC §14)

/// What VoiceOver hears and can do on the image. Built by the host (SpecimenWindow) from BenchModel; the MTKView carries
/// it as one adjustable element. Rotor `Probe axis` (x/y) and `Probe step` (1 / 16 px) change how swipes move the probe.
@MainActor
public final class SpecimenAccessibilityModel {
    public enum Axis: String, Sendable { case x, y }
    public var label: String = "Image window"
    /// The spoken value; it starts with the provenance ("Live, Metal. …").
    public var value: () -> String = { "" }
    public var hint: String? = "Swipe up or down to move the probe. Use the rotor to choose its axis and step."
    public var axis: Axis = .x
    public var step: Int = 1
    /// Moves the probe by (dx, dy) window pixels and returns what to announce.
    public var moveProbe: (Int, Int) -> Void = { _, _ in }
    /// Custom actions in SPEC §14 order (name, handler returning true when handled).
    public var actions: [(name: String, handler: () -> Bool)] = []
    public init() {}

    func adjust(_ direction: Int) {
        let d = direction * step
        if axis == .x { moveProbe(d, 0) } else { moveProbe(0, d) }
    }
    /// Runs the current handler of the action named `name` (handlers change with the Bench's state; names rarely do).
    func perform(_ name: String) -> Bool { actions.first { $0.name == name }?.handler() ?? false }
}

/// An MTKView whose drawable stays exactly `fixedDrawableSize` (review fix E-20). MTKView couples the two: setting
/// `contentScaleFactor` recomputes the drawable as bounds × scale (0 × 0 before layout), and setting `drawableSize` sets
/// `contentScaleFactor` = drawable / bounds (MEASURED on the phone 14 Oct 2026: the E-20 AppTest read a 0 × 0 drawable, and
/// an unguarded re-assert recursed through `-[MTKView setDrawableSize:]` → `setContentScaleFactor:` until the stack ran out).
/// So the size is re-asserted only once bounds exist, and never re-entrantly; with bounds = N / displayScale points the
/// scale MTKView derives is exactly displayScale.
@MainActor
class FixedDrawableMTKView: MTKView {
    var fixedDrawableSize: CGSize? { didSet { assertDrawableSize() } }
    private var asserting = false
    override var colorPixelFormat: MTLPixelFormat { didSet { assertDrawableSize() } }
    override var contentScaleFactor: CGFloat { didSet { assertDrawableSize() } }
    override func layoutSubviews() {
        super.layoutSubviews()
        assertDrawableSize()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        assertDrawableSize()
    }
    private func assertDrawableSize() {
        guard !asserting, let size = fixedDrawableSize, size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        asserting = true
        defer { asserting = false }
        if autoResizeDrawable { autoResizeDrawable = false }
        if drawableSize != size { drawableSize = size }
    }
}

/// The specimen MTKView: an MTKView (the frozen `makeUIView` type) that can also be the image's accessibility element.
@MainActor
final class SpecimenMTKView: FixedDrawableMTKView {
    /// Assigning the same model again only refreshes the action list when its names changed, so VoiceOver's rotor and
    /// action state survive the frequent SwiftUI updates of a live window.
    var accessibilityModel: SpecimenAccessibilityModel? {
        didSet {
            if accessibilityModel !== oldValue { applyAccessibility() } else { refreshActions() }
        }
    }
    private var actionNames: [String] = []

    private func applyAccessibility() {
        guard let model = accessibilityModel else {
            isAccessibilityElement = false
            accessibilityCustomRotors = nil
            accessibilityCustomActions = nil
            actionNames = []
            return
        }
        isAccessibilityElement = true
        accessibilityLabel = model.label
        accessibilityHint = model.hint
        accessibilityTraits = [.adjustable, .image]
        accessibilityIdentifier = "specimen.window"
        accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Probe axis") { [weak self] _ in
                guard let self, let model = self.accessibilityModel else { return nil }
                model.axis = model.axis == .x ? .y : .x
                UIAccessibility.post(notification: .announcement, argument: "Probe axis \(model.axis.rawValue)")
                return UIAccessibilityCustomRotorItemResult(targetElement: self, targetRange: nil)
            },
            UIAccessibilityCustomRotor(name: "Probe step") { [weak self] _ in
                guard let self, let model = self.accessibilityModel else { return nil }
                model.step = model.step == 1 ? 16 : 1
                UIAccessibility.post(notification: .announcement, argument: model.step == 1 ? "Probe step 1 pixel" : "Probe step 16 pixels")
                return UIAccessibilityCustomRotorItemResult(targetElement: self, targetRange: nil)
            },
        ]
        actionNames = []
        refreshActions()
    }

    private func refreshActions() {
        guard let model = accessibilityModel else { return }
        accessibilityLabel = model.label
        let names = model.actions.map(\.name)
        guard names != actionNames else { return }
        actionNames = names
        accessibilityCustomActions = names.map { name in
            UIAccessibilityCustomAction(name: name) { [weak self] _ in self?.accessibilityModel?.perform(name) ?? false }
        }
    }

    override var accessibilityValue: String? {
        get { accessibilityModel?.value() }
        set { }
    }
    override func accessibilityIncrement() { accessibilityModel?.adjust(+1) }
    override func accessibilityDecrement() { accessibilityModel?.adjust(-1) }
}
