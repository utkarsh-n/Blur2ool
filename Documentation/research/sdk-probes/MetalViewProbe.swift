// Swift 6 strict-concurrency probe: SwiftUI + MTKView (UIViewRepresentable) + compute blur + GPU timing.
import SwiftUI
import MetalKit
import Observation

@MainActor @Observable
final class GPUStats {
    var lastGPUms: Double = 0
}

/// Renderer: main-actor isolated (MTKView and MTKViewDelegate methods are NS_SWIFT_UI_ACTOR).
@MainActor
final class BlurRenderer: NSObject, MTKViewDelegate {
    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let pipeline: any MTLComputePipelineState
    let stats: GPUStats
    var sigma: Float = 4

    init?(stats: GPUStats) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        let src = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void copyKernel(texture2d<half, access::read> src [[texture(0)]],
                               texture2d<half, access::write> dst [[texture(1)]],
                               uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
            dst.write(src.read(gid), gid);
        }
        """
        guard let lib = try? device.makeLibrary(source: src, options: nil),
              let fn = lib.makeFunction(name: "copyKernel"),
              let pso = try? device.makeComputePipelineState(function: fn) else { return nil }
        self.device = device; self.queue = queue; self.pipeline = pso; self.stats = stats
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let cb = queue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder() else { return }
        enc.setComputePipelineState(pipeline)
        enc.setTexture(drawable.texture, index: 0)
        enc.setTexture(drawable.texture, index: 1)
        let w = pipeline.threadExecutionWidth
        let h = max(1, min(16, pipeline.maxTotalThreadsPerThreadgroup / w))
        enc.dispatchThreads(MTLSize(width: drawable.texture.width, height: drawable.texture.height, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1))
        enc.endEncoding()
        let stats = self.stats
        // Completion handler runs on a Metal-owned thread: it is @Sendable; read times there, hop to MainActor.
        cb.addCompletedHandler { buffer in
            let ms = (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
            Task { @MainActor in stats.lastGPUms = ms }
        }
        cb.present(drawable)
        cb.commit()
    }
}

struct MetalBlurView: UIViewRepresentable {
    let stats: GPUStats
    var sigma: Float

    func makeCoordinator() -> BlurRenderer? { BlurRenderer(stats: stats) }

    func makeUIView(context: Context) -> MTKView {
        let v = MTKView(frame: .zero, device: context.coordinator?.device)
        v.framebufferOnly = false          // drawable texture is written by a compute kernel
        v.colorPixelFormat = .bgra8Unorm
        v.enableSetNeedsDisplay = true     // draw on demand, not every frame
        v.isPaused = true
        v.delegate = context.coordinator
        return v
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator?.sigma = sigma
        uiView.setNeedsDisplay()
    }
}

struct ProbeRoot: View {
    @State private var stats = GPUStats()
    @State private var sigma: Float = 4
    var body: some View {
        VStack {
            MetalBlurView(stats: stats, sigma: sigma)
            Slider(value: $sigma, in: 0...64)
            Text(String(format: "%.3f ms", stats.lastGPUms))
        }
    }
}

@main
struct ProbeApp: App {
    var body: some Scene { WindowGroup { ProbeRoot() } }
}
