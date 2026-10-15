import Foundation

// OWNER: CONTENT-LAYERS. The seven floors, the rail and the pills (ARCHITECTURE §5.11; SPEC §4.1.3–§4.1.4, §5).
// Pages are DATA: every page merges the operator's own `FloorFacts` with the class template of SPEC §5.2 and the live
// Runs in `LiveFacts`. Hand-written text is limited to the catalog signature, one governing rule per floor template and
// family, and one closing lesson per Tier 1 entry (SPEC §5.0 rule 5). The frozen type name is `FloorPageBuilder`.

public struct FloorPageBuilder: FloorPageBuilding {
    /// Tool conventions (SEMANTICS); nil = `BlurServices.tools`, resolved at use so the service locator stays acyclic.
    public let tools: (any ToolConventionProviding)?
    /// Where the Shader tab reads the bundled `.metal` text (the app bundle by default).
    public let shaderSources: any ContentShaderSourceProviding

    public init(tools: (any ToolConventionProviding)? = nil, shaderSources: any ContentShaderSourceProviding = ContentBundleShaderSources()) {
        self.tools = tools
        self.shaderSources = shaderSources
    }

    var toolProvider: any ToolConventionProviding { tools ?? BlurServices.tools }

    // MARK: Pages

    public func pages(for op: any BlurOperator, context: FloorContext) -> [FloorPage] {
        let inputs = ContentPageInputs(op: op, context: context, tools: toolProvider, shaderSources: shaderSources)
        return Floor.allCases.map { page($0, inputs: inputs) }
    }

    public func page(_ floor: Floor, for op: any BlurOperator, context: FloorContext) -> FloorPage {
        page(floor, inputs: ContentPageInputs(op: op, context: context, tools: toolProvider, shaderSources: shaderSources))
    }

    func page(_ floor: Floor, inputs i: ContentPageInputs) -> FloorPage {
        let draft: ContentFloorDraft
        switch floor {
        case .slide: draft = ContentFloorTemplates.slide(i)
        case .api: draft = ContentFloorTemplates.api(i)
        case .math: draft = ContentFloorTemplates.math(i)
        case .kernel: draft = ContentFloorTemplates.kernel(i)
        case .algorithm: draft = ContentFloorTemplates.algorithm(i)
        case .gpu: draft = ContentFloorTemplates.gpu(i)
        case .pixels: draft = ContentFloorTemplates.pixels(i)
        }
        return Self.merge(floor: floor, draft: draft, facts: i.op.facts(floor, i.context), entry: i.entry)
    }

    /// Merges the operator's facts over the template (SPEC §5.0): the operator's numbers come first and the template fills
    /// the remaining primary slots; at most six numbers stay primary and the rest move into `All … details`, never
    /// dropped. An operator `emptyReason` means the floor has nothing honest to plot, so only the operator's own figure
    /// and numbers remain.
    static func merge(floor: Floor, draft: ContentFloorDraft, facts: FloorFacts, entry: CatalogEntry) -> FloorPage {
        var numbers: [LabeledValue] = []
        var figure = draft.figure, empty = draft.emptyReason
        if let reason = facts.emptyReason {
            numbers = facts.numbers
            figure = facts.figure
            empty = reason
        } else {
            var seen = Set<String>()
            for row in facts.numbers + draft.numbers where !seen.contains(row.id) {
                seen.insert(row.id); numbers.append(row)
            }
            if let f = facts.figure { figure = f }
        }
        var details = draft.details + facts.details
        if numbers.count > 6 {
            details.insert(.values(Array(numbers[6...])), at: 0)
            numbers = Array(numbers.prefix(6))
        }
        var tabs = draft.tabs
        if let opTabs = facts.tabs {
            var merged = tabs ?? []
            for t in opTabs {
                if let k = merged.firstIndex(where: { $0.id == t.id }) { merged[k] = t } else { merged.append(t) }
            }
            tabs = merged
        }
        tabs = tabs.map { $0.map(Self.capped) }
        if numbers.isEmpty && figure == nil && (tabs ?? []).isEmpty && empty == nil {
            empty = Self.defaultEmptyReason(floor: floor, entry: entry)
        }
        return FloorPage(floor: floor, eyebrow: floor.eyebrow, question: floor.question, signature: entry.signature,
                         dominantBadges: Self.dominantBadges(numbers: numbers, figure: figure, fallback: draft.dominantFallback),
                         governingRule: facts.governingRule ?? draft.governingRule, figure: figure, numbers: numbers,
                         details: details, tabs: tabs, inThisApp: draft.inThisApp, emptyState: empty)
    }

