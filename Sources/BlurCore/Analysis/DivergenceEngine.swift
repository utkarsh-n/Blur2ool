import Foundation

// OWNER: ANALYSIS. SPEC §8.4 "Where two blurs part ways": compares two configurations floor by floor and names the first
// floor where they differ, with a one-line reason in which every number is badged (review fix E-51). Keys are computed
// from data (operators, plans, PSFs, tool conventions), never hand-labelled per pair.
//
//   1 SLIDE      the typed value in the home tool's convention, equal at display precision. Either blur not offered by
//                the home tool → `≠ · NOT IN <TOOL>`, skipped when naming the first difference.
//   2 API        the API tuple normalised to per-axis σ (equal within 3 %, the σ-hold residual) plus colour space, edges
//                and alpha. Blurs without a σ compare their primary in its own unit (same blur); for two different blurs
//                an undefined σ is not a difference here (their operators differ at MATH).
//   3 MATH       the continuous operator id and its parameters (`floorKey(.math)`).
//   4 KERNEL     the effective discrete 2-D PSF, equal within 10⁻⁹ (linear classes); for NL classes the weight rule
//                (`floorKey(.kernel)`).
//   5 ALGORITHM  the pass graph: algorithm class, pass count and per-pass structure (names, logical taps, output scale).
//   6 GPU        how the passes run: pass kinds, fetches per pass, the fetch pattern (`floorKey(.gpu)`) and the
//                precision settings (accumulator, intermediate format, SAT centring).
//   7 PIXEL      max |A − B| ≤ 1 fp16 ulp → `≈ same`; otherwise `differs` with the max in 8-bit steps.

public struct DivergenceEngine: DivergenceComputing {
    public typealias OperatorLookup = @Sendable (BlurID) -> (any BlurOperator)?

    /// Floor 2: per-axis σ equal within 3 % (the σ-hold residual).
    public static let sigmaRelativeTolerance = 0.03
    /// Floor 4: effective discrete PSFs equal within 10⁻⁹.
    public static let kernelTolerance = 1e-9
    /// Floor 7: max |A − B| ≤ 1 fp16 ulp → `≈ same`.
    public static let pixelULPTolerance = 1.0
    /// Settings › Home tool default (SPEC §4.1.4: SwiftUI points).
    public static let defaultHomeToolID = "swiftui"

    private let lookup: OperatorLookup
    private let toolProvider: (any ToolConventionProviding)?

    /// The app's engine: operators from `BlurRegistry`, tool conventions from `BlurServices.tools`.
    public init() {
        lookup = { BlurRegistry.op($0) }
        toolProvider = nil
    }

    /// An engine over another operator set or tool convention provider (tests, lessons over a subset).
    public init(lookup: @escaping OperatorLookup, tools: (any ToolConventionProviding)? = nil) {
        self.lookup = lookup
        toolProvider = tools
    }

