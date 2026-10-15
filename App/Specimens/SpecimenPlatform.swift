import Foundation
import CoreGraphics
import CoreText
import ImageIO
import BlurCore

// OWNER: TESTIMAGES (frozen API, ARCHITECTURE §5.9 / AppContract/System). The platform half of the test images:
// • `textCoverage`: Core Text coverage of the four text lines of `text` (SPEC §11 #10), drawn exactly where BlurCore's
//   `TextSpecimenLayout` puts them, in the system font at 9, 12, 18 and 32 px, grey-scale anti-aliased, into a canvas-sized
//   mask. `material-backdrop` reuses its 18-px line. BlurCore stays Foundation-only.
// • `cgImage`: a linear premultiplied buffer as a half-float CGImage in extended linear sRGB (for SwiftUI views and the
//   system exhibits).
// • `photoCanvas`: PhotosPicker data decoded through the image's colour profile into linear premultiplied RGBA (ImageIO +
//   Core Graphics, EXIF orientation applied by exact quarter-turns and flips, no interpolation), centre-cropped, then
//   area-averaged to the canvas by BlurCore (`PhotoSpecimen`), engraved `PHOTO · RESAMPLED ×s (BOX)`.
public enum SpecimenPlatform {
    /// Core Text coverage of the four text lines at canvas size (SPEC §11 #10); BlurCore stays Foundation-only.
    @MainActor public static func textCoverage(canvasSide: Int, margin: Int, options: SpecimenOptions) -> TextCoverage {
        let n = canvasSide - 2 * margin
        let empty = TextCoverage(mask: ScalarBuffer(width: canvasSide, height: canvasSide, values: Array(repeating: 0, count: canvasSide * canvasSide)))
        guard n > 0, let gray = CGColorSpace(name: CGColorSpace.linearGray),
              let context = CGContext(data: nil, width: canvasSide, height: canvasSide, bitsPerComponent: 8, bytesPerRow: canvasSide,
                                      space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return empty }
        // Black ground, white glyphs: in a linear grey space without alpha the stored value IS the coverage.
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide))
        context.setShouldAntialias(true)
        context.setAllowsFontSmoothing(false)
        context.setShouldSmoothFonts(false)
        context.setAllowsFontSubpixelPositioning(true)
        context.setShouldSubpixelPositionFonts(false)                  // glyphs start on whole pixels: stems are repeatable
        let white = CGColor(gray: 1, alpha: 1)
        for line in TextSpecimenLayout.lines {
            let font = CTFontCreateUIFontForLanguage(.system, CGFloat(line.pixelSize), nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, CGFloat(line.pixelSize), nil)
            let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: white]
            guard let text = CFAttributedStringCreate(nil, line.text as CFString, attributes as CFDictionary) else { continue }
            let ctLine = CTLineCreateWithAttributedString(text)
            for right in [false, true] {
                let origin = TextSpecimenLayout.origin(of: line, rightHalf: right, windowSize: n, margin: margin)
                // Core Graphics is y up: canvas row b (y down) is CG y = side − b.
                context.textPosition = CGPoint(x: CGFloat(origin.x), y: CGFloat(canvasSide - origin.baseline))
                CTLineDraw(ctLine, context)
            }
        }
        guard let data = context.data else { return empty }
        let bytes = data.bindMemory(to: UInt8.self, capacity: canvasSide * canvasSide)
        // The first row in memory is the top row of the image (y down), the canvas's row 0.
        let values = (0..<(canvasSide * canvasSide)).map { Float(bytes[$0]) * (1.0 / 255.0) }
        return TextCoverage(mask: ScalarBuffer(width: canvasSide, height: canvasSide, values: values))
    }

    /// A CGImage of a linear premultiplied buffer in extended linear sRGB (for SwiftUI views and exhibits).
    public static func cgImage(_ buffer: ImageBuffer) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else { return nil }
        let halves = buffer.pixels.map { SIMD4<Float16>($0) }
        let data = halves.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
                                | CGBitmapInfo.byteOrder16Little.rawValue)
        return CGImage(width: buffer.width, height: buffer.height, bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: buffer.width * 8,
                       space: space, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// PhotosPicker data → linear rgba16Float canvas, centre-cropped and area-averaged (caption `PHOTO · RESAMPLED ×s (BOX)`).
    /// Returns nil when the data is not an image ImageIO can decode. Runs off the main actor (a detached task).
    public static func photoCanvas(from data: Data, windowSize: Int) async throws -> SpecimenCanvas? {
        try Task.checkCancellation()
        return await Task.detached(priority: .userInitiated) { () -> SpecimenCanvas? in
            withLinearSquare(of: data) { side, halves in
                PhotoSpecimen.canvas(cropSide: side, windowSize: windowSize) { j in
                    let row = halves + j * side * 4
                    return (0..<side).map { i in
                        SIMD4<Float>(Float(row[4 * i]), Float(row[4 * i + 1]), Float(row[4 * i + 2]), Float(row[4 * i + 3]))
                    }
                }
            }
        }.value
    }

    /// Decodes `data` (any ImageIO format) into the centre-cropped, EXIF-oriented square as linear premultiplied half floats
    /// in extended linear sRGB, and hands `body` the side and the pixels (row-major RGBA Float16, top row first; valid only
    /// inside `body`). Returns nil when ImageIO cannot decode the data.
    static func withLinearSquare<T>(of data: Data, _ body: (Int, UnsafePointer<Float16>) -> T) -> T? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldAllowFloat: true] as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let w = image.width, h = image.height
        let quarterTurn = (5...8).contains(orientation)
        let ow = quarterTurn ? h : w, oh = quarterTurn ? w : h            // the oriented (displayed) size
        let crop = PhotoSpecimen.centreCrop(width: ow, height: oh)
        let side = crop.side
        guard side > 0 else { return nil }
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 16, bytesPerRow: side * 8, space: space,
                                      bitmapInfo: info) else { return nil }
        context.interpolationQuality = .none
        context.clear(CGRect(x: 0, y: 0, width: side, height: side))
        // Oriented space is y up with the oriented image filling [0, ow] × [0, oh]; the context shows the crop square.
        context.translateBy(x: CGFloat(-crop.x), y: CGFloat(-(oh - crop.y - side)))
        context.concatenate(orientationTransform(orientation, width: CGFloat(w), height: CGFloat(h)))
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let base = context.data else { return nil }
        return body(side, UnsafePointer(base.bindMemory(to: Float16.self, capacity: side * side * 4)))
    }

    /// The exact transform (quarter turns and flips only) that maps the raw w × h image to its EXIF-oriented position in a
    /// y-up space (orientation 1…8, CGImagePropertyOrientation).
    static func orientationTransform(_ orientation: Int, width w: CGFloat, height h: CGFloat) -> CGAffineTransform {
        switch orientation {
        case 2: return CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0)            // mirrored
        case 3: return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)           // rotated 180°
        case 4: return CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)            // flipped vertically
        case 5: return CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: h, ty: w)           // transposed
        case 6: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)            // displayed rotated 90° clockwise
        case 7: return CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)             // transverse
        case 8: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)            // displayed rotated 90° counter-clockwise
        default: return .identity
        }
    }
}
