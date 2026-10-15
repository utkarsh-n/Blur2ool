import Foundation

// OWNER: FAM-F2 (seed written for the skeleton; the skeleton copies it, FAM-F2 completes it).
// gaussian-blur (SPEC §9.4 F2 row, §5.3 A fixtures). Variants: gaussian-2d-direct, gaussian-separable,
// gaussian-linear-sampling (default), gaussian-compute-tile. Discretisation (Sampled · Integrated · Lindeberg) and
// truncation (2 · 2.5 · 3 · 4 × σ) are parameters; every combination runs on the GPU as a weight table.

public struct GaussianOperator: BlurOperator {
    public init() {}

    public static let id: BlurID = "gaussian-blur"
    public static let direct2D: VariantID = "gaussian-2d-direct"
    public static let separable: VariantID = "gaussian-separable"
    public static let linearSampled: VariantID = "gaussian-linear-sampling"
    public static let computeTile: VariantID = "gaussian-compute-tile"
    /// Dynamic threadgroup memory of the compute-tile variant: one 256 × 1 row (or 1 × 256 column) tile of half4 with
    /// its apron, (256 + 2r) × 8 B (review fix E-12; σ 4 → r 12 → 2,240 B). Bound with dispatch2D(threadgroupMemory:).
    public static func computeTileBytes(radius r: Int) -> Int { (256 + 2 * r) * 8 }
    /// The largest radius whose tile fits the 16,384 B Apple2 limit: (16,384 / 8 − 256) / 2 = 896. Every σ in range
    /// (r ≤ 256 at σ 64, k 4) fits, so the fallback below exists only for devices reporting a smaller limit.
    public static let tileBudgetRadius = (16_384 / 8 - 256) / 2

