import Foundation

// OWNER: CONTENT-LAYERS. The digits-in-plain-strings lint and its allow-list (ARCHITECTURE §5.1 rule "BadgedLine";
// SPEC §12.2 item 8): every number that reaches the screen travels as a badged value, so view-bound plain strings may
// contain digits only where this file allows them. Tests run it over every page, chip, pill, trace step, lesson and field
// guide page CONTENT-LAYERS generates, together with `honestyViolations` on every BadgedValue and BadgedLine.
//
// THE ALLOW-LIST (where digits may appear in a plain String):
//  1. Equations: `ContentBlock.equation`, `FloorPage.governingRule` (callout mono, the floor's one governing rule).
//  2. Code: `CodeBlock` text and its annotations (the code that ran is REFERENCE: "it is the code").
//  3. Citations: `SourceRef` (paper years, section numbers, URLs).
//  4. Badged data tables: a `TableBlock` with a provenance (every cell carries the table's badge).
//  5. Badged one-line notes and verbatim catalog text with its own badge: `.note(text, provenance)` with a non-nil
//     provenance (fingerprint card rows, research lines) and `FloorPage.signature` (CATALOG §2 verbatim, REFERENCE).
//  6. Identifier tokens, anywhere: tokens that begin with a letter or `§` (fp16, rgba16Float, A17, SHA-256, Apple9, P12,
//     F6, §5.2, b2_f2_gauss_linear_fs), kind words `2-D`, `8-bit`, `13-tap`, `5-point`, sizes `3×3`, gains `×16`, level
//     names `↓1` / `↑2`, versions after iOS · macOS · MSL · Metal · Swift · Xcode · WWDC, coordinates `(447, 455)`,
//     equation fragments (`H ≥ 0`, `λ = 0.125`, `ν = 0.1`) and the marker name `−3 dB`.
//  7. Trace narration (`TraceStep` / `TraceSubStep` completed, next, phase and announcement lines): integers are
//     ordinals and counts ("fetch 7 of 13", "Step 10 / 15"); every DECIMAL number must also appear as a badged value of
//     the same step (panel numbers, branch values) or of the trace record behind the sub-step (its tap rows).
// Everything else: no token may begin with a digit, or with a sign followed by a digit.

public enum ContentLint {

    // MARK: Plain strings

    /// Digit violations in one plain view-bound string.
    public static func digitViolations(_ s: String, context: String) -> [String] {
        let quantities = quantityTokens(s, allowDecimals: false, allowIntegers: false)
        return quantities.isEmpty ? [] : ["\(context): digits in plain text \(quantities.map { "'\($0)'" }.joined(separator: ", ")) in '\(s)'"]
    }

