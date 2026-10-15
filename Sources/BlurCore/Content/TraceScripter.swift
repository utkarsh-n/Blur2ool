import Foundation

// OWNER: CONTENT-LAYERS. The pixel trace's script (SPEC §6.3 grammar, §6.4 honesty, §6.5 per-class sub-steps). Steps are
// generated from the blur's pass graph, the catalog data and the TraceRecord (GPU records are LIVE, reconstructions are
// COMPUTED; JF M-6), so every Tier 1 entry gets a walk without hand-written step lists. The only hand-written text is
// the closing lesson of the four guided descents' entries. A step never changes parameters; it only reveals. Branches
// are values beside the real path (`if sRGB-encoded: 115/255`, COMPUTED), never forks.

public struct TraceScripter: TraceScripting {
    public let tools: (any ToolConventionProviding)?
    public init(tools: (any ToolConventionProviding)? = nil) { self.tools = tools }

    public func steps(for record: TraceRecord, op: any BlurOperator, context: FloorContext) -> [TraceStep] {
        var configuration = context.configuration
        configuration.variant = record.variant
        configuration.parameters = record.parameters
        configuration.settings = record.settings
        configuration.probe = record.probe
        let ctx = FloorContext(configuration: configuration, homeToolID: context.homeToolID, displayScale: context.displayScale,
                               live: context.live, content: context.content, compareB: nil)
        let builder = FloorPageBuilder(tools: tools)
        let i = ContentPageInputs(op: op, context: ctx, tools: builder.toolProvider, shaderSources: builder.shaderSources)
        var w = ContentTraceWriter(i: i, record: record, builder: builder)
        return w.write()
    }
}

/// One step before ids, next lines, labels and phase lines are known.
struct ContentStepDraft {
    var floor: Floor
    var completed: String
    var subSteps: [TraceSubStep] = []
    var passIndex: Int?
    var panel = FloorFacts()
    var branchValues: [LabeledValue] = []
    var closingLesson: String?
    /// What the first `Next …` press inside this step does ("fetch 1 at +0.00 px").
    var firstNext: String?
}

struct ContentTraceWriter {
    let i: ContentPageInputs
    let record: TraceRecord
    let builder: FloorPageBuilder
    var drafts: [ContentStepDraft] = []
    lazy var pages: [Floor: FloorPage] = Dictionary(uniqueKeysWithValues: Floor.allCases.map { ($0, builder.page($0, inputs: i)) })

    init(i: ContentPageInputs, record: TraceRecord, builder: FloorPageBuilder) {
        self.i = i; self.record = record; self.builder = builder
    }

    var probe: PixelPoint { record.probe }

    mutating func write() -> [TraceStep] {
        slideStep()
        apiSteps()
        mathStep()
        if i.cls == .spaceVariant || i.cls == .temporal { centreStep() }
        kernelSteps()
        if i.cls == .system {
            systemLaneSteps()
        } else if i.cls == .atlas {
            atlasSteps()
        } else {
            algorithmSteps()
            gpuSteps()
        }
        pixelSteps()
        return finish()
    }

    // MARK: Floors 1–2

    mutating func slideStep() {
        let typed = ContentSlide.typed(i, toolID: i.context.homeToolID)
        let tool = ContentValues.toolName(i.context.homeToolID, conventions: i.tools.all)
        var panel = FloorFacts()
        let page = pages[.slide]
        panel.figure = page?.figure
        panel.numbers = page?.numbers ?? []
        panel.governingRule = page?.governingRule
        let completed: String
        switch typed.kind {
        case .number:
            var text = typed.value.text
            if text.hasPrefix("≈") { text.removeFirst() }
            completed = "You would type \(text) in \(tool)"
        case .unverified: completed = "\(tool)'s number for this blur is UNVERIFIED"
        case .notOffered: completed = "\(tool) does not offer this blur"
        case .words: completed = "\(tool) offers \(typed.value.text.lowercased())"
        }
        if typed.sigmaMatchedOnly { panel.details.append(.note(ContentToolKernels.sameSigmaCaption + ": the number matches σ, not the kernel's shape.", nil)) }
        drafts.append(ContentStepDraft(floor: .slide, completed: completed, panel: panel))
    }

