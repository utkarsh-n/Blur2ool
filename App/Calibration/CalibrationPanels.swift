import SwiftUI
import Charts
import BlurCore

// OWNER: CALIBRATION (SPEC §4.8 panels, §12 badges, §14 accessibility). The Calibrate sheet's panels. Numbers come only
// from BlurCore's CalibrationReadout as BadgedValues (their text is BlurCore's one formatter); each row carries its badge
// at the trailing edge (one badge for a row whose numbers share a provenance, as the SPEC §4.8 wireframe draws them,
// otherwise one per number); every plot has an AXChartDescriptor and a data-table disclosure with the same numbers.

// MARK: - Shared pieces

/// Metro manifest values this sheet uses (Documentation/metro-station-design-tokens.json), named here so the sheet depends
/// only on the frozen starter (InstrumentPalette, InstrumentMetrics) and the frozen component initialisers.
enum CalibrationLayout {
    static let mainStack: CGFloat = 12              // componentSpacing.mainStack
    static let screenInset: CGFloat = 12            // componentSpacing.screenInset
    static let portraitContentMax: CGFloat = 540    // layout.portraitContentMax
    static let labelTracking: CGFloat = 1.2         // Metro §4 telemetry label: caption2 mono, tracking 1.2
    static let panelFill: Double = 0.85             // opacity.panelFill
    static let divider: Double = 0.10               // Metro §12 dividers: white 0.10
}

enum CalibrationInk {
    static func of(_ p: Provenance?) -> Color {
        switch p {
        case .live?: InstrumentPalette.actionCyan
        case .measured?: InstrumentPalette.instrumentAmber
        case .computed?: InstrumentPalette.displayInk
        case .modeled?: InstrumentPalette.spectrum
        case .reference?: InstrumentPalette.secondaryInk
        case .inferred?: InstrumentPalette.spectrumDepth
        case nil: InstrumentPalette.secondaryInk
        }
    }
}

/// A panel eyebrow: caption mono, tracked, secondary ink.
struct CalibrationEyebrow: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced))
            .tracking(CalibrationLayout.labelTracking)
            .foregroundStyle(InstrumentPalette.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A BadgedLine as one text run: words in the given ink, literals in mono, each number followed by its badge word.
struct CalibrationLineText: View {
    let line: BadgedLine
    var font: Font = .footnote
    var ink: Color = InstrumentPalette.secondaryInk

    var body: some View {
        line.segments.enumerated().reduce(Text("")) { text, item in
            let (i, segment) = item
            let space = i == 0 ? "" : " "
            switch segment {
            case .text(let s):
                return Text("\(text)\(space)\(Text(s).foregroundStyle(ink))")
            case .literal(let s):
                return Text("\(text)\(space)\(Text(s).font(font.monospaced()).foregroundStyle(InstrumentPalette.displayInk))")
            case .value(let v):
                let number = Text(v.textWithUnit).font(font.monospacedDigit()).foregroundStyle(InstrumentPalette.displayInk)
                guard let p = v.provenance, !v.isInput else { return Text("\(text)\(space)\(number)") }
                let badge = Text(" " + p.word).font(.system(.caption2, design: .monospaced)).foregroundStyle(CalibrationInk.of(p))
                return Text("\(text)\(space)\(number)\(badge)")
            }
        }
        .font(font)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(line.spoken)
    }
}

/// A wrapping row (values and badges reflow at larger Dynamic Type instead of shrinking).
struct CalibrationFlowLayout: Layout {
    var spacing: CGFloat = 12
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width { y += lineHeight + lineSpacing; x = 0; lineHeight = 0 }
            x += size.width + spacing
            widest = Swift.max(widest, x - spacing)
            lineHeight = Swift.max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + size.width > bounds.maxX { y += lineHeight + lineSpacing; x = bounds.minX; lineHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = Swift.max(lineHeight, size.height)
        }
    }
}

/// One RESULT row: the ALL-CAPS label and the row's badge on top, the values (sub-label, number, unit) reflowing below,
/// the note under them.
struct CalibrationReadoutRowView: View {
    let row: CalibrationReadoutRow
    @ScaledMetric(relativeTo: .title3) private var valueSize: CGFloat = 19

