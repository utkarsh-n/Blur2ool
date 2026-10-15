import Foundation

// OWNER: SEMANTICS (ARCHITECTURE §8.2). `ToolConventions`, the frozen name behind `BlurServices.tools`: what each tool's
// blur number means (STACK §0–§6, §8), in both directions, with its badge.
//
//   typedValue  σ (device px) → what a person would type in that tool for that blur      (floor 1, SLIDE chip, σ-hold)
//   sigmaPx     a typed value → the σ it produces here ("you typed 10", reverse mode)
//
// Badges: REFERENCE (spec, header, vendor source; cited), MEASURED (research Mac, `.notThisDevice`, until this phone's
// CalibrationLaw for the same subject replaces it), INFERRED, COMPUTED, or UNVERIFIED words. Every SwiftUI-derived value
// carries `.offscreen` (ImageRenderer fits) on its qualifiers, caption and spoken text (review fix P-34). A tool that
// does not offer a blur answers "—" with the caption `NOT IN <TOOL>` (the SLIDE chip's dash, Compare's skipped floor).

public struct ToolConventions: ToolConventionProviding {
    public init() {}

    /// One convention per tool and per drop-shadow convention, described by its primary control (usually the Gaussian).
    public var all: [ToolConvention] { Self.conventions }

    public func typedValue(toolID: String, blur: BlurID, sigmaPx: Double, displayScale: Double, measuredLaw: CalibrationLaw?) -> BadgedValue {
        Self.typedValue(toolID: toolID, blur: blur, sigmaPx: sigmaPx, displayScale: displayScale, measuredLaw: measuredLaw)
    }

    public func sigmaPx(toolID: String, blur: BlurID, typed value: Double, displayScale: Double, measuredLaw: CalibrationLaw?) -> BadgedValue {
        Self.sigmaPx(toolID: toolID, blur: blur, typed: value, displayScale: displayScale, measuredLaw: measuredLaw)
    }
}

// MARK: - Conventions list

public extension ToolConventions {
    static let conventions: [ToolConvention] = SemanticsCatalog.tools.map { tool in
        let c = SemanticsCatalog.control(toolID: tool.id, blur: tool.primaryBlur)
        let hasLaw = c?.isOfferedWithLaw ?? false
        return ToolConvention(id: tool.id, toolName: tool.name, controlName: c?.controlName ?? tool.name, unit: tool.unit,
                              provenance: c?.provenance ?? .reference, source: c?.source ?? SourceRef("stack-semantics.md §0 (summary table)"),
                              lawDescription: hasLaw ? c?.lawDescription : nil)
    }

    /// Settings › Home tool options in SPEC order.
    static var homeToolOptions: [ToolConvention] {
        SemanticsCatalog.homeToolIDs.compactMap { id in conventions.first { $0.id == id } }
    }
    /// The drop-shadow CONVENTION menu (P27).
    static var shadowConventions: [ToolConvention] {
        SemanticsCatalog.shadowConventionIDs.compactMap { id in conventions.first { $0.id == id } }
    }

    static func offer(toolID: String, blur: BlurID) -> SemanticsOffer { SemanticsCatalog.offer(toolID: toolID, blur: blur) }
    static func offers(toolID: String, blur: BlurID) -> Bool { offer(toolID: toolID, blur: blur).isOffered }
    /// Compare's SLIDE caption when a blur is absent from the home tool: `NOT IN SWIFTUI`.
    static func notInToolCaption(toolID: String) -> String { "NOT IN " + (SemanticsCatalog.tool(toolID)?.label ?? toolID.uppercased()) }
    static func toolName(_ toolID: String) -> String { SemanticsCatalog.tool(toolID)?.name ?? toolID }
}

// MARK: - SwiftUI law

public extension ToolConventions {
    /// SwiftUI `.blur(radius:)` on the research Mac (CAL §4.0, §5.1): σ ≈ r·scale while r·scale ≤ 5 px, ≈ 0.90·r·scale
    /// above, MEASURED offscreen through ImageRenderer on macOS 27.2. The switch is 5 device px, so 5/scale pt.
    static func macSwiftUIBlurLaw(displayScale: Double) -> CalibrationLaw {
        CalibrationLaw(subject: .swiftUIBlur, smallRatio: 1.0, largeRatio: 0.90,
                       switchParameter: SemanticsMath.swiftUISwitchDevicePx / max(displayScale, 1e-9), points: [],
                       device: SemanticsCatalog.researchMac)
    }

