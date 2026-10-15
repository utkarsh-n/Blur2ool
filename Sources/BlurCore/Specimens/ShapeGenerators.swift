import Foundation

// OWNER: TESTIMAGES. Test images with shapes, text and auxiliary buffers (SPEC §11 #10, #13, #16, #20, #21). Text coverage
// comes from the app (`SpecimenPlatform.textCoverage`, Core Text) so BlurCore stays Foundation-only; without it the images
// are still generated (deterministically) and the caption says that the text is missing.

// MARK: - Text layout (shared with the app's Core Text renderer)

/// Where the four text lines of `text` sit (SPEC §11 #10). The app draws exactly these strings, in the system font at these
/// pixel sizes, with these baselines, into the canvas-sized coverage mask; both halves carry every line.
public enum TextSpecimenLayout {
    public struct Line: Sendable, Hashable {
        /// Font size in pixels (the coverage mask is drawn at 1 unit = 1 px).
        public var pixelSize: Double
        /// Blur2ool's own sentence.
        public var text: String
        /// Baseline row relative to c.y (window pixels, y down).
        public var baseline: Int
        public init(pixelSize: Double, text: String, baseline: Int) { self.pixelSize = pixelSize; self.text = text; self.baseline = baseline }
    }
    public static let lines: [Line] = [
        Line(pixelSize: 9, text: "Blur is an average of light. Every pixel asks its neighbours.", baseline: -110),
        Line(pixelSize: 12, text: "Blur is an average of light.", baseline: -70),
        Line(pixelSize: 18, text: "Edges become ramps.", baseline: -20),
        Line(pixelSize: 32, text: "Light spreads.", baseline: 50),
    ]
    /// Start of every line in the left (white-on-black) half and in the right (black-on-white) half, relative to c.x.
    public static let leftStart = -380
    public static let rightStart = 24
    /// The 12-px line carries the default probe (its first stem).
    public static let probeLine = 1
    /// The 18-px line is the one text line of `material-backdrop`.
    public static let backdropLine = 2

    /// Canvas pixel of the start of `line`'s baseline in a half (for the renderer): x, baseline y.
    public static func origin(of line: Line, rightHalf: Bool, windowSize n: Int, margin m: Int) -> (x: Int, baseline: Int) {
        let c = SpecimenGeometry.centre(windowSize: n)
        return (c.x + (rightHalf ? rightStart : leftStart) + m, c.y + line.baseline + m)
    }
}

/// `text` · Text: four lines (9, 12, 18 and 32 px) white-on-black in the left half and black-on-white in the right half;
/// option noise: none · salt-and-pepper (0–30 %, seed 3) · Gaussian σ 0.05 (seed 3).
public struct TextSpecimenGenerator: SpecimenGenerating {
    public init() {}
    public static let id: SpecimenID = "text"
    public static let seed: UInt32 = 3
    public var descriptor: SpecimenDescriptor {
        SpecimenDescriptor(id: Self.id, menuName: "Text",
                           reveals: "legibility; doubled strokes (camera shake); halos (USM); rank vs average on impulses",
                           isHDR: false, isHighContrastPattern: false, supportsExposure: false, needsTextCoverage: true,
                           animated: false,
                           options: [SpecimenOptionSpec.choice("noise", "NOISE", spoken: "noise",
                                                               [("none", "None"), ("saltAndPepper", "Salt and pepper"), ("gaussian", "Gaussian σ 0.05")],
                                                               default: "none"),
                                     SpecimenOptionSpec.percent("amount", "SALT AND PEPPER", spoken: "salt and pepper amount",
                                                                range: 0...30, step: 1, default: 10,
                                                                note: "Share of pixels set to black or white (seed 3).")])
    }

