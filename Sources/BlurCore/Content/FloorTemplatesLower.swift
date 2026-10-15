import Foundation

// OWNER: CONTENT-LAYERS. Floor templates 4–7 (SPEC §5.1 KERNEL, ALGORITHM, GPU, PIXELS; §5.2 per class; §4.3 floor 6 tabs).

extension ContentFloorTemplates {

    // MARK: Floor 4 · KERNEL

    static func kernel(_ i: ContentPageInputs) -> ContentFloorDraft {
        var d = ContentFloorDraft(inThisApp: kernelInThisApp(i))
        d.governingRule = governingRuleKernel(i)
        switch i.cls {
        case .adaptive: adaptiveKernel(i, &d)
        case .rank: rankKernel(i, &d)
        case .spaceVariant, .temporal: fieldKernel(i, &d)
        case .system: systemKernel(i, &d)
        case .gather2D, .skewSeparable, .stochastic, .iterativePDE: twoDKernel(i, &d)
        case .globalFFT:
            if i.psf != nil { twoDKernel(i, &d) } else { d.emptyReason = "NO PIXEL FOOTPRINT · GLOBAL (FFT)" }
        default:
            if let psf = i.psf, !ContentKernelMath.isSeparable(psf.kernel) { twoDKernel(i, &d) } else { separableKernel(i, &d) }
        }
        return d
    }

    static func governingRuleKernel(_ i: ContentPageInputs) -> String {
        if let cut = i.massCut, let s = i.request.parameters.double("sigma") {
            let k = i.request.parameters.choice("truncation") ?? "3"
            let bound = "|n| ≤ ⌈\(k)σ⌉ = \(NumberStyle.integer().text(Double(cut.radius)))"
            switch cut.discretisation {
            case "integrated": return "g[n] = Φ((n + ½)/σ) − Φ((n − ½)/σ), renormalised,  \(bound)"
            case "lindeberg": return "g[n] = e^(−t)·Iₙ(t),  t = σ² = \(NumberStyle.decimals(2).text(s * s)),  renormalised,  \(bound)"
            default: return "g[n] = exp(−n²/2σ²) / Σ,  \(bound)"
            }
        }
        switch i.cls {
        case .adaptive: return "w(p, q) = spatial(q − p) × range(in(q) − in(p)),  out = Σ w·in / Σ w"
        case .rank: return "sort the window; keep the middle value"
        case .runningSum: return "S(x) = S(x − 1) + in(x + r) − in(x − r − 1);  box = S / (2r + 1)"
        case .recursive: return "y[n] = b·x[n] − Σ aₖ·y[n − k]   (causal, then anticausal)"
        case .iterativePDE: return "u ← u + λ·(u_N + u_S + u_E + u_W − 4u)"
        case .spaceVariant, .temporal: return "w_p[q] = the local PSF at p, sampled where the taps land"
        case .system: return "LSF = d(ESF)/dx, fitted to offscreen renders"
        default: return "w[n] = PSF sampled on the pixel grid,  Σ w = 1"
        }
    }

    static func kernelInThisApp(_ i: ContentPageInputs) -> String {
        switch i.cls {
        case .adaptive: return "IN THIS APP · The weight map is LIVE · CPU: BlurCore recomputes it from the current image, because the GPU never stores it."
        case .rank: return "IN THIS APP · The window is read on the CPU from the current image (LIVE · CPU); the GPU sorts the same values with a network."
        case .system: return "IN THIS APP · Apple's kernel is not exposed: the curve is our model (MODELED) beside the line-spread function measured offscreen."
        case .atlas: return "IN THIS APP · CPU ONLY · TIER 3: BlurCore computes these weights in Double; no GPU runs them."
        default:
            if i.pairAnalysis != nil {
                return "IN THIS APP · BlurCore computes every weight in Double. The GPU receives the pair weights and offsets in the details, and the hardware rounds each pair's fraction to its sub-texel precision, so the effective taps differ from the stems by the MODELED error above."
            }
            return "IN THIS APP · Weights come from BlurCore (Double) and are the exact numbers the GPU receives."
        }
    }