    public var entry: CatalogEntry {
        let sigma = ParameterSpec(
            key: "sigma", label: "SIGMA", spokenLabel: "sigma", unit: .px,
            kind: .continuous(ContinuousSpec(range: 0.3...64, fineStep: 0.1, decimals: 1,
                                             semanticStops: [0.5, 1, 2, 4, 8, 16, 32, 64].map { SemanticStop($0) },
                                             bands: [MeaningBand(from: 0, "Sub-pixel"), MeaningBand(from: 0.5, "Anti-alias"),
                                                     MeaningBand(from: 1.5, "Softened"), MeaningBand(from: 4, "Frosted"),
                                                     MeaningBand(from: 12, "Backdrop"), MeaningBand(from: 32, "Fog")])),
            defaultValue: .double(12))
        let truncation = ParameterSpec(
            key: "truncation", label: "TRUNCATION", spokenLabel: "truncation", unit: .none,
            kind: .choice(ChoiceSpec([ChoiceOption("2", "2"), ChoiceOption("2.5", "2.5"), ChoiceOption("3", "3"), ChoiceOption("4", "4")])),
            defaultValue: .choice("3"), note: "× σ")
        let discretisation = ParameterSpec(
            key: "discretisation", label: "DISCRETISATION", spokenLabel: "discretisation", unit: .none,
            kind: .choice(ChoiceSpec([ChoiceOption("sampled", "Sampled"), ChoiceOption("integrated", "Integrated"),
                                      ChoiceOption("lindeberg", "Lindeberg")])),
            defaultValue: .choice("sampled"))
        let source = SourceRef("Getreuer 2013, A Survey of Gaussian Convolution Algorithms (IPOL)", url: "https://www.ipol.im/pub/art/2013/87/")
        return CatalogEntry(
            id: Self.id, displayName: "Gaussian blur", family: .f2, tier: .tier1, verdict: .trueBlur, linearity: .lsi,
            separability: .yes,
            properties: [.linear, .shiftInvariant, .separable, .isotropic, .positiveKernel, .semigroup, .nonNegativeResponse],
            costClass: .linearR, algorithmClass: .separableFIR,
            signature: "The only blur that is both round and separable; its continuous response fades every detail smoothly and never inverts phase.",
            mathSymbol: "G", glyph: GlyphSpec(.rings, [1, 2, 3]), parameters: [sigma, truncation, discretisation], primary: "sigma",
            deck: .crownPair("sigma"),
            variants: [
                VariantDescriptor(id: Self.direct2D, displayName: "2-D direct", tier: .tier1, algorithmClass: .gather2D,
                                  costClass: .quadraticR, runsOnGPU: true, supportsRenormalise: true),
                VariantDescriptor(id: Self.separable, displayName: "Separable", tier: .tier1, algorithmClass: .separableFIR,
                                  costClass: .linearR, runsOnGPU: true, supportsRenormalise: true),
                VariantDescriptor(id: Self.linearSampled, displayName: "Linear-sampled", tier: .tier1, algorithmClass: .separableFIR,
                                  costClass: .linearR, runsOnGPU: true),
                VariantDescriptor(id: Self.computeTile, displayName: "Compute tile", tier: .tier1, algorithmClass: .separableFIR,
                                  costClass: .linearR, runsOnGPU: true, supportsRenormalise: true,
                                  note: "Blur2ool implementation variant: threadgroup tile + apron (GPU §3.2)"),
            ],
            defaultVariant: Self.linearSampled, defaultSpecimen: "night-city", handles: [],
            appleTwins: [
                AppleTwinSpec(id: "CIGaussianBlur", call: "CIFilter.gaussianBlur(); inputRadius = σ", mapping: "σ = inputRadius",
                              provenance: .measured, source: SourceRef("live-calibration.md §5.2 (MEASURED, macOS 27.2)"), subject: .ciGaussianBlur),
                AppleTwinSpec(id: "MPSImageGaussianBlur", call: "MPSImageGaussianBlur(device:sigma:)", mapping: "σ = sigma",
                              provenance: .measured, source: SourceRef("live-calibration.md §5.3 (MEASURED, macOS 27.2)"), subject: .mpsGaussianBlur),
            ],
            tell: TellSpec(specimen: "siemens-star", text: "Siemens star: no reversed rings, a round grey disc."),
            neighbours: ["box-blur", "binomial-blur", "iterated-box"], traceDepth: .full, heroOrder: 0,
            card: CardRows(psfShape: CardRow("round bell, no rim; excess kurtosis 0", .computed),
                           response: CardRow("continuous e^(−2π²σ²ν²) > 0; as run (k 3) min H −0.0012 at σ 12", .computed),
                           edges: CardRow("erf S-curve, 10–90 % = 2.563 σ, no overshoot", .computed),
                           cost: CardRow("O(r) separable · O(1) via IIR or pyramid", .computed),
                           artifacts: CardRow("square halo on HDR lights if cut at 2σ", .computed),
                           usedIn: CardRow("CSS blur(), CIGaussianBlur, MPS, SIFT, Canny", .reference, source: SourceRef("CATALOG.md §2"))),
            unverified: [], detailReference: "catalog-lsi.md §2–§4", sources: [source, SourceRef("Rákos 2010, Efficient Gaussian blur with linear sampling (RasterGrid)")])
    }

    // MARK: Kernel

    public func sigmaParameter(_ request: OperatorRequest) -> Double { request.parameters.double("sigma") ?? 12 }
    public func truncation(_ request: OperatorRequest) -> Double { Double(request.parameters.choice("truncation") ?? "3") ?? 3 }

    /// The 1-D kernel the GPU receives (Double; uploaded as Float).
    public func kernel(_ request: OperatorRequest) -> Kernel1D {
        let s = sigmaParameter(request), k = truncation(request)
        switch request.parameters.choice("discretisation") ?? "sampled" {
        case "integrated": return KernelMath.gaussianIntegrated(sigma: s, truncation: k)
        case "lindeberg": return KernelMath.gaussianLindeberg(sigma: s, truncation: k)
        default: return KernelMath.gaussianSampled(sigma: s, truncation: k)
        }
    }

    public func resolveVariant(_ request: OperatorRequest) -> VariantResolution {
        let r = kernel(request).origin
        switch request.variant {
        case Self.direct2D where sigmaParameter(request) > 8:
            return VariantResolution(variant: Self.separable, reason: "2-D DIRECT ABOVE σ 8 · USING SEPARABLE")
        case Self.computeTile where r > Self.tileBudgetRadius:
            return VariantResolution(variant: Self.linearSampled, reason: "TILE BUDGET R ≤ \(Self.tileBudgetRadius) · USING LINEAR-SAMPLED")
        case Self.linearSampled where request.settings.edgeMode == .renormalise:
            return VariantResolution(variant: Self.separable, reason: "RENORMALISE NEEDS WHOLE TAPS · USING SEPARABLE")
        default:
            return VariantResolution(variant: request.variant)
        }
    }

