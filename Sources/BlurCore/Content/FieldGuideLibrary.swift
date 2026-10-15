import Foundation

// OWNER: CONTENT-LAYERS. Field guide pages (SPEC §4.7 Guide tab): one page per entry with its sources, the HONESTY LABELS
// legend (§12.4) and THE LENS ON THIS INSTRUMENT (§12.5). The frozen type name is `FieldGuideLibrary`.

public struct FieldGuideLibrary: FieldGuideProviding {
    public let tools: (any ToolConventionProviding)?
    public init(tools: (any ToolConventionProviding)? = nil) { self.tools = tools }

    public func page(for op: any BlurOperator, context: FloorContext) -> FieldGuidePage {
        let e = op.entry
        let builder = FloorPageBuilder(tools: tools)
        let i = ContentPageInputs(op: op, context: context, tools: builder.toolProvider, shaderSources: builder.shaderSources)
        var blocks: [ContentBlock] = [
            .note(e.signature, .reference),
            .chips([e.family.eyebrow, e.tier.chip, e.verdict.chip, e.linearity.chip, e.costClass.rawValue]),
            .paragraph(e.family.question),
        ]
        blocks.append(.disclosure(title: "Fingerprint", blocks: e.card.ordered.map { .note("\($0.label) · \($0.row.text)", $0.row.provenance) }
                                  + [.sources(e.card.ordered.compactMap(\.row.source))]))
        if let bands = e.primarySpec.flatMap({ spec -> [MeaningBand]? in if case .continuous(let c) = spec.kind { return c.bands }; return nil }), !bands.isEmpty {
            blocks.append(.paragraph("The serif meaning words (\(bands.map(\.name).joined(separator: ", "))) are Blur2ool's own descriptive words, not a standard."))
        }
        // What each tool would need typed for this blur (home tool first), with each convention's own badge.
        let conventions = i.tools.all
        let ids = [context.homeToolID] + conventions.map(\.id).filter { $0 != context.homeToolID }
        let rows = ids.map { id -> LabeledValue in
            let typed = ContentSlide.typed(i, toolID: id)
            var v = typed.value
            if typed.sigmaMatchedOnly { v.caption = ContentToolKernels.addCaption(v.caption, ContentToolKernels.sameSigmaCaption) }
            if typed.kind == .unverified { v = .unverified(id + " mapping") }
            if typed.kind == .notOffered { v = BadgedValue(value: nil, text: "NOT OFFERED", provenance: nil, spoken: "not offered") }
            return LabeledValue(id: "tool-" + id, label: ContentValues.toolName(id, conventions: conventions).uppercased(), value: v)
        }
        blocks.append(.disclosure(title: "In the tools you use", blocks: [.values(rows)]))
        if !e.appleTwins.isEmpty {
            blocks.append(.disclosure(title: "Apple's twins", blocks: e.appleTwins.flatMap { twin -> [ContentBlock] in
                [.code(CodeBlock(language: "swift", text: twin.call)), .note("\(twin.id): \(twin.mapping)", twin.provenance), .sources([twin.source])]
            }))
        }
        if !e.unverified.isEmpty {
            blocks.append(.disclosure(title: "Still unverified", blocks: e.unverified.map { .note($0 + " · UNVERIFIED", .reference) }
                                      + [.sources([SourceRef(e.detailReference)])]))
        }
        let neighbours = e.neighbours.map { BlurRegistry.entry($0)?.displayName ?? $0.rawValue }
        if !neighbours.isEmpty { blocks.append(.disclosure(title: "Most often confused with", blocks: [.chips(neighbours)])) }
        blocks.append(.sources(e.sources + [SourceRef(e.detailReference)]))
        return FieldGuidePage(blur: e.id, title: e.displayName, blocks: blocks)
    }

