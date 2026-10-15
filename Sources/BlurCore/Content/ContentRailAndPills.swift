import Foundation

// OWNER: CONTENT-LAYERS. Rail chips (SPEC §4.1.4: seven chips, ≤ 6 characters, glyph badges, Compare = / ≠ / ≈) and the
// two flanking pills (SPEC §4.1.3 table: LSI, LOCAL @ PROBE, T(ν, A), N/A · RANK, INFERRED — NOT EXPOSED, Compare).

enum ContentRail {
    static func value(_ floor: Floor, _ i: ContentPageInputs) -> BadgedValue {
        switch floor {
        case .slide: return slide(i)
        case .api: return api(i)
        case .math:
            let provenance: Provenance = i.cls == .system ? .reference : .computed
            return .words(i.entry.mathSymbol, spoken: "\(i.entry.displayName), \(mathSpoken(i.entry.mathSymbol))", provenance,
                          source: provenance == .reference ? (i.entry.sources.first ?? SourceRef(i.entry.detailReference)) : nil)
        case .kernel: return kernel(i)
        case .algorithm: return algorithm(i)
        case .gpu: return gpu(i)
        case .pixels: return pixel(i)
        }
    }

    static func mathSpoken(_ symbol: String) -> String {
        switch symbol {
        case "G": "Gaussian bell"
        case "rect": "rectangle"
        case "tent": "triangle"
        case "disc": "disc"
        case "hex": "hexagon"
        case "exp": "exponential"
        case "ray": "rays"
        case "arc": "arcs"
        case "rank": "rank order"
        case "w·f": "weighted average"
        case "PDE": "partial differential equation"
        case "FFT": "frequency domain"
        case "sys": "system internals"
        default: symbol
        }
    }

    /// SLIDE: the home tool's typed value for this blur (σ-matched values prefixed ≈; `UNVER.`; `—` when not offered).
    static func slide(_ i: ContentPageInputs) -> BadgedValue {
        let typed = ContentSlide.typed(i, toolID: i.context.homeToolID)
        let toolName = ContentValues.toolName(i.context.homeToolID, conventions: i.tools.all)
        switch typed.kind {
        case .notOffered:
            return BadgedValue(value: nil, text: "—", provenance: nil, caption: "NOT IN \(toolName.uppercased())",
                               spoken: "not offered in \(toolName)")
        case .unverified:
            return BadgedValue(value: nil, text: "UNVER.", provenance: nil, qualifiers: .unverified,
                               spoken: "\(toolName) mapping, unverified")
        case .words:
            var v = typed.value
            if v.text.count > 6 { v.text = String(v.text.prefix(5)) + "…" }
            return v
        case .number(let n):
            var v = typed.value
            let prefix = typed.sigmaMatchedOnly ? "≈" : ""
            // The chip prints the tool's input precision (one decimal, Metro fine step) in at most six characters.
            var body = abs(n) < 100 ? NumberStyle.decimals(1).text(n) : NumberStyle.decimals(0).text(n)
            if prefix.count + body.count > 6 { body = NumberStyle.decimals(0).text(n) }
            if prefix.count + body.count > 6 { body = NumberStyle.significant(2).text(n) }
            v.text = prefix + body
            if typed.sigmaMatchedOnly {
                // SEMANTICS may already say it; never twice.
                if !v.spoken.lowercased().hasPrefix("about") { v.spoken = "about " + v.spoken }
                if !v.spoken.lowercased().contains("sigma-matched") { v.spoken += ", sigma-matched; \(toolName)'s kernel shape differs" }
                v.caption = ContentToolKernels.addCaption(v.caption, ContentToolKernels.sameSigmaCaption)
            }
            v.unit = nil                // chips print no units; the unit is in the spoken value
            return v
        }
    }

