import SwiftUI
import Accessibility
import BlurCore

// OWNER: METRO-COMPONENTS (frozen initialiser, ARCHITECTURE §5.14; Metro §11; METRO §C.5; SPEC §4.1.3 "Pills", §12.2 item 4,
// §14 "Plots", §17 item 3). A vertical signal pill ported from Metro Station `MetroStationPillView.swift`:
//   • Static enclosure: pillLight → pillDark capsule, 0.8-pt outline whose gradient runs family primary 0.36 (0.70 under
//     Increased Contrast) → white 0.10 → family secondary 0.38. The outline, the title row and the axis rows NEVER
//     animate (Metro contract A.5); only the interior changes.
//   • Interior: Metro's calibration (five hairlines and a spine), a quiet reference trace, the primary trace, the depth
//     trace, comparison traces and markers. On an accepted change the interior eases from the old shape to the new one in
//     ≤ 150 ms (a geometric blend when the two share their sample grid, a cross-fade otherwise); Reduce Motion snaps.
//   • KERNEL (wave family) runs DOWNWARD from −extent (top) to +extent (bottom); taps are horizontal stems from the zero
//     spine. FREQ (spectrum family) runs UPWARD from DC (bottom) to Nyquist (top) and plots the SIGNED H(ν): a hairline
//     marks zero, and negative lobes are shaded spectrum secondary AND dashed (colour never alone, SPEC §14). A −3 dB
//     marker is a dashed carrier line with a dot (Metro's carrier marker).
//   • Comparisons: B dashed, C dotted, D dash-dot, in display ink (pattern + colour differ from A).
//   • An engraving lane on the trailing edge carries the provenance WORD (glyph + word, dashed outline for INFERRED;
//     SPEC §12.2 item 4: never glyph-only outside rail chips) and, when the title is longer than six characters
//     (`LOCAL @ PROBE`, `T(ν, A 0.20)`), the full title, both reading bottom-to-top. The title row then shows the family
//     name. With no honest plot the pill engraves `emptyText` (`N/A · RANK`, `INFERRED — NOT EXPOSED`): never blank.
//   • VoiceOver: one element whose value states the axes, directions, normalization, the summary, markers, comparisons
//     and the provenance; plus an AXChartDescriptor (Audio Graphs).
public enum PillFamily: Sendable { case wave, spectrum }