    private var sharedBadge: (Provenance, Qualifiers)? {
        let badges = row.values.compactMap { v -> String? in v.value.provenance.map { "\($0.rawValue)|\(v.value.qualifiers.rawValue)" } }
        guard let first = row.values.first?.value, let p = first.provenance, Set(badges).count == 1, badges.count == row.values.count else { return nil }
        return (p, first.qualifiers)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                CalibrationEyebrow(text: row.label)
                Spacer(minLength: 4)
                if let badge = sharedBadge { HonestyBadge(badge.0, qualifiers: badge.1) }
            }
            CalibrationFlowLayout(spacing: 14, lineSpacing: 6) {
                ForEach(Array(row.values.enumerated()), id: \.offset) { _, item in
                    valueView(item, ownBadge: sharedBadge == nil)
                }
            }
            if let note = row.note { CalibrationLineText(line: note, font: .caption) }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func valueView(_ item: CalibrationReadoutValue, ownBadge: Bool) -> some View {
        let v = item.value
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if item.isWinner {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(InstrumentPalette.instrumentAmber)
                    .accessibilityLabel("lowest residual")
            }
            if let sub = item.sublabel {
                Text(sub).font(.system(.caption2, design: .monospaced)).foregroundStyle(InstrumentPalette.secondaryInk)
            }
            Text(v.text)
                .font(.system(size: v.value == nil ? valueSize * 0.78 : valueSize, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(valueInk(item))
                .lineLimit(1)
            if let unit = v.unit {
                Text(unit).font(.system(.caption2, design: .monospaced)).foregroundStyle(InstrumentPalette.secondaryInk)
            }
            if ownBadge, let p = v.provenance, !v.isInput { HonestyBadge(p, qualifiers: v.qualifiers) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((item.sublabel.map { $0.lowercased() + " " } ?? "") + v.spoken + (item.isWinner ? ", lowest residual" : ""))
    }

    /// Numbers in the instrument's cyan (the winner in amber); words in their badge's ink.
    private func valueInk(_ item: CalibrationReadoutValue) -> Color {
        if item.value.value == nil { return CalibrationInk.of(item.value.provenance) }
        return item.isWinner ? InstrumentPalette.instrumentAmber : InstrumentPalette.actionCyan
    }
}

// MARK: - RESULT

struct CalibrationResultPanel: View {
    let request: CalibrationRequest
    let result: CalibrationResult?
    let service: CalibrationService

    private var rows: [CalibrationReadoutRow] {
        guard let result else { return CalibrationReadout.pendingRows(request) }
        return CalibrationReadout.rows(result, border: request.subject == .swiftUIBlur ? service.borderFindings[.swiftUIBlur] : nil,
                                       onScreenVerified: service.captureTest?.passed ?? false)
    }

    var body: some View {
        InstrumentContentPanel {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    if let result {
                        CalibrationLineText(line: CalibrationReadout.header(result), font: .caption2.monospaced())
                    } else {
                        CalibrationEyebrow(text: "RESULT · NOT YET MEASURED ON THIS PHONE")
                    }
                }
                if let failure = service.lastFailure, !service.isBusy {
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(InstrumentPalette.actionAmber)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                }
                ForEach(rows) { row in
                    CalibrationReadoutRowView(row: row)
                    if row.id != rows.last?.id { Divider().overlay(Color.white.opacity(CalibrationLayout.divider)) }
                }
                if let result, result.fit.lsf.count > 4 {
                    CalibrationLSFPlot(fit: result.fit, device: result.device).padding(.top, 8)
                }
            }
        }
    }
}

/// The measured line-spread function beside a Gaussian of the same σ (SPEC §4.8: "the LSF, for plotting beside the theory").
struct CalibrationLSFPlot: View {
    let fit: PSFFit
    let device: DeviceStamp

    struct Sample: Identifiable, Hashable { var id: String; var x: Double; var y: Double; var series: String }

