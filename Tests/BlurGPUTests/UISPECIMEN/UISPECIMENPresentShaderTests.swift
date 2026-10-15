import Foundation
import Metal
import Testing
@testable import BlurCore
@testable import BlurGPU

// OWNER: UI-SPECIMEN. The present pass (App/GPU/Shaders/B2Present.metal, ARCHITECTURE §6.5) on the Mac GPU, compiled from
// App/GPU/Shaders with ParityRunner.compileLibrary exactly as blur-gpucheck compiles it (one translation unit, fast math):
// 1 : 1 present = SRGB.code8 per pixel; nearest zoom replicates texels; split and Wipe land on the requested column;
// Difference × gain is exact; Flip, Line-up, crop (periscope and the loupe's 14 × 14 copy), preview upscaling, the
// rubber-band shift, EDR and missing textures. No simulator is involved (Documentation/HOLD-SIMULATOR.md).

/// Field-for-field mirror of `B2PresentParams` (B2Present.metal static_asserts 144 bytes) and of the app's
/// `PresentShaderParams` (App/Render/PresentGeometry.swift; the phone AppTest checks that one).
struct UISPECIMEN_PresentParams {
    var backdrop = SIMD4<Float>(0, 0, 0, 1)
    var contour = SIMD4<Float>(0, 0, 0, 0)
    var ratioAB = SIMD4<Float>(1, 1, 1, 1)
    var ratioCD = SIMD4<Float>(1, 1, 1, 1)
    var origin = SIMD2<Float>(0, 0)
    var texelsPerPixel = SIMD2<Float>(1, 1)
    var lineUpOrigin = SIMD2<Float>(0, 0)
    var drawableSize = SIMD2<Float>(0, 0)
    var shift = SIMD2<Int32>(0, 0)
    var splitColumn: Int32 = -1
    var mode: UInt32 = 0
    var edr: UInt32 = 0
    var available: UInt32 = 1
    var gain: Float = 1
    var contourStep: Float = 0
    var showB: UInt32 = 0
    var reserved0: UInt32 = 0
    var reserved1: UInt32 = 0
    var reserved2: UInt32 = 0
}

/// Renders the present pass offscreen on the Mac GPU and reads the drawable back.
@MainActor
final class UISPECIMEN_PresentHarness {
    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let library: any MTLLibrary
    let compiledFrom: String
    private var pipelines: [MTLPixelFormat.RawValue: any MTLRenderPipelineState] = [:]
    private let dummy: any MTLTexture

