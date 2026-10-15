import Foundation
import Metal
import CryptoKit
import BlurCore

// FROZEN — ARCHITECTURE.md §5.8. The GPU context: one per process, main-actor isolated (JF G-2, SDK §5).
// Swift 6 rules (binding, §5.15):
// • MTLTexture, MTLBuffer, MTLCommandBuffer and encoders are not Sendable: they never leave the main actor.
// • Completion handlers capture only Sendable values (GPUCompletion); results return through a continuation.
// • No nonisolated(unsafe), no @unchecked Sendable on anything that holds a Metal resource.
// • BlurCore work (references, kernels, floors) runs off the main actor on Sendable values.

/// The shader sources and their hashes (ARCHITECTURE §6.6). Per-file SHA-256 from Tools/shader-manifest.sh;
/// the combined SHA-256 is always computed in Swift by `assemble`, so the app and blur-gpucheck agree by construction.
public struct ShaderManifest: Sendable, Codable, Hashable {
    public var files: [String: String]
    public var combinedSHA256: String
    public var mathMode: String
    public var languageVersion: String
    public init(files: [String: String], combinedSHA256: String, mathMode: String = "fast", languageVersion: String = "4.1") {
        self.files = files; self.combinedSHA256 = combinedSHA256; self.mathMode = mathMode; self.languageVersion = languageVersion
    }

    /// The exact include line every shader file starts with.
    public static let includeLine = "#include \"B2Shared.h\""

    /// The single translation unit blur-gpucheck compiles: the header once, then every `.metal` file in byte-wise
    /// file-name order with its include line removed, separated by "\n".
    public static func assemble(header: String, files: [(name: String, text: String)]) -> String {
        let bodies = files.sorted { Array($0.name.utf8).lexicographicallyPrecedes(Array($1.name.utf8)) }.map { file in
            "// ---- \(file.name)\n" + file.text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { $0.trimmingCharacters(in: .whitespaces) != includeLine }.joined(separator: "\n")
        }
        return ([header] + bodies).joined(separator: "\n")
    }

    public static func sha256(_ text: String) -> String { sha256(Data(text.utf8)) }
    public static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// Builds a manifest from source texts (header named "B2Shared.h").
    public static func make(header: String, files: [(name: String, text: String)]) -> ShaderManifest {
        var map = ["B2Shared.h": sha256(header)]
        for f in files { map[f.name] = sha256(f.text) }
        return ShaderManifest(files: map, combinedSHA256: sha256(assemble(header: header, files: files)))
    }

    /// Loads `<bundle>/ShaderSources/` (copies made by Tools/shader-manifest.sh), verifies every per-file hash, and
    /// computes the combined hash. Returns nil when a file is missing or a hash differs (the app then shows the failure).
    public static func load(from directory: URL) -> (manifest: ShaderManifest, texts: [String: String])? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("ShaderManifest.json")),
              let listed = try? JSONDecoder().decode([String: [String: String]].self, from: data), let files = listed["files"],
              let header = try? String(contentsOf: directory.appendingPathComponent("B2Shared.h"), encoding: .utf8) else { return nil }
        var texts: [String: String] = ["B2Shared.h": header]
        for name in files.keys where name != "B2Shared.h" {
            guard let text = try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8) else { return nil }
            texts[name] = text
        }
        for (name, expected) in files where sha256(texts[name] ?? "") != expected { return nil }
        let shaders = texts.filter { $0.key.hasSuffix(".metal") }.map { (name: $0.key, text: $0.value) }
        return (make(header: header, files: shaders), texts)
    }
}

@MainActor
public final class GPUContext {
    public let device: any MTLDevice
    public let queue: any MTLCommandQueue
    public let library: any MTLLibrary
    public let manifest: ShaderManifest
    public let mathMode: String
    public private(set) var facts: GPUFacts
    /// Every compute dispatch made through `dispatch2D`, recorded only when `recordsDispatches` (blur-gpucheck and
    /// tests); the app leaves it off so the log cannot grow without bound (review fix E-17).
    public private(set) var dispatchLog: [String] = []
    public let recordsDispatches: Bool
    /// Dispatches made so far (always counted).
    public private(set) var dispatchCount = 0

    private var computeCache: [String: any MTLComputePipelineState] = [:]
    private var renderCache: [String: any MTLRenderPipelineState] = [:]
    private var computeTasks: [String: Task<any MTLComputePipelineState, any Error>] = [:]
    private var renderTasks: [String: Task<any MTLRenderPipelineState, any Error>] = [:]
    private var pool: [TextureSpec: [any MTLTexture]] = [:]