    /// API: the parameter the call carries, in px (σ for Gaussians).
    static func api(_ i: ContentPageInputs) -> BadgedValue {
        guard let spec = i.primarySpec, let v = i.primaryValue else { return .words("—", spoken: "no numeric parameter") }
        var value = v, style = spec.numberStyle
        if spec.unit == .pt {          // SwiftUI radius: the call's px = pt × scale
            value = v * i.scale
            style = ContentStyle.px1
        }
        var badged = BadgedValue.number(value, style, .computed)
        badged.unit = nil               // chips print no units; the unit is spoken
        if badged.text.count > 6 { badged.text = NumberStyle.significant(3).text(value) }
        if ContentOffscreen.isSwiftUIEntry(i.entry.id) { badged = ContentOffscreen.mark(badged) }
        return badged
    }

    /// KERNL: taps per axis (separable), taps per pixel (2-D), samples (gathers), window (rank), LIVE count (adaptive).
    static func kernel(_ i: ContentPageInputs) -> BadgedValue {
        let main = i.plan.passes.max { $0.tapsPerPixel < $1.tapsPerPixel }
        switch i.cls {
        case .separableFIR, .recursive, .runningSum:
            if let k = i.marginal { return chipNumber(Double(k.tapCount), noun: CountNoun("tap per axis", "taps per axis"), .computed) }
        case .rank:
            if let taps = main?.tapsPerPixel, taps > 0 {
                let side = Int(taps.squareRoot().rounded())
                if side * side == Int(taps.rounded()) {
                    return BadgedValue(value: taps, text: "\(NumberStyle.integer().text(Double(side)))×\(NumberStyle.integer().text(Double(side)))",
                                       provenance: .computed, spoken: "\(side) by \(side) window, computed")
                }
                return chipNumber(taps, noun: CountNoun("tap in the window", "taps in the window"), .computed)
            }
        case .adaptive:
            if let psf = i.psf, psf.provenance == .live {
                let n = ContentKernelMath.effectiveTaps(psf.kernel).rounded()
                var v = chipNumber(n, noun: CountNoun("effective tap", "effective taps"), .live)
                v.qualifiers.insert(.cpu)
                return v
            }
            if let taps = main?.tapsPerPixel { return chipNumber(taps, noun: CountNoun("tap per pixel", "taps per pixel"), .computed) }
        case .gather2D, .skewSeparable, .spaceVariant, .stochastic, .temporal:
            if let taps = main?.tapsPerPixel { return chipNumber(taps, noun: CountNoun("sample per pixel", "samples per pixel"), .computed) }
        case .sparseIterated:
            if let k = i.marginal { return chipNumber(Double(k.tapCount), noun: CountNoun("effective tap per axis", "effective taps per axis"), .computed) }
        case .system:
            return .words("SYS", spoken: "system kernel, not exposed", .inferred)
        case .globalFFT:
            return .words("FFT", spoken: "no pixel footprint, global", .computed)
        default:
            break
        }
        if let k = i.marginal { return chipNumber(Double(k.tapCount), noun: CountNoun("tap per axis", "taps per axis"), .computed) }
        if let taps = main?.tapsPerPixel { return chipNumber(taps, noun: CountNoun("tap per pixel", "taps per pixel"), .computed) }
        return .words("—", spoken: "no kernel")
    }

    static func chipNumber(_ n: Double, noun: CountNoun, _ provenance: Provenance) -> BadgedValue {
        var v = BadgedValue.number(n, .integer(noun: noun), provenance)
        v.unit = nil
        if v.text.count > 6 { v.text = NumberStyle.significant(2).text(n) }
        return v
    }

    /// ALGO: passes (`2×`), iterations (`32×`), levels (`L4`).
    static func algorithm(_ i: ContentPageInputs) -> BadgedValue {
        if i.cls == .system { return .words("SYS", spoken: "render server, inferred", .inferred) }
        let passes = i.plan.passes
        if i.cls == .sparseIterated, passes.contains(where: { $0.outputScale < 1 }) {
            let levels = Set(passes.map(\.outputScale).filter { $0 < 1 }).count
            return ContentStyle.chipCount(Double(levels), suffix: "", prefix: "L", spokenNoun: CountNoun("level", "levels"), .computed)
        }
        if i.cls == .iterativePDE {
            return ContentStyle.chipCount(Double(passes.count), spokenNoun: CountNoun("iteration", "iterations"), .computed)
        }
        return ContentStyle.chipCount(Double(passes.count), spokenNoun: CountNoun("pass", "passes"), .computed)
    }