    static func separableKernel(_ i: ContentPageInputs, _ d: inout ContentFloorDraft) {
        guard let k = i.marginal else { d.emptyReason = i.entry.linearity == .nonlinear ? "N/A · NONLINEAR" : "NO KERNEL"; return }
        let provenance = i.psf?.provenance ?? .computed
        d.figure = .plot(ContentFigures.kernelPlot(k, profile: i.profile, provenance: provenance,
                                                    summary: "the discrete weights as stems over the continuous curve"))
        d.numbers.append(LabeledValue(id: "centre", label: "CENTRE WEIGHT", value: .number(k.weights[Swift.min(Swift.max(k.origin, 0), k.tapCount - 1)], ContentStyle.weight, provenance)))
        d.numbers.append(LabeledValue(id: "taps", label: "TAPS", value: .number(Double(k.tapCount), .integer(noun: CountNoun("per axis", "per axis")), provenance)))
        if let cut = i.massCut {
            d.numbers.append(LabeledValue(id: "massCut", label: "MASS CUT · PER AXIS", value: .number(cut.perAxis * 100, ContentStyle.percent, .computed)))
        } else {
            d.numbers.append(LabeledValue(id: "massCut", label: "MASS CUT", value: .words("NONE · FINITE KERNEL", spoken: "nothing is cut: the kernel is finite", .computed)))
        }
        d.numbers.append(LabeledValue(id: "sigma", label: "σ OF KERNEL", value: .number(k.sigma, ContentStyle.px2, provenance)))
        let asRun = KernelMath.response(k, frequencies: ResponseQuery().frequencies)
        let minH = asRun.min() ?? 0
        let ripple = i.entry.properties.contains(.nonNegativeResponse) && minH < -1e-9
        d.numbers.append(LabeledValue(id: "minH", label: "MIN H (ripple)", value: .number(minH, ContentStyle.response(minH), provenance,
                                                                                          caption: ripple ? "H ≥ 0 (CONTINUOUS) · TRUNCATED: RIPPLE" : nil)))
        if let error = approximationError(i, kernel: k) {
            d.numbers.append(error.row)
            d.details.append(.disclosure(title: "How the error is defined", blocks: error.definition))
        } else if let cut = i.massCut {
            d.numbers.append(LabeledValue(id: "massCut2D", label: "MASS CUT · 2-D", value: .number(cut.twoD * 100, ContentStyle.percent, .computed)))
        }
        if let cut = i.massCut {
            var rows = [LabeledValue(id: "massCutContinuous", label: "CONTINUOUS TAIL BEYOND THE CUT", value: .number(cut.continuous * 100, ContentStyle.percent, .computed))]
            if d.numbers.contains(where: { $0.id == "errorVs" }) {
                rows.insert(LabeledValue(id: "massCut2D", label: "MASS CUT · 2-D", value: .number(cut.twoD * 100, ContentStyle.percent, .computed)), at: 0)
            }
            d.details.append(.values(rows))
            d.details.append(.paragraph("The mass cut is discrete: the share of the untruncated \(cut.discretisation) kernel that lies beyond the cut and was renormalised away. The continuous Gaussian's tail beyond the same radius is shown for comparison."))
        }
        d.details.append(.table(TableBlock(columns: ["OFFSET", "WEIGHT"], rows: k.weights.indices.map {
            [NumberStyle(precision: .decimals(0), explicitPlus: true).text(k.offset($0)), ContentStyle.weight.text(k.weights[$0])]
        }, caption: "The weights the GPU receives (Float of BlurCore's Double)", provenance: provenance)))
        if let pairs = i.pairAnalysis {
            d.details.append(.table(TableBlock(columns: ["PAIR", "OFFSET", "WEIGHT"], rows: pairs.table.offsets.indices.map {
                [NumberStyle.integer().text(Double($0)), NumberStyle.decimals(4).text(pairs.table.offsets[$0]), ContentStyle.weight.text(pairs.table.weights[$0])]
            }, caption: "The pair table: one bilinear fetch per pair, both sides", provenance: .computed)))
            d.details.append(.table(TableBlock(columns: ["PAIR", "t REQUESTED", "t AS THE HARDWARE ROUNDS IT"], rows: pairs.requestedFractions.indices.map {
                [NumberStyle.integer().text(Double($0 + 1)), ContentTraceFormat.fraction.text(pairs.requestedFractions[$0]), ContentTraceFormat.fraction.text(pairs.quantizedFractions[$0])]
            }, caption: "Bilinear fractions quantized to the sub-texel rule", provenance: .modeled)))
        }
        if i.entry.spec("discretisation") != nil {
            d.details.append(.chips(["SAMPLED", "INTEGRATED", "LINDEBERG"]))
            d.details.append(.paragraph("Discretisation: sampled weights evaluate the bell at whole pixels; integrated weights average it over each pixel; Lindeberg's discrete Gaussian is the one whose variance is exactly σ² and that obeys the semigroup law on the grid."))
        }
        let dft = PlotSpec(xAxis: PlotAxis(label: "frequency", unit: "c/px"), yAxis: PlotAxis(label: "H", normalized: true),
                           series: [PlotSeries(name: "DFT of the taps", xs: ResponseQuery().frequencies, ys: asRun, style: .solid, role: .primary, provenance: provenance)],
                           showsZeroLine: true, accessibilitySummary: "the signed response of the taps exactly as run")
        d.details.append(.disclosure(title: "The DFT of the taps", blocks: [.figure(.plot(dft))]))
        d.details.append(.paragraph("The 2-D kernel is the outer product of these weights with themselves: every row is this row scaled."))
    }

    struct ErrorRow { var row: LabeledValue; var definition: [ContentBlock] }

    /// The `ERROR VS <reference>` slot (review fix: every approximating entry declares its reference and definition).
    static func approximationError(_ i: ContentPageInputs, kernel k: Kernel1D) -> ErrorRow? {
        if let pairs = i.pairAnalysis {
            let rule = i.subTexelRule
            let ruleWords = "\(rule.bits)-BIT " + (rule.rounding == .nearest ? "ROUND TO NEAREST" : "TRUNCATE")
            var v = BadgedValue.number(pairs.maxTapError, ContentStyle.response, .modeled,
                                       caption: ruleWords + (rule.measuredHere ? " · MEASURED ON THIS PHONE" : " · MEASURED ON M1 MAX ONLY"))
            v.unit = "per tap"
            v.spoken = ContentStyle.response.spoken(pairs.maxTapError) + " per tap, modeled"
            let centre = k.weights[k.origin]
            return ErrorRow(row: LabeledValue(id: "errorVs", label: "ERROR VS SAMPLED", value: v), definition: [
                .equation("error = max over taps |w_effective − w_stem|,  w_effective = (a + b)·(1 − t_q), (a + b)·t_q"),
                .values([LabeledValue(id: "errorShare", label: "SHARE OF THE CENTRE WEIGHT",
                                      value: .number(pairs.maxTapError / Swift.max(centre, 1e-300) * 100, ContentStyle.percent, .modeled))]),
                .paragraph("Each pair (a, b) becomes one bilinear fetch at fraction t = b/(a + b); the hardware rounds t to its sub-texel precision, so the two effective taps shift slightly. This phone's own rule replaces the Mac's once its sub-texel probe has run."),
            ])
        }
        let approximatesGaussian: Set<String> = ["iterated-box", "kawase-blur", "dual-kawase", "pyramid-blur", "iir-gaussian", "binomial-blur"]
        if approximatesGaussian.contains(i.entry.id.rawValue), let s = i.sigma, s > 0.2 {
            let g = KernelMath.gaussianSampled(sigma: s, truncation: 4)
            let e = ContentKernelMath.relativeL2(k, g)
            return ErrorRow(row: LabeledValue(id: "errorVs", label: "ERROR VS GAUSSIAN", value: .number(e * 100, ContentStyle.percent, .computed)),
                            definition: [.equation("error = ‖k − g_σ‖₂ / ‖g_σ‖₂,  g_σ = the sampled Gaussian with the same σ"),
                                         .paragraph("The relative L2 distance between this kernel and the Gaussian of equal second moment, on the pixel grid.")])
        }
        return nil
    }

    static func twoDKernel(_ i: ContentPageInputs, _ d: inout ContentFloorDraft) {
        guard let psf = i.psf else { d.emptyReason = "NO KERNEL"; return }
        let k = psf.kernel
        d.figure = .heatmap(ContentFigures.kernelHeatmap(k, caption: "THE 2-D WEIGHTS · CENTRED ON THE PROBE", provenance: psf.provenance))
        let nonZero = Double(k.weights.filter { $0 != 0 }.count)
        let centre = (k.originX >= 0 && k.originX < k.width && k.originY >= 0 && k.originY < k.height) ? k[k.originX, k.originY] : 0
        let m = k.marginalX, my = k.marginalY
        d.numbers.append(LabeledValue(id: "taps", label: "TAPS PER PIXEL", value: .number(nonZero, ContentStyle.taps, psf.provenance)))
        d.numbers.append(LabeledValue(id: "centre", label: "CENTRE WEIGHT", value: .number(centre, NumberStyle.significant(3), psf.provenance)))
        d.numbers.append(LabeledValue(id: "sigmaX", label: "σ ACROSS X", value: .number(m.sigma, ContentStyle.px2, psf.provenance)))
        d.numbers.append(LabeledValue(id: "sigmaY", label: "σ ACROSS Y", value: .number(my.sigma, ContentStyle.px2, psf.provenance)))
        let h = KernelMath.response(k, axisDegrees: 0, frequencies: ResponseQuery().frequencies)
        d.numbers.append(LabeledValue(id: "minH", label: "MIN H (AS RUN, ALONG X)", value: .number(h.min() ?? 0, ContentStyle.response(h.min() ?? 0), psf.provenance)))
        let samples = i.plan.passes.map(\.tapsPerPixel).max() ?? nonZero
        d.numbers.append(LabeledValue(id: "samples", label: "SAMPLES PER PIXEL", value: .number(samples, ContentStyle.samples, .computed)))
        d.details.append(.paragraph(ContentKernelMath.isSeparable(k)
            ? "These weights factor into a row times a column, so a separable variant can run them in two passes."
            : "These weights do not factor into a row times a column: a separable shortcut would change the kernel."))
        d.details.append(.figure(.plot(ContentFigures.kernelPlot(m, profile: nil, provenance: psf.provenance, summary: "the column sums: the line-spread function along x"))))
        if i.cls == .stochastic { d.details.append(.note("One realization copies a single random neighbour; the expected kernel above is what many realizations average to.", .computed)) }
        if i.cls == .iterativePDE { d.details.append(.note("H ≥ 0 only for λ ≤ ⅛; the explicit kernel itself stays non-negative, a monotone step response, up to λ = ¼ (SPEC §17 items 1, 23).", .computed)) }
    }

