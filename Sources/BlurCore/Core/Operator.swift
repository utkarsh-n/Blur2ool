import Foundation

// FROZEN — ARCHITECTURE.md §5.5. The behaviour of one catalog entry. Conformers are value types (Sendable), one per
// entry, in Sources/BlurCore/Operators/<Group>/ and listed in that group's `<Group>Catalog.operators`.

/// Everything an operator needs to answer a question about one configuration.
public struct OperatorRequest: Sendable, Codable, Hashable {
    public var parameters: ParameterValues
    public var variant: VariantID
    public var settings: SilentSettings
    /// Size in pixels of the image being rendered: the window (894 × 894 on the 15 Pro Max), or ⌊N·pixelScale⌋ for a
    /// preview (447 × 447 half, 223 × 223 quarter).
    public var size: ImageSize
    /// Render resolution relative to the full window: 1 (full), 0.5 (half preview) or 0.25 (quarter preview). Pixel-unit
    /// parameters in `parameters` are already expressed at this scale (`BlurOperator.previewRequest`, review fix E-4).
    public var pixelScale: Double
    public init(parameters: ParameterValues, variant: VariantID, settings: SilentSettings = .standard, size: ImageSize,
                pixelScale: Double = 1) {
        self.parameters = parameters; self.variant = variant; self.settings = settings; self.size = size
        self.pixelScale = pixelScale
    }
}

public extension PixelPoint {
    /// A full-resolution window pixel mapped into a preview of scale `s` (0.5 → ⌊p/2⌋). Probes and integer handles.
    func previewMapped(_ scale: Double) -> PixelPoint {
        PixelPoint(x: Int((Double(x) * scale).rounded(.down)), y: Int((Double(y) * scale).rounded(.down)))
    }
}

/// The current image (window-sized, linear premultiplied, half-rounded) and auxiliary buffers, for data-dependent answers.
public struct OperatorContent: Sendable, Equatable {
    public var image: ImageBuffer
    public var auxiliary: AuxiliaryInputs
    public init(image: ImageBuffer, auxiliary: AuxiliaryInputs = .none) { self.image = image; self.auxiliary = auxiliary }
}

/// How the hardware turns a bilinear fraction into its fixed-point weight (review fix E-6).
public enum SubTexelRounding: String, Sendable, Codable, Hashable {
    /// Round to the nearest 1/2^bits (MEASURED on the M1 Max, GPU §2.3).
    case nearest
    /// Truncate toward zero.
    case truncate
}

public struct ReferenceOptions: Sendable, Hashable {
    /// Round every intermediate and the output to fp16 exactly as the GPU stores rgba16Float (parity mode).
    public var emulateHalfStorage: Bool
    /// Quantize bilinear fractions like the hardware (8 bits MEASURED on M1 Max only; the Simulator forwards to the Mac
    /// GPU, so it is not independent evidence; This phone measures the A17 Pro). nil = exact fractions.
    public var subTexelBits: Int?
    public var subTexelRounding: SubTexelRounding
    public init(emulateHalfStorage: Bool = true, subTexelBits: Int? = nil, subTexelRounding: SubTexelRounding = .nearest) {
        self.emulateHalfStorage = emulateHalfStorage; self.subTexelBits = subTexelBits; self.subTexelRounding = subTexelRounding
    }
    /// The Mac rule (blur-gpucheck on the M1 Max): 8 bits, round to nearest.
    public static let parity = ReferenceOptions(emulateHalfStorage: true, subTexelBits: 8, subTexelRounding: .nearest)
    public static let exact = ReferenceOptions(emulateHalfStorage: false, subTexelBits: nil)
    /// The rule this device's sub-texel probe MEASURED (`DeviceProbeKind.bilinearSubTexelBits`, numbers "subTexelBits"
    /// and "roundsToNearest" 1/0). nil until the probe has run: in-app parity of bilinear classes is then reportOnly
    /// with the caption `SUB-TEXEL RULE NOT YET MEASURED`.
    public static func forDevice(_ probes: [DeviceProbeResult]) -> ReferenceOptions? {
        guard let probe = probes.last(where: { $0.kind == .bilinearSubTexelBits }),
              let bits = probe.numbers["subTexelBits"] else { return nil }
        let nearest = (probe.numbers["roundsToNearest"] ?? 1) >= 0.5
        return ReferenceOptions(emulateHalfStorage: true, subTexelBits: Int(bits), subTexelRounding: nearest ? .nearest : .truncate)
    }
}

