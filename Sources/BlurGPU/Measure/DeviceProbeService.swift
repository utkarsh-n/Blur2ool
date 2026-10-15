import Foundation
import Metal
import BlurCore

// OWNER: GPU-MEASURE. The This-phone device probes (SPEC §4.7, §13.1–§13.4; ARCHITECTURE §4.3, §8.2, §11.6; research
// gpu-pipeline §2.3, §2.6, §3.5, §4.3, §5 item 7). Every probe is on demand (JF G-17) except the sub-texel probe, which
// ENGINE runs once after the idle gate. Each returns a DeviceProbeResult: badged rows for the screens (MEASURED with the
// device stamp; words where a number would not be honest) and machine-readable `numbers` for BlurCore
// (`ReferenceOptions.forDevice` reads "subTexelBits"/"roundsToNearest"; CostModel reads "gigabytesPerSecond").
// GPU kernels: App/GPU/Shaders/Probes.metal (prefix b2_probe_). Timing probes never report a time in the Simulator.

@MainActor
public final class DeviceProbeService: DeviceProbing {
    /// Test seam (ARCHITECTURE §12.3): facts used instead of `context.facts` (the Simulator branch on the Mac).
    var factsOverride: GPUFacts?

    public init() {}
    init(factsOverride: GPUFacts?) { self.factsOverride = factsOverride }

    /// The order of `Measure everything · ≈ 20 s` (SPEC §4.7): cheapest and most-needed first.
    public static let everything: [DeviceProbeKind] = [.limits, .bilinearSubTexelBits, .mipmapImpulse, .counterSamplingPoints,
                                                       .copyBandwidthBlit, .copyBandwidthCompute, .compressionAB, .fmaThroughput,
                                                       .tracedEqualsUntraced]

    public func run(_ kind: DeviceProbeKind, context: GPUContext, device: DeviceStamp) async throws -> DeviceProbeResult {
        try Task.checkCancellation()
        switch kind {
        case .limits: return try await limits(context, device)
        case .bilinearSubTexelBits: return try await subTexel(context, device)
        case .mipmapImpulse: return try await mipmapImpulse(context, device)
        case .copyBandwidthBlit: return try await copyBandwidth(context, device, compute: false)
        case .copyBandwidthCompute: return try await copyBandwidth(context, device, compute: true)
        case .compressionAB: return try await compressionAB(context, device)
        case .fmaThroughput: return try await fmaThroughput(context, device)
        case .counterSamplingPoints: return try await counterSamplingPoints(context, device)
        case .tracedEqualsUntraced: return try await tracedEqualsUntraced(context, device)
        }
    }

    /// Every probe, in `everything` order (This phone › Measure everything). Cancellable between probes.
    public func runAll(context: GPUContext, device: DeviceStamp) async throws -> [DeviceProbeResult] {
        var results: [DeviceProbeResult] = []
        for kind in Self.everything { results.append(try await run(kind, context: context, device: device)) }
        return results
    }

    /// The cost floors' bandwidth from a copy-bandwidth result: MEASURED on this device, labelled with how it was taken.
    public static func bandwidthAssumption(_ result: DeviceProbeResult) -> BandwidthAssumption? {
        guard result.kind == .copyBandwidthBlit || result.kind == .copyBandwidthCompute,
              let gbps = result.numbers["gigabytesPerSecond"], gbps.isFinite, gbps > 0 else { return nil }
        let how = result.kind == .copyBandwidthBlit ? "blit copy" : "compute copy"
        return BandwidthAssumption(gigabytesPerSecond: gbps, label: "\(how) measured on \(result.device.deviceModel)",
                                   provenance: .measured, qualifiers: result.device.isSimulator ? .simulator : [])
    }

    // MARK: Styles and rows

    static let gbps = NumberStyle.decimals(1, unit: "GB/s", spokenUnit: "gigabytes per second")
    static let ms = NumberStyle.decimals(3, unit: "ms", spokenUnit: "milliseconds")
    static let gflops = NumberStyle(precision: .decimals(0), unit: "GFLOP/s", spokenUnit: "gigaflops per second", grouping: true)
    static let bytes = NumberStyle(precision: .decimals(0), unit: "B", spokenUnit: "bytes", grouping: true)
    static let megabytes = NumberStyle.decimals(1, unit: "MB", spokenUnit: "megabytes")
    static let ratio = NumberStyle.decimals(2, unit: "×", spokenUnit: "times")
    static let level = NumberStyle.decimals(4)

    private func facts(_ context: GPUContext) -> GPUFacts { factsOverride ?? context.facts }
    private func simulated(_ context: GPUContext, _ device: DeviceStamp) -> Bool { facts(context).isSimulator || device.isSimulator }

