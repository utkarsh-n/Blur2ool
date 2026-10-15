import Foundation

// OWNER: CONTENT-LAYERS. Floor templates 1–3 (SPEC §5.1 SLIDE, API, MATH; §5.2 per class).

enum ContentFloorTemplates {

    // MARK: Floor 1 · SLIDE

    static func slide(_ i: ContentPageInputs) -> ContentFloorDraft {
        let conventions = i.tools.all
        let home = i.context.homeToolID
        let ids = [home] + conventions.map(\.id).filter { $0 != home }
        let homeName = ContentValues.toolName(home, conventions: conventions)
        var rows: [LabeledValue] = []
        var anyOffered = false
        for id in ids {
            let typed = ContentSlide.typed(i, toolID: id)
            let name = ContentValues.toolName(id, conventions: conventions).uppercased()
            var value = typed.value
            switch typed.kind {
            case .notOffered:
                value = BadgedValue(value: nil, text: "NOT OFFERED", provenance: nil, spoken: "not offered in \(name.lowercased())")
            case .unverified:
                value = .unverified("\(name.lowercased()) mapping")
            case .number:
                anyOffered = true
                if typed.sigmaMatchedOnly {
                    value.caption = ContentToolKernels.addCaption(value.caption, ContentToolKernels.sameSigmaCaption)
                    if !value.spoken.lowercased().contains("different kernel") && !value.spoken.lowercased().contains("shape differs") {
                        value.spoken += ", same sigma, different kernel"
                    }
                }
            case .words:
                anyOffered = true
            }
            rows.append(LabeledValue(id: "tool-" + id, label: name, value: value))
        }
        var numbers = rows
        if var first = numbers.first {
            first.id = "you-type"
            first.label = "YOU TYPE · " + homeName.uppercased()
            numbers[0] = first
        }
        let homeConvention = conventions.first { $0.id == home }
        var details: [ContentBlock] = []
        // Reverse mode: the same typed number in every tool (STACK §8, JD G18).
        let typedHome: Double = {
            if case .number(let n) = ContentSlide.typed(i, toolID: home).kind { return n }
            return 10
        }()
        var reverse: [LabeledValue] = [LabeledValue(id: "typed", label: "YOU TYPED", value: .input(typedHome, .decimals(1)))]
        for id in ids {
            let law = ContentOffscreen.isSwiftUITool(id) ? i.swiftUILaw : nil
            var v = i.tools.sigmaPx(toolID: id, blur: i.entry.id, typed: typedHome, displayScale: i.scale, measuredLaw: law)
            if ContentOffscreen.isSwiftUITool(id) && v.value != nil { v = ContentOffscreen.mark(v) }
            reverse.append(LabeledValue(id: "reverse-" + id, label: ContentValues.toolName(id, conventions: conventions).uppercased() + " · σ", value: v))
        }
        details.append(.disclosure(title: "You typed ⇄ what you get: the same number in every tool", blocks: [.values(reverse)]))
        if !conventions.isEmpty {
            let controls = conventions.map { "\($0.toolName): \($0.controlName)" }.joined(separator: "\n")
            let laws: [ContentBlock] = conventions.map { c in
                .note("\(c.toolName): \(c.lawDescription ?? "the law is UNVERIFIED")", c.provenance)
            }
            details.append(.disclosure(title: "The conventions table", blocks: [.code(CodeBlock(language: "text", text: controls))] + laws
                                       + [.sources(conventions.map(\.source))]))
        }
        details.append(.equation("σ px = typed value × the tool's law × display scale \(NumberStyle.decimals(0).text(i.scale)) (pt → px)"))
        if !anyOffered {
            details.append(.paragraph("No design tool offers this blur. It lives in engines, libraries and papers:"))
            details.append(.note(i.entry.card.usedIn.text, i.entry.card.usedIn.provenance))
        }
        details.append(.sources([SourceRef(ContentResearch.stackSource)] + (homeConvention.map { [$0.source] } ?? [])))
        let rule = homeConvention?.lawDescription.map { "\(homeName): \($0)" } ?? "σ px = typed value × the tool's law × display scale"
        var line = "IN THIS APP · Typed values convert BlurCore's per-axis σ through each tool's published (REFERENCE) or measured (MEASURED) law; tools whose law is unknown read UNVERIFIED instead of a number"
        line += ContentOffscreen.isSwiftUITool(home) ? "; SwiftUI numbers come from offscreen ImageRenderer fits." : "."
        return ContentFloorDraft(numbers: numbers, figure: .toolBars(ToolBarsSpec(rows: rows, homeToolID: home, reverseMode: false)),
                                 governingRule: rule, details: details, inThisApp: line, dominantFallback: [.reference])
    }

