import Foundation
import Metal
import BlurCore
import BlurGPU

// OWNER: GPUCHECK. Mutation cases (ARCHITECTURE §3.2 item 5, §7 rule 9; review fix E-5). For every judged tolerance class
// a factory publishes, test-only factories wrap the REAL pipeline with one deliberate defect and run it through the
// frozen ParityRunner (same encode path, same CPU reference, same evaluator), on Night City at +4 EV and on step edges.
// Each mutation must FAIL; a mutation that passes is a gate failure: the class is too loose there.
//
// The three defects, all applied on the GPU to the real pipeline's work (the CPU reference is never touched):
//   σ × 1.01      the pipeline receives the request with its primary size parameter × 1.01 (wrong weights everywhere);
//                 integer parameters that round back to themselves move by one, and the report says so.
//   dropped tap   the last pass loses the tap with the smallest weight (for radius-truncated kernels this is the last tap;
//                 for fixed-tap kernels the plan's smallest-weight tap): out' = out − w · fetch(input of the last pass,
//                 p + offset), with the pipeline's own edge mapping and, for fractional offsets, the same hardware
//                 bilinear sampler. The tap comes from the tables the GPU actually received (EncodedBlur.uploadedWeights
//                 and uploadedOffsets, interpreted along the last pass's axis) or, failing that, from the operator's CPU
//                 trace reconstruction of the last pass. Exact for a linear FIR last pass; for adaptive and selection
//                 kernels it is a defect of the same size, labelled as such.
//   skipped pass  the last pass is replaced by an identity copy of its input (a one-pass blur outputs its input).
// Each mutation runs after an unmutated CONTROL of the same configuration; when the control itself fails, the mutations
// of that configuration cannot be judged and are reported as CONTROL FAILED, never as caught.

enum GPUCheckMutationKind: String, CaseIterable, Sendable {
    case sigma, droppedTap, skippedPass
    var label: String {
        switch self {
        case .sigma: "σ × 1.01"
        case .droppedTap: "dropped tap"
        case .skippedPass: "skipped pass"
        }
    }
}

struct GPUCheckMutationSpecimen: Sendable, Hashable {
    var id: SpecimenID
    var options: SpecimenOptions
    var label: String
    var addBrightestProbe: Bool
    /// Night City at +4 EV (HDR point lights up to 16,000 over dark buildings) and step edges at 45° (an axis-aligned
    /// pass of a separable kernel leaves the vertical step unchanged by symmetry, so a defect in it would be invisible to
    /// ANY tolerance; at 45° every axis-aligned pass crosses the edge).
    static let all = [
        GPUCheckMutationSpecimen(id: "night-city", options: SpecimenOptions(exposureEV: 4), label: "Night City +4 EV", addBrightestProbe: true),
        GPUCheckMutationSpecimen(id: "step-edges", options: SpecimenOptions(choices: ["orientation": "45"]), label: "step edges 45°",
                                 addBrightestProbe: false),
    ]
}

/// A tap to drop: offset from the output pixel's centre in the last pass's input texels, and its weight.
struct GPUCheckTap: Sendable, Hashable {
    var offset: SIMD2<Double>
    var weight: Double
    var source: String
    var isInteger: Bool { offset.x == offset.x.rounded() && offset.y == offset.y.rounded() }
    var label: String {
        func f(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.3f", v) }
        return "offset (\(f(offset.x)), \(f(offset.y))) · w \(String(format: "%.3e", weight)) · \(source)"
    }
}

enum GPUCheckTaps {
    /// The smallest-weight tap (|w| > 0); ties go to the LAST tap in kernel order.
    static func smallest(_ taps: [(offset: SIMD2<Double>, weight: Double)]) -> (offset: SIMD2<Double>, weight: Double)? {
        var best: (offset: SIMD2<Double>, weight: Double)?
        for t in taps where abs(t.weight) > 0 {
            if let b = best, abs(t.weight) > abs(b.weight) * (1 + 1e-6) { continue }
            best = t
        }
        return best
    }

