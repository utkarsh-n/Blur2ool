import Foundation

// OWNER: CALIBRATION (SPEC §4.8, §12, §13.3–§13.4). Everything the Calibrate sheet prints, as badged data: the RESULT rows
// (σ, σ/(r·scale), kurtosis on the axis and at 45°, model competition with the winner marked, wobble, extent, blend, border,
// the Mac reference kept beside the phone value), the prediction before a measurement exists, and the sweep plot's series.
// The numbers are MEASURED with this phone's DeviceStamp; SwiftUI and Core Animation subjects carry OFFSCREEN (SPEC §12.2
// item 9) and the drawHierarchy path ON-SCREEN · EXPERIMENTAL until its objective capture test passes; the shape name is
// an interpretation (INFERRED); a Mac value is MEASURED · NOT THIS DEVICE with the Mac's stamp. Tests run
// honestyViolations over all of it. The sheet only lays these out; it never formats a number itself.

public struct CalibrationReadoutValue: Sendable, Hashable {
    /// A short ALL-CAPS sub-label inside a row ("AXIS", "45°", "GAUSSIAN"), or nil.
    public var sublabel: String?
    public var value: BadgedValue
    /// The model-competition winner (drawn with a ✓ and spoken "lowest residual").
    public var isWinner: Bool
    public init(sublabel: String? = nil, value: BadgedValue, isWinner: Bool = false) {
        self.sublabel = sublabel; self.value = value; self.isWinner = isWinner
    }
}

public struct CalibrationReadoutRow: Sendable, Hashable, Identifiable {
    public var id: String
    /// ALL-CAPS mono label.
    public var label: String
    public var values: [CalibrationReadoutValue]
    /// An explanatory line under the row (every number in it badged).
    public var note: BadgedLine?
    public init(id: String, label: String, values: [CalibrationReadoutValue], note: BadgedLine? = nil) {
        self.id = id; self.label = label; self.values = values; self.note = note
    }
    public var badgedValues: [BadgedValue] { values.map(\.value) + (note?.values ?? []) }
}

/// What the border probe found for a SwiftUI blur (CAL §5.1 item 6).
public struct CalibrationBorderFinding: Sendable, Codable, Hashable {
    /// Alpha of the view's outermost column after the blur.
    public var borderAlpha: Double
    /// Alpha four device pixels outside the view's frame (the spill).
    public var outsideAlpha: Double
    public var opaqueRequested: Bool
    public init(borderAlpha: Double, outsideAlpha: Double, opaqueRequested: Bool) {
        self.borderAlpha = borderAlpha; self.outsideAlpha = outsideAlpha; self.opaqueRequested = opaqueRequested
    }
    public var spills: Bool { outsideAlpha > 0.01 }
    public var fadesToTransparent: Bool { borderAlpha < 0.98 }
    public var words: String {
        switch (fadesToTransparent, spills) {
        case (true, true): "TRANSPARENT EDGES, SPILLS OUTSIDE"
        case (true, false): "TRANSPARENT EDGES, STAYS INSIDE"
        case (false, true): "OPAQUE EDGES, SPILLS OUTSIDE"
        case (false, false): "OPAQUE EDGES, STAYS INSIDE"
        }
    }
}

public enum CalibrationReadout {
    public static let sigmaStyle = NumberStyle.decimals(2, unit: "px", spokenUnit: "pixels")
    public static let ratioStyle = NumberStyle.decimals(3)
    public static let kurtosisStyle = NumberStyle.decimals(2)
    public static let percentStyle = NumberStyle.decimals(1, unit: "%", spokenUnit: "percent")
    /// Model residuals are a few tenths of a percent of the step: two decimals keep the competition readable.
    public static let residualStyle = NumberStyle.decimals(2, unit: "%", spokenUnit: "percent")
    public static let midpointStyle = NumberStyle.decimals(2)
    public static let millisecondsStyle = NumberStyle.decimals(0, unit: "ms", spokenUnit: "milliseconds")
    public static let phaseNoun = CountNoun("phase", "phases")

    /// The qualifiers and caption every measured number of `request` carries.
    public static func qualifiers(_ request: CalibrationRequest, onScreenVerified: Bool = false) -> (Qualifiers, String?) {
        if request.path == .drawHierarchyOnScreen {
            return onScreenVerified ? ([], "ON-SCREEN CAPTURE") : ([.experimental], "ON-SCREEN · EXPERIMENTAL")
        }
        if request.subject.isOffscreenRenderOfOnScreenAPI { return ([.offscreen], "OFFSCREEN") }
        return ([], nil)
    }

