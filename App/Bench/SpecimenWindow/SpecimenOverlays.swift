import Foundation
import SwiftUI
import BlurCore

// OWNER: UI-SPECIMEN (SPEC §4.1.3, §8.3, §14; METRO §C.1). The SwiftUI overlays above the specimen MTKView: the probe
// crosshair, the on-image handles and the dividers. They are foreground drawings, never sampled by the blur, never glass,
// and never hit-tested (touches belong to the UIKit touch layer underneath, which hit-tests the same geometry).
// Each handle is also an adjustable VoiceOver element (±8 px, dividers ±10 %) with Centre on probe / Centre on image / Reset.
//
// Handle parameter convention (HandleSpec.parameters, positions in window pixels, widths in px), read in this order:
//   centre       [centre]  (kind .position → .point(x, y))  or  [x, y]
//   focusBand    [band centre y (.position uses its y), band width (px), optional angle (°)]
//   irisEllipse  [centre (.position) or x, y, radius (px)]
//   rampEnds     [start y, end y]
//   glassGrip    drawn and dragged by SystemExhibitView (FAM-F10), not here.

/// One handle resolved for the current configuration and view geometry.
struct SpecimenHandle: Identifiable, Hashable {
    enum Shape: Hashable {
        /// Amber ring with a dot (⊕): zoom, spin, god rays, cat's-eye, iris centre.
        case ring
        /// A small amber knob (iris radius).
        case knob
        /// A horizontal amber line across the window with a grip at its right end (focus lines, ramp ends).
        case line
        /// The band grip between two focus lines.
        case bandGrip
        /// A divider: 1-pt hairline over the full height with a metal grip at mid-height.
        case divider
    }
    var id: String
    var shape: Shape
    /// Centre of the 44-pt target in view points.
    var point: SIMD2<Double>
    var line: SpecimenLineHandle?
    /// Spoken name ("Zoom centre", "Split").
    var label: String
    /// Spoken value ("x 447, y 447 pixels", "Split at 50 percent").
    var value: String
    /// Axis the adjustable action moves (dividers and lines move along one axis only).
    var adjustsBothAxes: Bool
}

/// Resolves the handles a blur declares (and the dividers) into view geometry, and turns drags into parameter writes.
@MainActor
enum SpecimenHandleLayout {
    static let hitRadius = 22.0   // 44-pt targets (SPEC §4.1.3)

