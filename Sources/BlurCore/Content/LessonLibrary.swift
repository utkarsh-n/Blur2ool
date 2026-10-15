import Foundation

// OWNER: CONTENT-LAYERS. Catalog › Lessons as data (SPEC §8.5; CATALOG §7 with the SPEC §17 truth fixes): the four guided
// descents and the thirty pairs that teach. Each lesson sets specimen, A, B (or a triad), axis, matching rule, view, σ
// and probe, and writes its look-for line into the status row (a BadgedLine: every number badged, review fix E-51).
// Numbers BlurCore can compute from KernelMath are computed here (COMPUTED by construction); the others keep the badge
// and source the research gave them, and claims that are still open read UNVERIFIED in words.
//
// Configurations are resolved against the registry when the library is first read. An entry that is not registered yet
// keeps its catalog id, an empty variant id (meaning "the entry's default variant") and the lesson's σ to be held at
// apply time; `LessonLibrary.unresolved(_:)` lists what is missing so INTEGRATE can re-check once every family is in.

public enum LessonLibrary {
    public static let all: [Lesson] = descents + pairs

    /// What a lesson references that this build does not register (entries, variants, parameters, test images).
    public static func unresolved(_ lesson: Lesson) -> [String] {
        ContentLessonData.specs.first { $0.id == lesson.id }.map(ContentLessonData.unresolved) ?? ["no specification for \(lesson.id)"]
    }

    public static var descents: [Lesson] { ContentLessonData.specs.filter { $0.kind == .guidedDescent }.map(ContentLessonData.lesson) }
    public static var pairs: [Lesson] { ContentLessonData.specs.filter { $0.kind == .pair }.map(ContentLessonData.lesson) }

    /// A lesson whose configurations are re-resolved against the registry now (ENGINE calls this from `apply(lesson)` so
    /// entries registered after the library was first read get their defaults and σ-hold).
    public static func resolved(_ lesson: Lesson) -> Lesson {
        ContentLessonData.specs.first { $0.id == lesson.id }.map(ContentLessonData.lesson) ?? lesson
    }
}

// MARK: - Specification DSL

struct ContentLessonSlot: Sendable {
    var blur: BlurID
    var variant: VariantID? = nil
    /// Per-axis σ to hold through `holdingSigma` (SPEC §8.1); nil keeps the entry's defaults.
    var sigma: Double? = nil
    /// Parameter overrides by key; a key the entry does not declare is matched by its label, else listed as unresolved.
    var overrides: [String: ParameterValue] = [:]
    var colourSpace: ColourSpace? = nil
    var alphaMode: AlphaMode? = nil
}

struct ContentLessonSpec: Sendable {
    var id: String
    var kind: LessonKind
    var title: String
    var setupLine: String
    var specimen: SpecimenID
    var specimenChoices: [String: String] = [:]
    var probe: PixelPoint
    var slots: [ContentLessonSlot]
    var axis: CompareAxis
    var match: MatchRule
    var view: CompareView?
    var lookFor: @Sendable () -> [LabeledValue]
}

enum ContentLessonData {
    static let windowSize = 894

    // MARK: Resolution

    static func lesson(_ s: ContentLessonSpec) -> Lesson {
        let rows = s.lookFor()
        return Lesson(id: s.id, kind: s.kind, title: s.title, setupLine: s.setupLine,
                      configurations: s.slots.map { configuration($0, spec: s) }, axis: s.axis, match: s.match, view: s.view,
                      lookFor: rows, statusLine: statusLine(rows))
    }

    /// "LOOK FOR · MIN H A −0.217 · B −0.0010": every number a badged value, labels plain words.
    static func statusLine(_ rows: [LabeledValue]) -> BadgedLine {
        var segments: [BadgedSegment] = []
        for (n, row) in rows.prefix(4).enumerated() {
            if n > 0 { segments.append(.text("·")) }
            segments.append(row.label.contains(where: \.isNumber) ? .literal(row.label) : .text(row.label))
            segments.append(.value(row.value))
        }
        return BadgedLine(segments)
    }

    static func configuration(_ slot: ContentLessonSlot, spec: ContentLessonSpec) -> RenderConfiguration {
        var settings = SilentSettings.standard
        if let c = slot.colourSpace { settings.colourSpace = c }
        if let a = slot.alphaMode { settings.alphaMode = a }
        var options = SpecimenOptions.standard
        options.choices = spec.specimenChoices
        guard let op = BlurRegistry.op(slot.blur) else {
            var p = ParameterValues()
            if let s = slot.sigma { p["sigma"] = .double(s) }
            for (k, v) in slot.overrides { p[ParameterKey(rawValue: k)] = v }
            return RenderConfiguration(blur: slot.blur, variant: slot.variant ?? VariantID(rawValue: ""), parameters: p, settings: settings,
                                       specimen: spec.specimen, specimenOptions: options, pan: .zero, probe: spec.probe, windowSize: windowSize)
        }
        let entry = op.entry
        var parameters = entry.defaultParameters
        if let s = slot.sigma { parameters = op.holdingSigma(s, current: parameters).parameters }
        for (key, value) in slot.overrides {
            if let spec = match(key, in: entry) { parameters[spec.key] = coerce(value, to: spec) }
        }
        let variant = slot.variant.flatMap { entry.variant($0) != nil ? $0 : nil } ?? entry.defaultVariant
        return RenderConfiguration(blur: slot.blur, variant: variant, parameters: parameters, settings: settings, specimen: spec.specimen,
                                   specimenOptions: options, pan: .zero, probe: spec.probe, windowSize: windowSize)
    }