    private var samples: [Sample] {
        let n = fit.lsf.count, half = (n - 1) / 2
        let peak = Swift.max(fit.lsf.max() ?? 1, 1e-12)
        let s = Swift.max(fit.sigmaPx, 1e-6)
        let gaussPeak = 1 / ((2 * Double.pi).squareRoot() * s)
        return fit.lsf.enumerated().flatMap { i, v -> [Sample] in
            let x = Double(i - half)
            return [Sample(id: "m\(i)", x: x, y: v / peak, series: "This phone (measured)"),
                     Sample(id: "g\(i)", x: x, y: gaussPeak * exp(-x * x / (2 * s * s)) / peak, series: "Gaussian of the same σ (computed)")]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                CalibrationEyebrow(text: "LINE-SPREAD FUNCTION · NORMALIZED")
                Spacer()
                HonestyBadge(.measured)
            }
            Chart(samples) { s in
                LineMark(x: .value("Offset (px)", s.x), y: .value("LSF (normalized)", s.y), series: .value("Series", s.series))
                    .foregroundStyle(s.series.hasPrefix("This") ? InstrumentPalette.actionCyan : InstrumentPalette.secondaryInk)
                    .lineStyle(s.series.hasPrefix("This") ? StrokeStyle(lineWidth: 2) : StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    .interpolationMethod(.linear)
            }
            .chartLegend(.hidden)
            .chartXAxisLabel("offset from the edge (device px)", alignment: .center)
            .chartYAxis { AxisMarks(position: .leading, values: [0, 0.5, 1]) }
            .frame(height: 120)
            .accessibilityChartDescriptor(CalibrationLSFDescriptor(samples: samples))
            HStack(spacing: 14) {
                legendSwatch(InstrumentPalette.actionCyan, dashed: false, "this phone")
                legendSwatch(InstrumentPalette.secondaryInk, dashed: true, "Gaussian, same σ")
            }
            .font(.caption2)
            .foregroundStyle(InstrumentPalette.secondaryInk)
        }
    }

    private func legendSwatch(_ color: Color, dashed: Bool, _ text: String) -> some View {
        HStack(spacing: 4) {
            Path { p in p.move(to: CGPoint(x: 0, y: 4)); p.addLine(to: CGPoint(x: 18, y: 4)) }
                .stroke(color, style: StrokeStyle(lineWidth: dashed ? 1.2 : 2, dash: dashed ? [4, 3] : []))
                .frame(width: 18, height: 8)
            Text(text)
        }
        .accessibilityHidden(true)
    }
}

struct CalibrationLSFDescriptor: AXChartDescriptorRepresentable {
    let samples: [CalibrationLSFPlot.Sample]
    func makeChartDescriptor() -> AXChartDescriptor {
        let xs = samples.map(\.x)
        let x = AXNumericDataAxisDescriptor(title: "Offset from the edge, device pixels", range: (xs.min() ?? 0)...(xs.max() ?? 1),
                                            gridlinePositions: []) { String(format: "%.0f pixels", $0) }
        let y = AXNumericDataAxisDescriptor(title: "Line-spread, normalized", range: 0...1, gridlinePositions: [0.5]) { String(format: "%.2f", $0) }
        let series = Dictionary(grouping: samples, by: \.series).sorted { $0.key > $1.key }.map { name, points in
            AXDataSeriesDescriptor(name: name, isContinuous: true, dataPoints: points.map { AXDataPoint(x: $0.x, y: $0.y) })
        }
        return AXChartDescriptor(title: "Measured line-spread function beside a Gaussian of the same sigma", summary: nil,
                                 xAxis: x, yAxis: y, additionalAxes: [], series: series)
    }
}

// MARK: - SWEEP

struct CalibrationSweepPanel: View {
    let subject: CalibrationSubject
    let path: CalibrationPath
    let colourMode: CalibrationColourMode
    let opaque: Bool
    let displayScale: Double
    let service: CalibrationService

    private var model: CalibrationSweepModel {
        let mine = service.results(subject).filter {
            $0.request.colourMode == colourMode && ($0.request.opaque ?? false) == (subject == .swiftUIBlur ? opaque : false)
        }
        return CalibrationSweepModel.make(subject: subject, path: path, displayScale: displayScale, results: mine)
    }

