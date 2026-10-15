import Foundation
import Metal
import BlurCore

// FROZEN API — ARCHITECTURE.md §3.2, §7. Runs one ParityCase exactly as the app renders (same encode path, colour
// pre/post passes, half-rounded input) and compares with BlurReference. Used by blur-gpucheck (all cases) and by the
// app's PARITY telemetry (a 128 × 128 crop). Implementation by SKEL; GPUCHECK extends reporting, not semantics.

public struct TracedComparison: Sendable, Hashable, Codable {
    /// Output words (fp16 channels) that differ between the traced and the untraced specialization.
    public var differingWords: Int
    /// The last traced pass's final record (flags = 2), rounded to fp16, equals the output at the probe (every channel).
    /// Compared only when that block did not overflow (review fix E-13).
    public var finalSumMatchesOutput: Bool
    public var tapsPerTracedPass: [Int]
    public var overflow: Int
    /// Set when a traced pass wrote no flags = 2 record.
    public var missingFinalRecord: Bool
    public var passed: Bool { differingWords == 0 && finalSumMatchesOutput && overflow == 0 && !missingFinalRecord }
}

public struct ParityOutcome: Sendable, Codable {
    public var caseName: String
    public var evaluation: ParityEvaluation?
    public var traced: TracedComparison?
    /// Mac/phone GPU time of the untraced command buffer (MEASURED, informational; never from the Simulator).
    public var gpuMilliseconds: Double?
    /// What was compared: "full 256 × 256" or "3 crops of 128 × 128 at the probes".
    public var comparedRegions: String?
    public var failure: String?
    public var passed: Bool { failure == nil && (evaluation?.passed ?? false) && (traced?.passed ?? true) }
}

/// Which pixels the CPU reference computes (review fix E-8): the whole window at small sizes, 128 × 128 crops around
/// the case's probes (or the centre) at full size.
public enum ParityRegionPolicy: Sendable, Hashable {
    case fullWindow
    case crops(side: Int)
    public static func standard(windowSize: Int) -> ParityRegionPolicy { windowSize <= 256 ? .fullWindow : .crops(side: 128) }
}