    static func make() throws -> UISPECIMEN_PresentHarness? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return try UISPECIMEN_PresentHarness(device: device)
    }

    private init(device: any MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else { throw GPUError.unsupported("no command queue") }
        self.queue = queue
        let directory = UISPECIMEN_PresentHarness.shaderDirectory()
        do {
            library = try ParityRunner.compileLibrary(device: device, shaderDirectory: directory).library
            compiledFrom = "every App/GPU/Shaders/*.metal (one translation unit)"
        } catch {
            // A neighbour's half-finished family file must not hide the present shader's own result: compile the three
            // files the present pass needs, still through ParityRunner.compileLibrary, and say so in the output.
            let subset = FileManager.default.temporaryDirectory.appendingPathComponent("b2-uispecimen-shaders-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: subset, withIntermediateDirectories: true)
            for name in ["B2Shared.h", "B2Common.metal", "B2Present.metal"] {
                try FileManager.default.copyItem(at: directory.appendingPathComponent(name), to: subset.appendingPathComponent(name))
            }
            library = try ParityRunner.compileLibrary(device: device, shaderDirectory: subset).library
            compiledFrom = "B2Shared.h + B2Common.metal + B2Present.metal (the full directory failed: \(error))"
            print("UISPECIMEN_PresentHarness: \(compiledFrom)")
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 1, height: 1, mipmapped: false)
        d.usage = .shaderRead; d.storageMode = .shared
        guard let dummy = device.makeTexture(descriptor: d) else { throw GPUError.textureAllocationFailed("dummy") }
        var zero = [Float16](repeating: 0, count: 4)
        dummy.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &zero, bytesPerRow: 8)
        self.dummy = dummy
    }

    static func shaderDirectory() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("App/GPU/Shaders")
    }

    private func pipeline(_ format: MTLPixelFormat) throws -> any MTLRenderPipelineState {
        if let p = pipelines[format.rawValue] { return p }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "b2_common_fullscreen_vs")
        descriptor.fragmentFunction = library.makeFunction(name: "b2_present_fs")
        descriptor.colorAttachments[0].pixelFormat = format
        let p = try device.makeRenderPipelineState(descriptor: descriptor)
        pipelines[format.rawValue] = p
        return p
    }

    /// An rgba16Float texture holding `texels` (row-major), rounded to fp16 exactly as the app's textures are.
    func texture(_ texels: [SIMD4<Float>], width: Int, height: Int) throws -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        d.usage = .shaderRead; d.storageMode = .shared
        guard let t = device.makeTexture(descriptor: d) else { throw GPUError.textureAllocationFailed("source") }
        var halves = texels.flatMap { [Float16($0.x), Float16($0.y), Float16($0.z), Float16($0.w)] }
        t.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: &halves, bytesPerRow: width * 8)
        return t
    }

    func uniform(_ value: SIMD4<Float>, side: Int) throws -> any MTLTexture {
        try texture([SIMD4<Float>](repeating: value, count: side * side), width: side, height: side)
    }

    /// Draws one present pass into a `width × height` drawable of `format` and returns its pixels (row-major).
    private func draw(_ params: UISPECIMEN_PresentParams, slots: [(any MTLTexture)?], width: Int, height: Int,
                      format: MTLPixelFormat) async throws -> any MTLTexture {
        var p = params
        p.drawableSize = SIMD2(Float(width), Float(height))
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
        d.usage = .renderTarget; d.storageMode = .shared
        guard let target = device.makeTexture(descriptor: d), let cb = queue.makeCommandBuffer() else {
            throw GPUError.textureAllocationFailed("drawable")
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 0, blue: 1, alpha: 1)   // magenta: never expected
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = cb.makeRenderCommandEncoder(descriptor: pass) else { throw GPUError.unsupported("encoder") }
        encoder.setRenderPipelineState(try pipeline(format))
        for index in 0..<4 { encoder.setFragmentTexture(index < slots.count ? (slots[index] ?? dummy) : dummy, index: index) }
        encoder.setFragmentBytes(&p, length: MemoryLayout<UISPECIMEN_PresentParams>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in cb.addCompletedHandler { _ in c.resume() }; cb.commit() }
        if let error = cb.error { throw GPUError.commandBufferFailed("\(error)") }
        return target
    }

    /// SDR: bgra8Unorm drawable, returned as (r, g, b, a) codes.
    func presentSDR(_ params: UISPECIMEN_PresentParams, slots: [(any MTLTexture)?], width: Int, height: Int) async throws -> [SIMD4<Int>] {
        let target = try await draw(params, slots: slots, width: width, height: height, format: .bgra8Unorm)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return (0..<(width * height)).map { i in SIMD4(Int(bytes[4 * i + 2]), Int(bytes[4 * i + 1]), Int(bytes[4 * i]), Int(bytes[4 * i + 3])) }
    }

    /// EDR: rgba16Float drawable, returned as floats.
    func presentEDR(_ params: UISPECIMEN_PresentParams, slots: [(any MTLTexture)?], width: Int, height: Int) async throws -> [SIMD4<Float>] {
        var p = params
        p.edr = 1
        let target = try await draw(p, slots: slots, width: width, height: height, format: .rgba16Float)
        var halves = [Float16](repeating: 0, count: width * height * 4)
        target.getBytes(&halves, bytesPerRow: width * 8, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return (0..<(width * height)).map { i in SIMD4(Float(halves[4 * i]), Float(halves[4 * i + 1]), Float(halves[4 * i + 2]), Float(halves[4 * i + 3])) }
    }
}

