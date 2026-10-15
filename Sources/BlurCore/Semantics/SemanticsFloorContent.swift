import Foundation

// OWNER: SEMANTICS. Floor 1 (SLIDE) data built from the conventions: the tool bars (home tool first, forward and
// reverse), the primary numbers, the pt → px chain, and "the same word radius means at least sixteen things"
// (STACK §8) for any typed value, each σ and edge width with its badge. CONTENT-LAYERS composes the page from these.

public extension ToolConventions {
    /// This phone's laws from Calibrate results (`LiveFacts.calibrations` or the Run log), one per subject, fitted by
    /// `BlurServices.psfFitter` (CALIBRATION). Subjects with fewer than three results have no law yet, so their
    /// conventions stay on the Mac law with `.notThisDevice`.
    static func measuredLaws(from results: [CalibrationResult]) -> [CalibrationLaw] {
        let bySubject = Dictionary(grouping: results.filter { !$0.device.isSimulator || results.allSatisfy(\.device.isSimulator) },
                                   by: \.request.subject)
        return CalibrationSubject.allCases.compactMap { subject in
            guard let sweep = bySubject[subject], sweep.count >= 3 else { return nil }
            return BlurServices.psfFitter.law(sweep)
        }
    }

    /// The calibration law in `laws` for a control's subject, if any.
    static func law(for control: SemanticsControl, in laws: [CalibrationLaw]) -> CalibrationLaw? {
        guard let s = control.calibrationSubject else { return nil }
        return laws.last { $0.subject == s }
    }

