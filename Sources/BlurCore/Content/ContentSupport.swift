import Foundation

// OWNER: CONTENT-LAYERS. Shared helpers for the floor templates, rail, pills, trace scripts, lessons and field guide
// (ARCHITECTURE §5.11; SPEC §5.2). Every symbol here carries a `Content` prefix because BlurCore is one module shared by
// thirteen operator areas; nothing here extends a frozen type.

// MARK: - Template class (SPEC §5.2)

/// The row of SPEC §5.2 that decides what each floor's slots contain, from the RESOLVED variant's algorithm class,
/// the entry's tier and its verdict.
public enum ContentTemplateClass: String, Sendable, Codable, Hashable, CaseIterable {
    case separableFIR, gather2D, skewSeparable, recursive, runningSum, sparseIterated, spaceVariant, adaptive, rank,
         iterativePDE, globalFFT, stochastic, temporal, system, derived, atlas

    public static func of(_ op: any BlurOperator, _ request: OperatorRequest) -> ContentTemplateClass {
        let entry = op.entry
        if entry.tier == .tier3 { return .atlas }
        if entry.tier == .system { return .system }
        let resolved = op.resolveVariant(request).variant
        let algorithm = entry.variant(resolved)?.algorithmClass ?? entry.algorithmClass
        switch algorithm {
        case .separableFIR: return .separableFIR
        case .gather2D: return .gather2D
        case .skewSeparable: return .skewSeparable
        case .recursive: return .recursive
        case .runningSum: return .runningSum
        case .sparseIterated: return .sparseIterated
        case .spaceVariantGather: return .spaceVariant
        case .adaptiveWeighted: return .adaptive
        case .selection: return .rank
        case .iterativePDE: return .iterativePDE
        case .globalFFT: return .globalFFT
        case .stochastic: return .stochastic
        case .temporal: return .temporal
        case .system: return .system
        case .derived: return .derived
        case .atlasOnly: return .atlas
        }
    }

    /// True for classes whose PSF depends on where the probe is (SPEC §4.1.4 "shift invariance lesson").
    public var isLocal: Bool { [.spaceVariant, .adaptive, .temporal].contains(self) }

    /// The unit one `Next …` press reveals inside a pass (SPEC §6.5).
    public var subStepNoun: (singular: String, plural: String) {
        switch self {
        case .rank: ("compare-exchange", "compare-exchanges")
        case .iterativePDE: ("iteration", "iterations")
        case .adaptive: ("tap", "taps")
        case .recursive: ("recursion step", "recursion steps")
        case .globalFFT: ("frequency", "frequencies")
        case .gather2D, .spaceVariant, .stochastic, .temporal: ("sample", "samples")
        default: ("fetch", "fetches")
        }
    }

    /// The `Next …` label for a sub-step of this class (SPEC §6.2 item 4).
    public var nextLabel: String {
        switch self {
        case .iterativePDE: "Next iteration"
        case .adaptive, .skewSeparable, .rank: "Next tap"
        default: "Next fetch"
        }
    }
}

// MARK: - Number styles (all display formatting goes through the frozen NumberStyle)