    var body: some View {
        let m = model
        InstrumentContentPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    CalibrationEyebrow(text: "SWEEP · " + CalibrationReadout.ratioLabel(subject) + " VS " + subject.parameterSymbol.uppercased())
                    Spacer()
                }
                CalibrationSweepChart(model: m)
                legend(m)
                lawRows(m)
                runControls(m)
                CalibrationSweepTable(model: m)
            }
        }
    }

    private func legend(_ m: CalibrationSweepModel) -> some View {
        CalibrationFlowLayout(spacing: 12, lineSpacing: 4) {
            swatch(filled: true, InstrumentPalette.actionCyan, "this iPhone")
            swatch(filled: false, InstrumentPalette.secondaryInk, "not yet measured")
            if !m.mac.isEmpty { dash("macOS 27.2 (M1 Max) reference") }
            if m.switchParameter != nil { diamond(filled: m.switchIsMeasured, m.switchIsMeasured ? "switch, measured" : "switch, inferred") }
        }
        .font(.caption2)
        .foregroundStyle(InstrumentPalette.secondaryInk)
        .accessibilityHidden(true)
    }
    private func swatch(filled: Bool, _ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(filled ? c : .clear).overlay(Circle().stroke(c, lineWidth: 1)).frame(width: 7, height: 7)
            Text(t)
        }
    }
    private func dash(_ t: String) -> some View {
        HStack(spacing: 4) {
            Path { p in p.move(to: CGPoint(x: 0, y: 4)); p.addLine(to: CGPoint(x: 16, y: 4)) }
                .stroke(InstrumentPalette.secondaryInk, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])).frame(width: 16, height: 8)
            Text(t)
        }
    }
    private func diamond(filled: Bool, _ t: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: filled ? "diamond.fill" : "diamond").font(.caption2).foregroundStyle(InstrumentPalette.instrumentAmber)
            Text(t)
        }
    }

    @ViewBuilder
    private func lawRows(_ m: CalibrationSweepModel) -> some View {
        if let row = lawRow(m) { CalibrationReadoutRowView(row: row) }
    }

    private func lawRow(_ m: CalibrationSweepModel) -> CalibrationReadoutRow? {
        var values: [CalibrationReadoutValue] = []
        if let s = m.smallRatio { values.append(CalibrationReadoutValue(sublabel: "BELOW", value: s)) }
        if let l = m.largeRatio { values.append(CalibrationReadoutValue(sublabel: m.smallRatio == nil ? "RATIO" : "ABOVE", value: l)) }
        if let s = m.switchParameter { values.append(CalibrationReadoutValue(sublabel: "SWITCH", value: s)) }
        guard !values.isEmpty else { return nil }
        let note: BadgedLine = m.law == nil
            ? .words("the switch is the Mac's, divided by this screen's scale, until this phone's sweep measures it")
            : .words("this phone's law: the ratio below and above the switch, read from the measured points")
        return CalibrationReadoutRow(id: "law", label: m.law == nil ? "LAW · NOT YET MEASURED HERE" : "LAW · THIS PHONE",
                                     values: values, note: note)
    }

    @ViewBuilder
    private func runControls(_ m: CalibrationSweepModel) -> some View {
        let busy = service.isBusy
        let radii = CalibrationPlan.sweepParameters(subject).count
        let count = NumberStyle.integer(noun: CountNoun("radius", "radii")).text(Double(radii))
        let phases = NumberStyle.integer().text(Double(CalibrationPlan.phases))
        VStack(alignment: .leading, spacing: 8) {
            if busy {
                CalibrationProgressRow(service: service)
            } else {
                if subject == .swiftUIBlur {
                    Button { Task { await service.runBasicSet() } } label: {
                        Label("Run basic set · \(NumberStyle.integer().text(Double(CalibrationPlan.basicSetRadii.count))) radii × \(phases) phases",
                              systemImage: "dot.scope")
                            .frame(maxWidth: .infinity, minHeight: InstrumentMetrics.controlTarget)
                    }
                    .buttonStyle(.glass)
                    .tint(InstrumentPalette.actionCyan)
                }
                Button {
                    Task { await service.runSweep(subject, path: path, colourMode: colourMode, opaque: opaque) }
                } label: {
                    Label("Run sweep · \(count) radii × \(phases) phases", systemImage: "waveform.path.ecg")
                        .frame(maxWidth: .infinity, minHeight: InstrumentMetrics.controlTarget)
                }
                .buttonStyle(.glass)
                .tint(InstrumentPalette.actionCyan)
                if let estimate = sweepEstimate { CalibrationLineText(line: BadgedLine([.text("takes about"), .value(estimate)]), font: .caption) }
            }
        }
    }

    private var sweepEstimate: BadgedValue? {
        guard let rate = CalibrationEstimate.millisecondsPerPixel(service.results(subject)) else { return nil }
        let scale = subject.parameterIsPoints ? displayScale : 1
        let requests = CalibrationPlan.sweepParameters(subject).map {
            CalibrationRequest(subject: subject, path: path, parameter: $0, displayScale: scale, phases: CalibrationPlan.phases)
        }
        return CalibrationEstimate.badged(CalibrationEstimate.seconds(requests, msPerPixel: rate))
    }
}

