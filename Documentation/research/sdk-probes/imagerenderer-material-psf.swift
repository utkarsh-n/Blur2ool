import SwiftUI
// Offscreen (ImageRenderer) PSF of SwiftUI Materials: white 1-px line on black, material panel over it.
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
    return (0..<cg.width).map { px[((cg.height / 2) * cg.width + $0) * 4 + 1] }   // green channel
}
MainActor.assumeIsolated {
    let mats: [(String, Material)] = [("ultraThin", .ultraThinMaterial), ("thin", .thinMaterial), ("regular", .regularMaterial), ("thick", .thickMaterial), ("ultraThick", .ultraThickMaterial)]
    for (name, m) in mats {
        for scheme in [ColorScheme.dark, .light] {
            let base = row(Color.black.overlay { Color.clear.background(m) }.environment(\.colorScheme, scheme))
            let line = row(Color.black.overlay { Rectangle().fill(.white).frame(width: 1) }.overlay { Color.clear.background(m) }.environment(\.colorScheme, scheme))
            let d = zip(line, base).map { $0 - $1 }
            let area = d.reduce(0, +)
            let mean = d.enumerated().reduce(Float(0)) { $0 + Float($1.offset) * $1.element } / area
            let m2 = d.enumerated().reduce(Float(0)) { $0 + pow(Float($1.offset) - mean, 2) * $1.element } / area
            let m4 = d.enumerated().reduce(Float(0)) { $0 + pow(Float($1.offset) - mean, 4) * $1.element } / area
            let seg = Array(base[60..<196]); print(String(format: "  [base row range over black: %.4f]", seg.max()! - seg.min()!)); print(String(format: "%-10@ %@: background level %.3f, line response area %.3f (line passes %.0f%%), σ_eff %.2f px, kurtosis %.2f, peak %.4f",
                         name, scheme == .dark ? "dark " : "light", base[W / 2], area, area * 100, sqrt(m2), m4 / (m2 * m2), d.max()!))
        }
    }
}
