import SwiftUI
import CoreHaptics
import BlurCore

// OWNER: METRO-COMPONENTS (frozen initialiser, ARCHITECTURE §5.14; Metro §10, §15; METRO §C.4; SPEC §4.1.5, §9.1, §14).
// The metal crown, ported from Metro Station `App/Views/TempoCrownsView.swift` (TempoCrownControl + CrownMetalFace):
//   • 62-pt knurled metal face (40 grooves, concentric rings, accent pointer and datum) between two REAL 44 × 44 native
//     glass ± Buttons in a GlassEffectContainer; captions in reserved scaled 14-pt rows (Metro §10 Appearance).
//   • Gesture = `InstrumentCrownGesture` (pure, unit-tested on the phone): a 7-pt centre exclusion applied BEFORE the angle
//     reaches `CrownDetentTracker` (crossing the bearing discards angular history, so emerging cannot jump), the first
//     touch never steps, at most one step per update, 18 % reversal hysteresis, a pending notch is dropped on a deliberate
//     reversal, and `DetentRateLimiter` admits ≤ 20 detents per second (Metro §10).
//   • Haptics per role (Metro §15 detent vocabulary, Core Haptics transients from the token manifest): FINE, ANGLE and the
//     SECOND crown use the fine up/down pair; SEMANTIC uses the semantic pair. Feedback is emitted once per ACCEPTED change:
//     the crown plays it when the host's accessibilityValue changes within 0.3 s of the step it sent, so a step refused at a
//     range end stays silent (Metro contract A.17). Settings › Haptics reaches it through `\.instrumentHapticsEnabled`.
//   • VoiceOver: the face is one adjustable element with the same step; the ± buttons are separate real buttons.
//   • Never inside a TimelineView (Metro contract A.7); the host keeps its identity stable.
public enum CrownRole: Sendable { case fine, semantic, angle, second }

public extension EnvironmentValues {
    /// Settings › Haptics (AppSettings.hapticsEnabled). Hosts set it; the crown and the decimal Stepper read it. Default on.
    @Entry var instrumentHapticsEnabled: Bool = true
}

