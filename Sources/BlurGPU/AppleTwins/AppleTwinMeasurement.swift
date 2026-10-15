import Foundation
import Metal
import BlurCore

// OWNER: APPLE-TWINS. Measuring the twins from outside, the way research CAL §3 measured them on the Mac:
//   • edgeSamples (AppleTwinRunning, for Calibrate): a black | white step rendered through the API at `phases` whole-pixel
//     offsets, the 16 centre rows read back in the blur's working space, one EdgeSamples per phase (plus the 45° step at
//     phase 0 for the separable-vs-isotropic test). The canvas keeps the API's border (transparent for Core Image and MPS)
//     ≥ 4.5 σ away from the analysis window, so the plateaus are clean without changing the API's settings.
//   • impulseResponse: one white pixel through the API, read back whole, 2-D moments (zoom streaks, motion direction).
//   • edgePolicy: an all-white image and one with a black first column (CAL §3.3 "Edge mode").
// Everything a probe returns is MEASURED on the device it ran on; callers attach the DeviceStamp.

/// What the API does at the image border (CAL §3.3), MEASURED by `edgePolicy`.
public enum AppleTwinEdgeVerdict: String, Sendable, Codable, Hashable {
    /// Past the border counts as transparent black: a white image's border darkens and loses alpha.
    case transparent
    /// Past the border repeats the edge pixel: a black first column pulls the border to about half.
    case clamp
    /// The kernel is renormalised (or mirrored) inside the image: a black first column barely darkens the border.
    case renormalised
}

public struct AppleTwinEdgeProbe: Sendable, Codable, Hashable {
    /// Working-space value at column 0 (centre rows) of a blurred all-white image.
    public var whiteBorderValue: Double
    public var whiteBorderAlpha: Double
    /// The same when the input's column 0 is black.
    public var blackColumnBorderValue: Double
    public var verdict: AppleTwinEdgeVerdict
}

extension AppleTwinRunner {
    /// Canvas geometry for one edge measurement.
    struct EdgeGeometry {
        var reach: Int        // analysis half-window (px)
        var margin: Int       // extra canvas beyond the window, so the API's border cannot reach it
        var width: Int
        var height: Int
        var firstEdge: Int    // x of the first white column at phase 0
        var zoomDistance: Int?

        static let rows = 16
        static let band = 48

        init(subject: CalibrationSubject, parameter p: Double, phases: Int) {
            let sigmaGuess: Double
            switch subject {
            case .ciZoomBlur:
                let d = 200
                zoomDistance = d
                sigmaGuess = Swift.max(4, Swift.min(3, 0.03 * Swift.max(p, 1)) * Double(d) / 12.0.squareRoot() + 2)
            case .ciBoxBlur, .mpsBox, .mpsTent, .vImageBox, .vImageTent:
                zoomDistance = nil
                sigmaGuess = 0.6 * Swift.max(p, 1) + 1
            case .ciMaskedVariableBlur:
                // MEASURED (Mac): σ ≈ 1.14·r with excess kurtosis ≈ +1, so the tails need a wider window than 6·r.
                zoomDistance = nil
                sigmaGuess = 1.5 * Swift.max(p, 1)
            default:
                zoomDistance = nil
                sigmaGuess = Swift.max(p, 1)
            }
            reach = Int((6 * sigmaGuess).rounded(.up)) + 8
            margin = Int((4.5 * sigmaGuess).rounded(.up)) + 8
            width = 2 * (reach + margin) + Swift.max(1, phases) + 2
            height = Swift.max(32, 2 * margin + EdgeGeometry.rows)
            firstEdge = reach + margin + 1
        }

        /// Side of the square 45° canvas: the diagonal band (|x − y| < reach, |x + y − (2c − 1)| ≤ band) stays `margin`
        /// away from every border.
        var diagonalSide: Int { reach + EdgeGeometry.band + 2 * margin + 8 }
    }

    /// Readback → the numbers the API averaged (its working space), for one framework and storage choice.
    nonisolated static func workingSpaceIsEncoded(_ subject: CalibrationSubject, colourMode: CalibrationColourMode) -> Bool {
        switch AppleTwinCatalog.facts(subject)?.framework {
        case .coreImage?: false                                // CIContext default: linear light
        default: colourMode == .nonLinear                      // MPS / vImage: what the stored numbers mean
        }
    }

