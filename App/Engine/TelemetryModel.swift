import Foundation
import Observation
import BlurCore

// OWNER: ENGINE (frozen public API, ARCHITECTURE §5.9). Live numbers observed ONLY by the telemetry leaf views
// (Toothpaste lesson, METRO §F.5 item 4), so a new number never invalidates the Bench's body. Written by BenchModel from
// full-resolution Runs only (a preview never writes here; while one is on screen `isHeld` is true and the leaves engrave
// HELD), from settled timing Runs (GPU, ΔGPU) and from parity after timing (PARITY). Every value is a BadgedValue.

@MainActor @Observable
public final class TelemetryModel {
    /// σ EFF: second moment of the discrete kernel the GPU runs (COMPUTED); MEASURED · OFFSCREEN for Tier S fits.
    public var sigmaEff: BadgedValue?
    /// GPU (BLUR PASSES): MEASURED median of the settled timing Run; `–.––` until it exists; `TOO SLOW TO TIME` above budget.
    public var gpu: BadgedValue?
    /// PARITY: max |GPU − CPU| on the 128 × 128 crop around the probe in 8-bit steps (MEASURED), or the reason it is
    /// report-only (`SUB-TEXEL RULE NOT YET MEASURED`).
    public var parity: BadgedValue?
    /// Compare mode: ΔGPU (A − B), the axis-specific column, MAX |A−B| with its position.
    public var deltaGPU: BadgedValue?
    public var axisColumn: LabeledValue?
    public var maxDifference: BadgedValue?
    public var maxDifferenceAt: PixelPoint?
    /// True while a preview is on screen: every value above is the last full-resolution one, engraved HELD (SPEC §4.1.6).
    public var isHeld: Bool = false
    public init() {}

    /// Back to the empty state (a new blur or test image): every slot reads `–.––` until the next full Run.
    public func clearMeasurements(keepSigma: Bool = false) {
        if !keepSigma { sigmaEff = nil }
        gpu = .notYetMeasured(unit: "ms")
        parity = .notYetMeasured()
        deltaGPU = nil; maxDifference = nil; maxDifferenceAt = nil
    }
}