    /// GPU: MEASURED median ms of the last settled full-resolution timing Run; `–.––` until it exists; `SIM` in the Simulator.
    static func gpu(_ i: ContentPageInputs) -> BadgedValue {
        if let run = i.live.timedRun, let timing = run.timing, !run.device.isSimulator {
            var v = BadgedValue.number(timing.medianMilliseconds, ContentStyle.ms, .measured, device: run.device,
                                       caption: timing.thermalChanged ? "THERMAL CHANGED" : nil)
            v.unit = nil
            v.spoken = ContentStyle.ms.spoken(timing.medianMilliseconds) + ", " + Provenance.measured.spokenPhrase(device: run.device)
            return v
        }
        if let run = i.live.run, run.device.isSimulator {
            return .words("SIM", spoken: "no GPU timing in the Simulator")
        }
        if i.plan.fetchesPerFrame(i.request.size) > FetchBudget.full {
            return .words("SLOW", spoken: "too slow to time", .modeled)
        }
        return .notYetMeasured()
    }

    /// PIXEL: the probe's output, linear light, 3 significant digits, from the newest full-resolution Run (HELD in previews).
    static func pixel(_ i: ContentPageInputs) -> BadgedValue {
        guard let run = i.live.run, let probe = run.probe else { return .words("—", spoken: "no output yet") }
        let out = ContentValues.scalar(probe.output)
        var v = BadgedValue.number(out, ContentStyle.probe(out), .live, caption: i.isPreview ? "HELD" : nil)
        if v.text.count > 6 { v.text = NumberStyle.significant(2).text(ContentValues.scalar(probe.output)) }
        if ContentOffscreen.isSwiftUIEntry(i.entry.id) { v = ContentOffscreen.mark(v) }
        return v
    }
}

// MARK: - Floor 1 values shared by the rail and the Slide page

enum ContentSlide {
    enum Kind: Equatable { case number(Double), words, unverified, notOffered }

    struct Typed {
        var value: BadgedValue
        var kind: Kind
        var sigmaMatchedOnly: Bool
    }

    /// The per-axis σ the tools are asked about: the entry's own σ, else its primary in px.
    static func sigmaForTools(_ i: ContentPageInputs) -> Double {
        // The σ the API carries (CSS blur(σ), CIGaussianBlur σ …) when the entry has one in px; else the PSF's own σ.
        if let spec = i.entry.spec("sigma"), spec.unit == .px, let s = i.request.parameters.double("sigma") ?? i.entry.defaultParameters.double("sigma") { return s }
        if let s = i.sigma { return s }
        if let spec = i.primarySpec, let v = i.primaryValue {
            switch spec.unit {
            case .px: return v
            case .pt: return v * i.scale
            default: return 0
            }
        }
        return 0
    }

