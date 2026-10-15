import SwiftUI
import BlurCore

// OWNER: CONTENT-VIEWS. Floor 6 Silicon (SPEC §4.3, §5.1): the dispatch geometry drawn over a COPY of the output (the
// host sets `.figureBackdrop(_:)`; the specimen texture itself is never touched). Three views, chosen with a segmented
// control: THREADGROUPS (the whole grid), PROBE GROUP (the probe's threadgroup and the apron it reads, magnified, with its
// SIMD-groups banded and the probe's thread outlined) and TILES (the 32 × 32 tile grid, labelled as Apple's REFERENCE
// maximum for Apple9; the tile size a pass really uses is not published). Geometry is COMPUTED from the recorded dispatch.

struct DispatchOverlayFigure: View {
    let spec: DispatchOverlaySpec
    @State private var mode: Mode = .probeGroup
    @Environment(\.figureBackdrop) private var backdrop
    @Environment(\.dynamicTypeSize) private var size

    enum Mode: String, CaseIterable, Identifiable {
        case groups = "Threadgroups", probeGroup = "Probe group", tiles = "Tiles"
        var id: String { rawValue }
    }

    var body: some View {
        let layout = ContentLogic.dispatchLayout(spec)
        VStack(alignment: .leading, spacing: 6) {
            Picker("Overlay", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .instrumentControlOwnsTouches(identifier: "dispatchOverlayMode")
            if let layout {
                AnyLayout(size.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: ContentSpacing.section))
                                                   : AnyLayout(HStackLayout(alignment: .top, spacing: ContentSpacing.section))) {
                    DispatchOutputCanvas(layout: layout, mode: mode, backdrop: backdrop)
                        .aspectRatio(CGFloat(layout.output.x) / CGFloat(Swift.max(1, layout.output.y)), contentMode: .fit)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Dispatch over a copy of the output")
                        .accessibilityValue(DispatchOverlayFigure.spoken(spec, layout))
                    DispatchCaption(spec: spec, layout: layout, mode: mode)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ContentEngravedLine(text: "\(spec.dispatch.encoder.rawValue.uppercased()) PASS · NO THREADGROUPS TO DRAW")
            }
        }
        .padding(8)
        .contentPlotInset()
    }

    static func spoken(_ spec: DispatchOverlaySpec, _ l: ContentLogic.DispatchLayout) -> String {
        "\(l.groups.x) by \(l.groups.y) threadgroups of \(l.groupSize.x) by \(l.groupSize.y) threads over a \(l.output.x) by \(l.output.y) pixel output, computed. "
            + "The probe at \(l.probe.x), \(l.probe.y) is thread \(spec.probeThreadInGroup.map(String.init).joined(separator: ", ")) of threadgroup "
            + "\(spec.probeThreadgroup.map(String.init).joined(separator: ", ")), SIMD-group \(spec.probeSIMDGroup), lane \(spec.probeLane)."
            + (spec.apronTexels > 0 ? " Its threadgroup reads an apron of \(spec.apronTexels) texels on each side." : "")
    }
}

/// The output square with the chosen overlay; the probe group is magnified in an inset when it is too small to see.
struct DispatchOutputCanvas: View {
    let layout: ContentLogic.DispatchLayout
    let mode: DispatchOverlayFigure.Mode
    let backdrop: CGImage?