    /// A lesson key matches a parameter by key, or by its ALL-CAPS label ("passes" → PASSES).
    static func match(_ key: String, in entry: CatalogEntry) -> ParameterSpec? {
        if let s = entry.spec(ParameterKey(rawValue: key)) { return s }
        let wanted = key.uppercased().replacingOccurrences(of: "_", with: " ")
        return entry.parameters.first { $0.label.uppercased() == wanted || $0.label.uppercased().hasPrefix(wanted + " ") }
    }

    /// Choices match an option id or label, case-insensitively; numbers become the spec's own kind.
    static func coerce(_ value: ParameterValue, to spec: ParameterSpec) -> ParameterValue {
        switch (spec.kind, value) {
        case (.choice(let c), .choice(let wanted)):
            let w = wanted.lowercased()
            return .choice(c.options.first { $0.id.lowercased() == w || $0.label.lowercased() == w || $0.label.lowercased().hasPrefix(w) }?.id ?? wanted)
        case (.integer, .double(let d)): return .int(Int(d.rounded()))
        case (.continuous, .int(let n)): return .double(Double(n))
        default: return value
        }
    }

    static func unresolved(_ s: ContentLessonSpec) -> [String] {
        var missing: [String] = []
        if SpecimenRegistry.generator(s.specimen) == nil { missing.append("test image \(s.specimen.rawValue)") }
        for slot in s.slots {
            guard let op = BlurRegistry.op(slot.blur) else { missing.append("entry \(slot.blur.rawValue)"); continue }
            if let v = slot.variant, op.entry.variant(v) == nil { missing.append("variant \(v.rawValue) of \(slot.blur.rawValue)") }
            for key in slot.overrides.keys where match(key, in: op.entry) == nil { missing.append("parameter \(key) of \(slot.blur.rawValue)") }
        }
        return missing
    }

    // MARK: Values

    static func computed(_ v: Double, _ style: NumberStyle, caption: String? = nil) -> BadgedValue { .number(v, style, .computed, caption: caption) }
    /// A number the research computed and this build does not recompute: COMPUTED, with its source.
    static func research(_ v: Double, _ style: NumberStyle, _ source: String, caption: String? = nil) -> BadgedValue {
        .number(v, style, .computed, source: SourceRef(source), caption: caption)
    }
    static func row(_ id: String, _ label: String, _ value: BadgedValue) -> LabeledValue { LabeledValue(id: id, label: label, value: value) }
    static let pct = NumberStyle.significant(3, unit: "%", spokenUnit: "percent")
    static let resp = NumberStyle.significant(3)
    static let px = ContentStyle.px1
    static let p8 = "SPEC §8.5 (CATALOG §7, re-checked)"

    static func minH(_ k: Kernel1D) -> Double { KernelMath.response(k, frequencies: ResponseQuery(samples: 513).frequencies).min() ?? 0 }
    /// Box of the width σ-hold picks: w = nearest odd integer to √(12σ² + 1) (SPEC §8.1).
    static func boxFor(sigma: Double) -> Kernel1D {
        var w = Int((12 * sigma * sigma + 1).squareRoot().rounded())
        if w % 2 == 0 { w += (Double(w) < (12 * sigma * sigma + 1).squareRoot() ? 1 : -1) }
        return KernelMath.box(radius: Swift.max(0, (w - 1) / 2))
    }
    static func tentFor(sigma: Double) -> Kernel1D {
        KernelMath.tent(radius: Swift.max(1, Int(((6 * sigma * sigma + 1).squareRoot() - 1).rounded())))
    }

    // MARK: The library

    static let star: SpecimenID = "siemens-star", city: SpecimenID = "night-city", impulse: SpecimenID = "impulse"
    static let edges: SpecimenID = "step-edges", noisy: SpecimenID = "noisy-step", grid: SpecimenID = "impulse-grid"
    static let starProbe = PixelPoint(x: 404, y: 288), cityProbe = PixelPoint(x: 447, y: 455), centre = PixelPoint(x: 447, y: 447)

    static let specs: [ContentLessonSpec] = descentSpecs + pairSpecs

