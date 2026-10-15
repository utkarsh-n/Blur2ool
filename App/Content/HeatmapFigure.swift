import SwiftUI
import BlurCore

// OWNER: CONTENT-VIEWS. A heat map (SPEC §5.1 floors 3–4): a signed 2-D response or a weight map, never colour alone.
// Signed maps use a diverging ramp (cyan above zero, spectrum depth below) AND hatch every negative cell AND draw the zero
// contour; unsigned maps use a sequential ramp with the half-peak contour. The centre (DC or the probe's tap) is an amber
// ring with a dot. The legend states the extremes as numbers with the map's badge and says the ramp is square-root mapped.
// Cells are drawn nearest-neighbour from a bitmap built once per spec (no smoothing hides a single cell).

struct HeatmapFigure: View {
    let spec: HeatmapSpec
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        let style = ContentLogic.valueStyle(spec.values, unit: nil)
        let minV = spec.values.min() ?? 0, maxV = spec.values.max() ?? 0
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: ContentSpacing.group) {
                Text(spec.caption).contentFont(.engraving).foregroundStyle(ContentInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: ContentSpacing.inline)
                HonestyBadge(spec.provenance).fixedSize()
            }
            // Map beside its legend; at accessibility sizes the legend stacks under the map.
            AnyLayout(size.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: ContentSpacing.section))
                                               : AnyLayout(HStackLayout(alignment: .center, spacing: ContentSpacing.section))) {
                HeatmapCanvas(spec: spec, increasedContrast: contrast == .increased)
                    .aspectRatio(CGFloat(spec.width) / CGFloat(Swift.max(1, spec.height)), contentMode: .fit)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spec.caption.lowercased())
                    .accessibilityValue(HeatmapFigure.spokenSummary(spec, style: style))
                HeatmapLegend(spec: spec, minText: style.text(minV), maxText: style.text(maxV))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentPlotInset()
    }

    static func spokenSummary(_ spec: HeatmapSpec, style: NumberStyle) -> String {
        let minV = spec.values.min() ?? 0, maxV = spec.values.max() ?? 0
        var s = "\(spec.width) by \(spec.height) values, minimum \(style.spoken(minV)), maximum \(style.spoken(maxV)), \(spec.provenance.spokenPhrase(device: nil))"
        if spec.signed {
            let negative = spec.values.filter { $0 < 0 }.count
            s += ". \(negative) of \(spec.values.count) cells are negative and hatched; the zero contour is drawn"
        } else {
            s += ". The half-peak contour is drawn"
        }
        if spec.centre != nil { s += "; the centre is marked with a ring and a dot" }
        return s + ". The data table under All details lists the centre row and column."
    }
}

/// The cells, hatching, contour and centre mark.
struct HeatmapCanvas: View {
    let spec: HeatmapSpec
    let increasedContrast: Bool

