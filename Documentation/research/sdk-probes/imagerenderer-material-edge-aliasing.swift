import SwiftUI
let W = 513, H = 129
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
func moments(_ d: [Float]) -> (area: Float, sigma: Float, kurt: Float) {
    let a = d.reduce(0, +); let mu = d.enumerated().reduce(Float(0)) { $0 + Float($1.offset) * $1.element } / a
    let m2 = d.enumerated().reduce(Float(0)) { $0 + pow(Float($1.offset) - mu, 2) * $1.element } / a
    let m4 = d.enumerated().reduce(Float(0)) { $0 + pow(Float($1.offset) - mu, 4) * $1.element } / a
    return (a, sqrt(m2), m4 / (m2 * m2))
}
MainActor.assumeIsolated {
    let mats: [(String, Material)] = [("ultraThin", .ultraThinMaterial), ("thin", .thinMaterial), ("regular", .regularMaterial), ("thick", .thickMaterial), ("ultraThick", .ultraThickMaterial)]
    for scheme in [ColorScheme.light, .dark] {
        for (name, m) in mats {
            let s = row(HStack(spacing: 0) { Color.black; Color.white }.overlay { Color.clear.background(m) }.environment(\.colorScheme, scheme))
            let d = (1..<s.count).map { s[$0] - s[$0 - 1] }
            let mo = moments(Array(d[8..<(d.count - 8)]))
            print(String(format: "%@ %-10@: black→%.3f white→%.3f transmission %.3f | edge-derivative σ %.1f px, kurtosis %.2f", scheme == .light ? "light" : "dark ", name, s[30], s[W - 30], s[W - 30] - s[30], mo.sigma, mo.kurt))
        }
    }
    // Downsampling evidence: bars of width w; response area per unit bar width
    for w in [1, 2, 3, 4, 6, 8, 16] {
        var areas: [String] = []
        for off in 0..<4 {
            let base = row(Color.black.overlay { Color.clear.background(.regularMaterial) })
            let b = row(Color.black.overlay(alignment: .leading) { Rectangle().fill(.white).frame(width: CGFloat(w)).offset(x: CGFloat(250 + off)) }.overlay { Color.clear.background(.regularMaterial) })
            let a = zip(b, base).map { $0 - $1 }.reduce(0, +)
            areas.append(String(format: "%.3f", a / Float(w)))
        }
        print("bar width \(w) px, offsets 0-3: response area / width = \(areas.joined(separator: " "))")
    }
}
