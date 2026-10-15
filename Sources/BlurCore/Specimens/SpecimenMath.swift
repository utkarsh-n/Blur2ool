import Foundation

// OWNER: TESTIMAGES. BlurCore's own transcendental functions and random streams for the test images (ARCHITECTURE §5.6,
// review fix E-22). Every canvas must be bit-identical on the Mac and on the phone, so generators may use only +, −, ×, ÷,
// √ (all correctly rounded by IEEE 754) and the functions below, which are built from those operations alone, in a fixed
// order. Nothing here calls the platform's libm (`sin`, `cos`, `exp`, `log`, `pow`, `atan2`), whose last bits may differ
// between macOS and iOS releases. Accuracy is ≈ 1 ulp of Double over the ranges the generators use; the point is not
// accuracy but that the same inputs give the same bits everywhere.

public enum SpecimenMath {
    public static let pi = 3.141592653589793238462643383279502884
    public static let twoPi = 6.283185307179586476925286766559005768
    public static let halfPi = 1.570796326794896619231321691639751442
    public static let ln2 = 0.693147180559945309417232121458176568

    // Cody–Waite splits: hi parts carry few significant bits, so k·hi is exact for |k| < 2^20.
    private static let halfPiHi = 1.57079632673412561417e+00   // fdlibm pio2_1: 33 significant bits of π/2
    private static let halfPiMid = 6.07710050630396597660e-11  // fdlibm pio2_2: the next 33 bits
    private static let halfPiLo = 2.02226624879595063154e-21   // fdlibm pio2_2t: the rest (hi + mid + lo − π/2 ≈ 10^−37)
    private static let ln2Hi = 6.93147180369123816490e-01      // fdlibm ln2_hi: 32 significant bits of ln 2
    private static let ln2Lo = 1.90821492927058770002e-10      // fdlibm ln2_lo

    // MARK: Trigonometry

    /// sin(x) for |x| < 2^20 (the generators stay below 10^4).
    public static func sin(_ x: Double) -> Double {
        let (r, q) = reduceHalfPi(x)
        switch q & 3 {
        case 0: return sinKernel(r)
        case 1: return cosKernel(r)
        case 2: return -sinKernel(r)
        default: return -cosKernel(r)
        }
    }

    /// cos(x) for |x| < 2^20.
    public static func cos(_ x: Double) -> Double {
        let (r, q) = reduceHalfPi(x)
        switch q & 3 {
        case 0: return cosKernel(r)
        case 1: return -sinKernel(r)
        case 2: return -cosKernel(r)
        default: return sinKernel(r)
        }
    }

    /// x = q·π/2 + r with |r| ≤ π/4 (three-part Cody–Waite reduction).
    private static func reduceHalfPi(_ x: Double) -> (Double, Int) {
        let q = (x / halfPi).rounded(.toNearestOrEven)
        let r = ((x - q * halfPiHi) - q * halfPiMid) - q * halfPiLo
        return (r, Int(q))
    }

    /// Taylor series of sin on [−π/4, π/4] through x^19 (truncation < 10^−19), Horner form.
    private static func sinKernel(_ x: Double) -> Double {
        let z = x * x
        var p = -1.0 / 121_645_100_408_832_000.0                      // −1/19!
        p = p * z + 1.0 / 355_687_428_096_000.0                        // 1/17!
        p = p * z - 1.0 / 1_307_674_368_000.0                          // −1/15!
        p = p * z + 1.0 / 6_227_020_800.0                              // 1/13!
        p = p * z - 1.0 / 39_916_800.0                                 // −1/11!
        p = p * z + 1.0 / 362_880.0                                    // 1/9!
        p = p * z - 1.0 / 5_040.0                                      // −1/7!
        p = p * z + 1.0 / 120.0                                        // 1/5!
        p = p * z - 1.0 / 6.0                                          // −1/3!
        return x + x * z * p
    }

    /// Taylor series of cos on [−π/4, π/4] through x^20, Horner form.
    private static func cosKernel(_ x: Double) -> Double {
        let z = x * x
        var p = 1.0 / 2_432_902_008_176_640_000.0                     // 1/20!
        p = p * z - 1.0 / 6_402_373_705_728_000.0                      // −1/18!
        p = p * z + 1.0 / 20_922_789_888_000.0                         // 1/16!
        p = p * z - 1.0 / 87_178_291_200.0                             // −1/14!
        p = p * z + 1.0 / 479_001_600.0                                // 1/12!
        p = p * z - 1.0 / 3_628_800.0                                  // −1/10!
        p = p * z + 1.0 / 40_320.0                                     // 1/8!
        p = p * z - 1.0 / 720.0                                        // −1/6!
        p = p * z + 1.0 / 24.0                                         // 1/4!
        p = p * z - 0.5                                                // −1/2!
        return 1.0 + z * p
    }