/// The running job: words and a native progress bar (no unbadged numbers), with Pause / Resume and Cancel.
struct CalibrationProgressRow: View {
    let service: CalibrationService
    var body: some View {
        let (done, total, paused) = progress
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text((paused ? "PAUSED · " : "RUNNING · ") + (service.jobTitle ?? "CALIBRATION")
                     + (service.pausedByTouch ? " · RESUMES WHEN IDLE" : ""))
                    .font(.system(.caption, design: .monospaced))
                    .tracking(CalibrationLayout.labelTracking)
                    .foregroundStyle(paused ? InstrumentPalette.secondaryInk : InstrumentPalette.actionAmber)
                Spacer()
            }
            ProgressView(value: Double(done), total: Double(Swift.max(total, 1)))
                .tint(InstrumentPalette.actionAmber)
                .accessibilityLabel(service.jobTitle?.lowercased() ?? "calibration")
            HStack(spacing: 10) {
                Button(paused ? "Resume" : "Pause") { paused ? service.resume() : service.pause() }
                    .buttonStyle(.glass)
                    .frame(minHeight: InstrumentMetrics.controlTarget)
                Button("Cancel", role: .cancel) { service.cancel() }
                    .buttonStyle(.glass)
                    .frame(minHeight: InstrumentMetrics.controlTarget)
            }
        }
    }
    private var progress: (Int, Int, Bool) {
        switch service.state {
        case .running(let d, let t, _): (d, t, false)
        case .paused(let d, let t): (d, t, true)
        default: (0, 1, false)
        }
    }
}

struct CalibrationSweepChart: View {
    let model: CalibrationSweepModel

    struct Mark: Identifiable { var id: String; var x: Double; var y: Double }

    private var yDomain: ClosedRange<Double> {
        let ys = model.phone.map(\.ratio) + model.mac.map(\.ratio) + [model.smallRatio?.value, model.largeRatio?.value].compactMap { $0 }
        let lo = Swift.min(ys.min() ?? 0.85, 0.85), hi = Swift.max(ys.max() ?? 1.05, 1.05)
        return (lo - 0.03)...(hi + 0.03)
    }
    private var xDomain: ClosedRange<Double> {
        let xs = model.phone.map(\.parameter) + model.mac.map(\.parameter) + model.pending
        return Swift.max(0.1, (xs.min() ?? 0.25) * 0.8)...((xs.max() ?? 96) * 1.25)
    }

