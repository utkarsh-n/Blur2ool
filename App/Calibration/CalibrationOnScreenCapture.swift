import SwiftUI
import UIKit
import BlurCore

// OWNER: CALIBRATION (SPEC §13.3 PATH menu, "the experiment"). The on-screen path: the blurred edge is hosted in the app's
// window (behind the app's own content) and captured with UIView.drawHierarchy(in:afterScreenUpdates: true). Whether that
// capture contains what the render server composites (Core Animation filters, materials) is UNVERIFIED, so every result
// of this path stays labelled ON-SCREEN · EXPERIMENTAL until the objective capture test below passes on this phone:
// a render-server-only effect — a Material over a known black | white step — must appear in the capture as a spread
// step (the backdrop blurred) that differs from the bare step beside it. A person's confirmation cannot change the label.

public struct CalibrationCaptureTest: Sendable, Hashable {
    /// 10–90 % rise width (device px) of the bare step and of the step seen through the material.
    public var bareRiseWidthPx: Double
    public var materialRiseWidthPx: Double
    /// Black-side to white-side difference through the material (0 = a flat fill, no backdrop).
    public var materialContrast: Double
    /// Largest difference between the material row and the bare row.
    public var maxDifferenceFromBare: Double
    public var device: DeviceStamp
    /// The capture shows the backdrop blurred under the material: render-server compositing is captured.
    public var passed: Bool {
        materialContrast >= 0.1 && materialRiseWidthPx >= bareRiseWidthPx + 4 && maxDifferenceFromBare >= 0.05
    }
}

@MainActor
enum CalibrationOnScreenCapture {
    /// Hosts `view` (size in points) behind the app's content for one capture and returns the captured image.
    static func capture<V: View>(_ view: V, size: CGSize, scale: CGFloat) -> CGImage? {
        guard let window = CalibrationDevice.keyWindow, size.width > 0, size.height > 0 else { return nil }
        let host = UIHostingController(rootView: view.frame(width: size.width, height: size.height))
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.isUserInteractionEnabled = false
        host.view.accessibilityElementsHidden = true
        window.insertSubview(host.view, at: 0)
        defer { host.view.removeFromSuperview() }
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            _ = host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        return image.cgImage
    }

    /// The objective capture test (SPEC §13.3).
    static func runCaptureTest(scale: CGFloat, device: DeviceStamp) async -> CalibrationCaptureTest? {
        let gate = CalibrationRenderGate.shared
        guard await gate.waitForTurn() else { return nil }
        let size = CGSize(width: 240, height: 120)
        let view = ZStack(alignment: .topLeading) {
            HStack(spacing: 0) { Color.black; Color.white }
            Rectangle().fill(.ultraThinMaterial).frame(width: 140, height: 56).offset(x: 50, y: 62)
        }
        .frame(width: size.width, height: size.height)
        let (image, _) = gate.timed { capture(view, size: size, scale: scale) }
        guard let image else { return nil }
        guard let bare = row(image, yFraction: 30.0 / 120), let material = row(image, yFraction: 90.0 / 120) else { return nil }
        let s = Double(scale)
        let from = Int(60 * s), to = Int(180 * s)
        guard to <= bare.count, to <= material.count else { return nil }
        let bareSlice = Array(bare[from..<to]), materialSlice = Array(material[from..<to])
        let maxDiff = zip(bareSlice, materialSlice).map { abs($0 - $1) }.max() ?? 0
        let contrast = (materialSlice.suffix(Int(10 * s)).reduce(0, +) / (10 * s)) - (materialSlice.prefix(Int(10 * s)).reduce(0, +) / (10 * s))
        return CalibrationCaptureTest(bareRiseWidthPx: riseWidth(bareSlice), materialRiseWidthPx: riseWidth(materialSlice),
                                      materialContrast: contrast, maxDifferenceFromBare: maxDiff, device: device)
    }

    /// One image row (mean of R, G, B, encoded) at a fraction of the height.
    static func row(_ image: CGImage, yFraction: Double) -> [Double]? {
        guard let rows = CalibrationEdgeReadback.centreRows(image, encoded: true, rows: image.height) else { return nil }
        let y = Swift.min(rows.count - 1, Swift.max(0, Int(Double(rows.count) * yFraction)))
        return rows[y]
    }

    /// 10–90 % rise width of a profile that rises from its left end to its right end.
    static func riseWidth(_ v: [Double]) -> Double {
        guard let lo = v.first, let hi = v.last, hi - lo > 1e-3 else { return 0 }
        let a = lo + 0.1 * (hi - lo), b = lo + 0.9 * (hi - lo)
        guard let i = v.firstIndex(where: { $0 >= a }), let j = v.firstIndex(where: { $0 >= b }) else { return 0 }
        return Double(j - i)
    }
}