    static func fieldKernel(_ i: ContentPageInputs, _ d: inout ContentFloorDraft) {
        let n = 7, size = i.request.size
        var points: [PixelPoint] = [], kernels: [Kernel2D] = []
        for gy in 0..<n { for gx in 0..<n {
            let p = PixelPoint(x: Int((Double(gx) + 0.5) * Double(size.width) / Double(n)), y: Int((Double(gy) + 0.5) * Double(size.height) / Double(n)))
            if let psf = i.op.psf(at: p, i.request, content: i.context.content) { points.append(p); kernels.append(ContentFigures.trimmed(psf.kernel)) }
        } }
        if !kernels.isEmpty { d.figure = .psfField(PSFFieldSpec(gridSize: n, points: points, kernels: kernels)) }
        guard let psf = i.psf else { if d.figure == nil { d.emptyReason = "NO LOCAL PSF AT THE PROBE" }; return }
        let m = ContentKernelMath.principalMoments(psf.kernel)
        let nonZero = Double(psf.kernel.weights.filter { $0 != 0 }.count)
        d.numbers.append(LabeledValue(id: "taps", label: "LOCAL TAPS", value: .number(nonZero, ContentStyle.taps, psf.provenance)))
        d.numbers.append(LabeledValue(id: "along", label: "LOCAL σ ALONG", value: .number(m.along, ContentStyle.px2, psf.provenance)))
        d.numbers.append(LabeledValue(id: "across", label: "LOCAL σ ACROSS", value: .number(m.across, ContentStyle.px2, psf.provenance)))
        d.numbers.append(LabeledValue(id: "axis", label: "LOCAL AXIS", value: .number(m.degrees, NumberStyle.decimals(1, unit: "°", spokenUnit: "degrees"), psf.provenance)))
        let samples = i.plan.passes.map(\.tapsPerPixel).max() ?? nonZero
        d.numbers.append(LabeledValue(id: "samples", label: "SAMPLES PER PIXEL", value: .number(samples, ContentStyle.samples, .computed)))
        d.details.append(.figure(.heatmap(ContentFigures.kernelHeatmap(psf.kernel, caption: "THE PROBE'S OWN TAPS ON THE TEXEL GRID", provenance: psf.provenance))))
        d.details.append(.paragraph("A spot diagram: each cell of the grid is the PSF at that place in the image. A shift-invariant blur would draw the same shape everywhere."))
    }

    static func adaptiveKernel(_ i: ContentPageInputs, _ d: inout ContentFloorDraft) {
        guard let psf = i.psf, psf.provenance == .live || i.context.content != nil else {
            d.emptyReason = "LIVE WEIGHT MAP · NEEDS THE CURRENT IMAGE"
            if let taps = i.plan.passes.map(\.tapsPerPixel).max() {
                d.numbers.append(LabeledValue(id: "window", label: "WINDOW", value: .number(taps, ContentStyle.taps, .computed)))
            }
            return
        }
        let k = psf.kernel
        d.figure = .heatmap(ContentFigures.kernelHeatmap(k, caption: "LIVE · CPU WEIGHT MAP AT THE PROBE (THE EFFECTIVE PSF THERE)", provenance: .live))
        func live(_ v: Double, _ s: NumberStyle) -> BadgedValue { .number(v, s, .live, qualifiers: .cpu, caption: "CPU") }
        let total = k.sum
        let centre = (k.originX >= 0 && k.originX < k.width && k.originY >= 0 && k.originY < k.height && total != 0) ? k[k.originX, k.originY] / total : 0
        d.numbers.append(LabeledValue(id: "effective", label: "EFFECTIVE TAPS", value: live(ContentKernelMath.effectiveTaps(k), .decimals(1))))
        d.numbers.append(LabeledValue(id: "centre", label: "CENTRE WEIGHT", value: live(centre, NumberStyle.significant(3))))
        let m = ContentKernelMath.principalMoments(k)
        d.numbers.append(LabeledValue(id: "along", label: "σ ALONG", value: live(m.along, ContentStyle.px2)))
        d.numbers.append(LabeledValue(id: "across", label: "σ ACROSS", value: live(m.across, ContentStyle.px2)))
        if let taps = i.plan.passes.map(\.tapsPerPixel).max() {
            d.numbers.append(LabeledValue(id: "window", label: "WINDOW", value: .number(taps, ContentStyle.taps, .computed)))
        }
        d.details.append(.paragraph("Move the probe and this map changes: the weights depend on the values around it, which no LSI kernel ever does."))
    }

    static func rankKernel(_ i: ContentPageInputs, _ d: inout ContentFloorDraft) {
        let pill = ContentPills.sortedWindow(i)
        guard let plot = pill.plot, let ys = plot.series.first?.ys, !ys.isEmpty else {
            d.emptyReason = "SORTED WINDOW · NEEDS THE CURRENT IMAGE"
            d.numbers = rankNumbers(i)
            return
        }
        d.figure = .plot(plot)
        func live(_ v: Double) -> BadgedValue { .number(v, ContentStyle.probe(v), .live, qualifiers: .cpu, caption: "CPU") }
        d.numbers = rankNumbers(i)
        d.numbers.append(LabeledValue(id: "chosen", label: "CHOSEN VALUE", value: live(ys[ys.count / 2])))
        d.numbers.append(LabeledValue(id: "lowest", label: "LOWEST", value: live(ys.first ?? 0)))
        d.numbers.append(LabeledValue(id: "highest", label: "HIGHEST", value: live(ys.last ?? 0)))
        d.details.append(.paragraph("An impulse lands at one end of the sorted list and loses the vote: the middle value never belongs to it."))
    }

