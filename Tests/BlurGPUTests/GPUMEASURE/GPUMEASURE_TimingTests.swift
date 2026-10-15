import Foundation
import Metal
import Testing
@testable import BlurCore
@testable import BlurGPU

// OWNER: GPU-MEASURE. The timing protocol on the Mac GPU (ARCHITECTURE §8.2 GPU-MEASURE acceptance): budget stop,
// CancellationError, stage-boundary per-pass times, the pass-isolated fallback (forced Apple2 limits = the Simulator's
// counter-less GPU), fused measurement, ABAB, overhead, and nil whenever GPUFacts.isSimulator (the hold substitute for the
// on-simulator check, which is DEFERRED-BY-HOLD).

@MainActor
func GPUMEASURE_context(apple2: Bool = false) throws -> GPUContext? {
    guard let device = MTLCreateSystemDefaultDevice() else { return nil }
    let compiled = try ParityRunner.compileLibrary(device: device, shaderDirectory: shaderDirectory())
    return try GPUContext(device: device, library: compiled.library, manifest: compiled.manifest, forceApple2Limits: apple2,
                          recordsDispatches: true)
}

/// A prepared Gaussian pipeline and its timing inputs (the window already "pre-passed": a noise-free step image).
@MainActor
func GPUMEASURE_gaussianInputs(_ context: GPUContext, variant: VariantID = "gaussian-separable", sigma: Double = 12, n: Int = 256,
                               truncation: String = "3", settings: SilentSettings = .standard) async throws
    -> (pipeline: any GPUBlurPipeline, inputs: GPUBlurInputs) {
    let factory = try #require(GPUPipelineRegistry.factory("gaussian-blur", variant))
    let pipeline = factory.make()
    let request = OperatorRequest(parameters: ParameterValues(["sigma": .double(sigma), "truncation": .choice(truncation),
                                                               "discretisation": .choice("sampled")]),
                                  variant: variant, settings: settings, size: .square(n))
    try await context.prepareCommonPipelines()
    try await pipeline.prepare(context, request: request)
    let image = MeasureShapeInputs.verticalStep(size: .square(n), at: n / 2)
    let source = try await context.upload(HalfImageData(image), roles: [.read, .renderTarget])
    let roles: TextureRole = pipeline.writesDestinationFromCompute ? [.read, .renderTarget, .computeWrite] : [.read, .renderTarget]
    let destination = try context.texture(TextureSpec(width: n, height: n, roles: roles))
    return (pipeline, GPUBlurInputs(source: source, destination: destination, request: request))
}

func GPUMEASURE_simulatorFacts() -> GPUFacts {
    var facts = GPUFacts.apple2(deviceName: "Apple iOS simulator GPU")
    facts.isSimulator = true; facts.forcedApple2Limits = false; facts.familyName = "Apple2"
    return facts
}

@Suite(.serialized) struct GPUMEASURE_Timing {
    /// The default protocol on this Mac: 3 warm-ups, 15 samples (a 256² σ 12 blur is far below the 1 s budget),
    /// per-pass times from stage-boundary counters for both blur passes, and the overhead measured separately.
    @MainActor @Test func defaultProtocolUsesStageBoundaryCountersOnThisMac() async throws {
        guard let context = try GPUMEASURE_context() else { return }
        #expect(context.facts.supportsStageBoundaryCounters, "the M1 Max samples at stage boundaries (research §4.3)")
        let (pipeline, inputs) = try await GPUMEASURE_gaussianInputs(context)
        let summary = try #require(try await TimingService().measure(pipeline, inputs: inputs, request: TimingRequest(), context: context))
        print("GPUMEASURE timing: \(summary.method.rawValue) n=\(summary.samples) median \(summary.medianMilliseconds) ms IQR \(summary.iqrMilliseconds) "
              + "perPass \(summary.perPass.map { "\($0.passName)=\($0.medianMilliseconds)" }) overhead \(summary.overheadMilliseconds ?? -1)")
        #expect(summary.method == .stageBoundaryCounters)
        #expect(summary.warmups == 3 && summary.samples == 15 && summary.stopReason == .samplesReached)
        #expect(summary.perPass.map(\.passIndex) == [0, 1])
        #expect(summary.perPass.map(\.passName) == ["H", "V"])
        #expect(summary.perPass.allSatisfy { $0.medianMilliseconds > 0 && $0.samples == 15 })
        // Per-pass encoder times sit inside the command buffer's time.
        let passSum = summary.perPass.reduce(0) { $0 + $1.medianMilliseconds }
        #expect(passSum <= summary.medianMilliseconds * 1.1 + 0.05, "\(passSum) vs \(summary.medianMilliseconds)")
        #expect(summary.medianMilliseconds > 0 && summary.iqrMilliseconds >= 0)
        #expect((summary.overheadMilliseconds ?? 0) > 0, "the window copy is timed separately")
        #expect(summary.fusedMedianMilliseconds == nil && !summary.interleaved)
    }