    static func measured(_ v: Double, _ style: NumberStyle, _ device: DeviceStamp, _ q: (Qualifiers, String?)) -> BadgedValue {
        .number(v, style, .measured, qualifiers: q.0, device: device, caption: q.1)
    }
    static func measuredWords(_ text: String, _ device: DeviceStamp, _ q: (Qualifiers, String?)) -> BadgedValue {
        .words(text, spoken: q.1.map { "\(text.lowercased()), \($0.lowercased())" } ?? text.lowercased(), .measured,
               qualifiers: q.0, device: device, caption: q.1)
    }

    /// The RESULT header: `RESULT · 00:55 UTC · iPhone 15 Pro Max · iOS 27.2 · 15 Oct`. The time is in UTC because the
    /// DeviceStamp's day label is (a local time beside a UTC day would contradict it around midnight).
    public static func header(_ result: CalibrationResult) -> BadgedLine {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let c = calendar.dateComponents([.hour, .minute], from: result.device.date)
        let time = String(format: "%02d:%02d UTC", c.hour ?? 0, c.minute ?? 0)
        return BadgedLine([.text("RESULT ·"), .literal(time), .text("·"), .literal(result.device.label)])
    }

    /// The rows of one result (SPEC §4.8 RESULT panel).
    public static func rows(_ result: CalibrationResult, border: CalibrationBorderFinding? = nil,
                            onScreenVerified: Bool = false) -> [CalibrationReadoutRow] {
        let r = result.request, fit = result.fit, d = result.device
        let q = qualifiers(r, onScreenVerified: onScreenVerified)
        var rows: [CalibrationReadoutRow] = []
        guard fit.sigmaPx > 0 else {
            rows.append(CalibrationReadoutRow(id: "sigma", label: "σ", values: [
                CalibrationReadoutValue(value: measuredWords("NO EDGE FOUND", d, q))],
                note: .words("the render returned no step: the blur removed it or the edge left the canvas")))
            return rows
        }
        rows.append(CalibrationReadoutRow(id: "sigma", label: "σ", values: [
            CalibrationReadoutValue(sublabel: "MOMENT", value: measured(fit.sigmaPx, sigmaStyle, d, q)),
            CalibrationReadoutValue(sublabel: "LEAST SQUARES", value: measured(fit.lsqSigmaPx, sigmaStyle, d, q)),
        ]))
        if r.parameter > 0 {
            rows.append(CalibrationReadoutRow(id: "ratio", label: ratioLabel(r.subject), values: [
                CalibrationReadoutValue(value: measured(fit.sigmaPerParameterPixel, ratioStyle, d, q))],
                note: BadgedLine([.text("σ divided by the parameter in device pixels,"),
                                  .value(.number(r.parameter * r.displayScale, sigmaStyle, .computed))])))
        }
        var kurt = [CalibrationReadoutValue(sublabel: "AXIS", value: measured(fit.excessKurtosis, kurtosisStyle, d, q))]
        if let k45 = fit.excessKurtosis45 {
            kurt.append(CalibrationReadoutValue(sublabel: "45°", value: measured(k45, kurtosisStyle, d, q)))
        }
        rows.append(CalibrationReadoutRow(id: "kurtosis", label: "EXCESS KURTOSIS", values: kurt,
                                          note: kurtosisNote(fit)))
        if !fit.models.isEmpty {
            let best = fit.models.first?.model
            let ordered = [PSFModel.gaussian, .boxCubed, .truncatedGaussian].compactMap { m in fit.models.first { $0.model == m } }
            rows.append(CalibrationReadoutRow(id: "models", label: "MODEL FIT · RMS RESIDUAL", values: ordered.map { m in
                CalibrationReadoutValue(sublabel: modelTitle(m.model), value: measured(m.rmsResidualPercent, residualStyle, d, q),
                                        isWinner: m.model == best)
            }, note: .words("lowest residual wins; the app never picks a model in advance")))
        }
        rows.append(CalibrationReadoutRow(id: "shape", label: "LOOKS LIKE", values: [
            CalibrationReadoutValue(value: .words(fit.shapeName.uppercased(), spoken: fit.shapeName, .inferred,
                                                  caption: "READ FROM KURTOSIS"))],
            note: .words("an interpretation of the measured shape; how the API is built inside is not visible")))
        if r.phases > 1 {
            rows.append(CalibrationReadoutRow(id: "wobble", label: "WOBBLE", values: [
                CalibrationReadoutValue(sublabel: "CENTRE SPREAD", value: measured(fit.centreSpreadPx, sigmaStyle, d, q)),
                CalibrationReadoutValue(sublabel: "σ SPREAD", value: measured(fit.sigmaSpreadPercent, percentStyle, d, q)),
            ], note: BadgedLine([.text("edge moved through"), .value(.input(Double(r.phases), .integer(noun: phaseNoun))),
                                 .text(fit.centreSpreadPx > PSFFitter.shiftVariantSpreadPx
                                       ? "of whole device pixels: the centre moves, a resampling signature"
                                       : "of whole device pixels: shift-invariant at full resolution")])))
        }
        rows.append(CalibrationReadoutRow(id: "extent", label: "EXTENT", values: [
            CalibrationReadoutValue(sublabel: "VISIBLE", value: measured(fit.extentPx, sigmaStyle, d, q)),
            CalibrationReadoutValue(sublabel: "SUPPORT", value: measured(fit.supportPx, sigmaStyle, d, q)),
        ], note: .words("visible: still one eight-bit step off its plateau · support: above a thousandth of the peak")))
        if let mid = fit.encodedMidpoint, !r.subject.isShadow {
            let verdict = mid < 0.62 ? "GAMMA-ENCODED" : "LINEAR LIGHT"
            rows.append(CalibrationReadoutRow(id: "blend", label: "BLEND · EDGE MIDPOINT", values: [
                CalibrationReadoutValue(value: measured(mid, midpointStyle, d, q)),
                CalibrationReadoutValue(value: measuredWords(verdict, d, q)),
            ], note: BadgedLine([.text("encoded midpoint: a gamma-space blend gives"), .literal("0.50"),
                                 .text("and a linear-light blend"), .literal("0.735")])))
        }
        if let border {
            rows.append(CalibrationReadoutRow(id: "border", label: "BORDER", values: [
                CalibrationReadoutValue(value: measuredWords(border.words, d, q)),
            ], note: BadgedLine([.text("opaque:"), .literal(border.opaqueRequested ? "true" : "false"), .text("· border alpha"),
                                 .value(measured(border.borderAlpha, midpointStyle, d, q)), .text("· outside"),
                                 .value(measured(border.outsideAlpha, midpointStyle, d, q))])))
        }
        rows.append(contentsOf: macRows(r, phoneRatio: fit.sigmaPerParameterPixel, phoneSigma: fit.sigmaPx))
        rows.append(CalibrationReadoutRow(id: "time", label: "RENDER + READBACK", values: [
            CalibrationReadoutValue(value: .number(result.durationMilliseconds, millisecondsStyle, .measured, device: d,
                                                   caption: "WALL CLOCK, NOT GPU TIME"))]))
        return rows
    }

