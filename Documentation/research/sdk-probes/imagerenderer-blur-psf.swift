// Measure SwiftUI .blur(radius:) line-spread function via ImageRenderer (offscreen, float).
import SwiftUI
import CoreGraphics

let N = 257
@MainActor func render(_ radius: CGFloat, edge: Bool) -> [Float] {
    let content = ZStack(alignment: .leading) {
        Color.clear
        if edge { Rectangle().fill(.white).frame(width: CGFloat(3 * N / 2)) }
        else { Rectangle().fill(.white).frame(width: 1).frame(maxWidth: .infinity) }
    }
    .frame(width: CGFloat(edge ? 3 * N : N), height: CGFloat(N))
    .blur(radius: radius)
    let r = ImageRenderer(content: content)
    r.scale = 1
    r.colorMode = .extendedLinear
    guard let cg = r.cgImage else { fatalError("no image") }
    // Redraw into a known float RGBA buffer and return the alpha of the middle row.
    var px = [Float](repeating: 0, count: cg.width * cg.height * 4)
    let cs = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    px.withUnsafeMutableBytes { buf in
        let ctx = CGContext(data: buf.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 32,
                            bytesPerRow: cg.width * 16, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    }
    let y = cg.height / 2
    return (0..<cg.width).map { px[(y * cg.width + $0) * 4 + 3] }
}

@MainActor func run() {
    print("radius | sigma(LSF 2nd moment) | area | sigma(edge 10-90) | sigma/r | kurtosis | support half-width(px, >1e-5)")
    for r in [1.0, 2, 4, 8, 16, 32] {
        let l = render(r, edge: false)
        let area = l.reduce(0, +)
        let mean = l.enumerated().reduce(0.0) { $0 + Double($1.offset) * Double($1.element) } / Double(area)
        let m2 = l.enumerated().reduce(0.0) { $0 + pow(Double($1.offset) - mean, 2) * Double($1.element) } / Double(area)
        let m4 = l.enumerated().reduce(0.0) { $0 + pow(Double($1.offset) - mean, 4) * Double($1.element) } / Double(area)
        let nz = l.enumerated().filter { $0.element > 1e-5 }.map { Double($0.offset) }
        let support = ((nz.max() ?? 0) - (nz.min() ?? 0)) / 2
        let e = render(r, edge: true)
        let top = e[N / 2], frac = e.map { $0 / top }   // plateau far (>= 4 sigma) from both ends of the white bar
        func cross(_ t: Float) -> Double { // first index where frac drops below t, linear interp
            for i in (N / 2 + 1)..<frac.count where frac[i] < t { return Double(i - 1) + Double((frac[i - 1] - t) / (frac[i - 1] - frac[i])) }
            return .nan
        }
        let w1090 = cross(0.1) - cross(0.9)
        print(String(format: "%5.0f | %8.3f | %.4f | %8.3f | %.3f | %.2f | %.1f", r, sqrt(m2), area, w1090 / 2.5631, sqrt(m2) / r, m4 / (m2 * m2), support))
    }
}
MainActor.assumeIsolated { run() }