    /// What `toolID` needs typed for this blur, classified and decorated (≈ when only σ matches; OFFSCREEN for SwiftUI).
    static func typed(_ i: ContentPageInputs, toolID: String) -> Typed {
        let law = ContentOffscreen.isSwiftUITool(toolID) ? i.swiftUILaw : nil
        // The SwiftUI entry: what you type IS the hero (an input, no badge).
        if ContentOffscreen.isSwiftUIEntry(i.entry.id), ContentOffscreen.isSwiftUITool(toolID), let spec = i.primarySpec, let v = i.primaryValue {
            return Typed(value: .input(v, spec.numberStyle), kind: .number(v), sigmaMatchedOnly: false)
        }
        var v = i.tools.typedValue(toolID: toolID, blur: i.entry.id, sigmaPx: sigmaForTools(i), displayScale: i.scale, measuredLaw: law)
        let caption = (v.caption ?? "").uppercased()
        if v.value == nil && !v.qualifiers.contains(.unverified)
            && (v.text == "—" || v.text.uppercased().contains("NOT OFFERED") || caption.contains("NOT IN")) {
            return Typed(value: v, kind: .notOffered, sigmaMatchedOnly: false)
        }
        if v.qualifiers.contains(.unverified) || v.text.uppercased() == "UNVERIFIED" {
            return Typed(value: v, kind: .unverified, sigmaMatchedOnly: false)
        }
        if ContentOffscreen.isSwiftUITool(toolID) && v.value != nil { v = ContentOffscreen.mark(v) }
        guard let n = v.value else { return Typed(value: v, kind: .words, sigmaMatchedOnly: false) }
        let onlySigma = ContentToolKernels.matchesOnlySigma(toolID: toolID, blur: i.entry.id) && i.sigma != nil
        if v.text.hasPrefix("≈") { v.text.removeFirst() }
        return Typed(value: v, kind: .number(n), sigmaMatchedOnly: onlySigma)
    }
}

// MARK: - Pills

enum ContentPills {
    static func make(_ i: ContentPageInputs) -> PillContent {
        var kernel: PillPlot
        var freq: PillPlot
        switch i.cls {
        case .rank:
            kernel = sortedWindow(i)
            freq = PillPlot(title: "FREQ", plot: nil, emptyText: "N/A · RANK", badge: nil)
        case .adaptive:
            kernel = localKernel(i, live: true)
            freq = amplitudeTransfer(i)
        case .spaceVariant, .temporal:
            kernel = localKernel(i, live: false)
            freq = localResponse(i)
        case .system:
            kernel = modelKernel(i)
            freq = modelResponse(i)
        case .globalFFT:
            kernel = lsiKernel(i) ?? PillPlot(title: "KERNEL", plot: nil, emptyText: "NO PIXEL FOOTPRINT · GLOBAL (FFT)", badge: nil)
            freq = lsiResponse(i)
        default:
            kernel = lsiKernel(i) ?? PillPlot(title: "KERNEL", plot: nil, emptyText: i.entry.linearity == .nonlinear ? "N/A · NONLINEAR" : "NO KERNEL", badge: nil)
            freq = lsiResponse(i)
        }
        if let b = i.context.compareB, let opB = BlurRegistry.op(b.blur) {
            addComparison(&kernel, &freq, opB: opB, b: b, i: i)
        }
        return PillContent(kernel: kernel, freq: freq)
    }

    static let computedBadge = BadgedValue.words("COMPUTED", spoken: "computed", .computed)

    /// LSI: discrete taps as stems (normalised to the peak) over the continuous kernel; depth trace for chains.
    static func lsiKernel(_ i: ContentPageInputs) -> PillPlot? {
        guard let k = i.marginal else { return nil }
        let peak = Swift.max(k.weights.map(abs).max() ?? 1, 1e-300)
        var series: [PlotSeries] = []
        if let p = i.profile, !p.ys.isEmpty {
            // The continuous kernel (weight per pixel) on the same scale as the taps (divided by the same peak).
            series.append(PlotSeries(name: p.label, xs: p.xs, ys: p.ys.map { $0 / peak }, style: .quiet, role: .reference, provenance: .computed))
        }
        let isChain = i.cls == .sparseIterated || i.plan.passes.count > 2 || i.entry.id == "iterated-box"
        series.append(PlotSeries(name: isChain ? "effective kernel after all passes" : "taps",
                                 xs: k.weights.indices.map { k.offset($0) }, ys: k.weights.map { $0 / peak },
                                 style: .stems, role: isChain ? .depth : .primary, provenance: i.psf?.provenance ?? .computed))
        let plot = PlotSpec(xAxis: PlotAxis(label: "tap offset", unit: "px"), yAxis: PlotAxis(label: "weight", normalized: true),
                            series: series, accessibilitySummary: "kernel taps from the most negative offset to the most positive, normalized to the peak")
        return PillPlot(title: "KERNEL", plot: plot, emptyText: nil, badge: computedBadge)
    }