    var body: some View {
        let floor = yDomain.lowerBound + 0.012
        Chart {
            ForEach(model.mac) { p in
                LineMark(x: .value("Parameter", p.parameter), y: .value("Ratio", p.ratio), series: .value("Series", "Mac"))
                    .foregroundStyle(InstrumentPalette.secondaryInk)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            }
            ForEach(model.pending, id: \.self) { x in
                PointMark(x: .value("Parameter", x), y: .value("Ratio", floor))
                    .symbol { Circle().stroke(InstrumentPalette.secondaryInk, lineWidth: 1).frame(width: 5, height: 5) }
            }
            ForEach(model.phone) { p in
                PointMark(x: .value("Parameter", p.parameter), y: .value("Ratio", p.ratio))
                    .symbol { Circle().fill(InstrumentPalette.actionCyan).frame(width: 7, height: 7) }
            }
            if let s = model.switchParameter?.value {
                RuleMark(x: .value("Switch", s))
                    .foregroundStyle(InstrumentPalette.instrumentAmber.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: model.switchIsMeasured ? [] : [2, 3]))
                PointMark(x: .value("Switch", s), y: .value("Ratio", yDomain.upperBound - 0.02))
                    .symbol {
                        Image(systemName: model.switchIsMeasured ? "diamond.fill" : "diamond")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(InstrumentPalette.instrumentAmber)
                    }
            }
        }
        .chartXScale(domain: xDomain, type: .log)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: [0.25, 0.5, 1, 2, 4, 8, 16, 32, 64].filter { xDomain.contains($0) }) { v in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel { if let d = v.as(Double.self) { Text(d < 1 ? String(format: "%.2g", d) : String(format: "%.0f", d)) } }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel()
            }
        }
        .chartXAxisLabel(model.subject.parameterLabel.lowercased() + " (" + model.subject.parameterUnit + ", log)", alignment: .center)
        .frame(height: 190)
        .accessibilityChartDescriptor(CalibrationSweepDescriptor(model: model))
        .accessibilityLabel("Sweep plot. " + model.summary)
    }
}

struct CalibrationSweepDescriptor: AXChartDescriptorRepresentable {
    let model: CalibrationSweepModel
    func makeChartDescriptor() -> AXChartDescriptor {
        let xs = model.phone.map(\.parameter) + model.mac.map(\.parameter)
        let x = AXNumericDataAxisDescriptor(title: model.subject.parameterLabel.lowercased() + ", " + model.subject.parameterSpokenUnit,
                                            range: Swift.max(0.1, xs.min() ?? 0.25)...(xs.max() ?? 96), gridlinePositions: []) {
            String(format: "%.2f", $0)
        }
        let y = AXNumericDataAxisDescriptor(title: "sigma divided by the parameter in device pixels", range: 0...1.2,
                                            gridlinePositions: [0.9, 1.0]) { String(format: "%.3f", $0) }
        var series = [AXDataSeriesDescriptor(name: "This iPhone, measured", isContinuous: false,
                                             dataPoints: model.phone.map { AXDataPoint(x: $0.parameter, y: $0.ratio, label: $0.value.spoken) })]
        if !model.mac.isEmpty {
            series.append(AXDataSeriesDescriptor(name: "Mac reference, measured on macOS 27.2, not this device", isContinuous: true,
                                                 dataPoints: model.mac.map { AXDataPoint(x: $0.parameter, y: $0.ratio) }))
        }
        return AXChartDescriptor(title: "Sigma ratio against the parameter", summary: model.summary, xAxis: x, yAxis: y,
                                 additionalAxes: [], series: series)
    }
}

/// The plot's numbers as a table (SPEC §14: every plot has a data-table disclosure with the same numbers).
struct CalibrationSweepTable: View {
    let model: CalibrationSweepModel
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                if model.phone.isEmpty {
                    Text("No point measured on this phone yet.").font(.footnote).foregroundStyle(InstrumentPalette.secondaryInk)
                }
                ForEach(model.phone) { p in
                    CalibrationLineText(line: BadgedLine([.value(.input(p.parameter, NumberStyle.decimals(2, unit: model.subject.parameterUnit,
                                                                                                          spokenUnit: model.subject.parameterSpokenUnit))),
                                                          .text("→"), .value(p.value)]), font: .caption)
                }
                if !model.mac.isEmpty {
                    CalibrationEyebrow(text: "MAC REFERENCE · " + CalibrationMacReference.label).padding(.top, 6)
                    ForEach(model.mac.prefix(40)) { p in
                        CalibrationLineText(line: BadgedLine([.value(.input(p.parameter, NumberStyle.decimals(2, unit: model.subject.parameterUnit,
                                                                                                              spokenUnit: model.subject.parameterSpokenUnit))),
                                                              .text("→"), .value(p.value)]), font: .caption)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Data table").font(.footnote.weight(.medium)).foregroundStyle(InstrumentPalette.actionCyan)
        }
        .tint(InstrumentPalette.actionCyan)
    }
}