    static func systemKernel(_ i: ContentPageInputs, _ d: inout ContentFloorDraft) {
        var series: [PlotSeries] = []
        if let k = i.marginal {
            series.append(PlotSeries(name: "our model", xs: k.weights.indices.map { k.offset($0) }, ys: k.weights, style: .dashed, role: .reference, provenance: .modeled))
        }
        if let r = ContentSystem.calibrations(i).last, !r.fit.lsf.isEmpty {
            let lsf = r.fit.lsf, total = lsf.reduce(0, +), mean = lsf.indices.reduce(0.0) { $0 + Double($1) * lsf[$1] } / Swift.max(total, 1e-300)
            series.append(PlotSeries(name: "measured line-spread function", xs: lsf.indices.map { Double($0) - mean }, ys: lsf.map { $0 / Swift.max(total, 1e-300) },
                                     style: .points, role: .measured, provenance: .measured))
        }
        if !series.isEmpty {
            d.figure = .plot(PlotSpec(xAxis: PlotAxis(label: "offset", unit: "px"), yAxis: PlotAxis(label: "weight"), series: series,
                                      accessibilitySummary: "our model's kernel dashed beside the line-spread function measured offscreen"))
        } else {
            d.emptyReason = "SYSTEM INTERNALS · INFERRED"
        }
        d.numbers = ContentSystem.measuredFit(i)
    }

    // MARK: Floor 5 · ALGORITHM

    static func algorithm(_ i: ContentPageInputs) -> ContentFloorDraft {
        var d = ContentFloorDraft(inThisApp: "IN THIS APP · Pass counts and fetches are COMPUTED from the pass plan; the value after each pass is read LIVE from the real intermediate texture; per-pass milliseconds are MEASURED on this phone.")
        if i.cls == .atlas {
            d.emptyReason = "CPU ONLY IN THIS APP · TIER 3"
            d.details.append(.paragraph("This entry is an atlas page: BlurCore computes its curves on the CPU, and no GPU pipeline exists for it."))
            d.inThisApp = "IN THIS APP · Nothing on this floor runs: the entry is computed on the CPU only."
            return d
        }
        if i.cls == .system { return inferredLane(i, floor: .algorithm) }
        let plan = i.plan
        let timings = i.live.timedRun?.timing?.perPass ?? []
        d.figure = .passTiles(PassTilesSpec(passes: plan.passes, timings: timings, selected: nil))
        d.governingRule = algorithmRule(i)
        d.numbers.append(LabeledValue(id: "passes", label: "PASSES", value: .number(Double(plan.passes.count), ContentStyle.passes, .computed)))
        d.numbers.append(LabeledValue(id: "fetches", label: "FETCHES PER PIXEL", value: .number(plan.fetchesPerPixel.rounded(), ContentStyle.fetches, .computed)))
        // The alternatives: the same request under each other GPU variant.
        var alternatives: [LabeledValue] = []
        var disabledNotes: [ContentBlock] = []
        for v in i.entry.variants where v.runsOnGPU && v.id != i.resolution.variant {
            var r = i.request
            r.variant = v.id
            let altPlan = i.op.passPlan(r)
            let resolved = i.op.resolveVariant(r)
            var value = BadgedValue.number(altPlan.fetchesPerPixel.rounded(), ContentStyle.fetches, .computed)
            if let reason = i.op.disabledReason(v.id, r) {
                // A disabled variant has no honest count at these parameters: say so, and give the operator's reason.
                value = .words("DISABLED", spoken: "disabled: " + reason.lowercased(), .computed)
                disabledNotes.append(.note(reason, .computed))
            } else if resolved.variant != v.id {
                value.caption = "RESOLVES TO " + (i.entry.variant(resolved.variant)?.displayName.uppercased() ?? resolved.variant.rawValue.uppercased())
            }
            alternatives.append(LabeledValue(id: "alt-" + v.id.rawValue, label: v.displayName.uppercased() + " · FETCHES", value: value))
        }
        d.numbers += alternatives.prefix(2)
        if let run = i.fullRun, let probe = run.probe, !probe.perPass.isEmpty {
            for (n, value) in probe.perPass.enumerated().prefix(2) {
                let name = plan.passes.indices.contains(n) ? plan.passes[n].name : NumberStyle.integer().text(Double(n + 1))
                d.numbers.append(LabeledValue(id: "after-\(n)", label: "PROBE AFTER " + name, value: .number(ContentValues.scalar(value), ContentStyle.value4, .live)))
            }
        }
        d.numbers.append(LabeledValue(id: "intermediate", label: "INTERMEDIATE FORMAT", value: .words(ContentValues.words(i.settings.intermediate))))
        if alternatives.count > 2 { d.details.append(.values(Array(alternatives.dropFirst(2)))) }
        d.details += disabledNotes
        d.details.append(.table(TableBlock(columns: ["PASS", "KIND", "FETCHES PER PIXEL", "TAPS PER PIXEL", "SCALE"], rows: plan.passes.map {
            [$0.name, $0.kind.rawValue, NumberStyle.decimals(1).text($0.fetchesPerPixel), NumberStyle.decimals(0).text($0.tapsPerPixel), NumberStyle.decimals(3).text($0.outputScale)]
        }, caption: "The pass graph of the running variant", provenance: .computed)))
        if !timings.isEmpty, let run = i.live.timedRun {
            d.details.append(.values(timings.map { LabeledValue(id: "ms-\($0.passIndex)", label: "PASS " + $0.passName + " · GPU",
                                                                value: .number($0.medianMilliseconds, ContentStyle.ms, .measured, device: run.device)) }))
        }
        let curves = BlurServices.costModel.costCurve(for: i.op, request: i.request, sizes: [128, 256, 512, 894, 1024, 2048])
        if !curves.isEmpty {
            d.details.append(.figure(.plot(PlotSpec(xAxis: PlotAxis(label: "image side", unit: "px", logarithmic: true), yAxis: PlotAxis(label: "fetches per pixel"),
                                                    series: curves, accessibilitySummary: "fetches per pixel against image size for this family's algorithms"))))
        }
        if let reason = i.resolution.reason { d.details.insert(.note(reason, .computed), at: 0) }
        if i.cls == .globalFFT { d.details.append(.note("EVERY OUTPUT PIXEL DEPENDS ON EVERY INPUT PIXEL", .computed)) }
        if i.cls == .sparseIterated { d.details.append(.paragraph("A pyramid works at reduced resolution: the probe's phase within each level's grid decides which coarse texels it reads, which is why panning makes lights shimmer or snap.")) }
        for note in plan.notes { d.details.append(.note(note, .computed)) }
        return d
    }

