import Foundation

// OWNER: TESTIMAGES. The three scenes of SPEC §11 (#17 tilted plane with depth, #18 moving disc with velocity, depth and
// sub-frames, #19 aerial ground plane). Pinhole camera, y down; depth is in scene units (stated on screen as such).

// MARK: - Tilted plane (depth of field)

/// `scene-depth` · Tilted plane: a ground plane receding to a horizon 200 px above c, carrying rows of HDR point lights
/// (geometric rows z = 2.5·1.15^k for k = 0…23, columns every 1.25 units; 3 × 3 px nearer than z = 8), plus a near dark vertical bar (depth 1.2) 120 px right of c, with a
/// matching depth buffer (`auxiliary.depth`: plane z(y) = f·h/(y − horizon), sky 1,000, bar 1.2).
public struct SceneDepthGenerator: SpecimenGenerating {
    public init() {}
    public static let id: SpecimenID = "scene-depth"
    public static let focal = 700.0          // px
    public static let cameraHeight = 1.6     // scene units
    public static let horizon = -200.0       // rows relative to c.y (continuous)
    public static let skyDepth: Float = 1000
    public static let barDepth: Float = 1.2
    public static let barRange = 120..<152   // columns relative to c.x
    public static let lightIntensity: Float = 60
    public static let ground: Float = 0.015
    public static let bar: Float = 0.03
    public var descriptor: SpecimenDescriptor {
        SpecimenDescriptor(id: Self.id, menuName: "Tilted plane", reveals: "depth of field, CoC, near/far edge handling",
                           isHDR: true, isHighContrastPattern: false, supportsExposure: true, needsTextCoverage: false,
                           animated: false, options: [])
    }
    /// Plane depth at a window row (pixel centre), relative to c.y; nil above the horizon.
    public static func planeDepth(dy: Int) -> Double? {
        let below = Double(dy) + 0.5 - horizon
        return below > 0 ? focal * cameraHeight / below : nil
    }
    /// The lights: window pixel (relative to c) and size, nearest rows first.
    public static func lights() -> [(dx: Int, dy: Int, size: Int, colour: Int)] {
        var out: [(Int, Int, Int, Int)] = []
        var z = 2.5
        for row in 0..<24 {
            let y = horizon + focal * cameraHeight / z
            for col in -24...24 {
                let xw = 1.25 * Double(col)
                let x = focal * xw / z
                out.append((Int((x + 0.5).rounded(.down)), Int(y.rounded(.down)), z < 8 ? 3 : 1, row & 1))
            }
            z *= 1.15
        }
        return out
    }
    public func canvas(windowSize n: Int, margin m: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas {
        let frame = SpecimenFrame(windowSize: n, margin: m), c = frame.c, side = frame.side
        var pixels = [SIMD4<Float>](repeating: SIMD4(0, 0, 0, 1), count: side * side)
        for j in 0..<side where Self.planeDepth(dy: j - m - c.y) != nil {
            for i in 0..<side { pixels[j * side + i] = SpecimenRaster.grey(Self.ground) }
        }
        let warm = NightCityGenerator.colours[0], neutral = NightCityGenerator.colours[1]
        for light in Self.lights() {
            let rgb = light.colour == 0 ? warm : neutral
            let v = SIMD4<Float>(rgb.x * Self.lightIntensity, rgb.y * Self.lightIntensity, rgb.z * Self.lightIntensity, 1)
            let h = light.size / 2
            for y in (light.dy - h)...(light.dy + h) {
                for x in (light.dx - h)...(light.dx + h) {
                    let i = c.x + x + m, j = c.y + y + m
                    if i >= 0, j >= 0, i < side, j < side { pixels[j * side + i] = v }
                }
            }
        }
        for j in 0..<side {
            for dx in Self.barRange { let i = c.x + dx + m; if i >= 0 && i < side { pixels[j * side + i] = SpecimenRaster.grey(Self.bar) } }
        }
        let depth = SpecimenRaster.scalar(frame) { x, y in
            if Self.barRange.contains(x - c.x) { return Self.barDepth }
            return Self.planeDepth(dy: y - c.y).map { Float($0) } ?? Self.skyDepth
        }
        // On the bar's edge: the last plane column left of the near bar, 60 px below c.
        return makeSpecimenCanvas(Self.id, frame, options, image: ImageBuffer(width: side, height: side, pixels: pixels),
                                  probe: frame.relative(Self.barRange.lowerBound - 1, 60), auxiliary: AuxiliaryInputs(depth: depth))
    }
}

// MARK: - Moving disc (motion blur, frame accumulation)

/// `scene-motion` · Moving disc: a 120-px disc moving 24 px per frame (+x) over a 16-px checker, and a bar rotating 15° per
/// frame about a pivot up and left of c. `image` is frame 0; `auxiliary.velocity` is frame 0's motion (px per frame),
/// `auxiliary.depth` its depth (checker 10, bar 5, disc 3), and `auxiliary.subFrames` the scene at N times spread evenly
/// over one frame interval centred on frame 0 (t_k = (k + ½)/N − ½), so their mean is a 360° box shutter. Option SUB-FRAMES
/// N = 4 · 8 · 16 (each sub-frame is canvas-sized: 31.6 MB at N = 894). `render(time:)` draws any instant on demand.
public struct SceneMotionGenerator: SpecimenGenerating {
    public init() {}
    public static let id: SpecimenID = "scene-motion"
    public static let discRadius = 60.0
    public static let discSpeed = 24.0                      // px per frame
    public static let barHalfLength = 100.0
    public static let barHalfWidth = 8.0
    public static let barPivot = (dx: -220, dy: -200)       // relative to c
    public static let barAngle0 = 20.0 * SpecimenMath.pi / 180
    public static let barSpeed = 15.0 * SpecimenMath.pi / 180   // rad per frame (clockwise on screen)
    public static let checker = 16
    public static let checkerValues: (Float, Float) = (0.35, 0.12)
    public static let discColour = SIMD3<Float>(1.0, 0.55, 0.12)
    public static let barColour = SIMD3<Float>(0.25, 0.65, 1.0)
    public var descriptor: SpecimenDescriptor {
        SpecimenDescriptor(id: Self.id, menuName: "Moving disc", reveals: "per-pixel motion blur vs frame accumulation",
                           isHDR: false, isHighContrastPattern: true, supportsExposure: false, needsTextCoverage: false,
                           animated: true,
                           options: [SpecimenOptionSpec.choice("subFrames", "SUB-FRAMES", spoken: "sub-frames",
                                                               [("4", "4"), ("8", "8"), ("16", "16")], default: "8",
                                                               note: "Each sub-frame is a full canvas.")])
    }
    /// Sub-frame times (frames) for N sub-frames: (k + ½)/N − ½.
    public static func subFrameTimes(_ count: Int) -> [Double] { (0..<count).map { (Double($0) + 0.5) / Double(count) - 0.5 } }