    /// The stage-boundary sampler on its own: per-pass ms for a two-pass blur through a `.stageBoundaryCounters` recorder.
    @MainActor @Test func stageBoundarySamplerReturnsPerPassMilliseconds() async throws {
        guard let context = try GPUMEASURE_context() else { return }
        let (pipeline, inputs) = try await GPUMEASURE_gaussianInputs(context, n: 512)
        let service = TimingService()
        let sampler = try #require(service.makeSampler(passes: 2, context: context))
        _ = await (sampler as? MeasureStageBoundarySampler)?.clock.calibrated()
        for _ in 0..<3 {
            (sampler as? MeasureStageBoundarySampler)?.reset()
            let recorder = GPUCommandRecorder(context: context, isolation: .stageBoundaryCounters, label: "sampler", sampler: sampler)
            let encoded = try pipeline.encode(context, inputs, trace: nil, recorder: recorder)
            let done = await recorder.commitAndWait()
            context.recycle(encoded)
            #expect(done.count == 1 && done[0].error == nil)
            let perPass = try #require(recorder.passMilliseconds(done))
            print("GPUMEASURE sampler: \(perPass) of \(done[0].milliseconds) ms")
            #expect(Set(perPass.keys) == [0, 1])
            #expect(perPass.values.allSatisfy { $0 > 0 && $0 < done[0].milliseconds * 1.05 + 0.05 })
        }
    }