    /// The tokens of `s` that read as quantities after the allow-list is applied.
    static func quantityTokens(_ s: String, allowDecimals: Bool, allowIntegers: Bool) -> [String] {
        guard s.contains(where: \.isNumber) else { return [] }
        var text = s
        for pattern in strippedPatterns {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        let tokens = text.split(whereSeparator: { $0.isWhitespace || $0 == "/" }).map(String.init)
        var out: [String] = []
        for (i, raw) in tokens.enumerated() {
            let token = raw.trimmingCharacters(in: CharacterSet(charactersIn: "([{\"'“‘«").union(.whitespaces))
                .trimmingCharacters(in: CharacterSet(charactersIn: ")]}\"'”’».,;:!?…"))
            guard token.contains(where: \.isNumber) else { continue }
            if let first = token.unicodeScalars.first, CharacterSet.letters.contains(first) || first == "§" || first == "_" { continue }
            if token.range(of: allowedTokenPattern, options: .regularExpression) != nil { continue }
            if i > 0 {
                let previous = tokens[i - 1].trimmingCharacters(in: .punctuationCharacters)
                if versionWords.contains(previous) { continue }
                if token.range(of: #"^(1[89]\d\d|20[0-3]\d)$"#, options: .regularExpression) != nil,
                   let p = previous.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(p) { continue }
            }
            let isDecimal = token.contains(".") || token.contains("·10")
            if isDecimal && allowDecimals { continue }
            if !isDecimal && allowIntegers && token.range(of: #"^[±+−\-]?[0-9,]+$"#, options: .regularExpression) != nil { continue }
            out.append(token)
        }
        return out
    }

    static let strippedPatterns: [String] = [
        #"\(\s*[−\-+]?\d+\s*,\s*[−\-+]?\d+\s*\)"#,                                   // coordinates (447, 455)
        #"[A-Za-zσνλτμθΘγεκ₀-₉]+\s*(?:≥|≤|<|>|=|≠|≈)\s*[−\-+]?\d+(?:[.,]\d+)?"#,     // equation fragments H ≥ 0, λ = 0.125
        #"[−\-]3\s?dB"#,                                                             // the −3 dB marker name
        #"[A-Za-zσνλτμθΘγεκ]+\s*(?:≥|≤|<|>|=|≠|≈)\s*[¼½¾⅛⅓⅔⅜⅝⅞]"#,                   // equation fragments with vulgar fractions
        #"\d+–\d+\s?%"#,                                                            // the 10–90 % edge-width name
        #"\b(TIER|Tier|tier|FLOOR|Floor|floor|Step|STEP)\s\d+\b"#,                           // catalog tier chips, floor and step names
    ]
    static let allowedTokenPattern = #"^(\d+-(D|bit|BIT|tap|TAP|taps|TAPS|pass|PASS|point|POINT|pixel|PIXEL|px|PX)|\d+(×\d+)+|×\d+|[↓↑]\d+|\d+(st|nd|rd|th)|\d+²|(?=[0-9a-f]*[a-f])[0-9a-f]{8,}…?)$"#
    static let versionWords: Set<String> = ["iOS", "macOS", "MSL", "Metal", "Swift", "Xcode", "WWDC", "IEC", "Rec", "ITU-R", "CSS", "GIMP",
                                            "Photoshop", "PHOTOSHOP", "Android", "ANDROID", "Flutter", "FLUTTER", "OpenCV", "OPENCV", "ImageMagick",
                                            "IMAGEMAGICK", "Figma", "FIGMA", "Sketch", "SKETCH", "Unity", "UNITY", "Unreal", "UNREAL", "Windows",
                                            "WINDOWS", "Chrome", "Safari", "Firefox", "Blender", "Affinity", "Effects", "EFFECTS", "Level", "LEVEL"]

    // MARK: Values and lines

    public static func violations(_ value: BadgedValue, context: String) -> [String] {
        var problems = value.honestyViolations.map { "\(context): \($0)" }
        if let caption = value.caption { problems += digitViolations(caption, context: context + " caption") }
        if value.value == nil { problems += digitViolations(value.text, context: context + " words") }
        return problems
    }

    public static func violations(_ row: LabeledValue, context: String) -> [String] {
        digitViolations(row.label, context: context + " label") + violations(row.value, context: context + " " + row.label)
    }

    public static func violations(_ line: BadgedLine, context: String) -> [String] {
        line.honestyViolations.map { "\(context): \($0)" }
            + line.segments.flatMap { segment -> [String] in
                if case .value(let v) = segment, let caption = v.caption { return digitViolations(caption, context: context + " caption") }
                return []
            }
    }

    // MARK: Blocks and figures

    public static func violations(_ block: ContentBlock, context: String) -> [String] {
        switch block {
        case .paragraph(let s): return digitViolations(s, context: context + " paragraph")
        case .equation: return []
        case .values(let rows): return rows.flatMap { violations($0, context: context) }
        case .table(let t):
            var p = t.columns.flatMap { digitViolations($0, context: context + " table column") }
            if let caption = t.caption { p += digitViolations(caption, context: context + " table caption") }
            if t.provenance == nil { p += t.rows.flatMap { $0.flatMap { digitViolations($0, context: context + " unbadged table cell") } } }
            return p
        case .code: return []
        case .figure(let f): return violations(f, context: context)
        case .note(let s, let provenance): return provenance == nil ? digitViolations(s, context: context + " note") : []
        case .chips(let chips): return chips.flatMap { digitViolations($0, context: context + " chip") }
        case .sources: return []
        case .disclosure(let title, let blocks):
            return digitViolations(title, context: context + " disclosure") + blocks.flatMap { violations($0, context: context + " › " + title) }
        }
    }

    public static func violations(_ figure: FigureSpec, context: String) -> [String] {
        switch figure {
        case .plot(let p): return violations(p, context: context)
        case .heatmap(let h): return digitViolations(h.caption, context: context + " heat map caption")
        case .texelGrid, .dispatchOverlay, .psfField, .code: return []
        case .passTiles(let t):
            return t.passes.flatMap { digitViolations($0.name, context: context + " pass name") + digitViolations($0.summary, context: context + " pass summary") }
        case .toolBars(let b): return b.rows.flatMap { violations($0, context: context + " tool bar") }
        case .pair(let a, let b): return violations(a, context: context) + violations(b, context: context)
        }
    }

    public static func violations(_ plot: PlotSpec, context: String) -> [String] {
        var p = digitViolations(plot.xAxis.label, context: context + " x axis") + digitViolations(plot.yAxis.label, context: context + " y axis")
        p += plot.series.flatMap { digitViolations($0.name, context: context + " series") }
        p += plot.markers.flatMap { digitViolations($0.label, context: context + " marker") }
        p += digitViolations(plot.accessibilitySummary, context: context + " accessibility summary")
        return p
    }

    // MARK: Pages, rail, pills

    public static func violations(_ page: FloorPage) -> [String] {
        let c = page.eyebrow
        var p: [String] = []
        if page.eyebrow != page.floor.eyebrow { p.append("\(c): eyebrow differs from Floor.eyebrow") }
        if page.question != page.floor.question { p.append("\(c): question differs from Floor.question") }
        if page.numbers.count > 6 { p.append("\(c): \(page.numbers.count) primary numbers (at most six)") }
        p += page.numbers.flatMap { violations($0, context: c) }
        if let f = page.figure { p += violations(f, context: c) }
        p += page.details.flatMap { violations($0, context: c + " details") }
        for tab in page.tabs ?? [] {
            p += digitViolations(tab.title, context: c + " tab")
            if tab.numbers.count > 6 { p.append("\(c) tab \(tab.title): more than six numbers") }
            p += tab.numbers.flatMap { violations($0, context: c + " › " + tab.title) }
            if let f = tab.figure { p += violations(f, context: c + " › " + tab.title) }
            p += tab.details.flatMap { violations($0, context: c + " › " + tab.title + " details") }
        }
        p += digitViolations(page.inThisApp, context: c + " IN THIS APP")
        if let e = page.emptyState { p += digitViolations(e, context: c + " empty state") }
        if page.inThisApp.isEmpty { p.append("\(c): missing IN THIS APP line") }
        if page.figure == nil && page.numbers.isEmpty && page.emptyState == nil && (page.tabs ?? []).isEmpty {
            p.append("\(c): nothing on the page and no honest empty state")
        }
        let words = ([page.question, page.signature, page.inThisApp, page.emptyState ?? "", page.governingRule ?? ""]).joined(separator: " ").lowercased()
        for marker in ["todo", "lorem", "placeholder", "tbd", "fixme"] where words.contains(marker) { p.append("\(c): placeholder '\(marker)'") }
        return p
    }

    public static func violations(_ chips: [RailChip]) -> [String] {
        var p: [String] = []
        if chips.map(\.floor) != Floor.allCases { p.append("rail: chips are not the seven floors in order") }
        for chip in chips {
            let c = "rail \(chip.floor.railLabel)"
            p += violations(chip.value, context: c)
            if chip.value.text.count > 6 { p.append("\(c): '\(chip.value.text)' is longer than six characters") }
        }
        return p
    }

    public static func violations(_ pills: PillContent) -> [String] {
        func pill(_ pp: PillPlot, _ name: String) -> [String] {
            var title = pp.title
            if let badge = pp.badge, badge.value != nil {
                title = title.replacingOccurrences(of: badge.text, with: "")    // T(ν, A 0.20): the amplitude is the badge
            }
            var p = digitViolations(title, context: "pill \(name) title")
            if let e = pp.emptyText { p += digitViolations(e, context: "pill \(name) empty text") }
            if let plot = pp.plot { p += violations(plot, context: "pill \(name)") }
            if let badge = pp.badge { p += violations(badge, context: "pill \(name) badge") }
            if pp.plot == nil && (pp.emptyText ?? "").isEmpty { p.append("pill \(name): blank interior without an engraved reason") }
            return p
        }
        return pill(pills.kernel, "KERNEL") + pill(pills.freq, "FREQ")
    }

    // MARK: Trace

    public static func violations(_ steps: [TraceStep], record: TraceRecord? = nil) -> [String] {
        var p: [String] = []
        for (j, step) in steps.enumerated() {
            let c = "trace step \(step.id)"
            var badged = Set<String>()
            // A step's lines may quote its own badged values and, in `next`, the following step's (which the next press
            // reveals beside them), including the first tap row of the following pass.
            let following = j + 1 < steps.count ? steps[j + 1] : nil
            for row in step.panel.numbers + step.branchValues + (following.map { $0.panel.numbers + $0.branchValues } ?? []) { badged.insert(row.value.text) }
            for s in [step, following].compactMap({ $0 }) where !s.subSteps.isEmpty {
                if let record, let passIndex = s.passIndex, let pass = record.passes.first(where: { $0.id == passIndex }), let first = pass.taps.first {
                    for t in ContentTraceFormat.tapTexts(first) { badged.insert(t) }
                }
            }
            p += step.panel.numbers.flatMap { violations($0, context: c + " panel") }
            p += step.branchValues.flatMap { violations($0, context: c + " branch") }
            p += step.panel.details.flatMap { violations($0, context: c + " panel details") }
            if let f = step.panel.figure { p += violations(f, context: c + " panel") }
            func narration(_ s: String, _ what: String, extra: Set<String> = []) {
                for token in quantityTokens(s, allowDecimals: false, allowIntegers: true) {
                    let bare = token.trimmingCharacters(in: CharacterSet(charactersIn: "+"))
                    if !(badged.contains(token) || badged.contains(bare) || extra.contains(token) || extra.contains(bare)) {
                        p.append("\(c) \(what): decimal '\(token)' has no badged twin in '\(s)'")
                    }
                }
            }
            narration(step.completed, "completed"); narration(step.next, "next"); narration(step.phaseLine, "phase")
            narration(step.announcement, "announcement")
            if let lesson = step.closingLesson { narration(lesson, "closing lesson", extra: closingTwins(steps)) }
            for sub in step.subSteps {
                let twins = subStepTwins(sub, step: step, record: record)
                narration(sub.completed, "sub-step \(sub.id) completed", extra: twins)
                narration(sub.next, "sub-step \(sub.id) next", extra: twins)
                narration(sub.announcement, "sub-step \(sub.id) announcement", extra: twins)
            }
        }
        return p
    }

    /// The badged texts a closing lesson may quote: every badged number of the walk.
    static func closingTwins(_ steps: [TraceStep]) -> Set<String> {
        Set(steps.flatMap { ($0.panel.numbers + $0.branchValues).map(\.value.text) })
    }

    /// A sub-step's decimals are the record's own tap row (weight, fetched value, running sum, offset), rendered beside it
    /// with the record's badge (LIVE for GPU records, COMPUTED for reconstructions) by the Trace screen.
    static func subStepTwins(_ sub: TraceSubStep, step: TraceStep, record: TraceRecord?) -> Set<String> {
        var out = Set<String>()
        guard let record, let passIndex = step.passIndex, let pass = record.passes.first(where: { $0.id == passIndex }) else { return out }
        func add(_ tap: TraceTap) {
            for v in ContentTraceFormat.tapTexts(tap) { out.insert(v) }
        }
        if let i = sub.tapIndex, pass.taps.indices.contains(i) { add(pass.taps[i]) }
        if let i = sub.tapIndex, pass.taps.indices.contains(i + 1) { add(pass.taps[i + 1]) }
        if sub.tapIndex == nil, let first = pass.taps.first { add(first) }
        return out
    }

    // MARK: Lessons and field guide

    public static func violations(_ lesson: Lesson) -> [String] {
        let c = "lesson \(lesson.id)"
        return digitViolations(lesson.title, context: c + " title") + digitViolations(lesson.setupLine, context: c + " set-up")
            + lesson.lookFor.flatMap { violations($0, context: c + " look for") } + violations(lesson.statusLine, context: c + " status line")
    }

    public static func violations(_ page: FieldGuidePage) -> [String] {
        digitViolations(page.title, context: "field guide title")
            + page.blocks.flatMap { violations($0, context: "field guide \(page.blur.rawValue)") }
    }
}

/// How trace narration prints a tap's numbers, shared by the scripter (which writes the lines) and the lint (which finds
/// each decimal's badged twin in the record row the Trace screen shows beside the line).
public enum ContentTraceFormat {
    public static let weight = NumberStyle.decimals(5)
    public static let value = NumberStyle.decimals(3)
    public static let offset = NumberStyle(precision: .decimals(2), unit: "px", spokenUnit: "pixels", explicitPlus: true)
    public static let fraction = NumberStyle.decimals(4)

    public static func tapTexts(_ tap: TraceTap) -> [String] {
        var out = [weight.text(tap.weight), value.text(ContentValues.scalar(tap.fetched)), value.text(ContentValues.scalar(tap.runningSum)),
                   offset.text(tap.offset.x), offset.text(tap.offset.y), offset.text((tap.offset.x * tap.offset.x + tap.offset.y * tap.offset.y).squareRoot()),
                   value.text(ContentValues.scalar(tap.contribution))]
        if let r = tap.requestedFraction { out += [fraction.text(r.x), fraction.text(r.y)] }
        if let q = tap.quantizedFraction { out += [fraction.text(q.x), fraction.text(q.y)] }
        for (_, v) in tap.extras { out += [value.text(v), weight.text(v), NumberStyle.significant(3).text(v)] }
        return out
    }
}