    static func algorithmRule(_ i: ContentPageInputs) -> String {
        switch i.cls {
        case .separableFIR: return i.plan.passes.count == 1 ? "out = Σᵢ Σⱼ w[i]·w[j]·in(x − i, y − j)   (one 2-D gather)" : "out = V(H(in)):  rows first, then columns"
        case .sparseIterated: return "downsample → blur → upsample, one tile per level"
        case .recursive: return "causal pass, then anticausal pass, rows then columns"
        case .runningSum: return "scan rows, scan columns, then four reads per box"
        case .iterativePDE: return "u_(k+1) = u_k + λ·Δu_k, one tile per iteration batch"
        case .globalFFT: return "F → multiply by H → F⁻¹"
        case .adaptive: return "every tap weighs itself by the value it fetched"
        case .rank: return "sort or partially select the window"
        default: return "the passes of the running variant, in order"
        }
    }

    /// Floors 5–6 of system entries: the INFERRED lane (SPEC §5.1 floor 6 details).
    static func inferredLane(_ i: ContentPageInputs, floor: Floor) -> ContentFloorDraft {
        var d = ContentFloorDraft(inThisApp: "IN THIS APP · Everything on this floor is INFERRED: the render server runs this blur, and we can measure its output, not follow its passes.")
        d.emptyReason = "SYSTEM INTERNALS · INFERRED"
        d.dominantFallback = [.inferred]
        d.details = [
            .note("The render server (backboardd, INFERRED from the com.apple.CARenderServer registration) composites this effect outside the app.", .inferred),
            .note("Kernel names found in QuartzCore: tile_downsample_{1,2,4,8}, tile_simd_blur_{5…27}, downsample_blur_*, upsample_*, variable_blur_*", .inferred),
            .note("NAMES FROM iOS 26.5 SIM / macOS 27.2 · NOT RE-READ FOR iOS 27 · NOT OBSERVED RUNNING", nil),
            .note("WWDC 2014 described a five-pass downsample, blur and upsample pipeline for UIVisualEffectView.", .reference),
            .sources([SourceRef("gpu-pipeline.md §1.1 (QuartzCore kernel names)"), SourceRef("WWDC 2014 session 419, Advanced Graphics and Animations for iOS Apps")]),
        ]
        d.numbers = ContentSystem.measuredFit(i)
        return d
    }

    // MARK: Floor 6 · GPU (tabs Shader · Silicon)

    static func gpu(_ i: ContentPageInputs) -> ContentFloorDraft {
        if i.cls == .atlas {
            var d = ContentFloorDraft(inThisApp: "IN THIS APP · No GPU runs this entry: it is computed on the CPU only.")
            d.emptyReason = "CPU ONLY IN THIS APP · TIER 3"
            return d
        }
        if i.cls == .system {
            var d = inferredLane(i, floor: .gpu)
            d.tabs = [FloorTab(id: "silicon", title: "Silicon", dominantBadges: [.inferred], figure: nil, numbers: [], details: d.details),
                      FloorTab(id: "shader", title: "Shader", dominantBadges: [.inferred], figure: nil, numbers: [],
                               details: [.note("SYSTEM INTERNALS · INFERRED: Apple's shader source is not exposed.", .inferred)])]
            return d
        }
        let silicon = siliconTab(i)
        let shader = shaderTab(i)
        var d = ContentFloorDraft(inThisApp: "IN THIS APP · Dispatch geometry is COMPUTED from what the pipeline reported; limits and milliseconds are MEASURED on this phone; bytes and the bandwidth floor are MODELED; the source is REFERENCE: it is the code that ran.")
        d.tabs = [silicon, shader]
        d.figure = silicon.figure
        d.numbers = silicon.numbers
        d.governingRule = i.plan.passes.contains { $0.kind == .compute }
            ? "threadgroup = ⌊pixel / threads per group⌋ · lane = linear index mod SIMD width"
            : "one fragment per output pixel; the rasterizer's tile size is not published"
        d.dominantFallback = [.measured, .computed]
        if i.cls == .globalFFT { d.details.append(.note("EVERY OUTPUT PIXEL DEPENDS ON EVERY INPUT PIXEL", .computed)) }
        return d
    }

    /// The pass whose dispatch the overlay shows: the first traceable pass, else the first.
    static func probePassIndex(_ plan: PassPlan) -> Int { plan.passes.first(where: \.traceable)?.id ?? plan.passes.first?.id ?? 0 }