    public func canvas(windowSize n: Int, margin m: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas {
        let frame = SpecimenFrame(windowSize: n, margin: m), c = frame.c, side = frame.side
        let mask: ScalarBuffer? = text.flatMap { $0.mask.width == side && $0.mask.height == side ? $0.mask : nil }
        let noise = options.option("noise", "none")
        let amount = Swift.min(30, Swift.max(0, options.number("amount", 10))) / 100
        let seed = options.noiseSeed(Self.seed)
        let image = SpecimenRaster.render(frame) { x, y in
            let cov = Double(mask?[x + m, y + m] ?? 0)
            var v = x < c.x ? cov : 1 - cov
            switch noise {
            case "saltAndPepper":
                let u = SpecimenNoise.words(dx: x - c.x, dy: y - c.y, seed: seed)
                if Double(u.0) * (1.0 / 4_294_967_296.0) < amount { v = u.1 & 1 == 0 ? 0 : 1 }
            case "gaussian":
                v += 0.05 * SpecimenNoise.gaussian(dx: x - c.x, dy: y - c.y, seed: seed)
            default: break
            }
            return SpecimenRaster.grey(SpecimenRaster.sdr(v))
        }
        let probe = mask.flatMap { Self.firstStem($0, frame: frame) }
            ?? frame.relative(TextSpecimenLayout.leftStart, TextSpecimenLayout.lines[TextSpecimenLayout.probeLine].baseline - 4)
        return makeSpecimenCanvas(Self.id, frame, options, image: image, probe: probe,
                                  caption: mask == nil ? "TEXT NOT RENDERED · CORE TEXT RUNS IN THE APP" : nil)
    }

    /// The default probe: the first stem of the 12-px line in the left half (the first column whose coverage reaches 0.5,
    /// at the row where that column is most covered).
    public static func firstStem(_ mask: ScalarBuffer, frame: SpecimenFrame) -> PixelPoint? {
        let c = frame.c, m = frame.margin
        let line = TextSpecimenLayout.lines[TextSpecimenLayout.probeLine]
        let base = c.y + line.baseline
        let rows = (base - Int(line.pixelSize))...(base + 2)
        for x in (c.x + TextSpecimenLayout.leftStart - 4)..<c.x {
            var best: (row: Int, value: Float)? = nil
            for y in rows {
                let i = x + m, j = y + m
                guard i >= 0, j >= 0, i < mask.width, j < mask.height else { continue }
                let v = mask[i, j]
                if v >= 0.5 && (best == nil || v > best!.value) { best = (y, v) }
            }
            if let best { return PixelPoint(x: x, y: best.row) }
        }
        return nil
    }
}

// MARK: - Shape on transparent

/// `alpha-shape` · Shape on transparent: a saturated red disc (radius 200 px) about c + (0.5, 0.5) on fully transparent
/// (0, 0, 0, 0), premultiplied, edges 4 × 4 supersampled; option `Square and star` (a 300-px square and a five-point star)
/// for drop shadows. `auxiliary.mask` is the coverage (alpha).
public struct AlphaShapeGenerator: SpecimenGenerating {
    public init() {}
    public static let id: SpecimenID = "alpha-shape"
    public static let red = SIMD3<Float>(1, 0, 0)
    public static let discRadius = 200.0
    public static let squareHalf = 150.0
    public static let starOuter = 150.0
    /// Regular {5/2} star: inner/outer radius = sin 18° / sin 54° = 0.381966.
    public static let starInner = 150.0 * 0.38196601125010515
    /// Light grey behind the transparent pixels (linear 0.5).
    public static let backdrop = SIMD4<Float>(0.5, 0.5, 0.5, 1)
    public var descriptor: SpecimenDescriptor {
        SpecimenDescriptor(id: Self.id, menuName: "Shape on transparent",
                           reveals: "premultiplied vs straight alpha (dark fringe); shadow conventions",
                           isHDR: false, isHighContrastPattern: false, supportsExposure: false, needsTextCoverage: false,
                           animated: false,
                           options: [SpecimenOptionSpec.choice("shape", "SHAPE", spoken: "shape",
                                                               [("disc", "Disc"), ("squareAndStar", "Square and star")], default: "disc")])
    }
    /// Vertices of the star (y down, first point straight up), about `centre`.
    public static func starVertices(centre: SIMD2<Double>) -> [SIMD2<Double>] {
        (0..<10).map { k in
            let angle = -SpecimenMath.halfPi + Double(k) * SpecimenMath.pi / 5
            let r = k % 2 == 0 ? starOuter : starInner
            return SIMD2(centre.x + r * SpecimenMath.cos(angle), centre.y + r * SpecimenMath.sin(angle))
        }
    }
    /// Even–odd point-in-polygon test.
    @inline(__always)
    static func inside(_ p: SIMD2<Double>, _ poly: [SIMD2<Double>]) -> Bool {
        var result = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { result.toggle() }
            j = i
        }
        return result
    }