public struct InstrumentCrown: View {
    private let caption: String
    private let subcaption: String
    private let role: CrownRole
    private let detentDegrees: Double
    private let isEnabled: Bool
    private let label: String
    private let value: String
    private let onStep: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.instrumentHapticsEnabled) private var hapticsEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption2) private var captionRowHeight = InstrumentMetrics.captionRowHeight
    @State private var gesture: InstrumentCrownGesture
    @State private var awaitingFeedback: (direction: Int, time: Double)?

    public init(caption: String, subcaption: String, role: CrownRole, detentDegrees: Double, isEnabled: Bool = true,
                accessibilityLabel: String, accessibilityValue: String, onStep: @escaping (Int) -> Void) {
        self.caption = caption; self.subcaption = subcaption; self.role = role; self.detentDegrees = detentDegrees
        self.isEnabled = isEnabled; self.label = accessibilityLabel; self.value = accessibilityValue; self.onStep = onStep
        _gesture = State(initialValue: InstrumentCrownGesture(detentDegrees: detentDegrees))
    }

    /// Fine and angle crowns are cyan (continuous signal/control); semantic and second crowns are amber (Metro §10, SPEC §9.1).
    nonisolated public static func accent(_ role: CrownRole) -> Color {
        switch role {
        case .fine, .angle: InstrumentPalette.instrumentCyan
        case .semantic, .second: InstrumentPalette.instrumentAmber
        }
    }

    /// The face's centre symbol: what one notch means (Metro draws "1" for one BPM and a metronome for a marking).
    nonisolated public static func symbol(_ role: CrownRole) -> String {
        switch role {
        case .fine: "plusminus"
        case .semantic: "stairs"
        case .angle: "angle"
        case .second: "dial.medium"
        }
    }

    private var accent: Color { InstrumentCrown.accent(role) }
    private var accessibleCaptions: Bool { dynamicTypeSize.isAccessibilitySize }

    public var body: some View {
        VStack(spacing: 5) {
            Text(caption)
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(accent)
                .lineLimit(accessibleCaptions ? 2 : 1)
                .minimumScaleFactor(accessibleCaptions ? 1 : 0.9)
                .multilineTextAlignment(.center)
                .frame(minHeight: captionRowHeight)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)

            GlassEffectContainer(spacing: InstrumentMetrics.crownGlassSpacing) {
                HStack(spacing: InstrumentMetrics.crownGlassSpacing) {
                    stepButton(-1)
                    face
                    stepButton(1)
                }
            }
            .instrumentControlOwnsTouches(identifier: "crown")

            Text(subcaption)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(InstrumentOpacity.captionInk))
                .lineLimit(accessibleCaptions ? 2 : 1)
                .minimumScaleFactor(accessibleCaptions ? 1 : 0.9)
                .multilineTextAlignment(.center)
                .frame(minHeight: captionRowHeight)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .opacity(isEnabled ? 1 : InstrumentOpacity.disabledControl)
        .onAppear { if hapticsEnabled { InstrumentDetentHaptics.shared.prepare() } }
        .onDisappear { finishGesture() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { finishGesture() } }
        .onChange(of: value) { _, _ in playAcceptedFeedback() }
    }

    // MARK: Face

    private var face: some View {
        let d = InstrumentMetrics.crownDiameter
        return InstrumentCrownFace(accent: accent, symbol: InstrumentCrown.symbol(role),
                                   rotation: reduceMotion ? 0 : gesture.rotation, isPressed: gesture.isDragging)
            .frame(width: d, height: d)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    guard isEnabled else { return }
                    let event = gesture.move(to: drag.location, at: ProcessInfo.processInfo.systemUptime)
                    InstrumentCrown.dispatch(event, isEnabled: isEnabled) { emit($0) }
                }
                .onEnded { _ in finishGesture() })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityHint(InstrumentCrown.hint(role))
            .accessibilityAdjustableAction { direction in
                guard isEnabled else { return }
                switch direction {
                case .increment: emit(1)
                case .decrement: emit(-1)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("instrumentCrown.\(role)")
    }

    nonisolated static func hint(_ role: CrownRole) -> String {
        switch role {
        case .fine: "Turn clockwise, or swipe up, for one fine step up; counterclockwise for one step down."
        case .semantic: "Turn, or swipe up or down, to move to the next or previous named stop."
        case .angle: "Turn clockwise, or swipe up, to rotate by one step."
        case .second: "Turn clockwise, or swipe up, for one step up of the second parameter."
        }
    }

    private func stepButton(_ direction: Int) -> some View {
        Button { emit(direction) } label: {
            Image(systemName: direction > 0 ? "plus" : "minus")
                .font(.system(size: InstrumentMetrics.crownSymbol, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: InstrumentMetrics.controlTarget, height: InstrumentMetrics.controlTarget)
                .contentShape(.circle)
                .glassEffect(.regular.tint(accent.opacity(InstrumentOpacity.crownGlassTint)).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(direction > 0 ? "Increase \(label)" : "Decrease \(label)")
        .accessibilityIdentifier("instrumentCrown.\(role).\(direction > 0 ? "plus" : "minus")")
    }

    // MARK: Accepted steps and feedback

    private func emit(_ direction: Int) {
        guard let step = InstrumentCrown.accepted(direction, isEnabled: isEnabled) else { return }
        awaitingFeedback = (step, ProcessInfo.processInfo.systemUptime)
        onStep(step)
    }

    /// The step a request turns into: ±1 (any positive or negative request is one notch), or nil when the crown is
    /// disabled or the request is zero. Every input path (detent, ± button, adjustable action) goes through it.
    nonisolated public static func accepted(_ direction: Int, isEnabled: Bool) -> Int? {
        guard isEnabled, direction != 0 else { return nil }
        return direction > 0 ? 1 : -1
    }

    /// The gesture path exactly as the face's DragGesture runs it: a `.step` event becomes one `onStep` call.
    nonisolated public static func dispatch(_ event: InstrumentCrownGesture.Event, isEnabled: Bool, onStep: (Int) -> Void) {
        guard case .step(let direction) = event, let step = accepted(direction, isEnabled: isEnabled) else { return }
        onStep(step)
    }

    /// The host accepted the step when its value changed: one haptic for one accepted change (Metro §15).
    private func playAcceptedFeedback() {
        guard let pending = awaitingFeedback else { return }
        awaitingFeedback = nil
        guard hapticsEnabled, ProcessInfo.processInfo.systemUptime - pending.time <= 0.3 else { return }
        InstrumentDetentHaptics.shared.play(InstrumentDetentKind(role: role, direction: pending.direction))
    }

    private func finishGesture() {
        gesture.end()
    }
}

// MARK: - Gesture logic (pure; Tests/AppTests/METROCOMPONENTS)

/// The crown's touch logic, ported from Metro Station's TempoCrownControl with BlurCore's `CrownDetentTracker` and
/// `DetentRateLimiter`. Coordinates are crown-local points (origin top-left of the 62-pt face); time is in seconds.
public struct InstrumentCrownGesture: Sendable {
    public enum Event: Sendable, Equatable {
        /// Nothing to report (inside the centre exclusion, sub-detent travel, or a rate-limited pending notch).
        case none
        /// The first touch outside the exclusion: angular history begins; the value never changes on it (Metro §10).
        case began
        /// One accepted detent, ±1.
        case step(Int)
    }

    public let detentDegrees: Double
    public let diameter: Double
    public let centreExclusion: Double
    public private(set) var isDragging = false
    /// Accumulated visual rotation of the face in degrees (clockwise positive).
    public private(set) var rotation: Double = 0
    private var tracker: CrownDetentTracker
    private var limiter: DetentRateLimiter
    private var previousVisualAngle: Double?
    private var pendingStep = 0

    public init(detentDegrees: Double, diameter: Double = Double(InstrumentMetrics.crownDiameter),
                centreExclusion: Double = Double(InstrumentMetrics.crownCentreExclusion),
                maxEventsPerSecond: Double = InstrumentMotion.detentMaxHz) {
        self.detentDegrees = detentDegrees; self.diameter = diameter; self.centreExclusion = centreExclusion
        tracker = CrownDetentTracker(detentDegrees: detentDegrees)
        limiter = DetentRateLimiter(maxEventsPerSecond: maxEventsPerSecond)
    }

    /// Whether a crown-local point lies inside the centre exclusion (the bearing), where angles are meaningless.
    public func isInsideExclusion(_ location: CGPoint) -> Bool {
        let dx = Double(location.x) - diameter / 2, dy = Double(location.y) - diameter / 2
        return (dx * dx + dy * dy).squareRoot() < centreExclusion
    }

    public mutating func move(to location: CGPoint, at time: Double) -> Event {
        guard !isInsideExclusion(location) else {
            // Crossing the bearing discards only angular history; emerging on the other side cannot create a large step.
            tracker.reset()
            previousVisualAngle = nil
            pendingStep = 0
            return .none
        }
        let dx = Double(location.x) - diameter / 2, dy = Double(location.y) - diameter / 2
        let angle = atan2(dy, dx) * 180 / .pi
        if !isDragging {
            isDragging = true
            tracker = CrownDetentTracker(detentDegrees: detentDegrees)
            tracker.begin(angleDegrees: angle)
            limiter.reset()
            previousVisualAngle = angle
            pendingStep = 0
            return .began
        }
        if let previousVisualAngle {
            var delta = angle - previousVisualAngle
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            // A queued notch cannot fire against a new direction; sub-half-degree tremor leaves it calm.
            if pendingStep != 0, delta * Double(pendingStep) < -InstrumentMotion.crownTremorDegrees { pendingStep = 0 }
            rotation += delta
        }
        previousVisualAngle = angle
        let detent = tracker.update(angleDegrees: angle)
        if detent != 0 { pendingStep = detent }
        guard pendingStep != 0, limiter.admit(at: time) else { return .none }
        let direction = pendingStep
        pendingStep = 0
        return .step(direction)
    }

    /// The touch lifted, was cancelled, the view disappeared or the scene went inactive.
    public mutating func end() {
        guard isDragging else { return }
        isDragging = false
        tracker.reset()
        previousVisualAngle = nil
        pendingStep = 0
    }
}

// MARK: - Face (CrownMetalFace port; tokens from the manifest's `metal.*`)

private struct InstrumentCrownFace: View {
    let accent: Color
    let symbol: String
    let rotation: Double
    let isPressed: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(InstrumentPalette.crownBase)
                .shadow(color: .black.opacity(InstrumentOpacity.crownShadow),
                        radius: isPressed ? InstrumentMetrics.crownPressedShadowRadius : InstrumentMetrics.crownShadowRadius,
                        y: isPressed ? InstrumentMetrics.crownPressedShadowY : InstrumentMetrics.crownShadowY)
            Canvas { context, size in
                let diameter = Swift.min(size.width, size.height)
                let center = CGPoint(x: diameter / 2, y: diameter / 2)
                let rim = CGRect(x: 1.5, y: 1.5, width: diameter - 3, height: diameter - 3)
                context.fill(Path(ellipseIn: rim), with: .linearGradient(
                    Gradient(colors: [InstrumentPalette.crownRimLight, InstrumentPalette.crownRimDark, InstrumentPalette.crownRimMid]),
                    startPoint: CGPoint(x: 9, y: 0), endPoint: CGPoint(x: diameter - 8, y: diameter)))
                for index in 0..<InstrumentMetrics.crownKnurls {
                    let radians = (Double(index) * 360 / Double(InstrumentMetrics.crownKnurls) + rotation) * .pi / 180
                    var groove = Path()
                    groove.move(to: CGPoint(x: center.x + cos(radians) * diameter * 0.40, y: center.y + sin(radians) * diameter * 0.40))
                    groove.addLine(to: CGPoint(x: center.x + cos(radians) * diameter * 0.475, y: center.y + sin(radians) * diameter * 0.475))
                    context.stroke(groove, with: .color(.black.opacity(0.65)), lineWidth: 1.5)
                    context.stroke(groove, with: .color(.white.opacity(0.20)), lineWidth: 0.45)
                }
                let face = CGRect(x: 8, y: 8, width: diameter - 16, height: diameter - 16)
                context.fill(Path(ellipseIn: face), with: .linearGradient(
                    Gradient(colors: [InstrumentPalette.crownFaceLight, InstrumentPalette.crownFaceDark]),
                    startPoint: CGPoint(x: center.x - 12, y: 3), endPoint: CGPoint(x: diameter - 7, y: diameter)))
                context.stroke(Path(ellipseIn: face), with: .color(.white.opacity(0.31)), lineWidth: 0.7)
                for inset in stride(from: 11.0, through: 16.0, by: 1.5) {
                    context.stroke(Path(ellipseIn: CGRect(x: inset, y: inset, width: diameter - inset * 2, height: diameter - inset * 2)),
                                   with: .color(.white.opacity(0.045)), lineWidth: 0.4)
                }
                let pointerAngle = (-90 + rotation) * .pi / 180
                var pointer = Path()
                pointer.move(to: CGPoint(x: center.x + cos(pointerAngle) * 16, y: center.y + sin(pointerAngle) * 16))
                pointer.addLine(to: CGPoint(x: center.x + cos(pointerAngle) * 21, y: center.y + sin(pointerAngle) * 21))
                context.stroke(pointer, with: .color(accent), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                var datum = Path()
                datum.move(to: CGPoint(x: center.x - 2.5, y: 0.5))
                datum.addLine(to: CGPoint(x: center.x + 2.5, y: 0.5))
                datum.addLine(to: CGPoint(x: center.x, y: 4))
                datum.closeSubpath()
                context.fill(datum, with: .color(accent))
            }
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .dynamicTypeSize(.large)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Haptic detents (Metro §15; Core Haptics transients, prewarmed and cached)

public enum InstrumentDetentKind: Sendable, Hashable, CaseIterable {
    case fineUp, fineDown, semanticUp, semanticDown

    public init(role: CrownRole, direction: Int) {
        let up = direction > 0
        switch role {
        case .semantic: self = up ? .semanticUp : .semanticDown
        case .fine, .angle, .second: self = up ? .fineUp : .fineDown
        }
    }
    public var intensity: Float {
        switch self {
        case .fineUp: InstrumentHapticDetent.fineUpIntensity
        case .fineDown: InstrumentHapticDetent.fineDownIntensity
        case .semanticUp: InstrumentHapticDetent.semanticUpIntensity
        case .semanticDown: InstrumentHapticDetent.semanticDownIntensity
        }
    }
    public var sharpness: Float {
        switch self {
        case .fineUp: InstrumentHapticDetent.fineUpSharpness
        case .fineDown: InstrumentHapticDetent.fineDownSharpness
        case .semanticUp: InstrumentHapticDetent.semanticUpSharpness
        case .semanticDown: InstrumentHapticDetent.semanticDownSharpness
        }
    }
}

/// One Core Haptics engine for every adjustment control, with one cached transient player per detent kind. Feedback is
/// skipped (never queued) when it would exceed the detent density cap of 20 per second (Metro §15 "skip obsolete queued
/// feedback rather than producing bursts"). Devices without haptics stay silent; every change also shows a number.
@MainActor
public final class InstrumentDetentHaptics {
    public static let shared = InstrumentDetentHaptics()

    private var engine: CHHapticEngine?
    private var players: [InstrumentDetentKind: any CHHapticPatternPlayer] = [:]
    private var engineRunning = false
    private var lastPlayed = -Double.infinity
    public private(set) var playedCount = 0

    private init() {}

    public var isSupported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

    public func prepare() {
        guard isSupported, engine == nil else { return }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = true
            engine.resetHandler = { [weak self] in Task { @MainActor in self?.rebuildAfterReset() } }
            engine.stoppedHandler = { [weak self] _ in Task { @MainActor in self?.engineRunning = false } }
            try engine.start()
            self.engine = engine
            engineRunning = true
            cachePlayers()
        } catch {
            engine = nil
        }
    }

    public func play(_ kind: InstrumentDetentKind) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPlayed >= 1 / InstrumentMotion.detentMaxHz - 1e-6 else { return }
        if engine == nil { prepare() }
        guard let engine else { return }
        lastPlayed = now
        do {
            if !engineRunning { try engine.start(); engineRunning = true }
            if players[kind] == nil { cachePlayers() }
            try players[kind]?.start(atTime: CHHapticTimeImmediate)
            playedCount += 1
        } catch {
            engineRunning = false
            players.removeAll()
        }
    }

    private func cachePlayers() {
        guard let engine else { return }
        for kind in InstrumentDetentKind.allCases where players[kind] == nil {
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: kind.intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: kind.sharpness)
            ], relativeTime: 0)
            if let pattern = try? CHHapticPattern(events: [event], parameters: []),
               let player = try? engine.makePlayer(with: pattern) {
                players[kind] = player
            }
        }
    }

    private func rebuildAfterReset() {
        players.removeAll()
        engineRunning = false
        guard let engine else { return }
        do { try engine.start(); engineRunning = true; cachePlayers() } catch { self.engine = nil }
    }
}