    /// Tool ids to show for `blur`, home tool first. Tools that do not offer the blur are omitted, except the home tool,
    /// which always leads ("—"). For `drop-shadow` the P27 conventions follow the home tool, then the remaining tools.
    static func barToolIDs(blur: BlurID, homeToolID: String) -> [String] {
        var ids = [homeToolID]
        let offering = SemanticsCatalog.barOrder.filter { offers(toolID: $0, blur: blur) }
        if blur == "drop-shadow" {
            let duplicates: [String: String] = ["swiftui": "swiftui-shadow", "css": "css-box-shadow", "figma": "figma-shadow",
                                                "sketch": "sketch-shadow", "photoshop": "photoshop-shadow"]
            let skip = duplicates[homeToolID]
            ids += SemanticsCatalog.shadowConventionIDs.filter { $0 != skip && $0 != homeToolID }
            ids += offering.filter { duplicates[$0] == nil && $0 != homeToolID }
        } else {
            ids += offering.filter { $0 != homeToolID }
        }
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    /// Floor 1 bars, forward: what to type in each tool for σ = `sigmaPx` (SPEC §5.1 floor 1).
    static func toolBars(blur: BlurID, sigmaPx: Double, displayScale: Double, homeToolID: String,
                         measuredLaws: [CalibrationLaw] = []) -> ToolBarsSpec {
        let rows = barToolIDs(blur: blur, homeToolID: homeToolID).flatMap { id -> [LabeledValue] in
            let law = SemanticsCatalog.control(toolID: id, blur: blur).flatMap { self.law(for: $0, in: measuredLaws) }
            return readings(toolID: id, blur: blur, sigmaPx: sigmaPx, displayScale: displayScale, measuredLaw: law)
                .map { LabeledValue(id: $0.id, label: $0.label, value: $0.value) }
        }
        return ToolBarsSpec(rows: rows, homeToolID: homeToolID, reverseMode: false)
    }

    /// Floor 1 bars, reverse ("you typed 10: σ per tool").
    static func reverseToolBars(blur: BlurID, typed: Double, displayScale: Double, homeToolID: String,
                                measuredLaws: [CalibrationLaw] = []) -> ToolBarsSpec {
        let rows = barToolIDs(blur: blur, homeToolID: homeToolID).flatMap { id -> [LabeledValue] in
            let law = SemanticsCatalog.control(toolID: id, blur: blur).flatMap { self.law(for: $0, in: measuredLaws) }
            return reverseReadings(toolID: id, blur: blur, typed: typed, displayScale: displayScale, measuredLaw: law)
                .map { LabeledValue(id: $0.id, label: $0.label, value: $0.value) }
        }
        return ToolBarsSpec(rows: rows, homeToolID: homeToolID, reverseMode: true)
    }

    /// Floor 1's primary numbers (≤ 6): the home tool's value, then up to five other tools, numbers before words.
    static func primaryNumbers(_ bars: ToolBarsSpec) -> [LabeledValue] {
        guard let home = bars.rows.first else { return [] }
        let others = bars.rows.dropFirst()
        let numeric = others.filter { $0.value.value != nil }
        let words = others.filter { $0.value.value == nil && $0.value.text != "—" }
        return [home] + Array((numeric + words).prefix(5))
    }

    /// The unit chain of a typed value ("1.33 pt × 3 = 4.00 px → σ 4.00 px"), or nil when the tool has no law for the
    /// blur. The typed value is an input (no badge); px is COMPUTED; σ carries the convention's badge.
    static func unitChain(toolID: String, blur: BlurID, typed: Double, displayScale: Double, measuredLaw: CalibrationLaw?) -> BadgedLine? {
        guard let c = SemanticsCatalog.control(toolID: toolID, blur: blur), c.isOfferedWithLaw, typed.isFinite, typed >= 0 else { return nil }
        var sigma = sigmaPx(toolID: toolID, blur: blur, typed: typed, displayScale: displayScale, measuredLaw: measuredLaw)
        if let v = sigma.value, let tool = SemanticsCatalog.tool(toolID) {
            // The chain already says what was typed: speak σ as a number with its badge only.
            let lead = "sigma " + NumberStyle.significant(3, unit: "px", spokenUnit: "pixels").spoken(v) + " from "
            let tail = " in " + tool.name
            if sigma.spoken.hasPrefix(lead), let r = sigma.spoken.range(of: tail) {
                sigma.spoken = NumberStyle.significant(3, unit: "px", spokenUnit: "pixels").spoken(v) + sigma.spoken[r.upperBound...]
            }
        }
        var segments: [BadgedSegment] = [.value(.input(typed, c.typedStyle))]
        if c.scalesWithDisplay {
            let scaleStyle: NumberStyle = displayScale.rounded() == displayScale ? .integer() : .significant(3)
            segments += [.literal("× " + scaleStyle.text(displayScale) + " ="),
                         .value(.number(typed * displayScale, .significant(3, unit: "px", spokenUnit: "pixels"), .computed))]
        }
        segments += [.text("→ σ"), .value(sigma)]
        return BadgedLine(segments)
    }

    /// Floor 1 facts for the page builder: the bars as the figure (forward, or reverse when `reverseTyped` is set), the
    /// primary numbers, the home tool's law as the governing rule, and in details the full conventions of STACK §8 for
    /// the typed value, the unit chain and the sources.
    static func slideFloorFacts(blur: BlurID, sigmaPx: Double?, displayScale: Double, homeToolID: String,
                                measuredLaws: [CalibrationLaw] = [], reverseTyped: Double? = nil) -> FloorFacts {
        let controls = SemanticsCatalog.controls(for: blur)
        let bars: ToolBarsSpec
        if let typed = reverseTyped {
            bars = reverseToolBars(blur: blur, typed: typed, displayScale: displayScale, homeToolID: homeToolID, measuredLaws: measuredLaws)
        } else if let sigma = sigmaPx {
            bars = toolBars(blur: blur, sigmaPx: sigma, displayScale: displayScale, homeToolID: homeToolID, measuredLaws: measuredLaws)
        } else {
            let rows = barToolIDs(blur: blur, homeToolID: homeToolID).map { id in
                LabeledValue(id: id, label: SemanticsCatalog.tool(id)?.label ?? id.uppercased(),
                             value: slideChipValue(toolID: id, blur: blur, sigmaPx: nil, displayScale: displayScale, measuredLaw: nil))
            }
            bars = ToolBarsSpec(rows: rows, homeToolID: homeToolID, reverseMode: false)
        }
        let home = SemanticsCatalog.control(toolID: homeToolID, blur: blur)
        let rule = home?.lawDescription.map { "\(home!.controlName): \($0)" }
            ?? controls.first(where: { $0.isOfferedWithLaw }).flatMap { c in c.lawDescription.map { "\(c.controlName): \($0)" } }

        var details: [ContentBlock] = []
        let typedForTable = reverseTyped ?? 10
        let meanings = radiusMeanings(typed: typedForTable, displayScale: displayScale, measuredLaws: measuredLaws)
        details.append(.disclosure(title: "THE SAME NUMBER IN EVERY TOOL", blocks: [
            .paragraph("Type one number into each tool and you get a different σ. Each row says what that number is, the σ it gives on this display, and how wide a hard edge becomes."),
            .values(meanings.map { LabeledValue(id: $0.id + "-sigma", label: $0.label, value: $0.sigma) }),
            .disclosure(title: "EDGE WIDTH, TEN TO NINETY PERCENT", blocks: [
                .values(meanings.map { LabeledValue(id: $0.id + "-edge", label: $0.label, value: $0.edgeWidth) }),
            ]),
        ]))
        if let home, let t = reverseTyped ?? sigmaPx.flatMap({ typedValue(toolID: homeToolID, blur: blur, sigmaPx: $0, displayScale: displayScale,
                                                                          measuredLaw: law(for: home, in: measuredLaws)).value }),
           let chain = unitChain(toolID: homeToolID, blur: blur, typed: t, displayScale: displayScale, measuredLaw: law(for: home, in: measuredLaws)) {
            details.append(.values([LabeledValue(id: "chain-typed", label: "YOU TYPE", value: chain.values.first ?? .input(t, home.typedStyle)),
                                    LabeledValue(id: "chain-sigma", label: "σ HERE", value: chain.values.last ?? .notYetMeasured())]))
        }
        let laws = controls.compactMap { c -> String? in
            guard let d = c.lawDescription else { return nil }
            return "\(SemanticsCatalog.tool(c.toolID)?.name ?? c.toolID) \(c.controlName): \(d)"
        }
        if !laws.isEmpty { details.append(.disclosure(title: "EACH TOOL'S LAW", blocks: laws.map { .equation($0) })) }
        var seen = Set<String>()
        let sources = controls.map(\.source).filter { seen.insert($0.citation).inserted }
        if !sources.isEmpty { details.append(.sources(sources)) }

        let empty = controls.isEmpty ? "NO TOOL HERE OFFERS THIS BLUR · SEE WHERE IT LIVES" : nil
        return FloorFacts(numbers: primaryNumbers(bars), figure: .toolBars(bars), governingRule: rule, details: details, tabs: nil,
                          emptyReason: empty)
    }

    // MARK: The same "radius" in every tool (STACK §8)

    /// STACK §8 for any typed value `v` at this display: what `v` is in each tool, the σ it gives (device px) and the
    /// 10–90 % width of a hard edge through that kernel. Sorted by σ, largest first. At display scale 1 and v = 10 it
    /// reproduces STACK's table (SwiftUI with the ARCHITECTURE law 0.90·r).
    static func radiusMeanings(typed v: Double, displayScale s: Double, measuredLaws: [CalibrationLaw] = []) -> [SemanticsRadiusMeaning] {
        let scale = max(s, 1e-9)
        func reading(_ tool: String, _ blur: BlurID) -> [SemanticsReading] {
            let law = SemanticsCatalog.control(toolID: tool, blur: blur).flatMap { self.law(for: $0, in: measuredLaws) }
            return reverseReadings(toolID: tool, blur: blur, typed: v, displayScale: scale, measuredLaw: law)
        }
        func edge(_ shape: SemanticsMath.KernelShape, _ p: Provenance, caption: String? = nil) -> BadgedValue {
            .number(SemanticsMath.edgeWidth(shape), .significant(3, unit: "px", spokenUnit: "pixels"), p, caption: caption)
        }
        func computed(_ sigma: Double, _ p: Provenance, _ source: SourceRef) -> BadgedValue {
            .number(sigma, .significant(3, unit: "px", spokenUnit: "pixels"), p, source: source)
        }
        var rows: [SemanticsRadiusMeaning] = []
        func add(_ id: String, _ label: String, _ who: String, _ what: String, _ kernel: String, _ sigma: BadgedValue, _ edgeWidth: BadgedValue) {
            rows.append(SemanticsRadiusMeaning(id: id, label: label, who: who, what: what, kernel: kernel, sigma: sigma, edgeWidth: edgeWidth))
        }
        func gaussianRow(_ id: String, _ label: String, _ who: String, _ what: String, _ r: SemanticsReading) {
            add(id, label, who, what, "Gaussian", r.value, edge(.gaussian(sigma: r.value.value ?? 0), .computed))
        }

        if let r = reading("css", "gaussian-blur").first {
            gaussianRow("css", "CSS BLUR() · SVG · FLUTTER", "CSS filter: blur(), SVG stdDeviation, Flutter sigmaX (Skia), GraphicsContext.Filter.blur",
                        "σ, in points or CSS px", r)
        }
        if let r = reading("coreimage", "gaussian-blur").first {
            gaussianRow("coreimage", "CIGAUSSIANBLUR · MPS", "CIGaussianBlur inputRadius, MPSImageGaussianBlur sigma", "σ, in image px", r)
        }
        if let r = reading("gimp", "gaussian-blur").first {
            gaussianRow("gimp", "GIMP · OPENCV · IMAGEMAGICK", "GIMP 2.10 Size, OpenCV sigmaX, ImageMagick -blur 0xσ", "σ, in image px", r)
        }
        if let r = reading("sketch", "gaussian-blur").first, let sigma = r.value.value {
            add("sketch", "SKETCH", "Sketch layer blur", "σ, in points", "Gaussian cut at about ±2.5σ", r.value,
                edge(SemanticsMath.truncatedGaussian(effectiveSigma: sigma, cutInSigmas: 2.5), .modeled))
        }
        if let r = reading("swiftui", "gaussian-blur").first, let sigma = r.value.value {
            let law = swiftUIBlurLaw(displayScale: scale, measuredLaw: measuredLaws.last { $0.subject == .swiftUIBlur })
            let above = v > (law.switchParameter ?? .infinity)
            add("swiftui", "SWIFTUI .BLUR", "SwiftUI .blur(radius:), offscreen renderer", "nominal σ in points; a cheaper kernel above the switch",
                above ? "box-cubed-like" : "sampled Gaussian", r.value,
                above ? edge(.boxes([2 * sigma, 2 * sigma, 2 * sigma]), .modeled, caption: "BOX-CUBED MODEL") : edge(.gaussian(sigma: sigma), .computed))
        }
        if let r = reading("svg", "iterated-box").first, let sigma = r.value.value {
            let sv = v < 2 ? 0 : SemanticsMath.svgThreeBoxWidth(stdDeviation: v)
            let shape: SemanticsMath.KernelShape = sv == 0 ? .gaussian(sigma: sigma)
                : .boxes(Int(sv) % 2 == 1 ? [sv, sv, sv].map { $0 * scale } : [sv, sv, sv + 1].map { $0 * scale })
            add("svg-three-box", "SVG THREE-BOX RULE", "SVG and Skia raster three-box approximation of stdDeviation",
                "box width d = ⌊1.88·s + 0.5⌋, three passes", "piecewise quadratic", r.value, edge(shape, .computed))
        }
        do {
            let sigma = SemanticsMath.impellerEffectiveSigma(v) * scale
            let sp = SemanticsMath.impellerScaledSigma(v)
            let h = 3.0.squareRoot() * (sp - 0.5)
            var value = computed(sigma, .computed, SemanticsSources.flutterImpeller)
            value.caption = "TAP ROUNDING UNVERIFIED"
            value.spoken += ", tap rounding unverified"
            add("impeller", "FLUTTER IMPELLER", "Flutter ImageFilter.blur sigmaX on Impeller", "σ′ = ScaleSigma(σ), cut at ±√3·(σ′ − 0.5)",
                "truncated Gaussian", value, edge(.truncatedGaussian(sigma0: sp * scale, halfWidth: max(h, 0.5) * scale), .computed))
        }
        if let r = reading("android", "gaussian-blur").first {
            gaussianRow("android", "ANDROID RENDEREFFECT", "Android RenderEffect, BlurMaskFilter, Skia ConvertRadiusToSigma (px)",
                        "σ = 0.57735·r + 0.5", r)
        }
        do {
            let w = 2 * v.rounded() + 1
            add("box-radius", "BOX RADIUS · MPSIMAGEBOX", "a box blur radius in the usual 2r + 1 sense; MPSImageBox and vImage width 2r + 1",
                "half-width of a box", "box", computed(SemanticsMath.boxSigma(width: w), .computed, SemanticsSources.vImage),
                edge(.boxes([w]), .computed))
        }
        do {
            let sigma = SemanticsMath.skiaSigmaScale * max(v, 0)
            add("android-window", "ANDROID WINDOW BLUR", "Window.setBackgroundBlurRadius, Gaussian variant", "σ = 0.57735·r at quarter resolution",
                "Gaussian (Kawase on many builds)", computed(sigma, .reference, SemanticsSources.surfaceFlinger), edge(.gaussian(sigma: sigma), .computed))
        }
        if let r = reading("css-box-shadow", "drop-shadow").first {
            gaussianRow("box-shadow", "CSS BOX-SHADOW · CANVAS", "CSS box-shadow and text-shadow blur, canvas shadowBlur", "2σ: the shadow blur radius", r)
        }
        if let r = reading("figma", "gaussian-blur").first {
            gaussianRow("figma", "FIGMA BLUR", "Figma layer and background blur", "2σ (from its CSS export)", r)
        }
        for (i, r) in reading("calayer-shadow", "drop-shadow").enumerated() {
            let sigma = r.value.value ?? 0, b = 6.0.squareRoot() * sigma   // a tent of two boxes of width b has σ² = b²/6
            add(i == 0 ? "calayer" : "calayer-alt", r.label == "CALAYER" ? "CALAYER · STACK" : r.label, "CALayer.shadowRadius",
                i == 0 ? "2σ (one research reading)" : "about 1.1σ (the other reading)", i == 0 ? "Gaussian" : "tent-like", r.value,
                i == 0 ? edge(.gaussian(sigma: sigma), .computed) : edge(.boxes([b, b]), .modeled, caption: "TENT MODEL"))
        }
        if let r = reading("coreimage", "disc-blur").first, let sigma = r.value.value {
            add("disc", "CIDISCBLUR · LENS IRIS", "CIDiscBlur and CIBokehBlur radius, a lens iris radius", "disc radius", "uniform disc", r.value,
                edge(.disc(radius: 2 * sigma), .computed))
        }
        do {
            let w = 2 * v.rounded() + 1, a = (w + 1) / 2
            add("tent", "TENT · MPSIMAGETENT", "MPSImageTent and vImageTentConvolve width 2r + 1", "half-width of a tent", "triangle",
                computed(SemanticsMath.tentSigma(width: w), .computed, SemanticsSources.vImage), edge(.boxes([a, a]), .computed))
        }
        do {
            let sigma = v > 0 ? 0.3 * v + 0.6 : 0
            add("hwui-legacy", "ANDROID HWUI LEGACY", "Android hwui legacy weight generator", "σ = 0.3·r + 0.6", "Gaussian",
                computed(sigma, .reference, SemanticsSources.hwuiLegacy), edge(.gaussian(sigma: sigma), .computed))
        }
        do {
            let sigma = SemanticsMath.opencvSigma(kernelRadius: v)
            add("opencv-ksize", "OPENCV KSIZE ONLY", "OpenCV GaussianBlur(ksize: 2r + 1, sigmaX: 0)", "kernel half-width; σ from the size",
                "Gaussian", computed(sigma, .reference, SemanticsSources.opencv), edge(.gaussian(sigma: sigma), .computed))
        }
        do {
            let sigma = max(v, 0) / 3
            add("three-sigma", "KERNEL RADIUS IS THREE σ", "“kernel radius = 3σ” (Skia's ⌈3σ⌉ support read backwards)", "truncation support",
                "Gaussian", computed(sigma, .computed, SemanticsSources.threeSigma), edge(.gaussian(sigma: sigma), .computed))
        }
        if let r = reading("gimp-2.8", "gaussian-blur").first {
            gaussianRow("gimp-2.8", "GIMP 2.8", "GIMP 2.8 Gaussian Blur radius", "the 1/255 point minus one: σ = (r + 1)/3.329", r)
        }
        if let r = reading("coreimage", "box-blur").first, let sigma = r.value.value {
            let w = SemanticsMath.ciBoxWidth(radius: v)
            add("ciboxblur", "CIBOXBLUR", "CIBoxBlur inputRadius", "box width, the nearest odd (a diameter)", "box",
                r.value, edge(sigma > 0 ? .boxes([w]) : .gaussian(sigma: 0), .computed))
        }
        do {
            add("imagemagick-bare", "IMAGEMAGICK -BLUR R", "ImageMagick -blur r with no sigma", "kernel half-width; σ stays one", "Gaussian, cut at ±r",
                computed(1, .reference, SemanticsSources.imageMagick), edge(.truncatedGaussian(sigma0: 1, halfWidth: max(v.rounded(), 1)), .computed))
        }
        return rows.enumerated().sorted { a, b in
            let sa = a.element.sigma.value ?? -1, sb = b.element.sigma.value ?? -1
            return sa != sb ? sa > sb : a.offset < b.offset
        }.map(\.element)
    }
}
