import Foundation

// FROZEN — ARCHITECTURE.md §5.6. Test-image generator API (SPEC §11; implemented by TESTIMAGES).
// Procedural, deterministic, linear light, premultiplied; bit-identical on the Mac, the Simulator and the phone
// (except `text`, whose coverage mask the app renders with Core Text and hands in).

public struct SpecimenOptions: Sendable, Codable, Hashable {
    /// −2 … +6 EV, applied to light-carrying images before the blur AT RENDER TIME: the window pass multiplies by 2^EV
    /// (GPUContext.encodeWindowCopy) and BlurReference.run does the same before rounding. Canvases are always generated
    /// at 0 EV, so an EXPOSURE detent never regenerates or re-uploads a canvas (review fix E-10).
    public var exposureEV: Int
    /// Per-image choices by option key ("height": "0.20", "noise": "saltAndPepper", "period": "2", "orientation": "45").
    public var choices: [String: String]
    /// Overrides the image's fixed seed (photos and stochastic options only; built-ins keep their documented seed).
    public var seed: UInt32?
    public init(exposureEV: Int = 0, choices: [String: String] = [:], seed: UInt32? = nil) {
        self.exposureEV = exposureEV; self.choices = choices; self.seed = seed
    }
    public static let standard = SpecimenOptions()
    /// The options a canvas is generated and cached with: these options at 0 EV.
    public var canvasOptions: SpecimenOptions { var o = self; o.exposureEV = 0; return o }
}

public struct SpecimenDescriptor: Sendable, Codable, Hashable, Identifiable {
    public var id: SpecimenID
    /// Menu name under "Test image" ("Night City").
    public var menuName: String
    /// What it reveals (one line, the menu's secondary text).
    public var reveals: String
    public var isHDR: Bool
    /// Marked "HIGH-CONTRAST PATTERN" in the menu (WCAG 2.3.1, SPEC §11 rule 4).
    public var isHighContrastPattern: Bool
    public var supportsExposure: Bool
    /// Text is rendered by the app (Core Text) and handed in as a coverage mask.
    public var needsTextCoverage: Bool
    /// Moves only after an explicit Play (scene-motion, diffusion over time).
    public var animated: Bool
    /// Per-image options (menu items), keys used in `SpecimenOptions.choices`.
    public var options: [ParameterSpec]
    public init(id: SpecimenID, menuName: String, reveals: String, isHDR: Bool, isHighContrastPattern: Bool,
                supportsExposure: Bool, needsTextCoverage: Bool, animated: Bool, options: [ParameterSpec]) {
        self.id = id; self.menuName = menuName; self.reveals = reveals; self.isHDR = isHDR
        self.isHighContrastPattern = isHighContrastPattern; self.supportsExposure = supportsExposure
        self.needsTextCoverage = needsTextCoverage; self.animated = animated; self.options = options
    }
}

/// Coverage mask of the text lines (0…1), canvas-sized, rendered by the app with Core Text.
public struct TextCoverage: Sendable, Equatable {
    public var mask: ScalarBuffer
    public init(mask: ScalarBuffer) { self.mask = mask }
}

/// The geometry every specimen shares (SPEC §11 rule 2).
public enum SpecimenGeometry {
    /// Pan margin on every side of the window, in pixels.
    public static let margin = 256
    public static func canvasSide(windowSize n: Int) -> Int { n + 2 * margin }
    /// The window centre c = (⌊N/2⌋, ⌊N/2⌋) (447, 447) at N = 894.
    public static func centre(windowSize n: Int) -> PixelPoint { PixelPoint(x: n / 2, y: n / 2) }
}

/// A generated canvas: the window plus a pan margin on every side.
public struct SpecimenCanvas: Sendable, Equatable {
    public var id: SpecimenID
    public var options: SpecimenOptions
    public var windowSize: Int
    public var margin: Int
    /// (windowSize + 2·margin)², linear light, premultiplied.
    public var image: ImageBuffer
    /// Canvas-sized auxiliary buffers (depth, velocity, guide, mask, sub-frames), cropped together with the image.
    public var auxiliary: AuxiliaryInputs
    /// Default probe in window pixels, on the image's most informative feature.
    public var defaultProbe: PixelPoint
    /// Colour shown behind transparent pixels when presenting (linear, premultiplied).
    public var backdrop: SIMD4<Float>
    /// Engraved in the caption when not empty ("PHOTO · RESAMPLED ×0.31 (BOX)").
    public var caption: String?
    public init(id: SpecimenID, options: SpecimenOptions, windowSize: Int, margin: Int, image: ImageBuffer,
                auxiliary: AuxiliaryInputs, defaultProbe: PixelPoint, backdrop: SIMD4<Float>, caption: String? = nil) {
        self.id = id; self.options = options; self.windowSize = windowSize; self.margin = margin; self.image = image
        self.auxiliary = auxiliary; self.defaultProbe = defaultProbe; self.backdrop = backdrop; self.caption = caption
    }

    /// The N × N window at an integer pan offset (±margin), exactly as the GPU blit copies it, with cropped auxiliaries.
    public func window(pan: PixelPoint) -> OperatorContent {
        let region = PixelRegion(origin: PixelPoint(x: margin + pan.x, y: margin + pan.y), size: .square(windowSize))
        var aux = auxiliary
        func cropScalar(_ b: ScalarBuffer?) -> ScalarBuffer? {
            b.map { s in
                var v = [Float](repeating: 0, count: windowSize * windowSize)
                for y in 0..<windowSize { for x in 0..<windowSize {
                    let sx = Swift.min(Swift.max(region.origin.x + x, 0), s.width - 1)
                    let sy = Swift.min(Swift.max(region.origin.y + y, 0), s.height - 1)
                    v[y * windowSize + x] = s[sx, sy]
                } }
                return ScalarBuffer(width: windowSize, height: windowSize, values: v)
            }
        }
        aux.depth = cropScalar(auxiliary.depth)
        aux.mask = cropScalar(auxiliary.mask)
        aux.guide = auxiliary.guide?.crop(region)
        aux.subFrames = auxiliary.subFrames?.map { $0.crop(region) }
        if let vel = auxiliary.velocity {
            var v = [SIMD2<Float>](repeating: .zero, count: windowSize * windowSize)
            for y in 0..<windowSize { for x in 0..<windowSize {
                let sx = Swift.min(Swift.max(region.origin.x + x, 0), vel.width - 1)
                let sy = Swift.min(Swift.max(region.origin.y + y, 0), vel.height - 1)
                v[y * windowSize + x] = vel.values[sy * vel.width + sx]
            } }
            aux.velocity = VectorBuffer(width: windowSize, height: windowSize, values: v)
        }
        return OperatorContent(image: image.crop(region), auxiliary: aux)
    }
}

public protocol SpecimenGenerating: Sendable {
    var descriptor: SpecimenDescriptor { get }
    /// Deterministic: the same arguments give a bit-identical canvas on every platform. `text` is required when
    /// `descriptor.needsTextCoverage` (the app supplies it); generators must not import CoreText.
    func canvas(windowSize: Int, margin: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas
}