    /// atan(t) for t ≥ 0.
    private static func atanNonNegative(_ t: Double) -> Double {
        // Reduce to [0, 1], then to |u| ≤ tan(π/8) with atan(t) = π/4 + atan((t − 1)/(t + 1)), then halve the angle once:
        // atan(u) = 2·atan(u / (1 + √(1 + u²))), |v| ≤ 0.199. The odd series then converges below 10^−18 in 13 terms.
        var base = 0.0, sign = 1.0, u = t
        if u > 1 { u = 1 / u; base = halfPi; sign = -1 }
        var offset = 0.0
        if u > 0.41421356237309503 { u = (u - 1) / (u + 1); offset = pi / 4 }
        let v = u / (1 + (1 + u * u).squareRoot())
        let z = v * v
        var p = 1.0 / 25.0
        var k = 23.0
        while k >= 3 { p = p * (-z) + 1.0 / k; k -= 2 }               // 1/3 − z/5 + z²/7 … alternating
        let atanV = v - v * z * p
        let a = offset + 2 * atanV
        return base + sign * a
    }

    /// atan2(y, x) in (−π, π], screen convention irrelevant here (callers pass y down).
    public static func atan2(_ y: Double, _ x: Double) -> Double {
        if x == 0 && y == 0 { return 0 }
        if x == 0 { return y > 0 ? halfPi : -halfPi }
        let a = atanNonNegative(Swift.abs(y) / Swift.abs(x))
        if x > 0 { return y < 0 ? -a : a }
        return y < 0 ? -(pi - a) : pi - a
    }

    // MARK: Exponential and logarithm

    /// e^x for |x| < 700.
    public static func exp(_ x: Double) -> Double {
        if x > 709 { return .infinity }
        if x < -745 { return 0 }
        let k = (x / ln2).rounded(.toNearestOrEven)
        let r = (x - k * ln2Hi) - k * ln2Lo                             // |r| ≤ ln2/2
        var p = 1.0 / 6_227_020_800.0                                   // Taylor through r^13 (error < 10^−18), Horner
        p = p * r + 1.0 / 479_001_600.0
        p = p * r + 1.0 / 39_916_800.0
        p = p * r + 1.0 / 3_628_800.0
        p = p * r + 1.0 / 362_880.0
        p = p * r + 1.0 / 40_320.0
        p = p * r + 1.0 / 5_040.0
        p = p * r + 1.0 / 720.0
        p = p * r + 1.0 / 120.0
        p = p * r + 1.0 / 24.0
        p = p * r + 1.0 / 6.0
        p = p * r + 0.5
        p = p * r + 1.0
        p = p * r + 1.0
        return scaleByPowerOfTwo(p, Int(k))
    }

    /// ln(x) for x > 0 (−∞ at 0, NaN below).
    public static func log(_ x: Double) -> Double {
        if x.isNaN || x < 0 { return .nan }
        if x == 0 { return -.infinity }
        if x.isInfinite { return .infinity }
        // x = m·2^e with m ∈ [1, 2) exactly (bit fields), then m ∈ [√½, √2) by moving one factor of two.
        var e = Int(x.exponent)
        var m = x.significand
        if m > 1.4142135623730951 { m *= 0.5; e += 1 }
        // ln m = 2·atanh(s), s = (m − 1)/(m + 1), |s| ≤ 0.1716: the odd series converges below 10^−18 in 12 terms.
        let s = (m - 1) / (m + 1)
        let z = s * s
        var p = 1.0 / 23.0
        var k = 21.0
        while k >= 1 { p = p * z + 1.0 / k; k -= 2 }
        let lnM = 2 * s * p
        let de = Double(e)
        return de * ln2Hi + (de * ln2Lo + lnM)
    }

    /// x^y for x > 0 as e^(y·ln x); 0^y = 0 for y > 0.
    public static func pow(_ x: Double, _ y: Double) -> Double {
        if x == 0 { return y > 0 ? 0 : (y == 0 ? 1 : .infinity) }
        return exp(y * log(x))
    }

    /// x·2^k, exact (no rounding unless the result is subnormal).
    public static func scaleByPowerOfTwo(_ x: Double, _ k: Int) -> Double {
        var v = x, n = k
        while n > 1000 { v *= Double(sign: .plus, exponent: 1000, significand: 1); n -= 1000 }
        while n < -1000 { v *= Double(sign: .plus, exponent: -1000, significand: 1); n += 1000 }
        return v * Double(sign: .plus, exponent: n, significand: 1)
    }