/// CPU expectations, from BlurCore's SRGB (the frozen twin of b2_srgb_encode).
enum UISPECIMEN_Expect {
    static func half(_ v: Float) -> Double { Double(Float(Float16(v))) }
    /// SRGB.code8 of the fp16-rounded value composited over an opaque backdrop.
    static func code(_ c: SIMD4<Float>, backdrop: SIMD4<Float> = SIMD4(0, 0, 0, 1)) -> SIMD4<Int> {
        let a = half(c.w)
        func ch(_ v: Float, _ b: Float) -> Int { SRGB.code8(linear: half(v) + Double(b) * (1 - a)) }
        return SIMD4(ch(c.x, backdrop.x), ch(c.y, backdrop.y), ch(c.z, backdrop.z), 255)
    }
    /// Distance of encoded·255 from the nearest rounding boundary (k + 0.5): GPU fast-math powr and Double agree away from it.
    static func margin(_ linear: Double) -> Double {
        let e = Swift.min(Swift.max(SRGB.encode(linear), 0), 1) * 255
        return abs(e - (e.rounded(.down) + 0.5))
    }
    /// A deterministic value per (x, y, channel): a code centre ± 0.3, or an out-of-range value (negative, > 1, HDR).
    static func value(_ x: Int, _ y: Int, _ ch: Int) -> Float {
        let h = Int(b2pcg(UInt32(x * 7919 + y * 104_729 + ch * 1_299_709)) % 300)
        switch h {
        case 256: return -0.25
        case 257: return 1.5
        case 258: return 1000
        case 259: return 6400
        case 260..<300: return Float(SRGB.decode((Double(h - 260) * 6 + 0.25) / 255))
        default: return Float(SRGB.decode((Double(h) + (h % 2 == 0 ? 0.3 : -0.3)) / 255).clamped(0, 1))
        }
    }
    static func b2pcg(_ v: UInt32) -> UInt32 {
        let state = v &* 747_796_405 &+ 2_891_336_453
        let word = ((state >> ((state >> 28) &+ 4)) ^ state) &* 277_803_737
        return (word >> 22) ^ word
    }
}

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(self, lo), hi) }
}

@Suite("UISPECIMEN present pass on the Mac GPU") @MainActor
struct UISPECIMEN_PresentShader {
    @Test func paramsLayoutMatchesTheShader() {
        #expect(MemoryLayout<UISPECIMEN_PresentParams>.stride == 144)
        #expect(MemoryLayout<UISPECIMEN_PresentParams>.offset(of: \.origin) == 64)
        #expect(MemoryLayout<UISPECIMEN_PresentParams>.offset(of: \.drawableSize) == 88)
        #expect(MemoryLayout<UISPECIMEN_PresentParams>.offset(of: \.shift) == 96)
        #expect(MemoryLayout<UISPECIMEN_PresentParams>.offset(of: \.splitColumn) == 104)
        #expect(MemoryLayout<UISPECIMEN_PresentParams>.offset(of: \.gain) == 120)
        #expect(MemoryLayout<UISPECIMEN_PresentParams>.offset(of: \.showB) == 128)
    }

    @Test func presentFunctionsAreInTheLibrary() throws {
        guard let h = try UISPECIMEN_PresentHarness.make() else { return }
        #expect(h.library.functionNames.contains("b2_present_fs"))
        #expect(h.library.functionNames.contains("b2_common_fullscreen_vs"))
        print("UISPECIMEN present library compiled from \(h.compiledFrom)")
    }

    /// A 1 : 1 present of a known texture gives SRGB.code8 per pixel (ARCHITECTURE §8.2, PLAN UI-SPECIMEN CORE).
    @Test func oneToOnePresentGivesSRGBCode8PerPixel() async throws {
        guard let h = try UISPECIMEN_PresentHarness.make() else { return }
        let n = 128
        var texels: [SIMD4<Float>] = []
        for y in 0..<n { for x in 0..<n { texels.append(SIMD4(UISPECIMEN_Expect.value(x, y, 0), UISPECIMEN_Expect.value(x, y, 1),
                                                              UISPECIMEN_Expect.value(x, y, 2), 1)) } }
        let source = try h.texture(texels, width: n, height: n)
        var params = UISPECIMEN_PresentParams()
        let out = try await h.presentSDR(params, slots: [source], width: n, height: n)
        var compared = 0, skipped = 0, mismatches: [String] = []
        for i in 0..<(n * n) {
            let want = UISPECIMEN_Expect.code(texels[i])
            for ch in 0..<3 {
                let linear = UISPECIMEN_Expect.half(texels[i][ch])
                if UISPECIMEN_Expect.margin(linear) < 0.02 && linear > 0 && linear < 1 { skipped += 1; continue }
                compared += 1
                if out[i][ch] != want[ch], mismatches.count < 8 {
                    mismatches.append("(\(i % n), \(i / n)) ch \(ch): linear \(linear) GPU \(out[i][ch]) CPU \(want[ch])")
                }
            }
            #expect(out[i][3] == 255)
        }
        print("UISPECIMEN 1:1 present: \(compared) channels compared, \(skipped) within 0.02 of a rounding boundary skipped, \(mismatches.count) mismatches")
        #expect(mismatches.isEmpty, "\(mismatches)")
        #expect(compared > 3 * n * n * 9 / 10)

        // Premultiplied colour over a grey backdrop: rgb + backdrop · (1 − a).
        params.backdrop = SIMD4(0.2, 0.2, 0.2, 1)
        let translucent = try h.uniform(SIMD4(0.1, 0.3, 0.0, 0.5), side: 8)
        let over = try await h.presentSDR(params, slots: [translucent], width: 8, height: 8)
        let want = UISPECIMEN_Expect.code(SIMD4(0.1, 0.3, 0.0, 0.5), backdrop: params.backdrop)
        #expect(over.allSatisfy { $0 == want }, "over backdrop: GPU \(over[0]) CPU \(want)")
    }