    static func siliconTab(_ i: ContentPageInputs) -> FloorTab {
        var numbers: [LabeledValue] = [], details: [ContentBlock] = []
        var figure: FigureSpec?
        let run = i.fullRun ?? i.live.run
        let plan = i.plan
        let p = i.probe
        if let run, let dispatch = run.dispatch.first(where: { $0.passIndex == probePassIndex(plan) }) ?? run.dispatch.first {
            let isCompute = dispatch.encoder == .compute && dispatch.threadsPerThreadgroup.prefix(2).allSatisfy { $0 > 0 }
            if isCompute {
                let tx = dispatch.threadsPerThreadgroup[0], ty = dispatch.threadsPerThreadgroup.count > 1 ? dispatch.threadsPerThreadgroup[1] : 1
                let group = [p.x / tx, p.y / Swift.max(ty, 1)], thread = [p.x % tx, p.y % Swift.max(ty, 1)]
                let linear = thread[1] * tx + thread[0], width = Swift.max(dispatch.threadExecutionWidth, 1)
                figure = .dispatchOverlay(DispatchOverlaySpec(dispatch: dispatch, apronTexels: plan.supportRadius ?? 0, probeThreadgroup: group,
                                                              probeThreadInGroup: thread, probeSIMDGroup: linear / width, probeLane: linear % width))
                let groups = Double(dispatch.threadgroups.reduce(1, *))
                numbers.append(LabeledValue(id: "groups", label: "THREADGROUPS", value: .number(groups, ContentStyle.groups, .computed)))
                numbers.append(LabeledValue(id: "probeThread", label: "PROBE THREAD · GROUP",
                                            value: .words("(\(thread[0]), \(thread[1])) · (\(group[0]), \(group[1]))",
                                                          spoken: "thread \(thread[0]), \(thread[1]) of threadgroup \(group[0]), \(group[1])", .computed)))
                let memory = Double(dispatch.staticThreadgroupMemoryBytes + dispatch.dynamicThreadgroupMemoryBytes)
                let measured = dispatch.staticThreadgroupMemoryBytes > 0
                numbers.append(LabeledValue(id: "tgMemory", label: "THREADGROUP MEMORY",
                                            value: measured ? .number(memory, ContentStyle.bytes, .measured, device: run.device)
                                                            : .number(memory, ContentStyle.bytes, .computed)))
                details.append(.values([
                    LabeledValue(id: "threads", label: "THREADS PER GROUP", value: .number(Double(dispatch.threadsPerThreadgroup.reduce(1, *)), ContentStyle.threads, .computed)),
                    LabeledValue(id: "simd", label: "PROBE SIMD GROUP", value: .number(Double(linear / width), .integer(), .computed)),
                    LabeledValue(id: "lane", label: "PROBE LANE", value: .number(Double(linear % width), .integer(), .computed)),
                    LabeledValue(id: "width", label: "SIMD WIDTH", value: .number(Double(width), ContentStyle.threads, .measured, device: run.device)),
                    LabeledValue(id: "maxThreads", label: "PIPELINE MAX THREADS", value: .number(Double(dispatch.pipelineMaxThreads), ContentStyle.threads, .measured, device: run.device)),
                ]))
            } else {
                numbers.append(LabeledValue(id: "fragments", label: "FRAGMENTS", value: .number(Double(dispatch.outputSize.pixelCount), .integer(noun: CountNoun("fragment", "fragments")), .computed)))
                numbers.append(LabeledValue(id: "probeThread", label: "PROBE FRAGMENT",
                                            value: .words("(\(p.x), \(p.y))", spoken: "fragment \(p.x), \(p.y)", .computed)))
                figure = .dispatchOverlay(DispatchOverlaySpec(dispatch: dispatch, apronTexels: plan.supportRadius ?? 0, probeThreadgroup: [],
                                                              probeThreadInGroup: [], probeSIMDGroup: 0, probeLane: 0))
                details.append(.note("32 × 32 is the maximum tile size in Apple's tables for Apple9; the tile size this pass actually uses is not published (UNVERIFIED).", .reference))
            }
            details.append(.table(TableBlock(columns: ["PASS", "ENCODER", "THREADGROUPS", "THREADS", "TG MEMORY", "OUTPUT"], rows: run.dispatch.map {
                [$0.name, $0.encoder.rawValue, $0.threadgroups.map { NumberStyle.integer().text(Double($0)) }.joined(separator: " × "),
                 $0.threadsPerThreadgroup.map { NumberStyle.integer().text(Double($0)) }.joined(separator: " × "),
                 NumberStyle.integer().text(Double($0.staticThreadgroupMemoryBytes + $0.dynamicThreadgroupMemoryBytes)),
                 "\(NumberStyle.integer().text(Double($0.outputSize.width))) × \(NumberStyle.integer().text(Double($0.outputSize.height)))"]
            }, caption: "Dispatch per pass, as encoded for the frame on screen", provenance: .computed)))
            if let gpu = run.gpu {
                var rows = [LabeledValue(id: "limitThreads", label: "MAX THREADS PER GROUP", value: .number(Double(gpu.maxThreadsPerThreadgroup), ContentStyle.threads, .measured, device: run.device)),
                            LabeledValue(id: "limitMemory", label: "MAX THREADGROUP MEMORY", value: .number(Double(gpu.maxThreadgroupMemoryLength), ContentStyle.bytes, .measured, device: run.device))]
                if gpu.forcedApple2Limits { rows = rows.map { var r = $0; r.value.caption = "FORCED APPLE2 LIMITS"; return r } }
                details.append(.values(rows))
                details.append(.note("Feature Set Tables: Apple9 allows 32 KB of threadgroup memory and 1,024 threads per threadgroup.", .reference))
            }
        } else {
            details.append(.note("DISPATCH GEOMETRY ARRIVES WITH THE FIRST FRAME", nil))
        }
        numbers.append(LabeledValue(id: "loads", label: "TEXTURE LOADS PER PIXEL", value: .number(plan.fetchesPerPixel.rounded(), ContentStyle.fetches, .computed)))
        // GPU time: MEASURED median of the settled timing Run, never in the Simulator.
        if let timed = i.live.timedRun, let timing = timed.timing, !timed.device.isSimulator {
            numbers.append(LabeledValue(id: "gpuMs", label: "GPU TIME", value: .number(timing.medianMilliseconds, ContentStyle.ms, .measured, device: timed.device,
                                                                                    caption: timing.thermalChanged ? "THERMAL CHANGED" : nil)))
            if let overhead = timing.overheadMilliseconds {
                details.append(.values([LabeledValue(id: "overhead", label: "OVERHEAD · WINDOW COPY AND COLOUR PASSES",
                                                     value: .number(overhead, ContentStyle.ms, .measured, device: timed.device))]))
            }
            if let fused = timing.fusedMedianMilliseconds {
                details.append(.values([LabeledValue(id: "fused", label: "FUSED PASSES", value: .number(fused, ContentStyle.ms, .measured, device: timed.device,
                                                                                                          caption: "MEASUREMENT OVERHEAD IS THE DIFFERENCE"))]))
            }
        } else if i.plan.fetchesPerFrame(i.request.size) > FetchBudget.full {
            let ms = i.plan.fetchesPerFrame(i.request.size) / FetchBudget.modeledFetchesPerSecond * 1000
            numbers.append(LabeledValue(id: "gpuMs", label: "GPU TIME", value: .number(ms, NumberStyle.significant(2, unit: "ms", spokenUnit: "milliseconds"), .modeled,
                                                                                    qualifiers: .weakSource, caption: "TOO SLOW TO TIME")))
        } else {
            numbers.append(LabeledValue(id: "gpuMs", label: "GPU TIME", value: (i.live.run?.device.isSimulator ?? false)
                ? .words("NO GPU TIMING IN SIMULATOR") : .notYetMeasured(unit: "ms")))
        }
        // Bytes and the bandwidth floor: MODELED, with their assumption (UNVERIFIED peak until This phone measures copy bandwidth).
        let bandwidth: BandwidthAssumption = {
            if let probe = i.live.probe(.copyBandwidthBlit), let gbps = probe.numbers["gigabytesPerSecond"] {
                return BandwidthAssumption(gigabytesPerSecond: gbps, label: "copy bandwidth measured on this phone", provenance: .modeled, qualifiers: [])
            }
            return .a17ProLeak
        }()
        let cost = run?.cost ?? BlurServices.costModel.cost(for: plan, size: i.request.size, intermediate: i.settings.intermediate, bandwidth: bandwidth)
        numbers.append(LabeledValue(id: "bytes", label: "BYTES MOVED", value: .number(cost.bytesMoved / 1e6, ContentStyle.megabytes, .modeled,
                                                                                     caption: "IDEAL CACHE")))
        let floorQualifiers: Qualifiers = cost.bandwidth.qualifiers.contains(.weakSource) ? .weakSource : []
        details.append(.values([LabeledValue(id: "floor", label: "BANDWIDTH FLOOR",
                                             value: .number(cost.floorMilliseconds, ContentStyle.ms, .modeled, qualifiers: floorQualifiers,
                                                            caption: floorQualifiers.isEmpty ? "AT THIS PHONE'S MEASURED COPY BANDWIDTH" : "UNVERIFIED PEAK")),
                                LabeledValue(id: "bandwidth", label: "ASSUMED BANDWIDTH",
                                             value: .number(cost.bandwidth.gigabytesPerSecond, NumberStyle.decimals(1, unit: "GB/s", spokenUnit: "gigabytes per second"),
                                                            .modeled, qualifiers: floorQualifiers, caption: floorQualifiers.isEmpty ? nil : "LEAK-DERIVED · UNVERIFIED PEAK"))]))
        // Pass timeline: MEASURED bars per pass, MODELED ghost bars (each pass's bytes at the assumed bandwidth).
        let perPass = i.live.timedRun?.timing?.perPass ?? []
        var timeline: [LabeledValue] = []
        for (n, pass) in plan.passes.enumerated() {
            if let t = perPass.first(where: { $0.passIndex == pass.id }), let timed = i.live.timedRun, !timed.device.isSimulator {
                timeline.append(LabeledValue(id: "timeline-\(pass.id)", label: "PASS " + pass.name, value: .number(t.medianMilliseconds, ContentStyle.ms, .measured, device: timed.device)))
            }
            if cost.perPassBytes.indices.contains(n) {
                timeline.append(LabeledValue(id: "ghost-\(pass.id)", label: "PASS " + pass.name + " · FLOOR",
                                             value: .number(cost.perPassBytes[n] / (cost.bandwidth.gigabytesPerSecond * 1e9) * 1000, ContentStyle.ms, .modeled,
                                                            qualifiers: floorQualifiers, caption: floorQualifiers.isEmpty ? "GHOST BAR" : "GHOST BAR · UNVERIFIED PEAK")))
            }
        }
        if !timeline.isEmpty { details.append(.disclosure(title: "Pass timeline", blocks: [.values(timeline)])) }
        // This phone's own probes that bear on this floor (GPU-MEASURE's rows keep their badges).
        let probeRows = [DeviceProbeKind.compressionAB, .counterSamplingPoints, .copyBandwidthBlit, .tracedEqualsUntraced].compactMap { i.live.probe($0) }.flatMap(\.rows)
        if !probeRows.isEmpty { details.append(.disclosure(title: "Measured on this phone", blocks: [.values(probeRows)])) }
        details.append(.note("Render targets written without shaderWrite keep lossless compression on Apple9; compute outputs lose it.", .reference))
        details.append(.sources([SourceRef("Apple Tech Talk 111431 (lossless compression)"), SourceRef("Metal Feature Set Tables"), SourceRef("gpu-pipeline.md §2.5 (bandwidth)")]))
        let badges: [Provenance] = run == nil ? [.computed, .modeled] : [.measured, .computed]
        return FloorTab(id: "silicon", title: "Silicon", dominantBadges: badges, figure: figure, numbers: numbers, details: details)
    }

