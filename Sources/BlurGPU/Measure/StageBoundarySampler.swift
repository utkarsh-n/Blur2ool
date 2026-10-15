import Foundation
import Metal
import BlurCore

// OWNER: GPU-MEASURE. Per-pass GPU time from stage-boundary counter samples (ARCHITECTURE §5.8 PassTimestampSampling;
// research gpu-pipeline §4.3 item 2). GPUCommandRecorder (`.stageBoundaryCounters`) calls `attach` for every pass
// descriptor it builds; after the command buffer completes, `resolve()` turns the timestamp counter set into per-pass
// milliseconds. Apple GPUs sample only at stage boundaries (MEASURED on the M1 Max: draw, dispatch, tile and blit
// boundaries are unsupported), so the timestamps are per encoder: one encoder per pass is what makes them per pass.

/// GPU timestamp ticks → nanoseconds, MEASURED at run time (research §4.3: "the conversion must be looked up at runtime,
/// never assumed"). Each reading pairs `MTLDevice.sampleTimestamps()` (CPU, GPU) with `DispatchTime` uptime
/// nanoseconds. The CPU value is used as the time base when it advances in nanoseconds (MEASURED on the M1 Max: it does,
/// and there the GPU ticks equal it exactly); otherwise uptime nanoseconds are. The first reading stays the baseline, so
/// the estimate sharpens the longer the process runs.
@MainActor
public final class MeasureGPUClock {
    private struct Reading { var cpu: Double; var gpu: Double; var uptime: Double }
    public let device: any MTLDevice
    private let first: Reading
    private var ratio: Double?
    /// True once the CPU timestamp has been seen to advance in nanoseconds (to 1 %).
    public private(set) var cpuTimestampIsNanoseconds: Bool?

    public init(device: any MTLDevice) {
        self.device = device
        first = MeasureGPUClock.read(device)
    }

    private static func read(_ device: any MTLDevice) -> Reading {
        let (cpu, gpu) = device.sampleTimestamps()
        return Reading(cpu: Double(cpu), gpu: Double(gpu), uptime: Double(DispatchTime.now().uptimeNanoseconds))
    }

    private static var clocks: [ObjectIdentifier: MeasureGPUClock] = [:]
    /// One clock per device for the process, so the baseline spans every measurement.
    public static func shared(_ device: any MTLDevice) -> MeasureGPUClock {
        let key = ObjectIdentifier(device as AnyObject)
        if let clock = clocks[key] { return clock }
        let clock = MeasureGPUClock(device: device)
        clocks[key] = clock
        return clock
    }

    /// GPU ticks per nanosecond, refreshed now when the baseline is at least 2 ms long; nil before any estimate exists.
    public func refresh() -> Double? {
        let now = MeasureGPUClock.read(device)
        let du = now.uptime - first.uptime, dc = now.cpu - first.cpu, dg = now.gpu - first.gpu
        guard du >= 2_000_000, dg > 0 else { return ratio }
        let cpuIsNs = abs(dc / du - 1) < 0.01
        cpuTimestampIsNanoseconds = cpuIsNs
        let r = dg / (cpuIsNs ? dc : du)
        if r.isFinite, r > 1e-4, r < 1e4 {
            // Exactly 1 when the GPU counts the CPU timestamp's nanoseconds (identical deltas on the M1 Max).
            ratio = cpuIsNs && abs(r - 1) < 1e-6 ? 1 : r
        }
        return ratio
    }

    /// The ratio, waiting (asynchronously, never blocking the main thread) until the baseline is long enough.
    public func calibrated() async -> Double {
        if let r = refresh() { return r }
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 1_000_000)
            if let r = refresh() { return r }
        }
        return refresh() ?? 1
    }

    /// The last estimate (refreshed); 1 only if no 2 ms baseline was ever available, which `calibrated()` prevents.
    public func ticksPerNanosecond() -> Double { refresh() ?? 1 }
}

/// The stage-boundary `PassTimestampSampling` (one per timing session; reset before every sampled command buffer).
@MainActor
public final class MeasureStageBoundarySampler: PassTimestampSampling {
    private enum Kind { case compute, render, blit }
    private struct Attachment { var pass: Int; var kind: Kind; var base: Int }

    public let sampleBuffer: any MTLCounterSampleBuffer
    public let capacity: Int
    /// The process-wide tick → nanosecond calibration for this device.
    public let clock: MeasureGPUClock
    private var attachments: [Attachment] = []
    private var used = 0
    /// Passes whose encoders could not be sampled (capacity exhausted): they get no time rather than a wrong one.
    public private(set) var droppedAttachments = 0

