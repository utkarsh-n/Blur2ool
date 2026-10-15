import Foundation
import Metal
import Testing
@testable import BlurCore
@testable import BlurGPU

// OWNER: SKEL. Proves the GPU contract on the Mac GPU: shaders compiled from source as one translation unit, the
// Gaussian pipeline vs BlurReference within §7 tolerances, and traced == untraced bit for bit (JF G-7).

/// App/GPU/Shaders in the repo; the verification snapshot keeps them in Metal/.
func shaderDirectory() -> URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<4 { url.deleteLastPathComponent() }
    let repo = url.appendingPathComponent("App/GPU/Shaders")
    return FileManager.default.fileExists(atPath: repo.path) ? repo : url.appendingPathComponent("Metal")
}

@Suite struct SKEL_GPUContract {
    @Test func traceLayoutStrides() {
        #expect(MemoryLayout<TraceLayout.Header>.stride == TraceLayout.headerStride)
        #expect(MemoryLayout<TraceLayout.Tap>.stride == TraceLayout.tapStride)
    }

    @MainActor @Test func gaussianParityOnMacGPU() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let compiled = try ParityRunner.compileLibrary(device: device, shaderDirectory: shaderDirectory())
        #expect(compiled.library.functionNames.contains("b2_f2_gauss_linear_fs"))
        #expect(compiled.library.functionNames.contains("b2_f2_gauss_separable_fs"))
        let context = try GPUContext(device: device, library: compiled.library, manifest: compiled.manifest, recordsDispatches: true)
        for variant: VariantID in ["gaussian-linear-sampling", "gaussian-separable"] {
        guard let factory = GPUPipelineRegistry.factory("gaussian-blur", variant) else {
            Issue.record("no Gaussian factory \(variant)"); return
        }
        for parityCase in factory.parityCases(256) {
            let outcome = await ParityRunner.run(parityCase, factory: factory, context: context)
            #expect(outcome.failure == nil, "\(parityCase.name): \(outcome.failure ?? "")")
            #expect(outcome.passed, "\(parityCase.name): maxAbs \(outcome.evaluation?.stats.maxAbs ?? -1), excess \(outcome.evaluation?.worstExcess ?? -1)")
            if parityCase.checkTraced {
                #expect(outcome.traced?.differingWords == 0, "traced != untraced: \(outcome.traced?.differingWords ?? -1) words")
                #expect(outcome.traced?.finalSumMatchesOutput == true)
                #expect(outcome.traced?.tapsPerTracedPass.allSatisfy { $0 > 0 } == true)
                #expect(outcome.traced?.missingFinalRecord == false && outcome.traced?.overflow == 0)
            }
        }
        }
    }

    /// E-3: encode never compiles — an unprepared pipeline throws notPrepared; after prepare it encodes.
    @MainActor @Test func encodeNeverCompiles() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let compiled = try ParityRunner.compileLibrary(device: device, shaderDirectory: shaderDirectory())
        let context = try GPUContext(device: device, library: compiled.library, manifest: compiled.manifest)
        let pipeline = GaussianSeparablePipeline()
        let request = OperatorRequest(parameters: ParameterValues(["sigma": .double(2)]), variant: GaussianOperator.separable, size: .square(32))
        let spec = TextureSpec(width: 32, height: 32, roles: [.read, .renderTarget])
        let source = try context.texture(spec), output = try context.texture(spec)
        let recorder = GPUCommandRecorder(context: context, label: "unprepared")
        #expect(throws: GPUError.self) {
            _ = try pipeline.encode(context, GPUBlurInputs(source: source, destination: output, request: request), trace: nil, recorder: recorder)
        }
        try await pipeline.prepare(context, request: request)
        let ok = GPUCommandRecorder(context: context, label: "prepared")
        _ = try pipeline.encode(context, GPUBlurInputs(source: source, destination: output, request: request), trace: nil, recorder: ok)
        let completions = await ok.commitAndWait()
        #expect(completions.allSatisfy { $0.error == nil })
    }

    /// E-19: with per-pass isolation the pre- and post-passes get their own command buffers.
    @MainActor @Test func isolationGivesColourPassesOwnBuffers() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let compiled = try ParityRunner.compileLibrary(device: device, shaderDirectory: shaderDirectory())
        let context = try GPUContext(device: device, library: compiled.library, manifest: compiled.manifest)
        try await context.prepareCommonPipelines()
        let pipeline = GaussianSeparablePipeline()
        let request = OperatorRequest(parameters: ParameterValues(["sigma": .double(2)]), variant: GaussianOperator.separable,
                                      settings: SilentSettings(colourSpace: .srgbEncoded), size: .square(32))
        try await pipeline.prepare(context, request: request)
        let spec = TextureSpec(width: 32, height: 32, roles: [.read, .renderTarget])
        let window = try context.texture(spec), output = try context.texture(spec)
        let recorder = GPUCommandRecorder(context: context, isolation: .commandBufferPerPass, label: "isolated")
        let encoded = try context.encodeFullBlur(pipeline, window: window, output: output, request: request, trace: nil, recorder: recorder)
        let passes = recorder.bufferPasses, transient = encoded.transientTextures.count
        #expect(passes == [-2, 0, 1, -1])
        #expect(transient == 2)
        _ = await recorder.commitAndWait()
        context.recycle(encoded)
    }

    @MainActor @Test func apple2LimitsRefuseOversizedThreadgroupMemory() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let library = try await device.makeLibrary(source: "#include <metal_stdlib>\nusing namespace metal;\nkernel void k(uint2 g [[thread_position_in_grid]]) {}", options: nil)
        let context = try GPUContext(device: device, library: library, manifest: ShaderManifest(files: [:], combinedSHA256: ""), forceApple2Limits: true)
        let facts = context.facts
        #expect(facts.maxThreadsPerThreadgroup == 512 && facts.maxThreadgroupMemoryLength == 16_384)
        let pso = try await context.computePipeline("k", constants: FunctionConstants())
        let size = context.threadgroupSize(for: pso)
        #expect(size.width * size.height <= 512)
    }
}