    static func shaderTab(_ i: ContentPageInputs) -> FloorTab {
        guard let run = i.live.run, let shader = run.shader else {
            return FloorTab(id: "shader", title: "Shader", dominantBadges: [.reference], figure: nil, numbers: [],
                            details: [.note("SHADER PROVENANCE ARRIVES WITH THE FIRST FRAME", nil)])
        }
        var numbers: [LabeledValue] = [
            LabeledValue(id: "file", label: "FILE", value: .words(shader.fileName, spoken: shader.fileName, .reference, source: SourceRef("ShaderManifest.json (bundled)"))),
            LabeledValue(id: "mathMode", label: "MATH MODE", value: .words(shader.mathMode.uppercased(), .reference, source: SourceRef("ShaderManifest.json (bundled)"))),
            LabeledValue(id: "language", label: "LANGUAGE", value: .words("MSL " + shader.languageVersion, spoken: "metal shading language " + shader.languageVersion, .reference,
                                                                           source: SourceRef("ShaderManifest.json (bundled)"))),
            LabeledValue(id: "build", label: "BUILD", value: .words(shader.traced ? "TRACED" : "UNTRACED", .reference, source: SourceRef("Run shader provenance"))),
        ]
        var details: [ContentBlock] = [.values([LabeledValue(id: "functions", label: "FUNCTIONS",
                                                             value: .number(Double(shader.functionNames.count), .integer(noun: CountNoun("function", "functions")), .reference,
                                                                            source: SourceRef("ShaderManifest.json (bundled)")))]),
                                       .code(CodeBlock(language: "text", text: shader.functionNames.joined(separator: "\n")))]
        var figure: FigureSpec?
        if let text = i.shaderSources.source(fileName: shader.fileName) {
            let hash = ContentSHA256.hex(text)
            if hash.lowercased() == shader.fileSHA256.lowercased() {
                let listing = ContentShaderListing.parse(text, sha256: shader.fileSHA256, traced: shader.traced, functions: shader.functionNames)
                figure = .code(listing.code)
                numbers.append(LabeledValue(id: "sha", label: "SHA-256", value: .words(String(shader.fileSHA256.prefix(16)) + "…", spoken: "matches the run's stamp", .reference,
                                                                                   source: SourceRef("ShaderManifest.json (bundled)"))))
            } else {
                details.insert(.note("SOURCE CHECK FAILED · SHA-256 OF THE BUNDLED FILE DIFFERS FROM THE RUN'S STAMP", nil), at: 0)
            }
        } else {
            details.insert(.note("SOURCE TEXT IS NOT IN THIS BUILD'S BUNDLE", nil), at: 0)
        }
        details.append(.values([LabeledValue(id: "combined", label: "COMBINED SHA-256", value: .words(String(shader.combinedSHA256.prefix(16)) + "…",
                                                                                                      spoken: "combined source hash", .reference,
                                                                                                      source: SourceRef("ShaderManifest.assemble")))]))
        details.append(.paragraph("This is the text compiled into the shipped library; a build-time check proves the bundled copy byte-identical, and the device never recompiles it."))
        return FloorTab(id: "shader", title: "Shader", dominantBadges: [.reference], figure: figure, numbers: numbers, details: details)
    }

    // MARK: Floor 7 · PIXELS