    /// Nearest zoom (2×, 8×) replicates texels: every drawable pixel of a z × z block shows one texel, untouched.
    @Test(arguments: [(2, SIMD2<Int>(16, 8)), (8, SIMD2<Int>(5, 40)), (4, SIMD2<Int>(48, 0))])
    func nearestZoomReplicatesTexels(zoom: Int, origin: SIMD2<Int>) async throws {
        guard let h = try UISPECIMEN_PresentHarness.make() else { return }
        let n = 64
        var texels: [SIMD4<Float>] = []
        for y in 0..<n { for x in 0..<n {
            texels.append(SIMD4(Float(SRGB.decode((Double(x * 4) + 0.3) / 255)), Float(SRGB.decode((Double(y * 4) + 0.3) / 255)), 0.25, 1))
        } }
        let source = try h.texture(texels, width: n, height: n)
        var params = UISPECIMEN_PresentParams()
        params.origin = SIMD2(Float(origin.x), Float(origin.y))
        params.texelsPerPixel = SIMD2(repeating: 1 / Float(zoom))
        let out = try await h.presentSDR(params, slots: [source], width: n, height: n)
        var wrong = 0
        for y in 0..<n { for x in 0..<n {
            let tx = origin.x + x / zoom, ty = origin.y + y / zoom
            let want = tx < n && ty < n ? UISPECIMEN_Expect.code(texels[ty * n + tx]) : SIMD4(0, 0, 0, 255)
            if out[y * n + x] != want { wrong += 1 }
        } }
        #expect(wrong == 0, "zoom \(zoom)× from (\(origin.x), \(origin.y)): \(wrong) pixels differ from their texel")
        // Each z × z block is one value.
        for by in stride(from: 0, to: n, by: zoom) { for bx in stride(from: 0, to: n, by: zoom) {
            let first = out[by * n + bx]
            for y in by..<(by + zoom) { for x in bx..<(bx + zoom) where out[y * n + x] != first { Issue.record("block (\(bx), \(by)) not uniform") } }
        } }
    }