public struct ReferenceResult: Sendable, Equatable {
    /// Full window-sized output, still in the blur's working space (BlurReference applies the post-pass).
    public var output: ImageBuffer
    /// One image per pass of the plan, in order (sizes may differ for pyramid levels); the last equals `output`.
    public var intermediates: [ImageBuffer]
    public init(output: ImageBuffer, intermediates: [ImageBuffer]) { self.output = output; self.intermediates = intermediates }
}

public enum ReferenceError: Error, Sendable, Equatable {
    case unsupportedVariant(VariantID)
    case missingAuxiliary(String)
    case parameterOutOfRange(ParameterKey)
    case notImplemented(String)
}

/// The result of σ-hold (SPEC §8.1).
public struct SigmaHoldResult: Sendable, Codable, Hashable {
    public var parameters: ParameterValues
    /// The σ that was held (px, per axis).
    public var requestedSigma: Double
    /// The σ actually achieved (integer parameters leave a residual; a range limit leaves more), or nil when undefined.
    public var achievedSigma: Double?
    /// True when a parameter hit its range limit, so the achieved σ is not the held σ (review fix P-38).
    public var isClamped: Bool
    /// Status-row line with every number badged: "σ HELD 12.0 px → R 26.3 px", "σ HELD 12.0 px → r 20 (w 41, σ 11.83)",
    /// "σ HELD 12.0 px → σs 8.0 px (MAX) · Δσ −4.0 px", "σ NOT DEFINED · RANK FILTER".
    public var statusLine: BadgedLine
    public init(parameters: ParameterValues, requestedSigma: Double, achievedSigma: Double?, isClamped: Bool = false,
                statusLine: BadgedLine) {
        self.parameters = parameters; self.requestedSigma = requestedSigma; self.achievedSigma = achievedSigma
        self.isClamped = isClamped; self.statusLine = statusLine
    }

    /// The standard line: "σ HELD <σ> px → <label> <value> [(MAX)] [· σ <achieved> px | · Δσ <Δ> px]".
    /// The held σ is an input (no badge); converted values and the achieved σ are COMPUTED.
    public static func standardLine(held: Double, converted: [LabeledValue], achieved: Double?, isClamped: Bool) -> BadgedLine {
        let px = NumberStyle.decimals(1, unit: "px", spokenUnit: "pixels")
        var segments: [BadgedSegment] = [.text("σ HELD"), .value(.input(held, px)), .text("→")]
        for row in converted { segments += [.literal(row.label), .value(row.value)] }
        if isClamped { segments.append(.text("(MAX)")) }
        if let achieved {
            if isClamped {
                segments += [.text("· Δσ"), .value(.number(achieved - held, NumberStyle(precision: .decimals(1), unit: "px", spokenUnit: "pixels",
                                                                                          explicitPlus: true), .computed))]
            } else if abs(achieved - held) >= 0.005 {
                segments += [.text("· σ"), .value(.number(achieved, .decimals(2, unit: "px", spokenUnit: "pixels"), .computed))]
            }
        }
        return BadgedLine(segments)
    }
}

/// The variant that will actually run, and why it differs from the requested one ("2-D DIRECT ABOVE σ 8 · USING SEPARABLE").
public struct VariantResolution: Sendable, Codable, Hashable {
    public var variant: VariantID
    public var reason: String?
    public init(variant: VariantID, reason: String? = nil) { self.variant = variant; self.reason = reason }
}

/// The comparison key of one floor (SPEC §8.4). Two configurations are "same" on a floor when their keys match.
public struct FloorKey: Sendable, Codable, Hashable {
    public var identity: [String]
    public var numbers: [Double]
    /// Absolute tolerance for `numbers` (1e-9 for kernels; display precision for typed values).
    public var tolerance: Double
    /// One line used when this floor is the first difference ("rect vs bell").
    public var description: String
    public init(identity: [String], numbers: [Double] = [], tolerance: Double = 1e-9, description: String) {
        self.identity = identity; self.numbers = numbers; self.tolerance = tolerance; self.description = description
    }
    public func matches(_ other: FloorKey) -> Bool {
        guard identity == other.identity, numbers.count == other.numbers.count else { return false }
        return zip(numbers, other.numbers).allSatisfy { abs($0 - $1) <= Swift.max(tolerance, other.tolerance) }
    }
}