    // MARK: Colour

    /// IEC 61966-2-1 decode (encoded → linear) with BlurCore's own power function: the "Encoded ramp" option.
    public static func srgbDecode(_ e: Double) -> Double {
        e <= 0.04045 ? e / 12.92 : pow((e + 0.055) / 1.055, 2.4)
    }

    /// frac(t) = t − ⌊t⌋ ∈ [0, 1).
    public static func fraction(_ t: Double) -> Double { t - t.rounded(.down) }

    /// ⌊a / b⌋ for integers, b > 0 (floor division, correct for negative a).
    public static func floorDiv(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : -((-a + b - 1) / b) }
}

/// A deterministic PCG32 stream (O'Neill 2014: 64-bit LCG, XSH-RR output). Integer arithmetic only, so it is the same on
/// every platform. Used for the Night City lights (seed 7) and the per-image noise.
public struct SpecimenRandom: Sendable, Hashable {
    private var state: UInt64
    private let increment: UInt64

    public init(seed: UInt64, stream: UInt64 = 0x2545_F491) {
        increment = (stream << 1) | 1
        state = 0
        _ = next32()
        state &+= seed
        _ = next32()
    }

    public mutating func next32() -> UInt32 {
        let old = state
        state = old &* 6_364_136_223_846_793_005 &+ increment
        let xorShifted = UInt32(truncatingIfNeeded: ((old >> 18) ^ old) >> 27)
        let rot = UInt32(truncatingIfNeeded: old >> 59)
        return (xorShifted >> rot) | (xorShifted << ((~rot &+ 1) & 31))
    }

    /// Uniform in [0, 1) with 53 random bits.
    public mutating func nextUnit() -> Double {
        let hi = UInt64(next32() >> 5), lo = UInt64(next32() >> 6)       // 27 + 26 bits
        return Double(hi << 26 | lo) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// Uniform integer in 0..<bound (bound > 0), by rejection (no modulo bias).
    public mutating func nextInt(below bound: Int) -> Int {
        precondition(bound > 0)
        let b = UInt64(bound)
        let limit = (UInt64(1) << 32) - ((UInt64(1) << 32) % b)
        while true {
            let v = UInt64(next32())
            if v < limit { return Int(v % b) }
        }
    }

    /// Log-uniform in [lo, hi): lo·(hi/lo)^u, with BlurCore's own exp and log.
    public mutating func nextLogUniform(_ lo: Double, _ hi: Double) -> Double {
        let u = nextUnit()
        return Swift.min(hi, lo * SpecimenMath.exp(u * SpecimenMath.log(hi / lo)))
    }
}

/// Per-pixel noise keyed by a pixel's offset from the window centre and a seed (so a feature's neighbourhood carries the
/// same noise at N = 894 and N = 810, and panning reveals consistent noise). Integer hashing (NoiseHash.pcg) plus
/// Box–Muller with BlurCore's own log, cos and √.
public enum SpecimenNoise {
    /// Two independent 32-bit words for pixel (dx, dy) relative to c.
    public static func words(dx: Int, dy: Int, seed: UInt32) -> (UInt32, UInt32) {
        let ux = UInt32(bitPattern: Int32(truncatingIfNeeded: dx)), uy = UInt32(bitPattern: Int32(truncatingIfNeeded: dy))
        let a = NoiseHash.pcg(ux &+ NoiseHash.pcg(uy &+ NoiseHash.pcg(seed)))
        let b = NoiseHash.pcg(a ^ 0x9E37_79B9 ^ NoiseHash.pcg(seed &+ 0x632B_E5AB))
        return (a, b)
    }

    /// Uniform in [0, 1).
    public static func uniform(dx: Int, dy: Int, seed: UInt32) -> Double {
        Double(words(dx: dx, dy: dy, seed: seed).0) * (1.0 / 4_294_967_296.0)
    }

    /// Standard normal N(0, 1) (Box–Muller, cosine branch).
    public static func gaussian(dx: Int, dy: Int, seed: UInt32) -> Double {
        let (a, b) = words(dx: dx, dy: dy, seed: seed)
        let u1 = (Double(a) + 1) * (1.0 / 4_294_967_296.0)               // (0, 1]
        let u2 = Double(b) * (1.0 / 4_294_967_296.0)                     // [0, 1)
        return (-2 * SpecimenMath.log(u1)).squareRoot() * SpecimenMath.cos(SpecimenMath.twoPi * u2)
    }
}