    mutating func apiSteps() {
        // The unit chain.
        if let spec = i.primarySpec, let v = i.primaryValue, spec.unit == .px || spec.unit == .pt {
            let px = spec.unit == .pt ? v * i.scale : v
            let pt = px / Swift.max(i.scale, 1e-9)
            let ptValue = BadgedValue.number(pt, ContentStyle.pt2, .computed)
            let pxValue = spec.unit == .pt ? BadgedValue.number(px, ContentStyle.px1, .computed) : BadgedValue.number(px, spec.numberStyle, .computed)
            var panel = FloorFacts(numbers: [LabeledValue(id: "pt", label: spec.label + " · PT", value: ptValue),
                                             LabeledValue(id: "scale", label: "DISPLAY SCALE", value: .number(i.scale, .decimals(0), .computed)),
                                             LabeledValue(id: "px", label: spec.label + " · PX", value: pxValue)],
                                   governingRule: "px = pt × display scale")
            if ContentOffscreen.isSwiftUITool(i.context.homeToolID) {
                panel.details.append(.note("SwiftUI's regime switch: σ ≈ r·scale below about five device pixels, ≈ 0.90·r·scale above (MEASURED offscreen on macOS; this phone measures its own in Calibrate).", .measured))
            }
            drafts.append(ContentStepDraft(floor: .api, completed: "\(ptValue.text) pt × \(NumberStyle.decimals(0).text(i.scale)) = \(pxValue.text) px", panel: panel))
        } else if let spec = i.primarySpec, let v = i.primaryValue {
            let value = BadgedValue.number(v, spec.numberStyle, .computed)
            drafts.append(ContentStepDraft(floor: .api, completed: "\(spec.label.capitalized) \(value.textWithUnit) in Blur2ool's call",
                                           panel: FloorFacts(numbers: [LabeledValue(id: "primary", label: spec.unitLine, value: value)])))
        }
        // The silent parameters, each with its branch value.
        let s = record.settings
        let words = [ContentValues.words(s.colourSpace), ContentValues.words(s.edgeMode), ContentValues.words(s.alphaMode)].map { $0.lowercased() }
        var completed = words.joined(separator: ", ")
        completed = completed.prefix(1).uppercased() + completed.dropFirst()
        var panel = FloorFacts(numbers: [LabeledValue(id: "colour", label: "COLOUR SPACE", value: .words(ContentValues.words(s.colourSpace))),
                                         LabeledValue(id: "edges", label: "EDGES", value: .words(ContentValues.words(s.edgeMode))),
                                         LabeledValue(id: "alpha", label: "ALPHA", value: .words(ContentValues.words(s.alphaMode)))])
        var branches: [LabeledValue] = []
        if let real = realOutput {
            panel.numbers.append(LabeledValue(id: "real", label: "OUT ENCODED (THIS PATH)", value: .number(Double(SRGB.code8(linear: ContentValues.scalar(real.value))), ContentStyle.code8, real.provenance)))
        }
        branches = branchValues()
        panel.details.append(.paragraph("Branches, not forks: each alternative result is COMPUTED beside the real one, and the walk keeps following the real path."))
        drafts.append(ContentStepDraft(floor: .api, completed: completed, panel: panel, branchValues: branches))
    }

    /// The probe's output on the real path, as badged data: the GPU's record (LIVE) or the reconstruction (COMPUTED).
    var realOutput: (value: SIMD4<Double>, provenance: Provenance)? {
        if let g = record.gpuOutput { return (g, .live) }
        if let last = record.passes.last { return (last.outputAtProbe, last.source.provenance) }
        return nil
    }

    func branchValues() -> [LabeledValue] {
        guard let content = i.context.content else { return [] }
        var rows: [LabeledValue] = []
        if let b = ContentProbeReference.colourBranch(i.op, content: content, i.request, probe: probe) {
            let label = b.settings.colourSpace == .srgbEncoded ? "IF sRGB-ENCODED" : "IF LINEAR LIGHT"
            rows.append(LabeledValue(id: "branch-colour", label: label, value: .number(Double(SRGB.code8(linear: ContentValues.scalar(b.value))), ContentStyle.code8, .computed)))
        }
        func branch(_ label: String, _ change: (inout SilentSettings) -> Void) {
            var settings = i.settings
            change(&settings)
            guard settings != i.settings else { return }
            if let v = ContentProbeReference.branch(i.op, content: content, i.request, probe: probe, settings: settings) {
                rows.append(LabeledValue(id: "branch-" + label, label: label, value: .number(Double(SRGB.code8(linear: ContentValues.scalar(v))), ContentStyle.code8, .computed)))
            }
        }
        branch(i.settings.edgeMode == .mirror ? "IF CLAMP EDGES" : "IF MIRROR EDGES") { $0.edgeMode = $0.edgeMode == .mirror ? .clamp : .mirror }
        branch(i.settings.alphaMode == .straight ? "IF PREMULTIPLIED" : "IF STRAIGHT ALPHA") { $0.alphaMode = $0.alphaMode == .straight ? .premultiplied : .straight }
        return rows
    }

    // MARK: Floors 3–4