    /// The Mac fit points behind that law (CAL table 4.1, scale 1, `.nonLinear`): radius pt → σ px and centre spread.
    static let macSwiftUIBlurPoints: [CalibrationPoint] = [
        CalibrationPoint(parameter: 1, sigmaPx: 0.994, centreSpreadPx: 0), CalibrationPoint(parameter: 2, sigmaPx: 2.002, centreSpreadPx: 0),
        CalibrationPoint(parameter: 4, sigmaPx: 3.940, centreSpreadPx: 0), CalibrationPoint(parameter: 8, sigmaPx: 7.245, centreSpreadPx: 1.21),
        CalibrationPoint(parameter: 16, sigmaPx: 14.417, centreSpreadPx: 1.19), CalibrationPoint(parameter: 32, sigmaPx: 28.982, centreSpreadPx: 1.18),
        CalibrationPoint(parameter: 64, sigmaPx: 57.685, centreSpreadPx: 1.20),
    ]

    /// The law in use: this phone's when it measured `.swiftUIBlur`, otherwise the Mac's.
    static func swiftUIBlurLaw(displayScale: Double, measuredLaw: CalibrationLaw?) -> CalibrationLaw {
        if let law = measuredLaw, law.subject == .swiftUIBlur { return law }
        return macSwiftUIBlurLaw(displayScale: displayScale)
    }
    /// σ in device px for `.blur(radius: r)` (σ-hold and F10's model use the same law).
    static func swiftUISigmaPx(radiusPt r: Double, displayScale: Double, measuredLaw: CalibrationLaw?) -> Double {
        r > 0 ? swiftUIBlurLaw(displayScale: displayScale, measuredLaw: measuredLaw).sigmaPx(parameter: r, displayScale: displayScale) : 0
    }
    /// The radius in points that gives σ (SPEC §8.1 σ-hold row for `swiftui-layer-blur`).
    static func swiftUIRadiusPt(sigmaPx: Double, displayScale: Double, measuredLaw: CalibrationLaw?) -> SemanticsInverse {
        SemanticsMath.inverse(swiftUIBlurLaw(displayScale: displayScale, measuredLaw: measuredLaw), sigmaPx: sigmaPx,
                              unitScale: max(displayScale, 1e-9))
    }
    /// The SEMANTIC stop of the SwiftUI radius crown: the regime switch in points (≈ 1.7 pt at scale 3), MEASURED
    /// on the Mac with `.notThisDevice` and `.offscreen` until this phone's law replaces it.
    static func swiftUISwitchRadius(displayScale: Double, measuredLaw: CalibrationLaw?) -> BadgedValue {
        let law = swiftUIBlurLaw(displayScale: displayScale, measuredLaw: measuredLaw)
        let phone = law.subject == .swiftUIBlur && measuredLaw?.subject == .swiftUIBlur
        guard let sw = law.switchParameter else {
            return .words("NO SWITCH", spoken: "no regime switch measured", .measured, qualifiers: [.offscreen], device: law.device,
                          caption: "OFFSCREEN")
        }
        var q: Qualifiers = [.offscreen]
        if !phone { q.insert(.notThisDevice) }
        if law.device.isSimulator { q.insert(.simulator) }
        let caption = phone ? "OFFSCREEN" : "OFFSCREEN · NOT THIS PHONE"
        var v = BadgedValue.number(sw, .significant(2, unit: "pt", spokenUnit: "points"), .measured, qualifiers: q,
                                   source: phone ? SourceRef("Calibrate on this phone (ImageRenderer)") : SemanticsSources.swiftUIBlurMac,
                                   device: law.device, caption: caption)
        v.spoken = "regime switch at " + NumberStyle.significant(2, unit: "pt", spokenUnit: "points").spoken(sw) + ", "
            + Provenance.measured.spokenPhrase(device: law.device) + ", " + Self.spokenCaption(caption)
        return v
    }
}

// MARK: - Forward and reverse

public extension ToolConventions {
    /// What a person would type in `toolID` to get per-axis σ = `sigmaPx` for `blur` at `displayScale` (the first
    /// reading of `readings`).
    static func typedValue(toolID: String, blur: BlurID, sigmaPx: Double, displayScale: Double, measuredLaw: CalibrationLaw?) -> BadgedValue {
        readings(toolID: toolID, blur: blur, sigmaPx: sigmaPx, displayScale: displayScale, measuredLaw: measuredLaw)[0].value
    }