    static func pixels(_ i: ContentPageInputs) -> ContentFloorDraft {
        var d = ContentFloorDraft(inThisApp: "IN THIS APP · IN and OUT are read LIVE from the GPU for the frame on screen; the encoding, the branch and the CPU reference are COMPUTED by BlurCore in Double; the difference is MEASURED on this phone.")
        d.dominantFallback = [.live, .computed]
        if i.cls == .system {
            d.numbers = ContentSystem.measuredFit(i)
            d.emptyReason = ContentSystem.calibrations(i).isEmpty ? "OFFSCREEN VALUES ARRIVE WITH CALIBRATE" : nil
            d.inThisApp = "IN THIS APP · System values are MEASURED offscreen through ImageRenderer, never read from the screen."
            d.details.append(.note("SYSTEM · MEASURED (OFFSCREEN): the on-screen composite is not read back.", .inferred))
            return d
        }
        let p = i.probe
        let options = ReferenceOptions.forDevice(i.live.deviceProbes) ?? .parity
        let run = i.fullRun
        var cpuGrid: ImageBuffer?
        if let content = i.context.content, content.image.size.contains(p) {
            let region = ContentProbeReference.region(around: p, side: 9, in: content.image.size)
            if let out = ContentProbeReference.output(i.op, input: content.image, auxiliary: content.auxiliary, i.request, region: region, options: options) {
                var post = ColourTransform.post(out, i.settings)
                if options.emulateHalfStorage { post = post.roundedToHalf() }
                cpuGrid = post
            }
            let inRegion = ContentProbeReference.region(around: p, side: 9, in: content.image.size)
            let raw = ColourTransform.post(content.image.crop(inRegion), i.settings)
            let inGrid = TexelGridSpec(size: 9, origin: inRegion.origin, channel: .luma, values: raw.pixels.map { ContentValues.scalar($0) },
                                       weights: nil, highlighted: [p], provenance: run == nil ? .computed : .live)
            if let out = run?.trace?.passes.last?.neighbourhoodOut, out.count == 81 {
                let outGrid = TexelGridSpec(size: 9, origin: inRegion.origin, channel: .luma, values: out.map { ContentValues.scalar($0) }, weights: nil,
                                            highlighted: [p], provenance: run?.trace?.passes.last?.source.provenance ?? .computed)
                d.figure = .pair(.texelGrid(inGrid), .texelGrid(outGrid))
            } else if let cpu = cpuGrid {
                let outGrid = TexelGridSpec(size: 9, origin: inRegion.origin, channel: .luma, values: cpu.pixels.map { ContentValues.scalar($0) }, weights: nil,
                                            highlighted: [p], provenance: .computed)
                d.figure = .pair(.texelGrid(inGrid), .texelGrid(outGrid))
            }
        }
        let regionOrigin = cpuGrid.map { _ in ContentProbeReference.region(around: p, side: 9, in: i.request.size).origin }
        let cpuValue: SIMD4<Double>? = {
            guard let grid = cpuGrid, let o = regionOrigin else { return nil }
            return SIMD4<Double>(grid[p.x - o.x, p.y - o.y])
        }()
        // IN and OUT: LIVE from the GPU readback; else the canvas input and the CPU output (COMPUTED).
        if let probe = run?.probe {
            let vin = ContentValues.scalar(probe.input), vout = ContentValues.scalar(probe.output)
            d.numbers.append(LabeledValue(id: "in", label: "IN", value: .number(vin, ContentStyle.probe(vin), .live)))
            d.numbers.append(LabeledValue(id: "out", label: "OUT", value: .number(vout, ContentStyle.probe(vout), .live)))
        } else if let content = i.context.content, content.image.size.contains(p) {
            let raw = ColourTransform.post(content.image.crop(PixelRegion(origin: p, size: .square(1))), i.settings)
            let vin = ContentValues.scalar(raw[0, 0])
            d.numbers.append(LabeledValue(id: "in", label: "IN", value: .number(vin, ContentStyle.probe(vin), .computed)))
            if let c = cpuValue {
                let v = ContentValues.scalar(c)
                d.numbers.append(LabeledValue(id: "out", label: "OUT (CPU)", value: .number(v, ContentStyle.probe(v), .computed)))
            }
        }
        let shownOut: Double? = run?.probe.map { ContentValues.scalar($0.output) } ?? cpuValue.map { ContentValues.scalar($0) }
        if let out = shownOut {
            d.numbers.append(LabeledValue(id: "encoded", label: "OUT ENCODED", value: .number(Double(SRGB.code8(linear: out)), ContentStyle.code8, .computed)))
        }
        if let content = i.context.content, let branch = ContentProbeReference.colourBranch(i.op, content: content, i.request, probe: p) {
            let label = branch.settings.colourSpace == .srgbEncoded ? "IF sRGB-ENCODED" : "IF LINEAR LIGHT"
            d.numbers.append(LabeledValue(id: "branch", label: label, value: .number(Double(SRGB.code8(linear: ContentValues.scalar(branch.value))), ContentStyle.code8, .computed)))
        }
        if let c = cpuValue {
            let v = ContentValues.scalar(c)
            d.numbers.append(LabeledValue(id: "cpu", label: "CPU REFERENCE", value: .number(v, ContentStyle.probe(v), .computed)))
        }
        if let probe = run?.probe, let c = cpuValue, let run {
            let gpu = ContentValues.scalar(probe.output), cpu = ContentValues.scalar(c)
            let lsb = Double(abs(SRGB.code8(linear: gpu) - SRGB.code8(linear: cpu)))
            let ulps = abs(gpu - cpu) / Double(HalfFloat.ulp(Float(Swift.max(abs(cpu), 1.0 / 16384))))
            d.numbers.append(LabeledValue(id: "diff", label: "|GPU − CPU|", value: .number(lsb, ContentStyle.lsb, .measured, device: run.device)))
            d.details.append(.values([LabeledValue(id: "diffUlp", label: "|GPU − CPU| IN HALF-FLOAT ULPS", value: .number(ulps, ContentStyle.ulp, .measured, device: run.device))]))
        } else if run == nil {
            d.numbers.append(LabeledValue(id: "diff", label: "|GPU − CPU|", value: .notYetMeasured(unit: "LSB")))
        }
        if let parity = run?.parity, let run {
            d.details.append(.values([
                LabeledValue(id: "parityMax", label: "PARITY · 128² CROP · MAX", value: .number(parity.stats.maxLSB8, ContentStyle.lsb, .measured, device: run.device,
                                                                                            caption: parity.passed ? "WITHIN TOLERANCE" : "GPU DIFFERS FROM THE MATH ⚠︎")),
                LabeledValue(id: "parityUlp", label: "PARITY · MAX HALF-FLOAT ULPS", value: .number(parity.stats.maxULP16, ContentStyle.ulp, .measured, device: run.device)),
            ]))
        }
        if d.numbers.isEmpty && d.figure == nil { d.emptyReason = "WAITING FOR THE FIRST FRAME" }
        d.details.append(.paragraph("The rounding chain: the GPU accumulates in float, stores half floats between passes, and the display encodes to eight-bit sRGB."))
        if i.cls == .atlas {
            d.details.insert(.note("CPU · 128² CROP · COMPUTED: this entry runs on the CPU only.", .computed), at: 0)
            d.inThisApp = "IN THIS APP · Values are COMPUTED by BlurCore on the CPU; nothing on this page was produced by a GPU."
        }
        if i.cls == .rank { d.details.append(.paragraph("The impulse loses the vote: a rank filter returns one of the window's own values.")) }
        if i.cls == .stochastic { d.details.append(.paragraph("One realization copies one random neighbour per pixel; the mean of many converges to the expected kernel.")) }
        return d
    }
}