    static func handles(entry: CatalogEntry?, configuration: RenderConfiguration, geometry: PresentGeometry,
                        split: Double?, compare: CompareState?) -> [SpecimenHandle] {
        var out: [SpecimenHandle] = []
        let side = geometry.viewPoints
        // The divider grip sits at mid-height unless the probe is there (the default probe is 8 px below the centre).
        let probeY = geometry.point(ofPixelCentre: configuration.probe).y
        let gripY = abs(probeY - side / 2) < 40 ? (probeY < side / 2 ? side * 0.78 : side * 0.22) : side / 2
        if let compare, compare.view == .wipe, let x = geometry.splitPoint(compare.split) {
            out.append(SpecimenHandle(id: "compare", shape: .divider, point: SIMD2(x, gripY),
                                      line: SpecimenLineHandle(id: "compare", axis: .vertical, position: x),
                                      label: "Compare divider", value: "B left, A right, divider at \(percent(compare.split)) percent",
                                      adjustsBothAxes: false))
        } else if compare == nil, let split, let x = geometry.splitPoint(split) {
            out.append(SpecimenHandle(id: "split", shape: .divider, point: SIMD2(x, gripY),
                                      line: SpecimenLineHandle(id: "split", axis: .vertical, position: x),
                                      label: "Split", value: "Split at \(percent(split)) percent, input left of it",
                                      adjustsBothAxes: false))
        }
        guard let entry else { return out }
        let p = configuration.parameters
        for spec in entry.handles {
            let keys = spec.parameters
            switch spec.kind {
            case .centre:
                guard let c = position(keys, at: 0, in: p) else { continue }
                let v = geometry.point(ofWindowCoordinate: c)
                out.append(SpecimenHandle(id: "centre", shape: .ring, point: v, line: nil, label: centreLabel(entry),
                                          value: pixelsPhrase(c), adjustsBothAxes: true))
            case .focusBand:
                guard let y = coordinate(keys, at: 0, axis: 1, in: p), keys.count > 1, let width = p.double(keys[1]) else { continue }
                let centre = geometry.point(ofWindowCoordinate: SIMD2(Double(configuration.windowSize) / 2, y))
                let top = geometry.point(ofWindowCoordinate: SIMD2(0, y - width / 2)).y
                let bottom = geometry.point(ofWindowCoordinate: SIMD2(0, y + width / 2)).y
                out.append(SpecimenHandle(id: "focus.top", shape: .line, point: SIMD2(side - hitRadius, top),
                                          line: SpecimenLineHandle(id: "focus.top", axis: .horizontal, position: top),
                                          label: "Focus band, upper line", value: "band width \(Int(width.rounded())) pixels",
                                          adjustsBothAxes: false))
                out.append(SpecimenHandle(id: "focus.bottom", shape: .line, point: SIMD2(side - hitRadius, bottom),
                                          line: SpecimenLineHandle(id: "focus.bottom", axis: .horizontal, position: bottom),
                                          label: "Focus band, lower line", value: "band width \(Int(width.rounded())) pixels",
                                          adjustsBothAxes: false))
                out.append(SpecimenHandle(id: "focus.band", shape: .bandGrip, point: SIMD2(hitRadius, centre.y), line: nil,
                                          label: "Focus band", value: "centre at y \(Int(y.rounded())) pixels", adjustsBothAxes: false))
            case .irisEllipse:
                guard let c = position(keys, at: 0, in: p) else { continue }
                let radiusIndex = isPosition(keys.first, in: entry) ? 1 : 2
                let radius = radiusIndex < keys.count ? (p.double(keys[radiusIndex]) ?? 0) : 0
                out.append(SpecimenHandle(id: "iris.centre", shape: .ring, point: geometry.point(ofWindowCoordinate: c), line: nil,
                                          label: "Iris centre", value: pixelsPhrase(c), adjustsBothAxes: true))
                out.append(SpecimenHandle(id: "iris.radius", shape: .knob, point: geometry.point(ofWindowCoordinate: c + SIMD2(radius, 0)),
                                          line: nil, label: "Iris radius", value: "\(Int(radius.rounded())) pixels", adjustsBothAxes: false))
            case .rampEnds:
                for (index, id) in ["ramp.start", "ramp.end"].enumerated() where index < keys.count {
                    guard let y = coordinate(keys, at: index, axis: 1, in: p) else { continue }
                    let vy = geometry.point(ofWindowCoordinate: SIMD2(0, y)).y
                    out.append(SpecimenHandle(id: id, shape: .line, point: SIMD2(side - hitRadius, vy),
                                              line: SpecimenLineHandle(id: id, axis: .horizontal, position: vy),
                                              label: index == 0 ? "Ramp start" : "Ramp end", value: "y \(Int(y.rounded())) pixels",
                                              adjustsBothAxes: false))
                }
            case .glassGrip:
                continue
            }
        }
        return out
    }

    /// The parameter writes for a handle dragged to view point `point` (window pixels, clamped to each parameter's range).
    static func drag(_ id: String, to point: SIMD2<Double>, entry: CatalogEntry, configuration: RenderConfiguration,
                     geometry: PresentGeometry) -> [(HandleKind, ParameterKey, ParameterValue)] {
        let s = geometry.windowCoordinate(atPoint: point)
        let n = Double(configuration.windowSize - 1)
        let clampedS = SIMD2(Swift.min(Swift.max(s.x, 0), n), Swift.min(Swift.max(s.y, 0), n))
        let p = configuration.parameters
        func write(_ kind: HandleKind, _ keys: [ParameterKey], at index: Int, _ v: Double) -> (HandleKind, ParameterKey, ParameterValue)? {
            guard index < keys.count else { return nil }
            return (kind, keys[index], scalar(entry.spec(keys[index]), v))
        }
        for spec in entry.handles {
            let keys = spec.parameters
            switch (spec.kind, id) {
            case (.centre, "centre"), (.irisEllipse, "iris.centre"):
                if isPosition(keys.first, in: entry), let key = keys.first {
                    return [(spec.kind, key, .point(x: clampedS.x.rounded(), y: clampedS.y.rounded()))]
                }
                return [write(spec.kind, keys, at: 0, clampedS.x), write(spec.kind, keys, at: 1, clampedS.y)].compactMap { $0 }
            case (.irisEllipse, "iris.radius"):
                guard let c = position(keys, at: 0, in: p) else { return [] }
                let radiusIndex = isPosition(keys.first, in: entry) ? 1 : 2
                return [write(.irisEllipse, keys, at: radiusIndex, abs(s.x - c.x))].compactMap { $0 }
            case (.focusBand, "focus.band"):
                if isPosition(keys.first, in: entry), let key = keys.first {
                    return [(.focusBand, key, .point(x: Double(configuration.windowSize) / 2, y: clampedS.y.rounded()))]
                }
                return [write(.focusBand, keys, at: 0, clampedS.y)].compactMap { $0 }
            case (.focusBand, "focus.top"), (.focusBand, "focus.bottom"):
                guard let y = coordinate(keys, at: 0, axis: 1, in: p) else { return [] }
                return [write(.focusBand, keys, at: 1, 2 * abs(s.y - y))].compactMap { $0 }
            case (.rampEnds, "ramp.start"):
                return [write(.rampEnds, keys, at: 0, clampedS.y)].compactMap { $0 }
            case (.rampEnds, "ramp.end"):
                return [write(.rampEnds, keys, at: 1, clampedS.y)].compactMap { $0 }
            default:
                continue
            }
        }
        return []
    }