    /// LSI: the signed DFT of the discrete taps over the continuous response, −3 dB tick; ripple stated when the
    /// continuous response is non-negative but the truncated taps are not (SPEC §17 item 21).
    static func lsiResponse(_ i: ContentPageInputs) -> PillPlot {
        guard let plot = ContentFigures.responsePlot(discrete: i.discreteResponse, continuous: i.continuousResponse,
                                                     summary: "signed response from DC to Nyquist; negative lobes are shaded and dashed")
        else { return PillPlot(title: "FREQ", plot: nil, emptyText: i.entry.linearity == .nonlinear ? "N/A · NONLINEAR" : "NO RESPONSE", badge: nil) }
        var p = plot
        p.markers = p.markers.filter { $0.kind == .minus3dB }
        return PillPlot(title: "FREQ", plot: p, emptyText: nil, badge: responseBadge(i))
    }

    /// `H ≥ 0 (CONTINUOUS)` + `TRUNCATED: RIPPLE` with the as-run minimum, or plain COMPUTED.
    static func responseBadge(_ i: ContentPageInputs) -> BadgedValue {
        guard let d = i.discreteResponse, let minimum = d.minimum?.value else { return computedBadge }
        if i.entry.properties.contains(.nonNegativeResponse) && minimum < -1e-9 {
            return .number(minimum, ContentStyle.response(minimum), .computed, caption: "H ≥ 0 (CONTINUOUS) · TRUNCATED: RIPPLE")
        }
        if minimum < -1e-9 { return .number(minimum, ContentStyle.response(minimum), .computed, caption: "MIN H · CONTRAST INVERTS") }
        return computedBadge
    }

    /// LSV (`= COMPUTED`) and adaptive (`● LIVE · CPU`): the local PSF profile along its principal axis at the probe.
    static func localKernel(_ i: ContentPageInputs, live: Bool) -> PillPlot {
        guard let psf = i.psf else {
            return PillPlot(title: "LOCAL @ PROBE", plot: nil, emptyText: live ? "WEIGHTS NEED THE CURRENT IMAGE" : "NO LOCAL PSF AT THE PROBE", badge: nil)
        }
        let axis = ContentKernelMath.principalMoments(psf.kernel).degrees
        let k = ContentKernelMath.profile(psf.kernel, degrees: axis)
        let peak = Swift.max(k.weights.map(abs).max() ?? 1, 1e-300)
        let plot = PlotSpec(xAxis: PlotAxis(label: "offset along the local axis", unit: "px"), yAxis: PlotAxis(label: "weight", normalized: true),
                            series: [PlotSeries(name: live ? "weight row through the probe" : "local PSF", xs: k.weights.indices.map { k.offset($0) },
                                                ys: k.weights.map { $0 / peak }, style: .stems, role: .primary, provenance: psf.provenance)],
                            accessibilitySummary: "the PSF at the probe along its own axis, normalized to the peak")
        var badge: BadgedValue = psf.provenance == .live
            ? .words("LIVE", spoken: "live, computed on the CPU from the current image", .live, qualifiers: .cpu)
            : computedBadge
        if psf.provenance == .live { badge.caption = "CPU" }
        return PillPlot(title: "LOCAL @ PROBE", plot: plot, emptyText: nil, badge: badge)
    }

