import SwiftUI
let W = 257, H = 129
@MainActor func row(_ v: some View) -> [Float] {
    let r = ImageRenderer(content: v.frame(width: CGFloat(W), height: CGFloat(H))); r.scale = 1; r.colorMode = .extendedLinear
    let cg = r.cgImage!
    var px = [Float](repeating: 0, count: cg.width * cg.height * 4)
    px.withUnsafeMutableBytes { b in
        let ctx = CGContext(data: b.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 32, bytesPerRow: cg.width * 16,
                            space: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    }
    return (0..<cg.width).map { px[((cg.height / 2) * cg.width + $0) * 4 + 1] }
}
struct Stripes: View { var body: some View { HStack(spacing: 0) { ForEach(0..<64, id: \.self) { i in (i % 2 == 0 ? Color.white : Color.black).frame(width: 2) } }.frame(width: 256) } }
MainActor.assumeIsolated {
    let m = Material.regularMaterial
    let backs: [(String, AnyView)] = [
        ("black", AnyView(Color.black)), ("white", AnyView(Color.white)), ("grey50", AnyView(Color(white: 0.5))),
        ("stripes", AnyView(Stripes())),
        ("step", AnyView(HStack(spacing: 0) { Color.black; Color.white })),
        ("line", AnyView(Color.black.overlay { Rectangle().fill(.white).frame(width: 1) })),
        ("bar16", AnyView(Color.black.overlay { Rectangle().fill(.white).frame(width: 16) })),
    ]
    for (name, b) in backs {
        for (pname, panel) in [("full", true), ("panel", false)] {
            let v = b.overlay { if panel { Color.clear.background(m) } else { Color.clear.frame(width: 160, height: 60).background(m) } }
            let r = row(v)
            let xs = [20, 60, 100, 120, 128, 136, 156, 196, 236]
            print("\(name.padding(toLength: 8, withPad: " ", startingAt: 0)) \(pname.padding(toLength: 5, withPad: " ", startingAt: 0)): " + xs.map { String(format: "%d:%.3f", $0, r[$0]) }.joined(separator: " "))
        }
    }
}