    public init(operators: [any BlurOperator], tools: (any ToolConventionProviding)? = nil) {
        let table = Dictionary(operators.map { ($0.entry.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.init(lookup: { table[$0] }, tools: tools)
    }

    private var tools: any ToolConventionProviding { toolProvider ?? BlurServices.tools }

    // MARK: Public types

    /// One floor of the comparison, with its reason as a badged line for views and VoiceOver.
    public struct Row: Sendable, Hashable {
        public var comparison: FloorComparison
        /// The reason with every number a `BadgedValue` (render this; `comparison.reason` is its plain text or caption).
        public var line: BadgedLine
        /// Floor 1 when either blur is not offered by the home tool, or when the tool's mapping is unknown for two
        /// different blurs: shown as `≠` but skipped when naming the first difference (SPEC §8.4).
        public var isSkippedForFirstDifference: Bool
        public var floor: Floor { comparison.floor }
        public var verdict: FloorVerdict { comparison.verdict }
    }

    /// Pixel evidence for floor 7: A − B over the compared region.
    public struct PixelEvidence: Sendable, Hashable {
        public var stats: DifferenceStats
        /// LIVE for two renders on this phone (Compare's Difference view); MEASURED, with `device`, when B is the CPU
        /// reference (parity).
        public var provenance: Provenance
        public var device: DeviceStamp?
        public init(stats: DifferenceStats, provenance: Provenance = .live, device: DeviceStamp? = nil) {
            self.stats = stats; self.provenance = provenance; self.device = device
        }
    }

    // MARK: DivergenceComputing

    /// Seven rows, one per floor; the first `.differs` (skipping a floor 1 `NOT IN <TOOL>`) is `.partsWays`. Floor 7
    /// has no pixels here: it is `.same` for pixel-identical configurations and otherwise a prediction from the kernels,
    /// worded "not yet compared" (pass `pixels` to `rows` for the measured rule). Empty when either blur is not registered.
    public func compare(_ a: RenderConfiguration, _ b: RenderConfiguration, homeToolID: String, displayScale: Double) -> [FloorComparison] {
        rows(a, b, homeToolID: homeToolID, displayScale: displayScale).map(\.comparison)
    }

    /// The same seven comparisons with the floor 7 pixel rule applied to `pixels`.
    public func compare(_ a: RenderConfiguration, _ b: RenderConfiguration, homeToolID: String, displayScale: Double,
                        pixels: PixelEvidence?) -> [FloorComparison] {
        rows(a, b, homeToolID: homeToolID, displayScale: displayScale, pixels: pixels).map(\.comparison)
    }

    /// The seven rows with badged reasons. `measuredLaw` is this phone's SwiftUI law (Calibrate), if any.
    public func rows(_ a: RenderConfiguration, _ b: RenderConfiguration, homeToolID: String, displayScale: Double,
                     measuredLaw: CalibrationLaw? = nil, pixels: PixelEvidence? = nil) -> [Row] {
        guard let opA = lookup(a.blur), let opB = lookup(b.blur) else { return [] }
        let A = Side(a, opA), B = Side(b, opB)
        var rows = [slideRow(A, B, homeToolID: homeToolID, displayScale: displayScale, measuredLaw: measuredLaw),
                    apiRow(A, B), mathRow(A, B), kernelRow(A, B), algorithmRow(A, B), gpuRow(A, B), pixelRow(A, B, pixels)]
        if let i = rows.firstIndex(where: { $0.verdict == .differs && !$0.isSkippedForFirstDifference }) {
            rows[i].comparison.verdict = .partsWays
        }
        return rows
    }

    /// The first floor where the two part ways, if any.
    public static func firstDifference(_ comparisons: [FloorComparison]) -> FloorComparison? {
        comparisons.first { $0.verdict == .partsWays }
    }

    /// Compare's status-row line: `PARTS WAYS AT MATH`, or `SAME AT EVERY FLOOR` / `SAME UP TO THE PIXELS`.
    public static func statusLine(_ comparisons: [FloorComparison]) -> BadgedLine {
        if let first = firstDifference(comparisons) {
            return BadgedLine([.text("PARTS WAYS AT"), .literal(first.floor.tileLabel)])
        }
        if comparisons.contains(where: { $0.verdict == .approximatelySame }) { return .words("SAME UP TO THE LAST BITS") }
        return comparisons.isEmpty ? .words("NOT COMPARABLE") : .words("SAME AT EVERY FLOOR")
    }

    // MARK: σ-held neighbours (fingerprint card PARTS WAYS, Catalog › Divergence)

    /// `blur` configured to stand beside `a` (SPEC §8.1): σ held at A's per-axis σ when A has one, otherwise the
    /// entry's defaults; same settings, test image, pan, probe and window. nil when `blur` is not registered.
    public func heldConfiguration(_ blur: BlurID, matching a: RenderConfiguration, variant: VariantID? = nil) -> RenderConfiguration? {
        guard let op = lookup(blur) else { return nil }
        let entry = op.entry
        var parameters = entry.defaultParameters
        if let opA = lookup(a.blur), let sigma = opA.sigma(a.operatorRequest), sigma.isFinite, sigma > 0 {
            parameters = op.holdingSigma(sigma, current: parameters).parameters
        }
        return RenderConfiguration(blur: blur, variant: variant ?? entry.defaultVariant, parameters: parameters, settings: a.settings,
                                   specimen: a.specimen, specimenOptions: a.specimenOptions, pan: a.pan, probe: a.probe,
                                   windowSize: a.windowSize)
    }

    /// For each registered neighbour, the floor where it first parts ways with `a` at held σ (SPEC §7.1 item 9).
    /// Neighbours that are not registered, or that never part ways, are absent.
    public func partsWays(from a: RenderConfiguration, to neighbours: [BlurID], homeToolID: String,
                          displayScale: Double) -> [BlurID: FloorComparison] {
        var result: [BlurID: FloorComparison] = [:]
        for id in neighbours where id != a.blur {
            guard let b = heldConfiguration(id, matching: a),
                  let first = Self.firstDifference(compare(a, b, homeToolID: homeToolID, displayScale: displayScale)) else { continue }
            result[id] = first
        }
        return result
    }

    /// The card's PARTS WAYS line, in `order`: "Box blur at MATH · Tent blur at MATH · IIR Gaussian at KERNEL".
    public func partsWaysLine(_ map: [BlurID: FloorComparison], order: [BlurID]) -> BadgedLine {
        var segments: [BadgedSegment] = []
        for id in order {
            guard let floor = map[id]?.floor else { continue }
            if !segments.isEmpty { segments.append(.text("·")) }
            segments += [.literal(lookup(id)?.entry.displayName ?? id.rawValue), .text("at"), .literal(floor.tileLabel)]
        }
        return BadgedLine(segments)
    }

    // MARK: MIN H (Compare's distinguishing number; SPEC §8.3 Line-up, from the kernels each slot runs)

    /// The minimum of the signed response H(ν) on 0…0.5 c/px of the kernel this configuration runs (COMPUTED from the
    /// discrete taps; local at the probe for LSV blurs). Words for rank filters (`N/A · RANK`) and for entries without
    /// an image-independent response.
    public func minimumResponse(_ configuration: RenderConfiguration) -> BadgedValue {
        guard let op = lookup(configuration.blur) else { return .words("NOT IN THIS BUILD", spoken: "not available in this build") }
        let entry = op.entry
        let request = configuration.operatorRequest
        let algorithm = entry.variant(op.resolveVariant(request).variant)?.algorithmClass ?? entry.algorithmClass
        let lsv = entry.linearity == .lsv
        let query = ResponseQuery(samples: 2049, point: lsv ? configuration.probe : nil)
        guard let curve = op.response(query, request, content: nil) else {
            if algorithm == .selection || entry.verdict == .rankFilter { return .words("N/A · RANK", spoken: "not applicable, rank filter") }
            return .words("N/A", spoken: "not available without an image")
        }
        let marginal = Self.isLinearClass(entry.linearity) && entry.linearity != .lsv
            ? op.psf(at: configuration.probe, request, content: nil)?.kernel.marginalX : nil
        guard let minimum = AnalysisMath.minimum(of: curve, refineWith: marginal) else { return .words("N/A", spoken: "not available") }
        let qualifiers: Qualifiers = curve.provenance == .live ? .cpu : []
        return .number(minimum.value, Self.minimumStyle(minimum.value), curve.provenance, qualifiers: qualifiers)
    }

    /// `MIN H  A −0.217 · B 0 · C −0.0012 · D −0.132` for the slots on screen, in slot order.
    public func minimumResponseLine(_ slots: [(slot: RunSlot, configuration: RenderConfiguration)]) -> BadgedLine {
        var segments: [BadgedSegment] = [.text("MIN H")]
        for (i, item) in slots.enumerated() {
            if i > 0 { segments.append(.text("·")) }
            segments += [.literal(item.slot.rawValue.uppercased()), .value(minimumResponse(item.configuration))]
        }
        return BadgedLine(segments)
    }

    /// Display precision of a minimum of H: 3 decimals (−0.217), 4 below 0.01 (−0.0012), and 0 when it rounds to zero
    /// at 4 decimals (tent: H = sinc² ≥ 0).
    public static func minimumStyle(_ value: Double) -> NumberStyle {
        let magnitude = abs(value)
        if magnitude < 0.00005 { return .decimals(0) }
        return magnitude < 0.01 ? .decimals(4) : .decimals(3)
    }

    // MARK: - Floors

    /// Everything one side of the comparison needs, computed once.
    private struct Side {
        let configuration: RenderConfiguration
        let op: any BlurOperator
        let entry: CatalogEntry
        let request: OperatorRequest
        let resolved: VariantID
        let algorithmClass: AlgorithmClass
        let plan: PassPlan
        let sigma: Double?
        /// The effective discrete PSF at the probe, for linear classes only (adaptive PSFs need the image).
        let psf: PSF?

        init(_ configuration: RenderConfiguration, _ op: any BlurOperator) {
            self.configuration = configuration
            self.op = op
            entry = op.entry
            request = configuration.operatorRequest
            resolved = op.resolveVariant(request).variant
            algorithmClass = entry.variant(resolved)?.algorithmClass ?? entry.algorithmClass
            plan = op.passPlan(request)
            let s = op.sigma(request)
            sigma = s.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            psf = DivergenceEngine.isLinearClass(entry.linearity) ? op.psf(at: configuration.probe, request, content: nil) : nil
        }

        var name: String { entry.displayName }
        func key(_ floor: Floor) -> FloorKey { op.floorKey(floor, request) }

        /// Per-axis σ for entries that define one (`sigma(_:)` non-nil): the PSF's x and y marginals when the PSF is known
        /// (anisotropic kernels differ per axis), else the operator's σ on both axes. nil means "σ NOT DEFINED" (rank,
        /// space-variant, system), even when a local PSF exists.
        var axisSigmas: (x: Double, y: Double)? {
            guard sigma != nil else { return nil }
            if let k = psf?.kernel, let s = AnalysisMath.axisSigmas(k), s.x > 0 || s.y > 0 { return s }
            return sigma.map { ($0, $0) }
        }

        /// The σ handed to the home tool's convention: the API's own σ when the primary parameter is σ in px (a tool's
        /// "σ = value" means the continuous σ the parameter names, not the truncated kernel's moment), otherwise the
        /// per-axis σ; σ-less entries pass their primary value.
        var slideSigma: Double {
            if let spec = entry.primarySpec, spec.key == "sigma", spec.unit == .px, let v = request.parameters.double(spec.key) { return v }
            if let sigma { return sigma }
            if let key = entry.primarySpec?.key, let v = request.parameters.double(key) { return v }
            return 0
        }

        /// `slideSigma` badged: the API's σ is an input (no badge); a kernel's second moment is COMPUTED; nil without a σ.
        var slideSigmaValue: BadgedValue? {
            if let spec = entry.primarySpec, spec.key == "sigma", spec.unit == .px, let v = request.parameters.double(spec.key) {
                return .input(v, spec.numberStyle)
            }
            return sigma.map { .number($0, AnalysisMath.px2, .computed) }
        }

        var primaryValue: ParameterValue? { entry.primarySpec.flatMap { request.parameters[$0.key] } }

        var totalTaps: Double { plan.passes.reduce(0) { $0 + $1.tapsPerPixel * $1.outputScale * $1.outputScale } }

        var usesSAT: Bool {
            resolved.rawValue.lowercased().contains("sat")
                || plan.passes.contains { let n = $0.name.uppercased(); return n.contains("SAT") || n.contains("SCAN") }
        }
    }

    static func isLinearClass(_ c: LinearityClass) -> Bool { c == .lsi || c == .lsv || c == .expectation }

    private static let sigmaStyle = AnalysisMath.px2
    private static let passNoun = CountNoun("pass", "passes")
    private static let tapNoun = CountNoun("tap", "taps")

    private static func row(_ floor: Floor, _ verdict: FloorVerdict, _ line: BadgedLine, reason: String? = nil,
                            skipped: Bool = false) -> Row {
        Row(comparison: FloorComparison(floor: floor, verdict: verdict, reason: reason ?? line.text), line: line,
            isSkippedForFirstDifference: skipped)
    }

    private static func computed(_ value: Double, _ style: NumberStyle) -> BadgedValue { .number(value, style, .computed) }

    // MARK: Floor 1 · SLIDE

    /// Display name of a home tool ("SwiftUI"), from the convention provider or a short fallback list.
    func toolName(_ id: String) -> String {
        if let name = tools.all.first(where: { $0.id == id })?.toolName { return name }
        let known = ["swiftui": "SwiftUI", "css": "CSS", "figma": "Figma", "sketch": "Sketch", "photoshop": "Photoshop",
                     "aftereffects": "After Effects", "coreimage": "Core Image", "mps": "MPS", "android": "Android",
                     "flutter": "Flutter", "gimp": "GIMP", "opencv": "OpenCV", "imagemagick": "ImageMagick", "unity": "Unity",
                     "unreal": "Unreal"]
        return known[id.lowercased()] ?? id
    }

    /// A tool convention's way of saying "this tool has no such blur" (the SLIDE chip's `—`).
    public static func isNotOffered(_ value: BadgedValue) -> Bool {
        guard value.value == nil, !value.qualifiers.contains(.unverified) else { return false }
        let text = value.text.trimmingCharacters(in: .whitespaces)
        return text == "—" || text == "-" || text.uppercased().contains("NOT OFFERED") || text.uppercased().hasPrefix("NOT IN")
            || value.spoken.lowercased().contains("not offered")
    }

    private func slideRow(_ A: Side, _ B: Side, homeToolID: String, displayScale: Double, measuredLaw: CalibrationLaw?) -> Row {
        let provider = tools
        let tool = toolName(homeToolID)
        let tA = provider.typedValue(toolID: homeToolID, blur: A.configuration.blur, sigmaPx: A.slideSigma,
                                     displayScale: displayScale, measuredLaw: measuredLaw)
        let tB = provider.typedValue(toolID: homeToolID, blur: B.configuration.blur, sigmaPx: B.slideSigma,
                                     displayScale: displayScale, measuredLaw: measuredLaw)
        let caption = "NOT IN " + tool.uppercased()
        let absentA = Self.isNotOffered(tA), absentB = Self.isNotOffered(tB)
        if absentA || absentB {
            var segments: [BadgedSegment] = [.text("NOT IN"), .literal(tool.uppercased()), .text("·")]
            switch (absentA, absentB) {
            case (true, true): segments += [.text("neither blur is offered")]
            case (true, false): segments += [.literal(A.name), .text("is not offered")]
            default: segments += [.literal(B.name), .text("is not offered")]
            }
            return Self.row(.slide, .differs, BadgedLine(segments), reason: caption, skipped: true)
        }
        if tA.value != nil && tB.value != nil {
            if tA.textWithUnit == tB.textWithUnit {
                return Self.row(.slide, .same, BadgedLine([.literal(tool), .value(tA), .text("for both")]))
            }
            return Self.row(.slide, .differs, BadgedLine([.literal(tool), .value(tA), .text("vs"), .value(tB)]))
        }
        // The tool's mapping is UNVERIFIED for at least one side. For one blur, its typed value is a function of the
        // blur's own inputs, so equal inputs type equally and different σ type differently; for two blurs it is unknown.
        let unverified: [BadgedSegment] = [.text("·"), .literal(tool), .text("mapping unverified")]
        guard A.configuration.blur == B.configuration.blur else {
            return Self.row(.slide, .differs, BadgedLine([.text("UNVERIFIED IN"), .literal(tool.uppercased())]),
                            reason: "UNVERIFIED IN " + tool.uppercased(), skipped: true)
        }
        let same = A.key(.slide).matches(B.key(.slide))
        let values: [BadgedSegment]
        if let sa = A.slideSigmaValue, let sb = B.slideSigmaValue {
            values = same ? [.text("σ"), .value(sa), .text("for both")] : [.text("σ"), .value(sa), .text("vs"), .value(sb)]
        } else {
            values = same ? [.text("same"), .literal(A.key(.slide).description)]
                : [.literal(A.key(.slide).description), .text("vs"), .literal(B.key(.slide).description)]
        }
        return Self.row(.slide, same ? .same : .differs, BadgedLine(values + unverified))
    }

    // MARK: Floor 2 · API

    private static func colourWords(_ c: ColourSpace) -> String { c == .linearLight ? "LINEAR LIGHT" : "sRGB-ENCODED" }
    private static func alphaWords(_ a: AlphaMode) -> String { a == .premultiplied ? "PREMULTIPLIED" : "STRAIGHT ALPHA" }
    private static func edgeWords(_ e: EdgeMode) -> String { e.rawValue.uppercased() + " EDGES" }

    private static func relativeDifference(_ p: Double, _ q: Double) -> Double {
        let m = Swift.max(abs(p), abs(q))
        return m == 0 ? 0 : abs(p - q) / m
    }

    private func apiRow(_ A: Side, _ B: Side) -> Row {
        let sa = A.request.settings, sb = B.request.settings
        var silent: [BadgedSegment] = []
        if sa.colourSpace != sb.colourSpace { silent += [.text(Self.colourWords(sa.colourSpace) + " vs " + Self.colourWords(sb.colourSpace))] }
        if sa.edgeMode != sb.edgeMode { silent += [.text(Self.edgeWords(sa.edgeMode) + " vs " + Self.edgeWords(sb.edgeMode))] }
        if sa.alphaMode != sb.alphaMode { silent += [.text(Self.alphaWords(sa.alphaMode) + " vs " + Self.alphaWords(sb.alphaMode))] }

        var sizeSame = true
        var size: [BadgedSegment] = []
        if let xa = A.axisSigmas, let xb = B.axisSigmas {
            sizeSame = Self.relativeDifference(xa.x, xb.x) <= Self.sigmaRelativeTolerance
                && Self.relativeDifference(xa.y, xb.y) <= Self.sigmaRelativeTolerance
            let isotropic = abs(xa.x - xa.y) < 0.005 && abs(xb.x - xb.y) < 0.005
            func sigmas(_ s: (x: Double, y: Double)) -> [BadgedSegment] {
                isotropic ? [.value(Self.computed(s.x, Self.sigmaStyle))]
                    : [.text("x"), .value(Self.computed(s.x, Self.sigmaStyle)), .text("y"), .value(Self.computed(s.y, Self.sigmaStyle))]
            }
            size = [.text("σ")] + sigmas(xa) + (sizeSame ? [.text("≈")] : [.text("vs")]) + sigmas(xb)
            if sizeSame { size += [.text("within three percent")] }
        } else if A.configuration.blur == B.configuration.blur, let spec = A.entry.primarySpec {
            let va = A.primaryValue, vb = B.primaryValue
            sizeSame = Self.displayEqual(spec, va, vb)
            let label: [BadgedSegment] = [.literal(spec.label)]
            size = label + Self.primarySegments(spec, va) + (sizeSame ? [.text("for both")] : [.text("vs")] + Self.primarySegments(spec, vb))
        } else {
            let missing = [A, B].filter { $0.axisSigmas == nil }.map(\.name)
            size = [.text("σ NOT DEFINED ·")] + missing.enumerated().flatMap { i, n -> [BadgedSegment] in
                (i > 0 ? [.text("and")] : []) + [.literal(n)]
            }
        }
        let same = sizeSame && silent.isEmpty
        var segments: [BadgedSegment]
        if same {
            segments = size + [.text("· " + Self.colourWords(sa.colourSpace) + " · " + Self.edgeWords(sa.edgeMode) + " · "
                                     + Self.alphaWords(sa.alphaMode))]
        } else {
            let parts = (sizeSame ? [] : [size]) + silent.map { [$0] }
            segments = Array(parts.enumerated().map { i, p in (i > 0 ? [BadgedSegment.text("·")] : []) + p }.joined())
        }
        return Self.row(.api, same ? .same : .differs, BadgedLine(segments))
    }

    private static func displayEqual(_ spec: ParameterSpec, _ a: ParameterValue?, _ b: ParameterValue?) -> Bool {
        switch (a, b) {
        case (.double(let x)?, .double(let y)?): spec.numberStyle.text(x) == spec.numberStyle.text(y)
        case (.int(let x)?, .int(let y)?): x == y
        case (.double(let x)?, .int(let y)?), (.int(let y)?, .double(let x)?): spec.numberStyle.text(x) == spec.numberStyle.text(Double(y))
        default: a == b
        }
    }

    /// The primary value as the user set it (an input: no badge).
    private static func primarySegments(_ spec: ParameterSpec, _ v: ParameterValue?) -> [BadgedSegment] {
        switch v {
        case .double(let x)?: [.value(.input(x, spec.numberStyle))]
        case .int(let x)?: [.value(.input(Double(x), spec.numberStyle))]
        case .choice(let c)?: [.literal(c)]
        case .bool(let b)?: [.text(b ? "on" : "off")]
        case .intList(let list)?: [.literal(list.map(String.init).joined(separator: " "))]
        case .point(let x, let y)?: [.literal("(\(Int(x.rounded())), \(Int(y.rounded())))")]
        case nil: [.text("unset")]
        }
    }

    // MARK: Floor 3 · MATH

    /// Words for a key, with its numbers badged when two keys share a description ("bell · σ 4 vs 12").
    private static func keyDifference(_ ka: FloorKey, _ kb: FloorKey) -> [BadgedSegment] {
        if ka.description != kb.description || ka.identity != kb.identity {
            return [.literal(ka.description), .text("vs"), .literal(kb.description)]
        }
        let style = NumberStyle.significant(3)
        if let i = zip(ka.numbers, kb.numbers).enumerated().first(where: { abs($0.element.0 - $0.element.1) > Swift.max(ka.tolerance, kb.tolerance) })?.offset {
            return [.literal(ka.description), .text("·"), .value(computed(ka.numbers[i], style)), .text("vs"),
                    .value(computed(kb.numbers[i], style))]
        }
        return [.literal(ka.description), .text("· parameter counts differ")]
    }

    /// Two different blurs held at one σ name the same continuous operator when their keys agree within the key's own
    /// tolerance or within the σ-hold residual (3 %, as floor 2): a heat equation held at the Gaussian's σ is "Gaussian,
    /// σ = √(2t)" although t moves in whole λ steps (SPEC §8.4 row 3).
    static func matchesWithinHoldResidual(_ a: FloorKey, _ b: FloorKey) -> Bool {
        guard a.identity == b.identity, a.numbers.count == b.numbers.count else { return false }
        return zip(a.numbers, b.numbers).allSatisfy {
            abs($0 - $1) <= Swift.max(a.tolerance, b.tolerance) || relativeDifference($0, $1) <= sigmaRelativeTolerance
        }
    }

    private func mathRow(_ A: Side, _ B: Side) -> Row {
        let ka = A.key(.math), kb = B.key(.math)
        if ka.matches(kb) { return Self.row(.math, .same, BadgedLine([.literal(ka.description), .text("for both")])) }
        if A.configuration.blur != B.configuration.blur && Self.matchesWithinHoldResidual(ka, kb) {
            return Self.row(.math, .same, BadgedLine([.literal(ka.description), .text("for both · parameters within the σ-hold residual")]))
        }
        return Self.row(.math, .differs, BadgedLine(Self.keyDifference(ka, kb)))
    }

    // MARK: Floor 4 · KERNEL

    private func kernelRow(_ A: Side, _ B: Side) -> Row {
        let ka = A.key(.kernel), kb = B.key(.kernel)
        if let pa = A.psf?.kernel, let pb = B.psf?.kernel {
            let d = AnalysisMath.maxDifference(pa, pb)
            if d <= Self.kernelTolerance {
                return Self.row(.kernel, .same, BadgedLine([.text("same"), .literal("\(pa.width)×\(pa.height)"),
                                                            .text("PSF ·"), .literal(ka.description)]))
            }
            var segments: [BadgedSegment] = [.text("max |ΔPSF|"), .value(Self.computed(d, .significant(2)))]
            if ka.description != kb.description { segments += [.text("·"), .literal(ka.description), .text("vs"), .literal(kb.description)] }
            else { segments += [.text("·"), .literal("\(pa.width)×\(pa.height)"), .text("vs"), .literal("\(pb.width)×\(pb.height)")] }
            return Self.row(.kernel, .differs, BadgedLine(segments))
        }
        if ka.matches(kb) { return Self.row(.kernel, .same, BadgedLine([.text("same weight rule ·"), .literal(ka.description)])) }
        return Self.row(.kernel, .differs, BadgedLine(Self.keyDifference(ka, kb)))
    }

    // MARK: Floor 5 · ALGORITHM

    private struct PassShape: Equatable {
        var name: String
        var taps: Double
        var scale: Double
        static func == (l: PassShape, r: PassShape) -> Bool {
            l.name == r.name && abs(l.taps - r.taps) < 1e-6 && abs(l.scale - r.scale) < 1e-9
        }
    }

    private static func classWords(_ c: AlgorithmClass) -> String {
        switch c {
        case .separableFIR: "separable FIR"
        case .gather2D: "2-D gather"
        case .skewSeparable: "skew-separable"
        case .recursive: "recursive"
        case .runningSum: "running sum"
        case .sparseIterated: "sparse iterated"
        case .spaceVariantGather: "space-variant gather"
        case .adaptiveWeighted: "adaptive weights"
        case .selection: "selection"
        case .iterativePDE: "iterated PDE"
        case .globalFFT: "global FFT"
        case .stochastic: "stochastic"
        case .temporal: "temporal"
        case .system: "system"
        case .derived: "derived"
        case .atlasOnly: "atlas only"
        }
    }

    private static func passSummary(_ s: Side) -> [BadgedSegment] {
        let count = Double(s.plan.passes.count)
        return [.value(computed(count, .integer(noun: passNoun))), .text("·"),
                .value(computed(s.totalTaps.rounded(), .integer(noun: tapNoun)))]
    }

    private func algorithmRow(_ A: Side, _ B: Side) -> Row {
        let shapeA = A.plan.passes.map { PassShape(name: $0.name, taps: $0.tapsPerPixel, scale: $0.outputScale) }
        let shapeB = B.plan.passes.map { PassShape(name: $0.name, taps: $0.tapsPerPixel, scale: $0.outputScale) }
        if A.algorithmClass == B.algorithmClass && shapeA == shapeB {
            return Self.row(.algorithm, .same, BadgedLine(Self.passSummary(A) + [.text("·"), .literal(Self.classWords(A.algorithmClass)),
                                                                                .text("for both")]))
        }
        var segments: [BadgedSegment]
        if shapeA.count != shapeB.count || zip(shapeA, shapeB).contains(where: { $0.name != $1.name || abs($0.scale - $1.scale) > 1e-9 }) {
            let names = { (s: Side) in s.plan.passes.map(\.name).joined(separator: ", ") }
            segments = Self.passSummary(A) + [.literal("(" + names(A) + ")"), .text("vs")] + Self.passSummary(B) + [.literal("(" + names(B) + ")")]
        } else if shapeA != shapeB {
            let tapsA = A.plan.passes.first?.tapsPerPixel ?? 0, tapsB = B.plan.passes.first?.tapsPerPixel ?? 0
            segments = [.value(Self.computed(tapsA, Self.fetchStyle(tapsA))), .text("vs"),
                        .value(Self.computed(tapsB, AnalysisMath.countStyle(tapsB, noun: Self.tapNoun))), .text("per pass")]
        } else {
            segments = [.literal(Self.classWords(A.algorithmClass)), .text("vs"), .literal(Self.classWords(B.algorithmClass))]
        }
        return Self.row(.algorithm, .differs, BadgedLine(segments))
    }

    // MARK: Floor 6 · GPU

    private static func fetchWord(_ key: FloorKey) -> String { key.identity.first ?? key.description }
    /// Whole fetch counts as integers ("25"), fractional ones (a compute tile's 1.09 texture reads) with two decimals.
    private static func fetchStyle(_ v: Double) -> NumberStyle { abs(v - v.rounded()) < 1e-9 ? .integer() : .decimals(2) }

    private func gpuRow(_ A: Side, _ B: Side) -> Row {
        let ka = A.key(.gpu), kb = B.key(.gpu)
        let fa = A.plan.passes.map(\.fetchesPerPixel), fb = B.plan.passes.map(\.fetchesPerPixel)
        let kindsA = A.plan.passes.map(\.kind), kindsB = B.plan.passes.map(\.kind)
        let fetchesSame = fa.count == fb.count && zip(fa, fb).allSatisfy { abs($0 - $1) < 1e-6 }
        let sa = A.request.settings, sb = B.request.settings
        let satRelevant = A.usesSAT || B.usesSAT
        var differences: [[BadgedSegment]] = []
        if !fetchesSame {
            let uniformA = Set(fa.map { ($0 * 1e6).rounded() }).count == 1, uniformB = Set(fb.map { ($0 * 1e6).rounded() }).count == 1
            let perPass = uniformA && uniformB && !fa.isEmpty && !fb.isEmpty
            let va = perPass ? fa[0] : A.plan.fetchesPerPixel, vb = perPass ? fb[0] : B.plan.fetchesPerPixel
            differences.append([.value(Self.computed(va, Self.fetchStyle(va))), .literal(Self.fetchWord(ka)), .text("vs"),
                                .value(Self.computed(vb, Self.fetchStyle(vb))), .literal(Self.fetchWord(kb)),
                                .text(perPass ? "fetches per pass" : "fetches per pixel")])
        } else if !ka.matches(kb) {
            differences.append([.literal(ka.description), .text("vs"), .literal(kb.description)])
        }
        // The kinds of pass used (fragment, compute, blit, FFT …); how many passes there are is floor 5's business.
        if Set(kindsA) != Set(kindsB) {
            let words = { (k: [PassKind]) in Array(Set(k.map(\.rawValue))).sorted().joined(separator: " + ") }
            differences.append([.literal(words(kindsA)), .text("vs"), .literal(words(kindsB)), .text("passes")])
        }
        if sa.accumulator != sb.accumulator {
            differences.append([.literal(sa.accumulator.rawValue), .text("vs"), .literal(sb.accumulator.rawValue), .text("accumulator")])
        }
        if sa.intermediate != sb.intermediate {
            differences.append([.literal(sa.intermediate.rawValue), .text("vs"), .literal(sb.intermediate.rawValue), .text("intermediates")])
        }
        if satRelevant && sa.satCentring != sb.satCentring {
            differences.append([.text(sa.satCentring == .plain ? "plain" : "mean-centred"), .text("vs"),
                                .text(sb.satCentring == .plain ? "plain" : "mean-centred"), .text("SAT")])
        }
        if differences.isEmpty {
            let f = fa.first ?? 0
            let kinds = Array(Set(kindsA.map(\.rawValue))).sorted().joined(separator: " + ")
            return Self.row(.gpu, .same, BadgedLine([.value(Self.computed(f, Self.fetchStyle(f))), .literal(Self.fetchWord(ka)),
                                                     .text("fetches per pass ·"), .literal(kinds), .text("for both")]))
        }
        let segments = differences.enumerated().flatMap { i, d in (i > 0 ? [BadgedSegment.text("·")] : []) + d }
        return Self.row(.gpu, .differs, BadgedLine(segments))
    }

    // MARK: Floor 7 · PIXEL

    private func pixelRow(_ A: Side, _ B: Side, _ pixels: PixelEvidence?) -> Row {
        if let evidence = pixels {
            let s = evidence.stats
            let device = evidence.provenance == .measured ? evidence.device : nil
            func badge(_ v: Double, _ style: NumberStyle) -> BadgedValue { .number(v, style, evidence.provenance, device: device) }
            let ulps = NumberStyle(precision: .decimals(1), unit: "fp16 ulp", spokenUnit: "half-float ulps")
            if s.maxAbs == 0 { return Self.row(.pixels, .same, .words("identical pixels")) }
            if s.maxULP16 <= Self.pixelULPTolerance {
                return Self.row(.pixels, .approximatelySame, BadgedLine([.text("max |A − B|"), .value(badge(s.maxULP16, ulps)),
                                                                         .text("· within one ulp")]))
            }
            let steps = NumberStyle.integer(noun: CountNoun("8-bit step", "8-bit steps"))
            return Self.row(.pixels, .differs, BadgedLine([.text("max |A − B|"), .value(badge(s.maxLSB8.rounded(), steps)), .text("·"),
                                                           .value(badge(s.maxULP16, ulps))]))
        }
        let a = A.configuration, b = B.configuration
        let sameInput = a.specimen == b.specimen && a.specimenOptions == b.specimenOptions && a.pan == b.pan && a.windowSize == b.windowSize
        guard sameInput else { return Self.row(.pixels, .differs, .words("different input images · not yet compared")) }
        if a.blur == b.blur && A.resolved == B.resolved && a.parameters == b.parameters && a.settings == b.settings {
            return Self.row(.pixels, .same, .words("same configuration · same pixels"))
        }
        let sa = a.settings, sb = b.settings
        let samePrecision = sa.accumulator == sb.accumulator && sa.intermediate == sb.intermediate
            && sa.colourSpace == sb.colourSpace && sa.alphaMode == sb.alphaMode && sa.edgeMode == sb.edgeMode
        if let pa = A.psf?.kernel, let pb = B.psf?.kernel, samePrecision, AnalysisMath.maxDifference(pa, pb) <= Self.kernelTolerance {
            return Self.row(.pixels, .approximatelySame, .words("same kernel · equal up to rounding · not yet compared"))
        }
        return Self.row(.pixels, .differs, .words("different outputs expected · not yet compared"))
    }
}