    public func disabledReason(_ variant: VariantID, _ request: OperatorRequest) -> String? {
        if variant == Self.direct2D && sigmaParameter(request) > 8 { return "2-D direct: disabled above σ 8 · 2,401 taps per pixel" }
        if variant == Self.computeTile && kernel(request).origin > Self.tileBudgetRadius {
            return "Compute tile: radius above \(Self.tileBudgetRadius) does not fit 16 KB of threadgroup memory"
        }
        return nil
    }

    public func statusWarning(_ request: OperatorRequest) -> String? { resolveVariant(request).reason }

    public func passPlan(_ request: OperatorRequest) -> PassPlan {
        let k = kernel(request), r = k.origin, taps = Double(2 * r + 1)
        let variant = resolveVariant(request).variant
        let name = entry.variant(variant)?.displayName ?? "Separable"
        switch variant {
        case Self.direct2D:
            return PassPlan(algorithmName: name, passes: [PassDescriptor(id: 0, name: "2-D", kind: .fragment, fetchesPerPixel: taps * taps,
                                                                         tapsPerPixel: taps * taps, traceable: true, summary: "one 2-D gather")],
                            supportRadius: r)
        case Self.linearSampled:
            let f = Double(KernelMath.linearSampledTable(k).fetchesPerPass)
            return PassPlan(algorithmName: name, passes: [
                PassDescriptor(id: 0, name: "H", kind: .fragment, fetchesPerPixel: f, tapsPerPixel: taps, traceable: true, summary: "horizontal, bilinear pairs"),
                PassDescriptor(id: 1, name: "V", kind: .fragment, fetchesPerPixel: f, tapsPerPixel: taps, traceable: true, summary: "vertical, bilinear pairs")],
                            supportRadius: r + 1)
        case Self.computeTile:
            let reads = 1 + 2 * Double(r) / 256
            return PassPlan(algorithmName: name, passes: [
                PassDescriptor(id: 0, name: "H", kind: .compute, fetchesPerPixel: reads, tapsPerPixel: taps, traceable: true, summary: "row tile + apron"),
                PassDescriptor(id: 1, name: "V", kind: .compute, fetchesPerPixel: reads, tapsPerPixel: taps, traceable: true, summary: "column tile + apron")],
                            supportRadius: r)
        default:
            return PassPlan(algorithmName: name, passes: [
                PassDescriptor(id: 0, name: "H", kind: .fragment, fetchesPerPixel: taps, tapsPerPixel: taps, traceable: true, summary: "horizontal"),
                PassDescriptor(id: 1, name: "V", kind: .fragment, fetchesPerPixel: taps, tapsPerPixel: taps, traceable: true, summary: "vertical")],
                            supportRadius: r)
        }
    }

    public func psf(at point: PixelPoint, _ request: OperatorRequest, content: OperatorContent?) -> PSF? {
        let k = kernel(request)
        return PSF(kernel: Kernel2D(separable: k, k), isLocal: false, point: nil, provenance: .computed)
    }

    public func response(_ query: ResponseQuery, _ request: OperatorRequest, content: OperatorContent?) -> ResponseCurve? {
        let f = query.frequencies
        if query.continuous {
            let s = sigmaParameter(request)
            return ResponseCurve(kind: .signedTransfer, frequencies: f, values: f.map { KernelMath.gaussianResponse(sigma: s, frequency: $0) })
        }
        return ResponseCurve(kind: .signedTransfer, frequencies: f, values: KernelMath.response(kernel(request), frequencies: f))
    }

    public func continuousProfile(_ request: OperatorRequest) -> ProfileCurve? {
        let s = sigmaParameter(request), r = Double(kernel(request).origin)
        let xs = stride(from: -r, through: r, by: Swift.max(r / 128, 0.05)).map { $0 }
        return ProfileCurve(label: "G(x)", xs: xs, ys: xs.map { exp(-$0 * $0 / (2 * s * s)) / (s * (2 * Double.pi).squareRoot()) })
    }

    public func sigma(_ request: OperatorRequest) -> Double? { kernel(request).sigma }