    static func capped(_ tab: FloorTab) -> FloorTab {
        guard tab.numbers.count > 6 else { return tab }
        var t = tab
        t.details.insert(.values(Array(tab.numbers[6...])), at: 0)
        t.numbers = Array(tab.numbers.prefix(6))
        return t
    }

    static func defaultEmptyReason(floor: Floor, entry: CatalogEntry) -> String {
        switch entry.linearity {
        case .nonlinear: "N/A · NONLINEAR"
        case .lsv: "NO SINGLE RESPONSE · SPACE-VARIANT"
        case .system: "SYSTEM INTERNALS · INFERRED"
        default: entry.tier == .tier3 ? "CPU ONLY IN THIS APP · TIER 3" : "NOTHING TO SHOW ON THIS FLOOR FOR THIS BLUR"
        }
    }

    /// The floor's dominant badges: the most frequent provenances among its numbers and figure, at most two.
    static func dominantBadges(numbers: [LabeledValue], figure: FigureSpec?, fallback: [Provenance]) -> [Provenance] {
        var counts: [Provenance: Int] = [:]
        for row in numbers { if let p = row.value.provenance { counts[p, default: 0] += 1 } }
        for p in figure.map(ContentFigures.provenances) ?? [] { counts[p, default: 0] += 1 }
        if counts.isEmpty { return fallback }
        let order = Provenance.allCases
        return counts.sorted { a, b in a.value != b.value ? a.value > b.value : (order.firstIndex(of: a.key) ?? 0) < (order.firstIndex(of: b.key) ?? 0) }
            .prefix(2).map(\.key)
    }

    // MARK: Rail (SPEC §4.1.4)

    public func railChips(for op: any BlurOperator, context: FloorContext) -> [RailChip] {
        let i = ContentPageInputs(op: op, context: context, tools: toolProvider, shaderSources: shaderSources)
        let comparisons: [Floor: FloorComparison]
        if let b = context.compareB {
            let rows = BlurServices.divergence.compare(context.configuration, b, homeToolID: context.homeToolID, displayScale: context.displayScale)
            comparisons = Dictionary(rows.map { ($0.floor, $0) }, uniquingKeysWith: { a, _ in a })
        } else {
            comparisons = [:]
        }
        return Floor.allCases.map { floor in
            RailChip(floor: floor, value: ContentRail.value(floor, i), comparison: comparisons[floor])
        }
    }

    // MARK: Pills (SPEC §4.1.3 "Pills")

    public func pills(for op: any BlurOperator, context: FloorContext) -> PillContent {
        ContentPills.make(ContentPageInputs(op: op, context: context, tools: toolProvider, shaderSources: shaderSources))
    }
}

/// What a floor template produces before the operator's facts are merged in.
struct ContentFloorDraft {
    var numbers: [LabeledValue] = []
    var figure: FigureSpec?
    var governingRule: String?
    var details: [ContentBlock] = []
    var tabs: [FloorTab]?
    var emptyReason: String?
    var inThisApp: String
    var dominantFallback: [Provenance] = [.computed]
}

/// Everything a page, chip, pill or step needs, computed once per build (lazily: pages for rank filters never ask for a
/// response, and adaptive weight maps are computed only when a floor asks).
final class ContentPageInputs {
    let op: any BlurOperator
    let entry: CatalogEntry
    let context: FloorContext
    let tools: any ToolConventionProviding
    let shaderSources: any ContentShaderSourceProviding
    let request: OperatorRequest
    let resolution: VariantResolution
    let variant: VariantDescriptor?
    let plan: PassPlan
    let cls: ContentTemplateClass

    init(op: any BlurOperator, context: FloorContext, tools: any ToolConventionProviding, shaderSources: any ContentShaderSourceProviding) {
        self.op = op
        self.entry = op.entry
        self.context = context
        self.tools = tools
        self.shaderSources = shaderSources
        self.request = context.request
        self.resolution = op.resolveVariant(context.request)
        self.variant = op.entry.variant(resolution.variant)
        self.plan = op.passPlan(context.request)
        self.cls = ContentTemplateClass.of(op, context.request)
    }

