import SwiftUI
import BlurCore

// OWNER: CONTENT-VIEWS. A PSF field (SPEC §5.2 space-variant gathers, floor 4): the local PSFs of a grid of points drawn
// AT their positions and at ONE common scale (a lens spot diagram), so a zoom blur's spots stretch along their rays as they
// move away from the centre and a tilt-shift's spots swell away from the focus band. Each spot is normalised to its own
// peak (its shape is the point) and square-root mapped. The scale bar states how many pixels the spots' scale represents.
// VoiceOver hears the field's summary; the data table lists every spot's second moments.

struct PSFFieldFigure: View {
    let spec: PSFFieldSpec
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        let extent = PSFFieldFigure.windowExtent(spec)
        let reach = spec.kernels.map { CGFloat(Swift.max($0.width, $0.height)) }.max() ?? 1
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("LOCAL PSF AT \(spec.gridSize) × \(spec.gridSize) POINTS · ONE SCALE").contentFont(.engraving).foregroundStyle(ContentInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                HonestyBadge(.computed)
            }
            .accessibilityHidden(true)
            AnyLayout(size.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: ContentSpacing.section))
                                               : AnyLayout(HStackLayout(alignment: .bottom, spacing: ContentSpacing.section))) {
                PSFFieldCanvas(spec: spec, extent: extent, reach: reach)
                    .aspectRatio(1, contentMode: .fit)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Point spread functions across the image")
                    .accessibilityValue(PSFFieldFigure.spoken(spec))
                VStack(alignment: .leading, spacing: 6) {
                    PSFScaleBar(reach: reach, extent: extent, grid: spec.gridSize)
                    Text("EACH SPOT TO ITS OWN PEAK · √ RAMP").contentFont(.engraving).foregroundStyle(ContentInk.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentPlotInset()
    }

    /// The window the points sample: points sit at cell centres, so the window is twice the mean margin wider.
    static func windowExtent(_ spec: PSFFieldSpec) -> CGFloat {
        let xs = spec.points.map(\.x), ys = spec.points.map(\.y)
        guard let maxX = xs.max(), let minX = xs.min(), let maxY = ys.max(), let minY = ys.min() else { return 1 }
        return CGFloat(Swift.max(maxX + minX, maxY + minY) + 1)
    }

    static func spoken(_ spec: PSFFieldSpec) -> String {
        let moments = spec.kernels.map(ContentLogic.moments)
        guard let widest = moments.indices.max(by: { moments[$0].sigmaMajor < moments[$1].sigmaMajor }),
              let narrowest = moments.indices.min(by: { moments[$0].sigmaMajor < moments[$1].sigmaMajor }) else { return "" }
        let px = NumberStyle.decimals(2, unit: "px", spokenUnit: "pixels")
        let a = spec.points[widest], b = spec.points[narrowest]
        return "\(spec.points.count) local point spread functions, computed. The widest, at \(a.x), \(a.y), has sigma \(px.spoken(moments[widest].sigmaMajor)) along its axis and \(px.spoken(moments[widest].sigmaMinor)) across it; the narrowest, at \(b.x), \(b.y), has sigma \(px.spoken(moments[narrowest].sigmaMajor)). The data table lists every point."
    }
}

struct PSFFieldCanvas: View {
    let spec: PSFFieldSpec
    let extent: CGFloat
    let reach: CGFloat

    var body: some View {
        let images = spec.kernels.map(PSFFieldCanvas.spotImage)
        Canvas { context, size in
            let s = size.width / extent                                  // points per window pixel
            let cellPx = extent / CGFloat(spec.gridSize)                  // window pixels per grid cell
            let scale = cellPx * 0.92 / reach * s                          // one common scale: the largest spot fills 92 % of a cell
            var grid = Path()
            for k in 0...spec.gridSize {
                let v = CGFloat(k) * cellPx * s
                grid.move(to: CGPoint(x: v, y: 0)); grid.addLine(to: CGPoint(x: v, y: size.height))
                grid.move(to: CGPoint(x: 0, y: v)); grid.addLine(to: CGPoint(x: size.width, y: v))
            }
            context.stroke(grid, with: .color(ContentInk.grid), lineWidth: 0.5)
            for (i, p) in spec.points.enumerated() {
                let k = spec.kernels[i]
                let c = CGPoint(x: (CGFloat(p.x) + 0.5) * s, y: (CGFloat(p.y) + 0.5) * s)
                let w = CGFloat(k.width) * scale, h = CGFloat(k.height) * scale
                let origin = CGPoint(x: c.x - (CGFloat(k.originX) + 0.5) * scale, y: c.y - (CGFloat(k.originY) + 0.5) * scale)
                if let img = images[i] {
                    context.draw(Image(decorative: img, scale: 1).interpolation(.none), in: CGRect(origin: origin, size: CGSize(width: w, height: h)))
                }
                context.fill(Path(ellipseIn: CGRect(x: c.x - 0.8, y: c.y - 0.8, width: 1.6, height: 1.6)), with: .color(ContentInk.probe.opacity(0.9)))
            }
            context.stroke(Path(CGRect(origin: .zero, size: size)), with: .color(ContentInk.hairline), lineWidth: 0.5)
        }
    }

    /// One spot as an RGBA bitmap with transparent zero cells, normalised to its own peak, square-root mapped.
    @MainActor static func spotImage(_ k: Kernel2D) -> CGImage? {
        let peak = k.weights.max() ?? 0
        guard peak > 0, k.width > 0, k.height > 0 else { return nil }
        let ramp = ContentRamp.shared
        var bytes = [UInt8](repeating: 0, count: k.width * k.height * 4)
        for i in 0..<(k.width * k.height) where k.weights[i] > 0 {
            let t = ContentLogic.rampPosition(k.weights[i], limit: peak, signed: false)
            let rgb = ramp.rgb(1)
            let a = t                                                  // premultiplied: colour × coverage
            bytes[4 * i] = UInt8((rgb.0 * a * 255).rounded())
            bytes[4 * i + 1] = UInt8((rgb.1 * a * 255).rounded())
            bytes[4 * i + 2] = UInt8((rgb.2 * a * 255).rounded())
            bytes[4 * i + 3] = UInt8((a * 255).rounded())
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: k.width, height: k.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4 * k.width, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// How long one grid cell is in window pixels, and the spots' magnification (they are drawn larger than life when small).
struct PSFScaleBar: View {
    let reach: CGFloat
    let extent: CGFloat
    let grid: Int

    var body: some View {
        let cellPx = Double(extent) / Double(grid)
        let magnification = cellPx * 0.92 / Double(reach)
        VStack(alignment: .leading, spacing: 4) {
            Text("ONE CELL").contentFont(.engraving).foregroundStyle(ContentInk.secondary)
            BadgedValueText(.number(cellPx, NumberStyle.integer(unit: "px", spokenUnit: "pixels"), .computed), layout: .inline).fixedSize()
            Text("SPOTS ENLARGED").contentFont(.engraving).foregroundStyle(ContentInk.secondary)
            BadgedValueText(.number(magnification, NumberStyle.decimals(1, unit: "×", spokenUnit: "times"), .computed), layout: .inline).fixedSize()
        }
    }
}