    /// Reverse mode: the σ (device px) that typing `value` in `toolID` produces here.
    static func sigmaPx(toolID: String, blur: BlurID, typed value: Double, displayScale: Double, measuredLaw: CalibrationLaw?) -> BadgedValue {
        reverseReadings(toolID: toolID, blur: blur, typed: value, displayScale: displayScale, measuredLaw: measuredLaw)[0].value
    }

    /// Forward readings: one, or two when the sources disagree (`CALayer.shadowRadius`: σ = r/2 per STACK, ≈ 0.9·r per
    /// CAL; SPEC P27 renders the first and offers the second). A phone law for the subject settles it to one.
    static func readings(toolID: String, blur: BlurID, sigmaPx: Double, displayScale: Double,
                         measuredLaw: CalibrationLaw?) -> [SemanticsReading] {
        switch offer(toolID: toolID, blur: blur) {
        case .unknownTool(let id):
            var v = BadgedValue.unverified("\(id) mapping")
            v.caption = "UNKNOWN TOOL"
            return [SemanticsReading(id: id, label: id.uppercased(), value: v, lawDescription: nil)]
        case .notOffered(let tool):
            return [SemanticsReading(id: tool.id, label: tool.label, value: notOffered(tool), lawDescription: nil)]
        case .offered(let control):
            let tool = SemanticsCatalog.tool(control.toolID)!
            let resolved = resolve(control, displayScale: displayScale, measuredLaw: measuredLaw)
            var out = [SemanticsReading(id: tool.id, label: tool.label,
                                        value: forwardValue(control, tool: tool, resolved: resolved, sigmaPx: sigmaPx, displayScale: displayScale),
                                        lawDescription: resolved.lawDescription)]
            if let alt = alternate(control, resolved: resolved) {
                out.append(SemanticsReading(id: tool.id + "-alt", label: control.alternate?.label ?? tool.label,
                                            value: forwardValue(control, tool: tool, resolved: alt, sigmaPx: sigmaPx, displayScale: displayScale),
                                            lawDescription: alt.lawDescription))
            }
            return out
        }
    }

    /// Reverse readings ("you typed 10"): one, or two when the sources disagree.
    static func reverseReadings(toolID: String, blur: BlurID, typed value: Double, displayScale: Double,
                                measuredLaw: CalibrationLaw?) -> [SemanticsReading] {
        switch offer(toolID: toolID, blur: blur) {
        case .unknownTool(let id):
            var v = BadgedValue.unverified("\(id) mapping")
            v.caption = "UNKNOWN TOOL"
            return [SemanticsReading(id: id, label: id.uppercased(), value: v, lawDescription: nil)]
        case .notOffered(let tool):
            return [SemanticsReading(id: tool.id, label: tool.label, value: notOffered(tool), lawDescription: nil)]
        case .offered(let control):
            let tool = SemanticsCatalog.tool(control.toolID)!
            let resolved = resolve(control, displayScale: displayScale, measuredLaw: measuredLaw)
            var out = [SemanticsReading(id: tool.id, label: tool.label,
                                        value: reverseValue(control, tool: tool, resolved: resolved, typed: value, displayScale: displayScale),
                                        lawDescription: resolved.lawDescription)]
            if let alt = alternate(control, resolved: resolved) {
                out.append(SemanticsReading(id: tool.id + "-alt", label: control.alternate?.label ?? tool.label,
                                            value: reverseValue(control, tool: tool, resolved: alt, typed: value, displayScale: displayScale),
                                            lawDescription: alt.lawDescription))
            }
            return out
        }
    }