    public init(device: any MTLDevice, library: any MTLLibrary, manifest: ShaderManifest, mathMode: String = "fast",
                forceApple2Limits: Bool = false, recordsDispatches: Bool = false) throws {
        guard let queue = device.makeCommandQueue() else { throw GPUError.noCommandQueue }
        self.device = device; self.queue = queue; self.library = library; self.manifest = manifest; self.mathMode = mathMode
        self.recordsDispatches = recordsDispatches
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        let measured = GPUFacts(deviceName: device.name, familyName: GPUContext.familyName(device),
                                maxThreadsPerThreadgroup: device.maxThreadsPerThreadgroup.width,
                                maxThreadgroupMemoryLength: device.maxThreadgroupMemoryLength,
                                supportsApple7: device.supportsFamily(.apple7),
                                supports32BitFloatFiltering: device.supports32BitFloatFiltering,
                                readWriteTextureTier: Int(device.readWriteTextureSupport.rawValue),
                                supportsStageBoundaryCounters: device.supportsCounterSampling(.atStageBoundary),
                                isSimulator: isSimulator, forcedApple2Limits: false)
        facts = forceApple2Limits ? .apple2(deviceName: device.name) : measured
    }

    public static func familyName(_ device: any MTLDevice) -> String {
        let families: [(MTLGPUFamily, String)] = [(.apple10, "Apple10"), (.apple9, "Apple9"), (.apple8, "Apple8"), (.apple7, "Apple7"),
                                                   (.apple6, "Apple6"), (.apple5, "Apple5"), (.apple4, "Apple4"),
                                                   (.apple3, "Apple3"), (.apple2, "Apple2")]
        return families.first { device.supportsFamily($0.0) }?.1 ?? "Unknown"
    }

    // MARK: Pipelines (specialised from the precompiled library; never compiled from source on device)
    //
    // Review fix E-3: specialisation + backend compile take 59–417 ms (MEASURED, M1 Max), so it never runs on the main
    // actor. `computePipeline` / `renderPipeline` compile in a detached task (only Sendable values cross: the library,
    // the device, FunctionConstants and the resulting pipeline state) and coalesce in-flight compiles per key; `prepare`
    // awaits them. `encode` uses only the `prepared…` lookups, which throw `GPUError.notPrepared` on a cache miss.
    // (Note: this SDK imports `makeFunction(name:constantValues:)` and `make…PipelineState` without async overloads —
    // MEASURED by the "no async operations" diagnostic — so an `await` on them would still compile on the caller's actor.)

    public static func computeKey(_ function: String, _ constants: FunctionConstants) -> String { function + "#" + constants.cacheKey }
    public static func renderKey(fragment: String, vertex: String, colorFormats: [TextureFormat], _ constants: FunctionConstants) -> String {
        "\(vertex)|\(fragment)|\(colorFormats.map(\.rawValue))#\(constants.cacheKey)"
    }

    public func computePipeline(_ function: String, constants: FunctionConstants) async throws -> any MTLComputePipelineState {
        let key = GPUContext.computeKey(function, constants)
        if let cached = computeCache[key] { return cached }
        if let pending = computeTasks[key] { return try await pending.value }
        let library = self.library, device = self.device
        let task = Task.detached(priority: .userInitiated) { () throws -> any MTLComputePipelineState in
            let fn: any MTLFunction
            do { fn = try library.makeFunction(name: function, constantValues: constants.metalValues()) }
            catch { throw GPUError.missingFunction("\(function): \(error)") }
            return try device.makeComputePipelineState(function: fn)
        }
        computeTasks[key] = task
        defer { computeTasks[key] = nil }
        let pso = try await task.value
        computeCache[key] = pso
        return pso
    }