    // MARK: Floor 2 · API

    static func api(_ i: ContentPageInputs) -> ContentFloorDraft {
        let e = i.entry
        var numbers: [LabeledValue] = []
        if let spec = i.primarySpec, let v = i.primaryValue {
            if spec.unit == .pt {
                numbers.append(LabeledValue(id: "primary-px", label: spec.label + " · PX",
                                            value: .number(v * i.scale, ContentStyle.px1, .computed)))
                numbers.append(LabeledValue(id: "primary-pt", label: spec.label + " · PT", value: .input(v, spec.numberStyle)))
            } else {
                numbers.append(LabeledValue(id: "primary", label: spec.unitLine, value: .number(v, spec.numberStyle, .computed)))
                if spec.unit == .px {
                    numbers.append(LabeledValue(id: "primary-pt", label: spec.label + " · PT AT THIS SCALE",
                                                value: .number(v / Swift.max(i.scale, 1e-9), ContentStyle.pt2, .computed)))
                }
            }
        }
        numbers.append(LabeledValue(id: "colour", label: "COLOUR SPACE", value: .words(ContentValues.words(i.settings.colourSpace))))
        numbers.append(LabeledValue(id: "edges", label: "EDGES", value: .words(ContentValues.words(i.settings.edgeMode))))
        numbers.append(LabeledValue(id: "alpha", label: "ALPHA", value: .words(ContentValues.words(i.settings.alphaMode))))
        // The API's measured law: this phone's calibration of a twin (MEASURED · OFFSCREEN for SwiftUI), else precision.
        let measuredTwin = e.appleTwins.compactMap { twin in twin.subject.flatMap { i.live.calibration($0) }.map { (twin, $0) } }.first
        if let (twin, result) = measuredTwin {
            var v = BadgedValue.number(result.fit.sigmaPerParameterPixel, ContentStyle.ratio, .measured, device: result.device,
                                       caption: twin.id.uppercased())
            if ContentOffscreen.isSwiftUIDerived(result) { v = ContentOffscreen.mark(v) }
            numbers.append(LabeledValue(id: "law", label: "σ PER PARAMETER PX", value: v))
        } else {
            numbers.append(LabeledValue(id: "precision", label: "ACCUMULATE", value: .words(ContentValues.words(i.settings.accumulator))))
        }

        var code = "// Blur2ool's own call: every argument in its own unit\n"
        code += "b2ool.\(swiftName(e.id.rawValue))(\n"
        for spec in e.parameters where spec.scope == .blur {
            code += "    \(swiftName(spec.key.rawValue)): \(literal(i.request.parameters[spec.key] ?? spec.defaultValue, spec)),\n"
        }
        code += "    variant: .\(swiftName(i.resolution.variant.rawValue)),\n"
        code += "    colourSpace: .\(i.settings.colourSpace.rawValue), edges: .\(i.settings.edgeMode.rawValue), alpha: .\(i.settings.alphaMode.rawValue))\n"
        if !e.appleTwins.isEmpty {
            code += "\n// Apple twins (mapping · provenance)\n"
            for twin in e.appleTwins { code += "\(twin.call)    // \(twin.mapping) · \(twin.provenance.word)\n" }
        }
        var details: [ContentBlock] = []
        if !e.appleTwins.isEmpty {
            var twins: [ContentBlock] = []
            for twin in e.appleTwins {
                if let subject = twin.subject, let result = i.live.calibration(subject) {
                    var v = BadgedValue.number(result.fit.sigmaPx, ContentStyle.px2, .measured, device: result.device, caption: twin.id.uppercased())
                    if ContentOffscreen.isSwiftUIDerived(result) { v = ContentOffscreen.mark(v) }
                    twins.append(.values([LabeledValue(id: "twin-" + twin.id, label: twin.id.uppercased() + " · FITTED σ", value: v)]))
                }
                twins.append(.note("\(twin.id): \(twin.mapping)", twin.provenance))
                twins.append(.sources([twin.source]))
            }
            details.append(.disclosure(title: "Apple's twins and what each does differently", blocks: twins))
        }
        details.append(.paragraph("Same σ, different pixel: colour space, edges and alpha are arguments too. The Trace shows the probe's output under the other colour space beside the real one."))
        details.append(.note("Colour space · edges · alpha · precision are the API floor's silent parameters; Settings holds their defaults.", nil))
        let rule: String
        if let spec = i.primarySpec, spec.unit == .pt {
            rule = "px = pt × \(NumberStyle.decimals(0).text(i.scale))"
        } else if let spec = i.primarySpec, spec.unit == .px, let v = i.primaryValue {
            rule = "\(spec.label.lowercased()) = \(spec.numberStyle.text(v)) px = \(ContentStyle.pt2.text(v / Swift.max(i.scale, 1e-9))) pt × \(NumberStyle.decimals(0).text(i.scale))"
        } else {
            rule = "every argument in its own unit; colour, edges and alpha are arguments too"
        }
        let line = ContentOffscreen.isSwiftUIEntry(e.id)
            ? "IN THIS APP · The radius is what you set; its pixel size is COMPUTED; SwiftUI's blend space on screen is INFERRED and every fit is MEASURED offscreen."
            : "IN THIS APP · The call is Blur2ool's own and its arguments are COMPUTED from the controls; Apple's twins are REFERENCE or MEASURED, and SwiftUI's blend space on screen is INFERRED."
        return ContentFloorDraft(numbers: numbers, figure: .code(CodeBlock(language: "swift", text: code)), governingRule: rule,
                                 details: details, inThisApp: line)
    }