// MARK: - The on-screen experiment and what is inferred inside Apple

struct CalibrationOnScreenPanel: View {
    let service: CalibrationService
    let pathIsOnScreen: Bool

    var body: some View {
        InstrumentContentPanel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    CalibrationEyebrow(text: "ON-SCREEN PATH (EXPERIMENT) · drawHierarchy CAPTURE")
                    Spacer(minLength: 4)
                    if let test = service.captureTest { HonestyBadge(.measured, qualifiers: test.passed ? [] : [.experimental]) }
                }
                Text(service.captureTest.map { $0.passed
                        ? "The capture shows a material blurring its backdrop: this path captures what the render server composites on this phone."
                        : "The capture does not show the material blurring its backdrop: results of this path stay EXPERIMENTAL." }
                     ?? "Whether a drawHierarchy capture contains what the render server composites is not known. Until the test below shows a material blurring a known backdrop in the capture, results of this path are labelled ON-SCREEN · EXPERIMENTAL.")
                    .font(.footnote)
                    .foregroundStyle(InstrumentPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if let t = service.captureTest {
                    let style = NumberStyle.decimals(1, unit: "px", spokenUnit: "pixels")
                    CalibrationReadoutRowView(row: CalibrationReadoutRow(id: "capture", label: "CAPTURE TEST · " + (t.passed ? "PASSED" : "NOT PASSED"), values: [
                        CalibrationReadoutValue(sublabel: "BARE RISE", value: .number(t.bareRiseWidthPx, style, .measured, device: t.device)),
                        CalibrationReadoutValue(sublabel: "UNDER MATERIAL", value: .number(t.materialRiseWidthPx, style, .measured, device: t.device)),
                        CalibrationReadoutValue(sublabel: "CONTRAST", value: .number(t.materialContrast, .decimals(2), .measured, device: t.device)),
                    ], note: .words("pass: the step under the material is still there, spread wider than the bare step, and differs from it")))
                }
                Button { Task { await service.runCaptureTest() } } label: {
                    Label("Run the capture test", systemImage: "camera.metering.matrix")
                        .frame(maxWidth: .infinity, minHeight: InstrumentMetrics.controlTarget)
                }
                .buttonStyle(.glass)
                .tint(InstrumentPalette.actionCyan)
                .disabled(service.isBusy)
            }
        }
    }
}

struct CalibrationInsideApplePanel: View {
    let subject: CalibrationSubject
    @Environment(\.colorSchemeContrast) private var contrast

    private var lines: (mechanism: BadgedLine, provenance: BadgedLine)? {
        let names = BadgedLine([.text("NAMES FROM"), .literal("iOS 26.5"), .text("SIMULATOR /"), .literal("macOS 27.2"),
                                .text("· NOT RE-READ FOR"), .literal("iOS 27"), .text("· NOT OBSERVED RUNNING")])
        switch subject {
        case .swiftUIBlur:
            return (BadgedLine([.literal("CAFilter gaussianBlur"), .text("→ render server; above the switch a cheaper separable blur on a resampled image")]), names)
        case .swiftUIShadow, .caLayerShadow:
            return (BadgedLine([.text("shadow rasterised by Core Animation → render server; offscreen it is the software path")]), names)
        default:
            return nil
        }
    }

    var body: some View {
        if let lines {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    CalibrationEyebrow(text: "INSIDE APPLE")
                    Spacer()
                    HonestyBadge(.inferred)
                }
                CalibrationLineText(line: lines.mechanism, font: .footnote, ink: InstrumentPalette.displayInk)
                CalibrationLineText(line: lines.provenance, font: .caption2)
            }
            .padding(InstrumentMetrics.panelInset)
            .background(InstrumentPalette.content.opacity(CalibrationLayout.panelFill), in: .rect(cornerRadius: InstrumentMetrics.panelRadius))
            .overlay {
                RoundedRectangle(cornerRadius: InstrumentMetrics.panelRadius)
                    .stroke(InstrumentPalette.spectrumDepth.opacity(contrast == .increased ? 0.8 : 0.5),
                            style: StrokeStyle(lineWidth: contrast == .increased ? 1 : 0.8, dash: [5, 4]))
                    .allowsHitTesting(false)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