public enum FloorVerdict: String, Sendable, Codable, Hashable {
    case same, approximatelySame, differs, partsWays
    /// Rail glyph in Compare mode (SPEC §4.1.4).
    public var railSymbol: String {
        switch self {
        case .same: "="
        case .approximatelySame: "≈"
        case .differs, .partsWays: "≠"
        }
    }
}

public struct FloorComparison: Sendable, Codable, Hashable {
    public var floor: Floor
    public var verdict: FloorVerdict
    public var reason: String
    public init(floor: Floor, verdict: FloorVerdict, reason: String) { self.floor = floor; self.verdict = verdict; self.reason = reason }
}

/// Live and device facts the floors may show. Built by the app from the newest acknowledged Runs and stored measurements.
public struct LiveFacts: Sendable, Codable, Hashable {
    /// The newest acknowledged Run for the configuration on screen (LIVE probe values, dispatch, shader provenance).
    public var run: Run?
    /// The newest settled timing Run (MEASURED GPU ms), if any.
    public var timedRun: Run?
    /// This phone's device-probe results (sub-texel bits, copy bandwidth, limits …), newest per kind.
    public var deviceProbes: [DeviceProbeResult]
    /// Calibrate results (SwiftUI law, shadows, Core Image twins), newest per subject.
    public var calibrations: [CalibrationResult]
    public init(run: Run? = nil, timedRun: Run? = nil, deviceProbes: [DeviceProbeResult] = [], calibrations: [CalibrationResult] = []) {
        self.run = run; self.timedRun = timedRun; self.deviceProbes = deviceProbes; self.calibrations = calibrations
    }
    public func probe(_ kind: DeviceProbeKind) -> DeviceProbeResult? { deviceProbes.last { $0.kind == kind } }
    public func calibration(_ subject: CalibrationSubject) -> CalibrationResult? { calibrations.last { $0.request.subject == subject } }
}

/// Everything a floor page, a rail chip, a pill or a trace step needs.
public struct FloorContext: Sendable, Equatable {
    public var configuration: RenderConfiguration
    /// Settings › Home tool ("swiftui", "css", "figma" …; ToolConventionProviding ids).
    public var homeToolID: String
    /// Display scale (3 on the 15 Pro Max) for pt ↔ px.
    public var displayScale: Double
    public var live: LiveFacts
    /// The current window image after the pre-pass, for LIVE CPU weight maps (adaptive blurs); nil when not loaded.
    public var content: OperatorContent?
    /// The other configuration in Compare mode.
    public var compareB: RenderConfiguration?
    public init(configuration: RenderConfiguration, homeToolID: String, displayScale: Double, live: LiveFacts,
                content: OperatorContent? = nil, compareB: RenderConfiguration? = nil) {
        self.configuration = configuration; self.homeToolID = homeToolID; self.displayScale = displayScale
        self.live = live; self.content = content; self.compareB = compareB
    }
    public var request: OperatorRequest { configuration.operatorRequest }
    public var probe: PixelPoint { configuration.probe }
}

public protocol BlurOperator: Sendable {
    var entry: CatalogEntry { get }

    /// The passes the (resolved) variant runs, with fetch counts (COMPUTED).
    func passPlan(_ request: OperatorRequest) -> PassPlan

    /// The PSF at a window pixel. LSI: the same everywhere. LSV: local. Adaptive: needs `content` (LIVE · CPU).
    /// nil for rank filters and global operators without a pixel footprint.
    func psf(at point: PixelPoint, _ request: OperatorRequest, content: OperatorContent?) -> PSF?

    /// Signed H(ν) along an axis (LSI), local H at `query.point` (LSV), T(ν, A) (adaptive); nil for rank filters.
    func response(_ query: ResponseQuery, _ request: OperatorRequest, content: OperatorContent?) -> ResponseCurve?

    /// The continuous counterpart for the quiet trace, where one exists.
    func continuousProfile(_ request: OperatorRequest) -> ProfileCurve?

    /// Per-axis second moment σ in px of the discrete PSF, or nil when undefined (rank, space-variant, system materials).
    func sigma(_ request: OperatorRequest) -> Double?

    /// σ-hold conversion (SPEC §8.1): new parameters for this entry that give per-axis σ = `sigma` px.
    func holdingSigma(_ sigma: Double, current: ParameterValues) -> SigmaHoldResult