    static func swiftName(_ s: String) -> String {
        let parts = s.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " }).map(String.init)
        guard let first = parts.first else { return s }
        let body = first.lowercased() + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        return body.first?.isNumber == true ? "_" + body : body
    }

    static func literal(_ v: ParameterValue, _ spec: ParameterSpec) -> String {
        switch v {
        case .double(let d): return spec.numberStyle.text(d)
        case .int(let n): return NumberStyle.integer().text(Double(n))
        case .choice(let c): return Double(c) != nil ? c : "." + swiftName(c)
        case .bool(let b): return b ? "true" : "false"
        case .intList(let l): return "[" + l.map { NumberStyle.integer().text(Double($0)) }.joined(separator: ", ") + "]"
        case .point(let x, let y): return "(x: \(NumberStyle.decimals(1).text(x)), y: \(NumberStyle.decimals(1).text(y)))"
        }
    }

    // MARK: Floor 3 · MATH

    static func math(_ i: ContentPageInputs) -> ContentFloorDraft {
        var d = ContentFloorDraft(inThisApp: "IN THIS APP · Every number on this page is COMPUTED by BlurCore in Double from the continuous operator; definitions are REFERENCE.")
        d.governingRule = governingRuleMath(i)
        d.details.append(.chips(propertyChips(i)))
        switch i.cls {
        case .rank:
            d.emptyReason = "N/A · RANK"
            d.numbers = rankNumbers(i)
            d.details.append(.paragraph("A rank filter picks one of the window's own values. It has no kernel and no frequency response: H is not defined."))
        case .adaptive:
            adaptiveMath(i, &d)
        case .spaceVariant, .temporal:
            localMath(i, &d)
        case .system:
            systemMath(i, &d)
        case .gather2D, .skewSeparable:
            lsiMath(i, &d, twoD: true)
        default:
            let nonSeparable = i.psf.map { !ContentKernelMath.isSeparable($0.kernel) } ?? false
            lsiMath(i, &d, twoD: nonSeparable || i.entry.separability == .no || i.entry.separability == .skew)
        }
        if i.entry.properties.contains(.separable) && i.entry.properties.contains(.isotropic) {
            d.details.append(.disclosure(title: "Why only the Gaussian is both round and separable", blocks: [
                .equation("g(x)·g(y) = f(√(x² + y²))  ⇒  ln g(x) + ln g(y) = F(x² + y²)  ⇒  ln g(x) = a + b·x²"),
                .paragraph("A kernel that is separable and isotropic at once must be a Gaussian: the logarithm turns the product into a sum that can only depend on x² + y², which forces a quadratic exponent."),
                .sources([SourceRef("Herschel 1850; Maxwell 1860 (the two-line derivation; SPEC §17 item 11)")]),
            ]))
        }
        d.details.append(.chips([i.entry.verdict.chip, i.entry.linearity.chip]))
        d.details.append(.sources(i.entry.sources))
        return d
    }

