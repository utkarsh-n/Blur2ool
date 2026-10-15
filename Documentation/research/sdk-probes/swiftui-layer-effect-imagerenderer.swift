import SwiftUI
let N = 129
@MainActor func lsf(_ R: Float, lib: ShaderLibrary) -> [Float] {
    let v = ZStack { Color.clear; Rectangle().fill(.white).frame(width: 1) }
        .frame(width: CGFloat(N), height: CGFloat(N))
        .layerEffect(lib.boxH(.float(R)), maxSampleOffset: CGSize(width: CGFloat(R), height: 0))
    let r = ImageRenderer(content: v); r.scale = 1; r.colorMode = .extendedLinear
    let cg = r.cgImage!
    var px = [Float](repeating: 0, count: cg.width * cg.height * 4)
    px.withUnsafeMutableBytes { b in
        let ctx = CGContext(data: b.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 32, bytesPerRow: cg.width * 16,
                            space: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    }
    return (0..<cg.width).map { px[((cg.height / 2) * cg.width + $0) * 4 + 3] }
}
MainActor.assumeIsolated {
    let lib = ShaderLibrary(url: URL(fileURLWithPath: CommandLine.arguments[1]))
    for R: Float in [2, 5] {
        let l = lsf(R, lib: lib)
        let nz = l.enumerated().filter { $0.element > 1e-4 }
        print("box R=\(Int(R)): nonzero px \(nz.count) (expect \(2 * Int(R) + 1)), values \(Set(nz.map { String(format: "%.4f", $0.element) }).sorted()), area \(String(format: "%.4f", l.reduce(0, +))), expect each \(String(format: "%.4f", 1 / Float(2 * Int(R) + 1)))")
    }
}
