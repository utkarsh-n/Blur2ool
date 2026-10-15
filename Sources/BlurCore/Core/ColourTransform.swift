import Foundation

// FROZEN — ARCHITECTURE.md §5.4. Transfer functions, half rounding, the colour/alpha pre- and post-passes
// (ARCHITECTURE §4.2, mirrored exactly by B2Common.metal) and the deterministic noise hash (`b2_pcg`).

public enum SRGB {
    /// IEC 61966-2-1 encode (linear → encoded). The formula continues above 1 (HDR) and its linear segment continues
    /// below 0, exactly as `b2_srgb_encode` does on the GPU.
    public static func encode(_ l: Double) -> Double { l <= 0.0031308 ? 12.92 * l : 1.055 * pow(l, 1 / 2.4) - 0.055 }
    public static func decode(_ e: Double) -> Double { e <= 0.04045 ? e / 12.92 : pow((e + 0.055) / 1.055, 2.4) }
    /// 8-bit code value of a linear value, clipped to 0…255.
    public static func code8(linear l: Double) -> Int { Int((Swift.min(Swift.max(encode(l), 0), 1) * 255).rounded()) }
}

public enum HalfFloat {
    public static func round(_ x: Float) -> Float { Float(Float16(x)) }
    /// Spacing of fp16 values at |x|: the "1 ulp16" of the parity tolerances (ARCHITECTURE §7).
    public static func ulp(_ x: Float) -> Float {
        let h = Float16(abs(x))
        return h.isFinite ? Float(h.nextUp) - Float(h) : .infinity
    }
}

/// Rec. 709 luma on whatever values it is given (linear light or encoded, per the active colour space).
public enum Luma {
    public static func rec709(_ p: SIMD4<Float>) -> Float { 0.2126 * p.x + 0.7152 * p.y + 0.0722 * p.z }
}

/// The pre- and post-passes around every blur (ARCHITECTURE §4.2). Blur kernels never know the colour space or alpha mode.
public enum ColourTransform {
    public static func needsPasses(_ s: SilentSettings) -> Bool { s.colourSpace == .srgbEncoded || s.alphaMode == .straight }

    /// Before the blur: un-premultiply when straight alpha or sRGB-encoded; encode RGB when sRGB-encoded;
    /// re-premultiply when sRGB-encoded with premultiplied alpha.
    public static func pre(_ p: SIMD4<Float>, _ s: SilentSettings) -> SIMD4<Float> {
        let srgb = s.colourSpace == .srgbEncoded, straight = s.alphaMode == .straight
        var c = (srgb || straight) ? unpremultiply(p) : p
        if srgb { c = SIMD4(encode(c.x), encode(c.y), encode(c.z), c.w) }
        if srgb && !straight { c = premultiply(c) }
        return c
    }
    /// After the blur: the exact inverse of `pre`.
    public static func post(_ p: SIMD4<Float>, _ s: SilentSettings) -> SIMD4<Float> {
        let srgb = s.colourSpace == .srgbEncoded, straight = s.alphaMode == .straight
        var c = (srgb && !straight) ? unpremultiply(p) : p
        if srgb { c = SIMD4(decode(c.x), decode(c.y), decode(c.z), c.w) }
        if srgb || straight { c = premultiply(c) }
        return c
    }
    public static func pre(_ image: ImageBuffer, _ s: SilentSettings) -> ImageBuffer {
        needsPasses(s) ? image.map { pre($0, s) } : image
    }
    public static func post(_ image: ImageBuffer, _ s: SilentSettings) -> ImageBuffer {
        needsPasses(s) ? image.map { post($0, s) } : image
    }
    /// Colour of a fully transparent pixel is 0 (SPEC P19).
    public static func unpremultiply(_ p: SIMD4<Float>) -> SIMD4<Float> {
        p.w > 0 ? SIMD4(p.x / p.w, p.y / p.w, p.z / p.w, p.w) : .zero
    }
    public static func premultiply(_ p: SIMD4<Float>) -> SIMD4<Float> { SIMD4(p.x * p.w, p.y * p.w, p.z * p.w, p.w) }
    private static func encode(_ v: Float) -> Float { Float(SRGB.encode(Double(v))) }
    private static func decode(_ v: Float) -> Float { Float(SRGB.decode(Double(v))) }
}

/// PCG hash, bit-identical to `b2_pcg` / `b2_uniform` in B2Shared.h (stochastic blurs, procedural noise).
public enum NoiseHash {
    public static func pcg(_ v: UInt32) -> UInt32 {
        let state = v &* 747_796_405 &+ 2_891_336_453
        let word = ((state >> ((state >> 28) &+ 4)) ^ state) &* 277_803_737
        return (word >> 22) ^ word
    }
    /// Uniform in [0, 1] for pixel (x, y) and a seed.
    public static func uniform(x: UInt32, y: UInt32, seed: UInt32) -> Float {
        Float(pcg(x ^ pcg(y ^ pcg(seed)))) * (1.0 / 4_294_967_296.0)
    }
}