    static func governingRuleMath(_ i: ContentPageInputs) -> String {
        switch i.entry.mathSymbol {
        case "G": return "G(x) = e^(−x²/2σ²) / (σ√(2π))   ·   H(ν) = e^(−2π²σ²ν²)"
        case "rect": return "B(x) = 1/w for |x| ≤ w/2   ·   H(ν) = sin(πwν) / (πwν)"
        case "tent": return "T(x) = (1 − |x|/w) / w   ·   H(ν) = sinc²(wν)"
        case "disc": return "P(r) = 1/(πR²) for r ≤ R   ·   H(ρ) = 2·J₁(2πRρ) / (2πRρ)"
        case "hex": return "PSF = ⅓ (rhombus₁ + rhombus₂ + rhombus₃); each rhombus = segment ∗ segment"
        case "exp": return "L(x) = e^(−|x|/b) / (2b)   ·   H(ν) = 1 / (1 + 4π²b²ν²)"
        case "ray": return "local PSF: a segment of length a·r along the ray through the centre"
        case "arc": return "local PSF: an arc of angle Θ about the centre (length Θ·r)"
        case "rank": return "out(p) = the k-th smallest value in the window around p"
        case "w·f": return "out(p) = Σ w(p, q)·in(q) / Σ w(p, q),  w depends on the values"
        case "PDE": return "∂u/∂t = Δu   ·   σ = √(2t)"
        case "FFT": return "out = F⁻¹{ H · F{in} }   ·   H is the definition"
        case "sys": return "out = Apple's render path (not exposed); our model: PSF fitted to offscreen renders"
        default:
            switch i.cls {
            case .adaptive: return "out(p) = Σ w(p, q)·in(q) / Σ w(p, q),  w depends on the values"
            case .rank: return "out(p) = an order statistic of the window around p"
            case .iterativePDE: return "∂u/∂t = div(c·∇u)"
            case .globalFFT: return "out = F⁻¹{ H · F{in} }"
            case .stochastic: return "E[out] = in ∗ E[PSF]   (blur in expectation)"
            case .spaceVariant, .temporal: return "out(p) = ∫ PSF_p(q) · in(q) dq   (the PSF depends on p)"
            default: return "out = in ∗ PSF   ·   H(ν) = F{PSF}(ν)"
            }
        }
    }

    static func propertyChips(_ i: ContentPageInputs) -> [String] {
        let p = i.entry.properties
        var chips: [String] = []
        if p.contains(.linear) { chips.append("LINEAR") }
        if p.contains(.shiftInvariant) || i.entry.linearity == .lsi { chips.append("LSI") }
        if p.contains(.separable) { chips.append("SEPARABLE") }
        if p.contains(.isotropic) { chips.append("ISOTROPIC") }
        if p.contains(.semigroup) { chips.append("SEMIGROUP") }
        if p.contains(.positiveKernel) { chips.append("POSITIVE") }
        if p.contains(.edgePreserving) { chips.append("EDGE-PRESERVING") }
        if p.contains(.dataDependent) { chips.append("DATA-DEPENDENT") }
        chips += responseChips(i)
        return chips
    }

    /// Qualified response chips (SPEC §17 item 21; review fix P-35).
    static func responseChips(_ i: ContentPageInputs) -> [String] {
        guard ![.rank, .adaptive, .system].contains(i.cls) else { return [] }
        let asRun = i.discreteResponse?.minimum?.value
        if i.entry.properties.contains(.nonNegativeResponse) {
            if let m = asRun, m < -1e-9 { return ["H ≥ 0 (CONTINUOUS)", "TRUNCATED: RIPPLE"] }
            return ["H ≥ 0"]
        }
        if let m = asRun, m < -1e-9 { return ["H < 0 · CONTRAST INVERTS"] }
        return []
    }