public enum ContentStyle {
    public static let px1 = NumberStyle.decimals(1, unit: "px", spokenUnit: "pixels")
    public static let px2 = NumberStyle.decimals(2, unit: "px", spokenUnit: "pixels")
    public static let pt1 = NumberStyle.decimals(1, unit: "pt", spokenUnit: "points")
    public static let pt2 = NumberStyle.decimals(2, unit: "pt", spokenUnit: "points")
    public static let frequency = NumberStyle.decimals(4, unit: "c/px", spokenUnit: "cycles per pixel")
    public static let weight = NumberStyle.decimals(5)
    public static let value3 = NumberStyle.decimals(3)
    public static let value4 = NumberStyle.decimals(4)
    /// The one probe-value precision used everywhere (SPEC §4.1.3 loupe; rail PIXEL; floor 7).
    public static let probe = NumberStyle.significant(3)
    /// The probe-value style for one value: three significant digits, and "0.000" for an exact zero.
    public static func probe(_ value: Double) -> NumberStyle { value == 0 ? .decimals(3) : .significant(3) }
    public static let response = NumberStyle.significant(2)
    /// A response value at the precision the SPEC prints: −0.217 (≥ 0.1), −0.047 and −0.0012 (two significant digits),
    /// −0.0010 (four decimals between 10⁻⁴ and 10⁻³), 7.1·10⁻⁴ below.
    public static func response(_ v: Double) -> NumberStyle {
        let a = abs(v)
        if a >= 0.1 { return .significant(3) }
        if a >= 1e-3 || a == 0 { return .significant(2) }
        if a >= 9.5e-4 { return .decimals(4) }
        return .significant(2)
    }
    public static let percent = NumberStyle.significant(3, unit: "%", spokenUnit: "percent")
    public static let ms = NumberStyle.decimals(2, unit: "ms", spokenUnit: "milliseconds")
    public static let megabytes = NumberStyle.decimals(1, unit: "MB", spokenUnit: "megabytes")
    public static let bytes = NumberStyle.integer(unit: "B", spokenUnit: "bytes")
    public static let ratio = NumberStyle.decimals(2)
    public static let kurtosis = NumberStyle(precision: .decimals(2), explicitPlus: true)
    public static let code8 = NumberStyle.integer(unit: "/255", spokenUnit: "out of 255")
    public static let ulp = NumberStyle.decimals(1, unit: "ulp16", spokenUnit: "half-float ulps")
    public static let lsb = NumberStyle.decimals(0, unit: "LSB", spokenUnit: "eight-bit steps")
    public static func count(_ singular: String, _ plural: String) -> NumberStyle { .integer(noun: CountNoun(singular, plural)) }
    public static let taps = count("tap", "taps")
    public static let fetches = count("fetch", "fetches")
    public static let passes = count("pass", "passes")
    public static let samples = count("sample", "samples")
    public static let threads = count("thread", "threads")
    public static let groups = count("threadgroup", "threadgroups")

    /// "−0.0012" with its unit and a computed badge in one call.
    public static func computed(_ value: Double, _ style: NumberStyle, caption: String? = nil) -> BadgedValue {
        .number(value, style, .computed, caption: caption)
    }

    /// A count rendered as a rail-chip code ("2×", "L4") whose number is still badged data.
    public static func chipCount(_ value: Double, suffix: String = "×", prefix: String = "", spokenNoun: CountNoun,
                                 _ provenance: Provenance) -> BadgedValue {
        let style = NumberStyle.integer(noun: spokenNoun)
        return BadgedValue(value: value, text: prefix + NumberStyle.integer().text(value) + suffix, provenance: provenance,
                           spoken: style.spoken(value) + ", " + provenance.spokenPhrase(device: nil))
    }
}

// MARK: - Research measurements (shown on the phone only with their Mac label, SPEC §12.2 item 5)

public enum ContentResearch {
    /// The research Mac of 13–14 October 2026 (ARCHITECTURE header): Apple M1 Max, macOS 27.2.
    public static let mac: DeviceStamp = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 12)) ?? Date(timeIntervalSince1970: 0)
        return DeviceStamp(deviceModel: "Mac (Apple M1 Max)", gpuName: "Apple M1 Max", gpuFamily: "Apple7", osVersion: "macOS 27.2",
                           osBuild: "research", isSimulator: false, date: date, thermal: .nominal, lowPowerMode: false)
    }()

    /// A number MEASURED on the research Mac, never on this phone (`notThisDevice`).
    public static func measuredOnMac(_ value: Double, _ style: NumberStyle, source: String, caption: String? = nil,
                                     offscreen: Bool = false) -> BadgedValue {
        var v = BadgedValue.number(value, style, .measured, qualifiers: offscreen ? [.notThisDevice, .offscreen] : [.notThisDevice],
                                   source: SourceRef(source), device: mac, caption: caption)
        if offscreen { v = ContentOffscreen.mark(v) }
        return v
    }

    public static let calibrationSource = "live-calibration.md (MEASURED offscreen, macOS 27.2, M1 Max)"
    public static let stackSource = "stack-semantics.md §8 (the meanings of radius)"
    public static let catalogSource = "CATALOG.md §7 (pairs that teach)"
}

