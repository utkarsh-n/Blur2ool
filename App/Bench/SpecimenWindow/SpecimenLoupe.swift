import Foundation
import SwiftUI
import MetalKit
import UIKit
import BlurCore
import BlurGPU

// OWNER: UI-SPECIMEN (SPEC §4.1.3 "Metal loupe", §14 "Seeing pixels"; METRO §F.5 item 2). The pixel peeper: an OPAQUE
// 112 × 112 pt Metal view (never glass: a glass loupe would add the system's refraction to the very pixels inspected)
// with a 1.4-pt metal rim, showing the 14 × 14 output texels around its centre at 8 pt per texel (24 px at scale 3,
// nearest), the centre texel outlined, and under it one 11-pt mono value line: the centre's linear value (3 significant
// digits), its 8-bit sRGB code and the LIVE badge. Its texels are the loupe's own copy of `LoupeReading.texels` (a
// full-resolution Run's readback), so during a preview it keeps showing that reading, marked HELD (review fix P-36).

enum SpecimenLoupeMetrics {
    static let texels = 14
    static let pointsPerTexel = 8.0
    static var body: Double { Double(texels) * pointsPerTexel }   // 112 pt
    static let rim = 1.4
    /// The value strip under the loupe: `0.0885 lin · 84/255` + the LIVE badge at 11-pt mono needs ≈ 204 pt, wider than
    /// the 115-pt loupe (MEASURED in the hosted render on the phone, 14 Oct 2026: inside 115 pt it truncated to `0.0892 l…`).
    static let valueLine = 22.0
    static let valueGap = 4.0
    static let valueWidth = 206.0
    /// Height of the whole loupe (rim, texels, gap, value strip).
    static var height: Double { body + 2 * rim + valueGap + valueLine }
    /// Width used for placement: the wider of the loupe and its value strip.
    static var width: Double { Swift.max(body + 2 * rim, valueWidth) }
    /// SPEC §4.1.3 lets the loupe float 84 pt above the finger with its value line under it. Measured at that literal
    /// reading (body centre 84 pt up) the value strip's lower edge lands exactly on the finger (hosted render on the phone,
    /// 14 Oct 2026), so the fingertip would hide the numbers: the whole loupe instead keeps `clearance` above the finger,
    /// which puts the body's centre ≈ 111 pt above it (≥ 84 pt, the SPEC's intent: never under the finger).
    static let lift = 84.0
    static let clearance = 28.0
    /// Top of the area the loupe may use, relative to the window: the housing's caption row (24 pt) is allowed.
    static let captionAllowance = 24.0

    /// The loupe's frame origin (top-left, in window points) for a finger at `finger`, clamped inside the window and the
    /// caption area; when there is no room above the finger it flips below it, so the finger never hides it.
    static func origin(finger: SIMD2<Double>, side: Double) -> SIMD2<Double> {
        let w = width, h = height
        let x = Swift.min(Swift.max(finger.x - w / 2, 0), Swift.max(0, side - w))
        let above = finger.y - clearance - h
        let minimumY = -captionAllowance, maximumY = side - h
        if above >= minimumY { return SIMD2(x, Swift.min(above, maximumY)) }
        let below = finger.y + clearance
        let flipped = Swift.min(Swift.max(below, minimumY), maximumY)
        // Below would cover the finger too (a very small window): keep the clamped position above.
        let fingerInside = finger.y >= flipped && finger.y <= flipped + h
        return SIMD2(x, fingerInside ? Swift.max(minimumY, Swift.min(above, maximumY)) : flipped)
    }
}

/// The loupe's Metal view: an MTKView of 14·8 pt (an integer number of pixels per texel at any screen scale), presenting
/// the loupe's texel copy through the same present pass as the window (crop mode, nearest, SDR encode + clip).
struct MetalLoupeView: UIViewRepresentable {
    let renderer: PresentRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = FixedDrawableMTKView(frame: .zero, device: renderer.coordinator.gpu.device)
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.autoResizeDrawable = false
        view.framebufferOnly = true
        view.isOpaque = true
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.delegate = renderer
        renderer.attach(view)
        apply(view, scale: context.environment.displayScale)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        apply(view, scale: context.environment.displayScale)
        view.setNeedsDisplay()
    }

    /// 14 texels × 8 pt × scale: 24 px per texel at scale 3, an integer block at any integer scale.
    private func apply(_ view: MTKView, scale: CGFloat) {
        let s = scale.isFinite && scale > 0 ? scale : 3
        let side = CGFloat(SpecimenLoupeMetrics.body) * s
        if view.contentScaleFactor != s { view.contentScaleFactor = s }
        (view as? FixedDrawableMTKView)?.fixedDrawableSize = CGSize(width: side, height: side)
    }
}