    public func holdingSigma(_ sigma: Double, current: ParameterValues) -> SigmaHoldResult {
        var p = current
        let rounded = (sigma * 10).rounded() / 10
        let held = Swift.min(Swift.max(rounded, 0.3), 64)
        p["sigma"] = .double(held)
        let clamped = held != rounded
        let converted = [LabeledValue(id: "sigma", label: "σ",
                                      value: .number(held, .decimals(1, unit: "px", spokenUnit: "pixels"), .computed))]
        return SigmaHoldResult(parameters: p, requestedSigma: sigma, achievedSigma: held, isClamped: clamped,
                               statusLine: SigmaHoldResult.standardLine(held: sigma, converted: converted, achieved: held,
                                                                         isClamped: clamped))
    }

    // MARK: CPU reference (Double accumulation; same taps, same edge mapping, same sample positions as the GPU)

    public func reference(_ input: ImageBuffer, _ request: OperatorRequest, auxiliary: AuxiliaryInputs,
                          options: ReferenceOptions) throws -> ReferenceResult {
        let k = kernel(request), edge = request.settings.edgeMode
        let variant = resolveVariant(request).variant
        func store(_ b: ImageBuffer) -> ImageBuffer { options.emulateHalfStorage ? b.roundedToHalf() : b }
        switch variant {
        case Self.linearSampled:
            let table = KernelMath.linearSampledTable(k)
            let h = store(Self.linearPass(input, table: table, horizontal: true, edge: edge, bits: options.subTexelBits, rounding: options.subTexelRounding))
            let v = store(Self.linearPass(h, table: table, horizontal: false, edge: edge, bits: options.subTexelBits,
                                          rounding: options.subTexelRounding))
            return ReferenceResult(output: v, intermediates: [h, v])
        case Self.direct2D:
            let out = store(Self.direct2DPass(input, kernel: k, edge: edge))
            return ReferenceResult(output: out, intermediates: [out])
        default:
            let h = store(Self.integerPass(input, kernel: k, horizontal: true, edge: edge))
            let v = store(Self.integerPass(h, kernel: k, horizontal: false, edge: edge))
            return ReferenceResult(output: v, intermediates: [h, v])
        }
    }

    static func integerPass(_ image: ImageBuffer, kernel k: Kernel1D, horizontal: Bool, edge: EdgeMode) -> ImageBuffer {
        var out = ImageBuffer(width: image.width, height: image.height)
        let n = horizontal ? image.width : image.height
        for y in 0..<image.height {
            for x in 0..<image.width {
                var sum = SIMD4<Double>.zero, used = 0.0
                for i in k.weights.indices {
                    let o = i - k.origin
                    let j = (horizontal ? x : y) + o
                    if edge == .renormalise && (j < 0 || j >= n) { continue }
                    let p = horizontal ? image.fetch(j, y, edge: edge) : image.fetch(x, j, edge: edge)
                    sum += SIMD4<Double>(p) * k.weights[i]
                    used += k.weights[i]
                }
                if edge == .renormalise && used > 0 { sum /= used }
                out[x, y] = SIMD4<Float>(sum)
            }
        }
        return out
    }

    static func linearPass(_ image: ImageBuffer, table: LinearSampledTable, horizontal: Bool, edge: EdgeMode, bits: Int?,
                           rounding: SubTexelRounding = .nearest) -> ImageBuffer {
        var out = ImageBuffer(width: image.width, height: image.height)
        for y in 0..<image.height {
            for x in 0..<image.width {
                let cx = Double(x) + 0.5, cy = Double(y) + 0.5
                var sum = image.bilinear(cx, cy, edge: edge, subTexelBits: bits, rounding: rounding) * table.weights[0]
                for i in 1..<table.offsets.count {
                    let o = table.offsets[i]
                    let a = horizontal ? image.bilinear(cx + o, cy, edge: edge, subTexelBits: bits, rounding: rounding) : image.bilinear(cx, cy + o, edge: edge, subTexelBits: bits, rounding: rounding)
                    let b = horizontal ? image.bilinear(cx - o, cy, edge: edge, subTexelBits: bits, rounding: rounding) : image.bilinear(cx, cy - o, edge: edge, subTexelBits: bits, rounding: rounding)
                    sum += (a + b) * table.weights[i]
                }
                out[x, y] = SIMD4<Float>(sum)
            }
        }
        return out
    }