    mutating func mathStep() {
        var panel = FloorFacts()
        if let page = pages[.math] { panel.figure = page.figure; panel.numbers = page.numbers; panel.governingRule = page.governingRule }
        let completed: String
        if let spec = i.primarySpec, let v = i.primaryValue {
            let name = spec.key == "sigma" ? "σ" : spec.label.lowercased()
            let value = BadgedValue.number(v, spec.numberStyle, .computed)
            panel.numbers.insert(LabeledValue(id: "primary", label: spec.unitLine, value: value), at: 0)
            panel.numbers = Array(panel.numbers.prefix(6))
            completed = "\(i.entry.mathSymbol) with \(name) \(value.textWithUnit)"
        } else {
            completed = "\(i.entry.mathSymbol): \(ContentRail.mathSpoken(i.entry.mathSymbol))"
        }
        drafts.append(ContentStepDraft(floor: .math, completed: completed, panel: panel))
    }

    /// Space-variant classes: "Where is the centre?" (distance and angle from it, SPEC §6.5).
    mutating func centreStep() {
        guard let key = i.entry.parameters.first(where: { if case .position = $0.kind { return true }; return false })?.key,
              let c = i.request.parameters.point(key) ?? i.entry.defaultParameters.point(key) else { return }
        let dx = probe.centre.x - c.x, dy = probe.centre.y - c.y
        let distance = BadgedValue.number((dx * dx + dy * dy).squareRoot(), ContentStyle.px1, .computed)
        let angle = BadgedValue.number(atan2(dy, dx) * 180 / .pi, NumberStyle.decimals(1, unit: "°", spokenUnit: "degrees"), .computed)
        drafts.append(ContentStepDraft(floor: .math, completed: "The centre is \(distance.textWithUnit) away, at \(angle.textWithUnit)",
                                       panel: FloorFacts(numbers: [LabeledValue(id: "distance", label: "DISTANCE FROM THE CENTRE", value: distance),
                                                                   LabeledValue(id: "angle", label: "ANGLE FROM THE CENTRE", value: angle)],
                                                         governingRule: "r = |p − c|,  θ = atan2(y − c_y, x − c_x)")))
    }

    mutating func kernelSteps() {
        let page = pages[.kernel]
        var panel = FloorFacts()
        panel.figure = page?.figure; panel.numbers = page?.numbers ?? []; panel.governingRule = page?.governingRule
        if let k = i.marginal, [.separableFIR, .runningSum, .recursive, .sparseIterated, .derived, .atlas].contains(i.cls) {
            let how = (i.request.parameters.choice("discretisation") ?? (i.massCut != nil ? "sampled" : "")).lowercased()
            let taps = BadgedValue.number(Double(k.tapCount), ContentStyle.taps, .computed)
            panel.numbers.insert(LabeledValue(id: "weights", label: "WEIGHTS", value: taps), at: 0)
            panel.numbers = Array(panel.numbers.prefix(6))
            drafts.append(ContentStepDraft(floor: .kernel, completed: how.isEmpty ? "\(NumberStyle.integer().text(Double(k.tapCount))) weights per axis"
                                                                                  : "\(NumberStyle.integer().text(Double(k.tapCount))) weights \(how == "lindeberg" ? "from Lindeberg's discrete Gaussian" : how)",
                                           panel: panel))
            if let cut = i.massCut, let s = i.request.parameters.double("sigma") {
                let sigma = BadgedValue.number(k.sigma, NumberStyle.decimals(3, unit: "px", spokenUnit: "pixels"), .computed)
                let minH = KernelMath.response(k, frequencies: ResponseQuery().frequencies).min() ?? 0
                let ripple = BadgedValue.number(minH, ContentStyle.response(minH), .computed)
                var cutPanel = FloorFacts(numbers: [
                    LabeledValue(id: "radius", label: "CUT AT", value: .number(Double(cut.radius), ContentStyle.taps, .computed, caption: "EACH SIDE")),
                    LabeledValue(id: "mass", label: "MASS CUT · PER AXIS", value: .number(cut.perAxis * 100, ContentStyle.percent, .computed)),
                    LabeledValue(id: "mass2d", label: "MASS CUT · 2-D", value: .number(cut.twoD * 100, ContentStyle.percent, .computed)),
                    LabeledValue(id: "sigma", label: "DISCRETE σ", value: sigma),
                    LabeledValue(id: "ripple", label: "RIPPLE (MIN H)", value: ripple),
                    LabeledValue(id: "nominal", label: "NOMINAL σ", value: .input(s, ContentStyle.px1)),
                ], governingRule: page?.governingRule)
                cutPanel.figure = page?.figure
                drafts.append(ContentStepDraft(floor: .kernel, completed: "Renormalised after cutting at ±\(NumberStyle.integer().text(Double(cut.radius)))", panel: cutPanel))
            }
        } else {
            let completed: String
            switch i.cls {
            case .adaptive: completed = i.psf?.provenance == .live ? "Weights read from the image around the probe" : "Weights depend on the image"
            case .rank: completed = "The window is sorted, not weighted"
            case .spaceVariant, .temporal: completed = "The local PSF at the probe"
            case .system: completed = "Our model beside the measured spread"
            case .globalFFT: completed = "The kernel is defined by its spectrum"
            default: completed = "The 2-D weights"
            }
            drafts.append(ContentStepDraft(floor: .kernel, completed: completed, panel: panel))
        }
    }

