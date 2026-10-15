import Foundation
import Metal
import Testing
@testable import BlurCore
@testable import BlurGPU

// OWNER: TESTIMAGES. The canvases on the Mac GPU (ARCHITECTURE §4.1, §5.6): the fp16 canvas texture, the pan (a blit of the
// N × N region at an integer offset) and EXPOSURE at render time (`b2_common_window_fs`, × 2^EV) give exactly the CPU's
// `SpecimenCanvas.window(pan:)` rounded to fp16 and scaled, for every built-in image; the brightest Night City light at
// +6 EV (1,000 × 64 = 64,000) stays finite in rgba16Float.

@MainActor
func TESTIMAGES_gpuContext() throws -> GPUContext? {
    guard let device = MTLCreateSystemDefaultDevice() else { return nil }
    let compiled = try ParityRunner.compileLibrary(device: device, shaderDirectory: shaderDirectory())
    return try GPUContext(device: device, library: compiled.library, manifest: compiled.manifest, recordsDispatches: true)
}

@Suite(.serialized) struct TESTIMAGES_GPUWindow {
    /// The GPU window (blit at 0 EV, render pass × 2^EV otherwise) equals the CPU window, fp16-rounded and scaled, bit for bit.
    @MainActor @Test func windowCopyAndExposureMatchTheCPU() async throws {
        guard let context = try TESTIMAGES_gpuContext() else { return }
        try await context.prepareCommonPipelines()
        let n = 128
        for generator in SpecimenRegistry.generators {
            let d = generator.descriptor
            let canvas = generator.canvas(windowSize: n, margin: SpecimenGeometry.margin, options: .standard, text: nil)
            let texture = try await context.upload(HalfImageData(canvas.image), roles: [.read])
            let evs = d.supportsExposure ? [0, -2, 6] : [0]
            for pan in [PixelPoint.zero, PixelPoint(x: 256, y: -256), PixelPoint(x: -97, y: 31)] {
                for ev in evs {
                    let out = try context.texture(TextureSpec(width: n, height: n, roles: [.read, .renderTarget]))
                    let recorder = GPUCommandRecorder(context: context, label: "window \(d.id) \(ev)")
                    try context.encodeWindowCopy(canvas: texture, margin: canvas.margin, pan: pan, size: n, exposureEV: ev,
                                                 destination: out, recorder: recorder)
                    _ = await recorder.commitAndWait()
                    let gpu = try await context.readTexels(out, region: PixelRegion(origin: .zero, size: .square(n)))
                    let cpu = canvas.window(pan: pan).image.roundedToHalf().scaled(by: Float(1 << (ev + 2)) / 4).roundedToHalf()
                    let differing = zip(gpu, cpu.pixels).filter { $0.0 != $0.1 }.count
                    #expect(differing == 0, "\(d.id) pan \(pan) \(ev) EV: \(differing) texels differ")
                    context.recycle(out, spec: TextureSpec(width: n, height: n, roles: [.read, .renderTarget]))
                }
            }
            context.recycle(texture, spec: TextureSpec(width: canvas.image.width, height: canvas.image.height, roles: [.read]))
        }
    }

    /// Night City at N = 894 and +6 EV: the brightest light (≤ 1,000 at 0 EV) is finite after the window pass.
    @MainActor @Test func brightestLightSurvivesSixStops() async throws {
        guard let context = try TESTIMAGES_gpuContext() else { return }
        try await context.prepareCommonPipelines()
        let n = 894
        let canvas = NightCityGenerator().canvas(windowSize: n, margin: SpecimenGeometry.margin, options: .standard, text: nil)
        let texture = try await context.upload(HalfImageData(canvas.image), roles: [.read])
        let out = try context.texture(TextureSpec(width: n, height: n, roles: [.read, .renderTarget]))
        let recorder = GPUCommandRecorder(context: context, label: "night city +6 EV")
        try context.encodeWindowCopy(canvas: texture, margin: canvas.margin, pan: .zero, size: n, exposureEV: 6, destination: out,
                                     recorder: recorder)
        _ = await recorder.commitAndWait()
        let texels = try await context.readTexels(out, region: PixelRegion(origin: .zero, size: .square(n)))
        let peak = texels.map { Swift.max($0.x, Swift.max($0.y, $0.z)) }.max() ?? 0
        let cpuPeak = canvas.window(pan: .zero).image.pixels.map { Swift.max($0.x, Swift.max($0.y, $0.z)) }.max() ?? 0
        print("TESTIMAGES_GPU Night City peak at +6 EV: \(peak) (CPU 0 EV peak \(cpuPeak))")
        #expect(peak.isFinite && peak <= 65_504 && peak == HalfFloat.round(HalfFloat.round(cpuPeak) * 64))
        let c = SpecimenGeometry.centre(windowSize: n)
        let reference = texels[c.y * n + c.x]
        print("TESTIMAGES_GPU reference light at +6 EV: \(reference)")
        #expect(reference.x == 6400 && reference.y == 6400 && reference.z == 6400)          // the reference light, 100 × 2^6
        // (The frozen window pass also multiplies alpha by 2^EV: requests/TESTIMAGES.md item 1.)
    }
}
