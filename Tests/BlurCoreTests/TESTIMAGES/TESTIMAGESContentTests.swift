import Foundation
import Testing
@testable import BlurCore

// OWNER: TESTIMAGES. What each test image shows: the SPEC §11 coordinate convention and every default probe's IN value,
// the Night City statistics and the launch fixture (computed with GaussianOperator's reference), the auxiliary buffers,
// and the photo resampler.

func TESTIMAGES_window(_ id: String, _ n: Int = 894, _ options: SpecimenOptions = .standard, text: TextCoverage? = nil) -> (SpecimenCanvas, ImageBuffer) {
    let g = SpecimenRegistry.generator(SpecimenID(rawValue: id))!
    let canvas = g.canvas(windowSize: n, margin: SpecimenGeometry.margin, options: options, text: text)
    return (canvas, canvas.window(pan: .zero).image)
}

@Suite struct TESTIMAGES_Probes {
    /// Every default probe at N = 894 sits at the SPEC §11 coordinates.
    @Test func defaultProbesAtSpecCoordinates() {
        let expected: [String: (Int, Int)] = [
            "night-city": (447, 455), "siemens-star": (404, 288), "zone-plate": (747, 460), "step-edges": (446, 300),
            "noisy-step": (447, 300), "impulse": (447, 455), "impulse-grid": (455, 447), "checkerboard": (447, 447),
            "stripes": (447, 447), "ramp": (447, 447), "noise-field": (300, 447), "alpha-shape": (647, 447), "edge-bar": (40, 447),
            "rings": (543, 447), "material-backdrop": (447, 700), "guide-pair": (447, 447), "photo": (447, 447),
            "sun-and-bars": (447, 527), "scene-motion": (387, 447), "aerial": (447, 447), "scene-depth": (566, 507),
        ]
        for g in SpecimenRegistry.generators where g.descriptor.id != "text" {
            let probe = g.canvas(windowSize: 894, margin: 256, options: .standard, text: nil).defaultProbe
            let want = expected[g.descriptor.id.rawValue]
            #expect(want.map { PixelPoint(x: $0.0, y: $0.1) } == probe, "\(g.descriptor.id): \(probe)")
        }
    }

    /// SPEC §11 rule 2 fixtures: star (747, 460) = 1.000, zone plate (747, 460) = 0.224, star edge (404, 288) = 0.875,
    /// Night City (447, 455) = 0; checked feature-relative at N = 810 (the same offsets from c give the same values).
    @Test(arguments: [894, 810])
    func probeInValues(n: Int) {
        let c = SpecimenGeometry.centre(windowSize: n)
        let (_, star) = TESTIMAGES_window("siemens-star", n)
        #expect(star[c.x + 300, c.y + 13] == SIMD4<Float>(1, 1, 1, 1))                      // (747, 460): middle of a white wedge
        #expect(star[c.x - 43, c.y - 159] == SIMD4<Float>(0.875, 0.875, 0.875, 1))          // (404, 288): 14 of 16 samples
        let (_, zone) = TESTIMAGES_window("zone-plate", n)
        #expect(Swift.abs(zone[c.x + 300, c.y + 13].x - 0.224) < 0.0005, "zone plate IN \(zone[c.x + 300, c.y + 13].x)")
        let (_, city) = TESTIMAGES_window("night-city", n)
        #expect(city[c.x, c.y + 8] == SIMD4<Float>(0, 0, 0, 1))
        #expect(city[c.x, c.y] == SIMD4<Float>(100, 100, 100, 1))
    }

    /// θ = atan2(y − 447.5, x − 447.5) with y down grows clockwise on screen; values sit at pixel centres.
    @Test func coordinateConvention() {
        let n = 894, c = SpecimenGeometry.centre(windowSize: n)
        let (_, star) = TESTIMAGES_window("siemens-star", n)
        #expect(star[c.x + 200, c.y + 4].x == 1)        // θ ≈ +1.1° (just below +x on screen): sin 36θ > 0 → white
        #expect(star[c.x + 200, c.y - 5].x == 0)        // θ ≈ −1.4° (just above): sin 36θ < 0 → black
        #expect(star[c.x + 430, c.y + 13].x == 1 && star[c.x + 446, c.y + 300].x == 0.5)   // inside r 440 / outside (0.5)
        // Radial images are centred on c + (0.5, 0.5): the zone plate is symmetric about pixel c.
        let (_, zone) = TESTIMAGES_window("zone-plate", n)
        #expect(zone[c.x + 17, c.y] == zone[c.x - 17, c.y] && zone[c.x, c.y + 17] == zone[c.x, c.y - 17] && zone[c.x, c.y].x == 1)
    }

