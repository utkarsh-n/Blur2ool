import XCTest
import SwiftUI
import MetalKit
import UIKit
@testable import Blur2ool
import BlurCore
import BlurGPU

// OWNER: SKEL (ARCHITECTURE §9.1 item 6; run on the phone under the simulator hold with
// `Tools/build.sh device-build-for-testing` + `device-session "test --area SKEL"`).
// 1. The app's default library holds every registered pipeline's functions, the B2Common functions and instrumentLensOptics.
// 2. ShaderManifest.load verifies the bundled sources (Tools/shader-manifest.sh) and computes the combined SHA.
// 3. A Gaussian render through the app's RenderCoordinator gives a probe value within `bilinear` of BlurReference.
// 4. MetalSpecimenView's drawable is exactly N × N, autoResizeDrawable is off, contentScaleFactor = displayScale, sRGB layer.
@MainActor
final class SKEL_AppTests: XCTestCase {
    private func library() throws -> (any MTLDevice, any MTLLibrary) {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        return (device, try XCTUnwrap(device.makeDefaultLibrary(), "the app's default.metallib"))
    }

    func testDefaultLibraryContainsEveryRegisteredFunction() throws {
        let names = Set(try library().1.functionNames)
        var expected: Set<String> = ["b2_common_fullscreen_vs", "b2_common_colour_fs", "b2_common_window_fs", "b2_common_downsample2x_fs",
                                     "b2_common_copy_fs", "b2_present_fs", "b2_f6_hexlines_mrt_fs", "instrumentLensOptics"]
        for factory in GPUPipelineRegistry.factories { expected.formUnion(factory.make().functionNames) }
        XCTAssertTrue(expected.isSubset(of: names), "missing: \(expected.subtracting(names).sorted())")
    }

    func testShaderManifestLoads() throws {
        let directory = try XCTUnwrap(Bundle.main.resourceURL?.appendingPathComponent("ShaderSources"))
        let loaded = try XCTUnwrap(ShaderManifest.load(from: directory), "ShaderSources/ShaderManifest.json verifies")
        XCTAssertEqual(loaded.manifest.combinedSHA256.count, 64)
        XCTAssertNotNil(loaded.texts["F2Gaussian.metal"])
        XCTAssertNotNil(loaded.texts["B2Shared.h"])
    }

    func testGaussianProbeMatchesReferenceWithinBilinear() async throws {
        let (device, library) = try library()
        let manifest = ShaderManifest.load(from: Bundle.main.resourceURL!.appendingPathComponent("ShaderSources"))?.manifest
            ?? ShaderManifest(files: [:], combinedSHA256: "")
        let context = try GPUContext(device: device, library: library, manifest: manifest)
        let coordinator = RenderCoordinator(gpu: context, specimens: SpecimenStore())
        let n = 256, c = SpecimenGeometry.centre(windowSize: n)
        let probe = PixelPoint(x: c.x - 1, y: c.y - 100)
        let configuration = RenderConfiguration(blur: GaussianOperator.id, variant: GaussianOperator.linearSampled,
                                                parameters: ParameterValues(["sigma": .double(4), "truncation": .choice("3"),
                                                                             "discretisation": .choice("sampled")]),
                                                settings: .standard, specimen: "step-edges", specimenOptions: .standard, pan: .zero,
                                                probe: probe, windowSize: n)
        let run = try await coordinator.render(RenderRequest(configuration: configuration, slot: .a, quality: .full, generation: 1,
                                                             kind: .display, traced: false))
        let gpu = try XCTUnwrap(run?.probe?.output)
        let window = StepEdgesGenerator().canvas(windowSize: n, margin: SpecimenGeometry.margin, options: .standard, text: nil).window(pan: .zero).image
        let cpu = try BlurReference.runCrop(GaussianOperator(), input: window, configuration.operatorRequest,
                                            region: PixelRegion(origin: probe, size: .square(1)), options: .parity)[0, 0]
        for ch in 0..<4 {
            let allowance = ParityTolerance.bilinear.allowance(reference: Double(cpu[ch]), scale: 1, bilinearPasses: 2)
            XCTAssertLessThanOrEqual(abs(gpu[ch] - Double(cpu[ch])), allowance, "channel \(ch): GPU \(gpu[ch]) CPU \(cpu[ch])")
        }
        XCTAssertEqual(run?.device.isSimulator, false)
    }