// MARK: - SwiftUI-derived values carry OFFSCREEN on every surface (SPEC §12.2 item 9; review fix P-34)

public enum ContentOffscreen {
    /// The caption every SwiftUI-derived value carries.
    public static let caption = "OFFSCREEN"

    /// Adds the `.offscreen` qualifier, the OFFSCREEN caption and the spoken word, idempotently.
    public static func mark(_ value: BadgedValue) -> BadgedValue {
        var v = value
        v.qualifiers.insert(.offscreen)
        if let c = v.caption {
            if !c.uppercased().contains(caption) { v.caption = c + " · " + caption }
        } else {
            v.caption = caption
        }
        if !v.spoken.lowercased().contains("offscreen") { v.spoken += ", offscreen" }
        return v
    }

    /// True when the value carries all three marks.
    public static func isMarked(_ value: BadgedValue) -> Bool {
        value.qualifiers.contains(.offscreen) && (value.caption ?? "").uppercased().contains(caption)
            && value.spoken.lowercased().contains("offscreen")
    }

    /// Tool conventions whose numbers come from SwiftUI renders (ImageRenderer fits).
    public static func isSwiftUITool(_ toolID: String) -> Bool { toolID.lowercased().hasPrefix("swiftui") }

    /// Calibrations whose subject is SwiftUI, or whose path is ImageRenderer.
    public static func isSwiftUIDerived(_ result: CalibrationResult) -> Bool {
        [.swiftUIBlur, .swiftUIShadow].contains(result.request.subject)
            || [.imageRendererCGImage, .imageRendererRenderInto].contains(result.request.path)
    }

    /// Catalog entries that ARE SwiftUI's own blur: every number derived from them is a SwiftUI measurement or model.
    public static func isSwiftUIEntry(_ id: BlurID) -> Bool { id.rawValue.hasPrefix("swiftui") }
}

// MARK: - Tool kernels (rail SLIDE `≈`; floor 1 `SAME σ, DIFFERENT KERNEL`)

public enum ContentToolKernels {
    /// True when the tool's blur for `blur` matches only σ: its kernel shape is known to differ (SwiftUI's large-radius
    /// kernel has excess kurtosis −0.45, MEASURED offscreen on macOS; closest model box³, INFERRED).
    public static func matchesOnlySigma(toolID: String, blur: BlurID) -> Bool {
        if ContentOffscreen.isSwiftUITool(toolID) { return !ContentOffscreen.isSwiftUIEntry(blur) }
        return false
    }
    public static let sameSigmaCaption = "SAME σ, DIFFERENT KERNEL"
    /// Appends a caption phrase once ("A · B"), case-insensitively.
    public static func addCaption(_ caption: String?, _ phrase: String) -> String {
        guard let c = caption, !c.isEmpty else { return phrase }
        return c.uppercased().contains(phrase.uppercased()) ? c : c + " · " + phrase
    }
}

// MARK: - Values

public enum ContentValues {
    /// The scalar shown for a pixel: Rec. 709 luma of the linear RGB (equals the channel value on grey images).
    public static func scalar(_ v: SIMD4<Double>) -> Double { 0.2126 * v.x + 0.7152 * v.y + 0.0722 * v.z }
    public static func scalar(_ v: SIMD4<Float>) -> Double { scalar(SIMD4<Double>(v)) }