    struct Geometry: Sendable {
        var disc: SIMD2<Double>
        var pivot: SIMD2<Double>
        var axis: SIMD2<Double>          // unit vector along the bar
        init(c: PixelPoint, time t: Double) {
            disc = SIMD2(Double(c.x) + 0.5 + SceneMotionGenerator.discSpeed * t, Double(c.y) + 0.5)
            pivot = SIMD2(Double(c.x + SceneMotionGenerator.barPivot.dx) + 0.5, Double(c.y + SceneMotionGenerator.barPivot.dy) + 0.5)
            let a = SceneMotionGenerator.barAngle0 + SceneMotionGenerator.barSpeed * t
            axis = SIMD2(SpecimenMath.cos(a), SpecimenMath.sin(a))
        }
        @inline(__always) func onBar(_ px: Double, _ py: Double) -> Bool {
            let dx = px - pivot.x, dy = py - pivot.y
            let along = dx * axis.x + dy * axis.y, across = -dx * axis.y + dy * axis.x
            return Swift.abs(along) <= SceneMotionGenerator.barHalfLength && Swift.abs(across) <= SceneMotionGenerator.barHalfWidth
        }
        /// Bar coverage with a fast path (decided when the centre is > 0.75 px from the bar's rectangle).
        @inline(__always) func barCoverage(_ x: Int, _ y: Int) -> Float {
            let dx = Double(x) + 0.5 - pivot.x, dy = Double(y) + 0.5 - pivot.y
            let along = Swift.abs(dx * axis.x + dy * axis.y), across = Swift.abs(-dx * axis.y + dy * axis.x)
            let L = SceneMotionGenerator.barHalfLength, W = SceneMotionGenerator.barHalfWidth
            if along < L - 0.75 && across < W - 0.75 { return 1 }
            if along > L + 0.75 || across > W + 0.75 { return 0 }
            return SpecimenRaster.coverage(x, y) { px, py in onBar(px, py) }
        }
    }

    /// The scene at time `t` (frames), canvas-sized, linear, opaque.
    public static func render(time t: Double, windowSize n: Int, margin m: Int) -> ImageBuffer {
        let frame = SpecimenFrame(windowSize: n, margin: m), c = frame.c
        let g = Geometry(c: c, time: t)
        return SpecimenRaster.render(frame) { x, y in
            let cell = SpecimenMath.floorDiv(x - c.x, Self.checker) + SpecimenMath.floorDiv(y - c.y, Self.checker)
            let bg: Float = cell & 1 == 0 ? Self.checkerValues.0 : Self.checkerValues.1
            var rgb = SIMD3<Float>(bg, bg, bg)
            let b = g.barCoverage(x, y)
            if b > 0 { rgb = rgb * (1 - b) + Self.barColour * b }
            let d = SpecimenRaster.discCoverage(x, y, centre: g.disc, radius: Self.discRadius)
            if d > 0 { rgb = rgb * (1 - d) + Self.discColour * d }
            return SIMD4(rgb.x, rgb.y, rgb.z, 1)
        }
    }