    private func row(_ id: String, _ label: String, _ value: Double, _ style: NumberStyle, _ device: DeviceStamp,
                     caption: String? = nil) -> LabeledValue {
        LabeledValue(id: id, label: label, value: .number(value, style, .measured, qualifiers: device.isSimulator ? .simulator : [],
                                                          device: device, caption: caption))
    }
    private func words(_ id: String, _ label: String, _ text: String, _ device: DeviceStamp, caption: String? = nil) -> LabeledValue {
        LabeledValue(id: id, label: label, value: .words(text, .measured, qualifiers: device.isSimulator ? .simulator : [], device: device,
                                                         caption: caption))
    }
    /// The Simulator's GPU times are meaningless (research §4.3 item 3): timing probes say so instead of a number.
    private func noTiming(_ kind: DeviceProbeKind, _ label: String, _ device: DeviceStamp) -> DeviceProbeResult {
        DeviceProbeResult(kind: kind, rows: [LabeledValue(id: kind.rawValue, label: label,
                                                          value: .words("NO GPU TIMING IN SIMULATOR", qualifiers: .simulator))],
                          numbers: [:], device: device)
    }

    // MARK: Limits

    private func limits(_ context: GPUContext, _ device: DeviceStamp) async throws -> DeviceProbeResult {
        let d = context.device
        let pso = try await context.computePipeline("b2_probe_copy_k", constants: FunctionConstants())
        let family = GPUContext.familyName(d)
        let appleFamily = Double(family.dropFirst("Apple".count)) ?? 0
        var numbers: [String: Double] = [
            "maxThreadsPerThreadgroup": Double(d.maxThreadsPerThreadgroup.width),
            "maxThreadgroupMemoryLength": Double(d.maxThreadgroupMemoryLength),
            "threadExecutionWidth": Double(pso.threadExecutionWidth),
            "readWriteTextureTier": Double(d.readWriteTextureSupport.rawValue),
            "supports32BitFloatFiltering": d.supports32BitFloatFiltering ? 1 : 0,
            "supportsApple7": d.supportsFamily(.apple7) ? 1 : 0,
            "supportsStageBoundaryCounters": d.supportsCounterSampling(.atStageBoundary) ? 1 : 0,
            "appleFamily": appleFamily,
            "maxBufferLength": Double(d.maxBufferLength),
        ]
        numbers["recommendedMaxWorkingSetSize"] = Double(d.recommendedMaxWorkingSetSize)
        let rows = [
            words("family", "GPU FAMILY", family.uppercased(), device),
            row("threads", "THREADS PER THREADGROUP", numbers["maxThreadsPerThreadgroup"]!, .integer(), device),
            row("tgmem", "THREADGROUP MEMORY", numbers["maxThreadgroupMemoryLength"]!, Self.bytes, device),
            row("simd", "SIMD WIDTH", numbers["threadExecutionWidth"]!, .integer(noun: CountNoun("thread", "threads")), device),
            row("rwtier", "READ-WRITE TEXTURE TIER", numbers["readWriteTextureTier"]!, .integer(), device),
            words("float32filter", "32-BIT FLOAT FILTERING", d.supports32BitFloatFiltering ? "SUPPORTED" : "NOT SUPPORTED", device),
        ]
        return DeviceProbeResult(kind: .limits, rows: rows, numbers: numbers, device: device)
    }

    // MARK: Bilinear sub-texel precision (ARCHITECTURE §4.3; research gpu-pipeline §2.3 item 1)

    static let subTexelSamples = 65_536

    /// Samples the hardware's bilinear weight at `subTexelSamples` exact fractions between two texel centres.
    func sampleSubTexel(_ context: GPUContext, format: MTLPixelFormat = .rgba16Float, width: Int = 2, base: Int = 0,
                        axis: Int = 0) async throws -> [Float] {
        let pso = try await context.computePipeline("b2_probe_subtexel_k", constants: FunctionConstants())
        let w = axis == 0 ? width : 1, h = axis == 0 ? 1 : width
        var ramp = ImageBuffer(width: w, height: h)
        for i in 0..<width where i > base { ramp.pixels[i] = SIMD4(1, 1, 1, 1) }
        let texture = try await MeasureTextures.upload(ramp, format: format, usage: [.shaderRead], context: context)
        let count = Self.subTexelSamples
        guard let out = context.device.makeBuffer(length: count * MemoryLayout<Float>.stride, options: .storageModeShared) else {
            throw GPUError.bufferAllocationFailed
        }
        var params = MeasureSubTexelParams(count: UInt32(count), axis: UInt32(axis), base: Float(base), pad: 0)
        let recorder = GPUCommandRecorder(context: context, label: "probe sub-texel")
        let encoder = try recorder.computeEncoder(pass: 0, label: "sub-texel ramp")
        encoder.setTexture(texture, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<MeasureSubTexelParams>.stride, index: 0)
        encoder.setBuffer(out, offset: 0, index: 3)
        try context.dispatch2D(encoder, pso: pso, width: count, height: 1, preferred: MTLSize(width: 256, height: 1, depth: 1),
                               label: "b2_probe_subtexel_k")
        encoder.endEncoding()
        try await MeasureTextures.commit(recorder)
        let p = out.contents().bindMemory(to: Float.self, capacity: count)
        return Array(UnsafeBufferPointer(start: p, count: count))
    }