    /// Interprets the uploaded tables as a 1-D kernel along `axis`: a Rákos pair table (offsets[0] = 0; tap order centre,
    /// +o₁, −o₁, +o₂, … as KernelMath.linearSampledTable) or an odd integer table (taps −r … +r).
    static func fromTables(weights: [Float]?, offsets: [Float]?, axis: SIMD2<Double>?) -> GPUCheckTap? {
        guard let axis, let weights, !weights.isEmpty else { return nil }
        var taps: [(offset: SIMD2<Double>, weight: Double)] = []
        if let offsets, !offsets.isEmpty {
            guard offsets.count == weights.count, offsets[0] == 0 else { return nil }
            taps.append((.zero, Double(weights[0])))
            for i in 1..<weights.count {
                taps.append((axis * Double(offsets[i]), Double(weights[i])))
                taps.append((axis * -Double(offsets[i]), Double(weights[i])))
            }
            guard let t = smallest(taps) else { return nil }
            return GPUCheckTap(offset: t.offset, weight: t.weight, source: "pair table of \(weights.count) uploaded weights")
        }
        guard weights.count >= 3, weights.count % 2 == 1 else { return nil }
        let r = weights.count / 2
        for k in 0..<weights.count { taps.append((axis * Double(k - r), Double(weights[k]))) }
        guard let t = smallest(taps) else { return nil }
        return GPUCheckTap(offset: t.offset, weight: t.weight, source: "table of \(weights.count) uploaded weights")
    }

    /// The axis of a pass from its tile name ("H", "V", "SCAN ROWS", "FFT COLUMNS"…), or nil.
    static func axis(ofPassNamed name: String?) -> SIMD2<Double>? {
        guard let raw = name?.uppercased() else { return nil }
        let words = raw.split { !$0.isLetter }.map(String.init)
        if words.contains("V") || raw.contains("VERT") || raw.contains("COLUMN") || words.contains("COLS") { return SIMD2(0, 1) }
        if words.contains("H") || raw.contains("HORIZ") || raw.contains("ROW") { return SIMD2(1, 0) }
        return nil
    }

    /// The operator's CPU trace reconstruction of the last pass, when it reconstructs every pass of the plan.
    static func fromTrace(_ record: TraceRecord, planPasses: Int) -> GPUCheckTap? {
        guard record.passes.count == planPasses, let last = record.passes.last else { return nil }
        let taps = last.taps.filter { !$0.dropped }.map { (offset: $0.offset, weight: $0.weight) }
        guard taps.count >= 2, let t = smallest(taps) else { return nil }
        return GPUCheckTap(offset: t.offset, weight: t.weight, source: "CPU trace reconstruction of pass \(last.id)")
    }
}

enum GPUCheckParameterScaling {
    /// The entry's primary size parameter (σ, radius, …) × `factor`, or the first size parameter after it. Integers
    /// that round back to themselves move by one step. nil when the entry has no size parameter.
    static func scaled(_ values: ParameterValues, entry: CatalogEntry, factor: Double) -> (values: ParameterValues, detail: String)? {
        let sizeUnits: Set<ParameterUnit> = [.px, .texels, .pixelsSquared, .pt, .cssPx]
        let blurSpecs = entry.parameters.filter { $0.scope == .blur }
        var ordered: [ParameterSpec] = []
        if let primary = entry.primarySpec, primary.scope == .blur { ordered.append(primary) }
        ordered += blurSpecs.filter { sizeUnits.contains($0.unit) && $0.key != entry.primary }
        ordered += blurSpecs.filter { spec in
            if case .continuous = spec.kind { return !ordered.contains { $0.key == spec.key } }
            return false
        }
        for spec in ordered {
            let current = values[spec.key] ?? spec.defaultValue
            var out = values
            switch current {
            case .double(let v) where v != 0:
                let n = v * factor
                out[spec.key] = .double(n)
                return (out, "\(spec.key) \(format(v)) → \(format(n))")
            case .int(let v):
                var n = Int((Double(v) * factor).rounded())
                var note = ""
                if n == v { n = v + (factor >= 1 ? 1 : -1); note = " (× \(format(factor)) rounds back to \(v): moved by one)" }
                out[spec.key] = .int(n)
                return (out, "\(spec.key) \(v) → \(n)\(note)")
            case .intList(let list) where !list.isEmpty:
                var moved = list.map { Int((Double($0) * factor).rounded()) }
                if moved == list, let i = list.indices.last { moved[i] = list[i] + 1 }
                out[spec.key] = .intList(moved)
                return (out, "\(spec.key) \(list) → \(moved)")
            default:
                continue
            }
        }
        return nil
    }