    public func canvas(windowSize n: Int, margin m: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas {
        let frame = SpecimenFrame(windowSize: n, margin: m), c = frame.c
        let count = [4, 8, 16].contains(Int(options.number("subFrames", 8))) ? Int(options.number("subFrames", 8)) : 8
        let g = Geometry(c: c, time: 0)
        let image = Self.render(time: 0, windowSize: n, margin: m)
        let velocity = SpecimenRaster.vector(frame) { x, y in
            if SpecimenRaster.discCoverage(x, y, centre: g.disc, radius: Self.discRadius) >= 0.5 { return SIMD2(Float(Self.discSpeed), 0) }
            if g.barCoverage(x, y) >= 0.5 {
                let dx = Double(x) + 0.5 - g.pivot.x, dy = Double(y) + 0.5 - g.pivot.y
                return SIMD2(Float(-Self.barSpeed * dy), Float(Self.barSpeed * dx))      // ω × r, y down
            }
            return .zero
        }
        let depth = SpecimenRaster.scalar(frame) { x, y in
            if SpecimenRaster.discCoverage(x, y, centre: g.disc, radius: Self.discRadius) >= 0.5 { return 3 }
            if g.barCoverage(x, y) >= 0.5 { return 5 }
            return 10
        }
        let subFrames = Self.subFrameTimes(count).map { Self.render(time: $0, windowSize: n, margin: m) }
        // The disc's trailing (left) rim on the row of c.
        return makeSpecimenCanvas(Self.id, frame, options, image: image, probe: frame.relative(-60, 0),
                                  auxiliary: AuxiliaryInputs(depth: depth, velocity: velocity, subFrames: subFrames))
    }
}

// MARK: - Aerial ground plane (tilt-shift)

/// `aerial` · Aerial ground plane: a checker in perspective whose squares are 32 px wide on the focus line (the row of c),
/// horizon 149 px above c (the top third at N = 894), 4 × 4 supersampled; a soft sky above. `auxiliary.depth` is the plane
/// depth (sky 1,000).
public struct AerialGenerator: SpecimenGenerating {
    public init() {}
    public static let id: SpecimenID = "aerial"
    public static let focal = 600.0
    public static let horizon = -149.0
    /// Square side 1 unit; camera height chosen so a square is 32 px wide on the row of c: h = 149·S/32.
    public static let square = 1.0
    public static let cameraHeight = 149.0 / 32.0
    public static let light = SIMD3<Float>(0.6, 0.62, 0.5)
    public static let dark = SIMD3<Float>(0.07, 0.11, 0.06)
    public static let skyHorizon = SIMD3<Float>(0.55, 0.65, 0.8)
    public static let skyTop = SIMD3<Float>(0.12, 0.25, 0.55)
    public var descriptor: SpecimenDescriptor {
        SpecimenDescriptor(id: Self.id, menuName: "Aerial ground plane", reveals: "tilt-shift's \"toy town\"",
                           isHDR: false, isHighContrastPattern: true, supportsExposure: false, needsTextCoverage: false,
                           animated: false, options: [])
    }
    /// Checker value (0 dark, 1 light) at a point (window coordinates relative to the continuous centre).
    @inline(__always)
    static func checker(_ u: Double, _ v: Double) -> Double {
        let below = v - horizon
        guard below > 0 else { return -1 }
        let z = focal * cameraHeight / below
        let xw = u * z / focal
        let a = Int((xw / square).rounded(.down)) + Int((z / square).rounded(.down))
        return a & 1 == 0 ? 1 : 0
    }
    public func canvas(windowSize n: Int, margin m: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas {
        let frame = SpecimenFrame(windowSize: n, margin: m), centre = frame.centre
        let span = Double(n / 2 + m)
        let image = SpecimenRaster.render(frame) { x, y in
            let rowCentre = Double(y) + 0.5 - centre.y
            if rowCentre + 0.5 <= Self.horizon {
                let t = Float(Swift.min(1, Swift.max(0, (Self.horizon - rowCentre) / span)))
                let s = Self.skyHorizon + (Self.skyTop - Self.skyHorizon) * t
                return SIMD4(s.x, s.y, s.z, 1)
            }
            var lightShare = 0.0, sky = 0.0
            for sy in SpecimenRaster.subOffsets {
                for sx in SpecimenRaster.subOffsets {
                    let v = Self.checker(Double(x) + sx - centre.x, Double(y) + sy - centre.y)
                    if v < 0 { sky += 1 } else { lightShare += v }
                }
            }
            let ground = 16 - sky
            var rgb = Self.dark * Float(ground / 16) + (Self.light - Self.dark) * Float(lightShare / 16)
            rgb += Self.skyHorizon * Float(sky / 16)
            return SIMD4(rgb.x, rgb.y, rgb.z, 1)
        }
        let depth = SpecimenRaster.scalar(frame) { _, y in
            let below = Double(y) + 0.5 - centre.y - Self.horizon
            return below > 0 ? Float(Self.focal * Self.cameraHeight / below) : 1000
        }
        return makeSpecimenCanvas(Self.id, frame, options, image: image, probe: frame.c, auxiliary: AuxiliaryInputs(depth: depth))
    }
}
