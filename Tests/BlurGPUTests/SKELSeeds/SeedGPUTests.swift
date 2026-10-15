import Foundation
import Metal
import Testing
@testable import BlurCore
@testable import BlurGPU

// OWNER: SKEL. The GPU seeds of ARCHITECTURE §9.1 item 5 (review fix E-15) on the Mac GPU, compiled from App/GPU/Shaders as
// one translation unit: the compute tile (dynamic threadgroup memory through dispatch2D, compute TRACE_PROBE, final
// records), the two-attachment MRT pass with parity on both attachments, and the commandBufferPerPass timing smoke test.
// Kept beside Tests/BlurGPUTests/SKEL (frozen, byte-identical to the snapshot); `core-test --area SKEL` runs both.

@MainActor
func SKEL_seedContext(apple2: Bool = false) throws -> GPUContext? {
    guard let device = MTLCreateSystemDefaultDevice() else { return nil }
    let compiled = try ParityRunner.compileLibrary(device: device, shaderDirectory: shaderDirectory())
    return try GPUContext(device: device, library: compiled.library, manifest: compiled.manifest, forceApple2Limits: apple2,
                          recordsDispatches: true)
}

@Suite(.serialized) struct SKEL_ComputeTileSeed {
    @MainActor @Test(arguments: [false, true]) func parityTracesAndDispatch(apple2: Bool) async throws {
        guard let context = try SKEL_seedContext(apple2: apple2) else { return }
        let factory = try #require(GPUPipelineRegistry.factory("gaussian-blur", "gaussian-compute-tile"))
        for parityCase in factory.parityCases(128) {
            let before = context.dispatchLog.count
            let outcome = await ParityRunner.run(parityCase, factory: factory, context: context)
            #expect(outcome.failure == nil, "\(parityCase.name): \(outcome.failure ?? "")")
            #expect(outcome.passed, "\(parityCase.name): maxAbs \(outcome.evaluation?.stats.maxAbs ?? -1) excess \(outcome.evaluation?.worstExcess ?? -1)")
            let renders = 1 + (parityCase.checkTraced ? parityCase.probes.count : 0)
            #expect(context.dispatchLog.count - before == 2 * renders, "every compute pass goes through dispatch2D")
            if parityCase.checkTraced {
                #expect(outcome.traced?.differingWords == 0)
                #expect(outcome.traced?.finalSumMatchesOutput == true)
                #expect(outcome.traced?.missingFinalRecord == false && outcome.traced?.overflow == 0)
                #expect(outcome.traced?.tapsPerTracedPass.allSatisfy { $0 > 0 } == true)
            }
        }
        // σ 4 → r 12: the row tile is 256 × 1 threads with (256 + 2·12) × 8 B = 2,240 B of dynamic threadgroup memory.
        #expect(context.dispatchLog.contains { $0.contains("H tile r12") && $0.contains("tg=256x1") && $0.contains("tgmem=2240") })
        #expect(context.dispatchLog.contains { $0.contains("V tile r12") && $0.contains("tg=1x256") })
        if apple2 { #expect(context.facts.forcedApple2Limits && context.facts.maxThreadgroupMemoryLength == 16_384) }
    }

    /// The compute tile and the separable fragment pass run the same fma chain: identical fp16 output.
    @MainActor @Test func tileEqualsSeparableBitForBit() async throws {
        guard let context = try SKEL_seedContext() else { return }
        try await context.prepareCommonPipelines()
        let n = 96
        let canvas = NightCityGenerator().canvas(windowSize: n, margin: SpecimenGeometry.margin, options: .standard, text: nil)
        let source = try await context.upload(HalfImageData(canvas.window(pan: PixelPoint(x: 40, y: -20)).image), roles: [.read, .renderTarget])
        var outputs: [[SIMD4<Float>]] = []
        for (pipeline, variant) in [(GaussianComputeTilePipeline() as any GPUBlurPipeline, GaussianOperator.computeTile),
                                    (GaussianSeparablePipeline(), GaussianOperator.separable)] {
            let request = OperatorRequest(parameters: ParameterValues(["sigma": .double(5)]), variant: variant, size: .square(n))
            try await pipeline.prepare(context, request: request)
            let out = try context.texture(TextureSpec(width: n, height: n, roles: [.read, .renderTarget, .computeWrite]))
            let recorder = GPUCommandRecorder(context: context, label: "\(variant)")
            _ = try context.encodeFullBlur(pipeline, window: source, output: out, request: request, trace: nil, recorder: recorder)
            _ = await recorder.commitAndWait()
            outputs.append(try await context.readTexels(out, region: PixelRegion(origin: .zero, size: .square(n))))
        }
        let differing = zip(outputs[0], outputs[1]).reduce(0) { acc, p in acc + (0..<4).filter { p.0[$0].bitPattern != p.1[$0].bitPattern }.count }
        #expect(differing == 0)
    }
}

@Suite(.serialized) struct SKEL_MRTSeed {
    /// Parity on BOTH attachments of the two-attachment pass, against F6HexLineSeedReference (`bilinear`, one pass).
    @MainActor @Test(arguments: [false, true]) func bothAttachmentsMatchTheReference(apple2: Bool) async throws {
        guard let context = try SKEL_seedContext(apple2: apple2) else { return }
        try await context.prepareCommonPipelines()
        let outcomes = await F6HexLineSeed.parityOutcomes(windowSize: 128, context: context)
        #expect(outcomes.count == 2 * F6HexLineSeed.cases(128).count)
        #expect(outcomes.filter { $0.caseName.hasSuffix("· T1") }.count == outcomes.filter { $0.caseName.hasSuffix("· T2") }.count)
        for outcome in outcomes {
            #expect(outcome.failure == nil, "\(outcome.caseName): \(outcome.failure ?? "")")
            #expect(outcome.passed, "\(outcome.caseName): maxAbs \(outcome.evaluation?.stats.maxAbs ?? -1) excess \(outcome.evaluation?.worstExcess ?? -1)")
        }
    }