    static func lsiMath(_ i: ContentPageInputs, _ d: inout ContentFloorDraft, twoD: Bool) {
        let continuous = i.continuousResponse, discrete = i.discreteResponse
        let curve = continuous ?? discrete
        if twoD, let psf = i.psf {
            d.figure = .heatmap(ContentFigures.responseHeatmap(psf.kernel, provenance: psf.provenance == .live ? .live : .computed))
            if let plot = ContentFigures.responsePlot(discrete: discrete, continuous: continuous, summary: "a horizontal slice of the signed response") {
                d.details.append(.disclosure(title: "A one-dimensional slice", blocks: [.figure(.plot(plot))]))
            }
        } else if let plot = ContentFigures.responsePlot(discrete: discrete, continuous: continuous,
                                                         summary: "signed frequency response from DC to Nyquist; the taps' response is solid and the continuous one quiet") {
            d.figure = .plot(plot)
        }
        guard let c = curve else {
            if d.figure == nil { d.emptyReason = i.cls == .globalFFT ? "NO PIXEL FOOTPRINT · GLOBAL (FFT)" : "NO RESPONSE FOR THIS OPERATOR" }
            return
        }
        let label = continuous != nil ? "(CONTINUOUS)" : "(TAPS)"
        // The Gaussian's continuous widths are exact: FWHM = 2√(2 ln 2)·σ, 10–90 % edge = 2·Φ⁻¹(0.9)·σ (the operator's
        // profile is cut at the kernel's radius, which would bias both).
        let gaussianSigma: Double? = i.entry.mathSymbol == "G" && continuous != nil ? i.request.parameters.double("sigma") : nil
        if let s = gaussianSigma {
            d.numbers.append(LabeledValue(id: "fwhm", label: "FWHM", value: .number(2 * (2 * log(2.0)).squareRoot() * s, ContentStyle.px2, .computed)))
        } else if let p = i.profile, let w = ContentKernelMath.fwhm(xs: p.xs, ys: p.ys) {
            d.numbers.append(LabeledValue(id: "fwhm", label: "FWHM", value: .number(w, ContentStyle.px2, .computed)))
        } else if let k = i.marginal, let w = ContentKernelMath.fwhm(xs: k.weights.indices.map { k.offset($0) }, ys: k.weights) {
            d.numbers.append(LabeledValue(id: "fwhm", label: "FWHM (TAPS)", value: .number(w, ContentStyle.px2, .computed)))
        }
        // Half amplitude and −3 dB: exact for the Gaussian (e^(−2π²σ²ν²) = ½ or 1/√2), else interpolated on the curve.
        let half = gaussianSigma.map { (log(2.0) / (2 * .pi * .pi * $0 * $0)).squareRoot() } ?? c.firstCrossing(of: 0.5)
        let db3 = gaussianSigma.map { (log(2.0) / (4 * .pi * .pi * $0 * $0)).squareRoot() } ?? c.firstCrossing(of: 1 / 2.0.squareRoot())
        if let f = half {
            d.numbers.append(LabeledValue(id: "half", label: "HALF AMPLITUDE", value: .number(f, ContentStyle.frequency, .computed)))
        }
        if let f = db3 {
            d.numbers.append(LabeledValue(id: "db3", label: "−3 dB", value: .number(f, ContentStyle.frequency, .computed)))
        }
        if let f = c.firstCrossing(of: 0) {
            d.numbers.append(LabeledValue(id: "zero", label: "FIRST ZERO", value: .number(f, ContentStyle.frequency, .computed)))
        } else {
            d.numbers.append(LabeledValue(id: "zero", label: "FIRST ZERO", value: .words("NONE", spoken: "no zero below Nyquist", .computed)))
        }
        if let m = c.minimum {
            d.numbers.append(LabeledValue(id: "minH", label: "MIN H " + label, value: .number(m.value, ContentStyle.response(m.value), .computed)))
        }
        if let s = gaussianSigma {
            d.numbers.append(LabeledValue(id: "edge", label: "10–90 % EDGE", value: .number(2 * 1.2815515655446004 * s, ContentStyle.px2, .computed)))
        } else if let p = i.profile, let w = ContentKernelMath.edgeWidth(xs: p.xs, ys: p.ys) {
            d.numbers.append(LabeledValue(id: "edge", label: "10–90 % EDGE", value: .number(w, ContentStyle.px2, .computed)))
        } else if let k = i.marginal, let w = ContentKernelMath.edgeWidth(k) {
            d.numbers.append(LabeledValue(id: "edge", label: "10–90 % EDGE (TAPS)", value: .number(w, ContentStyle.px2, .computed)))
        }
        if let asRun = discrete?.minimum, continuous != nil {
            d.details.insert(.values([LabeledValue(id: "minH-run", label: "MIN H (AS RUN)", value: .number(asRun.value, ContentStyle.response(asRun.value), .computed)),
                                      LabeledValue(id: "nyquist-run", label: "H AT NYQUIST (AS RUN)",
                                                   value: .number(discrete?.nyquistValue ?? 0, ContentStyle.response(discrete?.nyquistValue ?? 0), .computed))]), at: 0)
        }
        if let p = i.profile {
            let k = i.marginal
            var markers: [PlotMarker] = []
            if let k { markers = [PlotMarker(x: k.offset(0), label: "support", kind: .supportBracket, provenance: .computed),
                                  PlotMarker(x: k.offset(k.tapCount - 1), label: "support", kind: .supportBracket, provenance: .computed)] }
            let plot = PlotSpec(xAxis: PlotAxis(label: "offset", unit: "px"), yAxis: PlotAxis(label: p.label), series:
                                    [PlotSeries(name: p.label, xs: p.xs, ys: p.ys, style: .solid, role: .reference, provenance: .computed)],
                                markers: markers, accessibilitySummary: "the continuous point-spread function with the kernel's support marked")
            d.details.append(.disclosure(title: "The continuous profile and its support", blocks: [.figure(.plot(plot))]))
        }
        if i.cls == .stochastic { d.details.append(.note("BLUR IN EXPECTATION: one realization is not a blur; the mean of many is.", .computed)) }
        if i.cls == .globalFFT { d.details.append(.note("H is the definition: the kernel is whatever F⁻¹{H} is, and every output pixel depends on every input pixel.", .computed)) }
        if i.cls == .derived { d.details.append(contentsOf: derivedTest(i)) }
        if i.cls == .atlas { d.details.append(.note("CPU ONLY IN THIS APP · TIER 3: these curves are computed by BlurCore; nothing runs on the GPU.", .computed)) }
    }

