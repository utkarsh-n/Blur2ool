import Foundation
import Metal
import BlurCore

// OWNER: GPU-MEASURE. ON THIS PHONE (SPEC §7.1 item 10, §7.4, §13.1): the shape of OUR Metal implementation measured
// from GPU output, for the fingerprint card and LOOKS MOST LIKE. Small background renders through the running variant
// (`pipeline.encode` only: the blur's own kernel, no colour or alpha passes), each read back by a blit in the same
// command buffer:
//
//   impulse grid (2 × 2 impulses 128 px apart, or one at the centre below 256 px) → the PSF: σ_equiv, excess kurtosis on
//       the axis and at 45°, and the minimum of H along x, y and both diagonals (projection–slice theorem);
//   4-phase step edge (the step at c, c + 1, c + 2, c + 3)  → edge-centre spread over phases (the shift-variance
//       detector, live-calibration §3.3) and an ESF σ that does not need a usable impulse response (each edge is also
//       rendered as its complement, so both tails are read near 0 where fp16 is precise);
//   45° step edge                                         → kurtosis at 45° when the impulse response is unusable;
//   1-px stripes                                          → the signed response at Nyquist along x;
//   36-cycle sinusoidal star                              → the signed ring response H(ν) for ν = 36/(2πr), orientation-
//       averaged; with the stripes it gives the minimum H of filters whose impulse response is meaningless (rank,
//       range-weighted and selection filters remove or keep an isolated impulse instead of spreading it);
//   timing at the request's size                          → ms per megapixel (nil in the Simulator).
//
// The impulse amplitude is 4,096 (a power of two) on an opaque black background, so the PSF tail of a σ 4 Gaussian at
// 5σ is still a normal fp16 number. Everything is MEASURED from this GPU; the analytic values stay COMPUTED elsewhere.

/// One ring of the star measurement.
public struct MeasureRingResponse: Sendable, Hashable {
    public var radius: Double
    /// cycles per pixel along the ring (36 / 2πr).
    public var frequency: Double
    public var response: Double
}

/// What ShapeService saw, beyond the frozen ShapeMeasurement (tests, Run notes, the Calibrate-style plots).
public struct MeasureShapeReport: Sendable, Hashable {
    public var measurement: ShapeMeasurement
    /// Moments of the averaged impulse response (normalised to mass 1), when it had usable mass.
    public var psf: MeasurePSFMoments?
    /// True when σ, both kurtoses and minimum H came from the impulse response (mass within 5 % of the input's).
    public var usedImpulseResponse: Bool
    /// Moment σ of the line spread of the step edge, per phase, and the edge-centre offsets from the true step position.
    public var edgeSigmas: [Double]
    public var edgeCentreOffsets: [Double]
    /// Excess kurtosis of the edge line spreads on the axis (mean over phases) and of the 45° edge.
    public var edgeKurtosisAxis: Double?
    public var edgeKurtosis45: Double?
    /// The signed response at ν = 0.5 along x from the 1-px stripes.
    public var stripesResponse: Double?
    public var rings: [MeasureRingResponse]
    /// Minimum of H from the impulse response's four slices (nil when unusable).
    public var psfMinimumResponse: Double?
    public var windowSize: ImageSize
}

@MainActor
public final class ShapeService: ShapeMeasuring {
    /// Test seam (ARCHITECTURE §12.3): facts used instead of `context.facts` (the ms/MP column reads SIM in the Simulator).
    var factsOverride: GPUFacts?

    public init() {}
    init(factsOverride: GPUFacts?) { self.factsOverride = factsOverride }

    /// Power of two; at σ 4 the PSF peaks at ≈ 40 and is ≈ 1.5·10⁻⁴ at 5σ, a normal fp16 value.
    public nonisolated static let impulseAmplitude: Float = 4096
    public nonisolated static let cropSide = 128

    public func measure(_ pipeline: any GPUBlurPipeline, request: OperatorRequest, context: GPUContext) async throws -> ShapeMeasurement {
        try await measureReport(pipeline, request: request, context: context).measurement
    }