    /// The two attachments really are different images: T1 sees only the ↑ line, T2 adds the ↘ line at half weight.
    @MainActor @Test func attachmentsHoldDifferentImages() async throws {
        guard let context = try SKEL_seedContext() else { return }
        var impulse = ImageBuffer(width: 48, height: 48)
        impulse[24, 24] = SIMD4(1, 1, 1, 1)
        try await F6HexLineSeed.prepare(context, edgeMode: .zero)
        let source = try await context.upload(HalfImageData(impulse), roles: [.read])
        let spec = TextureSpec(width: 48, height: 48, roles: [.read, .renderTarget])
        let t1 = try context.texture(spec), t2 = try context.texture(spec)
        let recorder = GPUCommandRecorder(context: context, label: "mrt")
        try F6HexLineSeed.encode(context, source: source, t1: t1, t2: t2, edgeMode: .zero, recorder: recorder)
        #expect(recorder.encodeLog.count == 1 && recorder.encodeLog.first?.kind == .render)
        let completions = await recorder.commitAndWait()
        #expect(completions.allSatisfy { $0.error == nil })
        let all = PixelRegion(origin: .zero, size: .square(48))
        let a = ImageBuffer(width: 48, height: 48, pixels: try await context.readTexels(t1, region: all))
        let b = ImageBuffer(width: 48, height: 48, pixels: try await context.readTexels(t2, region: all))
        #expect(a[24, 30].x > 0 && abs(b[24, 30].x - a[24, 30].x / 2) <= Float(HalfFloat.ulp(a[24, 30].x)))
        #expect(a[16, 19].x == 0 && b[16, 19].x > 0)
    }
}

@Suite(.serialized) struct SKEL_TimingSmoke {
    /// `.commandBufferPerPass`: per-pass milliseconds exist for every blur pass and never include the pre- and post-passes
    /// (review fix E-19), for a fragment pipeline and for the compute tile.
    @MainActor @Test func perPassMillisecondsExcludeColourPasses() async throws {
        guard let context = try SKEL_seedContext() else { return }
        try await context.prepareCommonPipelines()
        for pipeline in [GaussianSeparablePipeline() as any GPUBlurPipeline, GaussianComputeTilePipeline()] {
            let request = OperatorRequest(parameters: ParameterValues(["sigma": .double(12)]), variant: pipeline.variant,
                                          settings: SilentSettings(colourSpace: .srgbEncoded), size: .square(256))
            try await pipeline.prepare(context, request: request)
            let spec = TextureSpec(width: 256, height: 256, roles: [.read, .renderTarget, .computeWrite])
            let window = try context.texture(spec), output = try context.texture(spec)
            let recorder = GPUCommandRecorder(context: context, isolation: .commandBufferPerPass, label: "timing smoke")
            let encoded = try context.encodeFullBlur(pipeline, window: window, output: output, request: request, trace: nil, recorder: recorder)
            #expect(recorder.bufferPasses == [GPUCommandRecorder.prePass, 0, 1, GPUCommandRecorder.postPass])
            let completions = await recorder.commitAndWait()
            #expect(completions.count == 4 && completions.allSatisfy { $0.error == nil })
            let perPass = try #require(recorder.passMilliseconds(completions))
            #expect(Set(perPass.keys) == [0, 1], "per-pass times cover the blur passes only")
            #expect(perPass.values.allSatisfy { $0 > 0 && $0 < 1000 }, "\(perPass)")
            context.recycle(encoded)
        }
    }
}

/// fp16 storage rounding of THIS GPU (MEASURED), for Documentation/build/requests/SKEL.md item 1.
enum SKEL_HalfStoreRule: String { case towardZero, nearestEven, mixed }

func SKEL_halfTowardZero(_ v: Float) -> Float {
    let h = Float16(v)
    if abs(Float(h)) <= abs(v) || !h.isFinite { return Float(h) }
    return Float(v > 0 ? h.nextDown : h.nextUp)
}

/// Stores floats whose round-to-nearest and round-toward-zero halves differ, through a compute `write` and through a
/// render-target output, and reports which rule both paths follow.
@MainActor
func SKEL_measureHalfStoreRule(_ device: any MTLDevice) async throws -> (compute: SKEL_HalfStoreRule, render: SKEL_HalfStoreRule) {
    let source = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void skel_store_k(texture2d<float, access::write> t [[texture(0)]], constant float *v [[buffer(0)]],
                             uint2 g [[thread_position_in_grid]]) { t.write(float4(v[g.x]), g); }
    struct SkelVO { float4 p [[position]]; };
    vertex SkelVO skel_store_vs(uint vid [[vertex_id]]) {
        float2 uv = float2(float((vid << 1) & 2), float(vid & 2)); SkelVO o; o.p = float4(uv * float2(2, -2) + float2(-1, 1), 0, 1); return o;
    }
    fragment float4 skel_store_fs(SkelVO in [[stage_in]], constant float *v [[buffer(0)]]) { return float4(v[uint(in.p.x)]); }
    """
    let library = try await device.makeLibrary(source: source, options: nil)
    let ulp1: Float = 1.0 / 1024
    let values: [Float] = [1 + 0.75 * ulp1, 1 + 1.75 * ulp1, 0.090611696, -(1 + 0.75 * ulp1), 2049.9, 12.3456]
    let n = values.count
    guard let buffer = device.makeBuffer(bytes: values, length: n * 4, options: .storageModeShared),
          let queue = device.makeCommandQueue(), let cb = queue.makeCommandBuffer() else { throw GPUError.bufferAllocationFailed }
    func texture(_ usage: MTLTextureUsage) throws -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: n, height: 1, mipmapped: false)
        d.usage = usage; d.storageMode = .shared
        guard let t = device.makeTexture(descriptor: d) else { throw GPUError.textureAllocationFailed("probe") }
        return t
    }
    let written = try texture([.shaderWrite, .shaderRead]), rendered = try texture([.renderTarget, .shaderRead])
    let compute = try await device.makeComputePipelineState(function: library.makeFunction(name: "skel_store_k")!)
    let ce = cb.makeComputeCommandEncoder()!
    ce.setComputePipelineState(compute); ce.setTexture(written, index: 0); ce.setBuffer(buffer, offset: 0, index: 0)
    ce.dispatchThreadgroups(MTLSize(width: n, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
    ce.endEncoding()
    let pd = MTLRenderPipelineDescriptor()
    pd.vertexFunction = library.makeFunction(name: "skel_store_vs"); pd.fragmentFunction = library.makeFunction(name: "skel_store_fs")
    pd.colorAttachments[0].pixelFormat = .rgba16Float
    let rpd = MTLRenderPassDescriptor()
    rpd.colorAttachments[0].texture = rendered; rpd.colorAttachments[0].loadAction = .clear; rpd.colorAttachments[0].storeAction = .store
    let renderState = try await device.makeRenderPipelineState(descriptor: pd)
    let re = cb.makeRenderCommandEncoder(descriptor: rpd)!
    re.setRenderPipelineState(renderState); re.setFragmentBuffer(buffer, offset: 0, index: 0)
    re.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); re.endEncoding()
    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in cb.addCompletedHandler { _ in c.resume() }; cb.commit() }
    func rule(_ t: any MTLTexture) -> SKEL_HalfStoreRule {
        var out = [SIMD4<Float16>](repeating: .zero, count: n)
        t.getBytes(&out, bytesPerRow: n * 8, from: MTLRegionMake2D(0, 0, n, 1), mipmapLevel: 0)
        let stored = out.map { Float($0.x) }
        if zip(stored, values).allSatisfy({ $0 == SKEL_halfTowardZero($1) }) { return .towardZero }
        if zip(stored, values).allSatisfy({ $0 == Float(Float16($1)) }) { return .nearestEven }
        return .mixed
    }
    return (rule(written), rule(rendered))
}

@Suite(.serialized) struct SKEL_HalfStoreRounding {
    @MainActor @Test func storeRuleIsConsistentAcrossComputeAndRender() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let rule = try await SKEL_measureHalfStoreRule(device)
        print("SKEL_HalfStoreRounding: \(device.name) stores fp16 by \(rule.compute.rawValue) (compute write) and \(rule.render.rawValue) (render target)")
        #expect(rule.compute == rule.render && rule.compute != .mixed)
    }

    /// The trace's final record (flags = 2) is the value the pass stores: under the MEASURED store rule it equals the
    /// stored texel bit for bit (compute tile and separable fragment pass, Night City v0 σ 12 at the probe under the light).
    @MainActor @Test func finalRecordEqualsTheStoredValueUnderTheMeasuredRule() async throws {
        guard let context = try SKEL_seedContext() else { return }
        let rule = try await SKEL_measureHalfStoreRule(context.device).render
        let n = 128, c = SpecimenGeometry.centre(windowSize: n), probe = PixelPoint(x: c.x, y: c.y + 8)
        let window = NightCityGenerator().canvas(windowSize: n, margin: SpecimenGeometry.margin, options: .standard, text: nil).window(pan: .zero)
        let source = try await context.upload(HalfImageData(window.image), roles: [.read, .renderTarget])
        for pipeline in [GaussianComputeTilePipeline() as any GPUBlurPipeline, GaussianSeparablePipeline()] {
            let request = OperatorRequest(parameters: ParameterValues(["sigma": .double(12)]), variant: pipeline.variant, size: .square(n))
            try await pipeline.prepare(context, request: request)
            let output = try context.texture(TextureSpec(width: n, height: n, roles: [.read, .renderTarget, .computeWrite]))
            let recorder = GPUCommandRecorder(context: context, label: "final record")
            let encoded = try context.encodeFullBlur(pipeline, window: source, output: output, request: request,
                                                     trace: TraceRequest.sized(probe: probe, plan: GaussianOperator().passPlan(request)),
                                                     recorder: recorder)
            _ = await recorder.commitAndWait()
            let stored = try await context.readTexels(output, region: PixelRegion(origin: probe, size: .square(1)))[0]
            let blocks = TraceLayout.decode(try #require(encoded.traceBuffer), passes: 2, capacity: encoded.traceCapacity)
            let final = try #require(blocks[1].taps.last { $0.flags == 2 }).runningSum
            let nearest: (Float) -> Float = { (v: Float) -> Float in Float(Float16(v)) }
            let round: (Float) -> Float = rule == .towardZero ? SKEL_halfTowardZero : nearest
            #expect((0..<4).allSatisfy { round(final[$0]).bitPattern == stored[$0].bitPattern }, "\(pipeline.variant): final \(final) stored \(stored)")
            context.recycle(encoded)
        }
    }

    /// Reproduces requests/SKEL.md item 1 for INTEGRATE: the frozen ParityRunner compares the final record rounded to
    /// NEAREST with a toward-zero store, and the frozen CPU model rounds intermediates to nearest, so Night City v0 at σ 12
    /// fails `exactF32` (3 ulps) and `final=out` on this Mac although traced = untraced holds bit for bit.
    @MainActor @Test func frozenParityMisjudgesTowardZeroStores() async throws {
        guard let context = try SKEL_seedContext() else { return }
        let rule = try await SKEL_measureHalfStoreRule(context.device).render
        let factory = try #require(GPUPipelineRegistry.factory("gaussian-blur", "gaussian-compute-tile"))
        let n = 128, c = SpecimenGeometry.centre(windowSize: n), probe = PixelPoint(x: c.x, y: c.y + 8)
        let configuration = RenderConfiguration(blur: GaussianOperator.id, variant: GaussianOperator.computeTile,
                                                parameters: ParameterValues(["sigma": .double(12), "truncation": .choice("3")]),
                                                settings: .standard, specimen: "night-city", specimenOptions: .standard, pan: .zero,
                                                probe: probe, windowSize: n)
        let parityCase = ParityCase(name: "night city v0 σ12 (requests/SKEL.md item 1)", configuration: configuration, tolerance: .exactF32,
                                    bilinearPasses: 0, checkTraced: true, probes: [probe], note: "toward-zero fp16 stores")
        let outcome = await ParityRunner.run(parityCase, factory: factory, context: context)
        #expect(outcome.failure == nil && outcome.traced?.differingWords == 0 && outcome.traced?.overflow == 0)
        if rule == .towardZero {
            withKnownIssue("frozen parity assumes round-to-nearest fp16 stores; this GPU rounds toward zero") {
                #expect(outcome.passed)
            }
        } else {
            #expect(outcome.passed)
        }
    }
}