    /// Options the edge measurement uses: the API's defaults, with the zoom centre `zoomDistance` px left of the edge
    /// (so the streak there is horizontal and outward) and the full radius everywhere for the masked variable blur.
    func edgeOptions(_ request: CalibrationRequest, geometry g: EdgeGeometry, edge: Int) -> AppleTwinOptions {
        var options = AppleTwinOptions(mask: .uniform(1))
        options.vImageStorage = AppleTwinRunner.workingSpaceIsEncoded(request.subject, colourMode: request.colourMode) ? .srgb8 : .linear8
        if let d = g.zoomDistance { options.centre = SIMD2(Double(edge - d), Double(g.height) / 2) }
        return options
    }

    /// Readback texels → the numbers the API averaged. Only the vImage sRGB storage differs: the run decoded its 8-bit
    /// premultiplied-encoded result to linear light, so this re-encodes it the way the buffer held it, encode(c/α)·α.
    nonisolated static func toWorkingSpace(_ texels: [SIMD4<Float>], subject: CalibrationSubject, options: AppleTwinOptions) -> [SIMD4<Float>] {
        guard (subject == .vImageBox || subject == .vImageTent) && options.vImageStorage == .srgb8 else { return texels }
        return texels.map { p in
            guard p.w > 0 else { return .zero }
            let a = Double(p.w)
            return SIMD4(Float(SRGB.encode(Swift.max(0, Double(p.x) / a)) * a), Float(SRGB.encode(Swift.max(0, Double(p.y) / a)) * a),
                         Float(SRGB.encode(Swift.max(0, Double(p.z) / a)) * a), p.w)
        }
    }

    // MARK: edgeSamples (AppleTwinRunning)

    public func edgeSamples(_ request: CalibrationRequest, context: GPUContext) async throws -> [EdgeSamples] {
        guard supports(request.subject) else {
            throw GPUError.unsupported("\(request.subject.title) is measured through ImageRenderer (Calibrate), not as an in-process twin")
        }
        let g = EdgeGeometry(subject: request.subject, parameter: request.parameter, phases: request.phases)
        guard g.width <= 8192, g.diagonalSide <= 8192 else {
            throw GPUError.budgetExceeded("\(request.subject.title) parameter \(AppleTwinRunner.number(request.parameter)): edge canvas \(g.width) px wide")
        }
        let encoded = AppleTwinRunner.workingSpaceIsEncoded(request.subject, colourMode: request.colourMode)
        let size = ImageSize(width: g.width, height: g.height)
        let output = try makeOutput(size: size, context: context)
        var samples: [EdgeSamples] = []
        for phase in 0..<Swift.max(1, request.phases) {
            try Task.checkCancellation()
            let edge = g.firstEdge + phase
            let options = edgeOptions(request, geometry: g, edge: edge)
            var canvas = [SIMD4<Float>](repeating: SIMD4(0, 0, 0, 1), count: g.width * g.height)
            for y in 0..<g.height { for x in edge..<g.width { canvas[y * g.width + x] = SIMD4(1, 1, 1, 1) } }
            let input = try await makeTexture(canvas, size: size, context: context)
            try await run(request.subject, parameter: request.parameter, options: options, input: input, output: output, context: context)
            let rows = try await context.readTexels(output, region: PixelRegion(origin: PixelPoint(x: 0, y: g.height / 2 - EdgeGeometry.rows / 2),
                                                                               size: ImageSize(width: g.width, height: EdgeGeometry.rows)))
            let profile = AppleTwinAnalysis.columnProfile(AppleTwinRunner.toWorkingSpace(rows, subject: request.subject, options: options),
                                                          width: g.width, rows: EdgeGeometry.rows)
            let esf = AppleTwinAnalysis.normalise(Array(profile[(edge - g.reach)..<(edge + g.reach)]))
            let mid = (esf[g.reach - 1] + esf[g.reach]) / 2
            var esf45: [Double]? = nil
            if phase == 0 && request.subject != .ciZoomBlur {
                esf45 = try await diagonalESF(request, geometry: g, options: options, context: context)
            }
            samples.append(EdgeSamples(esf: esf, edgePosition: Double(g.reach), phase: phase,
                                       encodedMidpoint: encoded ? mid : SRGB.encode(Swift.min(Swift.max(mid, 0), 1)), esf45: esf45))
        }
        return samples
    }