    private func subTexel(_ context: GPUContext, _ device: DeviceStamp) async throws -> DeviceProbeResult {
        let n = Self.subTexelSamples
        let x = MeasureSubTexelAnalysis(samples: try await sampleSubTexel(context), count: n)
        try Task.checkCancellation()
        let y = MeasureSubTexelAnalysis(samples: try await sampleSubTexel(context, axis: 1), count: n)
        // Far from the origin (texels 1000 | 1001 of 1,024): coordinate precision must not cost fraction bits there.
        let wide = MeasureSubTexelAnalysis(samples: try await sampleSubTexel(context, width: 1024, base: 1000), count: n)
        let unorm = MeasureSubTexelAnalysis(samples: try await sampleSubTexel(context, format: .rgba8Unorm), count: n)
        let agree = x.bits == y.bits && x.bits == wide.bits && x.roundsToNearest == y.roundsToNearest && x.roundsToNearest == wide.roundsToNearest
        let numbers: [String: Double] = [
            "subTexelBits": Double(x.bits), "roundsToNearest": x.roundsToNearest ? 1 : 0, "distinctValues": Double(x.distinct),
            "maxError": x.maxError, "nearestMatchFraction": x.nearestFraction, "truncateMatchFraction": x.truncateFraction,
            "subTexelBitsY": Double(y.bits), "roundsToNearestY": y.roundsToNearest ? 1 : 0,
            "subTexelBitsWide": Double(wide.bits), "roundsToNearestWide": wide.roundsToNearest ? 1 : 0,
            "subTexelBitsUnorm8": Double(unorm.bits), "axesAgree": agree ? 1 : 0,
        ]
        let rows = [
            row("bits", "SUB-TEXEL BITS", Double(x.bits), .integer(noun: CountNoun("bit", "bits")), device,
                caption: agree ? nil : "AXES OR POSITIONS DIFFER"),
            words("rounding", "WEIGHT ROUNDING", x.roundsToNearest ? "ROUND TO NEAREST" : "TRUNCATE", device),
            row("distinct", "DISTINCT WEIGHTS", Double(x.distinct), .integer(), device),
            row("maxError", "WORST WEIGHT ERROR", x.maxError, .significant(3), device),
        ]
        return DeviceProbeResult(kind: .bilinearSubTexelBits, rows: rows, numbers: numbers, device: device)
    }

    // MARK: generateMipmaps impulse (ARCHITECTURE §4.3 "Mip chains"; research §3.5)

    /// Level-1 and level-2 texels after `generateMipmaps` of a 16 × 16 impulse of 1.0 at (8, 8), read back through a
    /// blit from the private texture (never getBytes on a mip level, research §2.7 item 7).
    func mipmapLevels(_ context: GPUContext) async throws -> (level1: [Float], level2: [Float]) {
        var impulse = ImageBuffer(width: 16, height: 16)
        impulse[8, 8] = SIMD4(1, 1, 1, 1)
        let texture = try await MeasureTextures.upload(impulse, format: .rgba16Float, usage: [.shaderRead, .renderTarget], mipmapped: true,
                                                       context: context)
        let recorder = GPUCommandRecorder(context: context, label: "probe generateMipmaps")
        let blit = try recorder.blitEncoder(pass: 0, label: "generateMipmaps")
        blit.generateMipmaps(for: texture)
        blit.endEncoding()
        try await MeasureTextures.commit(recorder)
        let l1 = try await context.readTexels(texture, region: PixelRegion(origin: .zero, size: .square(8)), level: 1)
        let l2 = try await context.readTexels(texture, region: PixelRegion(origin: .zero, size: .square(4)), level: 2)
        return (l1.map(\.x), l2.map(\.x))
    }