@MainActor
public enum ParityRunner {
    /// Compiles `B2Shared.h` + every `*.metal` in `directory` as ONE translation unit (ShaderManifest.assemble).
    public static func compileLibrary(device: any MTLDevice, shaderDirectory directory: URL, safeMath: Bool = false) throws
        -> (library: any MTLLibrary, manifest: ShaderManifest, source: String) {
        let header = try String(contentsOf: directory.appendingPathComponent("B2Shared.h"), encoding: .utf8)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".metal") }
        var files: [(name: String, text: String)] = []
        for name in names {
            let text = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            if !text.contains("SwiftUI/SwiftUI.h") { files.append((name, text)) }
        }
        let source = ShaderManifest.assemble(header: header, files: files)
        let options = MTLCompileOptions()
        options.mathMode = safeMath ? .safe : .fast
        options.mathFloatingPointFunctions = safeMath ? .precise : .fast
        options.languageVersion = .version4_1
        let library = try device.makeLibrary(source: source, options: options)
        return (library, ShaderManifest.make(header: header, files: files), source)
    }

    /// The GPU half runs on the main actor; canvas generation, fp16 conversion and the CPU reference run in detached
    /// tasks on Sendable values (review fix E-8). `referenceOptions` is `.parity` on the Mac and
    /// `ReferenceOptions.forDevice(probes)` in the app.
    public static func run(_ parityCase: ParityCase, factory: GPUPipelineFactory, context: GPUContext,
                           text: TextCoverage? = nil, regions: ParityRegionPolicy? = nil,
                           referenceOptions: ReferenceOptions = .parity) async -> ParityOutcome {
        var outcome = ParityOutcome(caseName: parityCase.name, evaluation: nil, traced: nil, gpuMilliseconds: nil,
                                    comparedRegions: nil, failure: nil)
        let config = parityCase.configuration
        guard let op = BlurRegistry.op(config.blur) else { outcome.failure = "no operator \(config.blur)"; return outcome }
        guard let generator = SpecimenRegistry.generator(config.specimen) else { outcome.failure = "no specimen \(config.specimen)"; return outcome }
        var spare: [(any MTLTexture, TextureSpec)] = []
        defer { for (t, spec) in spare { context.recycle(t, spec: spec) } }
        do {
            let canvasOptions = config.specimenOptions.canvasOptions, pan = config.pan, size = config.windowSize
            let window = await Task.detached(priority: .userInitiated) {
                generator.canvas(windowSize: size, margin: SpecimenGeometry.margin, options: canvasOptions, text: text).window(pan: pan)
            }.value
            let windowImage = window.image
            let half = await Task.detached(priority: .userInitiated) { HalfImageData(windowImage) }.value
            let request = config.operatorRequest
            let exposure = config.specimenOptions.exposureEV
            let pipeline = factory.make()
            try await context.prepareCommonPipelines()
            try await pipeline.prepare(context, request: request)
            let roles: TextureRole = pipeline.writesDestinationFromCompute ? [.read, .renderTarget, .computeWrite] : [.read, .renderTarget]
            let spec = TextureSpec(width: window.image.width, height: window.image.height, roles: roles)
            let inputSpec = TextureSpec(width: window.image.width, height: window.image.height, roles: [.read, .renderTarget])
            let uploaded = try await context.upload(half, roles: [.read, .renderTarget])
            spare.append((uploaded, inputSpec))
            let full = PixelRegion(origin: .zero, size: window.image.size)

            // The window pass (× 2^EV at render time), then the blur, exactly as the app encodes it.
            func encodeWindow(_ recorder: GPUCommandRecorder) throws -> any MTLTexture {
                guard exposure != 0 else { return uploaded }
                let exposed = try context.texture(inputSpec)
                spare.append((exposed, inputSpec))
                try context.encodeWindowCopy(canvas: uploaded, margin: 0, pan: .zero, size: size, exposureEV: exposure,
                                             destination: exposed, recorder: recorder)
                return exposed
            }
            let plain = try context.texture(spec)
            spare.append((plain, spec))
            let recorder = GPUCommandRecorder(context: context, label: parityCase.name)
            let source = try encodeWindow(recorder)
            let encoded = try context.encodeFullBlur(pipeline, window: source, output: plain, request: request, trace: nil, recorder: recorder)
            let completions = await recorder.commitAndWait()
            context.recycle(encoded)
            if let error = completions.compactMap(\.error).first { outcome.failure = error; return outcome }
            outcome.gpuMilliseconds = completions.reduce(0) { $0 + $1.milliseconds }
            let gpu = ImageBuffer(width: full.size.width, height: full.size.height, pixels: try await context.readTexels(plain, region: full))

            // Regions, CPU reference (detached) and the local scale of §7 rule 1.
            let policy = regions ?? .standard(windowSize: size)
            let compared: [PixelRegion]
            switch policy {
            case .fullWindow: compared = [full]
            case .crops(let side):
                let centres = parityCase.probes.isEmpty ? [config.probe] : parityCase.probes
                compared = centres.map { PixelRegion.centred(on: $0, side: side, inside: window.image.size) }
            }
            outcome.comparedRegions = policy == .fullWindow ? "full \(size) × \(size)"
                : "\(compared.count) crop(s) of \(compared.first?.size.width ?? 0)² at the probes"
            let auxiliary = window.auxiliary
            let plan = op.passPlan(request)
            let edge = request.settings.edgeMode
            let cpuParts: [ImageBuffer] = try await Task.detached(priority: .userInitiated) {
                if policy == .fullWindow {
                    return [try BlurReference.run(op, input: windowImage, request, auxiliary: auxiliary, options: referenceOptions,
                                                  exposureEV: exposure).output]
                }
                return try compared.map {
                    try BlurReference.runCrop(op, input: windowImage, request, region: $0, auxiliary: auxiliary,
                                              options: referenceOptions, exposureEV: exposure)
                }
            }.value
            let scales: [Float]? = await Task.detached(priority: .userInitiated) { () -> [Float]? in
                guard let radius = plan.supportRadius, edge != .wrap else { return nil }
                let exposed = exposure == 0 ? windowImage.roundedToHalf()
                    : windowImage.roundedToHalf().scaled(by: Float(pow(2.0, Double(exposure)))).roundedToHalf()
                return ParityEvaluation.localScale(exposed, radius: radius)
            }.value
            let globalScale = Double(window.image.pixels.reduce(Float(1)) { Swift.max($0, $1.max()) }) * pow(2.0, Double(exposure))
            // Stack the compared regions into one image for a single evaluation.
            func stack(_ parts: [ImageBuffer]) -> ImageBuffer {
                ImageBuffer(width: parts[0].width, height: parts.reduce(0) { $0 + $1.height }, pixels: parts.flatMap(\.pixels))
            }
            let gpuParts = compared.map { gpu.crop($0) }
            var localParts: [Float]?
            if let scales {
                localParts = compared.flatMap { r in
                    (r.origin.y..<(r.origin.y + r.size.height)).flatMap { y in
                        (r.origin.x..<(r.origin.x + r.size.width)).map { x in scales[y * window.image.width + x] }
                    }
                }
            }
            outcome.evaluation = ParityEvaluation.evaluate(gpu: stack(gpuParts), cpu: stack(cpuParts),
                                                           tolerance: parityCase.tolerance.adjusted(for: request.settings),
                                                           inputScale: globalScale, localScale: localParts,
                                                           bilinearPasses: parityCase.bilinearPasses,
                                                           domain: request.settings.colourSpace == .srgbEncoded ? .encoded : .linear)

            if parityCase.checkTraced {
                var comparison = TracedComparison(differingWords: 0, finalSumMatchesOutput: true, tapsPerTracedPass: [], overflow: 0,
                                                  missingFinalRecord: false)
                for probe in parityCase.probes {
                    let traced = try context.texture(spec)
                    spare.append((traced, spec))
                    let tracedRecorder = GPUCommandRecorder(context: context, label: parityCase.name + " traced")
                    let tracedSource = try encodeWindow(tracedRecorder)
                    let traceRequest = TraceRequest.sized(probe: probe, plan: plan)
                    let encoded = try context.encodeFullBlur(pipeline, window: tracedSource, output: traced, request: request,
                                                             trace: traceRequest, recorder: tracedRecorder)
                    _ = await tracedRecorder.commitAndWait()
                    context.recycle(encoded)
                    let tracedPixels = try await context.readTexels(traced, region: full)
                    comparison.differingWords += zip(tracedPixels, gpu.pixels).reduce(0) { acc, pair in
                        acc + (0..<4).filter { pair.0[$0].bitPattern != pair.1[$0].bitPattern }.count
                    }
                    guard let buffer = encoded.traceBuffer else { comparison.missingFinalRecord = true; continue }
                    let blocks = TraceLayout.decode(buffer, passes: encoded.tracedPassIndices.count, capacity: encoded.traceCapacity)
                    comparison.tapsPerTracedPass = blocks.map { $0.taps.count }
                    comparison.overflow += blocks.reduce(0) { $0 + Int($1.header.overflow) }
                    if blocks.contains(where: { block in !block.taps.contains { $0.flags == 2 } && block.header.overflow == 0 }) {
                        comparison.missingFinalRecord = true
                    }
                    if let last = blocks.last, last.header.overflow == 0, let final = last.taps.last(where: { $0.flags == 2 }),
                       !ColourTransform.needsPasses(request.settings) {
                        let out = gpu[probe.x, probe.y]
                        let matches = (0..<4).allSatisfy { HalfFloat.round(final.runningSum[$0]).bitPattern == out[$0].bitPattern }
                        comparison.finalSumMatchesOutput = comparison.finalSumMatchesOutput && matches
                    }
                }
                outcome.traced = comparison
            }
        } catch {
            outcome.failure = String(describing: error)
        }
        return outcome
    }
}