/// The opaque loupe: metal rim, the Metal texel view, the centre outline and the value line.
struct SpecimenLoupe: View {
    let renderer: PresentRenderer
    let reading: LoupeReading?
    /// Index (x, y) of the centre texel inside the 14 × 14 copy (it shifts near the window's edges).
    let centreTexel: SIMD2<Int>
    /// A preview is on screen: the reading is the last full-resolution one.
    let held: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let m = SpecimenLoupeMetrics.self
        VStack(spacing: m.valueGap) {
            ZStack(alignment: .topLeading) {
                MetalLoupeView(renderer: renderer)
                    .frame(width: m.body, height: m.body)
                Rectangle()   // the centre texel, outlined in instrument amber (a square: shape, not only colour)
                    .strokeBorder(InstrumentPalette.instrumentAmber, lineWidth: contrast == .increased ? 1.5 : 1)
                    .background(Rectangle().strokeBorder(.black.opacity(0.7), lineWidth: contrast == .increased ? 3.5 : 3))
                    .frame(width: m.pointsPerTexel + 2, height: m.pointsPerTexel + 2)
                    .offset(x: Double(centreTexel.x) * m.pointsPerTexel - 1, y: Double(centreTexel.y) * m.pointsPerTexel - 1)
            }
            .frame(width: m.body, height: m.body)
            .padding(m.rim)
            .background(SpecimenLoupe.metal(cornerRadius: 4))
            .overlay(SpecimenLoupe.rim(cornerRadius: 4 + m.rim, width: m.rim))
            valueLine
                .padding(.horizontal, 8)
                .frame(height: m.valueLine)
                .fixedSize()
                .background(SpecimenLoupe.metal(cornerRadius: m.valueLine / 2))
                .overlay(SpecimenLoupe.rim(cornerRadius: m.valueLine / 2, width: 0.8))
        }
        .frame(width: m.width, height: m.height, alignment: .top)
        .shadow(color: .black.opacity(0.7), radius: 10, y: 6)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loupe")
        .accessibilityValue(spoken)
    }

    /// Opaque instrument metal (METRO §B.5 housing tokens), never glass.
    static func metal(cornerRadius: Double) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(LinearGradient(colors: [InstrumentPalette.metalLight, InstrumentPalette.metalDark], startPoint: .top, endPoint: .bottom))
    }
    /// The housing's four-stop rim (white 0.36 → 0.025 → black → 0.15).
    static func rim(cornerRadius: Double, width: Double) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(LinearGradient(colors: [.white.opacity(0.36), .white.opacity(0.025), .black, .white.opacity(0.15)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: width)
    }

    @ViewBuilder private var valueLine: some View {
        HStack(spacing: 5) {
            if let reading {
                Text("\(reading.centreLinear.text) lin · \(reading.centreCode8.text)/255")
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(InstrumentPalette.displayInk)
                    .lineLimit(1)
                if held {
                    Text("HELD").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1)
                        .foregroundStyle(InstrumentPalette.secondaryInk)
                } else if let provenance = reading.centreLinear.provenance {
                    HonestyBadge(provenance).fixedSize()
                }
            } else {
                Text("READING…").font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(InstrumentPalette.secondaryInk)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.large)   // a fixed instrument strip; VoiceOver speaks the same value in full
    }

    private var spoken: String {
        guard let reading else { return "reading" }
        let where_ = "pixel \(reading.centre.x), \(reading.centre.y)"
        let state = held ? ", held from the last full-resolution frame" : ""
        return "\(where_): \(reading.centreLinear.spoken), 8-bit code \(reading.centreCode8.text) of 255, \(reading.centreCode8.provenance?.spokenPhrase(device: nil) ?? "")\(state)"
    }
}
