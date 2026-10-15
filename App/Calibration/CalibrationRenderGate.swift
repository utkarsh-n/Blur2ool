import Foundation

// OWNER: CALIBRATION (ARCHITECTURE §5.13 review fix E-21; SPEC §13.2). A single ImageRenderer render is synchronous on
// the main actor and cannot be pre-empted (the first one also compiles RenderBox pipelines), so a 16-ms slice cannot be
// enforced. The rule instead: ONE render per run-loop turn, each one timed; the gap before the next render starts at one
// 16-ms frame and doubles after every render that took longer than 16 ms (reset after a render under 16 ms; capped);
// no render while any control is active; any touch pauses the queue. Every calibration render goes through this gate.
// Platform-neutral (Foundation only): the macOS cross-check harness compiles it too.

@MainActor
public final class CalibrationRenderGate {
    public static let shared = CalibrationRenderGate()

    /// The base gap: one display frame at 60 Hz, so the UI always gets a run-loop turn between two renders.
    public static let baseGapMilliseconds = 16.0
    /// A render slower than this doubles the gap.
    public static let budgetMilliseconds = 16.0
    public static let maximumGapMilliseconds = 256.0

    public private(set) var gapMilliseconds = CalibrationRenderGate.baseGapMilliseconds
    /// Set by the service: a touch (or the Pause button) holds every render until it is cleared.
    public var paused = false
    /// Set through the idle-gate hook while a crown, handle or Stepper is held: no render runs meanwhile.
    public var controlActive = false
    public private(set) var lastRenderMilliseconds: Double?
    public private(set) var rendersTimed = 0
    /// Renders that exceeded the 16-ms budget (each doubled the gap).
    public private(set) var slowRenders = 0
    /// Sum of every timed render (the service reads differences: the render time of one measurement).
    public private(set) var totalMilliseconds = 0.0

    public init() {}

    /// Waits for this render's turn: the current gap (one run-loop turn at least), then while paused or a control is
    /// active. Returns false when the calling task was cancelled.
    public func waitForTurn() async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(gapMilliseconds * 1_000_000))
            while paused || controlActive {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        } catch {
            return false
        }
        return !Task.isCancelled
    }

    /// Times one synchronous render and applies the × 2 back-off.
    public func timed<T>(_ render: () -> T) -> (value: T, milliseconds: Double) {
        let start = DispatchTime.now().uptimeNanoseconds
        let value = render()
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        finished(milliseconds: ms)
        return (value, ms)
    }

    public func finished(milliseconds ms: Double) {
        lastRenderMilliseconds = ms
        rendersTimed += 1
        totalMilliseconds += ms
        if ms > Self.budgetMilliseconds {
            slowRenders += 1
            gapMilliseconds = Swift.min(Self.maximumGapMilliseconds, gapMilliseconds * 2)
        } else {
            gapMilliseconds = Self.baseGapMilliseconds
        }
    }

    public func reset() {
        gapMilliseconds = Self.baseGapMilliseconds
        paused = false
    }
}