    public var honestyLegend: [ContentBlock] {
        let rows: [(Provenance, String, String, String, String)] = [
            (.live, "circle.fill", "action cyan", "Computed now from the current image and parameters, by the GPU for the frame on screen, or by the CPU on the current image for adaptive weight maps, which the GPU never stores (LIVE · CPU). A CPU re-computation of a GPU value is never LIVE.",
             "The PIXEL chip, the loupe, the Trace's fetch rows, floor seven's IN and OUT."),
            (.measured, "stopwatch", "instrument amber", "Timed or fitted on a named device, with its OS build and date; research values stay labelled with the Mac they came from until this phone replaces them.",
             "GPU milliseconds, parity, This phone, Calibrate fits."),
            (.computed, "equal", "display ink", "An exact consequence of the math, computed by BlurCore in Double.",
             "Kernel weights, σ, fetch counts, conversions, dispatch geometry, branch values."),
            (.modeled, "approximately", "spectrum violet", "An estimate from a stated model; the assumption is in the details.",
             "Bytes moved, bandwidth floors, ghost bars, our reconstructions of Apple's materials, the hardware-rounded bilinear fraction."),
            (.reference, "book.closed", "secondary ink", "Documented by a spec, header, paper or vendor source, cited in this guide.",
             "Tool conventions, API documentation, feature tables, the shader source: it is the code."),
            (.inferred, "questionmark with a dashed border", "spectrum secondary", "About internals nobody outside the vendor can see; measured live where possible and upgraded to MEASURED when this phone measures it.",
             "SwiftUI's blur mechanism, the render-server lane, Figma's σ rule, Liquid Glass."),
        ]
        var blocks: [ContentBlock] = [.paragraph("Every number on screen carries one of six labels. The word is primary; the glyph and the ink repeat it.")]
        for (p, glyph, ink, meaning, homes) in rows {
            blocks.append(.disclosure(title: p.word, blocks: [.note(meaning, p), .paragraph("Glyph: \(glyph). Ink: \(ink)."), .paragraph("Where: " + homes)]))
        }
        blocks += [
            .note("UNVERIFIED is not a seventh label. It appears as the value itself, in words, where a number would be dishonest, or as a caption after a weak number's label. An unverified figure is never shown as a bare number.", nil),
            .note("SOURCES DISAGREE is a caption under two rows that each keep their own label; the disagreement is shown, never resolved silently.", nil),
            .note("OFFSCREEN travels with every number derived from SwiftUI: those come from ImageRenderer renders, not from the screen, and on-screen equivalence is UNVERIFIED.", nil),
            .note("Inputs carry no label: the hero, Stepper values and typed values are what you set. Everything derived from them is labelled.", nil),
            .note("The rail's chips are the one place a label is shown as its glyph alone; VoiceOver still speaks the word.", nil),
            .sources([SourceRef("SPEC §12 (honesty labels)"), SourceRef("Loom's badges (the precedent)")]),
        ]
        return blocks
    }

    public var lensNote: [ContentBlock] {
        [
            .paragraph("The glass on the controls and on the kernel well is Apple's Liquid Glass. It is drawn by the system; its lensing, scattering and tint are not exposed, and every figure about them is INFERRED."),
            .paragraph("Blur2ool measures and models glass only in the Liquid Glass exhibit. The image you study is never under glass on the Bench, and every number is read back from Metal textures or from offscreen renders, never from the screen."),
            .paragraph("When the page scrolls under the floating buttons, you are looking at the image through glass; the numbers are unaffected."),
            .note("Apple describes Liquid Glass as a material that “dynamically bends, shapes, and concentrates light”: the line between a warp, which moves samples, and a blur, which averages them.", .reference),
            .sources([SourceRef("WWDC25 session 219, Meet Liquid Glass"), SourceRef("Metro Station design system, the lens contract")]),
        ]
    }
}

// MARK: - Status-row lines (SPEC §4.1.3 status row; every number badged, review fix E-51)

public enum ContentStatusLines {
    /// "74 FETCHES · 2 PASSES · LINEAR-SAMPLED", with the variant name in a literal (it may contain digits: "2-D DIRECT").
    public static func phase(_ plan: PassPlan) -> BadgedLine {
        BadgedLine([.value(.number(plan.fetchesPerPixel.rounded(), .integer(), .computed)), .text("FETCHES ·"),
                    .value(.number(Double(plan.passes.count), .integer(), .computed)), .text(plan.passes.count == 1 ? "PASS ·" : "PASSES ·"),
                    .literal(plan.algorithmName.uppercased())])
    }