public struct InstrumentSignalPill: View {
    private let content: PillPlot
    private let family: PillFamily
    private let comparisons: [PillPlot]
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption2) private var titleSize = InstrumentTypeScale.pillTitle
    @ScaledMetric(relativeTo: .caption2) private var axisSize = InstrumentTypeScale.pillAxis
    @ScaledMetric(relativeTo: .caption2) private var titleHeight = InstrumentMetrics.captionRowHeight
    @State private var previous: PillScene?
    @State private var progress: Double = 1
    @State private var easing: Task<Void, Never>?

    public init(_ content: PillPlot, family: PillFamily, comparisons: [PillPlot] = []) {
        self.content = content; self.family = family; self.comparisons = comparisons
    }

    private var scene: PillScene { PillScene(content: content, comparisons: comparisons) }
    private var primaryInk: Color { family == .wave ? InstrumentPalette.wave : InstrumentPalette.spectrum }
    private var secondaryInk: Color { family == .wave ? InstrumentPalette.waveDepth : InstrumentPalette.spectrumDepth }
    /// Pill text scales with Dynamic Type up to these caps: a 36-pt channel cannot hold larger type (Metro §17: decorative
    /// metadata goes before essential values; the full content is in the VoiceOver value).
    private var title: CGFloat { Swift.min(titleSize, 13) }
    private var axis: CGFloat { Swift.min(axisSize, 11) }

    nonisolated public static func familyTitle(_ family: PillFamily) -> String { family == .wave ? "KERNEL" : "FREQ" }
    /// Titles longer than six characters move into the engraving lane; the title row shows the family name.
    nonisolated public static func titleRow(_ title: String, family: PillFamily) -> String { title.count <= 6 ? title : familyTitle(family) }

    public var body: some View {
        let axes = PillAxisLabels(plot: content.plot, family: family)
        VStack(spacing: InstrumentMetrics.pillInternalGap) {
            Text(InstrumentSignalPill.titleRow(content.title, family: family))
                .font(.system(size: title, weight: .semibold, design: .monospaced))
                .foregroundStyle(primaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: Swift.min(titleHeight, 17))
                .padding(.horizontal, 2)
            axisText(axes.upper)
            PillInterior(from: previous, to: scene, progress: progress, family: family, axisFont: axis,
                         contrast: contrast == .increased)
                .padding(.horizontal, 2.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            axisText(axes.lower)
        }
        .padding(.vertical, InstrumentMetrics.pillVerticalPadding)
        .frame(minWidth: 28, idealWidth: InstrumentMetrics.pillWidthRegular, maxWidth: 42,
               minHeight: 140, idealHeight: InstrumentMetrics.pillHeightMax, maxHeight: InstrumentMetrics.pillHeightMax)
        .background {
            Capsule().fill(LinearGradient(colors: [InstrumentPalette.pillLight, InstrumentPalette.pillDark],
                                          startPoint: .leading, endPoint: .trailing))
        }
        .overlay {
            Capsule().strokeBorder(LinearGradient(colors: [
                primaryInk.opacity(contrast == .increased ? InstrumentOpacity.pillPrimaryBorderIncreasedContrast
                                                          : InstrumentOpacity.pillPrimaryBorder),
                .white.opacity(InstrumentOpacity.pillWhiteBorder),
                secondaryInk.opacity(InstrumentOpacity.pillSecondaryBorder)
            ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: InstrumentMetrics.pillStroke)
            .allowsHitTesting(false)
        }
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(InstrumentSignalPill.spokenLabel(content, family: family))
        .accessibilityValue(InstrumentSignalPill.spokenValue(content, family: family, comparisons: comparisons))
        .accessibilityChartDescriptor(PillChartDescriptor(content: content, family: family, comparisons: comparisons))
        .accessibilityIdentifier("signalPill.\(InstrumentSignalPill.familyTitle(family))")
        .onChange(of: scene) { old, _ in ease(from: old) }
    }

    private func axisText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: axis, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(InstrumentOpacity.axisInk))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(height: axis + 2)
            .padding(.horizontal, InstrumentMetrics.pillHorizontalPadding)
    }

    /// Interior easing (≤ 150 ms): show the old scene, then animate `progress` 0 → 1 on the next turn of the run loop.
    private func ease(from old: PillScene) {
        easing?.cancel()
        guard !reduceMotion else { previous = nil; progress = 1; return }
        previous = old
        progress = 0
        easing = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: InstrumentMotion.pillInteriorEase)) { progress = 1 }
        }
    }

    // MARK: Spoken forms

    nonisolated public static func spokenLabel(_ content: PillPlot, family: PillFamily) -> String {
        let base = family == .wave ? "Kernel pill" : "Frequency response pill"
        let title = content.title.trimmingCharacters(in: .whitespaces)
        return title.uppercased() == familyTitle(family) ? base : base + ", " + title.lowercased()
    }

    nonisolated public static func spokenValue(_ content: PillPlot, family: PillFamily, comparisons: [PillPlot] = []) -> String {
        var parts: [String] = []
        if let plot = content.plot {
            parts.append(plot.accessibilitySummary)
            let range = PillGeometry.xRange(plot, comparisons: comparisons.compactMap(\.plot))
            let unit = plot.xAxis.unit.map { PillAxisLabels.spokenUnit($0) }.map { " " + $0 } ?? ""
            let lo = NumberStyle.significant(2).spoken(range.lowerBound), hi = NumberStyle.significant(2).spoken(range.upperBound)
            let y = plot.yAxis.label + (plot.yAxis.normalized ? ", normalized," : "")
            if family == .wave {
                parts.append("\(plot.xAxis.label.capitalized) runs downward from \(lo) to \(hi)\(unit); \(y) runs to the right")
            } else {
                parts.append("\(plot.xAxis.label.capitalized) runs upward from \(lo) to \(hi)\(unit); signed \(y) runs to the right of a zero line; values below zero are shaded and dashed")
            }
            for marker in plot.markers {
                parts.append("\(marker.label) at \(NumberStyle.significant(2).spoken(marker.x))\(unit)")
            }
            for (index, comparison) in comparisons.enumerated() where comparison.plot != nil {
                let pattern = ["dashed", "dotted", "dash-dot"][Swift.min(index, 2)]
                parts.append("\(["B", "C", "D"][Swift.min(index, 2)]), \(pattern): \(comparison.title.lowercased())")
            }
        } else if let empty = content.emptyText {
            parts.append(empty.lowercased())
        }
        if let badge = content.badge, let provenance = badge.provenance {
            parts.append(HonestyBadge.spokenLabel(provenance, qualifiers: badge.qualifiers))
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Scene (what the interior draws) and its blend

struct PillScene: Equatable {
    var plot: PlotSpec?
    var emptyText: String?
    var title: String
    var badge: BadgedValue?
    var comparisons: [PlotSpec]

    init(content: PillPlot, comparisons: [PillPlot]) {
        plot = content.plot; emptyText = content.emptyText; title = content.title; badge = content.badge
        self.comparisons = comparisons.compactMap(\.plot)
    }

    /// A geometric blend of two scenes that share their sample grid (same series, roles, styles and xs), else nil
    /// (the interior then cross-fades).
    static func blend(_ a: PillScene, _ b: PillScene, t: Double) -> PillScene? {
        guard let pa = a.plot, let pb = b.plot, pa.series.count == pb.series.count,
              a.comparisons.count == b.comparisons.count else { return nil }
        func mix(_ x: PlotSeries, _ y: PlotSeries) -> PlotSeries? {
            guard x.role == y.role, x.style == y.style, x.xs == y.xs else { return nil }
            return PlotSeries(name: y.name, xs: y.xs, ys: zip(x.ys, y.ys).map { $0 + ($1 - $0) * t }, style: y.style,
                              role: y.role, provenance: y.provenance)
        }
        var series: [PlotSeries] = []
        for (x, y) in zip(pa.series, pb.series) { guard let s = mix(x, y) else { return nil }; series.append(s) }
        var comparisons: [PlotSpec] = []
        for (ca, cb) in zip(a.comparisons, b.comparisons) {
            guard ca.series.count == cb.series.count else { return nil }
            var mixed: [PlotSeries] = []
            for (x, y) in zip(ca.series, cb.series) { guard let s = mix(x, y) else { return nil }; mixed.append(s) }
            var c = cb; c.series = mixed; comparisons.append(c)
        }
        var markers = pb.markers
        if pa.markers.count == pb.markers.count {
            markers = zip(pa.markers, pb.markers).map { m, n in
                var o = n; if m.kind == n.kind { o.x = m.x + (n.x - m.x) * t }; return o
            }
        }
        var out = b
        var plot = pb; plot.series = series; plot.markers = markers
        if let ra = pa.yAxis.range, let rb = pb.yAxis.range {
            plot.yAxis.range = (ra.lowerBound + (rb.lowerBound - ra.lowerBound) * t)...(ra.upperBound + (rb.upperBound - ra.upperBound) * t)
        }
        out.plot = plot
        out.comparisons = comparisons
        return out
    }
}

/// The axis endpoint engravings: KERNEL −extent (top) / +extent (bottom); FREQ Nyquist (top) / DC (bottom).
struct PillAxisLabels {
    var upper: String
    var lower: String
    init(plot: PlotSpec?, family: PillFamily) {
        guard let plot else { upper = " "; lower = " "; return }
        let range = PillGeometry.xRange(plot, comparisons: [])
        let unit = plot.xAxis.unit ?? ""
        func label(_ v: Double, signed: Bool) -> String {
            if unit == "c/px" && abs(v) < 1e-12 { return "DC" }
            if unit == "c/px" && abs(v - 0.5) < 1e-9 { return "NYQ" }
            let integral = abs(v - v.rounded()) < 1e-9
            var style = integral ? NumberStyle.integer() : NumberStyle.significant(2)
            style.explicitPlus = signed
            style.grouping = false
            return style.text(v)
        }
        if family == .wave {
            upper = label(range.lowerBound, signed: true); lower = label(range.upperBound, signed: true)
        } else {
            upper = label(range.upperBound, signed: false); lower = label(range.lowerBound, signed: false)
        }
    }
    static func spokenUnit(_ unit: String) -> String {
        switch unit {
        case "px": "pixels"
        case "c/px": "cycles per pixel"
        case "pt": "points"
        case "°": "degrees"
        default: unit
        }
    }
}

/// Value and position mapping shared by the drawing, the axis labels, the spoken value and the chart descriptor.
enum PillGeometry {
    static func xRange(_ plot: PlotSpec, comparisons: [PlotSpec]) -> ClosedRange<Double> {
        if let r = plot.xAxis.range, r.upperBound > r.lowerBound { return r }
        let xs = (plot.series + comparisons.flatMap(\.series)).flatMap(\.xs)
        guard let lo = xs.min(), let hi = xs.max(), hi > lo else { return -0.5...0.5 }
        return lo...hi
    }
    static func yRange(_ plot: PlotSpec, comparisons: [PlotSpec]) -> ClosedRange<Double> {
        if let r = plot.yAxis.range, r.upperBound > r.lowerBound { return r }
        let ys = (plot.series + comparisons.flatMap(\.series)).flatMap(\.ys).filter(\.isFinite)
        let lo = Swift.min(0, ys.min() ?? 0)
        let hi = Swift.max(ys.max() ?? 1, lo + 1e-9)
        return lo...hi
    }
}

// MARK: - Interior (Canvas; Animatable so only the interior eases)

private struct PillInterior: View, Animatable {
    var from: PillScene?
    var to: PillScene
    var progress: Double
    let family: PillFamily
    let axisFont: CGFloat
    let contrast: Bool

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private var ink: Color { family == .wave ? InstrumentPalette.wave : InstrumentPalette.spectrum }
    private var depthInk: Color { family == .wave ? InstrumentPalette.waveDepth : InstrumentPalette.spectrumDepth }
    private var laneWidth: CGFloat { axisFont + 2 }

    var body: some View {
        Canvas { context, size in
            let plotRect = CGRect(x: 0, y: 1, width: Swift.max(1, size.width - laneWidth - 1), height: Swift.max(1, size.height - 2))
            let lane = CGRect(x: plotRect.maxX + 1, y: 0, width: laneWidth, height: size.height)
            drawCalibration(&context, plotRect, scene: to)
            if let from, progress < 1 {
                if let blended = PillScene.blend(from, to, t: progress) {
                    drawScene(&context, plotRect, scene: blended)
                } else {
                    var old = context; old.opacity = 1 - progress
                    drawScene(&old, plotRect, scene: from)
                    var new = context; new.opacity = progress
                    drawScene(&new, plotRect, scene: to)
                }
            } else {
                drawScene(&context, plotRect, scene: to)
            }
            drawLane(&context, lane, scene: to)
        }
        .accessibilityHidden(true)
    }

    // Metro calibration: five hairlines (ends 0.17, inside 0.07) and the spine in the family ink.
    private func drawCalibration(_ context: inout GraphicsContext, _ rect: CGRect, scene: PillScene) {
        for index in 0...4 {
            let y = rect.minY + rect.height * Double(index) / 4
            var tick = Path()
            tick.move(to: CGPoint(x: rect.minX, y: y))
            tick.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.stroke(tick, with: .color(.white.opacity(index == 0 || index == 4 ? 0.17 : 0.07)), lineWidth: 0.5)
        }
    }

    private func drawScene(_ context: inout GraphicsContext, _ rect: CGRect, scene: PillScene) {
        guard let plot = scene.plot else {
            drawEmpty(&context, rect, text: scene.emptyText ?? "—")
            return
        }
        let xr = PillGeometry.xRange(plot, comparisons: scene.comparisons)
        let yr = PillGeometry.yRange(plot, comparisons: scene.comparisons)
        let left = rect.minX + 1, width = Swift.max(1, rect.width - 2)
        func vx(_ v: Double) -> CGFloat { left + CGFloat((v - yr.lowerBound) / (yr.upperBound - yr.lowerBound)) * width }
        func py(_ x: Double) -> CGFloat {
            let t = CGFloat((x - xr.lowerBound) / (xr.upperBound - xr.lowerBound))
            return family == .wave ? rect.minY + t * rect.height : rect.maxY - t * rect.height
        }
        let zeroX = vx(0)

        // Spine (Metro) and, for signed responses, the zero hairline (SPEC §4.1.3).
        var spine = Path()
        spine.move(to: CGPoint(x: zeroX, y: rect.minY)); spine.addLine(to: CGPoint(x: zeroX, y: rect.maxY))
        context.stroke(spine, with: .color(plot.showsZeroLine ? .white.opacity(0.38) : ink.opacity(0.22)),
                       lineWidth: plot.showsZeroLine ? 0.5 : 0.6)

        let ordered = plot.series.sorted { order($0.role) < order($1.role) }
        for series in ordered where series.role == .reference || series.role == .depth {
            stroke(&context, polyline(series, vx, py), series.role == .depth ? depthInk : ink.opacity(0.42),
                   width: series.role == .depth ? 1 : 0.8, dash: dash(for: series.style))
        }
        let patterns: [[CGFloat]] = [[3, 2], [0.8, 2], [4, 2, 0.8, 2]]
        for (index, comparison) in scene.comparisons.enumerated() {
            for series in comparison.series where series.role == .primary {
                stroke(&context, polyline(series, vx, py), InstrumentPalette.displayInk.opacity(0.75), width: 0.9,
                       dash: patterns[Swift.min(index, 2)])
            }
        }
        for series in ordered where series.role == .primary || series.role == .comparisonB
            || series.role == .comparisonC || series.role == .comparisonD {
            switch series.role {
            case .comparisonB: stroke(&context, polyline(series, vx, py), InstrumentPalette.displayInk.opacity(0.75), width: 0.9, dash: patterns[0])
            case .comparisonC: stroke(&context, polyline(series, vx, py), InstrumentPalette.displayInk.opacity(0.75), width: 0.9, dash: patterns[1])
            case .comparisonD: stroke(&context, polyline(series, vx, py), InstrumentPalette.displayInk.opacity(0.75), width: 0.9, dash: patterns[2])
            default:
                if series.style == .stems { drawStems(&context, series, vx, py, zeroX: zeroX, rect: rect) }
                else if series.style != .points {
                    drawSigned(&context, series, vx, py, zeroX: zeroX, rect: rect, dashOverride: dash(for: series.style))
                }
            }
        }
        for series in ordered where series.role == .measured || series.style == .points {
            for (x, y) in zip(series.xs, series.ys) where y.isFinite {
                let p = CGPoint(x: vx(y), y: py(x))
                context.fill(Path(ellipseIn: CGRect(x: p.x - 1.6, y: p.y - 1.6, width: 3.2, height: 3.2)),
                             with: .color(InstrumentPalette.instrumentAmber))
            }
        }
        for marker in plot.markers { drawMarker(&context, marker, y: py(marker.x), rect: rect, zeroX: zeroX) }
    }

    private func order(_ role: SeriesRole) -> Int {
        switch role {
        case .reference: 0
        case .depth: 1
        case .comparisonB, .comparisonC, .comparisonD: 2
        case .primary: 3
        case .measured: 4
        }
    }

    private func dash(for style: SeriesStyle) -> [CGFloat] {
        switch style {
        case .dashed: [3, 2]
        case .dotted: [0.8, 2]
        case .dashDot: [4, 2, 0.8, 2]
        default: []
        }
    }

    private func polyline(_ s: PlotSeries, _ vx: (Double) -> CGFloat, _ py: (Double) -> CGFloat) -> Path {
        var path = Path()
        var started = false
        for (x, y) in zip(s.xs, s.ys) {
            guard x.isFinite, y.isFinite else { started = false; continue }
            let p = CGPoint(x: vx(y), y: py(x))
            if started { path.addLine(to: p) } else { path.move(to: p); started = true }
        }
        return path
    }

    private func stroke(_ context: inout GraphicsContext, _ path: Path, _ color: Color, width: CGFloat, dash: [CGFloat]) {
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: width, lineCap: dash == [0.8, 2] ? .round : .butt, lineJoin: .round, dash: dash))
    }

    /// Discrete taps as horizontal stems from the spine; negative taps magenta and dashed (SPEC §14 colour never alone).
    private func drawStems(_ context: inout GraphicsContext, _ s: PlotSeries, _ vx: (Double) -> CGFloat,
                           _ py: (Double) -> CGFloat, zeroX: CGFloat, rect: CGRect) {
        let n = Swift.max(1, s.xs.count)
        let spacing = rect.height / CGFloat(Swift.max(1, n - 1))
        let width = Swift.min(1.4, Swift.max(0.5, spacing * 0.55))
        var positive = Path(), negative = Path(), tips = Path()
        for (x, y) in zip(s.xs, s.ys) where x.isFinite && y.isFinite {
            let yy = py(x), xx = vx(y)
            if y >= 0 {
                positive.move(to: CGPoint(x: zeroX, y: yy)); positive.addLine(to: CGPoint(x: xx, y: yy))
            } else {
                negative.move(to: CGPoint(x: zeroX, y: yy)); negative.addLine(to: CGPoint(x: xx, y: yy))
            }
            if spacing >= 3.5 { tips.addEllipse(in: CGRect(x: xx - 0.9, y: yy - 0.9, width: 1.8, height: 1.8)) }
        }
        context.stroke(positive, with: .color(ink.opacity(0.92)), lineWidth: width)
        context.stroke(negative, with: .color(InstrumentPalette.spectrumDepth), style: StrokeStyle(lineWidth: width, dash: [1.5, 1]))
        context.fill(tips, with: .color(ink))
    }

    /// A continuous signed trace: positive runs solid in the family ink over a faint fill; runs below zero are shaded
    /// spectrum secondary AND dashed (SPEC §4.1.3, §14).
    private func drawSigned(_ context: inout GraphicsContext, _ s: PlotSeries, _ vx: (Double) -> CGFloat,
                            _ py: (Double) -> CGFloat, zeroX: CGFloat, rect: CGRect, dashOverride: [CGFloat]) {
        let points = zip(s.xs, s.ys).filter { $0.0.isFinite && $0.1.isFinite }
        guard points.count > 1 else { return }
        var posFill = Path(), negFill = Path(), posLine = Path(), negLine = Path()
        posFill.move(to: CGPoint(x: zeroX, y: py(points[0].0)))
        negFill.move(to: CGPoint(x: zeroX, y: py(points[0].0)))
        for (x, y) in points {
            posFill.addLine(to: CGPoint(x: vx(Swift.max(0, y)), y: py(x)))
            negFill.addLine(to: CGPoint(x: vx(Swift.min(0, y)), y: py(x)))
        }
        posFill.addLine(to: CGPoint(x: zeroX, y: py(points[points.count - 1].0))); posFill.closeSubpath()
        negFill.addLine(to: CGPoint(x: zeroX, y: py(points[points.count - 1].0))); negFill.closeSubpath()
        context.fill(posFill, with: .color(ink.opacity(0.09)))
        context.fill(negFill, with: .color(InstrumentPalette.spectrumDepth.opacity(0.32)))
        // A value counts as negative only where it is drawn visibly below zero (≥ 0.3 pt): rounding residue of a strong
        // low-pass (H ≈ −1e−17) must not be styled as a negative lobe along the whole zero line.
        let floor = -0.3 / Swift.max(1e-9, Double(vx(1) - vx(0)))   // 0.3 pt in value units
        func clean(_ y: Double) -> Double { y < 0 && y > floor ? 0 : y }
        for i in 1..<points.count {
            let (x0, r0) = points[i - 1], (x1, r1) = points[i]
            let y0 = clean(r0), y1 = clean(r1)
            let a = CGPoint(x: vx(y0), y: py(x0)), b = CGPoint(x: vx(y1), y: py(x1))
            if (y0 >= 0) == (y1 >= 0) {
                if y0 >= 0 { posLine.move(to: a); posLine.addLine(to: b) } else { negLine.move(to: a); negLine.addLine(to: b) }
            } else {
                let t = y0 / (y0 - y1)
                let c = CGPoint(x: zeroX, y: py(x0 + (x1 - x0) * t))
                if y0 >= 0 { posLine.move(to: a); posLine.addLine(to: c); negLine.move(to: c); negLine.addLine(to: b) }
                else { negLine.move(to: a); negLine.addLine(to: c); posLine.move(to: c); posLine.addLine(to: b) }
            }
        }
        context.stroke(posLine, with: .color(ink.opacity(0.95)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: dashOverride))
        context.stroke(negLine, with: .color(InstrumentPalette.spectrumDepth),
                       style: StrokeStyle(lineWidth: 1.1, lineCap: .butt, dash: [2, 1.5]))
    }

    private func drawMarker(_ context: inout GraphicsContext, _ m: PlotMarker, y: CGFloat, rect: CGRect, zeroX: CGFloat) {
        guard y >= rect.minY - 0.5, y <= rect.maxY + 0.5 else { return }
        switch m.kind {
        case .minus3dB:
            var line = Path(); line.move(to: CGPoint(x: zeroX, y: y)); line.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.stroke(line, with: .color(InstrumentPalette.carrier), style: StrokeStyle(lineWidth: 0.75, dash: [2, 2]))
            context.fill(Path(ellipseIn: CGRect(x: rect.maxX - 3.6, y: y - 1.8, width: 3.6, height: 3.6)), with: .color(InstrumentPalette.carrier))
        case .halfAmplitude, .firstZero:
            var tick = Path(); tick.move(to: CGPoint(x: rect.maxX - 5, y: y)); tick.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.stroke(tick, with: .color(InstrumentPalette.secondaryInk), lineWidth: 0.8)
        case .probe, .supportBracket:
            var tick = Path(); tick.move(to: CGPoint(x: rect.minX, y: y)); tick.addLine(to: CGPoint(x: rect.minX + 5, y: y))
            context.stroke(tick, with: .color(InstrumentPalette.instrumentAmber), lineWidth: 1)
        case .regimeSwitch:
            let dot = Path(ellipseIn: CGRect(x: rect.maxX - 5, y: y - 2.2, width: 4.4, height: 4.4))
            if m.provenance == .measured { context.fill(dot, with: .color(InstrumentPalette.instrumentAmber)) }
            else { context.stroke(dot, with: .color(InstrumentPalette.instrumentAmber), lineWidth: 0.8) }
        case .custom:
            var tick = Path(); tick.move(to: CGPoint(x: rect.maxX - 4, y: y)); tick.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.stroke(tick, with: .color(.white.opacity(0.5)), lineWidth: 0.8)
        }
    }

    /// The honest empty state: the reason engraved along the pill (reading bottom-to-top), never a blank interior.
    private func drawEmpty(_ context: inout GraphicsContext, _ rect: CGRect, text: String) {
        var size = axisFont
        var resolved = context.resolve(Text(text).font(.system(size: size, weight: .medium, design: .monospaced))
            .foregroundStyle(InstrumentPalette.secondaryInk))
        let available = rect.height - 8
        let measured = resolved.measure(in: CGSize(width: 2000, height: 100)).width
        if measured > available, measured > 0 {
            size = Swift.max(6.5, size * available / measured)
            resolved = context.resolve(Text(text).font(.system(size: size, weight: .medium, design: .monospaced))
                .foregroundStyle(InstrumentPalette.secondaryInk))
        }
        var c = context
        c.translateBy(x: rect.midX, y: rect.midY)
        c.rotate(by: .degrees(-90))
        c.draw(resolved, at: .zero, anchor: .center)
    }

    /// The trailing engraving lane: the provenance word at the bottom, an overflowing title at the top.
    private func drawLane(_ context: inout GraphicsContext, _ lane: CGRect, scene: PillScene) {
        var c = context
        c.translateBy(x: lane.midX, y: lane.maxY - 2)
        c.rotate(by: .degrees(-90))
        var used: CGFloat = 0
        if let badge = scene.badge, let provenance = badge.provenance, !badge.isInput {
            let ink = HonestyBadge.ink(provenance)
            let words = ([provenance.word] + HonestyBadge.qualifierWords(badge.qualifiers)).joined(separator: " · ")
            let glyph: Text = HonestyBadge.symbolName(provenance).map { Text(Image(systemName: $0)) } ?? Text("≈")
            let resolved = c.resolve(Text("\(glyph) \(words)")
                .font(.system(size: axisFont - 0.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(ink))
            let size = resolved.measure(in: CGSize(width: lane.height, height: 40))
            let box = CGRect(x: 0, y: -size.height / 2 - 1.5, width: size.width + 6, height: size.height + 3)
            let dashed = provenance == .inferred
            c.stroke(Path(roundedRect: box, cornerRadius: box.height / 2),
                     with: .color(dashed ? ink.opacity(contrast ? 1 : 0.7)
                                         : .white.opacity(contrast ? InstrumentOpacity.badgeBorderIncreasedContrast : InstrumentOpacity.badgeBorder)),
                     style: StrokeStyle(lineWidth: dashed && contrast ? InstrumentMetrics.badgeStrokeIncreasedContrast : InstrumentMetrics.badgeStroke,
                                        dash: dashed ? [3, 2] : []))
            c.draw(resolved, at: CGPoint(x: 3, y: 0), anchor: .leading)
            used = box.width + 6
        }
        if scene.title.count > 6 {
            let resolved = c.resolve(Text(scene.title)
                .font(.system(size: axisFont - 0.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(ink.opacity(0.85)))
            let width = resolved.measure(in: CGSize(width: lane.height, height: 40)).width
            if width <= lane.height - 4 - used {
                c.draw(resolved, at: CGPoint(x: lane.height - 4, y: 0), anchor: .trailing)
            }
        }
    }
}

// MARK: - AXChartDescriptor (SPEC §14 "Plots": Audio Graphs for the pills)

private struct PillChartDescriptor: AXChartDescriptorRepresentable {
    let content: PillPlot
    let family: PillFamily
    let comparisons: [PillPlot]

    func makeChartDescriptor() -> AXChartDescriptor {
        let title = InstrumentSignalPill.spokenLabel(content, family: family)
        guard let plot = content.plot else {
            let axis = AXNumericDataAxisDescriptor(title: "none", range: 0...1, gridlinePositions: []) { _ in "" }
            return AXChartDescriptor(title: title, summary: content.emptyText ?? "", xAxis: axis, yAxis: axis,
                                     additionalAxes: [], series: [])
        }
        let others = comparisons.compactMap(\.plot)
        let xr = PillGeometry.xRange(plot, comparisons: others), yr = PillGeometry.yRange(plot, comparisons: others)
        let xUnit = plot.xAxis.unit.map { " " + PillAxisLabels.spokenUnit($0) } ?? ""
        let xAxis = AXNumericDataAxisDescriptor(title: plot.xAxis.label + (plot.xAxis.unit.map { " (\($0))" } ?? ""),
                                                range: xr, gridlinePositions: []) { NumberStyle.significant(3).spoken($0) + xUnit }
        let yAxis = AXNumericDataAxisDescriptor(title: plot.yAxis.label + (plot.yAxis.normalized ? ", normalized" : ""),
                                                range: yr, gridlinePositions: plot.showsZeroLine ? [0] : []) {
            NumberStyle.significant(3).spoken($0)
        }
        var series = plot.series.map { s in
            AXDataSeriesDescriptor(name: s.name, isContinuous: s.style != .stems && s.style != .points,
                                   dataPoints: zip(s.xs, s.ys).map { AXDataPoint(x: $0, y: $1) })
        }
        for (index, comparison) in comparisons.enumerated() {
            for s in comparison.plot?.series ?? [] where s.role == .primary {
                series.append(AXDataSeriesDescriptor(name: "\(["B", "C", "D"][Swift.min(index, 2)]): \(comparison.title)",
                                                     isContinuous: true, dataPoints: zip(s.xs, s.ys).map { AXDataPoint(x: $0, y: $1) }))
            }
        }
        return AXChartDescriptor(title: title, summary: plot.accessibilitySummary, xAxis: xAxis, yAxis: yAxis,
                                 additionalAxes: [], series: series)
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {}
}