    /// Why a contrast entry is not a blur: the test it fails (convexity, low-pass, DC gain).
    static func derivedTest(_ i: ContentPageInputs) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        if let k = i.psf?.kernel {
            if k.weights.contains(where: { $0 < -1e-12 }) { blocks.append(.paragraph("Fails convexity: some weights are negative, so the output can leave the range of its inputs.")) }
            if abs(k.sum - 1) > 1e-6 { blocks.append(.paragraph("Fails the DC test: a flat field does not come out unchanged.")) }
        }
        if let c = i.discreteResponse, (c.values.max() ?? 0) > 1 + 1e-6 {
            blocks.append(.values([LabeledValue(id: "maxH", label: "MAX H", value: .number(c.values.max() ?? 1, ContentStyle.response(c.values.max() ?? 1), .computed,
                                                                                          caption: "ABOVE ONE · SHARPENS"))]))
            blocks.append(.paragraph("Fails the low-pass test: some frequencies come out stronger than they went in."))
        }
        if blocks.isEmpty { blocks.append(.paragraph("Built from a blur, but its verdict is \(i.entry.verdict.chip.lowercased()).")) }
        return blocks
    }

    static func rankNumbers(_ i: ContentPageInputs) -> [LabeledValue] {
        var rows: [LabeledValue] = []
        if let taps = i.plan.passes.map(\.tapsPerPixel).max(), taps > 0 {
            rows.append(LabeledValue(id: "window", label: "WINDOW", value: .number(taps, ContentStyle.taps, .computed)))
            rows.append(LabeledValue(id: "rank", label: "CHOSEN RANK", value: .number((taps / 2).rounded(.down) + 1,
                                                                                       .integer(noun: CountNoun("in sorted order", "in sorted order")), .computed)))
        }
        return rows
    }

    static func adaptiveMath(_ i: ContentPageInputs, _ d: inout ContentFloorDraft) {
        let amplitudes = [0.01, 0.03, 0.1, 0.3]
        var series: [PlotSeries] = []
        var rows: [LabeledValue] = []
        for (n, a) in amplitudes.enumerated() {
            guard let c = i.op.response(ResponseQuery(point: i.probe, amplitude: a), i.request, content: i.context.content) else { continue }
            let style: SeriesStyle = [.solid, .dashed, .dotted, .dashDot][n]
            series.append(PlotSeries(name: "A = " + NumberStyle.decimals(2).text(a), xs: c.frequencies, ys: c.values, style: style,
                                     role: n == 0 ? .primary : .reference, provenance: c.provenance))
            if let t = interpolate(c, at: 0.1) {
                rows.append(LabeledValue(id: "T\(n)", label: "T AT ν = 0.1 · A = " + NumberStyle.decimals(2).text(a),
                                         value: .number(t, .decimals(3), c.provenance == .live ? .live : .computed)))
            }
        }
        if series.isEmpty {
            d.emptyReason = "N/A · NONLINEAR"
        } else {
            d.figure = .plot(PlotSpec(xAxis: PlotAxis(label: "frequency", unit: "c/px"), yAxis: PlotAxis(label: "T", normalized: true),
                                      series: series, showsZeroLine: true,
                                      accessibilitySummary: "amplitude-dependent transfer: how much of a sinusoid survives, for four contrasts"))
        }
        d.numbers = rows
        if let contrast = ContentPills.localContrast(i) {
            d.numbers.append(LabeledValue(id: "contrast", label: "LOCAL CONTRAST",
                                          value: .number(contrast, .decimals(2), .live, qualifiers: .cpu, caption: "CPU")))
        }
        d.details.append(.paragraph("An adaptive blur passes convexity, low-pass and shift invariance, but fails linearity and data independence: a small ripple is averaged away while a large edge survives. T(ν, A) replaces H."))
        d.details.append(.sources([SourceRef("catalog-nonlinear.md §0 (amplitude-dependent transfer)")]))
        d.inThisApp = "IN THIS APP · T(ν, A) is COMPUTED by BlurCore on synthetic sinusoids; the local contrast at the probe is LIVE · CPU, read from the current image."
    }

    static func interpolate(_ c: ResponseCurve, at nu: Double) -> Double? {
        guard c.frequencies.count >= 2 else { return nil }
        for k in 1..<c.frequencies.count where c.frequencies[k] >= nu {
            let t = (nu - c.frequencies[k - 1]) / Swift.max(c.frequencies[k] - c.frequencies[k - 1], 1e-300)
            return c.values[k - 1] + t * (c.values[k] - c.values[k - 1])
        }
        return nil
    }

    static func localMath(_ i: ContentPageInputs, _ d: inout ContentFloorDraft) {
        d.details.insert(.note("NO SINGLE RESPONSE · SPACE-VARIANT: the PSF depends on where the probe is; everything here is local to the probe.", .computed), at: 0)
        guard let psf = i.psf else { d.emptyReason = "NO SINGLE RESPONSE · SPACE-VARIANT"; return }
        let m = ContentKernelMath.principalMoments(psf.kernel)
        d.figure = .heatmap(ContentFigures.responseHeatmap(psf.kernel, provenance: psf.provenance))
        d.numbers.append(LabeledValue(id: "along", label: "LOCAL σ ALONG", value: .number(m.along, ContentStyle.px2, .computed)))
        d.numbers.append(LabeledValue(id: "across", label: "LOCAL σ ACROSS", value: .number(m.across, ContentStyle.px2, .computed)))
        d.numbers.append(LabeledValue(id: "axis", label: "LOCAL AXIS", value: .number(m.degrees, NumberStyle.decimals(1, unit: "°", spokenUnit: "degrees"), .computed)))
        let curve = i.op.response(ResponseQuery(axisDegrees: m.degrees, point: i.probe), i.request, content: i.context.content)
            ?? ResponseCurve(kind: .local(i.probe), frequencies: ResponseQuery().frequencies,
                             values: KernelMath.response(psf.kernel, axisDegrees: m.degrees, frequencies: ResponseQuery().frequencies))
        if let f = curve.firstCrossing(of: 0) {
            d.numbers.append(LabeledValue(id: "zero", label: "LOCAL FIRST ZERO", value: .number(f, ContentStyle.frequency, .computed)))
        }
        if let f = curve.firstCrossing(of: 0.5) {
            d.numbers.append(LabeledValue(id: "half", label: "LOCAL HALF AMPLITUDE", value: .number(f, ContentStyle.frequency, .computed)))
        }
        if let mn = curve.minimum {
            d.numbers.append(LabeledValue(id: "minH", label: "LOCAL MIN H", value: .number(mn.value, ContentStyle.response(mn.value), .computed)))
        }
        if let plot = ContentFigures.responsePlot(discrete: curve, continuous: nil, summary: "the local signed response along the PSF's axis") {
            d.details.append(.disclosure(title: "The local response along the PSF's axis", blocks: [.figure(.plot(plot))]))
        }
        d.inThisApp = "IN THIS APP · The local PSF and its response are COMPUTED by BlurCore at the probe; move the probe and they change, which no LSI page ever does."
    }

    static func systemMath(_ i: ContentPageInputs, _ d: inout ContentFloorDraft) {
        if let plot = i.discreteResponse.map({ c in
            PlotSpec(xAxis: PlotAxis(label: "frequency", unit: "c/px"), yAxis: PlotAxis(label: "H", normalized: true),
                     series: [PlotSeries(name: "our model", xs: c.frequencies, ys: c.values, style: .dashed, role: .reference, provenance: .modeled)],
                     showsZeroLine: true, accessibilitySummary: "our model's response, dashed; Apple's own response is not exposed")
        }) { d.figure = .plot(plot) }
        d.numbers = ContentSystem.measuredFit(i)
        if d.figure == nil && d.numbers.isEmpty { d.emptyReason = "SYSTEM INTERNALS · INFERRED" }
        d.details.append(.note("Apple does not expose this kernel. The curve is our model (MODELED); the numbers are fitted to offscreen renders (MEASURED).", .inferred))
        d.inThisApp = "IN THIS APP · The model is MODELED, fits are MEASURED offscreen (on this phone once Calibrate has run, else on the research Mac), and Apple's internals are INFERRED."
    }
}

