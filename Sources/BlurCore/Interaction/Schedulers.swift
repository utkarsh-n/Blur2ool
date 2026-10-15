import Foundation

// FROZEN API — ARCHITECTURE.md §5.10. Requested-vs-acknowledged render scheduling (SPEC §4.1.6) and the idle gate for
// automatic SwiftUI calibration (SPEC §2, §13.2). Pure logic with an injected clock.
// OWNER: ENGINE (bodies; tests in Tests/BlurCoreTests/ENGINE/). The skeleton's public signatures are unchanged; ENGINE
// adds one member, `measurementsFinished(generation:)` (requests/ENGINE.md item 1), so that a touch which cancels a
// measurement in flight re-arms it, while a touch after a completed measurement does not repeat it.

public enum RenderAction: Sendable, Hashable {
    /// Render the newest requested configuration now.
    case render(quality: RenderQuality, generation: UInt64)
    /// 300 ms after the last change, at full resolution: budgeted timing (3 warm-ups, ≤ 15 samples or 1 s of GPU time),
    /// then parity at background priority (never per detent).
    case startTiming(generation: UInt64)
    /// A change or touch arrived while timing/parity ran: cancel them between command buffers (review fix E-7).
    case cancelMeasurements
}

public struct RenderScheduler: Sendable {
    public let settleSeconds: Double
    public private(set) var currentGeneration: UInt64 = 0
    public private(set) var lastAcknowledged: UInt64 = 0
    private var lastChange: Double?
    private var lastQuality: RenderQuality = .full
    private var settled = true
    private var interacting = false
    private var measuring = false

    public init(settleSeconds: Double = 0.3) { self.settleSeconds = settleSeconds }

    /// Every accepted change renders at once: at `preview` quality (`BlurOperator.previewScale`: half or quarter) while
    /// interacting, otherwise full. Measurements in flight are cancelled first.
    public mutating func requestChanged(at time: Double, preview: RenderQuality?, interacting: Bool) -> [RenderAction] {
        currentGeneration += 1
        lastChange = time
        settled = false
        self.interacting = interacting
        lastQuality = interacting ? (preview ?? .full) : .full
        var actions: [RenderAction] = []
        if measuring { measuring = false; actions.append(.cancelMeasurements) }
        actions.append(.render(quality: lastQuality, generation: currentGeneration))
        return actions
    }

    /// A touch began anywhere (crown, handle, specimen): measurements in flight stop. The measurement of the current
    /// generation did not finish, so it is re-armed: it runs again `settleSeconds` after the interaction ends (or at the
    /// next settled tick), still once per generation.
    public mutating func touchBegan() -> [RenderAction] {
        guard measuring else { return [] }
        measuring = false
        settled = false
        return [.cancelMeasurements]
    }

    /// A crown, handle or pan was released.
    public mutating func interactionEnded(at time: Double) {
        interacting = false
        lastChange = time
    }

    /// After `settleSeconds` without a change and without interaction: re-render at full resolution if the last render
    /// was a preview, then start timing — once per generation.
    public mutating func tick(at time: Double) -> [RenderAction] {
        guard !settled, !interacting, let last = lastChange, time - last >= settleSeconds - 1e-9 else { return [] }
        settled = true
        var actions: [RenderAction] = []
        if lastQuality != .full {
            lastQuality = .full
            actions.append(.render(quality: .full, generation: currentGeneration))
        }
        actions.append(.startTiming(generation: currentGeneration))
        measuring = true
        return actions
    }

    /// Timing and parity for `generation` completed (or were skipped on purpose, e.g. above the budget): a later touch
    /// no longer cancels or repeats them. Stale generations are ignored.
    public mutating func measurementsFinished(generation: UInt64) {
        if generation == currentGeneration { measuring = false }
    }

    /// A Run for `generation` completed. Returns false (drop it) when an equal-or-newer generation has already been
    /// published: a stale render never overwrites a newer one. Renders are coalesced (latest wins): at most one render
    /// per slot is in flight, and when it completes the newest pending request is rendered once.
    public mutating func acknowledge(_ generation: UInt64) -> Bool {
        guard generation >= lastAcknowledged else { return false }
        lastAcknowledged = generation
        return true
    }
    public func isStale(_ generation: UInt64) -> Bool { generation < currentGeneration }
    /// True while the requested state differs from the acknowledged one (status row: RENDERING…).
    public var isRendering: Bool { lastAcknowledged < currentGeneration }
}

/// Automatic SwiftUI calibration may run only when ≥ 10 s since launch, ≥ 3 s since the last touch, no crown or handle
/// is active and the thermal state is nominal or fair (SPEC §2, §13.2; JF M-3). The same gate releases the one-time
/// sub-texel probe and the hero-dozen pipeline pre-warm (ARCHITECTURE §5.10).
public struct CalibrationIdleScheduler: Sendable {
    public let launchTime: Double
    public let minimumSinceLaunch: Double
    public let minimumIdle: Double
    public private(set) var lastTouch: Double
    public private(set) var controlActive = false

    public init(launchTime: Double, minimumSinceLaunch: Double = 10, minimumIdle: Double = 3) {
        self.launchTime = launchTime; self.minimumSinceLaunch = minimumSinceLaunch; self.minimumIdle = minimumIdle
        lastTouch = launchTime
    }
    /// Touch times only move forward (a late, older timestamp never shortens the idle time already counted).
    public mutating func noteTouch(at time: Double) { lastTouch = Swift.max(lastTouch, time) }
    public mutating func setControlActive(_ active: Bool) { controlActive = active }
    public func mayRun(at time: Double, thermal: ThermalLevel) -> Bool {
        time - launchTime >= minimumSinceLaunch && time - lastTouch >= minimumIdle && !controlActive
            && (thermal == .nominal || thermal == .fair)
    }
}
