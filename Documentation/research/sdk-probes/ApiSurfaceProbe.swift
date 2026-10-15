// Swift 6 typecheck of every SDK API the Blur2ool plan relies on (iOS 27 simulator + device).
import SwiftUI
import Charts
import PhotosUI
import CoreImage
import CoreImage.CIFilterBuiltins
import MetalPerformanceShaders
import ImageIO

enum Layer: String, CaseIterable, Hashable { case wysiwyg, api, math, kernel, gpu }

struct SurfaceProbe: View {
    @State private var layer: Layer = .wysiwyg
    @State private var pick: PhotosPickerItem?
    @State private var cg: CGImage?
    @State private var pose: Chart3DPose = .default
    var sigma: Double = 4

    var body: some View {
        VStack {
            Picker("Layer", selection: $layer) {
                ForEach(Layer.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.tabs)                                   // iOS 27

            // 1D kernel / frequency response as a function plot (iOS 18)
            Chart {
                LinePlot(x: "x", y: "g(x)", domain: -12...12) { x in exp(-x * x / (2 * 16)) / (4 * 2.5066) }
                RuleMark(x: .value("σ", 4))
            }
            .frame(height: 120)

            // 2D kernel as a surface (iOS 26)
            Chart3D {
                SurfacePlot(x: "x", y: "w", z: "y") { x, z in exp(-(x * x + z * z) / 8) }
                    .foregroundStyle(.heightBased)
            }
            .chart3DPose($pose)
            .chart3DCameraProjection(.perspective)
            .frame(height: 200)

            Image(systemName: "circle.grid.cross")
                .blur(radius: sigma)
                .layerEffect(ShaderLibrary.gaussianH(.float(Float(sigma))), maxSampleOffset: CGSize(width: 3 * sigma, height: 0))
                .glassEffect(.regular.tint(.orange), in: .rect(cornerRadius: 0))

            PhotosPicker(selection: $pick, matching: .images) { Text("Your photo") }
        }
        .task(id: pick) {
            guard let pick, let data = try? await pick.loadTransferable(type: Data.self) else { return }
            cg = Self.downsample(data, maxPixel: 2048)
        }
    }

    nonisolated static func downsample(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}

/// Live PSF measurement of SwiftUI's own blur: render a 1-pt line through `.blur` offscreen in float.
@MainActor func measureSwiftUIBlurLSF(radius: CGFloat) -> CGImage? {
    let view = ZStack { Color.clear; Rectangle().fill(.white).frame(width: 1) }
        .frame(width: 257, height: 257)
        .blur(radius: radius)
    let r = ImageRenderer(content: view)
    r.scale = 1
    r.colorMode = .extendedLinear
    return r.cgImage
}

/// Core Image and MPS vendor blurs.
func vendorBlurs(_ input: CIImage, device: any MTLDevice) -> [CIImage?] {
    let g = CIFilter.gaussianBlur(); g.inputImage = input; g.radius = 8
    let b = CIFilter.boxBlur(); b.inputImage = input; b.radius = 8
    let d = CIFilter.discBlur(); d.inputImage = input; d.radius = 8
    let m = CIFilter.motionBlur(); m.inputImage = input; m.radius = 8; m.angle = 0.5
    let z = CIFilter.zoomBlur(); z.inputImage = input; z.center = CGPoint(x: 128, y: 128); z.amount = 10
    let k = CIFilter.bokehBlur(); k.inputImage = input; k.radius = 8; k.ringAmount = 0.2; k.ringSize = 0.1; k.softness = 1
    let v = CIFilter.maskedVariableBlur(); v.inputImage = input; v.mask = input; v.radius = 8
    let md = CIFilter.median(); md.inputImage = input
    let mg = CIFilter.morphologyGradient(); mg.inputImage = input; mg.radius = 4
    _ = MPSImageGaussianBlur(device: device, sigma: 4)
    _ = MPSImageBox(device: device, kernelWidth: 9, kernelHeight: 9)
    _ = MPSImageTent(device: device, kernelWidth: 9, kernelHeight: 9)
    _ = MPSImageMedian(device: device, kernelDiameter: 5)
    return [g.outputImage, b.outputImage, d.outputImage, m.outputImage, z.outputImage, k.outputImage, v.outputImage, md.outputImage, mg.outputImage]
}