    /// nil when the device has no stage-boundary sampling or no timestamp counter set (the Simulator, Apple2 limits).
    public init?(device: any MTLDevice, passes: Int, label: String = "Blur2ool pass timestamps") {
        guard device.supportsCounterSampling(.atStageBoundary),
              let set = device.counterSets?.first(where: { $0.name == MTLCommonCounterSet.timestamp.rawValue }) else { return nil }
        // Four samples per encoder (render: vertex start/end, fragment start/end), room for two encoders per pass.
        // 32 KB per buffer at 8 B per sample (Feature Set Tables) caps this at 4,096 samples.
        let count = Swift.min(4_096, Swift.max(8, passes * 8))
        let descriptor = MTLCounterSampleBufferDescriptor()
        descriptor.counterSet = set
        descriptor.sampleCount = count
        descriptor.storageMode = .shared
        descriptor.label = label
        guard let buffer = try? device.makeCounterSampleBuffer(descriptor: descriptor) else { return nil }
        sampleBuffer = buffer; capacity = count; clock = MeasureGPUClock.shared(device)
    }

    /// Forget the previous command buffer's attachments (the same sample buffer is reused: at most 32 may exist).
    public func reset() { attachments.removeAll(keepingCapacity: true); used = 0; droppedAttachments = 0 }

    private func reserve(_ samples: Int) -> Int? {
        guard used + samples <= capacity else { droppedAttachments += 1; return nil }
        defer { used += samples }
        return used
    }

    public func attach(_ descriptor: MTLComputePassDescriptor, pass index: Int) {
        guard let base = reserve(2), let slot = descriptor.sampleBufferAttachments[0] else { return }
        slot.sampleBuffer = sampleBuffer
        slot.startOfEncoderSampleIndex = base
        slot.endOfEncoderSampleIndex = base + 1
        attachments.append(Attachment(pass: index, kind: .compute, base: base))
    }

    public func attach(_ descriptor: MTLRenderPassDescriptor, pass index: Int) {
        guard let base = reserve(4), let slot = descriptor.sampleBufferAttachments[0] else { return }
        slot.sampleBuffer = sampleBuffer
        slot.startOfVertexSampleIndex = base
        slot.endOfVertexSampleIndex = base + 1
        slot.startOfFragmentSampleIndex = base + 2
        slot.endOfFragmentSampleIndex = base + 3
        attachments.append(Attachment(pass: index, kind: .render, base: base))
    }

    public func attach(_ descriptor: MTLBlitPassDescriptor, pass index: Int) {
        guard let base = reserve(2), let slot = descriptor.sampleBufferAttachments[0] else { return }
        slot.sampleBuffer = sampleBuffer
        slot.startOfEncoderSampleIndex = base
        slot.endOfEncoderSampleIndex = base + 1
        attachments.append(Attachment(pass: index, kind: .blit, base: base))
    }

    /// Raw timestamps of the last command buffer (nil entries are MTLCounterErrorValue).
    public func timestamps() -> [UInt64?]? {
        guard used > 0, let data = try? sampleBuffer.resolveCounterRange(0..<used) else { return nil }
        let count = Swift.min(used, data.count / MemoryLayout<MTLCounterResultTimestamp>.stride)
        return data.withUnsafeBytes { raw -> [UInt64?] in
            let results = raw.bindMemory(to: MTLCounterResultTimestamp.self)
            return (0..<count).map { results[$0].timestamp == MTLCounterErrorValue || results[$0].timestamp == 0 ? nil : results[$0].timestamp }
        }
    }

    /// Per-pass milliseconds of the last command buffer. Compute and blit passes: encoder end − start. Render passes:
    /// the fragment stage (the blur's work; the full-screen triangle's vertex stage may run early, overlapping the
    /// previous pass on a TBDR GPU, research §4.3), falling back to vertex start → fragment end. Several encoders with
    /// one pass index add up. nil when no pass produced a valid pair.
    public func resolve() -> [Int: Double]? {
        guard let stamps = timestamps() else { return nil }
        let nsPerTick = 1 / clock.ticksPerNanosecond()
        func span(_ a: Int, _ b: Int) -> Double? {
            guard stamps.indices.contains(a), stamps.indices.contains(b), let s = stamps[a], let e = stamps[b], e >= s else { return nil }
            return Double(e - s) * nsPerTick / 1e6
        }
        var out: [Int: Double] = [:]
        for a in attachments {
            let ms: Double?
            switch a.kind {
            case .compute, .blit: ms = span(a.base, a.base + 1)
            case .render: ms = span(a.base + 2, a.base + 3) ?? span(a.base, a.base + 3)
            }
            if let ms { out[a.pass, default: 0] += ms }
        }
        return out.isEmpty ? nil : out
    }

    /// The passes that were attached in the last command buffer (in attach order, duplicates removed).
    public var attachedPasses: [Int] {
        var seen = Set<Int>()
        return attachments.map(\.pass).filter { seen.insert($0).inserted }
    }
}