    /// The before/after split and the Wipe land on the requested column: INPUT (or B) strictly left of it.
    @Test(arguments: [0, 1, 23, 32, 63, 64])
    func splitAndWipeBoundariesLandOnTheRequestedColumn(column: Int) async throws {
        guard let h = try UISPECIMEN_PresentHarness.make() else { return }
        let n = 64
        let inputValue = SIMD4<Float>(0.6, 0.6, 0.6, 1), outputValue = SIMD4<Float>(0.05, 0.1, 0.2, 1)
        let input = try h.uniform(inputValue, side: n), output = try h.uniform(outputValue, side: n)
        var params = UISPECIMEN_PresentParams()
        params.splitColumn = Int32(column)
        params.available = 0b11
        let split = try await h.presentSDR(params, slots: [output, input], width: n, height: n)
        let inCode = UISPECIMEN_Expect.code(inputValue), outCode = UISPECIMEN_Expect.code(outputValue)
        for y in [0, 31, 63] { for x in 0..<n {
            #expect(split[y * n + x] == (x < column ? inCode : outCode), "split column \(column): pixel (\(x), \(y))")
        } }
        params.mode = 1   // Wipe: B left, A right
        let wipe = try await h.presentSDR(params, slots: [output, input], width: n, height: n)
        for x in 0..<n { #expect(wipe[17 * n + x] == (x < column ? inCode : outCode), "wipe column \(column): x \(x)") }
        // No divider: the output everywhere, even with the input bound.
        params.mode = 0; params.splitColumn = -1
        let none = try await h.presentSDR(params, slots: [output, input], width: n, height: n)
        #expect(none.allSatisfy { $0 == outCode })
    }

    /// Difference |A − B| × gain: the encoded, clipped difference times the gain, as a grey ramp. × 16 is exact.
    @Test(arguments: [Float(1), 16, 256])
    func differenceGainIsExact(gain: Float) async throws {
        guard let h = try UISPECIMEN_PresentHarness.make() else { return }
        // Linear-segment values (sRGB encode = 12.92 · l), so the expected grey is an exact product, far from a rounding edge.
        let pairs: [(Float, Float)] = [(0.003, 0.001), (0.0025, 0.0024), (0.0002, 0.0001), (0.0031, 0.0), (0.001, 0.001)]
        for (av, bv) in pairs {
            let a = try h.uniform(SIMD4(av, av * 0.5, 0, 1), side: 16), b = try h.uniform(SIMD4(bv, bv * 0.5, 0, 1), side: 16)
            var params = UISPECIMEN_PresentParams()
            params.mode = 3; params.gain = gain; params.available = 0b11
            let out = try await h.presentSDR(params, slots: [a, b], width: 16, height: 16)
            let ea = 12.92 * UISPECIMEN_Expect.half(av), eb = 12.92 * UISPECIMEN_Expect.half(bv)
            let ea2 = 12.92 * UISPECIMEN_Expect.half(av * 0.5), eb2 = 12.92 * UISPECIMEN_Expect.half(bv * 0.5)
            let d = Swift.max(abs(ea - eb), abs(ea2 - eb2))
            let g = Swift.min(Swift.max(Double(gain) * d, 0), 1) * 255
            #expect(abs(g - (g.rounded(.down) + 0.5)) > 0.01, "test value too close to a rounding edge: \(g)")
            let want = Int(g.rounded())
            #expect(out.allSatisfy { $0 == SIMD4(want, want, want, 255) },
                    "× \(Int(gain)): A \(av) B \(bv) → GPU \(out[0]) CPU \(want) (|ΔE| \(d))")
        }
    }

    /// Contours mark where the difference crosses a multiple of the step, in the contour colour; elsewhere the ramp.
    @Test func differenceContoursFollowTheStep() async throws {
        guard let h = try UISPECIMEN_PresentHarness.make() else { return }
        let n = 32
        var a: [SIMD4<Float>] = [], b: [SIMD4<Float>] = []
        for _ in 0..<n { for x in 0..<n {
            a.append(SIMD4(Float(x) * 0.0001, 0, 0, 1))   // ΔE = 12.92 · 0.0001 · x ≈ 0.33 LSB per column
            b.append(SIMD4(0, 0, 0, 1))
        } }
        var params = UISPECIMEN_PresentParams()
        params.mode = 3; params.gain = 16; params.available = 0b11
        params.contour = SIMD4(1, 0, 1, 1)                 // magenta, so a contour pixel cannot be mistaken for grey
        params.contourStep = 4 / 255                        // every 4 LSB
        let out = try await h.presentSDR(params, slots: [try h.texture(a, width: n, height: n), try h.texture(b, width: n, height: n)],
                                         width: n, height: n)
        let contourColumns = (0..<n).filter { out[5 * n + $0] == SIMD4(255, 0, 255, 255) }
        let expected = (0..<(n - 1)).filter { x in
            let d0 = 12.92 * UISPECIMEN_Expect.half(Float(x) * 0.0001), d1 = 12.92 * UISPECIMEN_Expect.half(Float(x + 1) * 0.0001)
            return floor(d0 / (4.0 / 255)) != floor(d1 / (4.0 / 255))
        }
        #expect(contourColumns == expected, "contours at \(contourColumns), expected \(expected)")
        #expect(!expected.isEmpty)
        let grey = out[5 * n + 1]
        #expect(grey.x == grey.y && grey.y == grey.z, "the ramp is grey (luminance), not colour")
    }