    /// LSV: the local response along the PSF's axis at the probe; the global H does not exist.
    static func localResponse(_ i: ContentPageInputs) -> PillPlot {
        let axis = i.psf.map { ContentKernelMath.principalMoments($0.kernel).degrees } ?? 0
        let curve = i.op.response(ResponseQuery(axisDegrees: axis, point: i.probe), i.request, content: i.context.content)
            ?? i.psf.map { ResponseCurve(kind: .local(i.probe), frequencies: ResponseQuery().frequencies,
                                         values: KernelMath.response($0.kernel, axisDegrees: axis, frequencies: ResponseQuery().frequencies)) }
        guard let c = curve, let plot = ContentFigures.responsePlot(discrete: c, continuous: nil,
                                                                  summary: "the local signed response along the PSF's axis at the probe")
        else { return PillPlot(title: "LOCAL @ PROBE", plot: nil, emptyText: "NO SINGLE RESPONSE · SPACE-VARIANT", badge: nil) }
        var p = plot
        p.markers = p.markers.filter { $0.kind == .minus3dB }
        return PillPlot(title: "LOCAL @ PROBE", plot: p, emptyText: nil, badge: computedBadge)
    }

    /// Adaptive: T(ν, A) at the local contrast around the probe (NL §0); A is the LIVE · CPU contrast of a 9 × 9 window.
    static func amplitudeTransfer(_ i: ContentPageInputs) -> PillPlot {
        let measured = localContrast(i)
        let amplitude = measured ?? 0.20
        let amplitudeValue: BadgedValue = measured != nil
            ? { var v = BadgedValue.number(amplitude, .decimals(2), .live, qualifiers: .cpu, caption: "LOCAL CONTRAST · CPU"); v.spoken = "local contrast " + v.spoken; return v }()
            : .input(amplitude, .decimals(2))
        let title = "T(ν, A \(amplitudeValue.text))"
        guard let c = i.op.response(ResponseQuery(point: i.probe, amplitude: amplitude), i.request, content: i.context.content) else {
            return PillPlot(title: title, plot: nil, emptyText: "N/A · NONLINEAR", badge: amplitudeValue)
        }
        let plot = PlotSpec(xAxis: PlotAxis(label: "frequency", unit: "c/px"), yAxis: PlotAxis(label: "T", normalized: true),
                            series: [PlotSeries(name: "amplitude transfer", xs: c.frequencies, ys: c.values, style: .solid, role: .primary,
                                                provenance: c.provenance)],
                            showsZeroLine: true, accessibilitySummary: "how much of a sinusoid of the local contrast survives, from DC to Nyquist")
        return PillPlot(title: title, plot: plot, emptyText: nil, badge: amplitudeValue)
    }

    /// Max − min of the luma in the 9 × 9 window around the probe (LIVE · CPU), or nil without the image.
    static func localContrast(_ i: ContentPageInputs) -> Double? {
        guard let image = i.context.content?.image, image.size.contains(i.probe) else { return nil }
        var lo = Double.infinity, hi = -Double.infinity
        for dy in -4...4 { for dx in -4...4 {
            let v = ContentValues.scalar(image.fetch(i.probe.x + dx, i.probe.y + dy, edge: .clamp))
            lo = Swift.min(lo, v); hi = Swift.max(hi, v)
        } }
        return Swift.max(0.01, Swift.min(1, hi - lo))
    }

    /// Rank: the sorted window around the probe with the chosen value marked.
    static func sortedWindow(_ i: ContentPageInputs) -> PillPlot {
        guard let image = i.context.content?.image, image.size.contains(i.probe) else {
            return PillPlot(title: "SORTED WINDOW", plot: nil, emptyText: "THE WINDOW NEEDS THE CURRENT IMAGE", badge: nil)
        }
        let taps = i.plan.passes.map(\.tapsPerPixel).max() ?? 9
        let r = Swift.max(1, (Int(taps.squareRoot().rounded()) - 1) / 2)
        var values: [Double] = []
        for dy in -r...r { for dx in -r...r { values.append(ContentValues.scalar(image.fetch(i.probe.x + dx, i.probe.y + dy, edge: i.settings.edgeMode == .renormalise ? .clamp : i.settings.edgeMode))) } }
        values.sort()
        let chosen = values.count / 2
        let plot = PlotSpec(xAxis: PlotAxis(label: "rank"), yAxis: PlotAxis(label: "value"),
                            series: [PlotSeries(name: "sorted window", xs: values.indices.map(Double.init), ys: values, style: .points, role: .primary, provenance: .live)],
                            markers: [PlotMarker(x: Double(chosen), label: "chosen", kind: .custom, provenance: .live)],
                            accessibilitySummary: "the window around the probe sorted from darkest to brightest; the middle one is chosen")
        return PillPlot(title: "SORTED WINDOW", plot: plot, emptyText: nil,
                        badge: .words("LIVE", spoken: "live, read on the CPU from the current image", .live, qualifiers: .cpu, caption: "CPU"))
    }

