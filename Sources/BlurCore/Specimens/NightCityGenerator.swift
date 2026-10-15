import Foundation

// OWNER: TESTIMAGES. `night-city` · Night City (SPEC §11 #1; ARCHITECTURE §8.2 TESTIMAGES), replacing the skeleton's v0.
//
// The window (N × N, at pan 0) holds exactly the specified scene:
// • dark building silhouettes (every channel 0.02–0.06) under a black sky (0, 0, 0, 1);
// • 160 point lights at Poisson-disc positions drawn from PCG32 seed 7: 120 of 1 × 1 px with intensities log-uniform
//   20–1,000 and 40 of 3 × 3 px with intensities log-uniform 2–100 (intensity = the light's largest channel);
// • three colour temperatures as fixed linear-sRGB triples (sodium 2,000 K-like, neutral 4,000 K, cool 6,500 K);
// • a few lights in a row like a street, one pair 20 px apart, and exactly three lights within 8 px of the window border;
// • the white reference light of 100 (1 px) at c, with a clear zone around it, so the default probe (c.x, c.y + 8) reads
//   IN = 0 and a 16-px hexagon about the probe sees the reference light alone (SPEC §5.3 D: OUT 100/665 = 0.1504).
// The pan margin continues the city (more buildings and lights from separate streams of the same seed), so panning reveals
// real content. Canvases are generated at 0 EV; EXPOSURE multiplies by 2^EV at render time (the brightest light, 1,000,
// reaches 64,000 at +6 EV, below fp16's 65,504). Only +, −, ×, ÷, √ and SpecimenMath are used (review fix E-22).

/// One light of the Night City (window pixel of its centre).
public struct NightCityLight: Sendable, Hashable, Codable {
    public enum Role: String, Sendable, Codable, Hashable {
        /// Poisson-disc darts (seed 7).
        case poisson
        /// The two lights 20 px apart.
        case pair
        /// A row of lights like a street.
        case street
        /// The three lights within 8 px of the window border.
        case border
        /// The white reference light of 100 at c.
        case reference
        /// Pan-margin lights (outside the window at pan 0).
        case margin
    }
    public var x: Int
    public var y: Int
    /// 1 (1 × 1 px) or 3 (3 × 3 px).
    public var size: Int
    /// The largest channel of every pixel of the light (linear, 0 EV).
    public var intensity: Float
    /// Index into `NightCityGenerator.colours`, or −1 for the white reference light.
    public var colour: Int
    public var role: Role
    public init(x: Int, y: Int, size: Int, intensity: Float, colour: Int, role: Role) {
        self.x = x; self.y = y; self.size = size; self.intensity = intensity; self.colour = colour; self.role = role
    }
    /// Pixels from the light's centre to the nearest window border (negative outside the window).
    public func borderDistance(windowSize n: Int) -> Int { Swift.min(Swift.min(x, y), Swift.min(n - 1 - x, n - 1 - y)) }
}

/// A building silhouette: window columns [x0, x1), rows from `top` down to the canvas bottom, one shade.
public struct NightCityBuilding: Sendable, Hashable, Codable {
    public var x0: Int
    public var x1: Int
    public var top: Int
    public var shade: Float
}

/// The full layout of one canvas (window coordinates).
public struct NightCityLayout: Sendable, Hashable {
    public var windowSize: Int
    public var lights: [NightCityLight]
    public var buildings: [NightCityBuilding]
    /// Lights whose centre lies inside the window at pan 0 (the specified 160 plus the reference light).
    public var windowLights: [NightCityLight] { lights.filter { $0.role != .margin } }
}

public struct NightCityGenerator: SpecimenGenerating {
    public init() {}

    public static let id: SpecimenID = "night-city"
    public static let seed: UInt32 = 7
    /// Linear-sRGB triples (largest channel 1) of black bodies at 2,000 K, 4,000 K and 6,500 K: CIE xy from the Kim et al.
    /// (2002) Planckian-locus fit, converted to linear sRGB (D65) and normalised; computed offline and fixed here.
    public static let colours: [SIMD3<Float>] = [SIMD3(1.0, 0.2563, 0.0079), SIMD3(1.0, 0.6530, 0.3770), SIMD3(1.0, 0.9436, 0.9926)]
    public static let colourNames = ["sodium 2,000 K", "neutral 4,000 K", "cool 6,500 K"]
    public static let pointCount = 120
    public static let blockCount = 40
    public static let pointRange: ClosedRange<Double> = 20...1000
    public static let blockRange: ClosedRange<Double> = 2...100
    public static let referenceIntensity: Float = 100
    /// Minimum distance between Poisson-disc lights (px).
    public static let minimumDistance = 40.0
    /// Random lights keep at least this distance (px) from the window border, so exactly three lie within 8 px.
    public static let borderInset = 10
    public static let borderBand = 8
    /// Chebyshev radius around c kept free of every light but the reference (px; N/4 for small test windows).
    public static func clearRadius(windowSize n: Int) -> Int { Swift.min(64, n / 4) }
    public static let buildingShades: ClosedRange<Float> = 0.02...0.06