    // MARK: Floor 5

    mutating func algorithmSteps() {
        let plan = i.plan
        let passNames = plan.passes.map(\.name)
        var panel = FloorFacts(figure: .passTiles(PassTilesSpec(passes: plan.passes, timings: i.live.timedRun?.timing?.perPass ?? [], selected: nil)),
                               governingRule: pages[.algorithm]?.governingRule)
        let completed: String
        if i.cls == .separableFIR && passNames.count == 2, let k = i.marginal {
            let taps = Double(k.tapCount)
            panel.numbers = [LabeledValue(id: "direct", label: "2-D TAPS", value: .number(taps * taps, ContentStyle.taps, .computed)),
                             LabeledValue(id: "separable", label: "SEPARABLE TAPS", value: .number(2 * taps, ContentStyle.taps, .computed))]
            completed = "Split into \(passNames.joined(separator: " then "))"
        } else if plan.passes.count == 1 {
            panel.numbers = [LabeledValue(id: "taps", label: "TAPS PER PIXEL", value: .number(plan.passes[0].tapsPerPixel, ContentStyle.taps, .computed))]
            completed = i.cls == .separableFIR || i.cls == .gather2D ? "One 2-D gather" : "One pass: \(plan.passes[0].name)"
        } else {
            panel.numbers = [LabeledValue(id: "passes", label: "PASSES", value: .number(Double(plan.passes.count), ContentStyle.passes, .computed))]
            completed = i.cls == .iterativePDE ? "\(NumberStyle.integer().text(Double(plan.passes.count))) iterations" : "\(NumberStyle.integer().text(Double(plan.passes.count))) passes: \(passNames.joined(separator: " · "))"
        }
        drafts.append(ContentStepDraft(floor: .algorithm, completed: completed, panel: panel))
        if let pairs = i.pairAnalysis, let first = plan.passes.first {
            let fetches = BadgedValue.number(first.fetchesPerPixel, ContentStyle.fetches, .computed)
            let pairPanel = FloorFacts(numbers: [LabeledValue(id: "fetches", label: "FETCHES PER PASS", value: fetches),
                                                 LabeledValue(id: "taps", label: "TAPS PER PASS", value: .number(first.tapsPerPixel, ContentStyle.taps, .computed))],
                                       governingRule: "one bilinear fetch at k + b/(a + b) blends taps k and k + 1",
                                       details: [.table(TableBlock(columns: ["PAIR", "OFFSET", "WEIGHT"], rows: pairs.table.offsets.indices.map {
                                           [NumberStyle.integer().text(Double($0)), NumberStyle.decimals(4).text(pairs.table.offsets[$0]), ContentStyle.weight.text(pairs.table.weights[$0])]
                                       }, caption: "The pairing table", provenance: .computed))])
            drafts.append(ContentStepDraft(floor: .algorithm, completed: "Merged into \(NumberStyle.integer().text(first.fetchesPerPixel)) bilinear fetches per pass", panel: pairPanel))
        }
    }

    // MARK: Floor 6