    /// The handle's window position nudged by (dx, dy) window pixels, as a view point (adjustable actions reuse `drag`).
    static func nudged(_ handle: SpecimenHandle, by d: SIMD2<Double>, geometry: PresentGeometry) -> SIMD2<Double> {
        geometry.point(ofWindowCoordinate: geometry.windowCoordinate(atPoint: handle.point) + d)
    }

    // MARK: Helpers

    static func isPosition(_ key: ParameterKey?, in entry: CatalogEntry) -> Bool {
        guard let key, let spec = entry.spec(key) else { return false }
        if case .position = spec.kind { return true }
        return false
    }
    /// A position from either one `.point` parameter at `index` or two scalars at `index`, `index + 1`.
    static func position(_ keys: [ParameterKey], at index: Int, in p: ParameterValues) -> SIMD2<Double>? {
        guard index < keys.count else { return nil }
        if let point = p.point(keys[index]) { return point }
        guard index + 1 < keys.count, let x = p.double(keys[index]), let y = p.double(keys[index + 1]) else { return nil }
        return SIMD2(x, y)
    }
    /// One coordinate: from a `.point` parameter's axis, or a scalar.
    static func coordinate(_ keys: [ParameterKey], at index: Int, axis: Int, in p: ParameterValues) -> Double? {
        guard index < keys.count else { return nil }
        if let point = p.point(keys[index]) { return axis == 0 ? point.x : point.y }
        return p.double(keys[index])
    }
    static func scalar(_ spec: ParameterSpec?, _ v: Double) -> ParameterValue {
        switch spec?.kind {
        case .integer(let i)?: .int(i.clamped(Int(v.rounded())))
        case .continuous(let c)?: .double(c.clamped((v / c.fineStep).rounded() * c.fineStep))
        default: .double(v.rounded())
        }
    }
    static func percent(_ split: Double) -> Int { Int((Swift.min(Swift.max(split, 0), 1) * 100).rounded()) }
    static func pixelsPhrase(_ c: SIMD2<Double>) -> String { "x \(Int(c.x.rounded())), y \(Int(c.y.rounded())) pixels" }
    static func centreLabel(_ entry: CatalogEntry) -> String {
        switch entry.id.rawValue {
        case "radial-zoom-blur": "Zoom centre"
        case "spin-blur": "Spin centre"
        case "god-rays": "Sun"
        default: "\(entry.displayName) centre"
        }
    }
}

// MARK: - Drawing

/// The probe crosshair (SPEC §4.1.3): instrument amber, 1-pt lines, 13-pt arms, a 3-pt gap so the pixel itself is never
/// covered (the gap widens with zoom to clear the magnified pixel). Increased Contrast: 1.5 pt with a 1-pt black keyline.
struct SpecimenProbeCrosshair: View {
    var point: CGPoint
    /// The probe pixel's side in points at the current zoom.
    var pixelPoints: Double
    var increasedContrast: Bool

    var body: some View {
        Canvas { context, _ in
            let gap = Swift.max(3, pixelPoints / 2 + 1)
            var cross = Path()
            let p = point
            cross.move(to: CGPoint(x: p.x - gap - 13, y: p.y)); cross.addLine(to: CGPoint(x: p.x - gap, y: p.y))
            cross.move(to: CGPoint(x: p.x + gap, y: p.y)); cross.addLine(to: CGPoint(x: p.x + gap + 13, y: p.y))
            cross.move(to: CGPoint(x: p.x, y: p.y - gap - 13)); cross.addLine(to: CGPoint(x: p.x, y: p.y - gap))
            cross.move(to: CGPoint(x: p.x, y: p.y + gap)); cross.addLine(to: CGPoint(x: p.x, y: p.y + gap + 13))
            let width = increasedContrast ? 1.5 : 1.0
            context.stroke(cross, with: .color(.black.opacity(increasedContrast ? 1 : 0.55)),
                           style: StrokeStyle(lineWidth: width + 2, lineCap: .square))
            context.stroke(cross, with: .color(InstrumentPalette.instrumentAmber), style: StrokeStyle(lineWidth: width, lineCap: .square))
        }
        .allowsHitTesting(false)
    }
}

