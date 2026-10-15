import Foundation
import Metal
import BlurCore

// FROZEN — ARCHITECTURE.md §5.8. Measurement and Apple-twin seams (implemented by GPU-MEASURE and APPLE-TWINS in
// Sources/BlurGPU/Measure/ and Sources/BlurGPU/AppleTwins/). The app installs the implementations at launch.

public struct TimingRequest: Sendable, Hashable {
    public var warmups: Int
    /// Maximum timed samples (15).
    public var samples: Int
    /// Stop early once this many samples exist and summed GPU time reached `maxGPUSeconds` (review fix E-7).
    public var minSamples: Int
    public var maxGPUSeconds: Double
    public var isolation: PassIsolation
    /// Also time the fused form (fewest encoders) to report MEASUREMENT OVERHEAD.
    public var measureFused: Bool
    public init(warmups: Int = 3, samples: Int = 15, minSamples: Int = 3, maxGPUSeconds: Double = 1.0,
                isolation: PassIsolation = .singleCommandBuffer, measureFused: Bool = false) {
        self.warmups = warmups; self.samples = samples; self.minSamples = minSamples; self.maxGPUSeconds = maxGPUSeconds
        self.isolation = isolation; self.measureFused = measureFused
    }
}

/// SPEC §4.1.6: timing only after settle, at full resolution; returns nil in the Simulator (never a number).
/// Times the BLUR PASSES only (the pipeline's encode on an already pre-passed input); colour passes and the window copy
/// are timed once separately into `overheadMilliseconds` (review fix E-57). Budgeted and cancellable (E-7): it checks
/// `Task.isCancelled` between command buffers and throws `CancellationError` (every touch cancels it), stops at
/// `request.samples` or `maxGPUSeconds`, and is never called when the plan exceeds `FetchBudget.full`.
@MainActor
public protocol GPUTimingMeasuring: AnyObject {
    func measure(_ pipeline: any GPUBlurPipeline, inputs: GPUBlurInputs, request: TimingRequest,
                 context: GPUContext) async throws -> TimingSummary?
    /// ABAB interleaving for Compare's ΔGPU (thermal state recorded at both ends).
    func measureInterleaved(_ a: (any GPUBlurPipeline, GPUBlurInputs), _ b: (any GPUBlurPipeline, GPUBlurInputs),
                            request: TimingRequest, context: GPUContext) async throws -> (TimingSummary, TimingSummary)?
    /// A stage-boundary sampler for one recorder, or nil when the device has no stage-boundary counters.
    func makeSampler(passes: Int, context: GPUContext) -> (any PassTimestampSampling)?
}

/// SPEC §4.7 This phone; on demand only (JF G-17), never at launch.
@MainActor
public protocol DeviceProbing: AnyObject {
    func run(_ kind: DeviceProbeKind, context: GPUContext, device: DeviceStamp) async throws -> DeviceProbeResult
}

/// Core Image / MPS / vImage twins run in-process on this device (SPEC §8.2 Apple axis, §13.1).
@MainActor
public protocol AppleTwinRunning: AnyObject {
    func supports(_ subject: CalibrationSubject) -> Bool
    /// Runs the Apple API with its own parameter on `input` (window-sized rgba16Float, linear) into `output`.
    func run(_ subject: CalibrationSubject, parameter: Double, input: any MTLTexture, output: any MTLTexture,
             context: GPUContext) async throws
    /// Renders a step edge (and its 45° twin) through the API at `phases` whole-pixel offsets and returns edge samples
    /// for the PSF fitter (Calibrate for Core Image / MPS / vImage subjects).
    func edgeSamples(_ request: CalibrationRequest, context: GPUContext) async throws -> [EdgeSamples]
}

/// GPU-side fingerprint measurement from impulse grid, 4-phase step edge, 1-px stripes and a star crop (SPEC §7.1 item 10).
@MainActor
public protocol ShapeMeasuring: AnyObject {
    func measure(_ pipeline: any GPUBlurPipeline, request: OperatorRequest, context: GPUContext) async throws -> ShapeMeasurement
}

/// Main-actor service locator; the skeleton installs placeholder conformers that report "not available yet" honestly,
/// the owning areas replace them (their concrete type names are fixed in ARCHITECTURE §8).
@MainActor
public enum GPUServices {
    public static var timing: (any GPUTimingMeasuring)?
    public static var probes: (any DeviceProbing)?
    public static var appleTwins: (any AppleTwinRunning)?
    public static var shapes: (any ShapeMeasuring)?
}