    static func format(_ v: Double) -> String {
        if v == v.rounded() && abs(v) < 1e6 { return String(Int(v)) }
        return String(format: "%.4g", v)
    }
}

/// Test-only Metal: the dropped-tap pass. Compiled at runtime from B2Shared.h + this text into a library of its own;
/// never part of App/GPU/Shaders, the app or the combined SHA.
@MainActor
final class GPUCheckMutationKit {
    static let source = """
    // blur-gpucheck mutation kernels (test-only, ARCHITECTURE §3.2 item 5). Never compiled into the app.
    struct GPUCheckDropTapParams { float2 offset; float weight; uint edge; uint integerTap; uint pad0; uint pad1; uint pad2; };
    vertex B2VertexOut gpucheck_fullscreen_vs(uint vid [[vertex_id]]) {
        float2 uv = float2(float((vid << 1) & 2), float(vid & 2));
        B2VertexOut out;
        out.position = float4(uv * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);
        out.uv = uv;
        return out;
    }
    // out' = out − w · fetch(previous, p + offset): the contribution the last pass would have lost without that tap.
    fragment float4 gpucheck_drop_tap_fs(B2VertexOut in [[stage_in]],
                                         texture2d<float, access::sample> current [[texture(0)]],
                                         texture2d<float, access::sample> previous [[texture(1)]],
                                         constant GPUCheckDropTapParams &P [[buffer(0)]]) {
        uint2 pixel = uint2(in.position.xy);
        float4 tap = P.integerTap != 0u ? b2_fetch(previous, int2(pixel) + int2(rint(P.offset)), P.edge)
                                        : b2_sample(previous, float2(pixel) + 0.5f + P.offset, P.edge);
        return fma(-float4(P.weight), tap, current.read(pixel));
    }
    """

    struct DropTapParams {
        var offset: SIMD2<Float>
        var weight: Float
        var edge: UInt32
        var integerTap: UInt32
        var pad0: UInt32 = 0, pad1: UInt32 = 0, pad2: UInt32 = 0
    }

    let dropTap: any MTLRenderPipelineState

    init(device: any MTLDevice, header: String) throws {
        let options = MTLCompileOptions()
        options.mathMode = .fast
        options.mathFloatingPointFunctions = .fast
        options.languageVersion = .version4_1
        let library: any MTLLibrary
        do { library = try device.makeLibrary(source: header + "\n" + Self.source, options: options) }
        catch { throw GPUCheckSetupError.compile("mutation kernels: \(error)") }
        guard let vs = library.makeFunction(name: "gpucheck_fullscreen_vs"), let fs = library.makeFunction(name: "gpucheck_drop_tap_fs") else {
            throw GPUCheckSetupError.compile("mutation kernels: functions missing")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vs
        descriptor.fragmentFunction = fs
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        dropTap = try device.makeRenderPipelineState(descriptor: descriptor)
    }
}

struct GPUCheckNotApplicable: Error, CustomStringConvertible {
    static let marker = "MUTATION-N/A: "
    let reason: String
    var description: String { Self.marker + reason }
}

/// A real pipeline with one deliberate defect (test-only).
@MainActor
final class GPUCheckMutantPipeline: GPUBlurPipeline {
    enum Defect {
        /// The GPU runs these parameters (σ × 1.01; or, for the canary, the original parameters under a wrong reference).
        case parameters(ParameterValues)
        case droppedTap(axis: SIMD2<Double>?, fallback: GPUCheckTap?)
        case skippedPass
    }

    let inner: any GPUBlurPipeline
    let defect: Defect
    let kit: GPUCheckMutationKit?
    /// What was actually done, for the report ("dropped offset (0, −11.333) · w 3.4e-03 · pair table …").
    private(set) var applied: String?

    init(inner: any GPUBlurPipeline, defect: Defect, kit: GPUCheckMutationKit?) {
        self.inner = inner; self.defect = defect; self.kit = kit
    }

    var blur: BlurID { inner.blur }
    var variant: VariantID { inner.variant }
    var shaderFile: String { inner.shaderFile }
    var functionNames: [String] { inner.functionNames }
    var writesDestinationFromCompute: Bool { inner.writesDestinationFromCompute }

    func prepare(_ context: GPUContext, request: OperatorRequest) async throws {
        var r = request
        if case .parameters(let p) = defect { r.parameters = p }
        try await inner.prepare(context, request: r)
    }

