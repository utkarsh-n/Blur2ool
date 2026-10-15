import Foundation
import Metal
import BlurCore

// FROZEN — ARCHITECTURE.md §5.8. Pipelines never call `commandBuffer.make…Encoder` themselves: they ask the recorder for
// ONE encoder per pass. The recorder decides how passes map to command buffers (display: one buffer; per-pass timing:
// one buffer per pass) and lets GPU-MEASURE attach stage-boundary counter samples, without pipeline changes.

public enum PassIsolation: String, Sendable, Hashable {
    /// Display renders and parity: every pass in one command buffer (one encoder per pass).
    case singleCommandBuffer
    /// Per-pass timing without counters: one command buffer per pass, committed in order on one queue.
    case commandBufferPerPass
    /// Per-pass timing with `supportsCounterSampling(.atStageBoundary)`: one buffer, sampler attached to every pass.
    case stageBoundaryCounters
}

/// Attaches counter sample buffers to pass descriptors and resolves per-pass GPU ms. Implemented by GPU-MEASURE.
@MainActor
public protocol PassTimestampSampling: AnyObject {
    func attach(_ descriptor: MTLComputePassDescriptor, pass index: Int)
    func attach(_ descriptor: MTLRenderPassDescriptor, pass index: Int)
    func attach(_ descriptor: MTLBlitPassDescriptor, pass index: Int)
    /// Per-pass milliseconds after completion (nil when the device returned no valid samples).
    func resolve() -> [Int: Double]?
}

@MainActor
public final class GPUCommandRecorder {
    /// Pass indices below 0 are untimed preamble/postamble work (window copy, colour pre/post passes).
    public static let prePass = -2
    public static let postPass = -1

    public let context: GPUContext
    public let isolation: PassIsolation
    public let label: String
    public private(set) var commandBuffers: [any MTLCommandBuffer] = []
    /// (pass index, encoder kind, label) in encode order — blur-gpucheck asserts on it.
    public private(set) var encodeLog: [(pass: Int, kind: PassEncoderKind, label: String)] = []
    public var sampler: (any PassTimestampSampling)?

    public init(context: GPUContext, isolation: PassIsolation = .singleCommandBuffer, label: String,
                sampler: (any PassTimestampSampling)? = nil) {
        self.context = context; self.isolation = isolation; self.label = label; self.sampler = sampler
    }

    /// The command buffer for a pass: the single buffer, or, when isolating, a new one whenever the pass index changes.
    /// Negative indices get their own (untimed) buffers too, so the post-pass never inflates the last blur pass's
    /// time (review fix E-19).
    public func commandBuffer(forPass index: Int) throws -> any MTLCommandBuffer {
        if let current = commandBuffers.last, isolation != .commandBufferPerPass || currentPass == index {
            return current
        }
        guard let cb = context.queue.makeCommandBuffer() else { throw GPUError.encoderUnavailable("command buffer") }
        cb.label = "\(label) · pass \(index)"
        commandBuffers.append(cb)
        bufferPasses.append(index)
        currentPass = index
        return cb
    }
    private var currentPass: Int?
    /// The pass index each command buffer was created for (preamble buffers have negative indices).
    public private(set) var bufferPasses: [Int] = []

    public func computeEncoder(pass index: Int, label: String) throws -> any MTLComputeCommandEncoder {
        let cb = try commandBuffer(forPass: index)
        let descriptor = MTLComputePassDescriptor()
        if index >= 0, isolation == .stageBoundaryCounters { sampler?.attach(descriptor, pass: index) }
        guard let encoder = cb.makeComputeCommandEncoder(descriptor: descriptor) else { throw GPUError.encoderUnavailable(label) }
        encoder.label = label
        encodeLog.append((index, .compute, label))
        return encoder
    }

    public func renderEncoder(pass index: Int, descriptor: MTLRenderPassDescriptor, label: String) throws -> any MTLRenderCommandEncoder {
        let cb = try commandBuffer(forPass: index)
        if index >= 0, isolation == .stageBoundaryCounters { sampler?.attach(descriptor, pass: index) }
        guard let encoder = cb.makeRenderCommandEncoder(descriptor: descriptor) else { throw GPUError.encoderUnavailable(label) }
        encoder.label = label
        encodeLog.append((index, .render, label))
        return encoder
    }

    public func blitEncoder(pass index: Int, label: String) throws -> any MTLBlitCommandEncoder {
        let cb = try commandBuffer(forPass: index)
        let descriptor = MTLBlitPassDescriptor()
        if index >= 0, isolation == .stageBoundaryCounters { sampler?.attach(descriptor, pass: index) }
        guard let encoder = cb.makeBlitCommandEncoder(descriptor: descriptor) else { throw GPUError.encoderUnavailable(label) }
        encoder.label = label
        encodeLog.append((index, .blit, label))
        return encoder
    }

    /// Records a pass encoded by a framework (MPS, Core Image) into `commandBuffer(forPass:)`.
    public func noteExternalPass(_ index: Int, kind: PassEncoderKind, label: String) { encodeLog.append((index, kind, label)) }

    /// Commits every command buffer in order and awaits all completions (continuation + completion handler, §5.15).
    public func commitAndWait() async -> [GPUCompletion] {
        var results: [GPUCompletion] = []
        let buffers = commandBuffers
        for cb in buffers.dropLast() { cb.commit() }
        guard let last = buffers.last else { return [] }
        let tail = await context.commit(last)
        for cb in buffers.dropLast() {
            results.append(GPUCompletion(gpuStartTime: cb.gpuStartTime, gpuEndTime: cb.gpuEndTime,
                                         error: cb.error.map { String(describing: $0) }))
        }
        results.append(tail)
        return results
    }

    /// Per-pass GPU ms: from the sampler (stage-boundary counters) or from per-pass command buffers.
    public func passMilliseconds(_ completions: [GPUCompletion]) -> [Int: Double]? {
        switch isolation {
        case .stageBoundaryCounters: return sampler?.resolve()
        case .commandBufferPerPass:
            var out: [Int: Double] = [:]
            for (pass, c) in zip(bufferPasses, completions) where pass >= 0 { out[pass] = c.milliseconds }
            return out
        case .singleCommandBuffer: return nil
        }
    }
}