    /// MEASURED on this phone (requests/SKEL.md item 1): how a float is rounded when stored into rgba16Float, through a
    /// compute `write` and a render-target output. The M1 Max rounds toward zero; the A17 Pro's rule is printed here.
    func testHalfStoreRoundingIsConsistentAndReported() async throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
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
        let buffer = try XCTUnwrap(device.makeBuffer(bytes: values, length: n * 4, options: .storageModeShared))
        func texture(_ usage: MTLTextureUsage) throws -> any MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: n, height: 1, mipmapped: false)
            d.usage = usage; d.storageMode = .shared
            return try XCTUnwrap(device.makeTexture(descriptor: d))
        }
        let written = try texture([.shaderWrite, .shaderRead]), rendered = try texture([.renderTarget, .shaderRead])
        let compute = try await device.makeComputePipelineState(function: try XCTUnwrap(library.makeFunction(name: "skel_store_k")))
        let pd = MTLRenderPipelineDescriptor()
        pd.vertexFunction = library.makeFunction(name: "skel_store_vs"); pd.fragmentFunction = library.makeFunction(name: "skel_store_fs")
        pd.colorAttachments[0].pixelFormat = .rgba16Float
        let render = try await device.makeRenderPipelineState(descriptor: pd)
        let queue = try XCTUnwrap(device.makeCommandQueue()), cb = try XCTUnwrap(queue.makeCommandBuffer())
        let ce = try XCTUnwrap(cb.makeComputeCommandEncoder())
        ce.setComputePipelineState(compute); ce.setTexture(written, index: 0); ce.setBuffer(buffer, offset: 0, index: 0)
        ce.dispatchThreadgroups(MTLSize(width: n, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        ce.endEncoding()
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = rendered; rpd.colorAttachments[0].loadAction = .clear; rpd.colorAttachments[0].storeAction = .store
        let re = try XCTUnwrap(cb.makeRenderCommandEncoder(descriptor: rpd))
        re.setRenderPipelineState(render); re.setFragmentBuffer(buffer, offset: 0, index: 0)
        re.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); re.endEncoding()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in cb.addCompletedHandler { _ in c.resume() }; cb.commit() }
        func towardZero(_ v: Float) -> Float {
            let h = Float16(v)
            if abs(Float(h)) <= abs(v) || !h.isFinite { return Float(h) }
            return Float(v > 0 ? h.nextDown : h.nextUp)
        }
        func rule(_ t: any MTLTexture) -> String {
            var out = [SIMD4<Float16>](repeating: .zero, count: n)
            t.getBytes(&out, bytesPerRow: n * 8, from: MTLRegionMake2D(0, 0, n, 1), mipmapLevel: 0)
            let stored = out.map { Float($0.x) }
            if zip(stored, values).allSatisfy({ $0 == towardZero($1) }) { return "towardZero" }
            if zip(stored, values).allSatisfy({ $0 == Float(Float16($1)) }) { return "nearestEven" }
            return "mixed \(stored)"
        }
        let computeRule = rule(written), renderRule = rule(rendered)
        print("SKEL_HalfStoreRounding: \(device.name) stores fp16 by \(computeRule) (compute write) and \(renderRule) (render target)")
        XCTAssertEqual(computeRule, renderRule)
        XCTAssertFalse(computeRule.hasPrefix("mixed"), computeRule)
    }

    func testMetalSpecimenViewDrawableIsExactlyNByN() throws {
        let (device, library) = try library()
        let context = try GPUContext(device: device, library: library, manifest: ShaderManifest(files: [:], combinedSHA256: ""))
        let presenter = PresentRenderer(coordinator: RenderCoordinator(gpu: context, specimens: SpecimenStore()))
        let host = UIHostingController(rootView: MetalSpecimenView(renderer: presenter, windowPixels: 894).frame(width: 298, height: 298))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        func find(_ view: UIView) -> MTKView? { (view as? MTKView) ?? view.subviews.lazy.compactMap(find).first }
        // SwiftUI applies the window's traits (displayScale) in a later update pass: let it run.
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, find(host.view).map({ $0.contentScaleFactor != host.traitCollection.displayScale }) ?? true {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        let mtk = try XCTUnwrap(find(host.view), "MTKView in the hierarchy")
        XCTAssertEqual(host.traitCollection.displayScale, window.screen.scale)
        XCTAssertEqual(mtk.drawableSize, CGSize(width: 894, height: 894))
        XCTAssertFalse(mtk.autoResizeDrawable)
        XCTAssertEqual(mtk.contentScaleFactor, host.traitCollection.displayScale)
        XCTAssertEqual((mtk.layer as? CAMetalLayer)?.colorspace?.name, CGColorSpace.sRGB)
        XCTAssertEqual(mtk.colorPixelFormat, .bgra8Unorm)
        window.isHidden = true
    }
}