    public func renderPipeline(fragment: String, vertex: String = "b2_common_fullscreen_vs", colorFormats: [TextureFormat],
                               constants: FunctionConstants) async throws -> any MTLRenderPipelineState {
        let key = GPUContext.renderKey(fragment: fragment, vertex: vertex, colorFormats: colorFormats, constants)
        if let cached = renderCache[key] { return cached }
        if let pending = renderTasks[key] { return try await pending.value }
        let library = self.library, device = self.device
        let task = Task.detached(priority: .userInitiated) { () throws -> any MTLRenderPipelineState in
            let descriptor = MTLRenderPipelineDescriptor()
            do {
                descriptor.vertexFunction = try library.makeFunction(name: vertex, constantValues: constants.metalValues())
                descriptor.fragmentFunction = try library.makeFunction(name: fragment, constantValues: constants.metalValues())
            } catch { throw GPUError.missingFunction("\(vertex)/\(fragment): \(error)") }
            for (i, f) in colorFormats.enumerated() { descriptor.colorAttachments[i].pixelFormat = f.metal }
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        renderTasks[key] = task
        defer { renderTasks[key] = nil }
        let pso = try await task.value
        renderCache[key] = pso
        return pso
    }

    /// A pipeline state `prepare` already built. Never compiles.
    public func preparedComputePipeline(_ function: String, constants: FunctionConstants) throws -> any MTLComputePipelineState {
        let key = GPUContext.computeKey(function, constants)
        guard let pso = computeCache[key] else { throw GPUError.notPrepared(key) }
        return pso
    }

    /// A pipeline state `prepare` already built. Never compiles.
    public func preparedRenderPipeline(fragment: String, vertex: String = "b2_common_fullscreen_vs", colorFormats: [TextureFormat],
                                       constants: FunctionConstants) throws -> any MTLRenderPipelineState {
        let key = GPUContext.renderKey(fragment: fragment, vertex: vertex, colorFormats: colorFormats, constants)
        guard let pso = renderCache[key] else { throw GPUError.notPrepared(key) }
        return pso
    }

    /// Builds the B2Common pipelines every render may use: the 8 colour-pass specialisations, the exposure window pass
    /// and the preview downsample. Called once at launch (and by ParityRunner); cheap after the first call.
    public func prepareCommonPipelines() async throws {
        for srgb in [false, true] {
            for straight in [false, true] {
                for post in [false, true] {
                    _ = try await renderPipeline(fragment: "b2_common_colour_fs", colorFormats: [.rgba16Float],
                                                 constants: GPUContext.colourConstants(srgb: srgb, straight: straight, post: post))
                }
            }
        }
        _ = try await renderPipeline(fragment: "b2_common_window_fs", colorFormats: [.rgba16Float], constants: FunctionConstants())
        _ = try await renderPipeline(fragment: "b2_common_downsample2x_fs", colorFormats: [.rgba16Float], constants: FunctionConstants())
    }

    static func colourConstants(srgb: Bool, straight: Bool, post: Bool) -> FunctionConstants {
        FunctionConstants(family: [FunctionConstant(4, .bool(srgb)), FunctionConstant(5, .bool(straight)), FunctionConstant(6, .bool(post))])
    }

    // MARK: Textures and buffers

    public func texture(_ spec: TextureSpec) throws -> any MTLTexture {
        if var list = pool[spec], let t = list.popLast() { pool[spec] = list; return t }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: spec.format.metal, width: spec.width, height: spec.height,
                                                         mipmapped: spec.mipmapped)
        var usage: MTLTextureUsage = []
        if spec.roles.contains(.read) { usage.insert(.shaderRead) }
        if spec.roles.contains(.computeWrite) { usage.insert(.shaderWrite) }
        if spec.roles.contains(.renderTarget) { usage.insert(.renderTarget) }
        d.usage = usage
        d.storageMode = spec.shared ? .shared : .private
        guard let t = device.makeTexture(descriptor: d) else { throw GPUError.textureAllocationFailed("\(spec)") }
        return t
    }

    public func recycle(_ texture: any MTLTexture, spec: TextureSpec) { pool[spec, default: []].append(texture) }

    /// Returns an encode's transient textures to the pool. Call only after its command buffers completed and nothing
    /// shows its intermediates any more (the next encode on the same pipeline instance, §5.8 rule 5).
    public func recycle(_ encoded: EncodedBlur) {
        for t in encoded.transientTextures { recycle(t.texture, spec: t.spec) }
    }