    /// Title-cased tool name for a tool id when the conventions table does not know it ("swiftui" → "SwiftUI").
    public static func toolName(_ id: String, conventions: [ToolConvention]) -> String {
        if let c = conventions.first(where: { $0.id == id }) { return c.toolName }
        switch id.lowercased() {
        case "swiftui": return "SwiftUI"
        case "css": return "CSS"
        case "figma": return "Figma"
        case "photoshop": return "Photoshop"
        case "coreimage": return "Core Image"
        case "mps": return "Metal Performance Shaders"
        case "android": return "Android"
        case "flutter": return "Flutter"
        case "sketch": return "Sketch"
        case "gimp": return "GIMP"
        case "imagemagick": return "ImageMagick"
        default: return id.prefix(1).uppercased() + id.dropFirst()
        }
    }

    /// Plain words for the silent parameters.
    public static func words(_ c: ColourSpace) -> String { c == .linearLight ? "LINEAR LIGHT" : "sRGB-ENCODED" }
    public static func words(_ e: EdgeMode) -> String { e.rawValue.uppercased() }
    public static func words(_ a: AlphaMode) -> String { a == .premultiplied ? "PREMULTIPLIED" : "STRAIGHT" }
    public static func words(_ p: AccumulatorPrecision) -> String { p == .fp32 ? "fp32 ACCUMULATE" : "fp16 ACCUMULATE" }
    public static func words(_ f: IntermediateFormat) -> String { f.rawValue }
}

// MARK: - Kernel math the floors print (COMPUTED in Double)

public enum ContentKernelMath {
    /// Largest |w| normalised curve of a 1-D kernel as plot series.
    public static func stems(_ k: Kernel1D, normalisedToPeak: Bool = false, name: String = "taps",
                             provenance: Provenance = .computed) -> PlotSeries {
        let peak = normalisedToPeak ? Swift.max(k.weights.map(abs).max() ?? 1, 1e-300) : 1
        return PlotSeries(name: name, xs: k.weights.indices.map { k.offset($0) }, ys: k.weights.map { $0 / peak },
                          style: .stems, role: .primary, provenance: provenance)
    }

    /// The truncation analysis of Gaussian-family kernels: discrete mass the finite kernel drops (per axis and 2-D) and
    /// the continuous tail erfc(r/(σ√2)) (SPEC §5.3; review fix P-63). nil when the entry has no σ + truncation.
    public struct MassCut: Sendable, Hashable {
        public var radius: Int
        public var perAxis: Double
        public var twoD: Double
        public var continuous: Double
        public var discretisation: String
    }

    public static func massCut(_ op: any BlurOperator, _ request: OperatorRequest) -> MassCut? {
        let entry = op.entry
        guard entry.spec("truncation") != nil, let sigma = request.parameters.double("sigma") ?? entry.defaultParameters.double("sigma"),
              sigma > 0, let k = op.psf(at: PixelPoint(x: request.size.width / 2, y: request.size.height / 2), request, content: nil)?.kernel.marginalX
        else { return nil }
        let r = k.origin
        let discretisation = request.parameters.choice("discretisation") ?? "sampled"
        let inside: Double
        switch discretisation {
        case "integrated":
            inside = KernelMath.normalCDF((Double(r) + 0.5) / sigma) - KernelMath.normalCDF(-(Double(r) + 0.5) / sigma)
        case "lindeberg":
            let wide = KernelMath.gaussianLindeberg(sigma: sigma, truncation: 14)
            inside = (-r...r).reduce(0) { $0 + wide.weights[wide.origin + $1] }
        default:
            let wideR = Swift.max(r + 1, Int((14 * sigma).rounded(.up)) + 8)
            var total = 0.0, kept = 0.0
            for n in -wideR...wideR {
                let w = exp(-Double(n * n) / (2 * sigma * sigma))
                total += w
                if abs(n) <= r { kept += w }
            }
            inside = kept / total
        }
        let perAxis = Swift.max(0, 1 - inside)
        return MassCut(radius: r, perAxis: perAxis, twoD: 1 - (1 - perAxis) * (1 - perAxis),
                       continuous: KernelMath.gaussianMassBeyond(radius: r, sigma: sigma), discretisation: discretisation)
    }

