import Foundation

// FROZEN API — ARCHITECTURE.md §5.10. The image window's gesture arbiter (SPEC §4.1.3): pure logic, unit-tested with
// `swift test`; the app's UIKit touch layer forwards raw touches and performs the returned intents.
// OWNER: ENGINE (bodies; tests in Tests/BlurCoreTests/ENGINE/). Public signatures are the skeleton's, unchanged.
// Priority, highest first: handle drag > pinch > long-press loupe > one-finger drag (pan) > tap (probe).
//
// Rules implemented here (the ENGINE arbiter matrix tests every one):
// • One finger within a handle's hit radius (22 pt) starts a handle drag; the nearest handle wins. A handle drag never
//   pans, and a second finger never interrupts it (handle > pinch).
// • A second finger turns a pending touch, a pan or an open loupe into a pinch (pinch > loupe > pan > tap). The pan ends
//   (`panEnded`) and the loupe is cancelled without placing the probe (`loupeEnded(placeProbeAt: nil)`) first.
// • A still finger becomes the loupe once it has been down for `longPressSeconds` (0.35 s, inclusive) within the slop.
//   The 30 Hz `tick` fires it without movement; a move, lift or second finger arriving after that moment without a tick
//   first promotes the touch to the loupe, so the outcome never depends on timer jitter.
// • A move of more than `slopPoints` (8 pt, exclusive) from the touch-down point before the long press is a pan.
// • A lift before the long press with at most 8 pt of travel is a tap: `placeProbe` at the lift point.
// • A loupe lifted inside the window places the probe at its centre; lifted outside the window it is cancelled.
// • After a pinch, and after any gesture whose finger lifts while other fingers stay down, the remaining fingers are
//   ignored until every touch has lifted (`.draining`).
// • `cancelled` ends the active gesture with its own closing intent (so begin/end always pair), then `.cancelled`.

/// One active touch, in points of the window's coordinate space (origin top-left).
public struct TouchPoint: Sendable, Hashable {
    public var id: Int
    public var location: SIMD2<Double>
    public init(id: Int, location: SIMD2<Double>) { self.id = id; self.location = location }
}

public enum TouchPhase: String, Sendable, Hashable { case began, moved, ended, cancelled }

public struct TouchEvent: Sendable, Hashable {
    public var phase: TouchPhase
    /// The touches this event is about (began: the new ones; moved: all moving; ended/cancelled: the lifted ones).
    public var touches: [TouchPoint]
    /// Seconds (CACurrentMediaTime or any monotonic clock).
    public var time: Double
    public init(phase: TouchPhase, touches: [TouchPoint], time: Double) { self.phase = phase; self.touches = touches; self.time = time }
}

/// A draggable handle's hit target (44-pt square → 22-pt radius).
public struct HandleTarget: Sendable, Hashable {
    public var id: String
    public var centre: SIMD2<Double>
    public var hitRadius: Double
    public init(id: String, centre: SIMD2<Double>, hitRadius: Double = 22) { self.id = id; self.centre = centre; self.hitRadius = hitRadius }
}

public enum GestureIntent: Sendable, Hashable {
    case placeProbe(SIMD2<Double>)
    case handleBegan(String), handleMoved(String, SIMD2<Double>), handleEnded(String)
    case panBegan, panMoved(delta: SIMD2<Double>), panEnded
    case zoomBegan(centre: SIMD2<Double>), zoomChanged(scale: Double, centre: SIMD2<Double>), zoomEnded
    case loupeBegan(SIMD2<Double>), loupeMoved(SIMD2<Double>), loupeEnded(placeProbeAt: SIMD2<Double>?)
    case cancelled
}

public struct SpecimenGestureArbiter: Sendable {
    public enum State: Sendable, Hashable {
        case idle
        case pending(touch: Int, start: SIMD2<Double>, startTime: Double, last: SIMD2<Double>)
        case handle(touch: Int, id: String)
        case pan(touch: Int, last: SIMD2<Double>)
        case loupe(touch: Int, last: SIMD2<Double>)
        case pinch(a: Int, b: Int, startDistance: Double)
        /// After a pinch: ignore the remaining finger until every touch has lifted.
        case draining
    }

    public let longPressSeconds: Double
    public let slopPoints: Double
    /// The window's size in points; a loupe lifted outside it is cancelled.
    public var bounds: SIMD2<Double>
    public private(set) var state: State = .idle
    private var down: [Int: SIMD2<Double>] = [:]

    public init(bounds: SIMD2<Double>, longPressSeconds: Double = 0.35, slopPoints: Double = 8) {
        self.bounds = bounds; self.longPressSeconds = longPressSeconds; self.slopPoints = slopPoints
    }

    public mutating func reset() { state = .idle; down = [:] }

    public mutating func handle(_ event: TouchEvent, handles: [HandleTarget]) -> [GestureIntent] {
        switch event.phase {
        case .began: return began(event, handles: handles)
        case .moved: return moved(event)
        case .ended: return ended(event)
        case .cancelled: return cancelled()
        }
    }

    /// Called by a timer while one touch is down and still, so the long press fires without movement.
    public mutating func tick(time: Double) -> [GestureIntent] { promoteLongPress(at: time) }

    // MARK: - Transitions

    /// A pending touch held for `longPressSeconds` within the slop becomes the loupe (at its last position).
    private mutating func promoteLongPress(at time: Double) -> [GestureIntent] {
        guard case let .pending(touch, _, startTime, last) = state, time - startTime >= longPressSeconds - 1e-9 else { return [] }
        state = .loupe(touch: touch, last: last)
        return [.loupeBegan(last)]
    }

