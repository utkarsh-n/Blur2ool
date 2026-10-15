import XCTest
import CryptoKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Blur2ool
import BlurCore

// OWNER: TESTIMAGES. Phone-side tests (ARCHITECTURE §11.3 "Platform identity"; review fix E-22). Run under the simulator hold
// on the physical iPhone: `Tools/build.sh device-build-for-testing`, then `device-session "test --area TESTIMAGES"`.
// 1. Every built-in canvas hashes on the phone exactly as on the Mac (TESTIMAGESCanvasHashes.swift, recorded by CORE).
// 2. SpecimenPlatform's Core Text coverage renders a non-empty glyph mask where TextSpecimenLayout puts the lines, and the
//    text image's default probe lands on a stem.
// 3. cgImage round-trips linear values; photoCanvas decodes through the colour profile, applies EXIF orientation and
//    area-averages with the honest caption.

func TESTIMAGES_appSHA256(_ canvas: SpecimenCanvas) -> String {
    var hasher = SHA256()
    canvas.forEachCanonicalChunk { hasher.update(bufferPointer: $0) }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

final class TESTIMAGES_CanvasHashTests: XCTestCase {
    func testPhoneCanvasHashesEqualTheMacHashes() {
        XCTAssertEqual(TESTIMAGES_macCanvasHashes.count, 44, "22 images × N = 894, 810")
        var mismatches: [String] = []
        for n in [894, 810] {
            for generator in SpecimenRegistry.generators {
                let key = "\(generator.descriptor.id.rawValue)@\(n)"
                let canvas = generator.canvas(windowSize: n, margin: SpecimenGeometry.margin, options: .standard, text: nil)
                let sha = TESTIMAGES_appSHA256(canvas)
                print("TESTIMAGES_PHONE_HASH \(key) \(sha)")
                if TESTIMAGES_macCanvasHashes[key] != sha {
                    mismatches.append("\(key): phone \(sha), Mac \(TESTIMAGES_macCanvasHashes[key] ?? "missing")")
                }
            }
        }
        XCTAssertEqual(SpecimenRegistry.generators.count, 22)
        XCTAssertTrue(mismatches.isEmpty, "canvases differ between the phone and the Mac:\n" + mismatches.joined(separator: "\n"))
    }
}

@MainActor
final class TESTIMAGES_PlatformTests: XCTestCase {
    private let n = 894
    private var side: Int { n + 2 * SpecimenGeometry.margin }

    func testCoreTextCoverageRendersAGlyphMask() throws {
        let coverage = SpecimenPlatform.textCoverage(canvasSide: side, margin: SpecimenGeometry.margin, options: .standard)
        let mask = coverage.mask
        XCTAssertEqual(mask.width, side)
        XCTAssertEqual(mask.height, side)
        let inked = mask.values.filter { $0 >= 0.5 }.count
        XCTAssertGreaterThan(inked, 2_000, "glyph pixels with coverage ≥ 0.5")
        XCTAssertEqual(mask.values.max(), 1)
        XCTAssertTrue(mask.values.contains { $0 > 0.05 && $0 < 0.95 }, "grey-scale anti-aliasing")
        // Glyphs sit on every line, in both halves, and nowhere far from the text block.
        let c = SpecimenGeometry.centre(windowSize: n), m = SpecimenGeometry.margin
        for line in TextSpecimenLayout.lines {
            for start in [TextSpecimenLayout.leftStart, TextSpecimenLayout.rightStart] {
                var ink: Float = 0
                for y in (c.y + line.baseline - Int(line.pixelSize))...(c.y + line.baseline + 2) {
                    for x in (c.x + start)..<(c.x + start + 120) { ink += mask[x + m, y + m] }
                }
                XCTAssertGreaterThan(ink, Float(line.pixelSize), "line \(line.pixelSize) px at \(start)")
            }
        }
        var stray: Float = 0
        for y in 0..<(c.y - 160 + m) { for x in 0..<side { stray += mask[x, y] } }
        XCTAssertEqual(stray, 0, "no ink above the text block")

        // The text image uses it: white on black left, black on white right, probe on the first stem of the 12-px line.
        let canvas = TextSpecimenGenerator().canvas(windowSize: n, margin: m, options: .standard, text: coverage)
        XCTAssertNil(canvas.caption)
        let window = canvas.window(pan: .zero).image
        let probe = canvas.defaultProbe
        XCTAssertGreaterThanOrEqual(window[probe.x, probe.y].x, 0.5, "probe on a stem: \(probe)")
        let line = TextSpecimenLayout.lines[TextSpecimenLayout.probeLine]
        XCTAssertTrue((c.y + line.baseline - 12...c.y + line.baseline + 2).contains(probe.y))
        XCTAssertLessThan(probe.x, c.x + TextSpecimenLayout.leftStart + 12)
        let material = MaterialBackdropGenerator().canvas(windowSize: n, margin: m, options: .standard, text: coverage)
        XCTAssertNil(material.caption)
        let band = material.window(pan: .zero).image
        var dark = 0
        for y in (c.y - 40)..<(c.y + 40) { for x in 0..<c.x where band[x, y].x < 0.5 { dark += 1 } }
        XCTAssertGreaterThan(dark, 200, "the 18-px line is drawn black on white in the middle band")
    }

    func testCGImageCarriesLinearValues() throws {
        var buffer = ImageBuffer(width: 4, height: 2, fill: SIMD4(0.25, 0.5, 2.0, 1))
        buffer[1, 1] = SIMD4(0.1, 0, 0, 0.5)
        let image = try XCTUnwrap(SpecimenPlatform.cgImage(buffer))
        XCTAssertEqual(image.width, 4)
        XCTAssertEqual(image.bitsPerComponent, 16)
        XCTAssertEqual(image.colorSpace?.name, CGColorSpace.extendedLinearSRGB)
        let bytes = try XCTUnwrap(image.dataProvider?.data as Data?)
        let halves = bytes.withUnsafeBytes { Array($0.bindMemory(to: Float16.self)) }
        XCTAssertEqual(Float(halves[0]), 0.25)
        XCTAssertEqual(Float(halves[2]), 2.0, "HDR values survive")
        XCTAssertEqual(Float(halves[(1 * 4 + 1) * 4 + 3]), 0.5)
    }

    func testPhotoCanvasDecodesToLinearAndAreaAverages() async throws {
        let data = try TESTIMAGES_imageData(width: 64, height: 48) { _, _ in (128, 64, 200) }
        let decoded = try await SpecimenPlatform.photoCanvas(from: data, windowSize: 128)
        let canvas = try XCTUnwrap(decoded)
        XCTAssertEqual(canvas.id, "photo")
        XCTAssertEqual(canvas.image.width, 640)
        XCTAssertEqual(canvas.caption, "PHOTO · RESAMPLED ×13.33 (BOX)")
        let p = canvas.image[320, 320]
        XCTAssertEqual(Double(p.x), SRGB.decode(128.0 / 255), accuracy: 2e-3)
        XCTAssertEqual(Double(p.y), SRGB.decode(64.0 / 255), accuracy: 2e-3)
        XCTAssertEqual(Double(p.z), SRGB.decode(200.0 / 255), accuracy: 2e-3)
        XCTAssertEqual(p.w, 1, accuracy: 1e-3)
        let garbage = try await SpecimenPlatform.photoCanvas(from: Data("not an image".utf8), windowSize: 128)
        XCTAssertNil(garbage)
    }

    func testPhotoCanvasAppliesExifOrientation() async throws {
        // Raw image: red left half, blue right half. Orientation 1 keeps it; orientation 6 displays it turned 90° clockwise,
        // so red ends up on top.
        let raw: (Int, Int) -> (UInt8, UInt8, UInt8) = { x, _ in x < 20 ? (255, 0, 0) : (0, 0, 255) }
        let uprightData = try TESTIMAGES_imageData(width: 40, height: 20, orientation: 1, raw)
        let uprightCanvas = try await SpecimenPlatform.photoCanvas(from: uprightData, windowSize: 128)
        let upright = try XCTUnwrap(uprightCanvas)
        XCTAssertGreaterThan(upright.image[100, 320].x, 0.9)
        XCTAssertGreaterThan(upright.image[540, 320].z, 0.9)
        let turnedData = try TESTIMAGES_imageData(width: 40, height: 20, orientation: 6, raw)
        let turnedCanvas = try await SpecimenPlatform.photoCanvas(from: turnedData, windowSize: 128)
        let turned = try XCTUnwrap(turnedCanvas)
        XCTAssertGreaterThan(turned.image[320, 100].x, 0.9, "red on top")
        XCTAssertGreaterThan(turned.image[320, 540].z, 0.9, "blue at the bottom")
    }
}

/// An 8-bit sRGB TIFF (lossless, carries the EXIF orientation tag) of `pixel(x, y)`.
func TESTIMAGES_imageData(width: Int, height: Int, orientation: Int = 1, _ pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) throws -> Data {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height { for x in 0..<width {
        let (r, g, b) = pixel(x, y), k = (y * width + x) * 4
        bytes[k] = r; bytes[k + 1] = g; bytes[k + 2] = b
    } }
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
    let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let out = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(out, UTType.tiff.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return out as Data
}