    static func direct2DPass(_ image: ImageBuffer, kernel k: Kernel1D, edge: EdgeMode) -> ImageBuffer {
        var out = ImageBuffer(width: image.width, height: image.height)
        for y in 0..<image.height {
            for x in 0..<image.width {
                var sum = SIMD4<Double>.zero, used = 0.0
                for j in k.weights.indices {
                    for i in k.weights.indices {
                        let px = x + i - k.origin, py = y + j - k.origin
                        let w = k.weights[i] * k.weights[j]
                        if edge == .renormalise && (px < 0 || py < 0 || px >= image.width || py >= image.height) { continue }
                        sum += SIMD4<Double>(image.fetch(px, py, edge: edge)) * w
                        used += w
                    }
                }
                if edge == .renormalise && used > 0 { sum /= used }
                out[x, y] = SIMD4<Float>(sum)
            }
        }
        return out
    }

    public func traceReconstruction(probe: PixelPoint, input: ImageBuffer, _ request: OperatorRequest,
                                    auxiliary: AuxiliaryInputs) -> TraceRecord {
        // Seed: horizontal pass of the linear-sampled variant only; FAM-F2 completes every variant and pass (SPEC §6.3).
        let k = kernel(request), table = KernelMath.linearSampledTable(k), edge = request.settings.edgeMode
        let c = probe.centre
        var taps: [TraceTap] = []
        var sum = SIMD4<Double>.zero
        var order: [(Double, Double)] = [(0, table.weights[0])]
        for i in 1..<table.offsets.count { order += [(table.offsets[i], table.weights[i]), (-table.offsets[i], table.weights[i])] }
        for (n, (o, w)) in order.enumerated() {
            let v = input.bilinear(c.x + o, c.y, edge: edge)
            sum += v * w
            taps.append(TraceTap(id: n, position: SIMD2(c.x + o, c.y), offset: SIMD2(o, 0), texels: [], requestedFraction: nil,
                                 quantizedFraction: nil, weight: w, fetched: v, contribution: v * w, runningSum: sum))
        }
        let plan = passPlan(request)
        let pass = TracePass(id: 0, descriptor: plan.passes[0], source: .cpuReconstruction, pixel: probe, taps: taps,
                             truncatedTapCount: 0, outputAtProbe: sum, neighbourhoodIn: nil, neighbourhoodOut: nil)
        return TraceRecord(blur: entry.id, variant: request.variant, parameters: request.parameters, settings: request.settings,
                           probe: probe, input: SIMD4<Double>(input[probe.x, probe.y]), passes: [pass], gpuOutput: nil,
                           cpuReference: sum, differenceULP16: nil, tracedEqualsUntraced: nil)
    }

    public func uniqueNumber(_ request: OperatorRequest) -> LabeledValue {
        LabeledValue(id: "unique", label: "UNIQUE",
                     value: .number(0, .decimals(0), .computed,
                                    caption: "KURTOSIS ON AXIS = AT 45° WHILE SEPARABLE (HERSCHEL–MAXWELL)"))
    }

    public func floorKey(_ floor: Floor, _ request: OperatorRequest) -> FloorKey {
        let s = sigmaParameter(request), k = kernel(request)
        switch floor {
        case .slide: return FloorKey(identity: ["sigma"], numbers: [s], tolerance: 0.05, description: "σ \(s)")
        case .api: return FloorKey(identity: [request.settings.colourSpace.rawValue, request.settings.edgeMode.rawValue,
                                              request.settings.alphaMode.rawValue], numbers: [k.sigma, k.sigma], tolerance: 0.03 * k.sigma,
                                   description: "per-axis σ and silent parameters")
        case .math: return FloorKey(identity: ["gaussian"], numbers: [s], tolerance: 1e-9, description: "bell")
        case .kernel: return FloorKey(identity: ["fir"], numbers: k.weights, tolerance: 1e-9, description: "\(k.tapCount) sampled weights")
        case .algorithm: return FloorKey(identity: passPlan(request).passes.map(\.name) + [resolveVariant(request).variant.rawValue],
                                         description: passPlan(request).algorithmName)
        case .gpu: return FloorKey(identity: [resolveVariant(request).variant == Self.linearSampled ? "bilinear" : "integer"],
                                   description: resolveVariant(request).variant == Self.linearSampled ? "bilinear fetches" : "integer fetches")
        case .pixels: return FloorKey(identity: ["pixels"], description: "output pixels")
        }
    }
}
