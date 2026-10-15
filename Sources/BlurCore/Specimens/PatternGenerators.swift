import Foundation

// OWNER: TESTIMAGES. The pattern test images of SPEC §11 (#2–#9, #11, #12, #14, #15): linear light, opaque, evaluated at pixel
// centres in window coordinates relative to c (so every feature, and its default probe, keeps its meaning at N = 894 and
// N = 810). Noise is keyed by the pixel's offset from c and the image's documented seed; light is clamped at 0.

// MARK: - Siemens star (shared by #2 and the inset of #12)

public enum SiemensStar {
    /// The value at one point: 1 where sin(cycles·θ) ≥ 0, else 0, for r ≤ radius; `outside` beyond.
    /// θ = atan2(y − cy, x − cx) with y down (θ grows clockwise on screen).
    @inline(__always)
    public static func point(_ px: Double, _ py: Double, centre: SIMD2<Double>, radius: Double, cycles: Int,
                             outside: Double) -> Double {
        let dx = px - centre.x, dy = py - centre.y
        if dx * dx + dy * dy > radius * radius { return outside }
        let t = SpecimenMath.atan2(dy, dx) * Double(cycles) / SpecimenMath.twoPi
        return SpecimenMath.fraction(t) <= 0.5 ? 1 : 0
    }

    /// The 4 × 4-supersampled pixel value (SPEC §11 #2). Fast path: when the pixel centre is more than 0.6 px from every
    /// spoke line and from the rim, all sixteen points (within 0.53 px of the centre) agree, so the result equals the full
    /// supersample bit for bit.
    public static func pixel(_ x: Int, _ y: Int, centre: SIMD2<Double>, radius: Double, cycles: Int, outside: Double) -> Double {
        let dx = Double(x) + 0.5 - centre.x, dy = Double(y) + 0.5 - centre.y
        let r = (dx * dx + dy * dy).squareRoot()
        if r > 4 && Swift.abs(r - radius) > 0.75 {
            if r > radius { return outside }
            let t = SpecimenMath.atan2(dy, dx) * Double(cycles) / SpecimenMath.twoPi
            let g = SpecimenMath.fraction(2 * t)                         // position inside the half-cycle
            let dTheta = Swift.min(g, 1 - g) * 0.5 * SpecimenMath.twoPi / Double(cycles)
            if r * dTheta * 0.99 > 0.6 { return SpecimenMath.fraction(t) <= 0.5 ? 1 : 0 }
        }
        return SpecimenRaster.supersample(x, y) { px, py in
            point(px, py, centre: centre, radius: radius, cycles: cycles, outside: outside)
        }
    }
}