    @Test func flipShowsTheHeldSlot() async throws {
        guard let h = try UISPECIMEN_PresentHarness.make() else { return }
        let av = SIMD4<Float>(0.5, 0.1, 0.1, 1), bv = SIMD4<Float>(0.1, 0.1, 0.5, 1)
        let a = try h.uniform(av, side: 8), b = try h.uniform(bv, side: 8)
        var params = UISPECIMEN_PresentParams()
        params.mode = 2; params.available = 0b11; params.splitColumn = 4
        let showingA = try await h.presentSDR(params, slots: [a, b], width: 8, height: 8)
        #expect(showingA.allSatisfy { $0 == UISPECIMEN_Expect.code(av) }, "Flip ignores the divider and shows A")
        params.showB = 1
        let showingB = try await h.presentSDR(params, slots: [a, b], width: 8, height: 8)
        #expect(showingB.allSatisfy { $0 == UISPECIMEN_Expect.code(bv) })
    }

    /// Line-up 2 × 2: quadrant q shows the central N/2 crop of slot q (A B / C D), 1 : 1.
    @Test func lineUpQuadrantsShowCentralCrops() async throws {
        guard let h = try UISPECIMEN_PresentHarness.make() else { return }
        let n = 64, half = n / 2, cropOrigin = (n - half) / 2
        var slots: [any MTLTexture] = [], values: [[SIMD4<Float>]] = []
        for s in 0..<4 {
            var texels: [SIMD4<Float>] = []
            for y in 0..<n { for x in 0..<n {
                texels.append(SIMD4(Float(SRGB.decode((Double(x * 3) + 0.3) / 255)), Float(SRGB.decode((Double(y * 3) + 0.3) / 255)),
                                    Float(SRGB.decode((Double(s * 60) + 0.3) / 255)), 1))
            } }
            values.append(texels)
            slots.append(try h.texture(texels, width: n, height: n))
        }
        var params = UISPECIMEN_PresentParams()
        params.mode = 4; params.available = 0b1111
        params.lineUpOrigin = SIMD2(Float(cropOrigin), Float(cropOrigin))
        let out = try await h.presentSDR(params, slots: slots, width: n, height: n)
        var wrong = 0
        for y in 0..<n { for x in 0..<n {
            let q = (y >= half ? 2 : 0) + (x >= half ? 1 : 0)
            let tx = cropOrigin + x % half, ty = cropOrigin + y % half
            if out[y * n + x] != UISPECIMEN_Expect.code(values[q][ty * n + tx]) { wrong += 1 }
        } }
        #expect(wrong == 0, "\(wrong) Line-up pixels differ")
        // A slot that has not rendered yet is black, never another slot's image.
        params.available = 0b0111
        let missingD = try await h.presentSDR(params, slots: slots, width: n, height: n)
        #expect(missingD[(n - 1) * n + (n - 1)] == SIMD4(0, 0, 0, 255))
    }

    /// Periscope and loupe: a region of the texture magnified nearest; the loupe's 14 × 14 copy at 24 px per texel.
    @Test func cropMagnifiesTheLoupeCopy() async throws {
        guard let h = try UISPECIMEN_PresentHarness.make() else { return }
        var texels: [SIMD4<Float>] = []
        for y in 0..<14 { for x in 0..<14 {
            texels.append(SIMD4(Float(SRGB.decode((Double(x * 18) + 0.3) / 255)), Float(SRGB.decode((Double(y * 18) + 0.3) / 255)), 0.5, 1))
        } }
        let copy = try h.texture(texels, width: 14, height: 14)
        var params = UISPECIMEN_PresentParams()
        params.mode = 5
        params.texelsPerPixel = SIMD2(repeating: Float(14.0 / 336.0))
        let out = try await h.presentSDR(params, slots: [copy], width: 336, height: 336)
        var wrong = 0
        for y in 0..<336 { for x in 0..<336 where out[y * 336 + x] != UISPECIMEN_Expect.code(texels[(y / 24) * 14 + x / 24]) { wrong += 1 } }
        #expect(wrong == 0, "\(wrong) loupe pixels are not their texel's 24 × 24 block")

        // Periscope: a 40 × 40 crop at (100, 60) of a 256² output into a 120² drawable (3 px per texel).
        var big: [SIMD4<Float>] = []
        for y in 0..<256 { for x in 0..<256 { big.append(SIMD4(Float(x % 7) * 0.1, Float(y % 5) * 0.2, 0, 1)) } }
        let output = try h.texture(big, width: 256, height: 256)
        params.origin = SIMD2(100, 60); params.texelsPerPixel = SIMD2(repeating: Float(40.0 / 120.0))
        let crop = try await h.presentSDR(params, slots: [output], width: 120, height: 120)
        wrong = 0
        for y in 0..<120 { for x in 0..<120 where crop[y * 120 + x] != UISPECIMEN_Expect.code(big[(60 + y / 3) * 256 + 100 + x / 3]) { wrong += 1 } }
        #expect(wrong == 0, "\(wrong) periscope pixels differ")
    }