// MARK: - System entries (Tier S)

enum ContentSystem {
    /// The calibrations that belong to this entry (its twins' subjects, or SwiftUI's blur for the SwiftUI entry).
    static func calibrations(_ i: ContentPageInputs) -> [CalibrationResult] {
        var subjects = Set(i.entry.appleTwins.compactMap(\.subject))
        if ContentOffscreen.isSwiftUIEntry(i.entry.id) { subjects.insert(.swiftUIBlur) }
        return i.live.calibrations.filter { subjects.contains($0.request.subject) }
    }

    /// σ per parameter px, excess kurtosis and the shape name from this phone's newest fit (MEASURED · OFFSCREEN), or
    /// `–.––` slots until Calibrate has run.
    static func measuredFit(_ i: ContentPageInputs) -> [LabeledValue] {
        guard let r = calibrations(i).last else {
            return [LabeledValue(id: "ratio", label: "σ PER PARAMETER PX", value: .notYetMeasured()),
                    LabeledValue(id: "kurtosis", label: "EXCESS KURTOSIS", value: .notYetMeasured())]
        }
        func mark(_ v: BadgedValue) -> BadgedValue { ContentOffscreen.isSwiftUIDerived(r) ? ContentOffscreen.mark(v) : v }
        return [
            LabeledValue(id: "ratio", label: "σ PER PARAMETER PX", value: mark(.number(r.fit.sigmaPerParameterPixel, ContentStyle.ratio, .measured, device: r.device))),
            LabeledValue(id: "sigma", label: "FITTED σ", value: mark(.number(r.fit.sigmaPx, ContentStyle.px2, .measured, device: r.device))),
            LabeledValue(id: "kurtosis", label: "EXCESS KURTOSIS", value: mark(.number(r.fit.excessKurtosis, ContentStyle.kurtosis, .measured, device: r.device))),
            LabeledValue(id: "shape", label: "CLOSEST MODEL", value: mark(.words(r.fit.shapeName.uppercased(), .inferred))),
        ]
    }
}