    /// The SLIDE chip (SPEC §4.1.4): at most six characters. The typed value at two significant digits, prefixed `≈`
    /// when only σ matches; `UNVER.` when the mapping is unknown; `—` when the tool does not offer the blur; the
    /// control's short word when its number is not a σ. `sigmaPx` nil (the blur has no σ) gives `NO σ` for law controls.
    static func slideChipValue(toolID: String, blur: BlurID, sigmaPx: Double?, displayScale: Double,
                               measuredLaw: CalibrationLaw?) -> BadgedValue {
        switch offer(toolID: toolID, blur: blur) {
        case .unknownTool(let id):
            var v = BadgedValue.unverified("\(id) mapping"); v.text = "UNVER."; v.caption = "UNKNOWN TOOL"; return v
        case .notOffered(let tool):
            return notOffered(tool)
        case .offered(let control):
            let tool = SemanticsCatalog.tool(control.toolID)!
            switch control.mapping {
            case .unverified, .noSigma:
                var v = readings(toolID: toolID, blur: blur, sigmaPx: sigmaPx ?? 0, displayScale: displayScale, measuredLaw: measuredLaw)[0].value
                if case .noSigma(_, let chip, _) = control.mapping { v.text = chip } else { v.text = "UNVER." }
                return v
            case .law:
                guard let sigma = sigmaPx, sigma.isFinite, sigma >= 0 else {
                    return .words("NO σ", spoken: "this blur has no sigma to type in \(tool.name)", caption: "σ NOT DEFINED")
                }
                let resolved = resolve(control, displayScale: displayScale, measuredLaw: measuredLaw)
                let chipStyle = control.integerValued
                    ? NumberStyle.integer(unit: control.unitSymbol, spokenUnit: control.spokenUnit)
                    : NumberStyle(precision: .significant(2), unit: control.unitSymbol, spokenUnit: control.spokenUnit, grouping: false)
                var v = forwardValue(control, tool: tool, resolved: resolved, sigmaPx: sigma, displayScale: displayScale, style: chipStyle)
                if v.value == nil {
                    switch v.text {
                    case "OUT OF RANGE": v.text = "RANGE"
                    case "BELOW RANGE": v.text = "BELOW"
                    default: break
                    }
                }
                return v
            }
        }
    }
}

// MARK: - Resolution and value building

extension ToolConventions {
    /// A control's law as it applies now: this phone's CalibrationLaw for the subject, or the documented/Mac law.
    struct Resolved {
        var law: SemanticsLaw
        var calibration: CalibrationLaw?
        var provenance: Provenance?
        var device: DeviceStamp?
        var qualifiers: Qualifiers
        var source: SourceRef
        var lawDescription: String?
        var caption: String?
        var isPhoneLaw: Bool
    }

    static func resolve(_ c: SemanticsControl, displayScale: Double, measuredLaw: CalibrationLaw?) -> Resolved {
        guard case .law(let law) = c.mapping else {
            return Resolved(law: .constant(0), calibration: nil, provenance: c.provenance, device: c.measuredOn, qualifiers: c.qualifiers,
                            source: c.source, lawDescription: c.lawDescription, caption: c.caption, isPhoneLaw: false)
        }
        let ratioLaw: Bool = {
            switch law {
            case .swiftUIBlur: true
            case .linear(_, let offset, _): offset == 0
            default: false
            }
        }()
        if let m = measuredLaw, let subject = c.calibrationSubject, m.subject == subject, ratioLaw {
            var q = c.qualifiers
            q.remove(.notThisDevice); q.remove(.sourcesDisagree)
            if m.device.isSimulator { q.insert(.simulator) }
            let caption = c.caption == "SOURCES DISAGREE" ? nil : c.caption
            return Resolved(law: law, calibration: m, provenance: .measured, device: m.device, qualifiers: q,
                            source: SourceRef("Calibrate on \(m.device.label): \(m.points.count) points (\(subject.title))"),
                            lawDescription: describe(m), caption: caption, isPhoneLaw: true)
        }
        let calibration: CalibrationLaw? = { if case .swiftUIBlur = law { macSwiftUIBlurLaw(displayScale: displayScale) } else { nil } }()
        return Resolved(law: law, calibration: calibration, provenance: c.provenance, device: c.measuredOn, qualifiers: c.qualifiers,
                        source: c.source, lawDescription: c.lawDescription, caption: c.caption, isPhoneLaw: false)
    }

    /// The second reading when the control's sources disagree and no phone law settles it.
    static func alternate(_ c: SemanticsControl, resolved: Resolved) -> Resolved? {
        guard let alt = c.alternate, !resolved.isPhoneLaw else { return nil }
        return Resolved(law: alt.law, calibration: nil, provenance: alt.provenance, device: alt.measuredOn,
                        qualifiers: alt.measuredOn == nil ? [.sourcesDisagree] : [.notThisDevice, .sourcesDisagree], source: alt.source,
                        lawDescription: alt.lawDescription, caption: "SOURCES DISAGREE", isPhoneLaw: false)
    }

    /// A phone law in words ("σ ≈ 1.00·r·scale up to 1.67 pt, ≈ 0.91·r·scale above (this phone)").
    static func describe(_ law: CalibrationLaw) -> String {
        let r = NumberStyle.decimals(2)
        if let sw = law.switchParameter, let small = law.smallRatio {
            return "σ ≈ \(r.text(small))·p·scale up to \(r.text(sw)), ≈ \(r.text(law.largeRatio))·p·scale above (this phone)"
        }
        return "σ ≈ \(r.text(law.largeRatio))·p·scale (this phone)"
    }