    func encode(_ context: GPUContext, _ inputs: GPUBlurInputs, trace: TraceRequest?, recorder: GPUCommandRecorder) throws -> EncodedBlur {
        switch defect {
        case .parameters(let p):
            var mutated = inputs
            mutated.request.parameters = p
            applied = "GPU parameters replaced"
            return try inner.encode(context, mutated, trace: trace, recorder: recorder)
        case .skippedPass:
            let encoded = try inner.encode(context, inputs, trace: trace, recorder: recorder)
            let (previous, which) = try lastPassInput(encoded, inputs)
            let blit = try recorder.blitEncoder(pass: lastPassIndex(encoded), label: "MUTATION · skipped pass")
            blit.copy(from: previous, to: inputs.destination)
            blit.endEncoding()
            applied = "last pass (\(encoded.dispatch.last?.name ?? "pass \(lastPassIndex(encoded))")) replaced by an identity copy of \(which)"
            return encoded
        case .droppedTap(let axis, let fallback):
            guard let kit else { throw GPUCheckNotApplicable(reason: "no mutation kernels") }
            var encoded = try inner.encode(context, inputs, trace: trace, recorder: recorder)
            let destination = inputs.destination
            let (previous, which) = try lastPassInput(encoded, inputs)
            let passAxis = GPUCheckTaps.axis(ofPassNamed: encoded.dispatch.last?.name) ?? axis
            guard let tap = GPUCheckTaps.fromTables(weights: encoded.uploadedWeights, offsets: encoded.uploadedOffsets, axis: passAxis)
                    ?? fallback else {
                throw GPUCheckNotApplicable(reason: "no tap geometry for the last pass (uploaded tables are not a 1-D kernel along a known axis and the operator's CPU trace reconstruction does not cover every pass)")
            }
            guard destination.pixelFormat == .rgba16Float, destination.usage.contains(.renderTarget) else {
                throw GPUCheckNotApplicable(reason: "destination is not an rgba16Float render target")
            }
            let pass = lastPassIndex(encoded)
            let spec = TextureSpec(width: destination.width, height: destination.height, roles: [.read, .renderTarget])
            let current = try context.texture(spec)
            let blit = try recorder.blitEncoder(pass: pass, label: "MUTATION · keep the last pass's output")
            blit.copy(from: destination, to: current)
            blit.endEncoding()
            let source: any MTLTexture = (previous as AnyObject) === (destination as AnyObject) ? current : previous
            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = destination
            descriptor.colorAttachments[0].loadAction = .dontCare
            descriptor.colorAttachments[0].storeAction = .store
            let encoder = try recorder.renderEncoder(pass: pass, descriptor: descriptor, label: "MUTATION · dropped tap")
            encoder.setRenderPipelineState(kit.dropTap)
            encoder.setFragmentTexture(current, index: 0)
            encoder.setFragmentTexture(source, index: 1)
            let edge = inputs.request.settings.edgeMode
            var params = GPUCheckMutationKit.DropTapParams(offset: SIMD2(Float(tap.offset.x), Float(tap.offset.y)), weight: Float(tap.weight),
                                                           edge: edge == .renormalise ? EdgeMode.clamp.shaderIndex : edge.shaderIndex,
                                                           integerTap: tap.isInteger ? 1 : 0)
            encoder.setFragmentBytes(&params, length: MemoryLayout<GPUCheckMutationKit.DropTapParams>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            encoded.transientTextures.append((current, spec))
            applied = "dropped \(tap.label) from the last pass (input: \(which))"
            return encoded
        }
    }

    private func lastPassIndex(_ encoded: EncodedBlur) -> Int {
        Swift.max(0, encoded.dispatch.map(\.passIndex).max() ?? 0)
    }

    /// The input of the last pass: the previous pass's output, or the blur's input for a one-pass pipeline.
    private func lastPassInput(_ encoded: EncodedBlur, _ inputs: GPUBlurInputs) throws -> (any MTLTexture, String) {
        let destination = inputs.destination
        let previous: any MTLTexture
        let which: String
        if encoded.intermediates.count >= 2 {
            previous = encoded.intermediates[encoded.intermediates.count - 2]
            which = "pass \(encoded.intermediates.count - 2)'s output"
        } else {
            previous = inputs.source
            which = "the blur's input (one-pass pipeline)"
        }
        guard previous.width == destination.width, previous.height == destination.height, previous.pixelFormat == destination.pixelFormat else {
            throw GPUCheckNotApplicable(reason: "the last pass changes size or format (\(previous.width)×\(previous.height) → \(destination.width)×\(destination.height))")
        }
        return (previous, which)
    }
}

/// Lets the runner read what a mutant pipeline actually did after ParityRunner made and used it.
@MainActor
final class GPUCheckMutantBox {
    var pipeline: GPUCheckMutantPipeline?
}

/// One configuration the mutations of one (factory, size, class, specimen) run on.
struct GPUCheckMutationContext: Sendable {
    var factory: GPUPipelineFactory
    var size: Int
    var tolerance: ParityTolerance
    var bilinearPasses: Int
    var baseCase: String
    var specimen: GPUCheckMutationSpecimen
    var configuration: RenderConfiguration
    var probes: [PixelPoint]
    /// Primary size parameter × 1.01, or nil (σ × 1.01 not applicable).
    var sigmaMutation: (values: ParameterValues, detail: String)?
    var lastPassAxis: SIMD2<Double>?
    var traceTap: GPUCheckTap?
    var notes: [String]