    /// The Rákos pair table of a centred, symmetric integer kernel, and the largest |effective tap − stem| after the
    /// hardware quantizes each pair's fraction to `bits` (MODELED; review fix P-37).
    public struct PairAnalysis: Sendable, Hashable {
        public var table: LinearSampledTable
        public var maxTapError: Double
        public var bits: Int
        public var rounding: SubTexelRounding
        /// The per-pair fraction t = b/(a + b) as requested (COMPUTED) and as the hardware quantizes it (MODELED).
        public var requestedFractions: [Double]
        public var quantizedFractions: [Double]
    }

    public static func pairAnalysis(_ k: Kernel1D, bits: Int, rounding: SubTexelRounding) -> PairAnalysis? {
        let r = k.origin
        guard k.offsets == nil, k.tapCount == 2 * r + 1, r >= 1 else { return nil }
        for n in 1...r where abs(k.weights[r + n] - k.weights[r - n]) > 1e-12 { return nil }
        let table = KernelMath.linearSampledTable(k)
        let scale = Double(1 << bits)
        let rule: FloatingPointRoundingRule = rounding == .nearest ? .toNearestOrAwayFromZero : .towardZero
        var worst = 0.0
        var requested: [Double] = [], quantized: [Double] = []
        var n = 1, i = 1
        while n <= r {
            let a = k.weights[r + n], b = n + 1 <= r ? k.weights[r + n + 1] : 0
            let sum = table.weights[i]
            let t = table.offsets[i] - Double(n)
            let tq = (t * scale).rounded(rule) / scale
            requested.append(t); quantized.append(tq)
            worst = Swift.max(worst, abs(sum * (1 - tq) - a), abs(sum * tq - b))
            n += 2; i += 1
        }
        return PairAnalysis(table: table, maxTapError: worst, bits: bits, rounding: rounding, requestedFractions: requested,
                            quantizedFractions: quantized)
    }

    /// Positions where the cumulative sum (the edge-spread function) crosses 10 % and 90 % (linear interpolation).
    public static func edgeWidth(xs: [Double], ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 2 else { return nil }
        var cumulative: [Double] = [0]
        for i in 1..<xs.count { cumulative.append(cumulative[i - 1] + 0.5 * (ys[i] + ys[i - 1]) * (xs[i] - xs[i - 1])) }
        guard let total = cumulative.last, total > 0 else { return nil }
        let c = cumulative.map { $0 / total }
        func crossing(_ level: Double) -> Double? {
            for i in 1..<c.count where c[i - 1] < level && c[i] >= level {
                let t = (level - c[i - 1]) / Swift.max(c[i] - c[i - 1], 1e-300)
                return xs[i - 1] + t * (xs[i] - xs[i - 1])
            }
            return nil
        }
        guard let a = crossing(0.1), let b = crossing(0.9) else { return nil }
        return b - a
    }

    /// Edge width of a discrete kernel: its ESF steps at the half-integer boundaries between taps.
    public static func edgeWidth(_ k: Kernel1D) -> Double? {
        let total = k.sum
        guard total > 0, k.tapCount >= 1 else { return nil }
        var xs: [Double] = [k.offset(0) - 0.5], c: [Double] = [0]
        var acc = 0.0
        for i in k.weights.indices { acc += k.weights[i] / total; xs.append(k.offset(i) + 0.5); c.append(acc) }
        func crossing(_ level: Double) -> Double? {
            for i in 1..<c.count where c[i - 1] < level && c[i] >= level {
                let t = (level - c[i - 1]) / Swift.max(c[i] - c[i - 1], 1e-300)
                return xs[i - 1] + t * (xs[i] - xs[i - 1])
            }
            return nil
        }
        guard let a = crossing(0.1), let b = crossing(0.9) else { return nil }
        return b - a
    }