    var live: LiveFacts { context.live }
    var probe: PixelPoint { context.probe }
    var settings: SilentSettings { request.settings }
    var scale: Double { context.displayScale }

    /// The PSF at the probe; adaptive blurs get the current image (LIVE · CPU).
    lazy var psf: PSF? = op.psf(at: probe, request, content: context.content)
    /// The PSF without image content (for classes whose kernel does not depend on it).
    lazy var marginal: Kernel1D? = psf?.kernel.marginalX
    /// Discrete signed response of the taps (primary trace) along x, or the local one at the probe.
    lazy var discreteResponse: ResponseCurve? = op.response(ResponseQuery(point: cls.isLocal ? probe : nil), request, content: context.content)
    /// Continuous response (quiet trace) where the operator has one.
    lazy var continuousResponse: ResponseCurve? = op.response(ResponseQuery(point: cls.isLocal ? probe : nil, continuous: true), request,
                                                              content: context.content)
    lazy var profile: ProfileCurve? = op.continuousProfile(request)
    lazy var sigma: Double? = op.sigma(request)
    lazy var massCut: ContentKernelMath.MassCut? = ContentKernelMath.massCut(op, request)

    /// The primary parameter's value as a Double (px, pt, %, … in its own unit).
    var primaryValue: Double? { request.parameters.double(entry.primary) ?? entry.defaultParameters.double(entry.primary) }
    var primarySpec: ParameterSpec? { entry.primarySpec }

    /// The sub-texel rule: this phone's MEASURED probe if it has run, else the Mac rule (8 bits, nearest; MEASURED M1 Max).
    var subTexelRule: (bits: Int, rounding: SubTexelRounding, measuredHere: Bool) {
        if let o = ReferenceOptions.forDevice(live.deviceProbes), let bits = o.subTexelBits { return (bits, o.subTexelRounding, true) }
        return (8, .nearest, false)
    }

    /// True when the resolved variant merges taps through the hardware sampler (linear-sampled pairs).
    var mergesTaps: Bool {
        let id = resolution.variant.rawValue.lowercased(), name = (variant?.displayName ?? "").lowercased()
        return id.contains("linear-sampl") || name.contains("linear-sampled")
    }

    lazy var pairAnalysis: ContentKernelMath.PairAnalysis? = {
        guard mergesTaps, let k = marginal else { return nil }
        let rule = subTexelRule
        return ContentKernelMath.pairAnalysis(k, bits: rule.bits, rounding: rule.rounding)
    }()

    /// The newest full-resolution Run (measurement-derived values follow it; previews hold, SPEC §4.1.6).
    var fullRun: Run? { live.run.flatMap { $0.quality.publishesMeasurements ? $0 : nil } }
    var isPreview: Bool { live.run.map { !$0.quality.publishesMeasurements } ?? false }

    var swiftUILaw: CalibrationLaw? {
        let sweep = live.calibrations.filter { $0.request.subject == .swiftUIBlur }
        return sweep.count >= 2 ? BlurServices.psfFitter.law(sweep) : nil
    }
}

// MARK: - Figure helpers

enum ContentFigures {
    static func provenances(_ f: FigureSpec) -> [Provenance] {
        switch f {
        case .plot(let p): Array(Set(p.series.map(\.provenance)))
        case .heatmap(let h): [h.provenance]
        case .texelGrid(let t): [t.provenance]
        case .dispatchOverlay: [.computed]
        case .passTiles: [.computed]
        case .psfField: [.computed]
        case .toolBars(let b): b.rows.compactMap(\.value.provenance)
        case .code: [.reference]
        case .pair(let a, let b): provenances(a) + provenances(b)
        }
    }