    /// Rows before this phone has measured `parameter`: the slot engraved NOT YET MEASURED, what the research reading
    /// predicts (INFERRED for Mac laws), and the Mac's own measurement.
    public static func pendingRows(_ request: CalibrationRequest) -> [CalibrationReadoutRow] {
        var rows = [CalibrationReadoutRow(id: "sigma", label: "σ", values: [
            CalibrationReadoutValue(value: .notYetMeasured("–.––", unit: "px"))],
            note: .words("not yet measured on this phone"))]
        if let p = CalibrationLaws.prediction(request.subject, parameter: request.parameter, displayScale: request.displayScale) {
            rows.append(CalibrationReadoutRow(id: "prediction", label: "PREDICTED", values: [
                CalibrationReadoutValue(value: .number(p.sigmaPx, sigmaStyle, p.provenance, source: p.source,
                                                       caption: p.provenance == .inferred ? "UNTIL MEASURED HERE" : nil))],
                note: BadgedLine([.literal(p.lawText)])))
        }
        rows.append(contentsOf: macRows(request, phoneRatio: nil, phoneSigma: nil))
        return rows
    }

    /// MAC REFERENCE: the research Mac's nearest measured point (σ/parameter at scale 1, i.e. per device pixel), kept beside
    /// the phone's value for the session (SPEC §12.2 item 6), and the difference.
    static func macRows(_ r: CalibrationRequest, phoneRatio: Double?, phoneSigma: Double?) -> [CalibrationReadoutRow] {
        let px = r.subject.parameterIsPoints ? r.parameter * r.displayScale : r.parameter
        guard r.subject.hasSingleSigma, let mac = CalibrationMacReference.nearest(r.subject, path: r.path, parameterPx: px) else { return [] }
        let qualifiers: Qualifiers = r.subject.isOffscreenRenderOfOnScreenAPI ? [.notThisDevice, .offscreen] : [.notThisDevice]
        let macValue = BadgedValue.number(mac.ratio, ratioStyle, .measured, qualifiers: qualifiers,
                                          source: CalibrationMacReference.source, device: CalibrationMacReference.device,
                                          caption: "NOT THIS DEVICE")
        var rows = [CalibrationReadoutRow(id: "mac", label: "MAC REFERENCE · " + ratioLabel(r.subject), values: [
            CalibrationReadoutValue(value: macValue)],
            note: BadgedLine([.text("at"), .value(.input(mac.parameterPx, sigmaStyle)), .text("·"),
                              .literal(CalibrationMacReference.label)]))]
        if let phoneRatio, mac.ratio > 0 {
            let delta = (phoneRatio - mac.ratio) / mac.ratio * 100
            var style = percentStyle; style.explicitPlus = true
            rows.append(CalibrationReadoutRow(id: "delta", label: "THIS PHONE VS MAC", values: [
                CalibrationReadoutValue(value: .number(delta, style, .computed))],
                note: abs(mac.parameterPx - px) > 1e-9
                    ? BadgedLine([.text("nearest Mac radius; this measurement is at"), .value(.input(px, sigmaStyle))])
                    : .words("same device-pixel radius on both")))
        }
        return rows
    }