    public func measureReport(_ pipeline: any GPUBlurPipeline, request: OperatorRequest, context: GPUContext) async throws -> MeasureShapeReport {
        try Task.checkCancellation()
        let size = request.size
        let w = size.width, h = size.height
        guard w >= 32, h >= 32 else { throw GPUError.unsupported("shape measurement needs at least 32 × 32 px") }
        try await pipeline.prepare(context, request: request)
        let c = PixelPoint(x: w / 2, y: h / 2)
        let side = Swift.min(Self.cropSide, Swift.min(w, h))
        let dstSpec = TextureSpec(width: w, height: h, roles: pipeline.writesDestinationFromCompute ? [.read, .renderTarget, .computeWrite] : [.read, .renderTarget])
        let destination = try context.texture(dstSpec)
        defer { context.recycle(destination, spec: dstSpec) }

        func render(_ image: ImageBuffer, crops: [PixelRegion]) async throws -> [ImageBuffer] {
            try Task.checkCancellation()
            let half = await Task.detached(priority: .userInitiated) { HalfImageData(image) }.value
            let source = try await context.upload(half, roles: [.read])
            defer { context.recycle(source, spec: TextureSpec(width: image.width, height: image.height, roles: [.read])) }
            let recorder = GPUCommandRecorder(context: context, label: "shape \(pipeline.variant.rawValue)")
            let encoded = try pipeline.encode(context, GPUBlurInputs(source: source, destination: destination, request: request),
                                              trace: nil, recorder: recorder)
            let reads = try crops.map { try context.encodeReadTexels(destination, region: $0, recorder: recorder) }
            let done = await recorder.commitAndWait()
            context.recycle(encoded)
            try MeasureTextures.commitOrThrow(done)
            return zip(reads, crops).map { ImageBuffer(width: $1.size.width, height: $1.size.height, pixels: $0.decode()) }
        }

        // 1. Impulse grid → PSF.
        let impulses = MeasureShapeInputs.impulsePositions(size: size, centre: c, side: side)
        let impulseImage = await Task.detached(priority: .userInitiated) {
            MeasureShapeInputs.impulses(size: size, at: impulses, amplitude: ShapeService.impulseAmplitude)
        }.value
        let psfCrops = impulses.map { PixelRegion(origin: PixelPoint(x: $0.x - side / 2, y: $0.y - side / 2), size: .square(side)) }
        let psfImages = try await render(impulseImage, crops: psfCrops)
        let amplitude = Double(Self.impulseAmplitude) * Double(impulses.count)
        var psf = [Double](repeating: 0, count: side * side)
        for image in psfImages { for (k, p) in image.pixels.enumerated() { psf[k] += Double(p.x) / amplitude } }
        let psfMoments = MeasurePSFMoments(psf: psf, width: side, height: side)
        let usable = psfMoments.map { abs($0.mass - 1) < 0.05 && $0.x.variance > 0 && $0.y.variance > 0 } ?? false
        let psfMinimum = usable ? MeasureShapeMath.minimumResponse(psf: psf, width: side, height: side) : nil

        // An edge renders twice, as itself and as its complement (1 − v), and each tail is read from the render in which it
        // is near 0: fp16 spaces values below 1 by 2⁻¹¹, which inflates a 0 → 1 ESF's upper tail (MEASURED: σ +0.5 %,
        // kurtosis +0.1 at σ 4), while values near 0 keep full relative precision.
        func edgeSpread(_ image: ImageBuffer, region: PixelRegion) async throws -> ImageBuffer {
            let direct = try await render(image, crops: [region])[0]
            let complement = await Task.detached(priority: .userInitiated) { MeasureShapeInputs.complement(image) }.value
            let inverse = try await render(complement, crops: [region])[0]
            return ImageBuffer(width: direct.width, height: direct.height, pixels: zip(direct.pixels, inverse.pixels).map { a, b in
                let v = a.x <= 0.5 ? a.x : 1 - b.x
                return SIMD4(v, v, v, 1)
            })
        }

        // 2. 4-phase step edge → ESF/LSF per phase.
        let rowsHalf = 4
        let edgeRegion = PixelRegion(origin: PixelPoint(x: Swift.max(0, c.x - side / 2), y: c.y - rowsHalf),
                                     size: ImageSize(width: Swift.min(side, w - Swift.max(0, c.x - side / 2)), height: 2 * rowsHalf))
        var edgeSigmas: [Double] = [], offsets: [Double] = [], kurtoses: [Double] = []
        var phase0: ImageBuffer?
        for phase in 0..<4 {
            let step = c.x + phase
            let image = await Task.detached(priority: .userInitiated) { MeasureShapeInputs.verticalStep(size: size, at: step) }.value
            if phase == 0 { phase0 = image }
            let crop = try await edgeSpread(image, region: edgeRegion)
            let esf = (0..<crop.width).map { x in (0..<crop.height).reduce(0.0) { $0 + Double(crop[x, $1].x) } / Double(crop.height) }
            let lsf = MeasureShapeMath.lineSpread(esf: esf, origin: Double(edgeRegion.origin.x))
            if let m = MeasureProfileMoments(weights: lsf.weights, positions: lsf.positions, minimumMass: 0.5) {
                edgeSigmas.append(m.sigma); offsets.append(m.mean - Double(step)); kurtoses.append(m.excessKurtosis)
            }
        }

        // 3. 45° step edge (white where (x − cx) + (y − cy) ≥ 0) → the diagonal line spread on the s = x + y grid.
        let diagonal = await Task.detached(priority: .userInitiated) { MeasureShapeInputs.diagonalStep(size: size, centre: c) }.value
        let diagonalRegion = PixelRegion.centred(on: c, side: side, inside: size)
        let diagonalCrop = try await edgeSpread(diagonal, region: diagonalRegion)
        let kurtosis45Edge = MeasureShapeInputs.diagonalLineSpreadKurtosis(diagonalCrop, region: diagonalRegion, centre: c)

        // 4. 1-px stripes → H(0.5) along x.
        let stripes = await Task.detached(priority: .userInitiated) { MeasureShapeInputs.stripes(size: size) }.value
        let stripesRegion = PixelRegion.centred(on: c, side: Swift.min(64, side), inside: size)
        let stripesCrop = try await render(stripes, crops: [stripesRegion])[0]
        var out: [Double] = [], pattern: [Double] = []
        for y in 0..<stripesCrop.height {
            for x in 0..<stripesCrop.width {
                out.append(Double(stripesCrop[x, y].x)); pattern.append((stripesRegion.origin.x + x) % 2 == 0 ? 0.5 : -0.5)
            }
        }
        let stripesResponse = MeasureShapeMath.modulation(output: out, pattern: pattern)

        // 5. Sinusoidal star → ring responses.
        let star = await Task.detached(priority: .userInitiated) { MeasureShapeInputs.star(size: size, centre: c) }.value
        let starRegion = PixelRegion.centred(on: c, side: side, inside: size)
        let starCrop = try await render(star, crops: [starRegion])[0]
        let rings = MeasureShapeInputs.ringResponses(starCrop, region: starRegion, centre: c)

        // 6. ms per megapixel at the request's size (the blur alone, whole command buffer; never in the Simulator).
        var msPerMP: Double?
        if !(factsOverride ?? context.facts).isSimulator, let edge = phase0 {
            let half = await Task.detached(priority: .userInitiated) { HalfImageData(edge) }.value
            let source = try await context.upload(half, roles: [.read])
            defer { context.recycle(source, spec: TextureSpec(width: w, height: h, roles: [.read])) }
            let timing = TimingService(factsOverride: factsOverride)
            let session = MeasureTimingSession(service: timing, pipeline: pipeline,
                                               inputs: GPUBlurInputs(source: source, destination: destination, request: request),
                                               request: TimingRequest(warmups: 3, samples: 7, minSamples: 3, maxGPUSeconds: 0.25),
                                               context: context, wholeOnly: true)
            try await session.warmUp()
            var gpu = 0.0
            while session.samples < 7 {
                gpu += try await session.sample()
                if session.samples >= 3 && gpu >= 0.25 { break }
            }
            if let median = MeasureStatistics.median(session.whole) { msPerMP = median / (Double(w * h) / 1e6) }
        }

        let ringMinimum = (rings.map(\.response) + [stripesResponse].compactMap { $0 }).min()
        let edgeSigma = edgeSigmas.isEmpty ? nil : edgeSigmas.reduce(0, +) / Double(edgeSigmas.count)
        let edgeKurtosis = kurtoses.isEmpty ? nil : kurtoses.reduce(0, +) / Double(kurtoses.count)
        let spread = offsets.isEmpty ? 0 : (offsets.max()! - offsets.min()!)
        let measurement = ShapeMeasurement(
            sigmaPx: usable ? psfMoments!.sigma : (edgeSigma ?? 0),
            excessKurtosisAxis: usable ? psfMoments!.x.excessKurtosis : (edgeKurtosis ?? 0),
            excessKurtosis45: usable ? psfMoments!.diagonal45.excessKurtosis : (kurtosis45Edge ?? 0),
            shiftSpreadPx: spread,
            minResponse: (usable ? psfMinimum : ringMinimum) ?? 0,
            millisecondsPerMegapixel: msPerMP)
        return MeasureShapeReport(measurement: measurement, psf: psfMoments, usedImpulseResponse: usable, edgeSigmas: edgeSigmas,
                                  edgeCentreOffsets: offsets, edgeKurtosisAxis: edgeKurtosis, edgeKurtosis45: kurtosis45Edge,
                                  stripesResponse: stripesResponse, rings: rings, psfMinimumResponse: psfMinimum, windowSize: size)
    }
}

