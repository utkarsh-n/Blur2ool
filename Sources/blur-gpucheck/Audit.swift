import Foundation
import Metal
import BlurCore
import BlurGPU

// OWNER: GPUCHECK. The runtime half of the dispatch audit (ARCHITECTURE §3.2 item 4, §4.4 rule 1). Every registered
// pipeline runs inside `GPUCheckAuditedPipeline`, a pass-through wrapper (same blur, variant, functions, prepare and
// encode; it changes nothing the GPU does) that looks at what ONE `encode` call put into the recorder and the context:
// the compute encoders it opened (`GPUCommandRecorder.encodeLog`) and the dispatches it made through
// `GPUContext.dispatch2D` (`dispatchCount`, and `dispatchLog` because the CLI builds its context with
// `recordsDispatches: true`). A compute pass without a dispatch2D call bypassed the safe-dispatch path.

@MainActor
final class GPUCheckEncodeAudit {
    struct Encode {
        var traced: Bool
        /// Compute encoders the pipeline opened through the recorder: (plan pass index, label).
        var computePasses: [(pass: Int, label: String)]
        var renderPasses: Int
        var blitPasses: Int
        /// dispatch2D calls made during this encode.
        var dispatches: Int
        /// The dispatch2D log lines ("<label> tg=WxH groups=GxH tgmem=N").
        var dispatchLines: [String]
        var threw: String?
    }
    private(set) var encodes: [Encode] = []
    func record(_ e: Encode) { encodes.append(e) }

    struct Verdict {
        var computePasses = 0
        var dispatches = 0
        var encodes = 0
        var problems: [String] = []
        var lastDispatch: String?
        var passed: Bool { problems.isEmpty }
        var summary: String {
            guard computePasses > 0 || dispatches > 0 else { return "" }
            var s = "dispatch2D \(dispatches)/\(computePasses) compute passes over \(encodes) encode\(encodes == 1 ? "" : "s")"
            if let lastDispatch { s += " (\(lastDispatch))" }
            return s
        }
    }

    /// Every compute pass of every encode must have gone through dispatch2D, and (with the Apple2 limits forced, or
    /// always against the context's facts) every logged dispatch must fit the threadgroup limits.
    func verdict(facts: GPUFacts) -> Verdict {
        var v = Verdict()
        for (i, e) in encodes.enumerated() {
            v.encodes += 1
            v.computePasses += e.computePasses.count
            v.dispatches += e.dispatches
            let which = "encode \(i + 1)\(e.traced ? " (traced)" : "")"
            if e.dispatches < e.computePasses.count {
                v.problems.append("\(which): \(e.computePasses.count) compute pass(es) [\(e.computePasses.map(\.label).joined(separator: ", "))] but only \(e.dispatches) dispatch2D call(s): a compute pass bypassed GPUContext.dispatch2D")
            }
            if e.computePasses.isEmpty && e.dispatches > 0 {
                v.problems.append("\(which): \(e.dispatches) dispatch2D call(s) on compute encoder(s) the recorder did not open (encoders must come from GPUCommandRecorder.computeEncoder)")
            }
            for line in e.dispatchLines {
                if let tg = Self.field(line, "tg="), let (w, h) = Self.pair(tg), w * h > facts.maxThreadsPerThreadgroup {
                    v.problems.append("\(which): \(line): \(w * h) threads per threadgroup > \(facts.maxThreadsPerThreadgroup)")
                }
                if let mem = Self.field(line, "tgmem=").flatMap(Int.init), mem > facts.maxThreadgroupMemoryLength {
                    v.problems.append("\(which): \(line): \(mem) B threadgroup memory > \(facts.maxThreadgroupMemoryLength) B")
                }
            }
            if let last = e.dispatchLines.last { v.lastDispatch = last }
        }
        return v
    }

    static func field(_ line: String, _ key: String) -> String? {
        guard let r = line.range(of: key) else { return nil }
        return String(line[r.upperBound...].prefix { !$0.isWhitespace })
    }
    static func pair(_ text: String) -> (Int, Int)? {
        let parts = text.split(separator: "x").compactMap { Int($0) }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }
}

@MainActor
final class GPUCheckAuditedPipeline: GPUBlurPipeline {
    let inner: any GPUBlurPipeline
    let audit: GPUCheckEncodeAudit
    init(inner: any GPUBlurPipeline, audit: GPUCheckEncodeAudit) { self.inner = inner; self.audit = audit }

    var blur: BlurID { inner.blur }
    var variant: VariantID { inner.variant }
    var shaderFile: String { inner.shaderFile }
    var functionNames: [String] { inner.functionNames }
    var writesDestinationFromCompute: Bool { inner.writesDestinationFromCompute }

    func prepare(_ context: GPUContext, request: OperatorRequest) async throws {
        try await inner.prepare(context, request: request)
    }

    func encode(_ context: GPUContext, _ inputs: GPUBlurInputs, trace: TraceRequest?, recorder: GPUCommandRecorder) throws -> EncodedBlur {
        let logStart = recorder.encodeLog.count, countStart = context.dispatchCount, linesStart = context.dispatchLog.count
        func note(threw: String?) {
            let entries = recorder.encodeLog.dropFirst(logStart)
            audit.record(GPUCheckEncodeAudit.Encode(
                traced: trace != nil,
                computePasses: entries.filter { $0.kind == .compute }.map { ($0.pass, $0.label) },
                renderPasses: entries.filter { $0.kind == .render }.count,
                blitPasses: entries.filter { $0.kind == .blit }.count,
                dispatches: context.dispatchCount - countStart,
                dispatchLines: Array(context.dispatchLog.dropFirst(linesStart)), threw: threw))
        }
        do {
            let encoded = try inner.encode(context, inputs, trace: trace, recorder: recorder)
            note(threw: nil)
            return encoded
        } catch {
            note(threw: String(describing: error))
            throw error
        }
    }
}

extension GPUPipelineFactory {
    /// The same factory, with every pipeline it makes wrapped for the dispatch audit.
    func audited(_ audit: GPUCheckEncodeAudit) -> GPUPipelineFactory {
        let base = self
        return GPUPipelineFactory(blur: blur, variant: variant, make: { GPUCheckAuditedPipeline(inner: base.make(), audit: audit) },
                                  parityCases: parityCases)
    }
    var label: String { "\(blur)/\(variant)" }
}