    /// The 45° step (white where x − y ≥ 0) through the API, profiled across the diagonal; the edge sits at index `reach`.
    func diagonalESF(_ request: CalibrationRequest, geometry g: EdgeGeometry, options: AppleTwinOptions,
                     context: GPUContext) async throws -> [Double] {
        let n = g.diagonalSide
        var canvas = [SIMD4<Float>](repeating: SIMD4(0, 0, 0, 1), count: n * n)
        for y in 0..<n { for x in y..<n { canvas[y * n + x] = SIMD4(1, 1, 1, 1) } }
        let size = ImageSize.square(n)
        let input = try await makeTexture(canvas, size: size, context: context)
        let output = try makeOutput(size: size, context: context)
        try await run(request.subject, parameter: request.parameter, options: options, input: input, output: output, context: context)
        let texels = try await context.readTexels(output, region: PixelRegion(origin: .zero, size: size))
        let reach = g.reach, band = EdgeGeometry.band, subject = request.subject
        let profile = await Task.detached(priority: .userInitiated) {
            AppleTwinAnalysis.diagonalProfile(AppleTwinRunner.toWorkingSpace(texels, subject: subject, options: options),
                                              size: n, halfWidth: reach, band: band)
        }.value
        return AppleTwinAnalysis.normalise(profile)
    }

    // MARK: Impulse response

    /// One white pixel at `impulse` on opaque black, through the API at `parameter`, read back whole; 2-D moments of
    /// the mean-RGB response (MEASURED). Used for CIZoomBlur's outward streaks and CIMotionBlur's direction.
    public func impulseResponse(_ subject: CalibrationSubject, parameter: Double, options: AppleTwinOptions = AppleTwinOptions(),
                                size: ImageSize, impulse: PixelPoint, context: GPUContext) async throws -> AppleTwinImpulseMoments {
        guard size.contains(impulse) else { throw GPUError.unsupported("impulse \(impulse) outside \(size)") }
        var canvas = [SIMD4<Float>](repeating: SIMD4(0, 0, 0, 1), count: size.pixelCount)
        canvas[impulse.y * size.width + impulse.x] = SIMD4(1, 1, 1, 1)
        let input = try await makeTexture(canvas, size: size, context: context)
        let output = try makeOutput(size: size, context: context)
        try await run(subject, parameter: parameter, options: options, input: input, output: output, context: context)
        let texels = try await context.readTexels(output, region: PixelRegion(origin: .zero, size: size))
        let w = size.width, h = size.height
        return await Task.detached(priority: .userInitiated) {
            AppleTwinAnalysis.impulseMoments(texels, width: w, height: h, impulse: impulse)
        }.value
    }

    // MARK: Edge policy

    /// CAL §3.3 "Edge mode": a 256² all-white image, then the same with column 0 black, both through the API; values
    /// are read at column 0 over the 16 centre rows, in the API's working space.
    public func edgePolicy(_ subject: CalibrationSubject, parameter: Double, options: AppleTwinOptions = AppleTwinOptions(),
                           context: GPUContext) async throws -> AppleTwinEdgeProbe {
        let n = 256, size = ImageSize.square(n)
        let output = try makeOutput(size: size, context: context)
        func borderTexel(blackColumn: Bool) async throws -> SIMD4<Float> {
            var canvas = [SIMD4<Float>](repeating: SIMD4(1, 1, 1, 1), count: n * n)
            if blackColumn { for y in 0..<n { canvas[y * n] = SIMD4(0, 0, 0, 1) } }
            let input = try await makeTexture(canvas, size: size, context: context)
            try await run(subject, parameter: parameter, options: options, input: input, output: output, context: context)
            let column = try await context.readTexels(output, region: PixelRegion(origin: PixelPoint(x: 0, y: n / 2 - 8),
                                                                                  size: ImageSize(width: 1, height: 16)))
            let working = AppleTwinRunner.toWorkingSpace(column, subject: subject, options: options)
            return working.reduce(SIMD4<Float>.zero, +) / Float(working.count)
        }
        let white = try await borderTexel(blackColumn: false)
        let black = try await borderTexel(blackColumn: true)
        let whiteValue = AppleTwinAnalysis.luminance(white), blackValue = AppleTwinAnalysis.luminance(black)
        let verdict: AppleTwinEdgeVerdict
        if Double(white.w) < 0.95 || whiteValue < 0.95 { verdict = .transparent }
        else if blackValue < 0.75 { verdict = .clamp }
        else { verdict = .renormalised }
        return AppleTwinEdgeProbe(whiteBorderValue: whiteValue, whiteBorderAlpha: Double(white.w),
                                  blackColumnBorderValue: blackValue, verdict: verdict)
    }
}
