import Foundation
import Metal
import CoreImage
import CoreImage.CIFilterBuiltins
import BlurCore

// OWNER: APPLE-TWINS. The Core Image twins. One CIContext per GPUContext, created on our command queue with Core Image's
// default working space (extended linear sRGB, half-float working format): the API's own behaviour, so it blends in
// linear light (CAL §5.2: stripes 0.735 for every filter). The window texture is tagged extended linear sRGB on the way
// in and out, so no colour conversion happens around the blur.
//
// Orientation (MEASURED on the Mac, progress-APPLE-TWINS.md): CIImage(mtlTexture:) maps texture row 0 to CI y = 0 and a
// CIRenderDestination writes CI y = 0 to row 0, i.e. CI would see the window upside down. The input is therefore
// `oriented(.downMirrored)` and the destination `isFlipped`, which keeps the round trip the identity while giving CI the
// window the right way up: `inputCenter` is in CI's bottom-left coordinates and `inputAngle` turns counter-clockwise on
// screen, as Core Image documents. Past the extent CI samples transparent black (its default border); the output is
// cropped back to the window, so borders darken exactly as they do in an app using the filter.

extension AppleTwinRunner {
    static let linearSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) ?? CGColorSpaceCreateDeviceRGB()

    func coreImageContext(_ context: GPUContext) -> CIContext {
        let key = ObjectIdentifier(context)
        if let cached = coreImageCache, cached.key == key { return cached.context }
        let ci = CIContext(mtlCommandQueue: context.queue, options: [.cacheIntermediates: false, .name: "Blur2ool Apple twins"])
        coreImageCache = (key, ci)
        return ci
    }

    /// The window as Core Image sees it: linear, right way up, optionally clamped.
    func coreImageInput(_ texture: any MTLTexture, clamp: Bool) throws -> CIImage {
        guard let raw = CIImage(mtlTexture: texture, options: [.colorSpace: AppleTwinRunner.linearSpace]) else {
            throw GPUError.unsupported("Core Image could not wrap a \(texture.width)×\(texture.height) texture")
        }
        let upright = raw.oriented(.downMirrored)
        return clamp ? upright.clampedToExtent() : upright
    }

    /// The CIMaskedVariableBlur mask over `extent` (CI coordinates, y up): a texture's green channel, or `options.mask`.
    func coreImageMask(_ mask: (any MTLTexture)?, options: AppleTwinOptions, extent: CGRect) throws -> (image: CIImage, text: String) {
        if let mask {
            return (try coreImageInput(mask, clamp: true).cropped(to: extent), "mask texture \(mask.width)×\(mask.height)")
        }
        let space = AppleTwinRunner.linearSpace
        func grey(_ v: Double) -> CIColor {
            let c = CGFloat(Swift.min(Swift.max(v, 0), 1))
            return CIColor(red: c, green: c, blue: c, alpha: 1, colorSpace: space) ?? CIColor(red: c, green: c, blue: c)
        }
        switch options.mask {
        case .uniform(let v):
            return (CIImage(color: grey(v)).cropped(to: extent), "uniform mask \(AppleTwinRunner.number(v))")
        case .verticalRamp(let start, let end):
            let gradient = CIFilter.linearGradient()
            // Fractions are measured from the window's top; CI's y grows upwards from the bottom edge.
            gradient.point0 = CGPoint(x: 0, y: extent.height * (1 - start))
            gradient.point1 = CGPoint(x: 0, y: extent.height * (1 - Swift.max(end, start + 1e-6)))
            gradient.color0 = grey(0)
            gradient.color1 = grey(1)
            guard let image = gradient.outputImage else { throw GPUError.unsupported("CILinearGradient produced no mask") }
            return (image.cropped(to: extent), "ramp mask 0 at \(AppleTwinRunner.number(start * 100)) % → 1 at \(AppleTwinRunner.number(end * 100)) % of the height")
        }
    }

    /// The filter graph for one subject, with the call text that describes it exactly.
    func coreImageFilter(_ subject: CalibrationSubject, parameter p: Double, options: AppleTwinOptions, mask: (any MTLTexture)?,
                         input: CIImage, extent: CGRect) throws -> (image: CIImage, call: String) {
        let r = Float(p), rText = AppleTwinRunner.number(p)
        let output: CIImage?, call: String
        switch subject {
        case .ciGaussianBlur:
            let f = CIFilter.gaussianBlur(); f.inputImage = input; f.radius = r
            output = f.outputImage; call = "CIFilter.gaussianBlur() · radius \(rText)"
        case .ciBoxBlur:
            let f = CIFilter.boxBlur(); f.inputImage = input; f.radius = r
            output = f.outputImage; call = "CIFilter.boxBlur() · radius \(rText)"
        case .ciDiscBlur:
            let f = CIFilter.discBlur(); f.inputImage = input; f.radius = r
            output = f.outputImage; call = "CIFilter.discBlur() · radius \(rText)"
        case .ciBokehBlur:
            let f = CIFilter.bokehBlur(); f.inputImage = input; f.radius = r
            output = f.outputImage
            call = "CIFilter.bokehBlur() · radius \(rText) · ringAmount \(AppleTwinRunner.number(Double(f.ringAmount))) · ringSize \(AppleTwinRunner.number(Double(f.ringSize))) · softness \(AppleTwinRunner.number(Double(f.softness)))"
        case .ciMotionBlur:
            let f = CIFilter.motionBlur(); f.inputImage = input; f.radius = r; f.angle = Float(options.angleRadians)
            output = f.outputImage
            call = "CIFilter.motionBlur() · radius \(rText) · angle \(AppleTwinRunner.number(options.angleRadians)) rad"
        case .ciZoomBlur:
            let centre = options.centre ?? SIMD2(Double(extent.width) / 2, Double(extent.height) / 2)
            let ciCentre = CGPoint(x: centre.x, y: Double(extent.height) - centre.y)
            let f = CIFilter.zoomBlur(); f.inputImage = input; f.amount = r; f.center = ciCentre
            output = f.outputImage
            call = "CIFilter.zoomBlur() · amount \(rText) · center (\(AppleTwinRunner.number(Double(ciCentre.x))), \(AppleTwinRunner.number(Double(ciCentre.y))))"
        case .ciMaskedVariableBlur:
            let m = try coreImageMask(mask, options: options, extent: extent)
            let f = CIFilter.maskedVariableBlur(); f.inputImage = input; f.radius = r; f.mask = m.image
            output = f.outputImage; call = "CIFilter.maskedVariableBlur() · radius \(rText) · \(m.text)"
        default:
            throw GPUError.unsupported("\(subject.title) is not a Core Image twin")
        }
        guard let image = output else { throw GPUError.unsupported("\(subject.title) produced no output image") }
        return (image.cropped(to: extent), call)
    }

    func runCoreImage(_ subject: CalibrationSubject, parameter: Double, options: AppleTwinOptions, mask: (any MTLTexture)?,
                      input: any MTLTexture, output: any MTLTexture, context: GPUContext) async throws -> AppleTwinRunReport {
        let ci = coreImageContext(context)
        let extent = CGRect(x: 0, y: 0, width: input.width, height: input.height)
        let source = try coreImageInput(input, clamp: options.coreImageClampToExtent)
        let graph = try coreImageFilter(subject, parameter: parameter, options: options, mask: mask, input: source, extent: extent)
        let target = try writableTarget(for: output, context: context)
        let cb = try makeCommandBuffer(context, label: "Apple twin · \(subject.title)")
        let destination = CIRenderDestination(mtlTexture: target.texture, commandBuffer: cb)
        destination.isFlipped = true
        destination.colorSpace = AppleTwinRunner.linearSpace
        destination.alphaMode = .premultiplied
        do { _ = try ci.startTask(toRender: graph.image, to: destination) }
        catch { throw GPUError.commandBufferFailed("Core Image \(subject.title): \(error)") }
        if target.scratch != nil { try encodeCopy(from: target.texture, to: output, commandBuffer: cb) }
        let ms = try await commitChecked(cb, context: context)
        if let spec = target.scratch { context.recycle(target.texture, spec: spec) }
        var notes = ["CIContext default working space (extended linear sRGB, half float); window tagged extended linear sRGB in and out"]
        notes.append(options.coreImageClampToExtent ? "input.clampedToExtent(): borders clamp"
                                                    : "Core Image's own border: transparent black past the window")
        return AppleTwinRunReport(subject: subject, parameter: parameter,
                                  call: graph.call + (options.coreImageClampToExtent ? " · input.clampedToExtent()" : ""),
                                  size: ImageSize(width: input.width, height: input.height), gpuMilliseconds: ms,
                                  cpuMilliseconds: nil, clippedTexels: 0, notes: notes)
    }
}