    public static func ratioLabel(_ subject: CalibrationSubject) -> String {
        let p = subject.parameterSymbol
        return subject.parameterIsPoints ? "σ / (\(p)·SCALE)" : "σ / \(p)"
    }
    public static func modelTitle(_ model: PSFModel) -> String {
        switch model {
        case .gaussian: "GAUSSIAN"
        case .truncatedGaussian: "TRUNC-G"
        case .boxCubed: "BOX³"
        }
    }
    static func kurtosisNote(_ fit: PSFFit) -> BadgedLine {
        guard let k45 = fit.excessKurtosis45 else { return .words("Gaussian zero · box cubed and tent negative · peaked positive") }
        let separable = abs(fit.excessKurtosis) > 0.15 && abs(k45 - fit.excessKurtosis / 2) < abs(k45 - fit.excessKurtosis)
        return .words(separable ? "the diagonal is about half the axis value: a separable kernel"
                                : "axis and diagonal agree: an isotropic kernel")
    }
}

// MARK: - The sweep plot (SPEC §4.8 SWEEP; §13.3)

public struct CalibrationSweepPoint: Sendable, Hashable, Identifiable {
    public var id: String
    /// The API parameter (pt for SwiftUI) on the log x axis.
    public var parameter: Double
    /// σ / (parameter · scale).
    public var ratio: Double
    public var centreSpreadPx: Double?
    public var value: BadgedValue
}

public struct CalibrationSweepModel: Sendable, Hashable {
    public var subject: CalibrationSubject
    public var displayScale: Double
    /// This phone's points (filled).
    public var phone: [CalibrationSweepPoint]
    /// The Mac reference at the same device-pixel radii (dashed), parameter = Mac px / this scale.
    public var mac: [CalibrationSweepPoint]
    /// Radii of the planned sweep not yet measured here (hollow).
    public var pending: [Double]
    /// The regime switch: MEASURED (filled) from this phone's law, or INFERRED (hollow) from the Mac's 5-px switch.
    public var switchParameter: BadgedValue?
    public var switchIsMeasured: Bool
    public var law: CalibrationLaw?
    public var smallRatio: BadgedValue?
    public var largeRatio: BadgedValue?
    /// The plot's one-sentence accessibility summary.
    public var summary: String

    public static let parameterStyle = NumberStyle.decimals(2, unit: "pt", spokenUnit: "points")