    /// A signed response plot: discrete taps (primary) over the continuous response (quiet), zero line, markers.
    static func responsePlot(discrete: ResponseCurve?, continuous: ResponseCurve?, title: String = "H",
                             summary: String) -> PlotSpec? {
        guard discrete != nil || continuous != nil else { return nil }
        var series: [PlotSeries] = []
        if let c = continuous {
            series.append(PlotSeries(name: "continuous " + title, xs: c.frequencies, ys: c.values, style: .quiet, role: .reference, provenance: c.provenance))
        }
        if let d = discrete {
            series.append(PlotSeries(name: title + " of the taps", xs: d.frequencies, ys: d.values, style: .solid, role: .primary, provenance: d.provenance))
        }
        let reference = discrete ?? continuous!
        var markers: [PlotMarker] = []
        if let f = reference.firstCrossing(of: 1 / 2.0.squareRoot()) { markers.append(PlotMarker(x: f, label: "−3 dB", kind: .minus3dB, provenance: .computed)) }
        if let f = reference.firstCrossing(of: 0.5) { markers.append(PlotMarker(x: f, label: "half amplitude", kind: .halfAmplitude, provenance: .computed)) }
        if let f = reference.firstCrossing(of: 0) { markers.append(PlotMarker(x: f, label: "first zero", kind: .firstZero, provenance: .computed)) }
        return PlotSpec(xAxis: PlotAxis(label: "frequency", unit: "c/px", range: 0...(reference.frequencies.last ?? 0.5)),
                        yAxis: PlotAxis(label: title, normalized: true), series: series, markers: markers, showsZeroLine: true,
                        accessibilitySummary: summary)
    }

    /// Discrete stems over the continuous profile, both in weight per pixel.
    static func kernelPlot(_ k: Kernel1D, profile: ProfileCurve?, provenance: Provenance, supportMarkers: Bool = true,
                           summary: String) -> PlotSpec {
        var series: [PlotSeries] = []
        if let p = profile {
            series.append(PlotSeries(name: p.label, xs: p.xs, ys: p.ys, style: .quiet, role: .reference, provenance: .computed))
        }
        series.append(ContentKernelMath.stems(k, provenance: provenance))
        var markers: [PlotMarker] = []
        if supportMarkers, k.tapCount > 1 {
            markers = [PlotMarker(x: k.offset(0), label: "support", kind: .supportBracket, provenance: .computed),
                       PlotMarker(x: k.offset(k.tapCount - 1), label: "support", kind: .supportBracket, provenance: .computed)]
        }
        return PlotSpec(xAxis: PlotAxis(label: "tap offset", unit: "px"), yAxis: PlotAxis(label: "weight"), series: series,
                        markers: markers, accessibilitySummary: summary)
    }

    /// A 2-D kernel as a heat map centred on its origin, trimmed to its non-zero bounding box (at most 129 × 129).
    static func kernelHeatmap(_ k: Kernel2D, caption: String, provenance: Provenance, signed: Bool = false) -> HeatmapSpec {
        let t = trimmed(k)
        var w = t.width, h = t.height, values = t.weights, ox = t.originX, oy = t.originY
        let limit = 129
        if w > limit || h > limit {
            let sx = Int((Double(w) / Double(limit)).rounded(.up)), sy = Int((Double(h) / Double(limit)).rounded(.up))
            let nw = (w + sx - 1) / sx, nh = (h + sy - 1) / sy
            var v = [Double](repeating: 0, count: nw * nh)
            for y in 0..<h { for x in 0..<w { v[(y / sy) * nw + x / sx] += t.weights[y * w + x] } }
            values = v; w = nw; h = nh; ox /= sx; oy /= sy
        }
        return HeatmapSpec(width: w, height: h, values: values, signed: signed || values.contains { $0 < 0 },
                           centre: PixelPoint(x: ox, y: oy), caption: caption, provenance: provenance)
    }

    /// The non-zero bounding box of a 2-D kernel.
    static func trimmed(_ k: Kernel2D) -> Kernel2D {
        var x0 = k.width, x1 = -1, y0 = k.height, y1 = -1
        for y in 0..<k.height { for x in 0..<k.width where k[x, y] != 0 { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
        guard x1 >= x0, y1 >= y0 else { return k }
        let w = x1 - x0 + 1, h = y1 - y0 + 1
        var v = [Double](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w { v[y * w + x] = k[x0 + x, y0 + y] } }
        return Kernel2D(width: w, height: h, originX: k.originX - x0, originY: k.originY - y0, weights: v)
    }

    /// The signed 2-D H heat map of a PSF (the MATH figure of non-separable entries, review fix P-36/§5.1 floor 3).
    static func responseHeatmap(_ k: Kernel2D, provenance: Provenance) -> HeatmapSpec {
        let n = 33
        return HeatmapSpec(width: n, height: n, values: ContentKernelMath.signedResponse2D(k, samples: n), signed: true,
                           centre: PixelPoint(x: n / 2, y: n / 2),
                           caption: "SIGNED H(u, v) · DC AT THE CENTRE · NYQUIST AT THE EDGES · NEGATIVE REGIONS HATCHED",
                           provenance: provenance)
    }
}