    /// Full width at half maximum of a sampled profile (linear interpolation on both flanks).
    public static func fwhm(xs: [Double], ys: [Double]) -> Double? {
        guard let peakIndex = ys.indices.max(by: { ys[$0] < ys[$1] }), ys[peakIndex] > 0 else { return nil }
        let half = ys[peakIndex] / 2
        var left: Double?, right: Double?
        var i = peakIndex
        while i > 0 {
            if ys[i - 1] <= half { left = xs[i - 1] + (half - ys[i - 1]) / Swift.max(ys[i] - ys[i - 1], 1e-300) * (xs[i] - xs[i - 1]); break }
            i -= 1
        }
        i = peakIndex
        while i < ys.count - 1 {
            if ys[i + 1] <= half { right = xs[i] + (ys[i] - half) / Swift.max(ys[i] - ys[i + 1], 1e-300) * (xs[i + 1] - xs[i]); break }
            i += 1
        }
        guard let l = left, let r = right else { return nil }
        return r - l
    }

    /// The signed 2-D response H(u, v) of a PSF on an n × n grid of frequencies from −½ to ½ c/px (phase-centred on the
    /// centroid, so it is the real, signed transfer for symmetric kernels): the MATH figure of non-separable entries.
    public static func signedResponse2D(_ k: Kernel2D, samples n: Int = 33) -> [Double] {
        let total = k.sum
        guard total != 0 else { return Array(repeating: 0, count: n * n) }
        var mx = 0.0, my = 0.0
        for y in 0..<k.height { for x in 0..<k.width { mx += k[x, y] * Double(x - k.originX); my += k[x, y] * Double(y - k.originY) } }
        mx /= total; my /= total
        let freqs = (0..<n).map { -0.5 + Double($0) / Double(n - 1) }
        // Inner DFT along x for every row and every u: rowRe/rowIm[y][u].
        var rowRe = [[Double]](repeating: [Double](repeating: 0, count: n), count: k.height)
        var rowIm = rowRe
        for y in 0..<k.height {
            for (ui, u) in freqs.enumerated() {
                var re = 0.0, im = 0.0
                for x in 0..<k.width {
                    let w = k[x, y]
                    if w == 0 { continue }
                    let phase = -2 * Double.pi * u * (Double(x - k.originX) - mx)
                    re += w * cos(phase); im += w * sin(phase)
                }
                rowRe[y][ui] = re; rowIm[y][ui] = im
            }
        }
        var out = [Double](repeating: 0, count: n * n)
        for (vi, v) in freqs.enumerated() {
            for ui in 0..<n {
                var re = 0.0
                for y in 0..<k.height {
                    let phase = -2 * Double.pi * v * (Double(y - k.originY) - my)
                    re += rowRe[y][ui] * cos(phase) - rowIm[y][ui] * sin(phase)
                }
                out[vi * n + ui] = re / total
            }
        }
        return out
    }

    /// True when a 2-D kernel equals the outer product of its marginals (to 10⁻⁹ of its peak).
    public static func isSeparable(_ k: Kernel2D) -> Bool {
        let total = k.sum
        guard total != 0 else { return true }
        let mx = k.marginalX, my = k.marginalY
        let peak = k.weights.map(abs).max() ?? 1
        for y in 0..<k.height { for x in 0..<k.width where abs(k[x, y] - mx.weights[x] * my.weights[y] / total) > 1e-9 * peak { return false } }
        return true
    }