    private mutating func began(_ event: TouchEvent, handles: [HandleTarget]) -> [GestureIntent] {
        // A touch held still past the long-press time is a loupe before anything else happens to it.
        var out = promoteLongPress(at: event.time)
        for t in event.touches { down[t.id] = t.location }
        switch state {
        case .idle:
            if down.count == 1, let t = event.touches.first {
                let hit = handles.filter { distance($0.centre, t.location) <= $0.hitRadius }
                    .min { distance($0.centre, t.location) < distance($1.centre, t.location) }
                if let hit {
                    state = .handle(touch: t.id, id: hit.id)
                    return out + [.handleBegan(hit.id)]
                }
                state = .pending(touch: t.id, start: t.location, startTime: event.time, last: t.location)
                return out
            }
            return out + beginPinch()
        case .pending:
            return out + beginPinch()
        case .pan:
            out.append(.panEnded)
            return out + beginPinch()
        case .loupe:
            out.append(.loupeEnded(placeProbeAt: nil))      // pinch beats loupe: the loupe closes without moving the probe
            return out + beginPinch()
        case .handle, .pinch, .draining:
            return out                                       // handle > pinch; a third finger never joins a pinch
        }
    }

    /// The two lowest touch ids still down form the pinch.
    private mutating func beginPinch() -> [GestureIntent] {
        guard down.count >= 2 else { return [] }
        let ids = Array(down.keys.sorted().prefix(2))
        guard let a = down[ids[0]], let b = down[ids[1]] else { return [] }
        state = .pinch(a: ids[0], b: ids[1], startDistance: Swift.max(distance(a, b), 1))
        return [.zoomBegan(centre: (a + b) / 2)]
    }

    private mutating func moved(_ event: TouchEvent) -> [GestureIntent] {
        let out = promoteLongPress(at: event.time)
        for t in event.touches where down[t.id] != nil { down[t.id] = t.location }
        switch state {
        case let .pending(touch, start, startTime, _):
            guard let p = down[touch] else { return out }
            if distance(p, start) > slopPoints {
                state = .pan(touch: touch, last: p)
                return out + [.panBegan, .panMoved(delta: p - start)]
            }
            state = .pending(touch: touch, start: start, startTime: startTime, last: p)
            return out
        case let .handle(touch, id):
            guard event.touches.contains(where: { $0.id == touch }), let p = down[touch] else { return out }
            return out + [.handleMoved(id, p)]
        case let .pan(touch, last):
            guard event.touches.contains(where: { $0.id == touch }), let p = down[touch], p != last else { return out }
            state = .pan(touch: touch, last: p)
            return out + [.panMoved(delta: p - last)]
        case let .loupe(touch, last):
            guard event.touches.contains(where: { $0.id == touch }), let p = down[touch], p != last else { return out }
            state = .loupe(touch: touch, last: p)
            return out + [.loupeMoved(p)]
        case let .pinch(a, b, startDistance):
            guard event.touches.contains(where: { $0.id == a || $0.id == b }), let pa = down[a], let pb = down[b] else { return out }
            return out + [.zoomChanged(scale: distance(pa, pb) / startDistance, centre: (pa + pb) / 2)]
        case .idle, .draining:
            return out
        }
    }

    private mutating func ended(_ event: TouchEvent) -> [GestureIntent] {
        var out = promoteLongPress(at: event.time)
        let lifted = Set(event.touches.map(\.id))
        func liftPoint(_ id: Int, fallback: SIMD2<Double>) -> SIMD2<Double> { event.touches.first { $0.id == id }?.location ?? fallback }
        defer {
            for id in lifted { down[id] = nil }
            if down.isEmpty { state = .idle }
        }
        let othersRemain = !down.keys.filter { !lifted.contains($0) }.isEmpty
        switch state {
        case let .pending(touch, _, _, last) where lifted.contains(touch):
            state = othersRemain ? .draining : .idle
            return out + [.placeProbe(liftPoint(touch, fallback: last))]
        case let .handle(touch, id) where lifted.contains(touch):
            state = othersRemain ? .draining : .idle
            return out + [.handleEnded(id)]
        case let .pan(touch, last) where lifted.contains(touch):
            let p = liftPoint(touch, fallback: last)
            if p != last { out.append(.panMoved(delta: p - last)) }
            state = othersRemain ? .draining : .idle
            return out + [.panEnded]
        case let .loupe(touch, last) where lifted.contains(touch):
            let p = liftPoint(touch, fallback: last)
            if p != last { out.append(.loupeMoved(p)) }
            state = othersRemain ? .draining : .idle
            return out + [.loupeEnded(placeProbeAt: isInside(p) ? p : nil)]
        case let .pinch(a, b, _) where lifted.contains(a) || lifted.contains(b):
            state = othersRemain ? .draining : .idle
            return out + [.zoomEnded]
        default:
            return out
        }
    }

    private mutating func cancelled() -> [GestureIntent] {
        let closing: [GestureIntent]
        switch state {
        case .idle: closing = []
        case .pending, .draining: closing = [.cancelled]
        case .handle(_, let id): closing = [.handleEnded(id), .cancelled]
        case .pan: closing = [.panEnded, .cancelled]
        case .loupe: closing = [.loupeEnded(placeProbeAt: nil), .cancelled]
        case .pinch: closing = [.zoomEnded, .cancelled]
        }
        reset()
        return closing
    }

    private func isInside(_ p: SIMD2<Double>) -> Bool { p.x >= 0 && p.y >= 0 && p.x < bounds.x && p.y < bounds.y }
}

private func distance(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
    let d = a - b
    return (d.x * d.x + d.y * d.y).squareRoot()
}