    public var descriptor: SpecimenDescriptor {
        SpecimenDescriptor(id: Self.id, menuName: "Night City",
                           reveals: "PSF shape made visible (bokeh, rims, square supports, tails); linear vs gamma energy loss",
                           isHDR: true, isHighContrastPattern: false, supportsExposure: true, needsTextCoverage: false,
                           animated: false, options: [])
    }

    public func canvas(windowSize n: Int, margin m: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas {
        let frame = SpecimenFrame(windowSize: n, margin: m)
        let layout = Self.layout(windowSize: n, margin: m)
        let side = frame.side
        var pixels = [SIMD4<Float>](repeating: SIMD4(0, 0, 0, 1), count: side * side)
        for b in layout.buildings {
            let i0 = Swift.max(0, b.x0 + m), i1 = Swift.min(side, b.x1 + m), j0 = Swift.max(0, b.top + m)
            guard i0 < i1, j0 < side else { continue }
            let blue = Swift.min(Self.buildingShades.upperBound, b.shade * 1.08)
            let value = SIMD4<Float>(b.shade, b.shade, blue, 1)
            for j in j0..<side { for i in i0..<i1 { pixels[j * side + i] = value } }
        }
        for light in layout.lights {
            let rgb = light.colour < 0 ? SIMD3<Float>(1, 1, 1) : Self.colours[light.colour]
            let value = SIMD4<Float>(rgb.x * light.intensity, rgb.y * light.intensity, rgb.z * light.intensity, 1)
            let half = light.size / 2
            for y in (light.y - half)...(light.y + half) {
                for x in (light.x - half)...(light.x + half) {
                    let i = x + m, j = y + m
                    if i >= 0, j >= 0, i < side, j < side { pixels[j * side + i] = value }
                }
            }
        }
        let c = frame.c
        return SpecimenCanvas(id: Self.id, options: options.canvasOptions, windowSize: n, margin: m,
                              image: ImageBuffer(width: side, height: side, pixels: pixels), auxiliary: .none,
                              defaultProbe: PixelPoint(x: c.x, y: c.y + 8), backdrop: SIMD4(0, 0, 0, 1))
    }

    // MARK: Layout

    /// The deterministic layout for a window size (independent of options; exposure is applied at render time).
    public static func layout(windowSize n: Int, margin m: Int = SpecimenGeometry.margin) -> NightCityLayout {
        let c = SpecimenGeometry.centre(windowSize: n)
        let clear = clearRadius(windowSize: n)
        var lights: [NightCityLight] = []
        var rng = SpecimenRandom(seed: UInt64(seed), stream: 1)

        func inWindow(_ x: Int, _ y: Int, _ size: Int) -> Bool {
            let h = size / 2
            return x - h >= 0 && y - h >= 0 && x + h < n && y + h < n
        }
        func outsideClearZone(_ x: Int, _ y: Int, _ size: Int) -> Bool {
            Swift.max(abs(x - c.x), abs(y - c.y)) - size / 2 > clear
        }
        func farFromOthers(_ x: Int, _ y: Int, _ others: [NightCityLight]) -> Bool {
            let d2 = minimumDistance * minimumDistance
            for o in others {
                let dx = Double(x - o.x), dy = Double(y - o.y)
                if dx * dx + dy * dy < d2 { return false }
            }
            return true
        }
        func intensity(_ size: Int) -> Float {
            let r = size == 1 ? pointRange : blockRange
            return Float(rng.nextLogUniform(r.lowerBound, r.upperBound))
        }

        // 1. Fixed features (drawn from the same stream in a fixed order; kept only where they fit this window).
        let pairIntensity = intensity(1)                                   // the pair shares one log-uniform draw
        for dx in [-150, -130] where inWindow(c.x + dx, c.y - 96, 1) && outsideClearZone(c.x + dx, c.y - 96, 1) {
            lights.append(NightCityLight(x: c.x + dx, y: c.y - 96, size: 1, intensity: pairIntensity, colour: 1, role: .pair))
        }
        for k in 0..<12 {                                                   // a street: sodium lights every 30 px
            let x = c.x + 80 + 30 * k, y = c.y + 236 - k
            let v = intensity(1)
            if inWindow(x, y, 1) && outsideClearZone(x, y, 1)
                && Swift.min(Swift.min(x, y), Swift.min(n - 1 - x, n - 1 - y)) >= borderInset {
                lights.append(NightCityLight(x: x, y: y, size: 1, intensity: v, colour: 0, role: .street))
            }
        }
        let borderSpecs: [(Int, Int, Int)] = [(4, c.y - 180, 1), (c.x + 170, 5, 1), (n - 7, c.y + 140, 3)]
        for (x, y, size) in borderSpecs {
            let v = intensity(size), colour = rng.nextInt(below: 3)
            if inWindow(x, y, size) && outsideClearZone(x, y, size) {
                lights.append(NightCityLight(x: x, y: y, size: size, intensity: v, colour: colour, role: .border))
            }
        }

        // 2. Poisson-disc darts (random sequential adsorption) fill the totals: 120 of 1 × 1 and 40 of 3 × 3.
        let needPoints = Swift.max(0, pointCount - lights.filter { $0.size == 1 }.count)
        let needBlocks = Swift.max(0, blockCount - lights.filter { $0.size == 3 }.count)
        let total = needPoints + needBlocks
        var accepted = 0, attempts = 0
        let span = n - 2 * borderInset
        while accepted < total && attempts < 400_000 && span > 0 {
            attempts += 1
            let x = borderInset + rng.nextInt(below: span), y = borderInset + rng.nextInt(below: span)
            // Interleave the two kinds evenly through the darts.
            let size = (accepted + 1) * needBlocks / Swift.max(total, 1) > accepted * needBlocks / Swift.max(total, 1) ? 3 : 1
            guard outsideClearZone(x, y, size), farFromOthers(x, y, lights) else { continue }
            let v = intensity(size), colour = rng.nextInt(below: 3)
            lights.append(NightCityLight(x: x, y: y, size: size, intensity: v, colour: colour, role: .poisson))
            accepted += 1
        }

        // 3. The reference light (white, 100, 1 px) at c.
        lights.append(NightCityLight(x: c.x, y: c.y, size: 1, intensity: referenceIntensity, colour: -1, role: .reference))

        // 4. The pan margin continues the city at the same density (a separate stream of the same seed).
        var marginRng = SpecimenRandom(seed: UInt64(seed), stream: 2)
        let side = n + 2 * m
        let marginCount = Int((Double(pointCount + blockCount) * Double(side * side - n * n) / Double(n * n)).rounded())
        var placed = 0, tries = 0
        while placed < marginCount && tries < marginCount * 60 && m > 1 {
            tries += 1
            let x = -m + 1 + marginRng.nextInt(below: side - 2), y = -m + 1 + marginRng.nextInt(below: side - 2)
            let size = placed % 4 == 3 ? 3 : 1
            let h = size / 2
            let outside = x + h < 0 || y + h < 0 || x - h >= n || y - h >= n
            guard outside, farFromOthers(x, y, lights) else { continue }
            let r = size == 1 ? pointRange : blockRange
            let v = Float(marginRng.nextLogUniform(r.lowerBound, r.upperBound)), colour = marginRng.nextInt(below: 3)
            lights.append(NightCityLight(x: x, y: y, size: size, intensity: v, colour: colour, role: .margin))
            placed += 1
        }

        // 5. Buildings across the whole canvas width; columns near c stay low so the reference light keeps black sky.
        var cityRng = SpecimenRandom(seed: UInt64(seed), stream: 3)
        var buildings: [NightCityBuilding] = []
        var x = -m
        while x < n + m {
            let width = 24 + cityRng.nextInt(below: 65)
            let gap = cityRng.nextInt(below: 7)
            var top = c.y - 240 + cityRng.nextInt(below: 541)
            let shade = buildingShades.lowerBound + Float(cityRng.nextInt(below: 41)) * 0.001
            let tiered = cityRng.nextInt(below: 100) < 35
            let tierFraction = 40 + cityRng.nextInt(below: 31), tierRise = 20 + cityRng.nextInt(below: 71)
            let protected = x < c.x + 80 && x + width > c.x - 80
            if protected { top = Swift.max(top, c.y + 40) }
            buildings.append(NightCityBuilding(x0: x, x1: x + width, top: top, shade: shade))
            if tiered && !protected {
                let w = width * tierFraction / 100, x0 = x + (width - w) / 2
                buildings.append(NightCityBuilding(x0: x0, x1: x0 + w, top: top - tierRise, shade: shade))
            }
            x += width + gap
        }
        return NightCityLayout(windowSize: n, lights: lights, buildings: buildings)
    }
}