    mutating func gpuSteps() {
        let plan = i.plan
        for (n, descriptor) in plan.passes.enumerated() {
            let pass = record.passes.first { $0.descriptor.id == descriptor.id } ?? (record.passes.indices.contains(n) && record.passes[n].descriptor.name == descriptor.name ? record.passes[n] : nil)
            let taps = pass.map(tapsOf) ?? []
            let noun = i.cls.subStepNoun
            let count = NumberStyle.integer().text(Double(taps.count))
            let unitWord = taps.count == 1 ? noun.singular : noun.plural
            if n == 0 {
                var issue = FloorFacts(numbers: [LabeledValue(id: "outputs", label: descriptor.kind == .compute ? "THREADS" : "FRAGMENTS",
                                                              value: .number(Double(i.request.size.pixelCount) * descriptor.outputScale * descriptor.outputScale, .integer(noun: CountNoun("output pixel", "output pixels")), .computed)),
                                                 LabeledValue(id: "target", label: "TARGET", value: .words(ContentValues.words(i.settings.intermediate))),
                                                 LabeledValue(id: "sampler", label: "SAMPLER", value: .words(i.mergesTaps ? "LINEAR · " + ContentValues.words(i.settings.edgeMode) : "NEAREST · " + ContentValues.words(i.settings.edgeMode)))])
                if let page = pages[.gpu] { issue.figure = page.figure; issue.governingRule = page.governingRule }
                let verb: String
                switch descriptor.kind {
                case .fragment: verb = "Draw call issued for pass \(descriptor.name)"
                case .compute: verb = "Dispatch issued for pass \(descriptor.name)"
                case .cpu: verb = "Pass \(descriptor.name) runs on the CPU"
                default: verb = "Pass \(descriptor.name) encoded"
                }
                drafts.append(ContentStepDraft(floor: .gpu, completed: verb, passIndex: descriptor.id, panel: issue))
                if let pass {
                    drafts.append(ContentStepDraft(floor: .gpu, completed: "\(count) \(unitWord) done", subSteps: subSteps(pass, taps: taps),
                                                   passIndex: descriptor.id, panel: fetchPanel(pass, taps: taps), firstNext: firstLine(taps)))
                    let out = BadgedValue.number(ContentValues.scalar(pass.outputAtProbe), ContentStyle.value4, pass.source.provenance)
                    var written = FloorFacts(numbers: [LabeledValue(id: "out", label: "PASS \(descriptor.name) OUTPUT", value: out)])
                    if let grid = neighbourhoodGrid(pass) { written.figure = .texelGrid(grid) }
                    drafts.append(ContentStepDraft(floor: .gpu, completed: "Pass \(descriptor.name) written: \(out.text)", passIndex: descriptor.id, panel: written))
                } else {
                    drafts.append(ContentStepDraft(floor: .gpu, completed: "Pass \(descriptor.name) is not recorded in this trace", passIndex: descriptor.id))
                }
            } else if let pass {
                let previous = record.passes.first { $0.descriptor.id == plan.passes[n - 1].id }
                let before = previous.map { ContentValues.scalar($0.outputAtProbe) }
                let after = ContentValues.scalar(pass.outputAtProbe)
                let out = BadgedValue.number(after, ContentStyle.value4, pass.source.provenance)
                var panel = fetchPanel(pass, taps: taps)
                panel.numbers.append(LabeledValue(id: "out", label: "PASS \(descriptor.name) OUTPUT", value: out))
                let unchanged = before.map { ContentStyle.value4.text($0) == out.text } ?? false
                if unchanged {
                    panel.details.append(.paragraph("Every texel this pass reads holds the same value, so the weighted average returns it unchanged."))
                }
                let completed = unchanged ? "Pass \(descriptor.name): \(count) \(unitWord), value unchanged" : "Pass \(descriptor.name): \(count) \(unitWord), written: \(out.text)"
                drafts.append(ContentStepDraft(floor: .gpu, completed: completed, subSteps: subSteps(pass, taps: taps), passIndex: descriptor.id, panel: panel,
                                               firstNext: firstLine(taps)))
            } else {
                drafts.append(ContentStepDraft(floor: .gpu, completed: "Pass \(descriptor.name) is not recorded in this trace", passIndex: descriptor.id,
                                               panel: FloorFacts(details: [.note("Tier 2 entries trace one declared stage; this pass's value is on the Algorithm floor.", nil)])))
            }
        }
        // GPU time, MEASURED.
        if let timed = i.live.timedRun, let timing = timed.timing, !timed.device.isSimulator {
            let ms = BadgedValue.number(timing.medianMilliseconds, ContentStyle.ms, .measured, device: timed.device)
            var panel = FloorFacts(numbers: [LabeledValue(id: "gpu", label: "GPU TIME", value: ms)])
            panel.numbers += timing.perPass.prefix(5).map { LabeledValue(id: "pass-\($0.passIndex)", label: "PASS " + $0.passName,
                                                                         value: .number($0.medianMilliseconds, ContentStyle.ms, .measured, device: timed.device)) }
            panel.figure = .passTiles(PassTilesSpec(passes: plan.passes, timings: timing.perPass, selected: nil))
            drafts.append(ContentStepDraft(floor: .gpu, completed: "GPU time \(ms.textWithUnit)", panel: panel))
        } else {
            drafts.append(ContentStepDraft(floor: .gpu, completed: "GPU time not yet measured",
                                           panel: FloorFacts(numbers: [LabeledValue(id: "gpu", label: "GPU TIME", value: .notYetMeasured(unit: "ms"))])))
        }
    }

    /// "fetch 1 at +0.00 px": what the first press inside a pass reveals.
    func firstLine(_ taps: [TraceTap]) -> String? {
        guard let t = taps.first else { return nil }
        let noun = i.cls.subStepNoun.singular
        let d = abs(t.offset.y) < 1e-12 ? t.offset.x : (abs(t.offset.x) < 1e-12 ? t.offset.y : nil)
        return d.map { "\(noun) 1 at \(ContentTraceFormat.offset.text($0)) px" } ?? "\(noun) 1"
    }

    /// The taps of a pass in kernel order, without a final (flags = 2) record when the decoder kept one.
    func tapsOf(_ pass: TracePass) -> [TraceTap] {
        pass.taps.filter { ($0.extras["flags"] ?? 0) != 2 && ($0.extras["final"] ?? 0) == 0 }
    }