    private func mipmapImpulse(_ context: GPUContext, _ device: DeviceStamp) async throws -> DeviceProbeResult {
        let (l1, l2) = try await mipmapLevels(context)
        let p1 = Double(l1.max() ?? 0), p2 = Double(l2.max() ?? 0)
        let n1 = l1.filter { $0 != 0 }.count, n2 = l2.filter { $0 != 0 }.count
        let s1 = l1.reduce(0, +), s2 = l2.reduce(0, +)
        let box = p1 == 0.25 && n1 == 1 && p2 == 0.0625 && n2 == 1
        let numbers: [String: Double] = ["level1Peak": p1, "level2Peak": p2, "level1NonZero": Double(n1), "level2NonZero": Double(n2),
                                         "level1Sum": Double(s1), "level2Sum": Double(s2), "box2x2": box ? 1 : 0]
        let rows = [
            row("level1", "MIP LEVEL 1 PEAK", p1, Self.level, device),
            row("level2", "MIP LEVEL 2 PEAK", p2, Self.level, device),
            words("filter", "FILTER", box ? "2×2 BOX" : "NOT A 2×2 BOX", device, caption: box ? nil : "SEE LEVEL SUMS IN THE RUN LOG"),
        ]
        return DeviceProbeResult(kind: .mipmapImpulse, rows: rows, numbers: numbers, device: device)
    }

    // MARK: Copy bandwidth (research §5 item 5: blit and compute copy of a large noise texture)

    static let copyWidth = 4096, copyHeight = 2048
    static let copiesPerCommandBuffer = 4

    private func copyBandwidth(_ context: GPUContext, _ device: DeviceStamp, compute: Bool) async throws -> DeviceProbeResult {
        let kind: DeviceProbeKind = compute ? .copyBandwidthCompute : .copyBandwidthBlit
        let label = compute ? "COMPUTE COPY BANDWIDTH" : "BLIT COPY BANDWIDTH"
        if simulated(context, device) { return noTiming(kind, label, device) }
        let w = Self.copyWidth, h = Self.copyHeight
        let srcSpec = TextureSpec(width: w, height: h, roles: [.read, .computeWrite])
        let dstSpec = TextureSpec(width: w, height: h, roles: compute ? [.read, .computeWrite] : [.read])
        let src = try context.texture(srcSpec), dst = try context.texture(dstSpec)
        defer { context.recycle(src, spec: srcSpec); context.recycle(dst, spec: dstSpec) }
        try await MeasureTextures.fillNoise(src, seed: 0xB2C0_FFEE, context: context)
        let copyPSO = compute ? try await context.computePipeline("b2_probe_copy_k", constants: FunctionConstants()) : nil
        func encode(_ recorder: GPUCommandRecorder) throws {
            for i in 0..<Self.copiesPerCommandBuffer {
                if let pso = copyPSO {
                    let e = try recorder.computeEncoder(pass: i, label: "compute copy")
                    e.setTexture(src, index: 0); e.setTexture(dst, index: 1)
                    try context.dispatch2D(e, pso: pso, width: w, height: h, label: "b2_probe_copy_k")
                    e.endEncoding()
                } else {
                    let b = try recorder.blitEncoder(pass: i, label: "blit copy")
                    b.copy(from: src, to: dst)
                    b.endEncoding()
                }
            }
        }
        let times = try await MeasureTextures.time(context, warmups: 2, samples: 9, label: label, encode)
        guard let median = MeasureStatistics.median(times), median > 0 else { throw GPUError.commandBufferFailed("no copy timing") }
        let bytesPerCopy = Double(2 * w * h * 8)                 // one read and one write of every rgba16Float texel
        let perCopy = median / Double(Self.copiesPerCommandBuffer)
        let gigabytesPerSecond = bytesPerCopy / (perCopy / 1000) / 1e9
        let numbers: [String: Double] = ["gigabytesPerSecond": gigabytesPerSecond, "bytesPerCopy": bytesPerCopy,
                                         "millisecondsPerCopy": perCopy, "copiesPerCommandBuffer": Double(Self.copiesPerCommandBuffer),
                                         "samples": Double(times.count),
                                         "iqrMillisecondsPerCopy": (MeasureStatistics.iqr(times) ?? 0) / Double(Self.copiesPerCommandBuffer)]
        let rows = [
            row(kind.rawValue, label, gigabytesPerSecond, Self.gbps, device, caption: "READ + WRITE OF A NOISE TEXTURE"),
            row("\(kind.rawValue)-time", "TIME PER COPY", perCopy, Self.ms, device),
            row("\(kind.rawValue)-bytes", "BYTES PER COPY", bytesPerCopy / 1e6, Self.megabytes, device),
        ]
        return DeviceProbeResult(kind: kind, rows: rows, numbers: numbers, device: device)
    }

    // MARK: Compression A/B (research §2.6: fragment-written textures keep lossless compression unless .shaderWrite)

    static let compressionSide = 2048
    static let compressionPasses = 8