/// The procedural inputs of the shape measurement (deterministic; linear, premultiplied, opaque) and their read-outs.
public enum MeasureShapeInputs {
    static let black = SIMD4<Float>(0, 0, 0, 1), white = SIMD4<Float>(1, 1, 1, 1)

    /// 2 × 2 impulses 128 px apart around the centre when the window holds four crops, else one at the centre.
    public static func impulsePositions(size: ImageSize, centre c: PixelPoint, side: Int) -> [PixelPoint] {
        let half = side / 2
        let grid = [PixelPoint(x: c.x - half, y: c.y - half), PixelPoint(x: c.x + half, y: c.y - half),
                    PixelPoint(x: c.x - half, y: c.y + half), PixelPoint(x: c.x + half, y: c.y + half)]
        let fits = grid.allSatisfy { $0.x - half >= 0 && $0.y - half >= 0 && $0.x + half <= size.width && $0.y + half <= size.height }
        if fits && side == ShapeService.cropSide { return grid }
        return [PixelPoint(x: Swift.min(Swift.max(c.x, half), size.width - half), y: Swift.min(Swift.max(c.y, half), size.height - half))]
    }

    public static func impulses(size: ImageSize, at points: [PixelPoint], amplitude: Float) -> ImageBuffer {
        var image = ImageBuffer(width: size.width, height: size.height, fill: black)
        for p in points { image[p.x, p.y] = SIMD4(amplitude, amplitude, amplitude, 1) }
        return image
    }