    public func canvas(windowSize n: Int, margin m: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas {
        let frame = SpecimenFrame(windowSize: n, margin: m), c = frame.c
        let shapes = options.option("shape", "disc") == "squareAndStar"
        let disc = frame.centre
        let square = SIMD2<Double>(Double(c.x - 180) + 0.5, Double(c.y) + 0.5)
        let starCentre = SIMD2<Double>(Double(c.x + 200) + 0.5, Double(c.y) + 0.5)
        let star = Self.starVertices(centre: starCentre)
        let coverage = SpecimenRaster.scalar(frame) { x, y in
            guard shapes else { return SpecimenRaster.discCoverage(x, y, centre: disc, radius: Self.discRadius) }
            let px = Double(x) + 0.5, py = Double(y) + 0.5
            // Square: fully decided unless the pixel centre is within 0.75 px of an edge.
            let ex = Swift.abs(px - square.x), ey = Swift.abs(py - square.y)
            var sq: Float
            if ex < Self.squareHalf - 0.75 && ey < Self.squareHalf - 0.75 { sq = 1 }
            else if ex > Self.squareHalf + 0.75 || ey > Self.squareHalf + 0.75 { sq = 0 }
            else {
                sq = SpecimenRaster.coverage(x, y) { qx, qy in
                    Swift.abs(qx - square.x) <= Self.squareHalf && Swift.abs(qy - square.y) <= Self.squareHalf
                }
            }
            // Star: outside its circumcircle (+1 px) or inside the inner pentagon's incircle (−1 px) is decided.
            let dx = px - starCentre.x, dy = py - starCentre.y
            let r = (dx * dx + dy * dy).squareRoot()
            var st: Float
            if r > Self.starOuter + 1 { st = 0 }
            else if r < Self.starInner * 0.80901699437494742 - 1 { st = 1 }   // incircle of the inner pentagon: r·cos 36°
            else { st = SpecimenRaster.coverage(x, y) { qx, qy in Self.inside(SIMD2(qx, qy), star) } }
            return Swift.max(sq, st)
        }
        let image = ImageBuffer(width: frame.side, height: frame.side,
                                pixels: coverage.values.map { a in SIMD4<Float>(Self.red.x * a, Self.red.y * a, Self.red.z * a, a) })
        // On the rim: the disc's (647, 447) at 894; the square's right edge column for `Square and star`.
        let probe = shapes ? frame.relative(-30, 0) : frame.relative(200, 0)
        return makeSpecimenCanvas(Self.id, frame, options, image: image, probe: probe,
                                  auxiliary: AuxiliaryInputs(mask: coverage), backdrop: Self.backdrop)
    }
}

// MARK: - Stripes, text and split (the material backdrop)

/// `material-backdrop` · Stripes, text and split: six saturated 32-px colour stripes on top (repeating upward into the
/// margin), one text line in the middle (the 18-px line, black on white), a white/black split at the bottom (white left of
/// c.x, black from c.x). FAM-F10 draws the same layout in SwiftUI for the native glass exhibit (METRO §C.2).
public struct MaterialBackdropGenerator: SpecimenGenerating {
    public init() {}
    public static let id: SpecimenID = "material-backdrop"
    /// Linear sRGB, saturated: red, yellow, green, cyan, blue, magenta.
    public static let stripeColours: [SIMD3<Float>] = [SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0), SIMD3(0, 1, 1),
                                                       SIMD3(0, 0, 1), SIMD3(1, 0, 1)]
    public static let stripeHeight = 32
    /// Rows relative to c.y: stripes above −64, the text band [−64, 64), the split from 64 down.
    public static let stripesEnd = -64
    public static let splitStart = 64
    /// The text line's baseline in this image (relative to c.y).
    public static let textBaseline = 8
    public var descriptor: SpecimenDescriptor {
        SpecimenDescriptor(id: Self.id, menuName: "Stripes, text and split",
                           reveals: "how much of a material is colour stage vs blur; vibrancy; luminance squeeze",
                           isHDR: false, isHighContrastPattern: false, supportsExposure: false, needsTextCoverage: true,
                           animated: false, options: [])
    }
    public func canvas(windowSize n: Int, margin m: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas {
        let frame = SpecimenFrame(windowSize: n, margin: m), c = frame.c, side = frame.side
        let mask: ScalarBuffer? = text.flatMap { $0.mask.width == side && $0.mask.height == side ? $0.mask : nil }
        let line = TextSpecimenLayout.lines[TextSpecimenLayout.backdropLine]
        let shift = line.baseline - Self.textBaseline          // band row → source row in the text coverage
        let image = SpecimenRaster.render(frame) { x, y in
            let dy = y - c.y
            if dy < Self.stripesEnd {
                let k = SpecimenMath.floorDiv(dy - Self.stripesEnd, Self.stripeHeight)
                let colour = Self.stripeColours[((k % 6) + 6) % 6]
                return SIMD4(colour.x, colour.y, colour.z, 1)
            }
            if dy < Self.splitStart {
                var cov: Float = 0
                let source = dy + shift                                  // the row of the 18-px line in the text layout
                if x < c.x, let mask, source >= line.baseline - 22, source < line.baseline + 8 {
                    let i = x + m, j = c.y + source + m
                    if i >= 0, j >= 0, i < side, j < side { cov = mask[i, j] }
                }
                return SpecimenRaster.grey(1 - cov)
            }
            return x < c.x ? SIMD4<Float>(1, 1, 1, 1) : SIMD4<Float>(0, 0, 0, 1)
        }
        return makeSpecimenCanvas(Self.id, frame, options, image: image, probe: frame.relative(0, 253),   // (447, 700): the split
                                  caption: mask == nil ? "TEXT LINE NOT RENDERED · CORE TEXT RUNS IN THE APP" : nil)
    }
}

// MARK: - Sun behind bars

/// `sun-and-bars` · Sun behind bars: an HDR disc (radius 40 px, value 20) 120 px above c behind a grille of black occluder
/// bars, on a dim sky (0.02). `auxiliary.mask` is 1 where light can pass (sky or sun) and 0 on the bars.
public struct SunAndBarsGenerator: SpecimenGenerating {
    public init() {}
    public static let id: SpecimenID = "sun-and-bars"
    public static let sunValue: Float = 20
    public static let sunRadius = 40.0
    public static let sunOffset = -120
    public static let sky: Float = 0.02
    public var descriptor: SpecimenDescriptor {
        SpecimenDescriptor(id: Self.id, menuName: "Sun behind bars", reveals: "light shafts from an occlusion mask",
                           isHDR: true, isHighContrastPattern: false, supportsExposure: true, needsTextCoverage: false,
                           animated: false, options: [])
    }
    /// True on an occluder bar (window pixel relative to c): a grille 600 px wide over rows −300…+39 with 12-px vertical
    /// bars every 40 px (centred 20 px off c's column, so the ray straight below the sun passes a gap) and 10-px beams
    /// every 85 px.
    public static func isBar(dx: Int, dy: Int) -> Bool {
        guard dx >= -300, dx < 300, dy >= -300, dy < 40 else { return false }
        let vertical = dx - 14 - SpecimenMath.floorDiv(dx - 14, 40) * 40 < 12
        let horizontal = dy + 300 - SpecimenMath.floorDiv(dy + 300, 85) * 85 < 10
        return vertical || horizontal
    }
    public func canvas(windowSize n: Int, margin m: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas {
        let frame = SpecimenFrame(windowSize: n, margin: m), c = frame.c
        let sun = SIMD2<Double>(Double(c.x) + 0.5, Double(c.y + Self.sunOffset) + 0.5)
        let image = SpecimenRaster.render(frame) { x, y in
            if Self.isBar(dx: x - c.x, dy: y - c.y) { return SIMD4<Float>(0, 0, 0, 1) }
            let a = SpecimenRaster.discCoverage(x, y, centre: sun, radius: Self.sunRadius)
            let v = Self.sky * (1 - a) + Self.sunValue * a
            return SIMD4<Float>(v, v, v, 1)
        }
        let mask = SpecimenRaster.scalar(frame) { x, y in Self.isBar(dx: x - c.x, dy: y - c.y) ? 0 : 1 }
        // The disc centre's ray at 200 px: straight below the sun, past the grille.
        return makeSpecimenCanvas(Self.id, frame, options, image: image, probe: frame.relative(0, Self.sunOffset + 200),
                                  auxiliary: AuxiliaryInputs(mask: mask))
    }
}

// MARK: - Blocky depth + stripes (joint bilateral upsampling)

/// `guide-pair` · Blocky depth + stripes: the image is a 16-px blocky depth map (each block point-samples the true depth at
/// its centre; grey = (8 − depth)/7, near is bright), `auxiliary.guide` is a colour-stripe image whose colour changes where
/// the true depth does, and `auxiliary.depth` is the true, full-resolution depth (scene units).
public struct GuidePairGenerator: SpecimenGenerating {
    public init() {}
    public static let id: SpecimenID = "guide-pair"
    public static let block = 16
    public var descriptor: SpecimenDescriptor {
        SpecimenDescriptor(id: Self.id, menuName: "Blocky depth + stripes", reveals: "joint bilateral upsampling",
                           isHDR: false, isHighContrastPattern: false, supportsExposure: false, needsTextCoverage: false,
                           animated: false, options: [])
    }
    /// Region at window offset (dx, dy) from c: 0 background, 1 near disc, 2 middle rectangle.
    public static func region(dx: Int, dy: Int) -> Int {
        let ex = Double(dx) - 150, ey = Double(dy)                      // disc about c + (150.5, 0.5), radius 150
        if ex * ex + ey * ey <= 150 * 150 { return 1 }
        if dx >= -320 && dx < -120 && dy >= -260 && dy < -60 { return 2 }
        return 0
    }
    /// True depth (scene units): a floor tilted towards the viewer at 6, the rectangle at 3.5, the disc at 2.
    public static func depth(dx: Int, dy: Int) -> Float {
        switch region(dx: dx, dy: dy) {
        case 1: return 2
        case 2: return 3.5
        default: return Float(6 - 0.0015 * Double(dy))
        }
    }
    public static let palettes: [(SIMD3<Float>, SIMD3<Float>)] = [
        (SIMD3(0.05, 0.25, 0.6), SIMD3(0.1, 0.55, 0.65)),       // background: cool stripes
        (SIMD3(0.9, 0.35, 0.05), SIMD3(0.85, 0.75, 0.1)),       // disc: warm stripes
        (SIMD3(0.15, 0.6, 0.15), SIMD3(0.05, 0.3, 0.08)),       // rectangle: green stripes
    ]
    public func canvas(windowSize n: Int, margin m: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas {
        let frame = SpecimenFrame(windowSize: n, margin: m), c = frame.c, b = Self.block
        let image = SpecimenRaster.render(frame) { x, y in
            let bx = SpecimenMath.floorDiv(x - c.x, b) * b + b / 2, by = SpecimenMath.floorDiv(y - c.y, b) * b + b / 2
            let d = Self.depth(dx: bx, dy: by)
            return SpecimenRaster.grey(Swift.min(1, Swift.max(0, (8 - d) / 7)))
        }
        let depth = SpecimenRaster.scalar(frame) { x, y in Self.depth(dx: x - c.x, dy: y - c.y) }
        let guide = SpecimenRaster.render(frame) { x, y in
            let dx = x - c.x, dy = y - c.y
            let phase = SpecimenMath.floorDiv(dx, 12) & 1
            func colour(_ r: Int) -> SIMD3<Float> { phase == 0 ? Self.palettes[r].0 : Self.palettes[r].1 }
            let r = Self.region(dx: dx, dy: dy)
            // Anti-alias the disc rim in the guide (4 × 4); the rectangle's edges are pixel-aligned.
            let a = SpecimenRaster.discCoverage(x, y, centre: SIMD2(Double(c.x) + 150.5, Double(c.y) + 0.5), radius: 150)
            let base = colour(r == 1 ? 0 : r)
            let mixed = r == 2 ? base : base * (1 - a) + colour(1) * a
            return SIMD4(mixed.x, mixed.y, mixed.z, 1)
        }
        return makeSpecimenCanvas(Self.id, frame, options, image: image, probe: frame.c,
                                  auxiliary: AuxiliaryInputs(depth: depth, guide: guide))
    }
}