    private func compressionAB(_ context: GPUContext, _ device: DeviceStamp) async throws -> DeviceProbeResult {
        if simulated(context, device) { return noTiming(.compressionAB, "COMPRESSION A/B", device) }
        let n = Self.compressionSide
        let gradient = try await context.renderPipeline(fragment: "b2_probe_gradient_fs", colorFormats: [.rgba16Float], constants: FunctionConstants())
        let boxH = try await context.renderPipeline(fragment: "b2_probe_box_fs", colorFormats: [.rgba16Float], constants: FunctionConstants(direction: 0))
        let boxV = try await context.renderPipeline(fragment: "b2_probe_box_fs", colorFormats: [.rgba16Float], constants: FunctionConstants(direction: 1))
        let plainSpec = TextureSpec(width: n, height: n, roles: [.read, .renderTarget])
        let writeSpec = TextureSpec(width: n, height: n, roles: [.read, .renderTarget, .computeWrite])
        let plain = [try context.texture(plainSpec), try context.texture(plainSpec)]
        let writable = [try context.texture(writeSpec), try context.texture(writeSpec)]
        defer {
            for t in plain { context.recycle(t, spec: plainSpec) }
            for t in writable { context.recycle(t, spec: writeSpec) }
        }
        func pass(_ recorder: GPUCommandRecorder, _ index: Int, _ state: any MTLRenderPipelineState, source: (any MTLTexture)?,
                  destination: any MTLTexture, label: String) throws {
            let d = MTLRenderPassDescriptor()
            d.colorAttachments[0].texture = destination
            d.colorAttachments[0].loadAction = .dontCare
            d.colorAttachments[0].storeAction = .store
            let e = try recorder.renderEncoder(pass: index, descriptor: d, label: label)
            e.setRenderPipelineState(state)
            if let source { e.setFragmentTexture(source, index: 0) }
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            e.endEncoding()
        }
        // Smooth content in both pairs, written by a fragment pass (stored compressed where the usage allows).
        for pair in [plain, writable] {
            let r = GPUCommandRecorder(context: context, label: "compression fill")
            try pass(r, 0, gradient, source: nil, destination: pair[0], label: "gradient")
            try MeasureTextures.commitOrThrow(await r.commitAndWait())
        }
        func encoder(_ pair: [any MTLTexture]) -> (GPUCommandRecorder) throws -> Void {
            { recorder in
                for i in 0..<Self.compressionPasses {
                    try pass(recorder, i, i % 2 == 0 ? boxH : boxV, source: pair[i % 2], destination: pair[(i + 1) % 2],
                             label: i % 2 == 0 ? "box H" : "box V")
                }
            }
        }
        let (a, b) = try await MeasureTextures.timeABAB(context, warmups: 2, samples: 9, encoder(plain), encoder(writable))
        guard let ma = MeasureStatistics.median(a), let mb = MeasureStatistics.median(b), ma > 0, mb > 0 else {
            throw GPUError.commandBufferFailed("no compression timing")
        }
        let perPassA = ma / Double(Self.compressionPasses), perPassB = mb / Double(Self.compressionPasses)
        let numbers: [String: Double] = ["compressedMilliseconds": perPassA, "uncompressedMilliseconds": perPassB, "ratio": mb / ma,
                                         "passesPerCommandBuffer": Double(Self.compressionPasses), "samples": Double(a.count),
                                         "side": Double(n)]
        let rows = [
            row("compressed", "WITHOUT SHADERWRITE", perPassA, Self.ms, device, caption: "PER BOX PASS"),
            row("uncompressed", "WITH SHADERWRITE", perPassB, Self.ms, device, caption: "PER BOX PASS"),
            row("ratio", "SHADERWRITE COST", mb / ma, Self.ratio, device, caption: "SAME PASS · ONLY THE USAGE FLAG DIFFERS"),
        ]
        return DeviceProbeResult(kind: .compressionAB, rows: rows, numbers: numbers, device: device)
    }

    // MARK: FMA throughput (the roofline's ALU ceiling, research §5 item 5)

    static let fmaGrid = 1024, fmaIterations = 256