    public static func make(subject: CalibrationSubject, path: CalibrationPath, displayScale: Double,
                            results: [CalibrationResult], fitter: any PSFFitting = PSFFitter()) -> CalibrationSweepModel {
        let mine = results.filter { $0.request.subject == subject && $0.request.path == path && $0.request.parameter > 0 && $0.fit.sigmaPx > 0 }
        var newest: [Double: CalibrationResult] = [:]
        for r in mine where newest[r.request.parameter].map({ $0.device.date < r.device.date }) ?? true { newest[r.request.parameter] = r }
        let unit = subject.parameterIsPoints ? subject.parameterUnit : "px"
        let pStyle = NumberStyle.decimals(2, unit: unit, spokenUnit: subject.parameterSpokenUnit)
        let phone = newest.values.sorted { $0.request.parameter < $1.request.parameter }.map { r in
            let q = CalibrationReadout.qualifiers(r.request)
            return CalibrationSweepPoint(id: "phone-\(r.request.parameter)", parameter: r.request.parameter,
                                         ratio: r.fit.sigmaPerParameterPixel, centreSpreadPx: r.fit.centreSpreadPx,
                                         value: .number(r.fit.sigmaPerParameterPixel, CalibrationReadout.ratioStyle, .measured,
                                                        qualifiers: q.0, device: r.device, caption: q.1))
        }
        let scale = subject.parameterIsPoints ? displayScale : 1
        let macQualifiers: Qualifiers = subject.isOffscreenRenderOfOnScreenAPI ? [.notThisDevice, .offscreen] : [.notThisDevice]
        let mac = CalibrationMacReference.points(subject, path: path).filter { $0.sigmaPx > 0 }.map { p in
            CalibrationSweepPoint(id: "mac-\(p.parameterPx)", parameter: p.parameterPx / scale, ratio: p.ratio,
                                  centreSpreadPx: p.centreSpreadPx,
                                  value: .number(p.ratio, CalibrationReadout.ratioStyle, .measured, qualifiers: macQualifiers,
                                                 source: CalibrationMacReference.source, device: CalibrationMacReference.device,
                                                 caption: "NOT THIS DEVICE"))
        }
        let measured = Set(phone.map(\.parameter))
        let pending = CalibrationPlan.sweepParameters(subject).filter { !measured.contains($0) }
        let law = fitter.law(mine)
        var switchValue: BadgedValue?
        var switchMeasured = false
        if let law, let s = law.switchParameter {
            switchValue = .number(s, pStyle, .measured, device: law.device, caption: "REGIME SWITCH")
            switchMeasured = true
        } else if subject == .swiftUIBlur {
            switchValue = .number(CalibrationMacReference.swiftUISwitchPx / scale, pStyle, .inferred,
                                  source: CalibrationMacReference.source, caption: "MAC SWITCH ÷ SCALE")
        }
        let small = law?.smallRatio.map { BadgedValue.number($0, CalibrationReadout.ratioStyle, .measured, device: law?.device) }
        let large = law.map { BadgedValue.number($0.largeRatio, CalibrationReadout.ratioStyle, .measured, device: $0.device) }
        var summary = "\(phone.count) of \(phone.count + pending.count) radii measured on this phone"
        if let switchValue { summary += "; regime switch at \(switchValue.spoken)" }
        return CalibrationSweepModel(subject: subject, displayScale: displayScale, phone: phone, mac: mac, pending: pending,
                                     switchParameter: switchValue, switchIsMeasured: switchMeasured, law: law,
                                     smallRatio: small, largeRatio: large, summary: summary)
    }

    public var allBadgedValues: [BadgedValue] {
        phone.map(\.value) + mac.map(\.value) + [switchParameter, smallRatio, largeRatio].compactMap { $0 }
    }
}

/// The MODELED duration of a run of measurements, from this phone's measured wall-clock time per rendered pixel.
public enum CalibrationEstimate {
    /// Milliseconds per device pixel rendered, from recent results (nil without any).
    public static func millisecondsPerPixel(_ results: [CalibrationResult]) -> Double? {
        let rates = results.suffix(12).compactMap { r -> Double? in
            let canvas = CalibrationCanvas(parameter: r.request.parameter, scale: r.request.displayScale)
            let renders = Double(CalibrationPlan.renders(r.request))
            return canvas.pixels > 0 && r.durationMilliseconds > 0 ? r.durationMilliseconds / (canvas.pixels * renders) : nil
        }
        return rates.isEmpty ? nil : PSFStatistics.median(rates)
    }
    /// Seconds for `requests` at `msPerPixel`, plus one 16-ms gap per render (one render per run-loop turn).
    public static func seconds(_ requests: [CalibrationRequest], msPerPixel: Double) -> Double {
        requests.reduce(0) { total, r in
            let canvas = CalibrationCanvas(parameter: r.parameter, scale: r.displayScale)
            let renders = Double(CalibrationPlan.renders(r))
            return total + renders * (canvas.pixels * msPerPixel + 16) / 1000
        }
    }
    public static func badged(_ seconds: Double) -> BadgedValue {
        .number(seconds, NumberStyle.decimals(0, unit: "s", spokenUnit: "seconds"), .modeled,
                caption: "FROM THIS PHONE'S RENDER TIMES")
    }
}