/// Draws one handle in instrument amber over a black keyline (engraved look, readable on any image).
struct SpecimenHandleMark: View {
    var handle: SpecimenHandle
    var side: Double
    var increasedContrast: Bool

    var body: some View {
        Canvas { context, _ in
            let amber = GraphicsContext.Shading.color(InstrumentPalette.instrumentAmber)
            let key = GraphicsContext.Shading.color(.black.opacity(increasedContrast ? 1 : 0.6))
            let w = increasedContrast ? 1.6 : 1.2
            let p = CGPoint(x: handle.point.x, y: handle.point.y)
            func stroke(_ path: Path, _ width: Double) {
                context.stroke(path, with: key, lineWidth: width + 2)
                context.stroke(path, with: amber, lineWidth: width)
            }
            switch handle.shape {
            case .ring:
                stroke(Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)), w)
                var ticks = Path()   // ⊕: short ticks outside the ring mark the exact centre axes
                ticks.move(to: CGPoint(x: p.x - 14, y: p.y)); ticks.addLine(to: CGPoint(x: p.x - 10, y: p.y))
                ticks.move(to: CGPoint(x: p.x + 10, y: p.y)); ticks.addLine(to: CGPoint(x: p.x + 14, y: p.y))
                ticks.move(to: CGPoint(x: p.x, y: p.y - 14)); ticks.addLine(to: CGPoint(x: p.x, y: p.y - 10))
                ticks.move(to: CGPoint(x: p.x, y: p.y + 10)); ticks.addLine(to: CGPoint(x: p.x, y: p.y + 14))
                stroke(ticks, w)
                let dot = Path(ellipseIn: CGRect(x: p.x - 1.75, y: p.y - 1.75, width: 3.5, height: 3.5))
                context.fill(dot, with: amber)
            case .knob:
                stroke(Path(roundedRect: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12), cornerRadius: 3), w)
            case .line:
                var line = Path()
                line.move(to: CGPoint(x: 0, y: p.y)); line.addLine(to: CGPoint(x: side, y: p.y))
                context.stroke(line, with: key, lineWidth: 3)
                context.stroke(line, with: amber, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                stroke(Path(roundedRect: CGRect(x: p.x - 4, y: p.y - 9, width: 8, height: 18), cornerRadius: 4), w)
            case .bandGrip:
                stroke(Path(roundedRect: CGRect(x: p.x - 9, y: p.y - 5, width: 18, height: 10), cornerRadius: 5), w)
            case .divider:
                // The 1-pt hairline lies on the LEFT of the divider column (over the last input pixels), so the first
                // output column — and a probe standing on it — is never covered.
                var hairline = Path()
                hairline.move(to: CGPoint(x: p.x - 0.5, y: 0)); hairline.addLine(to: CGPoint(x: p.x - 0.5, y: side))
                var keyline = Path()
                keyline.move(to: CGPoint(x: p.x - 1.5, y: 0)); keyline.addLine(to: CGPoint(x: p.x - 1.5, y: side))
                context.stroke(keyline, with: .color(.black.opacity(0.5)), lineWidth: 1)
                context.stroke(hairline, with: .color(.white.opacity(increasedContrast ? 0.95 : 0.7)), lineWidth: 1)
                // Opaque metal grip (never glass over the image): 12 × 30 pt with ◀ ▶ chevrons, at `point.y`.
                let grip = CGRect(x: p.x - 6, y: p.y - 15, width: 12, height: 30)
                let shape = Path(roundedRect: grip, cornerRadius: 6)
                context.fill(shape, with: .linearGradient(Gradient(colors: [InstrumentPalette.metalLight, InstrumentPalette.metalDark]),
                                                          startPoint: CGPoint(x: grip.minX, y: grip.minY), endPoint: CGPoint(x: grip.maxX, y: grip.maxY)))
                context.stroke(shape, with: .color(.white.opacity(increasedContrast ? 0.6 : 0.32)), lineWidth: 0.8)
                var chevrons = Path()
                chevrons.move(to: CGPoint(x: p.x - 1, y: p.y - 6)); chevrons.addLine(to: CGPoint(x: p.x - 3.5, y: p.y - 3.5))
                chevrons.addLine(to: CGPoint(x: p.x - 1, y: p.y - 1))
                chevrons.move(to: CGPoint(x: p.x + 1, y: p.y + 1)); chevrons.addLine(to: CGPoint(x: p.x + 3.5, y: p.y + 3.5))
                chevrons.addLine(to: CGPoint(x: p.x + 1, y: p.y + 6))
                context.stroke(chevrons, with: .color(.white.opacity(0.75)), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
    }
}