    static let descentSpecs: [ContentLessonSpec] = [
        ContentLessonSpec(id: "descent-A", kind: .guidedDescent, title: "One pixel through a Gaussian",
                          setupLine: "Step edges, the probe on the dark side of the edge, a Gaussian sampled and cut at three σ, linear light.",
                          specimen: edges, probe: PixelPoint(x: 446, y: 300),
                          slots: [ContentLessonSlot(blur: "gaussian-blur", variant: "gaussian-linear-sampling", sigma: 4,
                                                    overrides: ["truncation": .choice("3"), "discretisation": .choice("sampled")])],
                          axis: .operator, match: .sigma, view: nil) {
            let k = KernelMath.gaussianSampled(sigma: 4)
            return [row("fetches", "FETCHES", computed(Double(2 * KernelMath.linearSampledTable(k).fetchesPerPass), ContentStyle.fetches)),
                    row("out", "OUT", research(0.4500, .decimals(4), "SPEC §5.3 A (fixture)")),
                    row("code", "ENCODED", research(179, ContentStyle.code8, "SPEC §5.3 A (fixture)")),
                    row("branch", "IF sRGB-ENCODED", research(115, ContentStyle.code8, "SPEC §5.3 A (fixture)"))]
        },
        ContentLessonSpec(id: "descent-B", kind: .guidedDescent, title: "Why zoom blur spares a star",
                          setupLine: "The Siemens star centred on the window, a centred zoom, the probe in the middle of a white wedge.",
                          specimen: star, probe: PixelPoint(x: 747, y: 460),
                          slots: [ContentLessonSlot(blur: "radial-zoom-blur", overrides: ["strength": .double(10), "samples": .int(32), "direction": .choice("centred")])],
                          axis: .operator, match: .none, view: nil) {
            [row("streak", "LOCAL STREAK", research(30, px, "SPEC §5.3 B (fixture)")),
             row("spacing", "TAP SPACING", research(0.969, NumberStyle.decimals(3, unit: "px", spokenUnit: "pixels"), "SPEC §5.3 B (fixture)")),
             row("out", "OUT ON THE STAR", research(1.000, .decimals(3), "SPEC §5.3 B (fixture)")),
             row("zone", "OUT ON THE ZONE PLATE", research(0.499, .decimals(3), "SPEC §5.3 B (fixture)"))]
        },
        ContentLessonSpec(id: "descent-C", kind: .guidedDescent, title: "The blur that looks before it averages",
                          setupLine: "A noise-free step, the probe on its bright side, a bilateral filter with a narrow range.",
                          specimen: noisy, specimenChoices: ["noise": "off"], probe: PixelPoint(x: 447, y: 300),
                          slots: [ContentLessonSlot(blur: "bilateral", overrides: ["range": .double(0.10), "space": .double(3.0)])],
                          axis: .operator, match: .none, view: nil) {
            [row("range", "RANGE WEIGHT ACROSS THE STEP", research(0.135, .decimals(3), "SPEC §5.3 C (fixture)")),
             row("far", "FAR-SIDE WEIGHT", research(9.4, pct, "SPEC §5.3 C (fixture)")),
             row("out", "OUT", research(0.581, .decimals(3), "SPEC §5.3 C (fixture)")),
             row("gauss", "GAUSSIAN OUT", research(0.513, .decimals(3), "SPEC §5.3 C (fixture)"))]
        },
        ContentLessonSpec(id: "descent-D", kind: .guidedDescent, title: "Four line blurs make a hexagon",
                          setupLine: "Night City's reference light, a six-bladed hexagon, the probe just below the light inside the hexagon.",
                          specimen: city, probe: cityProbe,
                          slots: [ContentLessonSlot(blur: "polygonal-bokeh", overrides: ["radius": .double(16), "blades": .int(6), "rotation": .double(0), "curvature": .double(0)])],
                          axis: .operator, match: .none, view: nil) {
            let r = 16.0
            return [row("area", "HEXAGON AREA", computed(3 * 3.0.squareRoot() / 2 * r * r, NumberStyle.decimals(1, unit: "px²", spokenUnit: "square pixels"))),
                    row("sigma", "PER-AXIS σ", computed((5.0 / 24).squareRoot() * r, ContentStyle.px2)),
                    row("fetches", "FETCHES", research(64, ContentStyle.fetches, "SPEC §5.3 D (fixture)")),
                    row("out", "OUT", research(0.1504, .decimals(4), "SPEC §5.3 D (fixture)"))]
        },
    ]