    /// White for x ≥ `at` (the step's left boundary is at continuous x = at).
    public static func verticalStep(size: ImageSize, at x0: Int) -> ImageBuffer {
        var image = ImageBuffer(width: size.width, height: size.height, fill: black)
        for y in 0..<size.height { for x in Swift.max(0, x0)..<size.width { image[x, y] = white } }
        return image
    }

    /// 1 − v in the colour channels (alpha stays 1): the edge's complement, whose upper tail is read near 0.
    public static func complement(_ image: ImageBuffer) -> ImageBuffer {
        image.map { SIMD4(1 - $0.x, 1 - $0.y, 1 - $0.z, $0.w) }
    }

    /// White where (x − cx) + (y − cy) ≥ 0: an edge whose normal is the 45° diagonal (y down).
    public static func diagonalStep(size: ImageSize, centre c: PixelPoint) -> ImageBuffer {
        var image = ImageBuffer(width: size.width, height: size.height, fill: black)
        for y in 0..<size.height { for x in 0..<size.width where (x - c.x) + (y - c.y) >= 0 { image[x, y] = white } }
        return image
    }

    /// 1-px vertical stripes: white on even columns.
    public static func stripes(size: ImageSize) -> ImageBuffer {
        var image = ImageBuffer(width: size.width, height: size.height, fill: black)
        for y in 0..<size.height { for x in stride(from: 0, to: size.width, by: 2) { image[x, y] = white } }
        return image
    }