    var prefix: String { "\(factory.label) @\(size): " }
    var controlName: String { prefix + "control · \(tolerance.name) · \(specimen.label) (from '\(baseCase)')" }
    func mutantName(_ kind: GPUCheckMutationKind) -> String { prefix + "mutation \(kind.label) · \(tolerance.name) · \(specimen.label)" }

    var controlCase: ParityCase {
        ParityCase(name: controlName, configuration: configuration, tolerance: tolerance, bilinearPasses: bilinearPasses,
                   checkTraced: false, probes: probes, note: "unmutated control for the mutation cases")
    }
    func mutantCase(_ kind: GPUCheckMutationKind) -> ParityCase {
        ParityCase(name: mutantName(kind), configuration: configuration, tolerance: tolerance, bilinearPasses: bilinearPasses,
                   checkTraced: false, probes: probes, note: "mutation \(kind.label): must FAIL")
    }
}

@MainActor
enum GPUCheckMutationPlanner {
    /// (factory, size, class) triples: every factory × every judged class it publishes (scope every), or the first
    /// factory per class (scope representative).
    static func targets(_ factories: [GPUPipelineFactory], sizes: [Int], scope: GPUCheckMutationScope)
        -> [(factory: GPUPipelineFactory, size: Int, base: ParityCase)] {
        var out: [(GPUPipelineFactory, Int, ParityCase)] = []
        var seenClass: Set<String> = []
        for factory in factories {
            for size in sizes {
                var seen: Set<String> = []
                for c in factory.parityCases(size) where !c.tolerance.reportOnly && !seen.contains(c.tolerance.name) {
                    seen.insert(c.tolerance.name)
                    if scope == .representative {
                        let key = "\(c.tolerance.name)@\(size)"
                        if seenClass.contains(key) { continue }
                        seenClass.insert(key)
                    }
                    out.append((factory, size, c))
                }
            }
        }
        return out
    }

    /// Names only (for --list), without generating images.
    static func names(_ factories: [GPUPipelineFactory], sizes: [Int], scope: GPUCheckMutationScope) -> [String] {
        targets(factories, sizes: sizes, scope: scope).flatMap { t in
            GPUCheckMutationSpecimen.all.flatMap { s in
                GPUCheckMutationKind.allCases.map { "\(t.factory.label) @\(t.size): mutation \($0.label) · \(t.base.tolerance.name) · \(s.label)" }
            }
        }
    }