    /// A half-resolution preview (447² of 894², here 32² of 64²) is upscaled nearest: 2 × 2 blocks per preview texel.
    @Test func previewIsUpscaledNearest() async throws {
        guard let h = try UISPECIMEN_PresentHarness.make() else { return }
        var texels: [SIMD4<Float>] = []
        for y in 0..<32 { for x in 0..<32 { texels.append(SIMD4(Float(x) / 31, Float(y) / 31, 0.3, 1)) } }
        let preview = try h.texture(texels, width: 32, height: 32)
        var params = UISPECIMEN_PresentParams()
        params.ratioAB = SIMD4(0.5, 0.5, 1, 1)
        let out = try await h.presentSDR(params, slots: [preview], width: 64, height: 64)
        var wrong = 0
        for y in 0..<64 { for x in 0..<64 where out[y * 64 + x] != UISPECIMEN_Expect.code(texels[(y / 2) * 32 + x / 2]) { wrong += 1 } }
        #expect(wrong == 0)
    }

    /// The pan's rubber band moves the content by whole drawable pixels and leaves black where no canvas exists.
    @Test func rubberBandShiftMovesWholePixels() async throws {
        guard let h = try UISPECIMEN_PresentHarness.make() else { return }
        let n = 32
        var texels: [SIMD4<Float>] = []
        for _ in 0..<n { for x in 0..<n { texels.append(SIMD4(Float(SRGB.decode((Double(x * 8) + 0.3) / 255)), 0.2, 0.2, 1)) } }
        let source = try h.texture(texels, width: n, height: n)
        var params = UISPECIMEN_PresentParams()
        params.shift = SIMD2(5, -3)
        let out = try await h.presentSDR(params, slots: [source], width: n, height: n)
        for y in [0, 10, 28, 29, 31] { for x in 0..<n {
            let cx = x - 5, cy = y + 3
            let want = cx < 0 || cy >= n ? SIMD4(0, 0, 0, 255) : UISPECIMEN_Expect.code(texels[cy * n + cx])
            #expect(out[y * n + x] == want, "(\(x), \(y))")
        } }
    }

    /// EDR writes extended linear values: above 1 and below 0 survive, composited over the backdrop, never encoded.
    @Test func edrWritesExtendedLinearValues() async throws {
        guard let h = try UISPECIMEN_PresentHarness.make() else { return }
        let source = try h.texture([SIMD4(2.5, -0.125, 0.5, 1), SIMD4(0.25, 0.5, 0.75, 0.5)], width: 2, height: 1)
        var params = UISPECIMEN_PresentParams()
        params.backdrop = SIMD4(0.5, 0.5, 0.5, 1)
        let out = try await h.presentEDR(params, slots: [source], width: 2, height: 1)
        #expect(out[0] == SIMD4(2.5, -0.125, 0.5, 1))
        #expect(out[1] == SIMD4(0.5, 0.75, 1.0, 1))
    }

    /// Before the first Run the coordinator has no output: a missing A is black (the app then binds the INPUT as A).
    @Test func missingOutputIsBlack() async throws {
        guard let h = try UISPECIMEN_PresentHarness.make() else { return }
        var params = UISPECIMEN_PresentParams()
        params.available = 0
        let out = try await h.presentSDR(params, slots: [nil], width: 4, height: 4)
        #expect(out.allSatisfy { $0 == SIMD4(0, 0, 0, 255) })
    }
}