    /// Stop at the GPU-time budget: once `minSamples` exist and the summed GPU time reaches `maxGPUSeconds`.
    @MainActor @Test func stopsAtTheGPUTimeBudget() async throws {
        guard let context = try GPUMEASURE_context() else { return }
        let (pipeline, inputs) = try await GPUMEASURE_gaussianInputs(context)
        let tiny = try #require(try await TimingService().measure(pipeline, inputs: inputs,
                                                                   request: TimingRequest(maxGPUSeconds: 1e-9), context: context))
        #expect(tiny.stopReason == .gpuTimeBudget && tiny.samples == 3, "minimum 3 samples, then the budget stops it")
        // A real budget: a heavy blur (σ 64 separable at 894², ≈ 770 taps per pixel) against 40 ms of GPU time.
        let (heavy, heavyInputs) = try await GPUMEASURE_gaussianInputs(context, sigma: 64, n: 894)
        let budget = 0.040
        let s = try #require(try await TimingService().measure(heavy, inputs: heavyInputs,
                                                                request: TimingRequest(maxGPUSeconds: budget), context: context))
        print("GPUMEASURE budget: n=\(s.samples) median \(s.medianMilliseconds) ms stop \(s.stopReason.rawValue)")
        #expect(s.stopReason == .gpuTimeBudget && s.samples >= 3 && s.samples < 15)
        // It stopped at the first sample that crossed the budget: n − 1 samples were not yet enough.
        #expect(Double(s.samples - 1) * s.medianMilliseconds < budget * 1000 * 1.5 + s.medianMilliseconds)
        #expect(Double(s.samples) * s.medianMilliseconds * 1.5 >= budget * 1000)
    }

    /// Cancelled before it starts, and cancelled between command buffers mid-run: both throw CancellationError and no
    /// command buffer runs after the cancel.
    @MainActor @Test func throwsCancellationErrorWhenCancelled() async throws {
        guard let context = try GPUMEASURE_context() else { return }
        let (pipeline, inputs) = try await GPUMEASURE_gaussianInputs(context)
        let early = Task { @MainActor in try await TimingService().measure(pipeline, inputs: inputs, request: TimingRequest(), context: context) }
        early.cancel()
        await #expect(throws: CancellationError.self) { _ = try await early.value }

        let service = TimingService()
        var seen = 0
        service.afterCommandBuffer = { count in
            seen = count
            if count == 5 { withUnsafeCurrentTask { $0?.cancel() } }       // a touch arrives after the 5th buffer
        }
        let midway = Task { @MainActor in try await service.measure(pipeline, inputs: inputs, request: TimingRequest(), context: context) }
        await #expect(throws: CancellationError.self) { _ = try await midway.value }
        #expect(seen == 5, "no command buffer after the cancel (saw \(seen))")
    }

    /// Without counters (`.commandBufferPerPass` requested, or a counter-less GPU such as the Simulator's Apple2 family
    /// forced here) the per-pass times come from one command buffer per pass.
    @MainActor @Test func passIsolatedFallback() async throws {
        guard let context = try GPUMEASURE_context() else { return }
        let (pipeline, inputs) = try await GPUMEASURE_gaussianInputs(context)
        let isolated = try #require(try await TimingService().measure(pipeline, inputs: inputs,
                                                                       request: TimingRequest(samples: 5, isolation: .commandBufferPerPass),
                                                                       context: context))
        #expect(isolated.method == .passIsolatedCommandBuffers && isolated.perPass.map(\.passIndex) == [0, 1])
        #expect(isolated.perPass.allSatisfy { $0.medianMilliseconds > 0 })

        guard let apple2 = try GPUMEASURE_context(apple2: true) else { return }
        #expect(!apple2.facts.supportsStageBoundaryCounters)
        #expect(TimingService().makeSampler(passes: 2, context: apple2) == nil)
        let (p2, i2) = try await GPUMEASURE_gaussianInputs(apple2)
        let forced = try #require(try await TimingService().measure(p2, inputs: i2, request: TimingRequest(samples: 5), context: apple2))
        #expect(forced.method == .passIsolatedCommandBuffers && forced.perPass.count == 2)
    }

    /// The fused form (one command buffer, no counter attachments) alongside the instrumented one; MEASUREMENT
    /// OVERHEAD is their difference. Also the compute tile (compute passes get encoder-boundary samples).
    @MainActor @Test func fusedMeasurementAndComputePasses() async throws {
        guard let context = try GPUMEASURE_context() else { return }
        for variant: VariantID in ["gaussian-separable", "gaussian-compute-tile", "gaussian-linear-sampling"] {
            let (pipeline, inputs) = try await GPUMEASURE_gaussianInputs(context, variant: variant)
            let s = try #require(try await TimingService().measure(pipeline, inputs: inputs,
                                                                    request: TimingRequest(samples: 7, measureFused: true), context: context))
            print("GPUMEASURE fused \(variant.rawValue): median \(s.medianMilliseconds) fused \(s.fusedMedianMilliseconds ?? -1) method \(s.method.rawValue)")
            #expect(s.method == .stageBoundaryCounters && s.perPass.count == 2)
            #expect((s.fusedMedianMilliseconds ?? 0) > 0)
        }
    }

    /// ABAB: both summaries interleaved, same n, thermal state recorded at both ends; the colour passes join the overhead.
    @MainActor @Test func interleavedABAB() async throws {
        guard let context = try GPUMEASURE_context() else { return }
        let a = try await GPUMEASURE_gaussianInputs(context, sigma: 4)
        let b = try await GPUMEASURE_gaussianInputs(context, variant: "gaussian-linear-sampling", sigma: 4,
                                                    settings: SilentSettings(colourSpace: .srgbEncoded))
        let pair = try #require(try await TimingService().measureInterleaved((a.pipeline, a.inputs), (b.pipeline, b.inputs),
                                                                              request: TimingRequest(samples: 6), context: context))
        #expect(pair.0.interleaved && pair.1.interleaved)
        #expect(pair.0.samples == 6 && pair.1.samples == 6)
        #expect(pair.0.thermalAtStart != .unknown && pair.1.thermalAtEnd != .unknown)
        #expect((pair.0.overheadMilliseconds ?? 0) > 0 && (pair.1.overheadMilliseconds ?? 0) > 0)
    }

    /// Simulator honesty (SPEC §4.1.6, §12.2 item 7): with GPUFacts.isSimulator every entry point returns nil and no
    /// GPU work is timed. On-simulator confirmation: DEFERRED-BY-HOLD.
    @MainActor @Test func returnsNilWhenGPUFactsSaySimulator() async throws {
        guard let context = try GPUMEASURE_context() else { return }
        let (pipeline, inputs) = try await GPUMEASURE_gaussianInputs(context)
        let service = TimingService(factsOverride: GPUMEASURE_simulatorFacts())
        var buffers = 0
        service.afterCommandBuffer = { buffers = $0 }
        #expect(try await service.measure(pipeline, inputs: inputs, request: TimingRequest(), context: context) == nil)
        #expect(try await service.measureInterleaved((pipeline, inputs), (pipeline, inputs), request: TimingRequest(), context: context) == nil)
        #expect(service.makeSampler(passes: 2, context: context) == nil)
        #expect(buffers == 0)
    }
}