    static func notOffered(_ tool: SemanticsTool) -> BadgedValue {
        .words("—", spoken: "not offered in \(tool.name)", caption: "NOT IN \(tool.label)")
    }

    /// The caption parts every value of a control carries, in order.
    static func captionParts(_ resolved: Resolved) -> [String] {
        var parts: [String] = []
        if resolved.qualifiers.contains(.offscreen) { parts.append("OFFSCREEN") }
        if resolved.qualifiers.contains(.notThisDevice) { parts.append("NOT THIS PHONE") }
        if resolved.qualifiers.contains(.simulator) { parts.append("SIMULATOR") }
        if let c = resolved.caption, !parts.contains(c) { parts.append(c) }
        return parts
    }

    static func spokenCaption(_ caption: String) -> String {
        caption.lowercased().replacingOccurrences(of: "σ", with: "sigma").replacingOccurrences(of: " · ", with: ", ")
    }

    static func assemble(number: Double, style: NumberStyle, prefix: String, numberPhrase: String, resolved: Resolved,
                         parts: [String]) -> BadgedValue {
        let caption = parts.isEmpty ? nil : parts.joined(separator: " · ")
        var v = BadgedValue.number(number, style, resolved.provenance ?? .computed, qualifiers: resolved.qualifiers,
                                   source: resolved.source, device: resolved.device, caption: caption)
        v.text = prefix + v.text
        v.spoken = ([numberPhrase, (resolved.provenance ?? .computed).spokenPhrase(device: resolved.device)]
                    + parts.map(spokenCaption)).joined(separator: ", ")
        return v
    }

    static func wordsValue(_ words: String, spoken: String, resolved: Resolved, extra: [String] = []) -> BadgedValue {
        let parts = captionParts(resolved) + extra
        var v = BadgedValue.words(words, spoken: spoken, resolved.provenance, qualifiers: resolved.qualifiers, source: resolved.source,
                                  device: resolved.device, caption: parts.isEmpty ? nil : parts.joined(separator: " · "))
        v.spoken = ([v.spoken] + parts.map(spokenCaption)).joined(separator: ", ")
        return v
    }

    /// Non-law answers shared by both directions.
    static func nonLawValue(_ c: SemanticsControl, tool: SemanticsTool, resolved: Resolved) -> BadgedValue? {
        switch c.mapping {
        case .law: return nil
        case .unverified(let subject):
            var v = BadgedValue.unverified(subject)
            v.qualifiers.formUnion(c.qualifiers)
            v.source = c.source
            v.caption = c.caption
            if let cap = c.caption { v.spoken += ", " + spokenCaption(cap) }
            return v
        case .noSigma(let words, _, let spoken):
            return wordsValue(words, spoken: spoken, resolved: resolved)
        }
    }

    static func forwardValue(_ c: SemanticsControl, tool: SemanticsTool, resolved: Resolved, sigmaPx sigma: Double, displayScale: Double,
                             style: NumberStyle? = nil) -> BadgedValue {
        if let v = nonLawValue(c, tool: tool, resolved: resolved) { return v }
        let u = c.unitScale(displayScale)
        guard sigma.isFinite, sigma >= 0 else {
            return .words("NO σ", spoken: "this blur has no sigma to type in \(tool.name)", caption: "σ NOT DEFINED")
        }
        if let maxU = c.maxSigmaUnits, sigma / u > maxU {
            return wordsValue("OUT OF RANGE", spoken: "beyond the largest blur \(c.controlName) produces", resolved: resolved)
        }
        let inv: SemanticsInverse = resolved.calibration.map { SemanticsMath.inverse($0, sigmaPx: sigma, unitScale: u) }
            ?? SemanticsMath.typed(resolved.law, sigmaPx: sigma, unitScale: u, integerValued: c.integerValued)
        guard let typed = inv.typed else {
            switch inv.status {
            case .belowRange:
                return wordsValue("BELOW RANGE", spoken: "below the smallest blur \(c.controlName) produces", resolved: resolved)
            default:
                return wordsValue("OUT OF RANGE", spoken: "beyond the largest blur \(c.controlName) produces", resolved: resolved)
            }
        }
        let style = style ?? c.typedStyle
        let sigmaOnly: Bool = {
            switch c.kernelMatch {
            case .sigmaOnly: true
            case .sameBelowSwitch: typed > (resolved.calibration?.switchParameter ?? .infinity)
            case .same, .unknown: false
            }
        }()
        var parts = captionParts(resolved)
        if sigmaOnly { parts.append(c.matchCaption) }
        if inv.status == .nearest { parts.append(c.integerValued ? "NEAREST ODD WIDTH" : "NEAREST REACHABLE") }
        let phrase = (sigmaOnly ? "about " : "") + style.spoken(typed) + " in " + tool.name
        var v = assemble(number: typed, style: style, prefix: sigmaOnly ? "≈" : "", numberPhrase: phrase, resolved: resolved, parts: parts)
        if sigmaOnly, c.matchCaption == "SAME σ, DIFFERENT KERNEL" {
            // SPEC §4.1.4: "about 4.4 points, sigma-matched; SwiftUI's kernel shape differs".
            v.spoken = v.spoken.replacingOccurrences(of: spokenCaption(c.matchCaption), with: "sigma-matched; \(tool.name)'s kernel shape differs")
        }
        return v
    }