    var body: some View {
        let image = HeatmapCanvas.bitmap(spec)
        let limit = spec.signed ? Swift.max(abs(spec.values.min() ?? 0), abs(spec.values.max() ?? 0)) : (spec.values.max() ?? 0)
        let contourLevel = spec.signed ? 0 : limit / 2
        let segments = ContentLogic.contour(spec.values, width: spec.width, height: spec.height, level: contourLevel)
        Canvas { context, size in
            let cw = size.width / CGFloat(spec.width), ch = size.height / CGFloat(spec.height)
            if let image {
                context.draw(Image(decorative: image, scale: 1).interpolation(.none), in: CGRect(origin: .zero, size: size))
            }
            if spec.signed {
                // Hatch every negative cell: diagonal lines clipped to the negative cells (never colour alone).
                var negative = Path()
                for j in 0..<spec.height { for i in 0..<spec.width where spec.values[j * spec.width + i] < 0 {
                    negative.addRect(CGRect(x: CGFloat(i) * cw, y: CGFloat(j) * ch, width: cw + 0.01, height: ch + 0.01))
                } }
                var hatch = Path()
                let step = CGFloat(ContentLogic.hatchSpacing(cellSize: Double(Swift.min(cw, ch))))
                var x: CGFloat = -size.height
                while x < size.width {
                    hatch.move(to: CGPoint(x: x, y: size.height)); hatch.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += step
                }
                var clipped = context
                clipped.clip(to: negative)
                clipped.stroke(hatch, with: .color(.white.opacity(increasedContrast ? 0.55 : 0.32)), lineWidth: 0.6)
            }
            // The zero (signed) or half-peak (unsigned) contour, in cell units scaled to the canvas.
            var contour = Path()
            for s in segments {
                contour.move(to: CGPoint(x: s.a.x * cw, y: s.a.y * ch)); contour.addLine(to: CGPoint(x: s.b.x * cw, y: s.b.y * ch))
            }
            context.stroke(contour, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 0.8, lineCap: .round, dash: spec.signed ? [] : [2, 2]))
            if let c = spec.centre {
                let p = CGPoint(x: (CGFloat(c.x) + 0.5) * cw, y: (CGFloat(c.y) + 0.5) * ch)
                let r = Swift.max(3.5, Swift.min(cw, ch) * 0.9)
                context.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(ContentInk.probe), lineWidth: 1.2)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 1.3, y: p.y - 1.3, width: 2.6, height: 2.6)), with: .color(ContentInk.probe))
            }
            context.stroke(Path(CGRect(origin: .zero, size: size)), with: .color(ContentInk.hairline), lineWidth: 0.5)
        }
    }

    /// The map as an RGBA bitmap, one pixel per cell (drawn nearest-neighbour).
    @MainActor static func bitmap(_ spec: HeatmapSpec) -> CGImage? {
        let w = spec.width, h = spec.height
        guard w > 0, h > 0, spec.values.count == w * h else { return nil }
        let limit = spec.signed ? Swift.max(abs(spec.values.min() ?? 0), abs(spec.values.max() ?? 0)) : (spec.values.max() ?? 0)
        let ramp = ContentRamp.shared
        var bytes = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) {
            let rgb = ramp.rgb(ContentLogic.rampPosition(spec.values[i], limit: limit, signed: spec.signed))
            bytes[4 * i] = UInt8((rgb.0 * 255).rounded())
            bytes[4 * i + 1] = UInt8((rgb.1 * 255).rounded())
            bytes[4 * i + 2] = UInt8((rgb.2 * 255).rounded())
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4 * w, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// The legend: a ramp with its extremes as numbers, the zero mark, and the cues that do not depend on colour.
struct HeatmapLegend: View {
    let spec: HeatmapSpec
    let minText: String
    let maxText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 6) {
                ramp.frame(width: 10, height: 64)
                VStack(alignment: .leading, spacing: 0) {
                    Text(maxText).contentFont(.tick).monospacedDigit().foregroundStyle(ContentInk.display)
                    Spacer(minLength: 2)
                    if spec.signed { Text("0").contentFont(.tick).foregroundStyle(ContentInk.secondary) ; Spacer(minLength: 2) }
                    Text(minText).contentFont(.tick).monospacedDigit().foregroundStyle(ContentInk.display)
                }
                .frame(height: 64)
            }
            .accessibilityHidden(true)
            if spec.signed {
                legendRow(swatch: AnyView(hatchSwatch), text: "BELOW ZERO · HATCHED")
                legendRow(swatch: AnyView(lineSwatch(dash: [])), text: "ZERO CONTOUR")
            } else {
                legendRow(swatch: AnyView(lineSwatch(dash: [2, 2])), text: "HALF-PEAK CONTOUR")
            }
            if spec.centre != nil { legendRow(swatch: AnyView(centreSwatch), text: spec.signed ? "DC · CENTRE" : "CENTRE TAP") }
            Text("√ RAMP").contentFont(.engraving).foregroundStyle(ContentInk.secondary.opacity(0.8))
        }
        .accessibilityHidden(true)
    }

    private var ramp: some View {
        let stops: [Color] = spec.signed
            ? [ContentInk.primary, InstrumentPalette.plot, ContentInk.negative]
            : [ContentInk.primary, InstrumentPalette.plot]
        return RoundedRectangle(cornerRadius: 2)
            .fill(LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom))
            .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(ContentInk.hairline, lineWidth: 0.5) }
    }

    private func legendRow(swatch: AnyView, text: String) -> some View {
        HStack(spacing: 5) {
            swatch.frame(width: 14, height: 9)
            Text(text).contentFont(.engraving).foregroundStyle(ContentInk.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hatchSwatch: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ContentInk.negative.opacity(0.6)))
            var p = Path()
            var x: CGFloat = -size.height
            while x < size.width { p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0)); x += 3 }
            context.stroke(p, with: .color(.white.opacity(0.5)), lineWidth: 0.6)
        }
    }

    private func lineSwatch(dash: [CGFloat]) -> some View {
        Canvas { context, size in
            var p = Path(); p.move(to: CGPoint(x: 0, y: size.height / 2)); p.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(p, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 0.9, dash: dash))
        }
    }

    private var centreSwatch: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            context.stroke(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(ContentInk.probe), lineWidth: 1.1)
            context.fill(Path(ellipseIn: CGRect(x: c.x - 1.2, y: c.y - 1.2, width: 2.4, height: 2.4)), with: .color(ContentInk.probe))
        }
    }
}

/// The heat-map ramp, mixed from Metro tokens resolved once to sRGB: the plot inset at 0, wave cyan at +1, spectrum depth
/// at −1 (the tokens stay named; nothing here re-types a colour).
struct ContentRamp: Sendable {
    let floor: (Double, Double, Double)
    let positive: (Double, Double, Double)
    let negative: (Double, Double, Double)

    @MainActor static let shared = ContentRamp(floor: components(InstrumentPalette.plot), positive: components(ContentInk.primary),
                                               negative: components(ContentInk.negative))

    func rgb(_ position: Double) -> (Double, Double, Double) {
        let target = position < 0 ? negative : positive
        let t = Swift.min(1, abs(position))
        return (floor.0 + (target.0 - floor.0) * t, floor.1 + (target.1 - floor.1) * t, floor.2 + (target.2 - floor.2) * t)
    }

    static func components(_ color: Color) -> (Double, Double, Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }
}
