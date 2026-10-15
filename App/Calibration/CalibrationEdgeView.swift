import SwiftUI

// OWNER: CALIBRATION (frozen initialiser, ARCHITECTURE §5.13). The black | white step that is blurred and fitted (CAL §7).
// At 0° the body is exactly Tools/calibrate/MeasurePSF.swift's `CalibrationEdge` (a black canvas with a white rectangle
// offset to `edgeX`), so a phone render and the research Mac's render of the same parameter are the same picture; the
// Mac cross-check compares the two byte for byte. Any other angle draws the white half-plane through (edgeX, height/2),
// rotated clockwise from vertical (the 45° twin that separates separable kernels from isotropic ones, CAL §3.1).
// Platform-neutral (SwiftUI only): it also compiles into the macOS cross-check harness.
public struct CalibrationEdgeView: View {
    public let size: CGSize
    public let edgeX: CGFloat
    public let angleDegrees: Double
    public init(size: CGSize, edgeX: CGFloat, angleDegrees: Double = 0) { self.size = size; self.edgeX = edgeX; self.angleDegrees = angleDegrees }

    public var body: some View {
        if angleDegrees == 0 {
            ZStack(alignment: .topLeading) {
                Color.black
                Color.white
                    .frame(width: Swift.max(0, size.width - edgeX), height: size.height)
                    .offset(x: edgeX)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        } else {
            ZStack(alignment: .topLeading) {
                Color.black
                CalibrationHalfPlane(pivot: CGPoint(x: edgeX, y: size.height / 2), angleDegrees: angleDegrees).fill(Color.white)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
    }
}

/// The white half-plane {p : (p − pivot) · n ≥ 0}, n = (cos θ, sin θ) (y down), clipped to the frame.
struct CalibrationHalfPlane: Shape {
    var pivot: CGPoint
    var angleDegrees: Double

    func path(in rect: CGRect) -> Path {
        let theta = angleDegrees * Double.pi / 180
        let n = (x: cos(theta), y: sin(theta))
        func side(_ p: CGPoint) -> Double { (Double(p.x - pivot.x)) * n.x + (Double(p.y - pivot.y)) * n.y }
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        var polygon: [CGPoint] = []
        for i in corners.indices {
            let a = corners[i], b = corners[(i + 1) % corners.count]
            let sa = side(a), sb = side(b)
            if sa >= 0 { polygon.append(a) }
            if (sa >= 0) != (sb >= 0) {
                let t = sa / (sa - sb)
                polygon.append(CGPoint(x: a.x + CGFloat(t) * (b.x - a.x), y: a.y + CGFloat(t) * (b.y - a.y)))
            }
        }
        var path = Path()
        guard let first = polygon.first else { return path }
        path.move(to: first)
        for p in polygon.dropFirst() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }
}