    static func reverseValue(_ c: SemanticsControl, tool: SemanticsTool, resolved: Resolved, typed: Double, displayScale: Double) -> BadgedValue {
        if let v = nonLawValue(c, tool: tool, resolved: resolved) { return v }
        let u = c.unitScale(displayScale)
        guard typed.isFinite, typed >= 0 else {
            return .words("—", spoken: "no value typed", caption: "NOTHING TYPED")
        }
        let sigma: Double? = resolved.calibration.map { typed > 0 ? $0.sigmaPx(parameter: typed, displayScale: u) : 0 }
            ?? SemanticsMath.sigmaPx(resolved.law, typed: typed, unitScale: u)
        guard let sigma else {
            return wordsValue("ODD WIDTHS ONLY", spoken: "\(c.controlName) accepts odd widths only", resolved: resolved)
        }
        var parts = captionParts(resolved)
        let tooBig = c.maxSigmaUnits.map { sigma / u > $0 } ?? false
        if tooBig { parts.append("ABOVE ITS MEASURED CAP") }
        let differs: Bool = {
            switch c.kernelMatch {
            case .sigmaOnly: true
            case .sameBelowSwitch: typed > (resolved.calibration?.switchParameter ?? .infinity)
            case .same, .unknown: false
            }
        }()
        if differs, let note = c.kernelNote { parts.append(note) }
        let style = NumberStyle.significant(3, unit: "px", spokenUnit: "pixels")
        let phrase = "sigma " + style.spoken(sigma) + " from " + c.typedStyle.spoken(typed) + " in " + tool.name
        return assemble(number: sigma, style: style, prefix: "", numberPhrase: phrase, resolved: resolved, parts: parts)
    }
}

// MARK: - Protocol conveniences (callable through `BlurServices.tools`)

public extension ToolConventionProviding {
    /// The SLIDE chip value (≤ 6 characters); see `ToolConventions.slideChipValue`.
    func slideChipValue(toolID: String, blur: BlurID, sigmaPx: Double?, displayScale: Double, measuredLaw: CalibrationLaw?) -> BadgedValue {
        ToolConventions.slideChipValue(toolID: toolID, blur: blur, sigmaPx: sigmaPx, displayScale: displayScale, measuredLaw: measuredLaw)
    }
    /// False when `toolID` does not offer `blur` (Compare floor 1 `NOT IN <TOOL>`, skipped for PARTS WAYS).
    func offers(toolID: String, blur: BlurID) -> Bool { ToolConventions.offers(toolID: toolID, blur: blur) }
    /// Both readings when the sources disagree (P27's toggle), one otherwise.
    func readings(toolID: String, blur: BlurID, sigmaPx: Double, displayScale: Double, measuredLaw: CalibrationLaw?) -> [SemanticsReading] {
        ToolConventions.readings(toolID: toolID, blur: blur, sigmaPx: sigmaPx, displayScale: displayScale, measuredLaw: measuredLaw)
    }
    func reverseReadings(toolID: String, blur: BlurID, typed value: Double, displayScale: Double,
                         measuredLaw: CalibrationLaw?) -> [SemanticsReading] {
        ToolConventions.reverseReadings(toolID: toolID, blur: blur, typed: value, displayScale: displayScale, measuredLaw: measuredLaw)
    }
}