    var body: some View {
        Canvas { context, size in
            let sx = size.width / CGFloat(layout.output.x), sy = size.height / CGFloat(layout.output.y)
            func rect(_ o: SIMD2<Int>, _ s: SIMD2<Int>) -> CGRect {
                CGRect(x: CGFloat(o.x) * sx, y: CGFloat(o.y) * sy, width: CGFloat(s.x) * sx, height: CGFloat(s.y) * sy)
            }
            let frame = CGRect(origin: .zero, size: size)
            if let backdrop {
                var dim = context
                dim.opacity = 0.55
                dim.draw(Image(decorative: backdrop, scale: 1).interpolation(.none), in: frame)
            } else {
                context.fill(Path(frame), with: .color(Color.white.opacity(0.025)))
            }
            switch mode {
            case .groups, .probeGroup:
                let strength = mode == .groups ? 1.0 : 0.4
                var grid = Path()
                let gw = CGFloat(layout.groupSize.x) * sx, gh = CGFloat(layout.groupSize.y) * sy
                if gw >= 2 { var x: CGFloat = 0; while x <= size.width + 0.5 { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)); x += gw } }
                if gh >= 2 { var y: CGFloat = 0; while y <= size.height + 0.5 { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)); y += gh } }
                context.stroke(grid, with: .color(ContentInk.primary.opacity(0.35 * strength)), lineWidth: 0.5)
                if gw < 2 || gh < 2 {
                    // Row or column groups thinner than a point: band every group instead of stroking each line.
                    let bands = gh < 2 ? layout.groups.y : layout.groups.x
                    let stride = Swift.max(1, bands / 48)
                    for b in Swift.stride(from: 0, to: bands, by: stride * 2) {
                        let r = gh < 2 ? CGRect(x: 0, y: CGFloat(b) * gh, width: size.width, height: CGFloat(stride) * gh)
                                       : CGRect(x: CGFloat(b) * gw, y: 0, width: CGFloat(stride) * gw, height: size.height)
                        context.fill(Path(r), with: .color(ContentInk.primary.opacity(0.07 * strength)))
                    }
                }
            case .tiles:
                var grid = Path()
                let t = 32.0
                var x: CGFloat = 0; while x <= size.width + 0.5 { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)); x += t * sx }
                var y: CGFloat = 0; while y <= size.height + 0.5 { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)); y += t * sy }
                context.stroke(grid, with: .color(ContentInk.comparisonB.opacity(0.4)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
            }
            // The probe's group, its apron, and the probe pixel (crosshair) on every view.
            let group = rect(layout.probeGroupOrigin, layout.groupSize)
            let apron = rect(layout.apronOrigin, layout.apronSize)
            if layout.apronSize != layout.groupSize {
                context.fill(Path(apron), with: .color(ContentInk.probe.opacity(0.12)))
                context.stroke(Path(apron.insetBy(dx: -0.5, dy: -0.5)), with: .color(ContentInk.probe.opacity(0.8)), style: StrokeStyle(lineWidth: 0.8, dash: [2, 1.5]))
            }
            context.stroke(Path(group.insetBy(dx: -1, dy: -1)), with: .color(ContentInk.probe), lineWidth: 1.2)
            let p = CGPoint(x: (CGFloat(layout.probe.x) + 0.5) * sx, y: (CGFloat(layout.probe.y) + 0.5) * sy)
            var cross = Path()
            cross.move(to: CGPoint(x: p.x - 7, y: p.y)); cross.addLine(to: CGPoint(x: p.x - 2.5, y: p.y))
            cross.move(to: CGPoint(x: p.x + 2.5, y: p.y)); cross.addLine(to: CGPoint(x: p.x + 7, y: p.y))
            cross.move(to: CGPoint(x: p.x, y: p.y - 7)); cross.addLine(to: CGPoint(x: p.x, y: p.y - 2.5))
            cross.move(to: CGPoint(x: p.x, y: p.y + 2.5)); cross.addLine(to: CGPoint(x: p.x, y: p.y + 7))
            context.stroke(cross, with: .color(ContentInk.probe), lineWidth: 1)
            context.stroke(Path(frame), with: .color(ContentInk.hairline), lineWidth: 0.5)
            if mode == .probeGroup { drawMagnified(&context, size: size, near: p) }
        }
    }

    /// The probe's group magnified in the lower half (or upper, if the probe is low): threads as cells, SIMD-groups banded,
    /// the apron hatched, the probe's thread outlined.
    private func drawMagnified(_ context: inout GraphicsContext, size: CGSize, near p: CGPoint) {
        let gs = layout.groupSize
        let apronX = (layout.probeGroupOrigin.x - layout.apronOrigin.x), apronY = (layout.probeGroupOrigin.y - layout.apronOrigin.y)
        let spanX = layout.apronSize.x, spanY = layout.apronSize.y
        let boxW = size.width * 0.92
        let cellW = Swift.min(boxW / CGFloat(spanX), size.height * 0.42 / CGFloat(spanY))
        // A one-row (or one-column) group is drawn as a strip: threads stay as wide as the box allows, rows at least 12 pt.
        let cellH = spanY == 1 ? Swift.max(cellW, 12) : cellW
        let cell = cellW
        let w = cellW * CGFloat(spanX), h = cellH * CGFloat(spanY)
        let top = p.y > size.height / 2 ? size.height * 0.06 : size.height - h - size.height * 0.06
        let box = CGRect(x: (size.width - w) / 2, y: top, width: w, height: h)
        context.fill(Path(box.insetBy(dx: -4, dy: -4)), with: .color(InstrumentPalette.plot.opacity(0.94)))
        context.stroke(Path(box.insetBy(dx: -4, dy: -4)), with: .color(ContentInk.hairline), lineWidth: 0.6)
        // apron cells: hatched
        var apronPath = Path()
        for j in 0..<spanY { for i in 0..<spanX {
            let inside = i >= apronX && i < apronX + gs.x && j >= apronY && j < apronY + gs.y
            if !inside { apronPath.addRect(CGRect(x: box.minX + CGFloat(i) * cell, y: box.minY + CGFloat(j) * cellH, width: cell, height: cellH)) }
        } }
        context.fill(apronPath, with: .color(ContentInk.probe.opacity(0.14)))
        // SIMD-groups: alternate bands across the group's row-major thread numbering
        let simd = layout.simdWidth
        for t in 0..<(gs.x * gs.y) {
            let i = t % gs.x, j = t / gs.x
            if (t / simd) % 2 == 1 {
                let r = CGRect(x: box.minX + CGFloat(apronX + i) * cell, y: box.minY + CGFloat(apronY + j) * cellH, width: cell, height: cellH)
                context.fill(Path(r), with: .color(ContentInk.primary.opacity(0.16)))
            }
        }
        let groupRect = CGRect(x: box.minX + CGFloat(apronX) * cell, y: box.minY + CGFloat(apronY) * cellH, width: CGFloat(gs.x) * cell, height: CGFloat(gs.y) * cellH)
        if cell >= 4 {
            var lines = Path()
            for i in 0...gs.x { let x = groupRect.minX + CGFloat(i) * cell; lines.move(to: CGPoint(x: x, y: groupRect.minY)); lines.addLine(to: CGPoint(x: x, y: groupRect.maxY)) }
            for j in 0...gs.y { let y = groupRect.minY + CGFloat(j) * cellH; lines.move(to: CGPoint(x: groupRect.minX, y: y)); lines.addLine(to: CGPoint(x: groupRect.maxX, y: y)) }
            context.stroke(lines, with: .color(Color.white.opacity(0.1)), lineWidth: 0.4)
        }
        context.stroke(Path(groupRect), with: .color(ContentInk.probe), lineWidth: 1)
        let th = SIMD2(layout.probe.x - layout.probeGroupOrigin.x, layout.probe.y - layout.probeGroupOrigin.y)
        let probeCell = CGRect(x: box.minX + CGFloat(apronX + th.x) * cell, y: box.minY + CGFloat(apronY + th.y) * cellH, width: Swift.max(cell, 1.5), height: cellH)
        context.fill(Path(probeCell), with: .color(ContentInk.probe.opacity(0.85)))
        context.stroke(Path(probeCell.insetBy(dx: -1.5, dy: -1.5)), with: .color(ContentInk.probe), lineWidth: 1)
    }
}

