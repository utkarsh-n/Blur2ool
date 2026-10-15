import Foundation
import Metal
import Testing
@testable import BlurCore
@testable import BlurGPU

// OWNER: ANALYSIS. One model of DRAM traffic (GPU §4.1): floor 6 shows the bytes each GPU pass recorded in its
// PassDispatch (`modeledBytes`), the cost readout shows CostModel's CostSummary. On the Mac GPU, every registered
// pipeline is prepared, encoded and committed at σ_equiv 4 px, and each pass's recorded bytes must equal the cost model's
// traffic for the same plan, size and format. A pipeline that disagrees is reported by name (fill `modeledBytes` from
// `CostModel().traffic(for:size:intermediate:)`; Documentation/build/requests/ANALYSIS.md).

@Suite struct ANALYSIS_GPUModeledBytes {
    @MainActor @Test func everyPipelineRecordsTheCostModelsBytes() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let compiled = try ParityRunner.compileLibrary(device: device, shaderDirectory: shaderDirectory())
        let context = try GPUContext(device: device, library: compiled.library, manifest: compiled.manifest)
        let n = 256, model = CostModel()
        var checked: [String] = [], skipped: [String] = []
        for factory in GPUPipelineRegistry.factories {
            let name = "\(factory.blur.rawValue)/\(factory.variant.rawValue)"
            guard let op = BlurRegistry.op(factory.blur) else { skipped.append(name + " (no operator)"); continue }
            let entry = op.entry
            let held = op.holdingSigma(FingerprintEngine.referenceSigma, current: entry.defaultParameters).parameters
            let request = OperatorRequest(parameters: held, variant: factory.variant, size: .square(n))
            guard op.resolveVariant(request).variant == factory.variant else { skipped.append(name + " (resolves away at σ 4)"); continue }
            let pipeline = factory.make()
            try await pipeline.prepare(context, request: request)
            let source = try context.texture(TextureSpec(width: n, height: n, roles: [.read, .renderTarget]))
            let destination = try context.texture(TextureSpec(width: n, height: n,
                                                              roles: pipeline.writesDestinationFromCompute ? [.read, .computeWrite] : [.read, .renderTarget]))
            let recorder = GPUCommandRecorder(context: context, label: "analysis-bytes")
            let encoded = try pipeline.encode(context, GPUBlurInputs(source: source, destination: destination, request: request),
                                              trace: nil, recorder: recorder)
            let completions = await recorder.commitAndWait()
            #expect(completions.allSatisfy { $0.error == nil }, "\(name): command buffer failed")
            let plan = op.passPlan(request)
            let traffic = model.traffic(for: plan, size: request.size, intermediate: request.settings.intermediate)
            #expect(encoded.dispatch.count == traffic.count, "\(name): \(encoded.dispatch.count) dispatches for \(traffic.count) plan passes")
            for (dispatch, modeled) in zip(encoded.dispatch, traffic) {
                #expect(dispatch.modeledBytes == modeled.bytes,
                        "\(name) pass \(modeled.name): PassDispatch.modeledBytes \(dispatch.modeledBytes) vs CostModel \(modeled.bytes)")
            }
            let summary = model.cost(for: plan, size: request.size, intermediate: .rgba16Float, bandwidth: .a17ProLeak)
            #expect(encoded.dispatch.map(\.modeledBytes).reduce(0, +) == summary.bytesMoved)
            checked.append(name)
        }
        print("ANALYSIS modeled bytes: checked \(checked.count) \(checked) · skipped \(skipped.count) \(skipped)")
        #expect(checked.count >= 3)   // the three Gaussian seeds are always registered
    }
}