    /// The CPU reference: the exact algorithm of the resolved variant (same passes, same weights, same edge mapping,
    /// same sample positions), accumulated in Double, on values ALREADY transformed by the colour pre-pass.
    /// It never applies colour-space or alpha transforms: `BlurReference.run` does (ARCHITECTURE §4.2).
    func reference(_ input: ImageBuffer, _ request: OperatorRequest, auxiliary: AuxiliaryInputs,
                   options: ReferenceOptions) throws -> ReferenceResult

    /// The reference output for one region only (in-app parity and blur-gpucheck at 894 on 128 × 128 crops).
    /// Default: full reference, cropped. REQUIRED override (with an apron of `passPlan.supportRadius`) for every entry
    /// whose cost class `isHeavyByDefault`, except global operators (FFT, IIR) (review fix E-8; ARCHITECTURE §5.5).
    func referenceCrop(_ input: ImageBuffer, _ request: OperatorRequest, auxiliary: AuxiliaryInputs,
                       region: PixelRegion, options: ReferenceOptions) throws -> ImageBuffer

    /// A CPU reconstruction of the probe's taps per pass (source `.cpuReconstruction`, COMPUTED). Shown beside GPU
    /// records, and as the trace itself for stages without GPU records.
    func traceReconstruction(probe: PixelPoint, input: ImageBuffer, _ request: OperatorRequest,
                             auxiliary: AuxiliaryInputs) -> TraceRecord

    /// Blur-specific content for one floor; the page builder fills what is left empty with generic content.
    func facts(_ floor: Floor, _ context: FloorContext) -> FloorFacts

    /// The fingerprint card's UNIQUE row (SPEC §7.2).
    func uniqueNumber(_ request: OperatorRequest) -> LabeledValue

    /// The divergence key of one floor (SPEC §8.4).
    func floorKey(_ floor: Floor, _ request: OperatorRequest) -> FloorKey

    /// The variant that will run for this request (automatic fallbacks with their reason).
    func resolveVariant(_ request: OperatorRequest) -> VariantResolution

    /// Why a variant is disabled for this request ("2-D direct: disabled above σ 8 · 2,401 taps per pixel"), or nil.
    func disabledReason(_ variant: VariantID, _ request: OperatorRequest) -> String?

    /// A sampling or budget warning for the status row ("32 SAMPLES · CORNER GAP 4.08 PX · GHOSTS"), or nil.
    func statusWarning(_ request: OperatorRequest) -> String?

    /// True when this request renders a reduced-resolution preview while a control moves (SPEC §4.1.6).
    func isHeavy(_ request: OperatorRequest) -> Bool

    /// The request at preview scale `scale` (0.5 or 0.25), or nil when this operator has no honest preview (it then
    /// renders at full resolution and shows RENDERING…). Default (review fixes E-4, P-36): `px`, `texels` and
    /// position values × scale; integers max(1, round(x·scale)) (0 stays 0 in lists); `px²` (diffusion time) × scale²;
    /// counts, ratios, angles and choices unchanged; nil for selection (rank) filters, system entries and atlas pages.
    func previewRequest(_ request: OperatorRequest, scale: Double) -> OperatorRequest?
}