    func fetchPanel(_ pass: TracePass, taps: [TraceTap]) -> FloorFacts {
        let provenance = pass.source.provenance
        var series = [PlotSeries(name: "weights", xs: taps.map { $0.offset.x != 0 || $0.offset.y == 0 ? $0.offset.x : $0.offset.y }, ys: taps.map(\.weight),
                                 style: .stems, role: .primary, provenance: provenance)]
        series.append(PlotSeries(name: "running sum", xs: taps.indices.map(Double.init), ys: taps.map { ContentValues.scalar($0.runningSum) },
                                 style: .points, role: .depth, provenance: provenance))
        let noun = i.cls.subStepNoun
        var numbers = [LabeledValue(id: "count", label: noun.plural.uppercased(), value: .number(Double(taps.count), .integer(noun: CountNoun(noun.singular, noun.plural)), provenance))]
        if pass.truncatedTapCount > 0 {
            numbers.append(LabeledValue(id: "truncated", label: "BEYOND THE RECORD", value: .number(Double(pass.truncatedTapCount), ContentStyle.taps, provenance)))
        }
        numbers.append(LabeledValue(id: "source", label: "SOURCE", value: .words(pass.source == .gpuRecord ? "GPU RECORD" : "CPU RECONSTRUCTION",
                                                                                  spoken: pass.source == .gpuRecord ? "recorded by the GPU" : "reconstructed by BlurCore", provenance)))
        var details: [ContentBlock] = []
        if pass.source == .gpuRecord {
            details.append(.note("These rows are the GPU's own TRACE_PROBE records for the frame on screen.", .live))
        } else {
            details.append(.note("These rows are recomputed by BlurCore in Double; a CPU re-computation is never LIVE.", .computed))
        }
        if taps.contains(where: { $0.quantizedFraction != nil }) {
            details.append(.note("t as requested is COMPUTED; t as the hardware rounds it is MODELED from the sub-texel rule.", .modeled))
        }
        let rule: String? = i.mergesTaps ? "one bilinear fetch at k + b/(a + b) blends taps k and k + 1" : (i.cls == .adaptive ? "w = spatial × range" : nil)
        return FloorFacts(numbers: numbers,
                          figure: .plot(PlotSpec(xAxis: PlotAxis(label: "offset", unit: "px"), yAxis: PlotAxis(label: "weight"), series: series,
                                                 accessibilitySummary: "this pass's fetch weights; the running sum grows as each one lands")),
                          governingRule: rule, details: details)
    }

    func neighbourhoodGrid(_ pass: TracePass) -> TexelGridSpec? {
        guard let out = pass.neighbourhoodOut, out.count == 81 else { return nil }
        return TexelGridSpec(size: 9, origin: PixelPoint(x: pass.pixel.x - 4, y: pass.pixel.y - 4), channel: .luma, values: out.map { ContentValues.scalar($0) },
                             weights: nil, highlighted: [pass.pixel], provenance: pass.source.provenance)
    }