/// `siemens-star` · Siemens star: 36 dark–light cycles about c + (0.5, 0.5) out to r = 440, 0.5 outside; 4 × 4 supersampled.
public struct SiemensStarGenerator: SpecimenGenerating {
    public init() {}
    public static let id: SpecimenID = "siemens-star"
    public static let cycles = 36
    public static let radius = 440.0
    public var descriptor: SpecimenDescriptor {
        SpecimenDescriptor(id: Self.id, menuName: "Siemens star",
                           reveals: "zeros (grey rings), inversion (reversed spokes), anisotropy, spin's grey ring, zoom's invariance",
                           isHDR: false, isHighContrastPattern: true, supportsExposure: false, needsTextCoverage: false,
                           animated: false, options: [])
    }
    public func canvas(windowSize n: Int, margin m: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas {
        let frame = SpecimenFrame(windowSize: n, margin: m), centre = frame.centre
        let image = SpecimenRaster.render(frame) { x, y in
            SpecimenRaster.grey(Float(SiemensStar.pixel(x, y, centre: centre, radius: Self.radius, cycles: Self.cycles, outside: 0.5)))
        }
        // (404, 288) at N = 894: r 164.7 px, 0.38 px from the spoke edge at θ = 255°, IN 0.875 (SPEC §11 #2).
        return makeSpecimenCanvas(Self.id, frame, options, image: image, probe: frame.relative(-43, -159),
                                  caption: NumberStyle.integer().text(Double(Self.cycles)) + " CYCLES")
    }
}

/// `zone-plate` · Zone plate: 0.5 + 0.5·cos(π·k·r²), k = 0.5/632.2, r from c + (0.5, 0.5); point-sampled at pixel centres.
public struct ZonePlateGenerator: SpecimenGenerating {
    public init() {}
    public static let id: SpecimenID = "zone-plate"
    /// Local frequency k·r cycles per pixel reaches Nyquist (0.5) at r = 632.2 px, the window corners at N = 894.
    public static let k = 0.5 / 632.2
    public var descriptor: SpecimenDescriptor {
        SpecimenDescriptor(id: Self.id, menuName: "Zone plate",
                           reveals: "the response laid out in space; zero rings; aliasing; zoom destroys it, spin spares it",
                           isHDR: false, isHighContrastPattern: true, supportsExposure: false, needsTextCoverage: false,
                           animated: false, options: [])
    }
    /// The value at window pixel offset (dx, dy) from c (exact integer r²).
    public static func value(dx: Int, dy: Int) -> Double {
        let r2 = Double(dx * dx + dy * dy)
        return 0.5 + 0.5 * SpecimenMath.cos(SpecimenMath.pi * k * r2)
    }
    public func canvas(windowSize n: Int, margin m: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas {
        let frame = SpecimenFrame(windowSize: n, margin: m), c = frame.c
        let image = SpecimenRaster.render(frame) { x, y in SpecimenRaster.grey(Float(Self.value(dx: x - c.x, dy: y - c.y))) }
        return makeSpecimenCanvas(Self.id, frame, options, image: image, probe: frame.relative(300, 13))   // (747, 460): IN 0.224
    }
}

/// `step-edges` · Step edges: 0 for window x ≤ c.x − 1, 1 for x ≥ c.x (vertical); option 45° (x − y ≥ 0 about c).
public struct StepEdgesGenerator: SpecimenGenerating {
    public init() {}
    public static let id: SpecimenID = "step-edges"
    public var descriptor: SpecimenDescriptor {
        SpecimenDescriptor(id: Self.id, menuName: "Step edges",
                           reveals: "edge spread, edge width, overshoot; separable vs isotropic (axis vs diagonal)",
                           isHDR: false, isHighContrastPattern: false, supportsExposure: false, needsTextCoverage: false,
                           animated: false,
                           options: [SpecimenOptionSpec.choice("orientation", "ORIENTATION", spoken: "orientation",
                                                               [("vertical", "Vertical"), ("45", "45°")], default: "vertical")])
    }
    public func canvas(windowSize n: Int, margin m: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas {
        let frame = SpecimenFrame(windowSize: n, margin: m), c = frame.c
        let diagonal = options.option("orientation", "vertical") == "45"
        let image = SpecimenRaster.render(frame) { x, y in
            let dx = x - c.x, dy = y - c.y
            return (diagonal ? dx - dy >= 0 : dx >= 0) ? SIMD4<Float>(1, 1, 1, 1) : SIMD4<Float>(0, 0, 0, 1)
        }
        // (446, 300): the last dark column, 147 px above c (SPEC §5.3 A). 45°: the dark pixel diagonally next to the edge.
        let probe = diagonal ? frame.relative(-105, -104) : frame.relative(-1, -147)
        return makeSpecimenCanvas(Self.id, frame, options, image: image, probe: probe)
    }
}

/// `noisy-step` · Noisy step: a vertical step centred on 0.5 of height 0.05 · 0.20 · 1.00 (default 0.20: 0.40 → 0.60),
/// Gaussian noise σ 0.02 (seed 1, switchable), optional thin horizontal line (1 px, 0.9) 153 px below c (y = 600 at 894).
public struct NoisyStepGenerator: SpecimenGenerating {
    public init() {}
    public static let id: SpecimenID = "noisy-step"
    public static let seed: UInt32 = 1
    public static let noiseSigma = 0.02
    public var descriptor: SpecimenDescriptor {
        SpecimenDescriptor(id: Self.id, menuName: "Noisy step",
                           reveals: "edge-aware filters by contrast; amplitude-dependent transfer; leaks along rows",
                           isHDR: false, isHighContrastPattern: false, supportsExposure: false, needsTextCoverage: false,
                           animated: false,
                           options: [SpecimenOptionSpec.choice("height", "STEP HEIGHT", spoken: "step height",
                                                               [("0.05", "0.05"), ("0.20", "0.20"), ("1.00", "1.00")], default: "0.20"),
                                     SpecimenOptionSpec.choice("noise", "NOISE", spoken: "noise",
                                                               [("gaussian", "σ 0.02"), ("none", "Off")], default: "gaussian"),
                                     SpecimenOptionSpec.choice("line", "LINE", spoken: "thin horizontal line",
                                                               [("none", "None"), ("thin", "+ Thin line")], default: "none")])
    }
    public func canvas(windowSize n: Int, margin m: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas {
        let frame = SpecimenFrame(windowSize: n, margin: m), c = frame.c
        let height = options.number("height", 0.20)
        let lo = 0.5 - height / 2, hi = 0.5 + height / 2
        let noisy = options.option("noise", "gaussian") != "none"
        let line = options.option("line", "none") == "thin"
        let seed = options.noiseSeed(Self.seed)
        let image = SpecimenRaster.render(frame) { x, y in
            let dx = x - c.x, dy = y - c.y
            var v = dx >= 0 ? hi : lo
            if line && dy == 153 { v = 0.9 }
            if noisy { v += Self.noiseSigma * SpecimenNoise.gaussian(dx: dx, dy: dy, seed: seed) }
            return SpecimenRaster.grey(SpecimenRaster.sdr(v))
        }
        return makeSpecimenCanvas(Self.id, frame, options, image: image, probe: frame.relative(0, -147))   // (447, 300)
    }
}

/// `impulse` · Impulse: one pixel at c with intensity 1 · 10 · 100 (HDR; exposure at render time).
public struct ImpulseGenerator: SpecimenGenerating {
    public init() {}
    public static let id: SpecimenID = "impulse"
    public var descriptor: SpecimenDescriptor {
        SpecimenDescriptor(id: Self.id, menuName: "Impulse", reveals: "the PSF itself; tails; truncation squares; pyramid snapping",
                           isHDR: true, isHighContrastPattern: false, supportsExposure: true, needsTextCoverage: false,
                           animated: false,
                           options: [SpecimenOptionSpec.choice("intensity", "INTENSITY", spoken: "intensity",
                                                               [("1", "1"), ("10", "10"), ("100", "100")], default: "1"),
                                     SpecimenOptionSpec.choice("display", "DISPLAY", spoken: "display",
                                                               [("linear", "Linear"), ("log", "Log")], default: "linear",
                                                               note: "Display only: the image itself is unchanged.")])
    }
    public func canvas(windowSize n: Int, margin m: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas {
        let frame = SpecimenFrame(windowSize: n, margin: m), c = frame.c
        let v = Float(options.number("intensity", 1))
        let image = SpecimenRaster.render(frame) { x, y in
            x == c.x && y == c.y ? SIMD4<Float>(v, v, v, 1) : SIMD4<Float>(0, 0, 0, 1)
        }
        return makeSpecimenCanvas(Self.id, frame, options, image: image, probe: frame.relative(0, 8))       // (447, 455)
    }
}

/// `impulse-grid` · Impulse grid: one-pixel dots every 64 px on a lattice through c (13 × 13 inside the window at 894 and
/// 810; the lattice continues into the pan margin), intensity 1 · 100.
public struct ImpulseGridGenerator: SpecimenGenerating {
    public init() {}
    public static let id: SpecimenID = "impulse-grid"
    public static let spacing = 64
    public var descriptor: SpecimenDescriptor {
        SpecimenDescriptor(id: Self.id, menuName: "Impulse grid",
                           reveals: "PSF fields of space-variant blurs (zoom rays, cat's eyes, variable blur); bokeh polygons",
                           isHDR: true, isHighContrastPattern: false, supportsExposure: true, needsTextCoverage: false,
                           animated: false,
                           options: [SpecimenOptionSpec.choice("intensity", "INTENSITY", spoken: "intensity",
                                                               [("1", "1"), ("100", "100")], default: "1")])
    }
    public func canvas(windowSize n: Int, margin m: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas {
        let frame = SpecimenFrame(windowSize: n, margin: m), c = frame.c
        let v = Float(options.number("intensity", 1)), s = Self.spacing
        let image = SpecimenRaster.render(frame) { x, y in
            let dx = x - c.x, dy = y - c.y
            let on = dx - SpecimenMath.floorDiv(dx, s) * s == 0 && dy - SpecimenMath.floorDiv(dy, s) * s == 0
            return on ? SIMD4<Float>(v, v, v, 1) : SIMD4<Float>(0, 0, 0, 1)
        }
        return makeSpecimenCanvas(Self.id, frame, options, image: image, probe: frame.relative(8, 0))       // (455, 447)
    }
}

/// `checkerboard` · Checkerboard of period 2 px (1-px squares) or 16 px, white square at c.
public struct CheckerboardGenerator: SpecimenGenerating {
    public init() {}
    public static let id: SpecimenID = "checkerboard"
    public var descriptor: SpecimenDescriptor {
        SpecimenDescriptor(id: Self.id, menuName: "Checkerboard",
                           reveals: "Nyquist content: the binomial erases the finest checker; a sampled Gaussian leaves a faint residue",
                           isHDR: false, isHighContrastPattern: true, supportsExposure: false, needsTextCoverage: false,
                           animated: false,
                           options: [SpecimenOptionSpec.choice("period", "PERIOD", spoken: "period",
                                                               [("2", "2 px"), ("16", "16 px")], default: "2")])
    }
    public func canvas(windowSize n: Int, margin m: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas {
        let frame = SpecimenFrame(windowSize: n, margin: m), c = frame.c
        let square = Swift.max(1, Int(options.number("period", 2)) / 2)
        let image = SpecimenRaster.render(frame) { x, y in
            let cell = SpecimenMath.floorDiv(x - c.x, square) + SpecimenMath.floorDiv(y - c.y, square)
            return cell & 1 == 0 ? SIMD4<Float>(1, 1, 1, 1) : SIMD4<Float>(0, 0, 0, 1)
        }
        return makeSpecimenCanvas(Self.id, frame, options, image: image, probe: frame.c)
    }
}

/// `stripes` · Stripes: 1-px vertical black/white columns (white at c's column).
public struct StripesGenerator: SpecimenGenerating {
    public init() {}
    public static let id: SpecimenID = "stripes"
    public var descriptor: SpecimenDescriptor {
        SpecimenDescriptor(id: Self.id, menuName: "Stripes",
                           reveals: "the colour-space verdict: a gamma blend vs a linear blend of black and white",
                           isHDR: false, isHighContrastPattern: true, supportsExposure: false, needsTextCoverage: false,
                           animated: false, options: [])
    }
    public func canvas(windowSize n: Int, margin m: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas {
        let frame = SpecimenFrame(windowSize: n, margin: m), c = frame.c
        let image = SpecimenRaster.render(frame) { x, _ in
            (x - c.x) & 1 == 0 ? SIMD4<Float>(1, 1, 1, 1) : SIMD4<Float>(0, 0, 0, 1)
        }
        return makeSpecimenCanvas(Self.id, frame, options, image: image, probe: frame.c)
    }
}

/// `ramp` · Ramp: 0 → 1 in linear light across the window width (value (x + 0.5)/N, clamped in the margin); option
/// `Encoded ramp` (the encoded value ramps; stored linear through the sRGB decode); optional Gaussian noise σ 0.01 (seed 11).
public struct RampGenerator: SpecimenGenerating {
    public init() {}
    public static let id: SpecimenID = "ramp"
    public static let seed: UInt32 = 11
    public var descriptor: SpecimenDescriptor {
        SpecimenDescriptor(id: Self.id, menuName: "Ramp", reveals: "terraces (surface blur, Perona–Malik), staircasing (TV)",
                           isHDR: false, isHighContrastPattern: false, supportsExposure: false, needsTextCoverage: false,
                           animated: false,
                           options: [SpecimenOptionSpec.choice("encoding", "RAMP", spoken: "ramp",
                                                               [("linear", "Linear ramp"), ("encoded", "Encoded ramp")], default: "linear"),
                                     SpecimenOptionSpec.choice("noise", "NOISE", spoken: "noise",
                                                               [("none", "Off"), ("gaussian", "σ 0.01")], default: "none")])
    }
    public func canvas(windowSize n: Int, margin m: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas {
        let frame = SpecimenFrame(windowSize: n, margin: m), c = frame.c
        let encoded = options.option("encoding", "linear") == "encoded"
        let noisy = options.option("noise", "none") == "gaussian"
        let seed = options.noiseSeed(Self.seed)
        let width = Double(n)
        let image = SpecimenRaster.render(frame) { x, y in
            let t = Swift.min(1, Swift.max(0, (Double(x) + 0.5) / width))
            var v = encoded ? SpecimenMath.srgbDecode(t) : t
            if noisy { v += 0.01 * SpecimenNoise.gaussian(dx: x - c.x, dy: y - c.y, seed: seed) }
            return SpecimenRaster.grey(SpecimenRaster.sdr(v))
        }
        return makeSpecimenCanvas(Self.id, frame, options, image: image, probe: frame.c)
    }
}

/// `noise-field` · Noise field: uniform 0.5 with Gaussian noise σ 0.1 (seed 9) and a 36-cycle star inset in the right third
/// (centre 260 px right of c, radius 110 px: inside the right third at N = 894 and at N = 810; spokes 0.2 / 0.8 so that the
/// noise is rarely clipped). Values are clipped to [0, 1].
public struct NoiseFieldGenerator: SpecimenGenerating {
    public init() {}
    public static let id: SpecimenID = "noise-field"
    public static let seed: UInt32 = 9
    public static let insetOffset = 260
    public static let insetRadius = 110.0
    public var descriptor: SpecimenDescriptor {
        SpecimenDescriptor(id: Self.id, menuName: "Noise field", reveals: "Kuwahara's blocks; smoothing strength",
                           isHDR: false, isHighContrastPattern: true, supportsExposure: false, needsTextCoverage: false,
                           animated: false, options: [])
    }
    public func canvas(windowSize n: Int, margin m: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas {
        let frame = SpecimenFrame(windowSize: n, margin: m), c = frame.c
        let star = SIMD2<Double>(Double(c.x + Self.insetOffset) + 0.5, Double(c.y) + 0.5)
        let seed = options.noiseSeed(Self.seed)
        let image = SpecimenRaster.render(frame) { x, y in
            let spoke = SiemensStar.pixel(x, y, centre: star, radius: Self.insetRadius, cycles: 36, outside: 0.5)
            let base = 0.2 + 0.6 * spoke                                     // 0.5 outside stays 0.5
            let v = base + 0.1 * SpecimenNoise.gaussian(dx: x - c.x, dy: y - c.y, seed: seed)
            return SpecimenRaster.grey(SpecimenRaster.sdr(v))
        }
        return makeSpecimenCanvas(Self.id, frame, options, image: image, probe: frame.relative(-147, 0))   // (300, 447)
    }
}

/// `edge-bar` · Bar at the border: a 32-px bright bar (value 1) touching the window's left border (x = 0…31), on black.
public struct EdgeBarGenerator: SpecimenGenerating {
    public init() {}
    public static let id: SpecimenID = "edge-bar"
    public static let width = 32
    public var descriptor: SpecimenDescriptor {
        SpecimenDescriptor(id: Self.id, menuName: "Bar at the border", reveals: "IIR boundary transient; FFT wrap-around; edge modes",
                           isHDR: false, isHighContrastPattern: false, supportsExposure: false, needsTextCoverage: false,
                           animated: false, options: [])
    }
    public func canvas(windowSize n: Int, margin m: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas {
        let frame = SpecimenFrame(windowSize: n, margin: m)
        let image = SpecimenRaster.render(frame) { x, _ in
            x >= 0 && x < Self.width ? SIMD4<Float>(1, 1, 1, 1) : SIMD4<Float>(0, 0, 0, 1)
        }
        return makeSpecimenCanvas(Self.id, frame, options, image: image, probe: PixelPoint(x: 40, y: frame.c.y))   // (40, 447)
    }
}

/// `rings` · Noisy rings: concentric rings of period 12 px about c + (0.5, 0.5), 0.5 ± 0.25 (contrast 0.5), Gaussian noise
/// σ 0.1 (seed 5).
public struct RingsGenerator: SpecimenGenerating {
    public init() {}
    public static let id: SpecimenID = "rings"
    public static let seed: UInt32 = 5
    public static let period = 12.0
    public var descriptor: SpecimenDescriptor {
        SpecimenDescriptor(id: Self.id, menuName: "Noisy rings",
                           reveals: "flow-following filters (anisotropic Kuwahara; coherence-enhancing diffusion)",
                           isHDR: false, isHighContrastPattern: true, supportsExposure: false, needsTextCoverage: false,
                           animated: false, options: [])
    }
    public func canvas(windowSize n: Int, margin m: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas {
        let frame = SpecimenFrame(windowSize: n, margin: m), c = frame.c
        let seed = options.noiseSeed(Self.seed)
        let image = SpecimenRaster.render(frame) { x, y in
            let dx = x - c.x, dy = y - c.y
            let r = Double(dx * dx + dy * dy).squareRoot()
            let v = 0.5 + 0.25 * SpecimenMath.cos(SpecimenMath.twoPi * r / Self.period)
                + 0.1 * SpecimenNoise.gaussian(dx: dx, dy: dy, seed: seed)
            return SpecimenRaster.grey(SpecimenRaster.sdr(v))
        }
        return makeSpecimenCanvas(Self.id, frame, options, image: image, probe: frame.relative(96, 0))     // (543, 447): a crest
    }
}