    /// Second-moment σ along and across the principal axis of a 2-D kernel, and the axis angle in degrees.
    public static func principalMoments(_ k: Kernel2D) -> (along: Double, across: Double, degrees: Double) {
        let total = k.sum
        guard total != 0 else { return (0, 0, 0) }
        var mx = 0.0, my = 0.0
        for y in 0..<k.height { for x in 0..<k.width { mx += k[x, y] * Double(x - k.originX); my += k[x, y] * Double(y - k.originY) } }
        mx /= total; my /= total
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for y in 0..<k.height { for x in 0..<k.width {
            let dx = Double(x - k.originX) - mx, dy = Double(y - k.originY) - my, w = k[x, y]
            sxx += w * dx * dx; syy += w * dy * dy; sxy += w * dx * dy
        } }
        sxx /= total; syy /= total; sxy /= total
        let mean = (sxx + syy) / 2, diff = ((sxx - syy) * (sxx - syy) / 4 + sxy * sxy).squareRoot()
        let angle = 0.5 * atan2(2 * sxy, sxx - syy) * 180 / .pi
        return (Swift.max(mean + diff, 0).squareRoot(), Swift.max(mean - diff, 0).squareRoot(), angle)
    }

    /// The 2-D kernel projected onto a direction (the local PSF profile along its axis), on integer bins.
    public static func profile(_ k: Kernel2D, degrees: Double) -> Kernel1D {
        let c = cos(degrees * .pi / 180), s = sin(degrees * .pi / 180)
        var bins: [Int: Double] = [:]
        for y in 0..<k.height { for x in 0..<k.width where k[x, y] != 0 {
            let d = Double(x - k.originX) * c + Double(y - k.originY) * s
            bins[Int(d.rounded()), default: 0] += k[x, y]
        } }
        let lo = bins.keys.min() ?? 0, hi = bins.keys.max() ?? 0
        return Kernel1D(weights: (lo...hi).map { bins[$0] ?? 0 }, origin: -lo)
    }

    /// Relative L2 distance ‖a − b‖₂ / ‖b‖₂ of two integer-offset kernels aligned on their offsets.
    public static func relativeL2(_ a: Kernel1D, _ b: Kernel1D) -> Double {
        let lo = Swift.min(-a.origin, -b.origin), hi = Swift.max(a.tapCount - 1 - a.origin, b.tapCount - 1 - b.origin)
        var num = 0.0, den = 0.0
        for o in lo...hi {
            let wa = (o + a.origin >= 0 && o + a.origin < a.tapCount) ? a.weights[o + a.origin] / a.sum : 0
            let wb = (o + b.origin >= 0 && o + b.origin < b.tapCount) ? b.weights[o + b.origin] / b.sum : 0
            num += (wa - wb) * (wa - wb); den += wb * wb
        }
        return den > 0 ? (num / den).squareRoot() : 0
    }

    /// The participation ratio 1 / Σŵ² of a weight map: how many taps effectively carry the average.
    public static func effectiveTaps(_ k: Kernel2D) -> Double {
        let total = k.sum
        guard total != 0 else { return 0 }
        let s2 = k.weights.reduce(0) { $0 + ($1 / total) * ($1 / total) }
        return s2 > 0 ? 1 / s2 : 0
    }
}

// MARK: - The CPU reference at the probe (floor 7, trace branches)

public enum ContentProbeReference {
    /// The region of `side` × `side` pixels centred on the probe (clipped to the window).
    public static func region(around p: PixelPoint, side: Int, in size: ImageSize) -> PixelRegion {
        PixelRegion.centred(on: p, side: side, inside: size)
    }