    /// A shared buffer holding `values` (weights, offsets, tap lists). ≤ 4 KB may use setBytes instead.
    public func buffer(_ values: [Float]) throws -> any MTLBuffer {
        let length = Swift.max(16, values.count * MemoryLayout<Float>.stride)
        guard let b = values.withUnsafeBytes({ raw in
            raw.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: raw.count, options: .storageModeShared) }
        }) ?? device.makeBuffer(length: length, options: .storageModeShared) else { throw GPUError.bufferAllocationFailed }
        return b
    }

    /// A zero-filled shared buffer for trace records: `passes` blocks of TraceLayout.passStride(capacity:).
    public func traceBuffer(passes: Int, capacity: Int, probe: PixelPoint) throws -> any MTLBuffer {
        let stride = TraceLayout.passStride(capacity: capacity)
        guard let b = device.makeBuffer(length: stride * Swift.max(1, passes), options: .storageModeShared) else {
            throw GPUError.bufferAllocationFailed
        }
        memset(b.contents(), 0, b.length)
        for pass in 0..<Swift.max(1, passes) {
            let header = b.contents().advanced(by: pass * stride).bindMemory(to: TraceLayout.Header.self, capacity: 1)
            header.pointee = TraceLayout.Header(probe: SIMD2(UInt32(probe.x), UInt32(probe.y)), tapCount: 0,
                                                passIndex: UInt32(pass), capacity: UInt32(capacity), overflow: 0, reserved: .zero)
        }
        return b
    }

    // MARK: Safe dispatch (ARCHITECTURE §4.4)

    /// The preferred size (16 × 16 for 2-D tiles; 256 × 1 or 1 × 256 for row and column tiles) halved until it fits
    /// min(pipeline limit, device or forced-Apple2 limit).
    public func threadgroupSize(for pso: any MTLComputePipelineState, preferred: MTLSize = MTLSize(width: 16, height: 16, depth: 1)) -> MTLSize {
        let cap = Swift.min(pso.maxTotalThreadsPerThreadgroup, facts.maxThreadsPerThreadgroup)
        var w = preferred.width, h = preferred.height
        while w * h > cap && h > 1 { h /= 2 }
        while w * h > cap && w > 1 { w /= 2 }
        return MTLSize(width: w, height: h, depth: 1)
    }

    /// The only way compute work is dispatched: dispatchThreadgroups over a grid covering width × height.
    /// Kernels bounds-check AFTER their threadgroup loads and barriers.
    @discardableResult
    public func dispatch2D(_ encoder: any MTLComputeCommandEncoder, pso: any MTLComputePipelineState, width: Int, height: Int,
                           preferred: MTLSize = MTLSize(width: 16, height: 16, depth: 1), threadgroupMemory: Int = 0,
                           label: String) throws -> (threadgroups: MTLSize, threadsPerThreadgroup: MTLSize) {
        let total = pso.staticThreadgroupMemoryLength + threadgroupMemory
        guard total <= facts.maxThreadgroupMemoryLength else {
            throw GPUError.budgetExceeded("\(label): \(total) B threadgroup memory > \(facts.maxThreadgroupMemoryLength) B")
        }
        let tg = threadgroupSize(for: pso, preferred: preferred)
        let groups = MTLSize(width: (width + tg.width - 1) / tg.width, height: (height + tg.height - 1) / tg.height, depth: 1)
        encoder.setComputePipelineState(pso)
        if threadgroupMemory > 0 { encoder.setThreadgroupMemoryLength((threadgroupMemory + 15) / 16 * 16, index: 0) }
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: tg)
        dispatchCount += 1
        if recordsDispatches {
            dispatchLog.append("\(label) tg=\(tg.width)x\(tg.height) groups=\(groups.width)x\(groups.height) tgmem=\(total)")
        }
        return (groups, tg)
    }

    // MARK: Specimens and the full blur (pre/post passes of ARCHITECTURE §4.2)

    /// Uploads fp16 texel bytes once (shared staging buffer → private rgba16Float texture via a blit), and waits.
    /// The Float → Float16 conversion happens before, off the main actor (`HalfImageData`, review fix E-9).
    public func upload(_ image: HalfImageData, roles: TextureRole = [.read]) async throws -> any MTLTexture {
        let texture = try self.texture(TextureSpec(width: image.width, height: image.height, roles: roles))
        let rowBytes = image.bytesPerRow
        guard let staging = image.bytes.withUnsafeBytes({ raw in
                  raw.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: raw.count, options: .storageModeShared) } }),
              let cb = queue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() else { throw GPUError.bufferAllocationFailed }
        blit.copy(from: staging, sourceOffset: 0, sourceBytesPerRow: rowBytes, sourceBytesPerImage: rowBytes * image.height,
                  sourceSize: MTLSize(width: image.width, height: image.height, depth: 1), to: texture,
                  destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        let done = await commit(cb)
        if let error = done.error { throw GPUError.commandBufferFailed(error) }
        return texture
    }

    /// The pan: the N × N window at an integer offset from the canvas texture (SPEC §4.1.3). At 0 EV a blit copy; otherwise
    /// the render pass `b2_common_window_fs`, which also multiplies by 2^EV (exposure at render time, review fix E-10).
    /// `destination` needs `.renderTarget` when `exposureEV != 0`.
    public func encodeWindowCopy(canvas: any MTLTexture, margin: Int, pan: PixelPoint, size: Int, exposureEV: Int = 0,
                                 destination: any MTLTexture, recorder: GPUCommandRecorder) throws {
        if exposureEV == 0 {
            let blit = try recorder.blitEncoder(pass: GPUCommandRecorder.prePass, label: "window copy")
            blit.copy(from: canvas, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: margin + pan.x, y: margin + pan.y, z: 0),
                      sourceSize: MTLSize(width: size, height: size, depth: 1), to: destination, destinationSlice: 0,
                      destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding()
            return
        }
        let pso = try preparedRenderPipeline(fragment: "b2_common_window_fs", colorFormats: [.rgba16Float], constants: FunctionConstants())
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = destination
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        let encoder = try recorder.renderEncoder(pass: GPUCommandRecorder.prePass, descriptor: pass, label: "window copy × 2^EV")
        encoder.setRenderPipelineState(pso)
        encoder.setFragmentTexture(canvas, index: 0)
        var params = WindowParams(originX: Int32(margin + pan.x), originY: Int32(margin + pan.y), gain: Float(pow(2.0, Double(exposureEV))), pad: 0)
        encoder.setFragmentBytes(&params, length: MemoryLayout<WindowParams>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
    /// Layout of `B2CommonWindowParams` in B2Common.metal.
    struct WindowParams { var originX: Int32; var originY: Int32; var gain: Float; var pad: Float }

    /// The frozen preview input (review fix E-4): `destination` (⌊w/2⌋ × ⌊h/2⌋) = 2 × 2 mean of `source`
    /// (`b2_common_downsample2x_fs`; CPU twin `ImageBuffer.downsampled2x`). Quarter previews apply it twice.
    public func encodeDownsample2x(source: any MTLTexture, destination: any MTLTexture, recorder: GPUCommandRecorder) throws {
        let pso = try preparedRenderPipeline(fragment: "b2_common_downsample2x_fs", colorFormats: [.rgba16Float], constants: FunctionConstants())
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = destination
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        let encoder = try recorder.renderEncoder(pass: GPUCommandRecorder.prePass, descriptor: pass, label: "preview 2 × 2 mean")
        encoder.setRenderPipelineState(pso)
        encoder.setFragmentTexture(source, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// The colour/alpha pre- or post-pass (B2Common.metal `b2_common_colour_fs`, function constants 4–6).
    public func encodeColourPass(post: Bool, settings: SilentSettings, source: any MTLTexture, destination: any MTLTexture,
                                 recorder: GPUCommandRecorder) throws {
        let constants = GPUContext.colourConstants(srgb: settings.colourSpace == .srgbEncoded, straight: settings.alphaMode == .straight,
                                                   post: post)
        let pso = try preparedRenderPipeline(fragment: "b2_common_colour_fs", colorFormats: [.rgba16Float], constants: constants)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = destination
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        let encoder = try recorder.renderEncoder(pass: post ? GPUCommandRecorder.postPass : GPUCommandRecorder.prePass,
                                                 descriptor: pass, label: post ? "colour post-pass" : "colour pre-pass")
        encoder.setRenderPipelineState(pso)
        encoder.setFragmentTexture(source, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// Runs one blur exactly as the app and blur-gpucheck must: colour pre-pass → pipeline → colour post-pass.
    /// Pipelines never implement colour-space or alpha handling themselves.
    public func encodeFullBlur(_ pipeline: any GPUBlurPipeline, window: any MTLTexture, output: any MTLTexture,
                               request: OperatorRequest, auxiliary: GPUAuxiliaryTextures = GPUAuxiliaryTextures(),
                               quality: RenderQuality = .full, trace: TraceRequest?, recorder: GPUCommandRecorder) throws -> EncodedBlur {
        guard ColourTransform.needsPasses(request.settings) else {
            return try pipeline.encode(self, GPUBlurInputs(source: window, destination: output, request: request,
                                                           auxiliary: auxiliary, quality: quality), trace: trace, recorder: recorder)
        }
        let spec = TextureSpec(width: window.width, height: window.height,
                               roles: pipeline.writesDestinationFromCompute ? [.read, .renderTarget, .computeWrite] : [.read, .renderTarget])
        let pre = try texture(spec), blurred = try texture(spec)
        try encodeColourPass(post: false, settings: request.settings, source: window, destination: pre, recorder: recorder)
        var encoded = try pipeline.encode(self, GPUBlurInputs(source: pre, destination: blurred, request: request,
                                                              auxiliary: auxiliary, quality: quality), trace: trace, recorder: recorder)
        try encodeColourPass(post: true, settings: request.settings, source: blurred, destination: output, recorder: recorder)
        encoded.intermediates.append(output)
        encoded.transientTextures += [(pre, spec), (blurred, spec)]
        return encoded
    }

    /// Encodes a region readback into `recorder` (by default with the post-pass work), so a render's probe texel costs
    /// no extra command buffer (review fix E-26). Decode the result after `recorder.commitAndWait()`.
    public func encodeReadTexels(_ texture: any MTLTexture, region: PixelRegion, level: Int = 0, recorder: GPUCommandRecorder,
                                 pass: Int = GPUCommandRecorder.postPass) throws -> PendingReadback {
        let bpp = texture.pixelFormat == .rgba32Float ? 16 : (texture.pixelFormat == .rgba8Unorm ? 4 : 8)
        let rowBytes = region.size.width * bpp
        guard let buffer = device.makeBuffer(length: rowBytes * region.size.height, options: .storageModeShared) else {
            throw GPUError.readbackFailed
        }
        let blit = try recorder.blitEncoder(pass: pass, label: "readback")
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: level,
                  sourceOrigin: MTLOrigin(x: region.origin.x, y: region.origin.y, z: 0),
                  sourceSize: MTLSize(width: region.size.width, height: region.size.height, depth: 1), to: buffer,
                  destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * region.size.height)
        blit.endEncoding()
        return PendingReadback(buffer: buffer, region: region, format: texture.pixelFormat)
    }

    // MARK: Running and reading back (frozen pattern: continuation + completion handler, Sendable payload)

    public func commit(_ commandBuffer: any MTLCommandBuffer) async -> GPUCompletion {
        await withCheckedContinuation { (continuation: CheckedContinuation<GPUCompletion, Never>) in
            commandBuffer.addCompletedHandler { done in
                continuation.resume(returning: GPUCompletion(gpuStartTime: done.gpuStartTime, gpuEndTime: done.gpuEndTime,
                                                             error: done.error.map { String(describing: $0) }))
            }
            commandBuffer.commit()
        }
    }

    /// Reads a region as Float RGBA through a blit into a shared buffer (never getBytes on a mip level, GPU §2.7 item 7).
    public func readTexels(_ texture: any MTLTexture, region: PixelRegion, level: Int = 0) async throws -> [SIMD4<Float>] {
        let bpp = texture.pixelFormat == .rgba32Float ? 16 : (texture.pixelFormat == .rgba8Unorm ? 4 : 8)
        let rowBytes = region.size.width * bpp
        guard let buffer = device.makeBuffer(length: rowBytes * region.size.height, options: .storageModeShared),
              let cb = queue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() else { throw GPUError.readbackFailed }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: level,
                  sourceOrigin: MTLOrigin(x: region.origin.x, y: region.origin.y, z: 0),
                  sourceSize: MTLSize(width: region.size.width, height: region.size.height, depth: 1), to: buffer,
                  destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * region.size.height)
        blit.endEncoding()
        let completion = await commit(cb)
        if let error = completion.error { throw GPUError.commandBufferFailed(error) }
        return GPUContext.decodeRGBA(buffer: buffer, count: region.size.width * region.size.height, format: texture.pixelFormat)
    }

    public nonisolated static func decodeRGBA(buffer: any MTLBuffer, count: Int, format: MTLPixelFormat) -> [SIMD4<Float>] {
        switch format {
        case .rgba32Float:
            let p = buffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: count)
            return Array(UnsafeBufferPointer(start: p, count: count))
        case .rgba8Unorm:
            let p = buffer.contents().bindMemory(to: SIMD4<UInt8>.self, capacity: count)
            return UnsafeBufferPointer(start: p, count: count).map { SIMD4<Float>($0) / 255 }
        default:
            let p = buffer.contents().bindMemory(to: SIMD4<Float16>.self, capacity: count)
            return UnsafeBufferPointer(start: p, count: count).map { SIMD4<Float>($0) }
        }
    }
}
