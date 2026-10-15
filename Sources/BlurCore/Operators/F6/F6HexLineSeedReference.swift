import Foundation

// OWNER: FAM-F6 (seed written by SKEL, review fix E-15). The CPU reference of the MRT seed `b2_f6_hexlines_mrt_fs`
// (App/GPU/Shaders/F6Lens.metal): pass 1 of the polygonal bokeh's four line blurs (SPEC §5.3 D),
//   T1 = blur(src, ↑)      T2 = ½·[blur(src, ↑) + blur(src, ↘)],
// each blur a one-sided line of `taps` bilinear samples of weight 1/taps, the first tap half a step out, step R/taps.
// It exists so that GPUCommandRecorder's two-attachment render encoder is proven, with parity on both attachments,
// before wave 1 (blur-gpucheck and Tests/BlurGPUTests/SKELSeeds run it through BlurGPU's F6HexLineSeed).
// TODO(FAM-F6): replace with polygonal-bokeh's operator (both passes, blades, rotation, curvature) and its parity cases.
public enum F6HexLineSeedReference {
    public static let taps = 16
    /// Hexagon circumradius R in px (SPEC §5.3 D).
    public static let circumradius = 16.0
    /// Chebyshev reach of one output pixel: the farthest tap plus one texel of bilinear footprint.
    public static var supportRadius: Int { Int(circumradius.rounded(.up)) + 1 }

    /// The ↑ taps, then the ↘ taps, as the Float texel offsets the GPU receives: (0, −(i + ½)·s) and
    /// (cos 30°·(i + ½)·s, sin 30°·(i + ½)·s) with s = R / taps (y down, so ↘ is +x, +y).
    public static func offsets(radius: Double = circumradius, taps: Int = taps) -> [SIMD2<Float>] {
        let step = radius / Double(taps), c30 = 3.0.squareRoot() / 2
        let up = (0..<taps).map { SIMD2<Float>(0, Float(-(Double($0) + 0.5) * step)) }
        let diag = (0..<taps).map { SIMD2<Float>(Float(c30 * (Double($0) + 0.5) * step), Float(0.5 * (Double($0) + 0.5) * step)) }
        return up + diag
    }

    /// T1 and T2 over `region` (window pixels) of `input` (the half-rounded window), accumulated in Double from the same
    /// sample positions the GPU computes (Float centre + Float offset), with the hardware's sub-texel rule from `options`;
    /// outputs rounded to fp16 when `options.emulateHalfStorage` (what the render targets store).
    public static func passOne(_ input: ImageBuffer, region: PixelRegion, edge: EdgeMode,
                               options: ReferenceOptions) -> (t1: ImageBuffer, t2: ImageBuffer) {
        let table = offsets()
        let w = 1.0 / Double(taps)
        var t1 = ImageBuffer(width: region.size.width, height: region.size.height)
        var t2 = t1
        for y in 0..<region.size.height {
            for x in 0..<region.size.width {
                let px = region.origin.x + x, py = region.origin.y + y
                let centre = SIMD2<Float>(Float(px) + 0.5, Float(py) + 0.5)
                var up = SIMD4<Double>.zero, diag = SIMD4<Double>.zero
                for i in 0..<taps {
                    let a = centre + table[i], b = centre + table[taps + i]
                    up += input.bilinear(Double(a.x), Double(a.y), edge: edge, subTexelBits: options.subTexelBits,
                                         rounding: options.subTexelRounding) * w
                    diag += input.bilinear(Double(b.x), Double(b.y), edge: edge, subTexelBits: options.subTexelBits,
                                           rounding: options.subTexelRounding) * w
                }
                t1[x, y] = SIMD4<Float>(up)
                t2[x, y] = SIMD4<Float>((up + diag) * 0.5)
            }
        }
        return options.emulateHalfStorage ? (t1.roundedToHalf(), t2.roundedToHalf()) : (t1, t2)
    }
}
