import Foundation
import Metal
import BlurCore

// OWNER: FAM-F6 (seed written by SKEL, review fix E-15). Proves GPUCommandRecorder.renderEncoder with TWO colour
// attachments (polygonal bokeh's MRT pass 1, SPEC §5.3 D) and parity on both attachments before wave 1.
// It is not in GPUPipelineRegistry (polygonal-bokeh has no operator yet, and a seed must not appear in the catalog):
// blur-gpucheck and Tests/BlurGPUTests/SKELSeeds call `parityOutcomes` explicitly. FAM-F6 keeps this entry point until
// polygonal-bokeh's registered MRT pipeline publishes parity cases on both attachments; GPUCHECK then drops the call.
// TODO(FAM-F6): the real polygonal-bokeh pipelines (both line passes, blades, rotation; 2-D gather for odd blades).
@MainActor
public enum F6HexLineSeed {
    public static let functionName = "b2_f6_hexlines_mrt_fs"
    public static let label = "polygonal-bokeh/hexlines-mrt-seed"
    public static let formats: [TextureFormat] = [.rgba16Float, .rgba16Float]

    public static func prepare(_ context: GPUContext, edgeMode: EdgeMode) async throws {
        _ = try await context.renderPipeline(fragment: functionName, colorFormats: formats, constants: FunctionConstants(edgeMode: edgeMode))
    }

