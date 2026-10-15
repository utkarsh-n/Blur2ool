import Foundation
import CryptoKit
import Testing
@testable import BlurCore

// OWNER: TESTIMAGES. CORE tests of the 22 test images (ARCHITECTURE §5.6, §8.2 TESTIMAGES; SPEC §11): the registry and
// descriptors, canvas geometry and value ranges, exposure (canvases are always generated at 0 EV), determinism (SHA-256 of
// the canonical canvas bytes, twice, at N = 894 and N = 810, equal to the fixture the phone AppTest compares with,
// review fix E-22) and BlurCore's own transcendental functions.

/// SHA-256 (hex) of a canvas's canonical byte stream.
func TESTIMAGES_sha256(_ canvas: SpecimenCanvas) -> String {
    var hasher = SHA256()
    canvas.forEachCanonicalChunk { hasher.update(bufferPointer: $0) }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

/// The Mac hashes recorded in Tests/AppTests/TESTIMAGES/TESTIMAGESCanvasHashes.swift (the fixture the phone compares with).
func TESTIMAGES_recordedHashes() -> [String: String] {
    let here = URL(fileURLWithPath: #filePath)
    let fixture = here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("AppTests/TESTIMAGES/TESTIMAGESCanvasHashes.swift")
    guard let text = try? String(contentsOf: fixture, encoding: .utf8) else { return [:] }
    var out: [String: String] = [:]
    let pattern = /"([a-z-]+@[0-9]+)": "([0-9a-f]{64})"/
    for match in text.matches(of: pattern) { out[String(match.1)] = String(match.2) }
    return out
}

let TESTIMAGES_specIDs: [String] = ["night-city", "siemens-star", "zone-plate", "step-edges", "noisy-step", "impulse", "impulse-grid",
                                    "checkerboard", "stripes", "text", "ramp", "noise-field", "alpha-shape", "edge-bar", "rings",
                                    "material-backdrop", "scene-depth", "scene-motion", "aerial", "sun-and-bars", "guide-pair", "photo"]

@Suite struct TESTIMAGES_Registry {
    @Test func allTwentyTwoRegisteredInSpecOrder() {
        #expect(SpecimenRegistry.generators.count == 22)
        #expect(SpecimenRegistry.generators.map(\.descriptor.id.rawValue) == TESTIMAGES_specIDs)
        #expect(SpecimenCatalog.ids.map(\.rawValue) == TESTIMAGES_specIDs)
        for id in TESTIMAGES_specIDs { #expect(SpecimenRegistry.generator(SpecimenID(rawValue: id)) != nil, "\(id)") }
        #expect(Set(SpecimenRegistry.generators.map(\.descriptor.menuName)).count == 22)
    }

    @Test func flagsFollowSpec() {
        let byID = Dictionary(uniqueKeysWithValues: SpecimenRegistry.generators.map { ($0.descriptor.id.rawValue, $0.descriptor) })
        // SPEC §11 rule 5: exposure multiplies the light-carrying images only.
        let light: Set<String> = ["night-city", "impulse", "impulse-grid", "scene-depth", "sun-and-bars"]
        for (id, d) in byID {
            #expect(d.supportsExposure == light.contains(id), "\(id) supportsExposure")
            #expect(d.isHDR == light.contains(id), "\(id) isHDR")
            #expect(d.needsTextCoverage == ["text", "material-backdrop"].contains(id), "\(id) needsTextCoverage")
            #expect(d.animated == (id == "scene-motion"), "\(id) animated")
            #expect(!d.reveals.isEmpty && !d.menuName.isEmpty)
        }
        // SPEC §11 rule 4: periodic high-contrast images are marked HIGH-CONTRAST PATTERN.
        for id in ["siemens-star", "zone-plate", "checkerboard", "stripes", "rings", "aerial", "noise-field", "scene-motion"] {
            #expect(byID[id]?.isHighContrastPattern == true, "\(id)")
        }
        for id in ["night-city", "step-edges", "impulse", "ramp", "photo", "text"] { #expect(byID[id]?.isHighContrastPattern == false, "\(id)") }
    }

    @Test func optionDefaultsAreAmongTheirChoices() {
        for g in SpecimenRegistry.generators {
            for spec in g.descriptor.options {
                switch (spec.kind, spec.defaultValue) {
                case (.choice(let c), .choice(let v)): #expect(c.options.contains { $0.id == v }, "\(g.descriptor.id) \(spec.key)")
                case (.continuous(let c), .double(let v)): #expect(c.range.contains(v))
                default: Issue.record("\(g.descriptor.id) \(spec.key): unexpected option kind")
                }
            }
        }
        // The option keys named in the frozen SpecimenOptions documentation.
        let keys = Dictionary(uniqueKeysWithValues: SpecimenRegistry.generators.map { ($0.descriptor.id.rawValue, Set($0.descriptor.options.map(\.key.rawValue))) })
        #expect(keys["noisy-step"]?.contains("height") == true)
        #expect(keys["text"]?.contains("noise") == true)
        #expect(keys["checkerboard"]?.contains("period") == true)
        #expect(keys["step-edges"]?.contains("orientation") == true)
    }
}

@Suite struct TESTIMAGES_CanvasGeometry {
    /// Canvas size (N + 512)², id, 0 EV options, probe inside the window, finite non-negative premultiplied values, aux sizes.
    @Test(arguments: TESTIMAGES_specIDs)
    func canvasIsWellFormed(id: String) throws {
        let g = try #require(SpecimenRegistry.generator(SpecimenID(rawValue: id)))
        for n in [894, 810] {
            let canvas = g.canvas(windowSize: n, margin: SpecimenGeometry.margin, options: .standard, text: nil)
            let side = n + 512
            #expect(canvas.id.rawValue == id && canvas.windowSize == n && canvas.margin == 256)
            #expect(canvas.image.width == side && canvas.image.height == side)
            #expect(canvas.options.exposureEV == 0)
            #expect(ImageSize.square(n).contains(canvas.defaultProbe), "\(id) probe \(canvas.defaultProbe)")
            var bad = 0, overOne = 0
            for p in canvas.image.pixels {
                if !(p.x.isFinite && p.y.isFinite && p.z.isFinite && p.w.isFinite) || p.x < 0 || p.y < 0 || p.z < 0 || p.w < 0 || p.w > 1 { bad += 1 }
                if Swift.max(p.x, Swift.max(p.y, p.z)) > p.w + 1e-6 { overOne += 1 }
            }
            #expect(bad == 0, "\(id): \(bad) non-finite, negative or alpha > 1 values")
            if !g.descriptor.isHDR { #expect(overOne == 0, "\(id): SDR image with \(overOne) premultiplied values above alpha") }
            let a = canvas.auxiliary
            if let d = a.depth { #expect(d.width == side && d.height == side && d.values.allSatisfy { $0.isFinite && $0 > 0 }) }
            if let v = a.velocity { #expect(v.width == side && v.height == side) }
            if let gd = a.guide { #expect(gd.width == side && gd.height == side) }
            if let mk = a.mask { #expect(mk.width == side && mk.height == side && mk.values.allSatisfy { $0 >= 0 && $0 <= 1 }) }
            for f in a.subFrames ?? [] { #expect(f.width == side && f.height == side) }
            // The window is exactly the N × N region at the margin (pan 0), with cropped auxiliaries.
            let window = canvas.window(pan: .zero)
            #expect(window.image.width == n && window.image[0, 0] == canvas.image[256, 256])
            #expect(window.image[n - 1, n - 1] == canvas.image[256 + n - 1, 256 + n - 1])
            if let d = window.auxiliary.depth { #expect(d.width == n && d[0, 0] == a.depth![256, 256]) }
        }
    }

    /// Canvases ignore exposure: they are generated at 0 EV and EXPOSURE is applied at render time (SPEC §11 rule 5, E-10).
    @Test(arguments: ["night-city", "impulse", "impulse-grid", "scene-depth", "sun-and-bars", "siemens-star"])
    func exposureIsNotInTheCanvas(id: String) throws {
        let g = try #require(SpecimenRegistry.generator(SpecimenID(rawValue: id)))
        let plain = g.canvas(windowSize: 256, margin: SpecimenGeometry.margin, options: .standard, text: nil)
        for ev in [-2, 4, 6] {
            let lit = g.canvas(windowSize: 256, margin: SpecimenGeometry.margin, options: SpecimenOptions(exposureEV: ev), text: nil)
            #expect(lit.image == plain.image && lit.options.exposureEV == 0, "\(id) at \(ev) EV")
            #expect(TESTIMAGES_sha256(lit) == TESTIMAGES_sha256(plain))
        }
    }
}

@Suite struct TESTIMAGES_Determinism {
    /// SHA-256 of the canonical canvas bytes, twice, at N = 894 and N = 810; equal to the recorded Mac fixture that the
    /// phone AppTest (Tests/AppTests/TESTIMAGES) compares its own hashes with.
    @Test(arguments: TESTIMAGES_specIDs)
    func hashesAreStableAndRecorded(id: String) throws {
        let g = try #require(SpecimenRegistry.generator(SpecimenID(rawValue: id)))
        let recorded = TESTIMAGES_recordedHashes()
        for n in [894, 810] {
            let first = TESTIMAGES_sha256(g.canvas(windowSize: n, margin: SpecimenGeometry.margin, options: .standard, text: nil))
            let second = TESTIMAGES_sha256(g.canvas(windowSize: n, margin: SpecimenGeometry.margin, options: .standard, text: nil))
            print("TESTIMAGES_HASH \(id)@\(n) \(first)")
            #expect(first == second, "\(id)@\(n): two runs differ")
            #expect(recorded["\(id)@\(n)"] == first, "\(id)@\(n): fixture \(recorded["\(id)@\(n)"] ?? "missing") ≠ computed \(first)")
        }
    }

    /// Options and the stochastic seed override change the canvas; the same options reproduce it.
    @Test func optionsAreDeterministicToo() {
        let cases: [(any SpecimenGenerating, SpecimenOptions)] = [
            (NoisyStepGenerator(), SpecimenOptions(choices: ["height": "1.00", "line": "thin"])),
            (NoisyStepGenerator(), SpecimenOptions(choices: ["noise": "none"])),
            (TextSpecimenGenerator(), SpecimenOptions(choices: ["noise": "saltAndPepper", "amount": "30"])),
            (RampGenerator(), SpecimenOptions(choices: ["encoding": "encoded", "noise": "gaussian"])),
            (CheckerboardGenerator(), SpecimenOptions(choices: ["period": "16"])),
            (AlphaShapeGenerator(), SpecimenOptions(choices: ["shape": "squareAndStar"])),
            (StepEdgesGenerator(), SpecimenOptions(choices: ["orientation": "45"])),
            (RingsGenerator(), SpecimenOptions(seed: 77)),
        ]
        for (g, options) in cases {
            let a = g.canvas(windowSize: 128, margin: 256, options: options, text: nil)
            let b = g.canvas(windowSize: 128, margin: 256, options: options, text: nil)
            let standard = g.canvas(windowSize: 128, margin: 256, options: .standard, text: nil)
            #expect(TESTIMAGES_sha256(a) == TESTIMAGES_sha256(b), "\(g.descriptor.id) \(options.choices)")
            #expect(a.image != standard.image, "\(g.descriptor.id) \(options.choices) must change the image")
        }
    }
}

@Suite struct TESTIMAGES_SpecimenMath {
    /// BlurCore's own functions agree with the platform's libm to ≈ 1 ulp (they must not CALL it: E-22).
    @Test func transcendentalsMatchLibm() {
        var rng = SpecimenRandom(seed: 99)
        var worst: [String: Double] = [:]
        func note(_ name: String, _ ours: Double, _ libm: Double) {
            let err = Swift.abs(ours - libm) / Swift.max(Swift.abs(libm).ulp, Double.leastNormalMagnitude)
            worst[name] = Swift.max(worst[name] ?? 0, err)
        }
        for _ in 0..<20_000 {
            let x = (rng.nextUnit() - 0.5) * 6000
            note("sin", SpecimenMath.sin(x), Foundation.sin(x))
            note("cos", SpecimenMath.cos(x), Foundation.cos(x))
            let y = (rng.nextUnit() - 0.5) * 2000, z = (rng.nextUnit() - 0.5) * 2000
            note("atan2", SpecimenMath.atan2(y, z), Foundation.atan2(y, z))
            let e = (rng.nextUnit() - 0.5) * 60
            note("exp", SpecimenMath.exp(e), Foundation.exp(e))
            let l = rng.nextUnit() * 1e6 + 1e-9
            note("log", SpecimenMath.log(l), Foundation.log(l))
            let b = rng.nextUnit()
            note("pow2.4", SpecimenMath.pow(b, 2.4), Foundation.pow(b, 2.4))
        }
        // Absolute-argument sin/cos near multiples of π lose relative accuracy in ANY implementation; bound in ulps of 1.
        for (name, ulps) in worst { print("TESTIMAGES_MATH \(name) worst \(ulps) ulp") }
        #expect((worst["exp"] ?? 99) <= 4 && (worst["log"] ?? 99) <= 4 && (worst["atan2"] ?? 99) <= 4)
        #expect((worst["pow2.4"] ?? 99) <= 64)
        for _ in 0..<2_000 {
            let x = (rng.nextUnit() - 0.5) * 6000
            #expect(Swift.abs(SpecimenMath.sin(x) - Foundation.sin(x)) < 1e-12)
            #expect(Swift.abs(SpecimenMath.cos(x) - Foundation.cos(x)) < 1e-12)
        }
        #expect(SpecimenMath.atan2(0, -1) == SpecimenMath.pi && SpecimenMath.atan2(-1e-300, -1) < 0)
        #expect(SpecimenMath.atan2(1, 0) == SpecimenMath.halfPi && SpecimenMath.atan2(0, 0) == 0)
        #expect(SpecimenMath.exp(0) == 1 && SpecimenMath.log(1) == 0)
        #expect(SpecimenMath.floorDiv(-1, 64) == -1 && SpecimenMath.floorDiv(-64, 64) == -1 && SpecimenMath.floorDiv(63, 64) == 0)
    }

    /// PCG32 reference outputs (O'Neill's pcg32-demo, srandom(42, 54)).
    @Test func pcg32MatchesTheReferenceStream() {
        var rng = SpecimenRandom(seed: 42, stream: 54)
        let expected: [UInt32] = [0xa15c_02b7, 0x7b47_f409, 0xba1d_3330, 0x83d2_f293, 0xbfa4_784b, 0xcbed_606e]
        #expect((0..<6).map { _ in rng.next32() } == expected)
        var u = SpecimenRandom(seed: 7)
        let draws = (0..<10_000).map { _ in u.nextUnit() }
        #expect(draws.allSatisfy { $0 >= 0 && $0 < 1 })
        #expect(Swift.abs(draws.reduce(0, +) / 10_000 - 0.5) < 0.01)
        var lu = SpecimenRandom(seed: 7, stream: 9)
        #expect((0..<2_000).map { _ in lu.nextLogUniform(20, 1000) }.allSatisfy { $0 >= 20 && $0 <= 1000 })
    }

    /// Gaussian noise has the stated σ (Box–Muller with BlurCore's log/cos).
    @Test func noiseHasUnitVariance() {
        var sum = 0.0, sq = 0.0
        let n = 200 * 200
        for y in -100..<100 { for x in -100..<100 { let z = SpecimenNoise.gaussian(dx: x, dy: y, seed: 1); sum += z; sq += z * z } }
        let mean = sum / Double(n), variance = sq / Double(n) - mean * mean
        #expect(Swift.abs(mean) < 0.02 && Swift.abs(variance - 1) < 0.03, "mean \(mean) variance \(variance)")
    }
}

@Suite struct TESTIMAGES_Honesty {
    /// Menu text carries no unbadged numbers (§5.1: digits belong in BadgedValues or deliberate literals) and no placeholder
    /// words; captions are the few engravings SPEC §11 asks for.
    @Test func menuTextAndCaptionsAreHonest() {
        let placeholders = ["todo", "lorem", "placeholder", "tbd", "fixme"]
        for g in SpecimenRegistry.generators {
            let d = g.descriptor
            for text in [d.menuName, d.reveals] {
                #expect(!text.contains { $0.isNumber }, "\(d.id): digits in menu text '\(text)'")
                #expect(!placeholders.contains { text.lowercased().contains($0) }, "\(d.id): placeholder in '\(text)'")
            }
            let caption = g.canvas(windowSize: 128, margin: 256, options: .standard, text: nil).caption
            if let caption {
                let allowed = caption == "36 CYCLES" || caption == "NO PHOTO CHOSEN" || caption.hasSuffix("· CORE TEXT RUNS IN THE APP")
                #expect(allowed, "\(d.id): unexpected caption '\(caption)'")
            }
        }
        // The photo caption states the resample as a box blur (SPEC §11 #22).
        #expect(PhotoSpecimen.caption(sourceSide: 3000, targetSide: 1406).wholeMatch(of: /PHOTO · RESAMPLED ×[0-9]+\.[0-9]{2} \(BOX\)/) != nil)
    }
}
