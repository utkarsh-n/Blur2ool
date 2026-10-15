import SwiftUI
// Does ImageRenderer capture backdrop effects (Material, glassEffect)? Stripes background, effect panel in the middle.
let W = 200, H = 100
struct Stripes: View { var body: some View { HStack(spacing: 0) { ForEach(0..<100, id: \.self) { i in (i % 2 == 0 ? Color.white : Color.black).frame(width: 2) } } } }
@MainActor func stats(_ v: some View, _ label: String) {
    let r = ImageRenderer(content: v.frame(width: CGFloat(W), height: CGFloat(H))); r.scale = 1; r.colorMode = .extendedLinear
    guard let cg = r.cgImage else { print("\(label): nil image"); return }
    var px = [Float](repeating: 0, count: cg.width * cg.height * 4)
    px.withUnsafeMutableBytes { b in
        let ctx = CGContext(data: b.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 32, bytesPerRow: cg.width * 16,
                            space: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    }
    func rowStats(_ y: Int, _ x0: Int, _ x1: Int) -> (Float, Float, Float, Float) {
        let vals = (x0..<x1).map { x -> (Float, Float, Float) in let i = (y * cg.width + x) * 4; return (px[i], px[i+1], px[i+2]) }
        let g = vals.map { $0.1 }
        let m = g.reduce(0, +) / Float(g.count)
        return (m, g.max()! - g.min()!, vals.map { $0.0 }.reduce(0, +) / Float(g.count), vals.map { $0.2 }.reduce(0, +) / Float(g.count))
    }
    let c = rowStats(H / 2, 80, 120), o = rowStats(10, 80, 120)
    print(String(format: "%@: centre G mean %.3f, G range %.3f, R/B mean %.3f/%.3f | outside G range %.3f", label, c.0, c.1, c.2, c.3, o.1))
}
MainActor.assumeIsolated {
    stats(Stripes(), "stripes only")
    stats(Stripes().overlay { Rectangle().fill(.clear).frame(width: 80, height: 40).background(.ultraThinMaterial) }, "ultraThinMaterial")
    stats(Stripes().overlay { Color.clear.frame(width: 80, height: 40).glassEffect(.regular, in: .rect) }, "glassEffect(.regular)")
    stats(Stripes().overlay { Stripes().frame(width: 80, height: 40).clipped().blur(radius: 4, opaque: true) }, "blur(4) on a copy")
}