    private func fmaThroughput(_ context: GPUContext, _ device: DeviceStamp) async throws -> DeviceProbeResult {
        if simulated(context, device) { return noTiming(.fmaThroughput, "FMA THROUGHPUT", device) }
        let g = Self.fmaGrid
        guard let out = context.device.makeBuffer(length: g * g * MemoryLayout<Float>.stride, options: .storageModePrivate) else {
            throw GPUError.bufferAllocationFailed
        }
        var params = MeasureFMAParams(iterations: UInt32(Self.fmaIterations), width: UInt32(g), a: 0.999_9, b: 1.0e-4)
        var medians: [Double] = []
        for name in ["b2_probe_fma_k", "b2_probe_fma_half_k"] {
            let pso = try await context.computePipeline(name, constants: FunctionConstants())
            let times = try await MeasureTextures.time(context, warmups: 2, samples: 7, label: name) { recorder in
                let e = try recorder.computeEncoder(pass: 0, label: name)
                e.setBytes(&params, length: MemoryLayout<MeasureFMAParams>.stride, index: 0)
                e.setBuffer(out, offset: 0, index: 3)
                try context.dispatch2D(e, pso: pso, width: g, height: g, label: name)
                e.endEncoding()
            }
            guard let m = MeasureStatistics.median(times), m > 0 else { throw GPUError.commandBufferFailed("no FMA timing") }
            medians.append(m)
        }
        let fmas = Double(g * g) * Double(Self.fmaIterations) * 16           // 4 chains × float4 per iteration
        let f32 = 2 * fmas / (medians[0] / 1000) / 1e9, f16 = 2 * fmas / (medians[1] / 1000) / 1e9
        let numbers: [String: Double] = ["gigaflopsFP32": f32, "gigaflopsFP16": f16, "millisecondsFP32": medians[0],
                                         "millisecondsFP16": medians[1], "fmasPerDispatch": fmas]
        let rows = [
            row("fp32", "FP32 FMA THROUGHPUT", f32, Self.gflops, device, caption: "DEPENDENT FMA CHAINS · NO MEMORY TRAFFIC"),
            row("fp16", "FP16 FMA THROUGHPUT", f16, Self.gflops, device),
        ]
        return DeviceProbeResult(kind: .fmaThroughput, rows: rows, numbers: numbers, device: device)
    }

    // MARK: Counter sampling points (research §4.3 item 2)

    private func counterSamplingPoints(_ context: GPUContext, _ device: DeviceStamp) async throws -> DeviceProbeResult {
        let d = context.device
        let points: [(String, String, MTLCounterSamplingPoint)] = [
            ("atStageBoundary", "STAGE BOUNDARY", .atStageBoundary), ("atDrawBoundary", "DRAW BOUNDARY", .atDrawBoundary),
            ("atDispatchBoundary", "DISPATCH BOUNDARY", .atDispatchBoundary),
            ("atTileDispatchBoundary", "TILE DISPATCH BOUNDARY", .atTileDispatchBoundary), ("atBlitBoundary", "BLIT BOUNDARY", .atBlitBoundary),
        ]
        var numbers: [String: Double] = [:]
        for (key, _, point) in points { numbers[key] = d.supportsCounterSampling(point) ? 1 : 0 }
        let hasTimestamps = d.counterSets?.contains { $0.name == MTLCommonCounterSet.timestamp.rawValue } ?? false
        numbers["timestampCounterSet"] = hasTimestamps ? 1 : 0
        // Do stage-boundary samples actually resolve? One compute and one blit pass, each with its own encoder.
        var resolved = false
        if !simulated(context, device), let sampler = MeasureStageBoundarySampler(device: d, passes: 2) {
            let ratio = await sampler.clock.calibrated()
            numbers["gpuTicksPerNanosecond"] = ratio
            if let ns = sampler.clock.cpuTimestampIsNanoseconds { numbers["cpuTimestampIsNanoseconds"] = ns ? 1 : 0 }
            let spec = TextureSpec(width: 256, height: 256, roles: [.read, .computeWrite])
            let a = try context.texture(spec), b = try context.texture(spec)
            defer { context.recycle(a, spec: spec); context.recycle(b, spec: spec) }
            let pso = try await context.computePipeline("b2_probe_copy_k", constants: FunctionConstants())
            let recorder = GPUCommandRecorder(context: context, isolation: .stageBoundaryCounters, label: "probe counters", sampler: sampler)
            let e = try recorder.computeEncoder(pass: 0, label: "compute copy")
            e.setTexture(a, index: 0); e.setTexture(b, index: 1)
            try context.dispatch2D(e, pso: pso, width: 256, height: 256, label: "b2_probe_copy_k")
            e.endEncoding()
            let blit = try recorder.blitEncoder(pass: 1, label: "blit copy")
            blit.copy(from: b, to: a)
            blit.endEncoding()
            let done = await recorder.commitAndWait()
            try MeasureTextures.commitOrThrow(done)
            let perPass = recorder.passMilliseconds(done) ?? [:]
            resolved = (perPass[0] ?? 0) > 0 && (perPass[1] ?? 0) > 0
        }
        numbers["stageBoundaryResolved"] = resolved ? 1 : 0
        var rows = points.map { key, label, _ in words(key, label, numbers[key] == 1 ? "SUPPORTED" : "NOT SUPPORTED", device) }
        rows.append(words("timestamps", "PER-PASS TIMESTAMPS", resolved ? "RESOLVED" : "UNAVAILABLE", device,
                          caption: resolved ? "ONE ENCODER PER PASS" : nil))
        return DeviceProbeResult(kind: .counterSamplingPoints, rows: rows, numbers: numbers, device: device)
    }

    // MARK: Traced = untraced (JF §9 #9; ARCHITECTURE §7 rule 5)

