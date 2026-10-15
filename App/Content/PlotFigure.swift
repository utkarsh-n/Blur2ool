import SwiftUI
import Charts
import Accessibility
import BlurCore

// OWNER: CONTENT-VIEWS. A PlotSpec in Swift Charts (SPEC §4.3, §14; METRO §C.8): stems with explicit widths (2 pt, thinner
// only when they would touch; relative-width marks on a numeric axis render invisible, METRO §F.4 item 1), a signed zero
// line, negative lobes shaded AND dashed in spectrum depth below the zero line (SPEC §4.1.3; colour never alone), quiet
// reference traces, compare series B dashed / C dotted / D dash-dot, measured points (filled for this phone, hollow for a
// reference device), markers (−3 dB carrier tick, the regime switch hollow while INFERRED and filled when MEASURED), axes
// with units and "normalized", tick labels formatted by BlurCore's NumberStyle, and an AXChartDescriptor with the same
// numbers (which also gives iOS Audio Graphs).

struct PlotFigure: View {
    let plot: PlotSpec
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        let model = PlotModel(plot, accessibilityLayout: size.isAccessibilitySize)
        VStack(alignment: .leading, spacing: 3) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: ContentSpacing.group) {
                    yTitle.fixedSize()
                    Spacer(minLength: ContentSpacing.inline)
                    ForEach(model.provenances, id: \.self) { HonestyBadge($0).fixedSize() }
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) { ForEach(model.provenances, id: \.self) { HonestyBadge($0).fixedSize() } }
                    yTitle.fixedSize(horizontal: false, vertical: true)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
            chart(model)
                .frame(minHeight: size.isAccessibilitySize ? 220 : 110, maxHeight: .infinity)
            // The x-axis title is never truncated (it carries the unit): beside the legend when both fit, above it otherwise.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: ContentSpacing.group) {
                    if showsLegend(model) { PlotLegend(entries: model.legend).fixedSize() }
                    Spacer(minLength: ContentSpacing.inline)
                    xTitle.fixedSize()
                }
                VStack(alignment: .trailing, spacing: 2) {
                    xTitle.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .trailing)
                    if showsLegend(model) || !model.labelsMarkers {
                        PlotLegend(entries: model.legend + (model.labelsMarkers ? [] : model.markerLegend)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentPlotInset()
    }

    private var yTitle: some View {
        Text("↑ " + ContentLogic.axisTitle(plot.yAxis)).contentFont(.engraving).foregroundStyle(ContentInk.secondary)
    }

    private var xTitle: some View {
        Text(ContentLogic.axisTitle(plot.xAxis) + " →").contentFont(.engraving).foregroundStyle(ContentInk.secondary)
    }

    private func showsLegend(_ m: PlotModel) -> Bool {
        m.legend.count > 1 || plot.series.contains { $0.provenance == .measured }
    }

    private func chart(_ m: PlotModel) -> some View {
        Chart {
            if m.showsZero {
                RuleMark(y: .value("zero", 0))
                    .lineStyle(StrokeStyle(lineWidth: 0.75))
                    .foregroundStyle(Color.white.opacity(0.42))
            }
            ForEach(m.areas) { p in
                AreaMark(x: .value("x", p.x), yStart: .value("zero", 0), yEnd: .value("y", p.y), series: .value("run", p.series))
                    .foregroundStyle(ContentInk.negative.opacity(0.22))
                    .interpolationMethod(.linear)
            }
            ForEach(m.lines) { p in
                LineMark(x: .value("x", p.x), y: .value("y", p.y), series: .value("run", p.series))
                    .lineStyle(p.stroke)
                    .foregroundStyle(p.ink)
                    .interpolationMethod(.linear)
            }
            ForEach(m.stems) { s in
                RuleMark(x: .value("x", s.x), yStart: .value("zero", 0), yEnd: .value("y", s.y))
                    .lineStyle(StrokeStyle(lineWidth: m.stemWidth, lineCap: .butt, dash: s.y < 0 ? [2, 1.5] : []))
                    .foregroundStyle(s.y < 0 ? ContentInk.negative : s.ink)
            }
            ForEach(m.tips) { s in
                PointMark(x: .value("x", s.x), y: .value("y", s.y))
                    .symbolSize(m.tipArea)
                    .foregroundStyle(s.y < 0 ? ContentInk.negative : s.ink)
            }
            ForEach(m.points) { p in
                PointMark(x: .value("x", p.x), y: .value("y", p.y))
                    .symbol { PlotPointSymbol(filled: p.filled, ink: p.ink) }
            }
            ForEach(m.markers) { mk in
                if m.labelsMarkers {
                    RuleMark(x: .value("marker", mk.x), yStart: .value("y", m.yRange.lowerBound), yEnd: .value("y", m.dataTop))
                        .lineStyle(StrokeStyle(lineWidth: mk.kind == .probe ? 1 : 0.75, dash: mk.kind == .probe ? [] : [3, 2.5]))
                        .foregroundStyle(mk.ink.opacity(0.85))
                        .annotation(position: .top, alignment: .leading, spacing: 1 + CGFloat(mk.row) * PlotModel.markerRowHeight,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            PlotMarkerLabel(marker: mk)
                        }
                } else {
                    // Accessibility sizes: the rule stays, its label moves to the legend under the plot.
                    RuleMark(x: .value("marker", mk.x), yStart: .value("y", m.yRange.lowerBound), yEnd: .value("y", m.dataTop))
                        .lineStyle(StrokeStyle(lineWidth: mk.kind == .probe ? 1 : 0.75, dash: mk.kind == .probe ? [] : [3, 2.5]))
                        .foregroundStyle(mk.ink.opacity(0.85))
                }
            }
        }
        .chartXScale(domain: m.xRange, type: m.xLog ? .log : .linear)
        .chartYScale(domain: m.yRange, type: m.yLog ? .log : .linear)
        .chartXAxis {
            AxisMarks(values: m.xTicks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(ContentInk.grid)
                AxisTick(length: 3, stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(ContentInk.hairline)
                // The end ticks anchor inward so their labels are never pushed off the plot.
                AxisValueLabel(anchor: PlotModel.xLabelAnchor(value.as(Double.self), m.xTicks)) {
                    if let v = value.as(Double.self) {
                        Text(m.xStyle.text(v)).contentFont(.tick).foregroundStyle(ContentInk.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: m.yTicks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(ContentInk.grid)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(m.yStyle.text(v)).contentFont(.tick).foregroundStyle(ContentInk.secondary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .accessibilityChartDescriptor(PlotChartDescriptor(plot: plot))
        .accessibilityLabel(plot.accessibilitySummary)
    }
}

// MARK: - Model (everything the chart draws, precomputed from the PlotSpec)

struct PlotModel {
    struct LinePoint: Identifiable { let id: Int; let x: Double; let y: Double; let series: String; let ink: Color; let stroke: StrokeStyle }
    struct AreaPoint: Identifiable { let id: Int; let x: Double; let y: Double; let series: String }
    struct Stem: Identifiable { let id: Int; let x: Double; let y: Double; let ink: Color }
    struct Point: Identifiable { let id: Int; let x: Double; let y: Double; let ink: Color; let filled: Bool }
    struct Marker: Identifiable { let id: Int; let x: Double; let label: String; let kind: MarkerKind; let ink: Color; let hollow: Bool; let row: Int }
    struct LegendEntry: Hashable { let name: String; let ink: Color; let dash: [CGFloat]; let width: CGFloat; let isStems: Bool }

    /// Marker names as legend entries (dashed rules), used when the labels cannot sit on the plot.
    var markerLegend: [LegendEntry] {
        markers.map { LegendEntry(name: $0.label, ink: $0.ink, dash: $0.kind == .probe ? [] : [3, 2.5], width: 0.9, isStems: false) }
    }

    var lines: [LinePoint] = []
    var areas: [AreaPoint] = []
    var stems: [Stem] = []
    var tips: [Stem] = []
    var points: [Point] = []
    var markers: [Marker] = []
    var legend: [LegendEntry] = []
    var provenances: [Provenance] = []
    let xRange: ClosedRange<Double>
    /// The y domain: the data range plus headroom for marker labels (labels sit inside the plot, above the data).
    var yRange: ClosedRange<Double>
    /// The top of the data range (marker rules end here; their labels sit above it).
    var dataTop: Double
    let xLog: Bool
    let yLog: Bool
    let xTicks: [Double]
    let yTicks: [Double]
    let xStyle: NumberStyle
    let yStyle: NumberStyle
    let showsZero: Bool
    var stemWidth: CGFloat = 2
    var tipArea: CGFloat = 9
    var markerRows = 0
    /// False at accessibility sizes: marker labels at full size would cover the data, so they join the legend instead.
    var labelsMarkers = true
    static let markerRowHeight: CGFloat = 14

    init(_ plot: PlotSpec, plotWidth: Double = 330, accessibilityLayout: Bool = false) {
        labelsMarkers = !accessibilityLayout
        xLog = plot.xAxis.logarithmic
        yLog = plot.yAxis.logarithmic
        let negative = ContentLogic.hasNegative(plot)
        let hasStems = plot.series.contains { $0.style == .stems }
        showsZero = !yLog && (plot.showsZeroLine || negative)
        let allX = plot.series.flatMap(\.xs) + plot.markers.map(\.x)
        let allY = plot.series.flatMap(\.ys)
        xRange = ContentLogic.extent(allX, declared: plot.xAxis.range, includeZero: false, logarithmic: xLog)
        var yr = ContentLogic.extent(allY, declared: plot.yAxis.range, includeZero: showsZero || hasStems, logarithmic: yLog)
        if plot.yAxis.range == nil && !yLog {
            let span = yr.upperBound - yr.lowerBound
            yr = (yr.lowerBound < 0 ? yr.lowerBound - span * 0.06 : yr.lowerBound)...(yr.upperBound + span * 0.08)
        }
        yRange = yr
        dataTop = yr.upperBound
        let xs = xLog ? ContentLogic.logTicks(xRange) : ContentLogic.niceTicks(xRange, count: 5)
        // Accessibility sizes keep tick labels at full size and print fewer of them: the ends (and zero).
        xTicks = accessibilityLayout && xs.count > 2 ? [xs[0], xs[xs.count - 1]] : xs
        let ys = yLog ? ContentLogic.logTicks(yRange) : ContentLogic.niceTicks(yRange, count: 4)
        // More than five decades on a short axis: label every other one.
        if accessibilityLayout && ys.count > 2 {
            yTicks = Array(Set([ys[0], ys[ys.count - 1]] + (ys.contains(0) ? [0] : []))).sorted()
        } else {
            yTicks = yLog && ys.count > 5 ? ys.enumerated().filter { $0.offset % 2 == 0 }.map(\.element) : ys
        }
        xStyle = ContentLogic.tickStyle(xTicks, logarithmic: xLog)
        yStyle = ContentLogic.tickStyle(yTicks, logarithmic: yLog)

        var lineID = 0, stemID = 0, pointID = 0
        let stemCount = plot.series.filter { $0.style == .stems }.map(\.xs.count).max() ?? 0
        stemWidth = CGFloat(ContentLogic.stemWidth(count: stemCount, plotWidth: plotWidth))
        tipArea = Swift.max(4, pow(stemWidth * 1.9, 2))
        var seen = Set<Provenance>()
        for (sIndex, s) in plot.series.enumerated() {
            if seen.insert(s.provenance).inserted { provenances.append(s.provenance) }
            let ink = PlotModel.ink(s.role)
            let base = PlotModel.dash(s.style)
            let width = PlotModel.width(s.role)
            legend.append(LegendEntry(name: s.name, ink: ink, dash: base, width: width, isStems: s.style == .stems))
            let pts = zip(s.xs, s.ys).filter { (!xLog || $0.0 > 0) && (!yLog || $0.1 > 0) && $0.0.isFinite && $0.1.isFinite }
            switch s.style {
            case .stems:
                for (x, y) in pts {
                    stems.append(Stem(id: stemID, x: x, y: y, ink: ink))
                    if s.role == .primary || s.role == .measured { tips.append(Stem(id: stemID, x: x, y: y, ink: ink)) }
                    stemID += 1
                }
            case .points:
                for (x, y) in pts { points.append(Point(id: pointID, x: x, y: y, ink: ink, filled: s.role == .measured)); pointID += 1 }
            default:
                let runs = yLog ? [ContentLogic.SignedRun(negative: false, xs: pts.map(\.0), ys: pts.map(\.1))]
                    : ContentLogic.signedRuns(xs: pts.map(\.0), ys: pts.map(\.1))
                for (rIndex, run) in runs.enumerated() {
                    let key = "\(sIndex)-\(rIndex)"
                    let runInk = run.negative && s.role != .reference ? ContentInk.negative : ink
                    let dash: [CGFloat] = run.negative ? (base.isEmpty ? [3.5, 2.5] : base) : base
                    let stroke = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash)
                    for (x, y) in zip(run.xs, run.ys) {
                        lines.append(LinePoint(id: lineID, x: x, y: y, series: key, ink: runInk, stroke: stroke)); lineID += 1
                        if run.negative && (s.role == .primary || s.role == .depth) {
                            areas.append(AreaPoint(id: lineID, x: x, y: y, series: key))
                        }
                    }
                }
                if s.provenance == .measured && pts.count <= 24 {
                    for (x, y) in pts { points.append(Point(id: pointID, x: x, y: y, ink: ink, filled: s.role == .measured)); pointID += 1 }
                }
            }
        }
        // Marker labels sit in rows above the plot area; a label that would collide with the previous one in its row moves
        // up a row (labels never overlap each other or the axis title).
        var rowEnds: [Double] = []
        let span = xLog ? log10(xRange.upperBound) - log10(xRange.lowerBound) : xRange.upperBound - xRange.lowerBound
        func position(_ x: Double) -> Double { (xLog ? log10(Swift.max(x, 1e-300)) - log10(xRange.lowerBound) : x - xRange.lowerBound) / Swift.max(span, 1e-300) }
        for (i, m) in plot.markers.enumerated().sorted(by: { $0.element.x < $1.element.x }) where !xLog || m.x > 0 {
            let ink: Color = switch m.kind {
            case .minus3dB: ContentInk.marker
            case .probe, .regimeSwitch: ContentInk.probe
            default: ContentInk.secondary
            }
            let start = position(m.x)
            let width = (Double(m.label.count) * 6.8 + (m.kind == .regimeSwitch ? 22 : 10)) / plotWidth
            let row = rowEnds.firstIndex { $0 < start } ?? rowEnds.count
            if row == rowEnds.count { rowEnds.append(start + width) } else { rowEnds[row] = start + width }
            markers.append(Marker(id: i, x: m.x, label: m.label, kind: m.kind, ink: ink, hollow: m.provenance != .measured, row: row))
        }
        markerRows = labelsMarkers ? rowEnds.count : 0
        // Headroom for the marker label rows, about 14 pt each on a plot area of about 110 pt.
        if markerRows > 0 {
            let share = 0.2 * Double(markerRows)
            if yLog {
                let decades = log10(yRange.upperBound) - log10(yRange.lowerBound)
                yRange = yRange.lowerBound...(yRange.upperBound * pow(10, decades * share))
            } else {
                yRange = yRange.lowerBound...(yRange.upperBound + (yRange.upperBound - yRange.lowerBound) * share)
            }
        }
    }

    static func xLabelAnchor(_ v: Double?, _ ticks: [Double]) -> UnitPoint {
        guard let v, ticks.count > 1 else { return .top }
        if v == ticks.first { return .topLeading }
        if v == ticks.last { return .topTrailing }
        return .top
    }

    static func ink(_ role: SeriesRole) -> Color {
        switch role {
        case .primary: ContentInk.primary
        case .reference: ContentInk.quiet
        case .depth: ContentInk.depth
        case .comparisonB: ContentInk.comparisonB
        case .comparisonC: ContentInk.comparisonC
        case .comparisonD: ContentInk.comparisonD
        case .measured: ContentInk.measured
        }
    }
    static func dash(_ style: SeriesStyle) -> [CGFloat] {
        switch style {
        case .solid, .stems, .points: []
        case .dashed: [5, 3]
        case .dotted: [1, 2.5]
        case .dashDot: [6, 2, 1, 2]
        case .quiet: []
        }
    }
    static func width(_ role: SeriesRole) -> CGFloat {
        switch role {
        case .primary: 1.7
        case .reference: 1
        case .depth: 1.4
        default: 1.4
        }
    }
}

/// A measured point: filled for this phone, hollow for a reference device (SPEC §4.8 sweep plot).
struct PlotPointSymbol: View {
    let filled: Bool
    let ink: Color
    var body: some View {
        ZStack {
            if filled { Circle().fill(ink) } else { Circle().fill(InstrumentPalette.plot); Circle().strokeBorder(ink, lineWidth: 1.2) }
        }
        .frame(width: 7, height: 7)
    }
}

/// A marker's engraved label; the regime switch carries a diamond, hollow while INFERRED, filled once MEASURED.
struct PlotMarkerLabel: View {
    let marker: PlotModel.Marker
    var body: some View {
        HStack(spacing: 3) {
            if marker.kind == .regimeSwitch {
                Image(systemName: marker.hollow ? "diamond" : "diamond.fill")
                    .font(.system(size: 8, weight: .semibold))
            }
            Text(marker.label).contentFont(.tick)
        }
        .foregroundStyle(marker.ink)
        .padding(.horizontal, 3)
        .background(InstrumentPalette.plot.opacity(0.85), in: .rect(cornerRadius: 3))
    }
}

/// The legend: each series' stroke pattern drawn (dash, dots, stems), never colour alone.
struct PlotLegend: View {
    let entries: [PlotModel.LegendEntry]
    var body: some View {
        ContentFlowLayout(spacing: 10, lineSpacing: 2) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                HStack(spacing: 4) {
                    Canvas { context, size in
                        let mid = size.height / 2
                        if e.isStems {
                            for i in 0..<4 {
                                let x = 2 + CGFloat(i) * 4.5
                                var p = Path(); p.move(to: CGPoint(x: x, y: size.height - 1)); p.addLine(to: CGPoint(x: x, y: 2 + CGFloat(i % 2) * 3))
                                context.stroke(p, with: .color(e.ink), lineWidth: 1.6)
                            }
                        } else {
                            var p = Path(); p.move(to: CGPoint(x: 0, y: mid)); p.addLine(to: CGPoint(x: size.width, y: mid))
                            context.stroke(p, with: .color(e.ink), style: StrokeStyle(lineWidth: e.width + 0.3, lineCap: .round, dash: e.dash))
                        }
                    }
                    .frame(width: 18, height: 9)
                    Text(e.name).contentFont(.engraving).foregroundStyle(ContentInk.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - AXChartDescriptor (SPEC §14: every plot; also gives Audio Graphs)

struct PlotChartDescriptor: AXChartDescriptorRepresentable {
    let plot: PlotSpec

    func makeChartDescriptor() -> AXChartDescriptor {
        let model = PlotModel(plot)
        let xStyle = ContentLogic.valueStyle(plot.series.flatMap(\.xs), unit: plot.xAxis.unit)
        let yStyle = ContentLogic.valueStyle(plot.series.flatMap(\.ys), unit: plot.yAxis.unit)
        let xAxis = AXNumericDataAxisDescriptor(title: ContentLogic.spokenAxisTitle(plot.xAxis), range: model.xRange,
                                                gridlinePositions: model.xTicks) { value in xStyle.spoken(value) }
        let yAxis = AXNumericDataAxisDescriptor(title: ContentLogic.spokenAxisTitle(plot.yAxis), range: model.yRange,
                                                gridlinePositions: model.yTicks) { value in yStyle.spoken(value) }
        let series = plot.series.map { s in
            AXDataSeriesDescriptor(name: "\(s.name), \(s.provenance.spokenPhrase(device: nil))",
                                   isContinuous: s.style != .stems && s.style != .points,
                                   dataPoints: zip(s.xs, s.ys).map { AXDataPoint(x: $0, y: $1) })
        }
        return AXChartDescriptor(title: "\(ContentLogic.spokenAxisTitle(plot.yAxis)) against \(ContentLogic.spokenAxisTitle(plot.xAxis))",
                                 summary: plot.accessibilitySummary, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: series)
    }
}