    /// The other probes read what their feature promises.
    @Test func featureValuesAtTheProbes() {
        let n = 894, c = SpecimenGeometry.centre(windowSize: n)
        let (_, step) = TESTIMAGES_window("step-edges", n)
        #expect(step[446, 300].x == 0 && step[447, 300].x == 1)                              // SPEC §5.3 A: x ≤ 446 → 0
        let (diagCanvas, diag) = TESTIMAGES_window("step-edges", n, SpecimenOptions(choices: ["orientation": "45"]))
        let dp = diagCanvas.defaultProbe
        #expect(diag[dp.x, dp.y].x == 0 && diag[dp.x + 1, dp.y].x == 1 && diag[c.x, c.y].x == 1 && diag[c.x - 1, c.y].x == 0)
        let (_, clean) = TESTIMAGES_window("noisy-step", n, SpecimenOptions(choices: ["noise": "none"]))
        #expect(clean[447, 300].x == 0.6 && clean[446, 300].x == 0.4)                          // SPEC §5.3 C: 0.40 → 0.60
        let (_, tall) = TESTIMAGES_window("noisy-step", n, SpecimenOptions(choices: ["noise": "none", "height": "1.00", "line": "thin"]))
        #expect(tall[447, 300].x == 1 && tall[446, 300].x == 0 && tall[100, 600].x == 0.9 && tall[100, 599].x == 0)
        let (_, noisy) = TESTIMAGES_window("noisy-step", n)
        let left = (0..<400).map { Double(noisy[$0 + 20, 100].x) }
        let mean = left.reduce(0, +) / 400, sd = (left.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / 400).squareRoot()
        #expect(Swift.abs(mean - 0.4) < 0.005 && Swift.abs(sd - 0.02) < 0.004, "noise mean \(mean) σ \(sd)")
        for intensity in ["1", "10", "100"] {
            let (_, imp) = TESTIMAGES_window("impulse", n, SpecimenOptions(choices: ["intensity": intensity]))
            let v = Float(intensity)!
            #expect(imp[447, 447] == SIMD4(v, v, v, 1) && imp[447, 455].x == 0 && imp.pixels.filter { $0.x > 0 }.count == 1)
        }
        for size in [894, 810] {
            let (_, grid) = TESTIMAGES_window("impulse-grid", size, SpecimenOptions(choices: ["intensity": "100"]))
            let gc = SpecimenGeometry.centre(windowSize: size)
            #expect(grid.pixels.filter { $0.x == 100 }.count == 169, "13 × 13 dots at N = \(size)")
            #expect(grid[gc.x, gc.y].x == 100 && grid[gc.x + 64, gc.y + 64].x == 100 && grid[gc.x + 8, gc.y].x == 0)
        }
        let (_, grid894) = TESTIMAGES_window("impulse-grid", n)
        #expect(grid894[63, 63].x == 1 && grid894[831, 831].x == 1)                            // x, y ∈ {63, 127, …, 831}
        let (_, checker) = TESTIMAGES_window("checkerboard", n)
        #expect(checker[c.x, c.y].x == 1 && checker[c.x + 1, c.y].x == 0 && checker[c.x + 1, c.y + 1].x == 1)
        let (_, checker16) = TESTIMAGES_window("checkerboard", n, SpecimenOptions(choices: ["period": "16"]))
        #expect(checker16[c.x + 7, c.y].x == 1 && checker16[c.x + 8, c.y].x == 0 && checker16[c.x - 1, c.y].x == 0)
        let (_, stripes) = TESTIMAGES_window("stripes", n)
        #expect(stripes[c.x, 0].x == 1 && stripes[c.x + 1, 0].x == 0 && stripes[c.x + 2, 500].x == 1)
        let (_, ramp) = TESTIMAGES_window("ramp", n)
        #expect(Swift.abs(ramp[c.x, c.y].x - 0.5) < 0.001 && ramp[0, 0].x < 0.001 && ramp[n - 1, 0].x > 0.999)
        let (_, encoded) = TESTIMAGES_window("ramp", n, SpecimenOptions(choices: ["encoding": "encoded"]))
        #expect(Swift.abs(Double(encoded[c.x, c.y].x) - SRGB.decode(Double(c.x) / 894 + 0.5 / 894)) < 1e-6)   // libm only in the test
        let (alphaCanvas, alpha) = TESTIMAGES_window("alpha-shape", n)
        #expect(alpha[647, 447] == SIMD4<Float>(0.5, 0, 0, 0.5))                                // on the rim: half covered
        #expect(alpha[c.x, c.y] == SIMD4<Float>(1, 0, 0, 1) && alpha[10, 10] == SIMD4<Float>(0, 0, 0, 0))
        #expect(alphaCanvas.backdrop.w == 1 && alphaCanvas.auxiliary.mask != nil)
        let (shapesCanvas, shapes) = TESTIMAGES_window("alpha-shape", n, SpecimenOptions(choices: ["shape": "squareAndStar"]))
        #expect(shapes[shapesCanvas.defaultProbe.x, shapesCanvas.defaultProbe.y].w == 0.5)      // the square's right rim
        #expect(shapes[c.x - 180, c.y].w == 1 && shapes[c.x + 200, c.y].w == 1 && shapes[c.x + 200, c.y - 140].w == 1)
        #expect(shapes[c.x + 200 + 120, c.y + 120].w == 0)                                    // between the star's points
        let (_, bar) = TESTIMAGES_window("edge-bar", n)
        #expect(bar[0, 10].x == 1 && bar[31, 447].x == 1 && bar[32, 447].x == 0 && bar[40, 447].x == 0)
        let (_, rings) = TESTIMAGES_window("rings", n)
        let crest = (0..<200).map { Double(rings[c.x + 96, c.y - 100 + $0].x) }
        #expect(crest.allSatisfy { $0 >= 0 && $0 <= 1 })
        let (_, material) = TESTIMAGES_window("material-backdrop", n)
        #expect(material[c.x - 1, 700].x == 1 && material[c.x, 700].x == 0)                     // the split at (447, 700)
        #expect(material[100, c.y - 64 - 1] == SIMD4<Float>(1, 0, 1, 1) && material[100, c.y - 64 - 32 * 6] == SIMD4<Float>(1, 0, 0, 1))
        let (_, sun) = TESTIMAGES_window("sun-and-bars", n)
        #expect(sun[c.x, c.y - 120].x == 20 && sun[c.x, c.y + 80].x == SunAndBarsGenerator.sky && sun[c.x + 20, c.y - 120].x == 0)
        let (_, guide) = TESTIMAGES_window("guide-pair", n)
        #expect(guide[c.x, c.y].x != guide[c.x - 16, c.y].x)                                  // a depth edge in the blocks
    }
}