    /// One fragment pass, pass index 0, writing T1 to colour attachment 0 and T2 to attachment 1 (no .shaderWrite).
    @discardableResult
    public static func encode(_ context: GPUContext, source: any MTLTexture, t1: any MTLTexture, t2: any MTLTexture,
                              edgeMode: EdgeMode, recorder: GPUCommandRecorder) throws -> PassDispatch {
        let pso = try context.preparedRenderPipeline(fragment: functionName, colorFormats: formats,
                                                     constants: FunctionConstants(edgeMode: edgeMode))
        let descriptor = MTLRenderPassDescriptor()
        for (i, target) in [t1, t2].enumerated() {
            descriptor.colorAttachments[i].texture = target
            descriptor.colorAttachments[i].loadAction = .dontCare
            descriptor.colorAttachments[i].storeAction = .store
        }
        let encoder = try recorder.renderEncoder(pass: 0, descriptor: descriptor, label: "hex lines ↑ ↘ (2 attachments)")
        encoder.setRenderPipelineState(pso)
        encoder.setFragmentTexture(source, index: 0)
        var params: [UInt32] = [UInt32(F6HexLineSeedReference.taps), 0, 0, 0]
        encoder.setFragmentBytes(&params, length: 16, index: 0)
        let offsets = F6HexLineSeedReference.offsets().flatMap { [$0.x, $0.y] }
        encoder.setFragmentBuffer(try context.buffer(offsets), offset: 0, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return PassDispatch(passIndex: 0, name: "↑ ↘ lines", encoder: .render, functionNames: ["b2_common_fullscreen_vs", functionName],
                            threadsPerThreadgroup: [0, 0, 0], threadgroups: [0, 0, 0], staticThreadgroupMemoryBytes: 0,
                            dynamicThreadgroupMemoryBytes: 0, threadExecutionWidth: 0, pipelineMaxThreads: 0,
                            outputSize: ImageSize(width: t1.width, height: t1.height), outputHasShaderWrite: false,
                            modeledBytes: 3 * Double(t1.width * t1.height) * 8)
    }

    public struct SeedCase: Sendable {
        public var name: String
        public var specimen: SpecimenID
        public var options: SpecimenOptions
        public var edge: EdgeMode
        public var probes: [PixelPoint]
    }

    /// Night City v0 (HDR lights, the reference light and the pair), the 45° step edges with mirror edges, and the impulse
    /// ×100 with zero edges; probes on the light, the pair and a corner (crops at 894, the whole window at ≤ 256).
    public nonisolated static func cases(_ n: Int) -> [SeedCase] {
        let c = SpecimenGeometry.centre(windowSize: n)
        func clampPoint(_ x: Int, _ y: Int) -> PixelPoint { PixelPoint(x: Swift.min(Swift.max(x, 0), n - 1), y: Swift.min(Swift.max(y, 0), n - 1)) }
        return [
            SeedCase(name: "night city v0 clamp", specimen: "night-city", options: .standard, edge: .clamp,
                     probes: [clampPoint(c.x, c.y + 8), clampPoint(c.x - 120, c.y - 60)]),
            SeedCase(name: "step edges 45° mirror", specimen: "step-edges", options: SpecimenOptions(choices: ["orientation": "45"]),
                     edge: .mirror, probes: [clampPoint(c.x, c.y), clampPoint(2, 2)]),
            SeedCase(name: "impulse ×100 zero", specimen: "impulse", options: SpecimenOptions(choices: ["intensity": "100"]),
                     edge: .zero, probes: [clampPoint(c.x, c.y + 8)]),
        ]
    }

    /// Renders every case exactly as an MRT pass and compares BOTH attachments with F6HexLineSeedReference under the
    /// `bilinear` class (one bilinear pass) with the local scale of ARCHITECTURE §7 rule 1. Names end in "· T1" / "· T2".
    public static func parityOutcomes(windowSize n: Int, context: GPUContext,
                                      include: @escaping (String) -> Bool = { _ in true }) async -> [ParityOutcome] {
        var outcomes: [ParityOutcome] = []
        for seed in cases(n) {
            let names = ["\(label) @\(n): \(seed.name) · T1", "\(label) @\(n): \(seed.name) · T2"]
            guard names.contains(where: include) else { continue }
            var spare: [(any MTLTexture, TextureSpec)] = []
            defer { for (t, spec) in spare { context.recycle(t, spec: spec) } }
            do {
                guard let generator = SpecimenRegistry.generator(seed.specimen) else { throw GPUError.unsupported("no specimen \(seed.specimen)") }
                let options = seed.options.canvasOptions
                let image = await Task.detached(priority: .userInitiated) {
                    generator.canvas(windowSize: n, margin: SpecimenGeometry.margin, options: options, text: nil).window(pan: .zero).image
                }.value
                let half = await Task.detached(priority: .userInitiated) { HalfImageData(image) }.value
                try await prepare(context, edgeMode: seed.edge)
                let readSpec = TextureSpec(width: n, height: n, roles: [.read])
                let source = try await context.upload(half, roles: [.read])
                spare.append((source, readSpec))
                let spec = TextureSpec(width: n, height: n, roles: [.read, .renderTarget])
                let t1 = try context.texture(spec), t2 = try context.texture(spec)
                spare += [(t1, spec), (t2, spec)]
                let recorder = GPUCommandRecorder(context: context, label: seed.name)
                try encode(context, source: source, t1: t1, t2: t2, edgeMode: seed.edge, recorder: recorder)
                let completions = await recorder.commitAndWait()
                if let error = completions.compactMap(\.error).first { throw GPUError.commandBufferFailed(error) }
                let milliseconds = completions.reduce(0) { $0 + $1.milliseconds }
                let full = PixelRegion(origin: .zero, size: .square(n))
                let gpu1 = ImageBuffer(width: n, height: n, pixels: try await context.readTexels(t1, region: full))
                let gpu2 = ImageBuffer(width: n, height: n, pixels: try await context.readTexels(t2, region: full))
                let regions = n <= 256 ? [full] : seed.probes.map { PixelRegion.centred(on: $0, side: 128, inside: .square(n)) }
                let edge = seed.edge
                let cpu = await Task.detached(priority: .userInitiated) { () -> (t1: [ImageBuffer], t2: [ImageBuffer], scale: [Float], global: Double) in
                    let input = image.roundedToHalf()
                    let parts = regions.map { F6HexLineSeedReference.passOne(input, region: $0, edge: edge, options: .parity) }
                    let scale = ParityEvaluation.localScale(input, radius: F6HexLineSeedReference.supportRadius)
                    let global = Double(input.pixels.reduce(Float(1)) { Swift.max($0, $1.max()) })
                    return (parts.map(\.t1), parts.map(\.t2), scale, global)
                }.value
                func stack(_ parts: [ImageBuffer]) -> ImageBuffer {
                    ImageBuffer(width: parts[0].width, height: parts.reduce(0) { $0 + $1.height }, pixels: parts.flatMap(\.pixels))
                }
                let local = regions.flatMap { r in
                    (r.origin.y..<(r.origin.y + r.size.height)).flatMap { y in (r.origin.x..<(r.origin.x + r.size.width)).map { x in cpu.scale[y * n + x] } }
                }
                let compared = n <= 256 ? "full \(n) × \(n)" : "\(regions.count) crop(s) of 128² at the probes"
                for (k, (gpu, reference)) in [(gpu1, cpu.t1), (gpu2, cpu.t2)].enumerated() {
                    let evaluation = ParityEvaluation.evaluate(gpu: stack(regions.map { gpu.crop($0) }), cpu: stack(reference),
                                                               tolerance: .bilinear, inputScale: cpu.global, localScale: local,
                                                               bilinearPasses: 1)
                    outcomes.append(ParityOutcome(caseName: names[k], evaluation: evaluation, traced: nil, gpuMilliseconds: milliseconds,
                                                  comparedRegions: compared, failure: nil))
                }
            } catch {
                outcomes.append(ParityOutcome(caseName: names[0], evaluation: nil, traced: nil, gpuMilliseconds: nil,
                                              comparedRegions: nil, failure: String(describing: error)))
            }
        }
        return outcomes
    }
}