    /// "RENDERING… PASS 2/2" (requested ≠ acknowledged).
    public static func rendering(pass: Int?, of total: Int?) -> BadgedLine {
        guard let pass, let total else { return .words("RENDERING…") }
        return BadgedLine([.text("RENDERING… PASS"), .literal("\(NumberStyle.integer().text(Double(pass)))/\(NumberStyle.integer().text(Double(total)))")])
    }

    /// The operator's automatic fallback ("2-D DIRECT ABOVE σ 8 · USING SEPARABLE") or sampling warning, as written by
    /// the operator: an engineering identifier line, kept literal.
    public static func operatorNotice(_ text: String) -> BadgedLine {
        text.contains(where: \.isNumber) ? BadgedLine([.literal(text)]) : .words(text)
    }

    /// "TOO SLOW TO TIME · ≈ 700 ms MODELED".
    public static func tooSlowToTime(_ plan: PassPlan, size: ImageSize) -> BadgedLine {
        let ms = plan.fetchesPerFrame(size) / FetchBudget.modeledFetchesPerSecond * 1000
        return BadgedLine([.text("TOO SLOW TO TIME · ≈"),
                           .value(.number(ms, NumberStyle.significant(2, unit: "ms", spokenUnit: "milliseconds"), .modeled, qualifiers: .weakSource,
                                          caption: "UNVERIFIED RATE"))])
    }

    /// "σ NOT DEFINED · RANK FILTER" (and SPACE-VARIANT, NONLINEAR, SYSTEM MATERIAL).
    public static func sigmaNotDefined(_ entry: CatalogEntry) -> BadgedLine {
        let reason: String
        switch entry.linearity {
        case .lsv: reason = "SPACE-VARIANT"
        case .system: reason = "SYSTEM MATERIAL"
        case .nonlinear: reason = entry.algorithmClass == .selection ? "RANK FILTER" : "NONLINEAR"
        default: reason = entry.algorithmClass == .selection ? "RANK FILTER" : "NO SECOND MOMENT"
        }
        return .words("σ NOT DEFINED · " + reason)
    }

    /// "PARTS WAYS AT MATH" (Compare).
    public static func partsWays(_ comparisons: [FloorComparison]) -> BadgedLine {
        guard let first = comparisons.first(where: { $0.verdict == .partsWays }) else { return .words("SAME ON EVERY FLOOR") }
        return .words("PARTS WAYS AT " + first.floor.railLabel)
    }

    /// "MAX 6 LSB · RMS 0.8 LSB · ×16" (Difference view; LIVE, or MEASURED when B is the CPU reference).
    public static func difference(max: Double, rms: Double, gain: Double, provenance: Provenance = .live, device: DeviceStamp? = nil) -> BadgedLine {
        BadgedLine([.text("MAX"), .value(.number(max, ContentStyle.lsb, provenance, device: device)), .text("· RMS"),
                    .value(.number(rms, NumberStyle.decimals(1, unit: "LSB", spokenUnit: "eight-bit steps"), provenance, device: device)),
                    .text("·"), .literal("×" + NumberStyle.integer().text(gain))])
    }

    /// "MIN H  A −0.217 · B 0 · C −0.0012 · D −0.132" (Line-up), from the kernels as run.
    public static func minimumResponses(_ configurations: [RenderConfiguration]) -> BadgedLine {
        var segments: [BadgedSegment] = [.text("MIN H")]
        for (n, c) in configurations.enumerated() {
            guard let op = BlurRegistry.op(c.blur) else { continue }
            let letter = ["A", "B", "C", "D"][Swift.min(n, 3)]
            if n > 0 { segments.append(.text("·")) }
            segments.append(.text(letter))
            if let h = op.response(ResponseQuery(), c.operatorRequest, content: nil)?.minimum?.value {
                segments.append(.value(.number(abs(h) < 1e-12 ? 0 : h, ContentStyle.response(abs(h) < 1e-12 ? 0 : h), .computed)))
            } else {
                segments.append(.value(.words("N/A", spoken: "not defined", .computed)))
            }
        }
        return BadgedLine(segments)
    }

    /// The coaching line of the first launch.
    public static let coaching = BadgedLine.words("TURN A CROWN · DRAG THE IMAGE · TAP A BLUR")
    public static let drivingB = BadgedLine.words("DRIVING B")
}
