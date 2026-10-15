import Foundation
import Metal
import BlurCore

// FROZEN — ARCHITECTURE.md §5.8. The GPU blur pipeline protocol, implemented per (blur, variant) by the FAM-* areas in
// Sources/BlurGPU/Pipelines/<Group>/, published through `<Group>Pipelines.factories`.

@MainActor
public protocol GPUBlurPipeline: AnyObject {
    var blur: BlurID { get }
    var variant: VariantID { get }
    /// The family shader file ("F2Gaussian.metal") and every Metal function this pipeline may use (provenance, §6.6).
    var shaderFile: String { get }
    var functionNames: [String] { get }
    /// True when the last pass writes the destination from a compute kernel (destination needs `.shaderWrite`).
    var writesDestinationFromCompute: Bool { get }
    /// Builds pipeline states asynchronously (`await context.computePipeline / renderPipeline`; BOTH TRACE_PROBE
    /// specializations for traceable passes, for the request's edge mode) and sizes scratch textures. Called when the
    /// variant, edge mode or window size changes and before Trace opens, never per frame (review fix E-3).
    func prepare(_ context: GPUContext, request: OperatorRequest) async throws
    /// Encodes every pass, one encoder per pass obtained from `recorder` with the pass's plan index. With `trace`, uses
    /// the TRACE_PROBE specialization for traceable passes and writes the probe's taps, then one flags = 2 record holding
    /// the stored value, into the returned trace buffer. Uses only `context.prepared…Pipeline` (never compiles; a miss
    /// throws `GPUError.notPrepared`). Must not commit, wait, read back, or touch colour space/alpha.
    /// Intermediates and scratch stay valid until the next `encode` on this instance (§5.8 rule 5).
    func encode(_ context: GPUContext, _ inputs: GPUBlurInputs, trace: TraceRequest?, recorder: GPUCommandRecorder) throws -> EncodedBlur
}

/// How the registry makes a pipeline and which parity cases it publishes.
public struct GPUPipelineFactory: Sendable {
    public var blur: BlurID
    public var variant: VariantID
    public var make: @MainActor @Sendable () -> any GPUBlurPipeline
    /// Parity cases for a window size (blur-gpucheck runs them at 256 and 894; ARCHITECTURE §7).
    public var parityCases: @Sendable (_ windowSize: Int) -> [ParityCase]
    public init(blur: BlurID, variant: VariantID, make: @escaping @MainActor @Sendable () -> any GPUBlurPipeline,
                parityCases: @escaping @Sendable (_ windowSize: Int) -> [ParityCase]) {
        self.blur = blur; self.variant = variant; self.make = make; self.parityCases = parityCases
    }
}

public enum GPUPipelineRegistry {
    public static let factories: [GPUPipelineFactory] =
        F1Pipelines.factories + F2Pipelines.factories + F3Pipelines.factories + F4Pipelines.factories
        + F5APipelines.factories + F5BPipelines.factories + F6Pipelines.factories + F7Pipelines.factories
        + F8APipelines.factories + F8BPipelines.factories + F9Pipelines.factories + F10Pipelines.factories
        + F11Pipelines.factories

    public static func factory(_ blur: BlurID, _ variant: VariantID) -> GPUPipelineFactory? {
        factories.first { $0.blur == blur && $0.variant == variant }
    }
}

/// Trace buffer layout shared with B2Shared.h (`B2TraceHeader` 32 B, `B2TraceTap` 64 B). One block per traced pass:
/// header followed by `capacity` taps. The pipeline sets each block's probe to the pixel that pass computes for the probe.
public enum TraceLayout {
    public struct Header: Sendable {
        public var probe: SIMD2<UInt32>
        public var tapCount: UInt32
        public var passIndex: UInt32
        public var capacity: UInt32
        public var overflow: UInt32
        public var reserved: SIMD2<UInt32>
        public init(probe: SIMD2<UInt32>, tapCount: UInt32, passIndex: UInt32, capacity: UInt32, overflow: UInt32, reserved: SIMD2<UInt32>) {
            self.probe = probe; self.tapCount = tapCount; self.passIndex = passIndex; self.capacity = capacity
            self.overflow = overflow; self.reserved = reserved
        }
    }
    public struct Tap: Sendable {
        /// Sample position in source texel coordinates (centres at i + 0.5).
        public var position: SIMD2<Float>
        public var weight: Float
        /// 1 when the tap was dropped by `renormalise`.
        public var flags: Float
        public var fetched: SIMD4<Float>
        public var runningSum: SIMD4<Float>
        /// Class-specific: spatial weight, range weight, sector variance, rank … (documented per pipeline).
        public var extra: SIMD4<Float>
    }
    public static let headerStride = 32
    public static let tapStride = 64
    public static func passStride(capacity: Int) -> Int { headerStride + tapStride * capacity }

    /// Decodes one block per traced pass from a completed shared buffer.
    public static func decode(_ buffer: any MTLBuffer, passes: Int, capacity: Int) -> [(header: Header, taps: [Tap])] {
        (0..<passes).map { pass in
            let base = buffer.contents().advanced(by: pass * passStride(capacity: capacity))
            let header = base.bindMemory(to: Header.self, capacity: 1).pointee
            let count = Int(Swift.min(header.tapCount, UInt32(capacity)))
            let taps = base.advanced(by: headerStride).bindMemory(to: Tap.self, capacity: capacity)
            return (header, Array(UnsafeBufferPointer(start: taps, count: count)))
        }
    }
}