    /// The operator's output (still in the working space) on `region`, computed from `input` (already pre-transformed).
    /// Shift-invariant operators with a finite support run on a crop with an apron (exact in the interior); every other
    /// operator goes through its own `referenceCrop` (required to be efficient for heavy classes, ARCHITECTURE §5.5).
    public static func output(_ op: any BlurOperator, input: ImageBuffer, auxiliary: AuxiliaryInputs, _ request: OperatorRequest,
                              region: PixelRegion, options: ReferenceOptions) -> ImageBuffer? {
        let entry = op.entry
        let shiftInvariant = entry.linearity == .lsi || entry.properties.contains(.shiftInvariant)
        let plan = op.passPlan(request)
        if shiftInvariant, auxiliary == .none, let apron = plan.supportRadius, apron <= 256 {
            let x0 = region.origin.x - apron, y0 = region.origin.y - apron
            let x1 = region.origin.x + region.size.width + apron, y1 = region.origin.y + region.size.height + apron
            if x0 >= 0, y0 >= 0, x1 <= input.width, y1 <= input.height {
                let cropRegion = PixelRegion(origin: PixelPoint(x: x0, y: y0), size: ImageSize(width: x1 - x0, height: y1 - y0))
                let crop = input.crop(cropRegion)
                guard let out = try? op.reference(crop, request, auxiliary: auxiliary, options: options).output else { return nil }
                return out.crop(PixelRegion(origin: PixelPoint(x: apron, y: apron), size: region.size))
            }
        }
        return try? op.referenceCrop(input, request, auxiliary: auxiliary, region: region, options: options)
    }

    /// The probe's reference value after the colour post-pass (linear light), or nil.
    public static func value(_ op: any BlurOperator, content: OperatorContent, _ request: OperatorRequest, probe: PixelPoint,
                             options: ReferenceOptions) -> SIMD4<Double>? {
        let region = PixelRegion(origin: probe, size: .square(1))
        guard content.image.size.contains(probe),
              let out = output(op, input: content.image, auxiliary: content.auxiliary, request, region: region, options: options)
        else { return nil }
        var v = ColourTransform.post(out, request.settings)
        if options.emulateHalfStorage { v = v.roundedToHalf() }
        return SIMD4<Double>(v[0, 0])
    }

    /// For shift-invariant operators with a finite support, the part of the window the probe's output depends on (with a
    /// margin), and the probe in its coordinates; otherwise the whole content. Branches transform only this part.
    public static func local(_ op: any BlurOperator, content: OperatorContent, _ request: OperatorRequest, probe: PixelPoint)
        -> (content: OperatorContent, probe: PixelPoint) {
        let entry = op.entry
        let shiftInvariant = entry.linearity == .lsi || entry.properties.contains(.shiftInvariant)
        guard shiftInvariant, content.auxiliary == .none, let apron = op.passPlan(request).supportRadius, apron <= 256 else { return (content, probe) }
        let m = apron + 6
        let x0 = probe.x - m, y0 = probe.y - m, side = 2 * m + 1
        guard x0 >= 0, y0 >= 0, x0 + side <= content.image.width, y0 + side <= content.image.height else { return (content, probe) }
        let crop = content.image.crop(PixelRegion(origin: PixelPoint(x: x0, y: y0), size: .square(side)))
        return (OperatorContent(image: crop, auxiliary: .none), PixelPoint(x: m, y: m))
    }

    /// The probe's output had the blur run with other silent settings (the API floor's branches, SPEC §6.3), linear light.
    public static func branch(_ op: any BlurOperator, content: OperatorContent, _ request: OperatorRequest, probe: PixelPoint,
                              settings branch: SilentSettings) -> SIMD4<Double>? {
        let l = local(op, content: content, request, probe: probe)
        let raw = ColourTransform.post(l.content.image, request.settings)
        var other = request
        other.settings = branch
        let pre = OperatorContent(image: ColourTransform.pre(raw, branch), auxiliary: l.content.auxiliary)
        return value(op, content: pre, other, probe: l.probe, options: .exact)
    }

    /// The probe's output had the blur run in the OTHER colour space (the API floor's branch, SPEC §6.3), linear light.
    public static func colourBranch(_ op: any BlurOperator, content: OperatorContent, _ request: OperatorRequest, probe: PixelPoint)
        -> (settings: SilentSettings, value: SIMD4<Double>)? {
        var settings = request.settings
        settings.colourSpace = request.settings.colourSpace == .linearLight ? .srgbEncoded : .linearLight
        return branch(op, content: content, request, probe: probe, settings: settings).map { (settings, $0) }
    }
}