/// The figure's engraved legend: coordinates and identifiers (literals), each cue named in words.
struct DispatchCaption: View {
    let spec: DispatchOverlaySpec
    let layout: ContentLogic.DispatchLayout
    let mode: DispatchOverlayFigure.Mode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(spec.dispatch.name + " · " + (spec.dispatch.functionNames.first ?? spec.dispatch.encoder.rawValue))
                .contentFont(.tick).foregroundStyle(ContentInk.display).fixedSize(horizontal: false, vertical: true)
            line("GRID", "\(layout.groups.x) × \(layout.groups.y)")
            line("GROUP", "\(layout.groupSize.x) × \(layout.groupSize.y)")
            line("PROBE", "(\(layout.probe.x), \(layout.probe.y))", ink: ContentInk.probe)
            line("THREAD", "(" + spec.probeThreadInGroup.prefix(2).map(String.init).joined(separator: ", ") + ")")
            line("SIMD", "\(spec.probeSIMDGroup) · LANE \(spec.probeLane)")
            Spacer(minLength: 2)
            switch mode {
            case .groups: cue(AnyView(Rectangle().strokeBorder(ContentInk.primary.opacity(0.7), lineWidth: 0.8)), "GROUPS")
            case .probeGroup:
                cue(AnyView(Rectangle().fill(ContentInk.primary.opacity(0.35))), "SIMD-GROUPS")
                if spec.apronTexels > 0 { cue(AnyView(Rectangle().fill(ContentInk.probe.opacity(0.3))), "APRON") }
            case .tiles:
                cue(AnyView(Rectangle().strokeBorder(ContentInk.comparisonB, style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))), "32 × 32 MAX")
                HonestyBadge(.reference).fixedSize()
            }
            cue(AnyView(Rectangle().fill(ContentInk.probe)), "PROBE")
        }
        .accessibilityHidden(true)
    }

    private func line(_ label: String, _ value: String, ink: Color = ContentInk.display) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label).contentFont(.engraving).foregroundStyle(ContentInk.secondary).fixedSize()
            Spacer(minLength: 2)
            Text(value).contentFont(.tick).monospacedDigit().foregroundStyle(ink).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func cue(_ swatch: AnyView, _ text: String) -> some View {
        HStack(spacing: 5) {
            swatch.frame(width: 10, height: 8)
            Text(text).contentFont(.engraving).foregroundStyle(ContentInk.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