    static let pairSpecs: [ContentLessonSpec] = [
        ContentLessonSpec(id: "P1", kind: .pair, title: "Box vs Gaussian at equal σ", setupLine: "Siemens star; box against Gaussian, σ held; wipe.",
                          specimen: star, probe: starProbe, slots: [.init(blur: "box-blur", sigma: 4), .init(blur: "gaussian-blur", sigma: 4)],
                          axis: .operator, match: .sigma, view: .wipe) {
            [row("boxMin", "MIN H BOX (AS RUN)", computed(minH(boxFor(sigma: 4)), resp)),
             row("gaussMin", "MIN H GAUSSIAN", .words("H > 0 (CONTINUOUS)", spoken: "positive everywhere, continuous", .computed))]
        },
        ContentLessonSpec(id: "P2", kind: .pair, title: "Box vs tent vs Gaussian", setupLine: "Siemens star; three blurs at one σ; line-up.",
                          specimen: star, probe: starProbe,
                          slots: [.init(blur: "box-blur", sigma: 4), .init(blur: "tent-blur", sigma: 4), .init(blur: "gaussian-blur", sigma: 4)],
                          axis: .operator, match: .sigma, view: .lineUp) {
            [row("box", "MIN H BOX (AS RUN)", computed(minH(boxFor(sigma: 4)), resp)),
             row("tent", "MIN H TENT", computed(Swift.max(0, minH(tentFor(sigma: 4))), resp, caption: "ZEROS, NO INVERSION")),
             row("gauss", "MIN H GAUSSIAN", .words("H > 0 (CONTINUOUS)", spoken: "positive everywhere, continuous", .computed))]
        },
        ContentLessonSpec(id: "P3", kind: .pair, title: "How fast repeated boxes become a bell", setupLine: "Impulse; the iterated box with one, two, three and four passes; line-up.",
                          specimen: impulse, probe: cityProbe,
                          slots: (1...4).map { ContentLessonSlot(blur: "iterated-box", sigma: 4, overrides: ["passes": .int($0)]) },
                          axis: .operator, match: .sigma, view: .lineUp) {
            [row("e1", "SHAPE ERROR · ONE PASS", research(38, pct, p8, caption: "RELATIVE L2 TO THE GAUSSIAN")),
             row("e2", "SHAPE ERROR · TWO PASSES", research(8.8, pct, p8)),
             row("e3", "SHAPE ERROR · THREE PASSES", research(4.8, pct, p8)),
             row("e4", "SHAPE ERROR · FOUR PASSES", research(3.4, pct, p8)),
             row("kurt", "EXCESS KURTOSIS · THREE PASSES", computed(-1.2 / 3, ContentStyle.kurtosis)),
             row("discrete", "DISCRETE VALUES AT THE LESSON'S WIDTH", .unverified("discrete shape error"))]
        },
        ContentLessonSpec(id: "P4", kind: .pair, title: "The same Gaussian in one pass or two", setupLine: "Night City; the 2-D gather against the separable passes; difference ×256.",
                          specimen: city, probe: cityProbe,
                          slots: [.init(blur: "gaussian-blur", variant: "gaussian-2d-direct", sigma: 8), .init(blur: "gaussian-blur", variant: "gaussian-separable", sigma: 8)],
                          axis: .implementation, match: .none, view: .difference256) {
            let taps = Double(KernelMath.gaussianSampled(sigma: 8).tapCount)
            return [row("direct", "2-D TAPS", computed(taps * taps, ContentStyle.taps)), row("sep", "SEPARABLE TAPS", computed(2 * taps, ContentStyle.taps)),
                    row("lsb", "DIFFERENCE", research(1, ContentStyle.lsb, p8, caption: "AT MOST"))]
        },
        ContentLessonSpec(id: "P5", kind: .pair, title: "What bilinear pairs cost", setupLine: "Night City; separable against linear-sampled at the same σ; difference ×256.",
                          specimen: city, probe: cityProbe,
                          slots: [.init(blur: "gaussian-blur", variant: "gaussian-separable", sigma: 10), .init(blur: "gaussian-blur", variant: "gaussian-linear-sampling", sigma: 10)],
                          axis: .implementation, match: .none, view: .difference256) {
            let k = KernelMath.gaussianSampled(sigma: 10)
            return [row("sep", "FETCHES PER PASS · SEPARABLE", computed(Double(k.tapCount), ContentStyle.fetches)),
                    row("lin", "FETCHES PER PASS · LINEAR-SAMPLED", computed(Double(KernelMath.linearSampledTable(k).fetchesPerPass), ContentStyle.fetches)),
                    row("diff", "DIFFERENCE ON THIS PHONE", .notYetMeasured(unit: "LSB"))]
        },
        ContentLessonSpec(id: "P6", kind: .pair, title: "Kawase's hollow centre", setupLine: "Night City; Kawase against the Gaussian, σ held; wipe.",
                          specimen: city, probe: cityProbe, slots: [.init(blur: "kawase-blur", sigma: 5.34), .init(blur: "gaussian-blur", sigma: 5.34)],
                          axis: .operator, match: .sigma, view: .wipe) {
            [row("centre", "CENTRE WEIGHT · KAWASE", research(0.0645, .decimals(4), p8)), row("gcentre", "CENTRE WEIGHT · GAUSSIAN", research(0.0674, .decimals(4), p8)),
             row("min", "MIN H · KAWASE", research(-0.047, resp, p8)), row("fetches", "FETCHES · KAWASE", research(20, ContentStyle.fetches, p8)),
             row("gfetches", "FETCHES · GAUSSIAN", research(38, ContentStyle.fetches, p8))]
        },
        ContentLessonSpec(id: "P7", kind: .pair, title: "Three pyramids and a moving light", setupLine: "A moving point light; mip chain, Call of Duty's taps and dual Kawase; pan to see them snap or shimmer.",
                          specimen: impulse, probe: cityProbe,
                          slots: [.init(blur: "pyramid-blur", variant: "mip-chain"), .init(blur: "pyramid-blur", variant: "cod-13tap"), .init(blur: "dual-kawase")],
                          axis: .operator, match: .none, view: .lineUp) {
            [row("snap", "MIP CHAIN SNAP", research(7.5, NumberStyle.decimals(1, unit: "px", spokenUnit: "pixels"), p8, caption: "UP TO ± AT FOUR LEVELS")),
             row("cod", "SHIFT VARIANCE · THIRTEEN TAPS", research(2.3, pct, p8, caption: "AT MOST")),
             row("dualLow", "SHIFT VARIANCE · DUAL KAWASE FROM", research(3.7, pct, p8)), row("dualHigh", "SHIFT VARIANCE · DUAL KAWASE TO", research(8.5, pct, p8))]
        },
        ContentLessonSpec(id: "P8", kind: .pair, title: "The blur that erases a checkerboard", setupLine: "A one-pixel checkerboard; binomial against Gaussian at small σ; wipe and loupe.",
                          specimen: "checkerboard", specimenChoices: ["period": "2"], probe: centre,
                          slots: [.init(blur: "binomial-blur", sigma: 1), .init(blur: "gaussian-blur", sigma: 1)], axis: .operator, match: .sigma, view: .wipe) {
            let b = KernelMath.response(KernelMath.binomial(order: 4), frequencies: [0.5]).first ?? 0
            let g = KernelMath.response(KernelMath.gaussianSampled(sigma: 1), frequencies: [0.5]).first ?? 0
            return [row("binomial", "LEFT AT NYQUIST · BINOMIAL", computed(abs(b) < 1e-12 ? 0 : b * 100, pct)),
                    row("gauss", "LEFT AT NYQUIST · SAMPLED GAUSSIAN", computed(g * 100, pct))]
        },
        ContentLessonSpec(id: "P9", kind: .pair, title: "When a sampled Gaussian forgets its σ", setupLine: "Impulse; sampled against Lindeberg's discrete Gaussian at a sub-pixel σ.",
                          specimen: impulse, probe: centre,
                          slots: [.init(blur: "gaussian-blur", sigma: 0.3, overrides: ["discretisation": .choice("sampled")]),
                                  .init(blur: "gaussian-blur", sigma: 0.3, overrides: ["discretisation": .choice("lindeberg")])],
                          axis: .implementation, match: .none, view: .wipe) {
            [row("sampled", "TRUE σ · SAMPLED", computed(KernelMath.gaussianSampled(sigma: 0.3).sigma, NumberStyle.decimals(3, unit: "px", spokenUnit: "pixels"))),
             row("lindeberg", "TRUE σ · LINDEBERG", computed(KernelMath.gaussianLindeberg(sigma: 0.3).sigma, NumberStyle.decimals(3, unit: "px", spokenUnit: "pixels")))]
        },
        ContentLessonSpec(id: "P10", kind: .pair, title: "The recursive Gaussian's long tails", setupLine: "An HDR light on a log display and the bar at the border; IIR against the Gaussian.",
                          specimen: impulse, specimenChoices: ["intensity": "100"], probe: cityProbe,
                          slots: [.init(blur: "iir-gaussian", sigma: 5), .init(blur: "gaussian-blur", sigma: 5)], axis: .operator, match: .sigma, view: .wipe) {
            [row("moment", "MOMENT σ AT NOMINAL FIVE", research(5.56, ContentStyle.px2, p8, caption: "ELEVEN PERCENT WIDE")),
             row("tails", "TAILS", .words("EXPONENTIAL", spoken: "exponential tails", .computed))]
        },
        ContentLessonSpec(id: "P11", kind: .pair, title: "Disc vs hexagon vs Gaussian", setupLine: "Night City; three bokeh shapes at one σ; line-up.",
                          specimen: city, probe: cityProbe,
                          slots: [.init(blur: "disc-blur", sigma: 8), .init(blur: "polygonal-bokeh", sigma: 8), .init(blur: "gaussian-blur", sigma: 8)],
                          axis: .operator, match: .sigma, view: .lineUp) {
            [row("disc", "MIN H · DISC", research(-0.132, resp, p8, caption: "ROUND INVERSION RINGS")),
             row("where", "AT ρ · R", research(0.817, .decimals(3), p8)),
             row("hex", "HEXAGON", .words("SIX-FOLD ZEROS", spoken: "six-fold zeros and straight edges", .computed)),
             row("gauss", "GAUSSIAN", .words("SOFT BALLS", spoken: "soft balls, no rings", .computed))]
        },
        ContentLessonSpec(id: "P12", kind: .pair, title: "Faking a disc with complex numbers", setupLine: "One HDR light; the exact disc against one and two complex components and the stochastic sampler.",
                          specimen: impulse, specimenChoices: ["intensity": "100"], probe: cityProbe,
                          slots: [.init(blur: "disc-blur"), .init(blur: "disc-blur", variant: "circular-separable-bokeh", overrides: ["components": .int(1)]),
                                  .init(blur: "disc-blur", variant: "circular-separable-bokeh", overrides: ["components": .int(2)]),
                                  .init(blur: "disc-blur", variant: "stochastic-bokeh")],
                          axis: .implementation, match: .none, view: .wipe) {
            [row("one", "RIPPLE · ONE COMPONENT", research(23, pct, p8, caption: "±")), row("two", "RIPPLE · TWO COMPONENTS", research(7.6, pct, p8, caption: "±"))]
        },
        ContentLessonSpec(id: "P13", kind: .pair, title: "The blur that respects edges", setupLine: "Noisy steps; bilateral against Gaussian, spatial σ held; wipe.",
                          specimen: noisy, probe: PixelPoint(x: 447, y: 300), slots: [.init(blur: "bilateral", sigma: 3), .init(blur: "gaussian-blur", sigma: 3)],
                          axis: .operator, match: .sigma, view: .wipe) {
            [row("far", "FAR-SIDE WEIGHT · BILATERAL", research(9.4, pct, p8)), row("gfar", "FAR-SIDE WEIGHT · GAUSSIAN", research(43.3, pct, p8)),
             row("out", "OUT · BILATERAL", research(0.581, .decimals(3), p8)), row("gout", "OUT · GAUSSIAN", research(0.513, .decimals(3), p8))]
        },
        ContentLessonSpec(id: "P14", kind: .pair, title: "Median vs bilateral vs Gaussian on salt and pepper", setupLine: "Text with salt-and-pepper noise; three filters; line-up.",
                          specimen: "text", specimenChoices: ["noise": "salt-and-pepper"], probe: centre,
                          slots: [.init(blur: "median"), .init(blur: "bilateral", sigma: 1), .init(blur: "gaussian-blur", sigma: 1)],
                          axis: .operator, match: .none, view: .lineUp) {
            [row("median", "MAX ERROR · MEDIAN", research(0, .decimals(3), p8)),
             row("bilateral", "BILATERAL", .words("IMPULSES KEPT", spoken: "impulses kept", .computed)),
             row("gauss", "MAX ERROR · GAUSSIAN", research(0.183, .decimals(3), p8))]
        },
        ContentLessonSpec(id: "P15", kind: .pair, title: "Gradient reversal, and how the guided filter avoids it", setupLine: "A noisy step with detail boosted; bilateral against guided; wipe.",
                          specimen: noisy, probe: PixelPoint(x: 447, y: 300),
                          slots: [.init(blur: "bilateral", overrides: ["detail boost": .int(4)]), .init(blur: "guided", overrides: ["detail boost": .int(4)])],
                          axis: .operator, match: .none, view: .wipe) {
            [row("bilateral", "BILATERAL", .words("REVERSED GRADIENT", spoken: "reversed gradient", .computed)),
             row("guided", "GUIDED", .words("NO REVERSAL", spoken: "no reversal", .computed))]
        },
        ContentLessonSpec(id: "P16", kind: .pair, title: "Diffusion is a Gaussian, until the step is too big", setupLine: "Impulse over time; the heat equation against the Gaussian; then a quarter step on a checkerboard.",
                          specimen: impulse, probe: cityProbe,
                          slots: [.init(blur: "heat-equation", overrides: ["time": .double(8), "lambda": .choice("0.125")]), .init(blur: "gaussian-blur", sigma: 4)],
                          axis: .operator, match: .sigma, view: .wipe) {
            [1.0, 2, 4.5, 8, 12.5].enumerated().map { n, t in
                row("t\(n)", "σ AT t = " + NumberStyle.decimals(1).text(t), computed((2 * t).squareRoot(), NumberStyle.decimals(4, unit: "px", spokenUnit: "pixels")))
            } + [row("quarter", "AT λ = ¼", .words("CHECKERBOARD NEVER FADES", spoken: "a one pixel checkerboard flips sign every step and never fades", .computed))]
        },
        ContentLessonSpec(id: "P17", kind: .pair, title: "Diffusion that stops at edges", setupLine: "A noisy step and a ramp; heat against Perona–Malik; the TV page shows a third way.",
                          specimen: "ramp", probe: centre, slots: [.init(blur: "heat-equation"), .init(blur: "perona-malik")], axis: .operator, match: .none, view: .wipe) {
            [row("heat", "HEAT", .words("BLURS THE STEP", spoken: "blurs the step", .computed)),
             row("pm", "PERONA–MALIK", .words("KEEPS THE STEP · TERRACES THE RAMP", spoken: "keeps the step and terraces the ramp", .computed)),
             row("tv", "TV DISC CONTRAST LOSS", .words("TWICE λ OVER R", spoken: "two lambda over R", .computed))]
        },
        ContentLessonSpec(id: "P18", kind: .pair, title: "The colour space decides the grey", setupLine: "One-pixel stripes; the same Gaussian in linear light and in sRGB-encoded values.",
                          specimen: "stripes", probe: centre,
                          slots: [.init(blur: "gaussian-blur", sigma: 4), .init(blur: "gaussian-blur", sigma: 4, colourSpace: .srgbEncoded)],
                          axis: .space, match: .none, view: .wipe) {
            [row("linear", "ENCODED GREY · LINEAR BLUR", computed(SRGB.encode(0.5), .decimals(3))),
             row("srgb", "ENCODED GREY · sRGB BLUR", computed(0.5, .decimals(3)))]
        },
        ContentLessonSpec(id: "P19", kind: .pair, title: "Dark fringes from straight alpha", setupLine: "A red disc on transparency over white; premultiplied against straight alpha; composited in linear light.",
                          specimen: "alpha-shape", probe: PixelPoint(x: 647, y: 447),
                          slots: [.init(blur: "gaussian-blur", sigma: 4), .init(blur: "gaussian-blur", sigma: 4, alphaMode: .straight)],
                          axis: .space, match: .none, view: .wipe) {
            [row("pre", "RED AT THE RIM · PREMULTIPLIED", research(255, ContentStyle.code8, p8)), row("str", "RED AT THE RIM · STRAIGHT", research(225, ContentStyle.code8, p8)),
             row("preEnc", "RED · ENCODED COMPOSITE · PREMULTIPLIED", research(255, ContentStyle.code8, p8)), row("strEnc", "RED · ENCODED COMPOSITE · STRAIGHT", research(191, ContentStyle.code8, p8))]
        },
        ContentLessonSpec(id: "P20", kind: .pair, title: "Hard streaks vs soft streaks", setupLine: "The impulse grid; box motion against a directional Gaussian; wipe.",
                          specimen: grid, probe: PixelPoint(x: 455, y: 447), slots: [.init(blur: "linear-motion-blur", sigma: 6), .init(blur: "anisotropic-gaussian", sigma: 6)],
                          axis: .operator, match: .sigma, view: .wipe) {
            [row("box", "BOX MOTION", .words("HARD ENDS · ZERO LINES", spoken: "hard-ended streaks and zero lines", .computed)),
             row("gauss", "DIRECTIONAL GAUSSIAN", .words("SOFT ENDS · NO ZEROS", spoken: "soft ends and no zeros", .computed)),
             row("ci", "CIMOTIONBLUR", .words("GAUSSIAN WEIGHTS", spoken: "Core Image's motion blur has Gaussian weights", .measured,
                                                device: ContentResearch.mac, caption: "MEASURED ON THE RESEARCH MAC"))]
        },
        ContentLessonSpec(id: "P21", kind: .pair, title: "Zoom and spin are duals", setupLine: "The centred star, then the zone plate; zoom against spin about the same centre.",
                          specimen: star, probe: PixelPoint(x: 747, y: 460), slots: [.init(blur: "radial-zoom-blur"), .init(blur: "spin-blur")],
                          axis: .operator, match: .none, view: .wipe) {
            [row("zoom", "ZOOM ON THE STAR", .words("UNTOUCHED", spoken: "the star is untouched", .computed)),
             row("spin", "SPIN · MIN OF THE ARC AVERAGE", research(-0.2172, .decimals(4), p8, caption: "CONTINUOUS")),
             row("where", "AT PERIODS", research(1.430, .decimals(3), p8)),
             row("discrete", "THE DISCRETE SAMPLED VALUE", .unverified("discrete spin minimum"))]
        },
        ContentLessonSpec(id: "P22", kind: .pair, title: "Two ways to blur motion", setupLine: "The moving disc; velocity buffer against frame accumulation; wipe.",
                          specimen: "scene-motion", probe: centre, slots: [.init(blur: "velocity-buffer-motion-blur"), .init(blur: "temporal-accumulation")],
                          axis: .operator, match: .none, view: .wipe) {
            [row("acc", "ACCUMULATION", .words("EXACT · GHOSTS AT LOW N", spoken: "exact, but ghosts at low sub-frame counts", .computed)),
             row("vel", "VELOCITY BUFFER", .words("UNDER-BLURS WHERE MOTIONS CONFLICT", spoken: "under-blurs where motions conflict", .computed))]
        },
        ContentLessonSpec(id: "P23", kind: .pair, title: "Blending blurs is not blurring", setupLine: "A ramp mask over the impulse grid; mip mix against the per-pixel Gaussian.",
                          specimen: grid, probe: PixelPoint(x: 455, y: 447),
                          slots: [.init(blur: "variable-progressive-blur", overrides: ["algorithm": .choice("mip mix")]), .init(blur: "variable-progressive-blur")],
                          axis: .implementation, match: .none, view: .wipe) {
            [row("wide", "NAIVE BLEND TOO WIDE AT HALFWAY", research(11.8, pct, p8)),
             row("kurt", "EXCESS KURTOSIS · VARIANCE-MATCHED MIX", research(1.5, ContentStyle.kurtosis, p8, caption: "GAUSSIAN IS ZERO"))]
        },
        ContentLessonSpec(id: "P24", kind: .pair, title: "Frosted glass is a blur only on average", setupLine: "Step edge and text; one realization, many, and the box they converge to.",
                          specimen: edges, probe: PixelPoint(x: 446, y: 300),
                          slots: [.init(blur: "frosted-glass-noise", overrides: ["realizations": .int(1)]), .init(blur: "frosted-glass-noise", overrides: ["realizations": .int(64)]),
                                  .init(blur: "box-blur", sigma: 2.58)],
                          axis: .operator, match: .none, view: .wipe) {
            [row("one", "ENERGY ABOVE A QUARTER C/PX · ONE", research(8.4, pct, p8)), row("box", "ENERGY ABOVE A QUARTER C/PX · BOX", research(2.0, pct, p8))]
        },
        ContentLessonSpec(id: "P25", kind: .pair, title: "Blurring, sharpening and undoing a blur", setupLine: "Blurred text; Gaussian, unsharp mask and Wiener deconvolution; line-up.",
                          specimen: "text", probe: centre,
                          slots: [.init(blur: "gaussian-blur", sigma: 1), .init(blur: "unsharp-mask"), .init(blur: "wiener-deconvolution")],
                          axis: .operator, match: .none, view: .lineUp) {
            [row("inverse", "GAIN AT NYQUIST · INVERSE FILTER", research(139, NumberStyle.decimals(0), p8, caption: "CONTINUOUS BLUR")),
             row("wiener", "GAIN AT NYQUIST · WIENER DEFAULT", research(0.72, .decimals(2), p8)),
             row("min", "GAIN AT NYQUIST · WIENER AT ITS SMALLEST K", research(47, NumberStyle.decimals(0), p8)),
             row("sampled", "INVERSE FILTER · THE APP'S SAMPLED KERNEL", research(71, NumberStyle.decimals(0), p8))]
        },
        ContentLessonSpec(id: "P26", kind: .pair, title: "SwiftUI's blur against ours", setupLine: "Impulse and step under a radius sweep; SwiftUI's blur against our Gaussian and the iterated box; Apple axis.",
                          specimen: edges, probe: PixelPoint(x: 446, y: 300),
                          slots: [.init(blur: "gaussian-blur", sigma: 12), .init(blur: "swiftui-layer-blur"), .init(blur: "iterated-box", sigma: 12, overrides: ["passes": .int(3)])],
                          axis: .apple, match: .sigma, view: .wipe) {
            [row("small", "σ PER RADIUS PX · SMALL RADII", ContentResearch.measuredOnMac(1.0, .decimals(2), source: ContentResearch.calibrationSource, offscreen: true)),
             row("large", "σ PER RADIUS PX · LARGE RADII", ContentResearch.measuredOnMac(0.90, .decimals(2), source: ContentResearch.calibrationSource, offscreen: true)),
             row("kurt", "EXCESS KURTOSIS", ContentResearch.measuredOnMac(-0.45, ContentStyle.kurtosis, source: ContentResearch.calibrationSource, offscreen: true)),
             row("model", "CLOSEST MODEL", .words("BOX³", spoken: "box cubed", .inferred)),
             row("phone", "ON THIS PHONE", ContentOffscreen.mark(.notYetMeasured()))]
        },
        ContentLessonSpec(id: "P27", kind: .pair, title: "The same ten in every tool's shadow", setupLine: "A square and a star on transparency; each tool's convention for the number ten.",
                          specimen: "alpha-shape", specimenChoices: ["shape": "square-and-star"], probe: PixelPoint(x: 647, y: 447),
                          slots: [.init(blur: "drop-shadow", overrides: ["convention": .choice("css box-shadow")]), .init(blur: "drop-shadow", overrides: ["convention": .choice("css drop-shadow()")])],
                          axis: .operator, match: .none, view: .wipe) {
            [row("box", "σ · CSS BOX-SHADOW", .number(5, px, .reference, source: SourceRef("CSS Backgrounds and Borders Level 3 (σ = blur radius / 2)"))),
             row("drop", "σ · CSS DROP-SHADOW()", .number(10, px, .reference, source: SourceRef("CSS Filter Effects Level 1 (σ = value)"))),
             row("figma", "σ · FIGMA", .number(4.4, px, .measured, qualifiers: .notThisDevice, source: SourceRef("third-party measurement (STACK §4)"),
                                              device: ContentResearch.mac, caption: "THIRD-PARTY MEASUREMENT")),
             row("calayer", "σ · CALAYER SHADOW RADIUS", .words("SOURCES DISAGREE", spoken: "the sources disagree until this phone measures it", .measured,
                                                                 qualifiers: .sourcesDisagree, device: ContentResearch.mac, caption: "SOURCES DISAGREE"))]
        },
        ContentLessonSpec(id: "P28", kind: .pair, title: "Material, glass and a CSS model", setupLine: "The stripes, text and split backdrop; Apple's material against Liquid Glass and our CSS model.",
                          specimen: "material-backdrop", probe: PixelPoint(x: 447, y: 700),
                          slots: [.init(blur: "apple-uiblureffect"), .init(blur: "liquid-glass"), .init(blur: "css-backdrop-filter")],
                          axis: .apple, match: .none, view: .wipe) {
            [row("material", "MATERIALS", .words("MOSTLY COLOUR STAGES", spoken: "mostly colour stages", .inferred)),
             row("glass", "LIQUID GLASS", .words("MOSTLY REFRACTION", spoken: "mostly refraction", .inferred)),
             row("css", "CSS BACKDROP", .words("σ = TYPED VALUE · sRGB · MIRRORED", spoken: "sigma equals the typed value, in sRGB, with mirrored edges", .reference,
                                                 source: SourceRef("CSS Filter Effects Level 2 (backdrop-filter)")))]
        },
        ContentLessonSpec(id: "P29", kind: .pair, title: "Bloom vs Gaussian vs Lorentzian", setupLine: "Night City at several exposures; three ways to spread light; line-up.",
                          specimen: city, probe: cityProbe,
                          slots: [.init(blur: "bloom"), .init(blur: "gaussian-blur", sigma: 8), .init(blur: "lorentzian-blur")],
                          axis: .operator, match: .none, view: .lineUp) {
            [row("gauss", "GAUSSIAN", .words("DIMS THE LIGHTS", spoken: "dims the lights", .computed)),
             row("slope", "BLOOM TAIL SLOPE", research(-2.0, .decimals(1), p8, caption: "LOG–LOG")),
             row("lorentz", "LORENTZIAN", .words("LIFTS THE BLACK LEVEL", spoken: "lifts the black level", .computed))]
        },
        ContentLessonSpec(id: "P30", kind: .pair, title: "Median vs dilate vs erode", setupLine: "Night City and text; a rank filter and two morphology operations; line-up.",
                          specimen: city, probe: cityProbe,
                          slots: [.init(blur: "median"), .init(blur: "morphology", overrides: ["operation": .choice("dilate")]), .init(blur: "morphology", overrides: ["operation": .choice("erode")])],
                          axis: .operator, match: .none, view: .lineUp) {
            [row("median", "MEDIAN", .words("EDGES STAY IN PLACE", spoken: "edges stay in place", .computed)),
             row("dilate", "DILATE", .words("LIGHTS GROW INTO CRISP DISCS", spoken: "lights grow into crisp discs", .computed)),
             row("erode", "ERODE", .words("LIGHTS SHRINK", spoken: "lights shrink", .computed))]
        },
    ]
}