@Suite struct TESTIMAGES_NightCity {
    /// SPEC §11 #1 and ARCHITECTURE §8.2 TESTIMAGES, at N = 894 and N = 810.
    @Test(arguments: [894, 810])
    func statistics(n: Int) throws {
        let layout = NightCityGenerator.layout(windowSize: n)
        let c = SpecimenGeometry.centre(windowSize: n)
        let lights = layout.windowLights.filter { $0.role != .reference }
        #expect(lights.count == 160)
        let points = lights.filter { $0.size == 1 }, blocks = lights.filter { $0.size == 3 }
        #expect(points.count == 120 && blocks.count == 40)
        #expect(points.allSatisfy { $0.intensity >= 20 && $0.intensity <= 1000 })
        #expect(blocks.allSatisfy { $0.intensity >= 2 && $0.intensity <= 100 })
        // Log-uniform: u = ln(I/lo)/ln(hi/lo) is uniform on [0, 1); Kolmogorov–Smirnov at α = 0.01.
        func ks(_ values: [Float], _ lo: Double, _ hi: Double) -> Double {
            let u = values.map { Foundation.log(Double($0) / lo) / Foundation.log(hi / lo) }.sorted()
            var d = 0.0
            for (i, v) in u.enumerated() { d = Swift.max(d, Swift.abs(Double(i + 1) / Double(u.count) - v), Swift.abs(v - Double(i) / Double(u.count))) }
            return d
        }
        let ksPoints = ks(points.map(\.intensity), 20, 1000), ksBlocks = ks(blocks.map(\.intensity), 2, 100)
        print("TESTIMAGES_NIGHTCITY N=\(n) KS points \(ksPoints) blocks \(ksBlocks)")
        #expect(ksPoints < 1.63 / Double(120).squareRoot() && ksBlocks < 1.63 / Double(40).squareRoot())
        // Three colour temperatures, all used.
        for k in 0..<3 { #expect(lights.filter { $0.colour == k }.count >= 10, "colour \(k)") }
        // The reference light: white, 100, 1 px, at c; the clear zone around it.
        let reference = try #require(layout.windowLights.first { $0.role == .reference })
        #expect(reference.x == c.x && reference.y == c.y && reference.intensity == 100 && reference.colour == -1 && reference.size == 1)
        #expect(lights.allSatisfy { Swift.max(abs($0.x - c.x), abs($0.y - c.y)) - $0.size / 2 > NightCityGenerator.clearRadius(windowSize: n) })
        // One pair 20 px apart.
        let pair = lights.filter { $0.role == .pair }
        #expect(pair.count == 2 && abs(pair[0].x - pair[1].x) == 20 && pair[0].y == pair[1].y && pair[0].intensity == pair[1].intensity)
        // A few in a row like a street.
        let street = lights.filter { $0.role == .street }
        #expect(street.count >= 8 && street.allSatisfy { $0.colour == 0 })
        // Exactly three lights within 8 px of the window border; every other light at least 10 px in.
        #expect(lights.filter { $0.borderDistance(windowSize: n) - $0.size / 2 <= 8 }.count == 3)
        #expect(lights.filter { $0.role == .border }.allSatisfy { $0.borderDistance(windowSize: n) <= 8 && $0.borderDistance(windowSize: n) - $0.size / 2 >= 0 })
        // Poisson-disc: no two lights closer than 40 px, except the deliberate pair and street spacing.
        let spaced = Set(lights.filter { $0.role == .poisson || $0.role == .border })
        for (i, a) in lights.enumerated() {
            for b in lights[(i + 1)...] where spaced.contains(a) || spaced.contains(b) {
                let d = Double((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
                #expect(d >= NightCityGenerator.minimumDistance, "lights \(a) and \(b) are \(d) px apart")
            }
        }
        // The canvas carries exactly these lights; the margin continues the city.
        let (canvas, window) = TESTIMAGES_window("night-city", n)
        for light in layout.windowLights {
            let p = window[light.x, light.y]
            #expect(Swift.max(p.x, Swift.max(p.y, p.z)) == light.intensity, "light at (\(light.x), \(light.y))")
        }
        let margin = layout.lights.filter { $0.role == .margin }
        #expect(margin.count > 100 && margin.allSatisfy { $0.x + $0.size / 2 < 0 || $0.y + $0.size / 2 < 0 || $0.x - $0.size / 2 >= n || $0.y - $0.size / 2 >= n })
        // Buildings: every non-light, non-sky pixel is a silhouette with every channel in 0.02–0.06.
        let lightPixels = Set(layout.lights.flatMap { l in (-(l.size / 2)...(l.size / 2)).flatMap { dy in (-(l.size / 2)...(l.size / 2)).map { dx in (l.y + dy + 256) * canvas.image.width + l.x + dx + 256 } } })
        var buildings = 0, stray = 0
        for (k, p) in canvas.image.pixels.enumerated() where !lightPixels.contains(k) && p != SIMD4<Float>(0, 0, 0, 1) {
            if p.w == 1 && [p.x, p.y, p.z].allSatisfy({ $0 >= 0.0199 && $0 <= 0.0601 }) { buildings += 1 } else { stray += 1 }
        }
        #expect(stray == 0 && buildings > 100_000)
        // HDR: the brightest light stays below fp16's maximum even at +6 EV.
        let peak = window.pixels.map { Swift.max($0.x, Swift.max($0.y, $0.z)) }.max() ?? 0
        #expect(peak >= 100 && peak <= 1000 && peak * 64 < 65_504)
        // SPEC §5.3 D: within 20 px of the probe only the reference light shines (a 16-px hexagon sees it alone).
        var sum: Float = 0
        for y in (c.y + 8 - 20)...(c.y + 8 + 20) { for x in (c.x - 20)...(c.x + 20) { sum += window[x, y].x } }
        #expect(sum == 100)
    }

    /// Small windows (the SKEL and gpucheck seeds use N = 96…256) still get a valid scene.
    @Test(arguments: [96, 128, 256])
    func smallWindows(n: Int) {
        let (canvas, window) = TESTIMAGES_window("night-city", n)
        let c = SpecimenGeometry.centre(windowSize: n)
        #expect(window[c.x, c.y] == SIMD4<Float>(100, 100, 100, 1) && window[c.x, c.y + 8] == SIMD4<Float>(0, 0, 0, 1))
        #expect(canvas.image.width == n + 512)
    }

    /// The launch fixture: at σ 12, 0 EV, at least 40 lights keep a blurred peak ≥ 0.25 linear (SPEC §11 #1 predicts about
    /// 60, MODELED from the distribution), computed with GaussianOperator's reference on the 894 window.
    @Test func launchFixture() throws {
        let n = 894
        let (_, window) = TESTIMAGES_window("night-city", n)
        let request = OperatorRequest(parameters: ParameterValues(["sigma": .double(12), "truncation": .choice("3")]),
                                      variant: GaussianOperator.separable, size: .square(n))
        let blurred = try BlurReference.run(GaussianOperator(), input: window, request, options: .exact).output
        let layout = NightCityGenerator.layout(windowSize: n)
        var bright = 0
        for light in layout.windowLights {
            var peak: Float = 0
            let h = light.size / 2 + 1
            for y in (light.y - h)...(light.y + h) where y >= 0 && y < n {
                for x in (light.x - h)...(light.x + h) where x >= 0 && x < n {
                    let p = blurred[x, y]
                    peak = Swift.max(peak, Swift.max(p.x, Swift.max(p.y, p.z)))
                }
            }
            if peak >= 0.25 { bright += 1 }
        }
        print("TESTIMAGES_LAUNCH lights with blurred peak ≥ 0.25 at σ 12, 0 EV: \(bright) of \(layout.windowLights.count)")
        #expect(bright >= 40)
    }
}

@Suite struct TESTIMAGES_Auxiliary {
    @Test func sceneDepthBuffer() throws {
        let (canvas, image) = TESTIMAGES_window("scene-depth")
        let c = SpecimenGeometry.centre(windowSize: 894)
        let depth = try #require(canvas.window(pan: .zero).auxiliary.depth)
        #expect(depth[c.x + 130, 100] == SceneDepthGenerator.barDepth && depth[c.x, 10] == SceneDepthGenerator.skyDepth)
        #expect(depth[c.x, c.y + 100] < depth[c.x, c.y] && depth[c.x, c.y] < depth[c.x, c.y - 150])   // recedes upwards
        let lights = image.pixels.filter { Swift.max($0.x, Swift.max($0.y, $0.z)) > 1 }.count
        #expect(lights > 200, "HDR lights on the plane: \(lights)")
        let p = canvas.defaultProbe
        #expect(depth[p.x, p.y] > SceneDepthGenerator.barDepth && depth[p.x + 1, p.y] == SceneDepthGenerator.barDepth)   // the bar's edge
    }

    @Test func sceneMotionBuffers() throws {
        let n = 256
        for count in [4, 8, 16] {
            let (canvas, _) = TESTIMAGES_window("scene-motion", n, SpecimenOptions(choices: ["subFrames": "\(count)"]))
            #expect(canvas.auxiliary.subFrames?.count == count)
        }
        let (canvas, image) = TESTIMAGES_window("scene-motion", n)
        let c = SpecimenGeometry.centre(windowSize: n)
        let content = canvas.window(pan: .zero)
        let velocity = try #require(content.auxiliary.velocity), depth = try #require(content.auxiliary.depth)
        let frames = try #require(content.auxiliary.subFrames)
        #expect(frames.count == 8 && SceneMotionGenerator.subFrameTimes(8).first == -0.4375)
        #expect(velocity.values[c.y * n + c.x] == SIMD2<Float>(24, 0) && depth[c.x, c.y] == 3)
        #expect(velocity.values[5 * n + 5] == .zero && depth[5, 5] == 10)
        // The disc covers c in every sub-frame (it moves ±12 px): accumulation keeps its colour there.
        let mean = frames.map { $0[c.x, c.y] }.reduce(SIMD4<Float>.zero, +) / Float(frames.count)
        #expect(Swift.abs(mean.x - 1) < 1e-6 && image[c.x, c.y] == SIMD4<Float>(1, 0.55, 0.12, 1))
        // Static background is pixel-identical in every sub-frame (SPEC §5.2: accumulation leaves static parts unchanged).
        #expect(frames.allSatisfy { $0[3, n - 3] == image[3, n - 3] })
        // The trailing rim at the probe is half covered at frame 0 and changes across the shutter.
        let p = canvas.defaultProbe
        #expect(Set(frames.map { $0[p.x, p.y].x }).count > 1)
        let bar = SceneMotionGenerator.Geometry(c: SpecimenGeometry.centre(windowSize: 894), time: 0)
        #expect(bar.onBar(bar.pivot.x + 50 * bar.axis.x, bar.pivot.y + 50 * bar.axis.y))
    }

    @Test func guidePairBuffers() throws {
        let (canvas, image) = TESTIMAGES_window("guide-pair")
        let c = SpecimenGeometry.centre(windowSize: 894)
        let content = canvas.window(pan: .zero)
        let depth = try #require(content.auxiliary.depth), guide = try #require(content.auxiliary.guide)
        #expect(depth[c.x, c.y] == 2 && depth[c.x - 1, c.y] > 5)                              // the true edge at the probe
        #expect(image[c.x - 5, c.y] == image[c.x - 8, c.y])                                   // blocky: constant inside a 16-px block
        #expect(guide[c.x + 100, c.y] != guide[c.x - 100, c.y + 200])                         // the guide's colour follows the depth
        #expect(content.auxiliary.depth!.width == 894)
    }

    @Test func masks() throws {
        let (alpha, _) = TESTIMAGES_window("alpha-shape")
        let mask = try #require(alpha.auxiliary.mask)
        #expect(zip(mask.values, alpha.image.pixels).allSatisfy { $0 == $1.w })
        let (sun, _) = TESTIMAGES_window("sun-and-bars")
        let sunMask = try #require(sun.window(pan: .zero).auxiliary.mask)
        let c = SpecimenGeometry.centre(windowSize: 894)
        #expect(sunMask[c.x + 20, c.y - 120] == 0 && sunMask[c.x, c.y - 120] == 1)
    }

    /// `window(pan:)` crops the image and every auxiliary buffer together, exactly as the GPU blit copies them.
    @Test func panCropsAuxiliariesTogether() throws {
        let (canvas, _) = TESTIMAGES_window("scene-depth", 256)
        for pan in [PixelPoint(x: 256, y: -256), PixelPoint(x: -100, y: 37)] {
            let content = canvas.window(pan: pan)
            let ox = 256 + pan.x, oy = 256 + pan.y
            #expect(content.image[10, 20] == canvas.image[ox + 10, oy + 20])
            #expect(content.auxiliary.depth![10, 20] == canvas.auxiliary.depth![ox + 10, oy + 20])
        }
    }
}

@Suite struct TESTIMAGES_Photo {
    @Test func areaAverageShrinksAndEnlargesExactly() {
        // 4 → 2: each output pixel is the mean of a 2 × 2 block.
        let src: [[SIMD4<Float>]] = (0..<4).map { y in (0..<4).map { x in SIMD4(Float(x + 4 * y), 0, 0, 1) } }
        let half = PhotoSpecimen.areaAverage(sourceSide: 4, targetSide: 2) { src[$0] }
        #expect(half[0, 0].x == (0 + 1 + 4 + 5) / 4 && half[1, 1].x == (10 + 11 + 14 + 15) / 4 && half[1, 1].w == 1)
        // 2 → 3: overlap weights (⅔ and ⅓) for the middle pixel.
        let two: [[SIMD4<Float>]] = [[SIMD4(0, 0, 0, 1), SIMD4(3, 0, 0, 1)], [SIMD4(0, 0, 0, 1), SIMD4(3, 0, 0, 1)]]
        let three = PhotoSpecimen.areaAverage(sourceSide: 2, targetSide: 3) { two[$0] }
        #expect(three[0, 0].x == 0 && Swift.abs(three[1, 0].x - 1.5) < 1e-6 && three[2, 0].x == 3)
        for (n, m) in [(4284, 1406), (300, 1406), (1406, 1406)] {
            let w = PhotoSpecimen.overlapWeights(sourceSide: n, targetSide: m)
            #expect(w.allSatisfy { Swift.abs($0.reduce(0) { $0 + $1.1 } - 1) < 1e-9 })
        }
    }

    @Test func uniformPhotoStaysUniformAndCaptionStatesTheBox() {
        let grey = SIMD4<Float>(0.25, 0.5, 0.75, 1)
        let canvas = PhotoSpecimen.canvas(cropSide: 1000, windowSize: 128) { _ in Array(repeating: grey, count: 1000) }
        #expect(canvas.image.width == 640 && canvas.id == "photo" && canvas.defaultProbe == PixelPoint(x: 64, y: 64))
        #expect(canvas.image.pixels.allSatisfy { Swift.abs($0.x - 0.25) < 1e-6 && Swift.abs($0.z - 0.75) < 1e-6 })
        #expect(canvas.caption == "PHOTO · RESAMPLED ×0.64 (BOX)")
        #expect(PhotoSpecimen.caption(sourceSide: 4284, targetSide: 1406) == "PHOTO · RESAMPLED ×0.33 (BOX)")
        #expect(PhotoSpecimen.centreCrop(width: 5712, height: 4284) == (714, 0, 4284))
        let empty = PhotoGenerator().canvas(windowSize: 128, margin: 256, options: .standard, text: nil)
        #expect(empty.caption == "NO PHOTO CHOSEN")
    }
}

@Suite struct TESTIMAGES_Text {
    /// With a coverage mask the text image puts white glyphs on black (left) and black on white (right), and the default
    /// probe lands on the first stem of the 12-px line. (The app renders the mask with Core Text; here a synthetic mask.)
    @Test func coverageDrivesBothHalvesAndTheProbe() {
        let n = 894, side = n + 512, c = SpecimenGeometry.centre(windowSize: n)
        var values = [Float](repeating: 0, count: side * side)
        let line = TextSpecimenLayout.lines[TextSpecimenLayout.probeLine]
        for (start, _) in [(TextSpecimenLayout.leftStart, 0), (TextSpecimenLayout.rightStart, 1)] {
            for y in (c.y + line.baseline - 9)..<(c.y + line.baseline) {          // a 2-px stem 3 px after the line start
                for x in (c.x + start + 3)..<(c.x + start + 5) { values[(y + 256) * side + x + 256] = 1 }
            }
        }
        let mask = TextCoverage(mask: ScalarBuffer(width: side, height: side, values: values))
        let (canvas, image) = TESTIMAGES_window("text", n, text: mask)
        let p = canvas.defaultProbe
        #expect(p.x == c.x + TextSpecimenLayout.leftStart + 3 && image[p.x, p.y].x == 1 && canvas.caption == nil)
        #expect(image[c.x + TextSpecimenLayout.rightStart + 3, c.y + line.baseline - 3].x == 0 && image[c.x + 100, c.y].x == 1)
        let (material, mImage) = TESTIMAGES_window("material-backdrop", n, text: mask)
        #expect(material.caption == nil && mImage[c.x, c.y].x == 1)
        let (noisy, _) = TESTIMAGES_window("text", n, SpecimenOptions(choices: ["noise": "saltAndPepper", "amount": "20"]), text: mask)
        let noisyWindow = noisy.window(pan: .zero).image
        var salt = 0
        for y in 0..<200 { for x in 0..<40 where noisyWindow[x, y].x == 1 { salt += 1 } }   // black far from the text
        let share = Double(salt) / 8000                                                     // half of 20 % turn white
        #expect(share > 0.08 && share < 0.12, "salt share \(share)")
    }
}