    /// Tier S: our model's kernel, dashed and MODELED.
    static func modelKernel(_ i: ContentPageInputs) -> PillPlot {
        guard let k = i.marginal else { return PillPlot(title: "KERNEL", plot: nil, emptyText: "INFERRED — NOT EXPOSED", badge: nil) }
        let peak = Swift.max(k.weights.map(abs).max() ?? 1, 1e-300)
        let plot = PlotSpec(xAxis: PlotAxis(label: "tap offset", unit: "px"), yAxis: PlotAxis(label: "weight", normalized: true),
                            series: [PlotSeries(name: "our model", xs: k.weights.indices.map { k.offset($0) }, ys: k.weights.map { $0 / peak },
                                                style: .dashed, role: .reference, provenance: .modeled)],
                            accessibilitySummary: "our model of the system kernel, dashed; Apple's own kernel is not exposed")
        var badge = BadgedValue.words("MODELED", spoken: "our model, modeled", .modeled)
        if ContentOffscreen.isSwiftUIEntry(i.entry.id) { badge.caption = "MODEL" }
        return PillPlot(title: "KERNEL", plot: plot, emptyText: nil, badge: badge)
    }

    /// Tier S: `INFERRED — NOT EXPOSED` for the system, with our model's response dashed.
    static func modelResponse(_ i: ContentPageInputs) -> PillPlot {
        let c = i.discreteResponse
        let plot = c.map { c in
            PlotSpec(xAxis: PlotAxis(label: "frequency", unit: "c/px"), yAxis: PlotAxis(label: "H", normalized: true),
                     series: [PlotSeries(name: "our model", xs: c.frequencies, ys: c.values, style: .dashed, role: .reference, provenance: .modeled)],
                     showsZeroLine: true, accessibilitySummary: "our model's response, dashed; the system's own response is not exposed")
        }
        return PillPlot(title: "FREQ", plot: plot, emptyText: "INFERRED — NOT EXPOSED",
                        badge: .words("INFERRED", spoken: "inferred, not exposed by Apple", .inferred))
    }

    /// Compare: A solid, B dashed (both pills).
    static func addComparison(_ kernel: inout PillPlot, _ freq: inout PillPlot, opB: any BlurOperator, b: RenderConfiguration, i: ContentPageInputs) {
        let rb = b.operatorRequest
        if var plot = kernel.plot, let k = opB.psf(at: b.probe, rb, content: nil)?.kernel.marginalX {
            let peak = Swift.max(k.weights.map(abs).max() ?? 1, 1e-300)
            plot.series = plot.series.filter { $0.role != .reference }
            plot.series.append(PlotSeries(name: "B · " + opB.entry.displayName, xs: k.weights.indices.map { k.offset($0) },
                                          ys: k.weights.map { $0 / peak }, style: .dashed, role: .comparisonB, provenance: .computed))
            kernel.plot = plot
        }
        if var plot = freq.plot, let c = opB.response(ResponseQuery(), rb, content: nil) {
            plot.series = plot.series.filter { $0.role != .reference }
            plot.series.append(PlotSeries(name: "B · " + opB.entry.displayName, xs: c.frequencies, ys: c.values, style: .dashed,
                                          role: .comparisonB, provenance: c.provenance))
            freq.plot = plot
        }
    }
}