    /// Builds the contexts: canvas (detached, cached per specimen and size), probes, σ × 1.01 parameters, the last pass's
    /// axis and the CPU-trace fallback tap.
    static func contexts(_ factories: [GPUPipelineFactory], sizes: [Int], scope: GPUCheckMutationScope,
                         include: (String) -> Bool) async -> [GPUCheckMutationContext] {
        var cache: [String: (window: ImageBuffer, probe: PixelPoint, auxiliary: AuxiliaryInputs)] = [:]
        var out: [GPUCheckMutationContext] = []
        for target in targets(factories, sizes: sizes, scope: scope) {
            for specimen in GPUCheckMutationSpecimen.all {
                let names = GPUCheckMutationKind.allCases.map {
                    "\(target.factory.label) @\(target.size): mutation \($0.label) · \(target.base.tolerance.name) · \(specimen.label)"
                }
                guard names.contains(where: include) else { continue }
                var notes: [String] = []
                guard let generator = SpecimenRegistry.generator(specimen.id) else {
                    notes.append("specimen \(specimen.id) is not registered")
                    continue
                }
                let key = "\(specimen.id)|\(specimen.options.choices)|\(target.size)"
                if cache[key] == nil {
                    let size = target.size, options = specimen.options.canvasOptions
                    cache[key] = await Task.detached(priority: .userInitiated) {
                        let canvas = generator.canvas(windowSize: size, margin: SpecimenGeometry.margin, options: options, text: nil)
                        let window = canvas.window(pan: .zero)
                        return (window.image, canvas.defaultProbe, window.auxiliary)
                    }.value
                }
                guard let image = cache[key] else { continue }
                var probes = [image.probe]
                if specimen.addBrightestProbe {
                    let w = image.window.width
                    var best = 0, bestValue: Float = -.infinity
                    for (i, p) in image.window.pixels.enumerated() where p.max() > bestValue { bestValue = p.max(); best = i }
                    let bright = PixelPoint(x: best % w, y: best / w)
                    if Swift.max(abs(bright.x - image.probe.x), abs(bright.y - image.probe.y)) > 32 { probes.append(bright) }
                }
                var configuration = target.base.configuration
                configuration.specimen = specimen.id
                configuration.specimenOptions = specimen.options
                configuration.pan = .zero
                configuration.probe = image.probe
                configuration.windowSize = target.size
                let request = configuration.operatorRequest
                var sigma: (values: ParameterValues, detail: String)?
                var axis: SIMD2<Double>?
                var traceTap: GPUCheckTap?
                if let op = BlurRegistry.op(configuration.blur) {
                    sigma = GPUCheckParameterScaling.scaled(configuration.parameters, entry: op.entry, factor: 1.01)
                    let plan = op.passPlan(request)
                    axis = GPUCheckTaps.axis(ofPassNamed: plan.passes.last?.name)
                    let window = image.window, auxiliary = image.auxiliary, probe = image.probe, ev = specimen.options.exposureEV
                    traceTap = await Task.detached(priority: .userInitiated) { () -> GPUCheckTap? in
                        var input = window.roundedToHalf()
                        if ev != 0 { input = input.scaled(by: Float(pow(2.0, Double(ev)))).roundedToHalf() }
                        return GPUCheckTaps.fromTrace(op.traceReconstruction(probe: probe, input: input, request, auxiliary: auxiliary),
                                                      planPasses: plan.passes.count)
                    }.value
                } else {
                    notes.append("no operator \(configuration.blur)")
                }
                out.append(GPUCheckMutationContext(factory: target.factory, size: target.size, tolerance: target.base.tolerance,
                                                   bilinearPasses: target.base.bilinearPasses, baseCase: target.base.name,
                                                   specimen: specimen, configuration: configuration, probes: probes,
                                                   sigmaMutation: sigma, lastPassAxis: axis, traceTap: traceTap, notes: notes))
            }
        }
        return out
    }
}

/// The deliberately wrong reference of `--canary`: the GPU renders the case's own parameters while the CPU reference
/// (the ParityCase's configuration) has the primary parameter × 1.25. It must FAIL.
@MainActor
enum GPUCheckCanary {
    static func cases(_ factories: [GPUPipelineFactory], size: Int) -> (factory: GPUPipelineFactory, parityCase: ParityCase)? {
        let preferred = factories.filter { $0.blur == "gaussian-blur" && $0.variant == "gaussian-separable" } + factories
        for factory in preferred {
            guard let base = factory.parityCases(size).first(where: { !$0.tolerance.reportOnly }),
                  let op = BlurRegistry.op(base.configuration.blur),
                  let wrong = GPUCheckParameterScaling.scaled(base.configuration.parameters, entry: op.entry, factor: 1.25) else { continue }
            var configuration = base.configuration
            configuration.parameters = wrong.values
            let gpuParameters = base.configuration.parameters
            let canary = GPUPipelineFactory(blur: factory.blur, variant: factory.variant, make: {
                GPUCheckMutantPipeline(inner: factory.make(), defect: .parameters(gpuParameters), kit: nil)
            }, parityCases: { _ in [] })
            let parityCase = ParityCase(name: "canary · deliberately wrong CPU reference (reference \(wrong.detail); the GPU renders the original) · from '\(base.name)'",
                                        configuration: configuration, tolerance: base.tolerance, bilinearPasses: base.bilinearPasses,
                                        checkTraced: false, probes: base.probes, note: "must FAIL: proves the gate can fail")
            return (canary, parityCase)
        }
        return nil
    }
}