    /// The shared Gaussian stage (fragment and compute forms; review fix E-14), whose traced specializations every Trace
    /// of a Gaussian-based blur runs: each factory's first checkTraced parity case at 128 × 128, rendered traced and
    /// untraced on this GPU and compared word for word.
    public static let tracedFactories: [(BlurID, VariantID)] = [("gaussian-blur", "gaussian-separable"),
                                                                ("gaussian-blur", "gaussian-linear-sampling"),
                                                                ("gaussian-blur", "gaussian-compute-tile")]

    func tracedComparisons(_ context: GPUContext, factories: [(BlurID, VariantID)] = DeviceProbeService.tracedFactories,
                           windowSize: Int = 128) async throws -> [(name: String, comparison: TracedComparison?, failure: String?)] {
        var out: [(String, TracedComparison?, String?)] = []
        for (blur, variant) in factories {
            try Task.checkCancellation()
            guard let factory = GPUPipelineRegistry.factory(blur, variant),
                  let parityCase = factory.parityCases(windowSize).first(where: \.checkTraced) else { continue }
            let outcome = await ParityRunner.run(parityCase, factory: factory, context: context, regions: .fullWindow)
            out.append((parityCase.name, outcome.traced, outcome.failure))
        }
        return out
    }

    private func tracedEqualsUntraced(_ context: GPUContext, _ device: DeviceStamp) async throws -> DeviceProbeResult {
        let results = try await tracedComparisons(context)
        let comparisons = results.compactMap(\.comparison)
        let failures = results.compactMap(\.failure)
        let differing = comparisons.reduce(0) { $0 + $1.differingWords }
        let finalOK = comparisons.allSatisfy(\.finalSumMatchesOutput)
        let overflow = comparisons.reduce(0) { $0 + $1.overflow }
        let equal = !comparisons.isEmpty && failures.isEmpty && comparisons.count == results.count && differing == 0 && overflow == 0
            && comparisons.allSatisfy { !$0.missingFinalRecord }
        let numbers: [String: Double] = ["equal": equal ? 1 : 0, "cases": Double(results.count), "differingWords": Double(differing),
                                         "finalSumMatchesOutput": finalOK ? 1 : 0, "overflow": Double(overflow),
                                         "failures": Double(failures.count)]
        let rows = [
            words("traced", "TRACED = UNTRACED", equal ? "BIT-IDENTICAL" : "DIFFERS", device,
                  caption: failures.isEmpty ? "GAUSSIAN STAGE · FRAGMENT AND COMPUTE" : "A CASE FAILED TO RUN"),
            row("tracedCases", "CASES", Double(results.count), .integer(), device),
            row("differing", "DIFFERING FP16 WORDS", Double(differing), .integer(), device),
        ]
        return DeviceProbeResult(kind: .tracedEqualsUntraced, rows: rows, numbers: numbers, device: device)
    }
}

/// The hardware's bilinear weight quantization from `count` samples at t = i / count (Probes.metal b2_probe_subtexel_k).
public struct MeasureSubTexelAnalysis: Sendable, Hashable {
    public var distinct: Int
    /// log2 of the reciprocal of the smallest step between distinct weights (8 → steps of 1/256).
    public var bits: Int
    /// Fractions of samples equal to round(t·2^bits)/2^bits (either tie direction) and to floor(t·2^bits)/2^bits.
    public var nearestFraction: Double
    public var truncateFraction: Double
    public var roundsToNearest: Bool
    /// max |weight − t|: 1/512 = 1.95·10⁻³ for 8 bits rounded to nearest.
    public var maxError: Double

    public init(samples: [Float], count: Int) {
        let values = Set(samples.map { Double($0) }).sorted()
        distinct = values.count
        var step = 1.0
        for (a, b) in zip(values, values.dropFirst()) where b - a > 1e-9 { step = Swift.min(step, b - a) }
        bits = distinct > 1 ? Int((-log2(step)).rounded()) : 0
        let q = pow(2.0, Double(bits))
        var near = 0, trunc = 0, worst = 0.0
        for (i, v) in samples.enumerated() {
            let t = Double(i) / Double(count), x = t * q, value = Double(v)
            if value == (x + 0.5).rounded(.down) / q || value == (x - 0.5).rounded(.up) / q { near += 1 }
            if value == x.rounded(.down) / q { trunc += 1 }
            worst = Swift.max(worst, abs(value - t))
        }
        let n = Double(Swift.max(1, samples.count))
        nearestFraction = Double(near) / n; truncateFraction = Double(trunc) / n
        roundsToNearest = nearestFraction >= truncateFraction
        maxError = worst
    }
}

/// Layouts of Probes.metal's parameter structs.
struct MeasureSubTexelParams { var count: UInt32; var axis: UInt32; var base: Float; var pad: Float }
struct MeasureFMAParams { var iterations: UInt32; var width: UInt32; var a: Float; var b: Float }
struct MeasureFillParams { var seed: UInt32; var pad0: UInt32 = 0; var pad1: UInt32 = 0; var pad2: UInt32 = 0 }