    /// One sub-step per tap (SPEC §6.5): a fetch, sample, tap, iteration, frequency or compare-exchange.
    func subSteps(_ pass: TracePass, taps: [TraceTap]) -> [TraceSubStep] {
        let n = taps.count
        let noun = i.cls.subStepNoun.singular
        let total = NumberStyle.integer().text(Double(n))
        // Recursive classes: contributions below 1 % of the final value are summarised in one row (SPEC §6.5).
        let finalMagnitude = abs(ContentValues.scalar(pass.outputAtProbe))
        var out: [TraceSubStep] = []
        var summarised: [Int] = []
        for (k, tap) in taps.enumerated() {
            if i.cls == .recursive, finalMagnitude > 0, abs(ContentValues.scalar(tap.contribution)) < 0.01 * finalMagnitude, k != n - 1 {
                summarised.append(k); continue
            }
            let index = NumberStyle.integer().text(Double(k + 1))
            let w = ContentTraceFormat.weight.text(tap.weight), v = ContentTraceFormat.value.text(ContentValues.scalar(tap.fetched))
            var completed: String
            switch i.cls {
            case .adaptive:
                let spatial = tap.extras["spatialWeight"].map { NumberStyle.significant(3).text($0) }
                let range = tap.extras["rangeWeight"].map { NumberStyle.significant(3).text($0) }
                if let s = spatial, let r = range {
                    completed = "\(noun) \(index) of \(total): spatial \(s) × range \(r) → w \(w) · v \(v)"
                } else {
                    completed = "\(noun) \(index) of \(total): w \(w) · v \(v)"
                }
            case .rank:
                if let rank = tap.extras["rank"] {
                    completed = "\(noun) \(index) of \(total): v \(v) · rank \(NumberStyle.integer().text(rank))"
                } else {
                    completed = "\(noun) \(index) of \(total): v \(v)"
                }
            case .iterativePDE:
                completed = "\(noun) \(index) of \(total): u \(ContentTraceFormat.value.text(ContentValues.scalar(tap.runningSum)))"
            case .globalFFT:
                completed = "\(noun) \(index) of \(total): H \(w) · X \(v)"
            default:
                completed = "\(noun) \(index) of \(total): w \(w) · v \(v)"
            }
            if tap.dropped { completed += " · dropped at the border" }
            let next: String
            if k + 1 < n {
                let t = taps[k + 1]
                let distance = abs(t.offset.y) < 1e-12 ? t.offset.x : (abs(t.offset.x) < 1e-12 ? t.offset.y : nil)
                if let d = distance {
                    next = "\(noun) \(NumberStyle.integer().text(Double(k + 2))) at \(ContentTraceFormat.offset.text(d)) px"
                } else {
                    next = "\(noun) \(NumberStyle.integer().text(Double(k + 2))) of \(total)"
                }
            } else {
                next = "Pass \(pass.descriptor.name) writes its value"
            }
            let sum = ContentTraceFormat.value.text(ContentValues.scalar(tap.runningSum))
            let highlighted = tap.texels.isEmpty ? [PixelPoint(x: Int(tap.position.x.rounded(.down)), y: Int(tap.position.y.rounded(.down)))] : tap.texels.map(\.texel)
            out.append(TraceSubStep(id: out.count, completed: completed, next: next, runningSum: tap.runningSum, highlighted: highlighted, tapIndex: k,
                                    announcement: "Completed: \(completed). Partial sum \(sum). Next: \(next)."))
        }
        if !summarised.isEmpty {
            let count = NumberStyle.integer().text(Double(summarised.count))
            let last = taps[summarised.last!]
            let firstShown = out.first?.tapIndex.map { "\(noun) \(NumberStyle.integer().text(Double($0 + 1))) of \(total)" }
            out.insert(TraceSubStep(id: 0, completed: "\(count) small contributions summarised", next: firstShown ?? "Pass \(pass.descriptor.name) writes its value",
                                    runningSum: last.runningSum, highlighted: [], tapIndex: nil,
                                    announcement: "Completed: \(count) small contributions summarised."), at: 0)
            out = out.enumerated().map { var s = $0.element; s.id = $0.offset; return s }
        }
        return out
    }

    // MARK: Tier S and Tier 3 lanes

    mutating func systemLaneSteps() {
        let lane = pages[.gpu]
        drafts.append(ContentStepDraft(floor: .algorithm, completed: "Runs in the render server",
                                       panel: FloorFacts(numbers: [], details: lane?.details ?? [])))
        drafts.append(ContentStepDraft(floor: .gpu, completed: "We can measure its output, not follow its fetches",
                                       panel: FloorFacts(details: [.note("SYSTEM INTERNALS · INFERRED", .inferred)])))
    }

    mutating func atlasSteps() {
        drafts.append(ContentStepDraft(floor: .algorithm, completed: "CPU only in this app: no GPU pass exists",
                                       panel: FloorFacts(details: [.note("CPU ONLY IN THIS APP · TIER 3", .computed)])))
    }

    // MARK: Floor 7

    mutating func pixelSteps() {
        let page = pages[.pixels]
        let real = realOutput
        let outValue = real.map { BadgedValue.number(ContentValues.scalar($0.value), ContentStyle.value3, $0.provenance) }
        let inValue = BadgedValue.number(ContentValues.scalar(record.input), ContentStyle.value3, record.passes.first?.source.provenance ?? .computed)
        var panel = FloorFacts(numbers: [LabeledValue(id: "in", label: "IN", value: inValue)])
        if let o = outValue { panel.numbers.append(LabeledValue(id: "out", label: "OUT", value: o)) }
        panel.numbers.append(LabeledValue(id: "cpu", label: "CPU REFERENCE", value: .number(ContentValues.scalar(record.cpuReference), ContentStyle.value4, .computed)))
        if let ulp = record.differenceULP16, let run = i.live.run {
            panel.numbers.append(LabeledValue(id: "ulp", label: "|GPU − CPU|", value: .number(ulp, ContentStyle.ulp, .measured, device: run.device)))
        }
        if let same = record.tracedEqualsUntraced, let run = i.live.run {
            panel.numbers.append(LabeledValue(id: "traced", label: "TRACED = UNTRACED", value: .words(same ? "YES" : "NO", spoken: same ? "bit-identical" : "differs", .measured, device: run.device)))
        }
        panel.figure = page?.figure
        drafts.append(ContentStepDraft(floor: .pixels, completed: outValue.map { "OUT \($0.text) linear" } ?? "OUT not recorded", panel: panel))
        let code = real.map { SRGB.code8(linear: ContentValues.scalar($0.value)) }
        var encodePanel = FloorFacts(governingRule: "code = round(255 · encode(OUT)),  encode = the sRGB curve (IEC 61966-2-1)")
        if let code {
            encodePanel.numbers = [LabeledValue(id: "code", label: "OUT ENCODED", value: .number(Double(code), ContentStyle.code8, .computed))]
        }
        let branches = branchValues().filter { $0.id == "branch-colour" }
        var step = ContentStepDraft(floor: .pixels, completed: code.map { "Encoded \(NumberStyle.integer().text(Double($0)))/255 for the display" } ?? "Nothing to encode",
                                    panel: encodePanel, branchValues: branches)
        step.closingLesson = closingLesson(inValue: inValue, outValue: outValue, code: code, branch: branches.first)
        drafts.append(step)
    }