public extension BlurOperator {
    func continuousProfile(_ request: OperatorRequest) -> ProfileCurve? { nil }
    func facts(_ floor: Floor, _ context: FloorContext) -> FloorFacts { .empty }
    func resolveVariant(_ request: OperatorRequest) -> VariantResolution { VariantResolution(variant: request.variant) }
    func disabledReason(_ variant: VariantID, _ request: OperatorRequest) -> String? { nil }
    func statusWarning(_ request: OperatorRequest) -> String? { nil }
    func isHeavy(_ request: OperatorRequest) -> Bool {
        (entry.variant(resolveVariant(request).variant)?.costClass ?? entry.costClass).isHeavyByDefault
    }
    func previewRequest(_ request: OperatorRequest, scale: Double) -> OperatorRequest? {
        let algorithm = entry.variant(resolveVariant(request).variant)?.algorithmClass ?? entry.algorithmClass
        guard ![.selection, .system, .atlasOnly].contains(algorithm), scale > 0, scale < 1 else { return nil }
        var values = request.parameters
        func scaledInt(_ v: Int, _ factor: Double) -> Int { v == 0 ? 0 : Swift.max(1, Int((Double(v) * factor).rounded())) }
        for spec in entry.parameters where spec.scope == .blur {
            guard let value = values[spec.key] else { continue }
            let factor: Double
            switch spec.unit {
            case .px, .texels: factor = scale
            case .pixelsSquared: factor = scale * scale
            default: factor = 1
            }
            switch value {
            case .point(let x, let y): values[spec.key] = .point(x: x * scale, y: y * scale)
            case .double(let v) where factor != 1: values[spec.key] = .double(v * factor)
            case .int(let v) where factor != 1: values[spec.key] = .int(scaledInt(v, factor))
            case .intList(let list) where factor != 1: values[spec.key] = .intList(list.map { scaledInt($0, factor) })
            default: break
            }
        }
        let side = { (n: Int) in Swift.max(1, Int((Double(n) * scale).rounded(.down))) }
        return OperatorRequest(parameters: values, variant: request.variant, settings: request.settings,
                               size: ImageSize(width: side(request.size.width), height: side(request.size.height)),
                               pixelScale: request.pixelScale * scale)
    }
    /// The preview scale while a control moves (review fix E-7): nil = render at full resolution; 0.5 for heavy entries
    /// or plans above `FetchBudget.preview`; 0.25 when even the half-resolution plan exceeds the preview budget.
    func previewScale(_ request: OperatorRequest) -> Double? {
        let full = passPlan(request).fetchesPerFrame(request.size)
        guard isHeavy(request) || full > FetchBudget.preview, let half = previewRequest(request, scale: 0.5) else { return nil }
        if passPlan(half).fetchesPerFrame(half.size) <= FetchBudget.preview { return 0.5 }
        return previewRequest(request, scale: 0.25) == nil ? 0.5 : 0.25
    }
    func referenceCrop(_ input: ImageBuffer, _ request: OperatorRequest, auxiliary: AuxiliaryInputs,
                       region: PixelRegion, options: ReferenceOptions) throws -> ImageBuffer {
        try reference(input, request, auxiliary: auxiliary, options: options).output.crop(region)
    }
}

/// Runs a reference exactly as the GPU path runs a blur: half-rounded input → exposure 2^EV (the window pass) →
/// colour pre-pass → operator → post-pass. `input` is the window at 0 EV, as the canvas texture holds it (review fix E-10).
public enum BlurReference {
    public static func run(_ op: any BlurOperator, input: ImageBuffer, _ request: OperatorRequest,
                           auxiliary: AuxiliaryInputs = .none, options: ReferenceOptions = .parity,
                           exposureEV: Int = 0) throws -> ReferenceResult {
        var source = options.emulateHalfStorage ? input.roundedToHalf() : input
        if exposureEV != 0 {
            source = source.scaled(by: Float(pow(2.0, Double(exposureEV))))
            if options.emulateHalfStorage { source = source.roundedToHalf() }
        }
        var pre = ColourTransform.pre(source, request.settings)
        if options.emulateHalfStorage && ColourTransform.needsPasses(request.settings) { pre = pre.roundedToHalf() }
        let core = try op.reference(pre, request, auxiliary: auxiliary, options: options)
        var out = ColourTransform.post(core.output, request.settings)
        if options.emulateHalfStorage { out = out.roundedToHalf() }
        return ReferenceResult(output: out, intermediates: core.intermediates)
    }

    /// The same transforms as `run`, but the operator computes only `region` (`referenceCrop`): in-app parity and
    /// blur-gpucheck at 894 (review fix E-8). Per-pixel transforms run on the whole window; they are cheap.
    public static func runCrop(_ op: any BlurOperator, input: ImageBuffer, _ request: OperatorRequest, region: PixelRegion,
                               auxiliary: AuxiliaryInputs = .none, options: ReferenceOptions = .parity,
                               exposureEV: Int = 0) throws -> ImageBuffer {
        var source = options.emulateHalfStorage ? input.roundedToHalf() : input
        if exposureEV != 0 {
            source = source.scaled(by: Float(pow(2.0, Double(exposureEV))))
            if options.emulateHalfStorage { source = source.roundedToHalf() }
        }
        var pre = ColourTransform.pre(source, request.settings)
        if options.emulateHalfStorage && ColourTransform.needsPasses(request.settings) { pre = pre.roundedToHalf() }
        let core = try op.referenceCrop(pre, request, auxiliary: auxiliary, region: region, options: options)
        var out = ColourTransform.post(core, request.settings)
        if options.emulateHalfStorage { out = out.roundedToHalf() }
        return out
    }
}