/// Small GPU helpers shared by the probes and the shape service.
@MainActor
enum MeasureTextures {
    /// A private texture holding `image` (converted to the format), uploaded through a shared staging buffer and a blit.
    static func upload(_ image: ImageBuffer, format: MTLPixelFormat, usage: MTLTextureUsage, mipmapped: Bool = false,
                       context: GPUContext) async throws -> any MTLTexture {
        let bytes: Data
        let bpp: Int
        switch format {
        case .rgba8Unorm:
            bpp = 4
            bytes = Data(image.pixels.flatMap { p in (0..<4).map { UInt8((Swift.min(Swift.max(p[$0], 0), 1) * 255).rounded()) } })
        default:
            bpp = 8
            bytes = HalfImageData(image).bytes
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: image.width, height: image.height, mipmapped: mipmapped)
        d.usage = usage
        d.storageMode = .private
        guard let texture = context.device.makeTexture(descriptor: d) else { throw GPUError.textureAllocationFailed("probe \(format.rawValue)") }
        guard let staging = bytes.withUnsafeBytes({ raw in
            raw.baseAddress.flatMap { context.device.makeBuffer(bytes: $0, length: raw.count, options: .storageModeShared) } }) else {
            throw GPUError.bufferAllocationFailed
        }
        let recorder = GPUCommandRecorder(context: context, label: "probe upload")
        let blit = try recorder.blitEncoder(pass: 0, label: "probe upload")
        blit.copy(from: staging, sourceOffset: 0, sourceBytesPerRow: image.width * bpp, sourceBytesPerImage: image.width * bpp * image.height,
                  sourceSize: MTLSize(width: image.width, height: image.height, depth: 1), to: texture, destinationSlice: 0,
                  destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        try await commit(recorder)
        return texture
    }

    /// PCG noise in every channel (b2_probe_noise_k), so lossless compression cannot inflate a copy rate.
    static func fillNoise(_ texture: any MTLTexture, seed: UInt32, context: GPUContext) async throws {
        let pso = try await context.computePipeline("b2_probe_noise_k", constants: FunctionConstants())
        var params = MeasureFillParams(seed: seed)
        let recorder = GPUCommandRecorder(context: context, label: "probe noise")
        let e = try recorder.computeEncoder(pass: 0, label: "noise")
        e.setTexture(texture, index: 1)
        e.setBytes(&params, length: MemoryLayout<MeasureFillParams>.stride, index: 0)
        try context.dispatch2D(e, pso: pso, width: texture.width, height: texture.height, label: "b2_probe_noise_k")
        e.endEncoding()
        try await commit(recorder)
    }

    static func commitOrThrow(_ completions: [GPUCompletion]) throws {
        if let error = completions.compactMap(\.error).first { throw GPUError.commandBufferFailed(error) }
    }

    static func commit(_ recorder: GPUCommandRecorder) async throws {
        try commitOrThrow(await recorder.commitAndWait())
    }

    /// `warmups` untimed then `samples` timed single command buffers; cancellable between them. GPU milliseconds.
    static func time(_ context: GPUContext, warmups: Int, samples: Int, label: String,
                     _ encode: (GPUCommandRecorder) throws -> Void) async throws -> [Double] {
        var times: [Double] = []
        for i in 0..<(warmups + samples) {
            try Task.checkCancellation()
            let recorder = GPUCommandRecorder(context: context, label: "\(label) \(i)")
            try encode(recorder)
            let done = await recorder.commitAndWait()
            try commitOrThrow(done)
            if i >= warmups { times.append(done.reduce(0) { $0 + $1.milliseconds }) }
        }
        try Task.checkCancellation()
        return times
    }

    /// The same, alternating A and B (ABAB) so both see the same clocks and thermal state.
    static func timeABAB(_ context: GPUContext, warmups: Int, samples: Int, _ a: (GPUCommandRecorder) throws -> Void,
                         _ b: (GPUCommandRecorder) throws -> Void) async throws -> ([Double], [Double]) {
        var ta: [Double] = [], tb: [Double] = []
        for i in 0..<(warmups + samples) {
            for index in 0..<2 {
                try Task.checkCancellation()
                let recorder = GPUCommandRecorder(context: context, label: "A/B \(index) \(i)")
                if index == 0 { try a(recorder) } else { try b(recorder) }
                let done = await recorder.commitAndWait()
                try commitOrThrow(done)
                guard i >= warmups else { continue }
                let ms = done.reduce(0) { $0 + $1.milliseconds }
                if index == 0 { ta.append(ms) } else { tb.append(ms) }
            }
        }
        try Task.checkCancellation()
        return (ta, tb)
    }
}