    /// ½ + ½ cos(36θ) about the centre of pixel c (SPEC §11 rule 2: radial images are centred on c + (0.5, 0.5)).
    public static func star(size: ImageSize, centre c: PixelPoint) -> ImageBuffer {
        var image = ImageBuffer(width: size.width, height: size.height, fill: black)
        for y in 0..<size.height {
            for x in 0..<size.width {
                let v = Float(0.5 + MeasureShapeMath.starPattern(x, y, centreX: c.x, centreY: c.y))
                image[x, y] = SIMD4(v, v, v, 1)
            }
        }
        return image
    }

    /// Excess kurtosis of the 45° edge's line spread: the output depends only on s = (x − cx) + (y − cy), so averaging
    /// each s-diagonal of the crop gives the ESF on the s grid and its differences the PSF's projection onto (1, 1).
    public static func diagonalLineSpreadKurtosis(_ crop: ImageBuffer, region: PixelRegion, centre c: PixelPoint) -> Double? {
        var sums: [Int: (Double, Int)] = [:]
        for y in 0..<crop.height {
            for x in 0..<crop.width {
                let s = (region.origin.x + x - c.x) + (region.origin.y + y - c.y)
                let v = Double(crop[x, y].x)
                let e = sums[s] ?? (0, 0)
                sums[s] = (e.0 + v, e.1 + 1)
            }
        }
        // Only diagonals fully inside the crop's inscribed band (|s| ≤ side/2) carry enough samples to be clean.
        let limit = Swift.min(crop.width, crop.height) / 2
        let keys = sums.keys.filter { abs($0) <= limit }.sorted()
        guard keys.count > 2 else { return nil }
        let esf = keys.map { sums[$0]!.0 / Double(sums[$0]!.1) }
        let lsf = MeasureShapeMath.lineSpread(esf: esf, origin: Double(keys[0]))
        return MeasureProfileMoments(weights: lsf.weights, positions: lsf.positions, minimumMass: 0.5)?.excessKurtosis
    }

    /// Ring responses of the blurred star for radii 12 … (side/2 − 4) px, where the ring frequency is ≤ 0.48 c/px.
    public static func ringResponses(_ crop: ImageBuffer, region: PixelRegion, centre c: PixelPoint) -> [MeasureRingResponse] {
        let maxRadius = Swift.min(crop.width, crop.height) / 2 - 4
        guard maxRadius >= 12 else { return [] }
        var buckets: [Int: (out: [Double], pattern: [Double])] = [:]
        for y in 0..<crop.height {
            for x in 0..<crop.width {
                let gx = region.origin.x + x, gy = region.origin.y + y
                let r = (Double(gx - c.x) * Double(gx - c.x) + Double(gy - c.y) * Double(gy - c.y)).squareRoot()
                let k = Int(r.rounded())
                guard k >= 12, k <= maxRadius, abs(r - Double(k)) < 0.5 else { continue }
                buckets[k, default: ([], [])].out.append(Double(crop[x, y].x))
                buckets[k, default: ([], [])].pattern.append(MeasureShapeMath.starPattern(gx, gy, centreX: c.x, centreY: c.y))
            }
        }
        return buckets.keys.sorted().compactMap { k in
            guard let b = buckets[k], let h = MeasureShapeMath.modulation(output: b.out, pattern: b.pattern) else { return nil }
            return MeasureRingResponse(radius: Double(k), frequency: MeasureShapeMath.starFrequency(radius: Double(k)), response: h)
        }
    }
}