    func closingLesson(inValue: BadgedValue, outValue: BadgedValue?, code: Int?, branch: LabeledValue?) -> String {
        let out = outValue?.text ?? "—"
        let fetches = NumberStyle.integer().text(i.plan.fetchesPerPixel.rounded())
        let passes = i.plan.passes.count
        let passWords = "\(NumberStyle.integer().text(Double(passes))) \(passes == 1 ? "pass" : "passes")"
        switch i.entry.id.rawValue {
        case "gaussian-blur":
            let typed = ContentSlide.typed(i, toolID: i.context.homeToolID)
            var typedText = typed.value.text
            if typedText.hasPrefix("≈") { typedText.removeFirst() }
            let you: String = { if case .number = typed.kind { return "you typed \(typedText)" }; return "you set the blur" }()
            var lesson = "Seven floors, one pixel: \(you), the GPU fetched \(fetches) times, and the pixel went from \(inValue.text) to \(out)."
            if let code, let b = branch {
                lesson += " The floor that most changed the answer was the one nobody shows: the colour space at the API floor (\(NumberStyle.integer().text(Double(code))) vs \(b.value.text))."
            }
            return lesson
        case "radial-zoom-blur":
            return "Your pixel went from \(inValue.text) to \(out) after \(fetches) samples along the ray through the centre. Zoom blur is (almost exactly) a box along rays: anything made of rays survives, and its dual, spin blur, does the opposite (P21)."
        case "bilateral":
            return "This blur asked every neighbour 'do you look like me?' before averaging. Your pixel went from \(inValue.text) to \(out): the neighbours that looked different were weighted down, and the edge survived."
        case "polygonal-bokeh":
            return "Your pixel was \(inValue.text). It turned \(out) because the light around it was spread evenly in the shape of a hexagon, built from four straight streaks. Set BLADES to 5 and the streak trick stops working: a pentagon is not a sum of line segments."
        default:
            return "Your pixel went from \(inValue.text) to \(out) after \(fetches) fetches in \(passWords)."
        }
    }

    // MARK: Assembly

    func finish() -> [TraceStep] {
        let n = drafts.count
        let total = NumberStyle.integer().text(Double(n))
        let plan = i.plan
        var steps: [TraceStep] = []
        for (j, d) in drafts.enumerated() {
            let following = j + 1 < n ? drafts[j + 1] : nil
            let next: String
            if let first = d.firstNext {
                next = first
            } else if let f = following {
                next = f.firstNext ?? f.completed
            } else {
                next = "Back to Blur2ool"
            }
            let label: String
            if !d.subSteps.isEmpty { label = i.cls.nextLabel }
            else if following == nil { label = "Finish" }
            else if let f = following, !f.subSteps.isEmpty { label = i.cls.nextLabel }
            else if let f = following, f.floor != d.floor { label = "Next floor" }
            else if let f = following, f.passIndex != nil, f.passIndex != d.passIndex { label = "Next pass" }
            else { label = "Next step" }
            var phase = "Step \(NumberStyle.integer().text(Double(j + 1))) / \(total)"
            if let p = d.passIndex, let k = plan.passes.firstIndex(where: { $0.id == p }) {
                let pass = plan.passes[k]
                let kind = pass.kind == .compute ? "compute thread" : (pass.kind == .fragment ? "fragment" : pass.kind.rawValue)
                let direction = pass.name == "H" ? "horizontal" : (pass.name == "V" ? "vertical" : pass.summary)
                phase += " · \(kind) (\(probe.x), \(probe.y)) · pass \(NumberStyle.integer().text(Double(k + 1))) of \(NumberStyle.integer().text(Double(plan.passes.count))) · \(direction)"
            } else {
                phase += " · floor \(d.floor.rawValue) · \(d.floor.title.lowercased())"
            }
            let completed = d.completed
            let announcement = "Completed: \(completed). Next: \(next)."
            steps.append(TraceStep(id: j, floor: d.floor, completed: completed, next: next, primaryLabel: label, subSteps: d.subSteps,
                                   passIndex: d.passIndex, panel: d.panel, branchValues: d.branchValues, phaseLine: phase,
                                   closingLesson: d.closingLesson, announcement: announcement))
        }
        return steps
    }
}
