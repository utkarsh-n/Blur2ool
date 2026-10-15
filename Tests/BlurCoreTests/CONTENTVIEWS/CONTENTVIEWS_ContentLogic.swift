import Foundation
@testable import BlurCore

// OWNER: CONTENT-VIEWS. GENERATED MIRROR of App/Content/ContentLogic.swift (namespace renamed) so `core-test --area CONTENTVIEWS` covers the
// app's pure content logic on the Mac. Do not edit here: edit the App file and regenerate; CONTENTVIEWS_MirrorDrift
// fails when the two copies differ.

// BEGIN MIRRORED
public enum CONTENTVIEWS_ContentLogic {

    // MARK: - Signed series (SPEC §4.1.3: negative lobes shaded AND dashed, below a zero line)

    /// A run of samples that share one sign. Neighbouring runs share their interpolated zero crossing.
    public struct SignedRun: Sendable, Hashable {
        public var negative: Bool
        public var xs: [Double]
        public var ys: [Double]
    }

    /// Splits a polyline into runs of one sign. A sign change between two samples inserts the linearly interpolated
    /// zero crossing at the end of one run and the start of the next, so the solid and dashed pieces meet on the zero line.
    public static func signedRuns(xs: [Double], ys: [Double]) -> [SignedRun] {
        let n = Swift.min(xs.count, ys.count)
        guard n > 0 else { return [] }
        var runs: [SignedRun] = []
        var current = SignedRun(negative: ys[0] < 0, xs: [xs[0]], ys: [ys[0]])
        var signKnown = ys[0] != 0
        for i in 1..<n {
            let x = xs[i], y = ys[i]
            if y == 0 { current.xs.append(x); current.ys.append(0); continue }   // zero joins the current run
            let negative = y < 0
            if !signKnown { current.negative = negative; signKnown = true }
            if negative == current.negative { current.xs.append(x); current.ys.append(y); continue }
            // sign change: close the run on the zero line and start the next one there
            let px = xs[i - 1], py = ys[i - 1]
            let zx = py == 0 ? px : px + py / (py - y) * (x - px)
            if py != 0 { current.xs.append(zx); current.ys.append(0) }
            runs.append(current)
            current = SignedRun(negative: negative, xs: [zx, x], ys: [0, y])
        }
        runs.append(current)
        return runs
    }

    /// True when any sample is below zero (the plot then shows its zero line even if the spec did not ask for it).
    public static func hasNegative(_ plot: PlotSpec) -> Bool { plot.series.contains { $0.ys.contains { $0 < 0 } } }

    // MARK: - Axes

    /// The data extent of every series, widened to include 0 for signed or stem plots, or the axis's declared range.
    public static func extent(_ values: [Double], declared: ClosedRange<Double>?, includeZero: Bool, logarithmic: Bool) -> ClosedRange<Double> {
        if let declared { return declared }
        var finite = values.filter { $0.isFinite }
        if logarithmic { finite = finite.filter { $0 > 0 } }
        guard var lo = finite.min(), var hi = finite.max() else { return logarithmic ? 1...10 : 0...1 }
        if includeZero && !logarithmic { lo = Swift.min(lo, 0); hi = Swift.max(hi, 0) }
        if hi - lo < 1e-12 { if logarithmic { lo /= 2; hi *= 2 } else { lo -= 0.5; hi += 0.5 } }
        return lo...hi
    }

    /// "Nice" tick positions (1, 2, 2.5, 5 × 10^k): the finest step that gives at most `count` + 1 ticks inside `range`.
    public static func niceTicks(_ range: ClosedRange<Double>, count: Int) -> [Double] {
        let span = range.upperBound - range.lowerBound
        guard span > 0, span.isFinite, count > 0 else { return [range.lowerBound] }
        func ticks(_ step: Double) -> [Double] {
            let first = Int(ceil(range.lowerBound / step - 1e-9)), last = Int(floor(range.upperBound / step + 1e-9))
            guard first <= last else { return [] }
            let scale = pow(10, Swift.max(0, 1 - floor(log10(step))) + 2)
            return (first...last).map { (Double($0) * step * scale).rounded() / scale }
        }
        var magnitude = pow(10, floor(log10(span / Double(count))) - 1)
        while magnitude < span * 10 {
            for m in [1.0, 2, 2.5, 5] {
                let t = ticks(m * magnitude)
                if !t.isEmpty && t.count <= count + 1 { return t }
            }
            magnitude *= 10
        }
        return [range.lowerBound, range.upperBound]
    }

    /// Powers of ten (and 2, 5 between them when there are few decades) inside a positive range.
    public static func logTicks(_ range: ClosedRange<Double>) -> [Double] {
        guard range.lowerBound > 0 else { return niceTicks(range, count: 4) }
        let a = Int(floor(log10(range.lowerBound))), b = Int(ceil(log10(range.upperBound)))
        let decades = b - a
        var ticks: [Double] = []
        for e in a...b {
            let base = pow(10, Double(e))
            for m in (decades <= 3 ? [1.0, 2, 5] : [1.0]) {
                let v = m * base
                if v >= range.lowerBound * (1 - 1e-9) && v <= range.upperBound * (1 + 1e-9) { ticks.append(v) }
            }
        }
        return ticks.isEmpty ? [range.lowerBound, range.upperBound] : ticks
    }

    /// The one tick-label style for a set of ticks: enough decimals to tell neighbours apart, no more. Logarithmic axes
    /// (ticks at 1, 2, 5 × 10^k) print each tick with one significant digit ("0.5", "20", "100,000").
    public static func tickStyle(_ ticks: [Double], logarithmic: Bool = false) -> NumberStyle {
        if logarithmic { return .significant(1) }
        let nonzero = ticks.filter { $0 != 0 }.map(abs)
        guard let smallest = nonzero.min(), let largest = nonzero.max() else { return .integer() }
        if largest >= 1e6 || smallest < 1e-3 { return .significant(2) }
        let steps = zip(ticks.dropFirst(), ticks).map { abs($0 - $1) }.filter { $0 > 0 }
        let step = steps.min() ?? smallest
        let decimals = Swift.max(0, Swift.min(4, Int(ceil(-log10(step) - 1e-9))))
        let needed = ticks.allSatisfy { abs($0 * pow(10, Double(decimals)) - ($0 * pow(10, Double(decimals))).rounded()) < 1e-6 }
            ? decimals : Swift.min(4, decimals + 1)
        return needed == 0 ? .integer() : .decimals(needed)
    }

    /// The axis title with its unit and the word "normalized" when the axis is normalized (Metro contract A.21).
    public static func axisTitle(_ axis: PlotAxis) -> String {
        var s = axis.label
        if let u = axis.unit, !u.isEmpty { s += " · " + u }
        if axis.normalized { s += " · normalized" }
        if axis.logarithmic { s += " · log" }
        return s
    }

    /// The spoken axis title ("tap offset in px, normalized").
    public static func spokenAxisTitle(_ axis: PlotAxis) -> String {
        var s = axis.label
        if let u = axis.unit, !u.isEmpty { s += " in " + u }
        if axis.normalized { s += ", normalized" }
        if axis.logarithmic { s += ", logarithmic" }
        return s
    }

    // MARK: - Stems (explicit widths: relative-width marks on a numeric axis render invisible, METRO §F.4 item 1)

    /// The stem width in points: 2 pt (SPEC §4.3) unless the stems would touch, never below 0.75 pt.
    public static func stemWidth(count: Int, plotWidth: Double) -> Double {
        guard count > 1 else { return 2 }
        let pitch = plotWidth / Double(count)
        return Swift.max(0.75, Swift.min(2, pitch * 0.55))
    }

    // MARK: - Heat maps (never colour alone: hatching, contours, legend values)

    public struct Segment: Sendable, Hashable {
        public var a: SIMD2<Double>
        public var b: SIMD2<Double>
    }

    /// Marching squares over cell centres (cell (i, j) sits at (i + 0.5, j + 0.5) in cell units). Returns the line
    /// segments where the field crosses `level`; saddles are resolved by the cell-centre mean.
    public static func contour(_ values: [Double], width: Int, height: Int, level: Double) -> [Segment] {
        guard width > 1, height > 1, values.count == width * height else { return [] }
        func v(_ i: Int, _ j: Int) -> Double { values[j * width + i] }
        func p(_ i: Int, _ j: Int) -> SIMD2<Double> { SIMD2(Double(i) + 0.5, Double(j) + 0.5) }
        func lerp(_ a: SIMD2<Double>, _ va: Double, _ b: SIMD2<Double>, _ vb: Double) -> SIMD2<Double> {
            let d = vb - va
            let t = abs(d) < 1e-300 ? 0.5 : (level - va) / d
            return a + (b - a) * Swift.min(1, Swift.max(0, t))
        }
        var out: [Segment] = []
        for j in 0..<(height - 1) {
            for i in 0..<(width - 1) {
                let c = [v(i, j), v(i + 1, j), v(i + 1, j + 1), v(i, j + 1)]
                let q = [p(i, j), p(i + 1, j), p(i + 1, j + 1), p(i, j + 1)]
                var index = 0
                for k in 0..<4 where c[k] > level { index |= 1 << k }
                if index == 0 || index == 15 { continue }
                // edge k joins corner k and corner (k + 1) % 4
                func e(_ k: Int) -> SIMD2<Double> { lerp(q[k], c[k], q[(k + 1) % 4], c[(k + 1) % 4]) }
                let centreAbove = (c.reduce(0, +) / 4) > level
                switch index {
                case 1, 14: out.append(Segment(a: e(3), b: e(0)))
                case 2, 13: out.append(Segment(a: e(0), b: e(1)))
                case 3, 12: out.append(Segment(a: e(3), b: e(1)))
                case 4, 11: out.append(Segment(a: e(1), b: e(2)))
                case 6, 9: out.append(Segment(a: e(0), b: e(2)))
                case 7, 8: out.append(Segment(a: e(2), b: e(3)))
                case 5:
                    if centreAbove { out.append(Segment(a: e(0), b: e(1))); out.append(Segment(a: e(2), b: e(3))) }
                    else { out.append(Segment(a: e(3), b: e(0))); out.append(Segment(a: e(1), b: e(2))) }
                case 10:
                    if centreAbove { out.append(Segment(a: e(3), b: e(0))); out.append(Segment(a: e(1), b: e(2))) }
                    else { out.append(Segment(a: e(0), b: e(1))); out.append(Segment(a: e(2), b: e(3))) }
                default: break
                }
            }
        }
        return out
    }

    /// The ramp position of a value: −1…1 for signed fields (negative below zero), 0…1 for non-negative ones. The magnitude
    /// is square-root mapped so small lobes stay visible (the legend says so). The views mix Metro tokens with it: the plot
    /// inset at 0, wave cyan at +1, spectrum depth at −1 (no colour literals here).
    public static func rampPosition(_ v: Double, limit: Double, signed: Bool) -> Double {
        guard limit > 0, v.isFinite else { return 0 }
        let t = Swift.min(1, abs(v) / limit).squareRoot()
        if signed { return v < 0 ? -t : t }
        return v <= 0 ? 0 : t
    }

    /// The grey a linear-light texel value shows on an SDR display (sRGB-encoded and clipped), 0…1.
    public static func displayGrey(linear: Double) -> Double { Swift.min(1, Swift.max(0, SRGB.encode(Swift.max(0, linear)))) }

    /// The diagonal hatch spacing in points for negative cells (they stay distinguishable without colour).
    public static func hatchSpacing(cellSize: Double) -> Double { Swift.max(3, Swift.min(6, cellSize * 0.8)) }

    // MARK: - PSF moments (PSF fields: what each local spot looks like, spoken)

    public struct Moments: Sendable, Hashable {
        /// Centroid relative to the kernel origin, in px.
        public var centroid: SIMD2<Double>
        /// Standard deviation along the major and minor principal axes, in px.
        public var sigmaMajor: Double
        public var sigmaMinor: Double
        /// Angle of the major axis from +x, degrees in (−90, 90], y down.
        public var angleDegrees: Double
    }

    public static func moments(_ k: Kernel2D) -> Moments {
        var m0 = 0.0, mx = 0.0, my = 0.0
        for y in 0..<k.height { for x in 0..<k.width {
            let w = k[x, y]
            m0 += w; mx += w * Double(x - k.originX); my += w * Double(y - k.originY)
        } }
        guard m0 != 0 else { return Moments(centroid: .zero, sigmaMajor: 0, sigmaMinor: 0, angleDegrees: 0) }
        let cx = mx / m0, cy = my / m0
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for y in 0..<k.height { for x in 0..<k.width {
            let w = k[x, y], dx = Double(x - k.originX) - cx, dy = Double(y - k.originY) - cy
            sxx += w * dx * dx; syy += w * dy * dy; sxy += w * dx * dy
        } }
        sxx /= m0; syy /= m0; sxy /= m0
        let mean = (sxx + syy) / 2, diff = (sxx - syy) / 2
        let root = (diff * diff + sxy * sxy).squareRoot()
        let l1 = Swift.max(0, mean + root), l2 = Swift.max(0, mean - root)
        var angle = 0.5 * atan2(2 * sxy, sxx - syy) * 180 / .pi
        if angle <= -90 { angle += 180 }
        return Moments(centroid: SIMD2(cx, cy), sigmaMajor: l1.squareRoot(), sigmaMinor: l2.squareRoot(), angleDegrees: angle)
    }

    // MARK: - Dispatch geometry (floor 6 Silicon; COMPUTED from the dispatch the pipeline recorded)

    public struct DispatchLayout: Sendable, Hashable {
        /// Threadgroups along x and y.
        public var groups: SIMD2<Int>
        /// Threads per threadgroup along x and y.
        public var groupSize: SIMD2<Int>
        /// Output size in pixels.
        public var output: SIMD2<Int>
        /// The probe pixel (window pixels).
        public var probe: SIMD2<Int>
        /// The probe's threadgroup's first pixel and its size clipped to the output.
        public var probeGroupOrigin: SIMD2<Int>
        /// The pixels the probe's threadgroup reads: its tile plus the apron, clipped to the output.
        public var apronOrigin: SIMD2<Int>
        public var apronSize: SIMD2<Int>
        /// Threads launched beyond the output (they return at the bounds check).
        public var surplus: SIMD2<Int>
        /// SIMD width used to band the group (the pipeline's threadExecutionWidth, or 32 when unknown).
        public var simdWidth: Int
        /// Rows of the probe's group that one SIMD-group covers (threads are numbered row-major in the group).
        public var simdRowsPerGroup: Double
        public var totalGroups: Int { groups.x * groups.y }
        public var threadsPerGroup: Int { groupSize.x * groupSize.y }
    }

    /// The dispatch geometry for drawing. Render, blit and MPS passes (threadsPerThreadgroup [0, 0, 0]) return nil:
    /// they have no threadgroups to draw.
    public static func dispatchLayout(_ spec: DispatchOverlaySpec) -> DispatchLayout? {
        let d = spec.dispatch
        guard d.threadsPerThreadgroup.count >= 2, d.threadgroups.count >= 2,
              d.threadsPerThreadgroup[0] > 0, d.threadsPerThreadgroup[1] > 0 else { return nil }
        let gs = SIMD2(d.threadsPerThreadgroup[0], d.threadsPerThreadgroup[1])
        let groups = SIMD2(d.threadgroups[0], d.threadgroups[1])
        let out = SIMD2(d.outputSize.width, d.outputSize.height)
        let tg = SIMD2(spec.probeThreadgroup.first ?? 0, spec.probeThreadgroup.dropFirst().first ?? 0)
        let th = SIMD2(spec.probeThreadInGroup.first ?? 0, spec.probeThreadInGroup.dropFirst().first ?? 0)
        let origin = tg &* gs
        let probe = origin &+ th
        let a = spec.apronTexels
        let lo = SIMD2(Swift.max(0, origin.x - a), Swift.max(0, origin.y - (gs.y > 1 ? a : 0)))
        let hi = SIMD2(Swift.min(out.x, origin.x + gs.x + a), Swift.min(out.y, origin.y + gs.y + (gs.y > 1 ? a : 0)))
        let simd = d.threadExecutionWidth > 0 ? d.threadExecutionWidth : 32
        return DispatchLayout(groups: groups, groupSize: gs, output: out, probe: probe, probeGroupOrigin: origin,
                              apronOrigin: lo, apronSize: hi &- lo,
                              surplus: SIMD2(groups.x * gs.x - out.x, groups.y * gs.y - out.y),
                              simdWidth: simd, simdRowsPerGroup: Double(simd) / Double(gs.x))
    }

    /// The probe thread's linear index in its group, its SIMD-group and lane (row-major numbering, COMPUTED).
    public static func probeLinearIndex(_ spec: DispatchOverlaySpec) -> Int {
        let gs = spec.dispatch.threadsPerThreadgroup
        let th = spec.probeThreadInGroup
        guard gs.count >= 1, th.count >= 1 else { return 0 }
        return (th.count > 1 ? th[1] : 0) * gs[0] + th[0]
    }

    // MARK: - Shader source (syntax colour, `@explain:` annotations, TRACE_PROBE lines)

    public enum TokenKind: String, Sendable, Hashable { case plain, keyword, type, number, comment, explain, string, preprocessor, attribute, function }

    public struct Token: Sendable, Hashable {
        public var text: String
        public var kind: TokenKind
    }

    static let metalKeywords: Set<String> = ["kernel", "fragment", "vertex", "constant", "device", "thread", "threadgroup",
        "return", "for", "if", "else", "while", "do", "struct", "using", "namespace", "constexpr", "inline", "static", "const",
        "true", "false", "break", "continue", "switch", "case", "default", "typedef", "enum", "template", "sizeof", "as_type",
        "let", "var", "func", "import", "in", "guard", "public", "private", "self", "nil", "some", "class", "protocol", "extension"]
    static let metalTypes: Set<String> = ["float", "float2", "float3", "float4", "half", "half2", "half3", "half4", "int", "int2",
        "int3", "int4", "uint", "uint2", "uint3", "uint4", "bool", "void", "short", "ushort", "char", "uchar", "texture2d",
        "sampler", "access", "metal", "Double", "Float", "Int", "String", "View", "Image", "Color", "CGFloat"]

    /// Splits one line into coloured tokens. A trailing `// @explain: …` comment becomes one `.explain` token.
    public static func tokenize(_ line: String, language: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(line)
        var i = 0
        func push(_ s: String, _ k: TokenKind) {
            if let last = tokens.last, last.kind == k, k == .plain { tokens[tokens.count - 1].text += s } else { tokens.append(Token(text: s, kind: k)) }
        }
        let firstNonSpace = chars.firstIndex { $0 != " " && $0 != "\t" }
        if let f = firstNonSpace, chars[f] == "#", language != "css" {
            if f > 0 { push(String(chars[0..<f]), .plain) }
            // preprocessor up to a comment
            var j = f
            while j < chars.count, !(chars[j] == "/" && j + 1 < chars.count && chars[j + 1] == "/") { j += 1 }
            push(String(chars[f..<j]), .preprocessor)
            i = j
        }
        while i < chars.count {
            let c = chars[i]
            if c == "/" && i + 1 < chars.count && chars[i + 1] == "/" {
                let rest = String(chars[i...])
                push(rest, rest.contains("@explain:") ? .explain : .comment)
                break
            }
            if c == "/" && i + 1 < chars.count && chars[i + 1] == "*" {
                var j = i + 2
                while j + 1 < chars.count, !(chars[j] == "*" && chars[j + 1] == "/") { j += 1 }
                j = Swift.min(chars.count, j + 2)
                push(String(chars[i..<j]), .comment); i = j; continue
            }
            if c == "\"" {
                var j = i + 1
                while j < chars.count, chars[j] != "\"" { j += (chars[j] == "\\" ? 2 : 1) }
                j = Swift.min(chars.count, j + 1)
                push(String(chars[i..<j]), .string); i = j; continue
            }
            if c == "[" && i + 1 < chars.count && chars[i + 1] == "[" {
                var j = i + 2
                while j + 1 < chars.count, !(chars[j] == "]" && chars[j + 1] == "]") { j += 1 }
                j = Swift.min(chars.count, j + 2)
                push(String(chars[i..<j]), .attribute); i = j; continue
            }
            if c.isNumber || (c == "." && i + 1 < chars.count && chars[i + 1].isNumber && (i == 0 || !(chars[i - 1].isLetter || chars[i - 1] == "_"))) {
                var j = i
                while j < chars.count, chars[j].isNumber || chars[j] == "." || chars[j] == "f" || chars[j] == "u" || chars[j] == "x"
                        || (chars[j] == "e" && j + 1 < chars.count && (chars[j + 1].isNumber || chars[j + 1] == "-")) || (chars[j] == "-" && j > i && chars[j - 1] == "e") { j += 1 }
                push(String(chars[i..<j]), .number); i = j; continue
            }
            if c.isLetter || c == "_" || c == "@" {
                var j = i
                while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" || chars[j] == "@" { j += 1 }
                let word = String(chars[i..<j])
                var k = j
                while k < chars.count, chars[k] == " " { k += 1 }
                let isCall = k < chars.count && chars[k] == "("
                let kind: TokenKind
                if metalKeywords.contains(word) { kind = .keyword }
                else if metalTypes.contains(word) || word.hasPrefix("B2") && word.first?.isUppercase == true && word.contains(where: \.isLowercase) { kind = .type }
                else if word.hasPrefix("B2_") || word.hasPrefix("@") { kind = .preprocessor }
                else if isCall { kind = .function }
                else { kind = .plain }
                push(word, kind); i = j; continue
            }
            push(String(c), .plain); i += 1
        }
        return tokens
    }

    /// The one-line explanations by 1-based line: the block's own annotations, plus every `// @explain: …` comment in
    /// the text (a line's own annotation wins when both exist).
    public static func explanations(_ code: CodeBlock) -> [Int: String] {
        var out: [Int: String] = [:]
        for (n, line) in code.text.components(separatedBy: "\n").enumerated() {
            guard let r = line.range(of: "@explain:") else { continue }
            let text = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { out[n + 1] = text }
        }
        for (k, v) in code.annotations { out[k] = v }
        return out
    }

    /// Lines to highlight: the block's own list plus every line that mentions TRACE_PROBE (traced builds, SPEC §4.3).
    public static func traceLines(_ code: CodeBlock) -> Set<Int> {
        var out = Set(code.highlightedLines)
        for (n, line) in code.text.components(separatedBy: "\n").enumerated() where line.contains("TRACE_PROBE") { out.insert(n + 1) }
        return out
    }

    /// The display text of a line with its trailing `@explain:` comment removed (the explanation is shown as a callout).
    public static func codeWithoutExplain(_ line: String) -> String {
        guard let r = line.range(of: "// @explain:") else { return line }
        return String(line[..<r.lowerBound]).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
    }

    /// The line window an excerpt of `count` lines shows: the window that holds the most marked lines (TRACE_PROBE or
    /// explained), the earliest such window on a tie, starting a line before the first mark it holds when it can.
    public static func excerptWindow(_ code: CodeBlock, count: Int) -> Range<Int> {
        let total = code.text.components(separatedBy: "\n").count
        guard total > count, count > 0 else { return 0..<total }
        let marks = Set(traceLines(code).map { $0 - 1 }).union(explanations(code).keys.map { $0 - 1 })
        guard !marks.isEmpty else { return 0..<count }
        var best = 0, bestCount = -1
        for start in 0...(total - count) {
            let n = marks.filter { $0 >= start && $0 < start + count }.count
            if n > bestCount { best = start; bestCount = n }
        }
        let firstMark = marks.filter { $0 >= best }.min() ?? best
        let start = Swift.max(0, Swift.min(total - count, Swift.min(best, firstMark - 1)))
        return start..<(start + count)
    }

    // MARK: - Data tables (every plot has one; SPEC §14)

    public struct DataTable: Sendable, Hashable {
        public var columns: [String]
        public var rows: [[String]]
        /// The spoken row ("x 0.10 c/px; H 0.168, computed; …").
        public var spokenRows: [String]
    }

    /// The plot's data as a table: one column for x, one per series, values at the series' own precision. Series that
    /// share x samples share rows; others are listed after, each with its own x.
    public static func dataTable(_ plot: PlotSpec) -> DataTable {
        let xStyle = valueStyle(plot.series.flatMap(\.xs), unit: plot.xAxis.unit)
        let xTitle = plot.xAxis.label + (plot.xAxis.unit.map { " · " + $0 } ?? "")
        var columns = [xTitle.uppercased()]
        var groups: [[PlotSeries]] = []
        for s in plot.series {
            if let g = groups.firstIndex(where: { $0[0].xs == s.xs }) { groups[g].append(s) } else { groups.append([s]) }
        }
        var rows: [[String]] = [], spoken: [String] = []
        let width = 1 + plot.series.count
        var col = 1
        for g in groups {
            for s in g { columns.append("\(s.name.uppercased()) · \(s.provenance.word)") }
            let styles = g.map { valueStyle($0.ys, unit: nil) }
            for i in g[0].xs.indices {
                var row = Array(repeating: "", count: width)
                row[0] = xStyle.text(g[0].xs[i])
                var words = ["\(plot.xAxis.label) \(xStyle.spoken(g[0].xs[i]))"]
                for (k, s) in g.enumerated() where i < s.ys.count {
                    row[col + k] = styles[k].text(s.ys[i])
                    words.append("\(s.name) \(styles[k].spoken(s.ys[i])), \(s.provenance.spokenPhrase(device: nil))")
                }
                rows.append(row); spoken.append(words.joined(separator: "; "))
            }
            col += g.count
        }
        return DataTable(columns: columns, rows: rows, spokenRows: spoken)
    }

    /// The precision used for a column of plotted values: 4 significant digits relative to the largest magnitude
    /// (so 0.09991 and 0.00111 share 5 decimals), scientific outside 10⁻³…10⁶; integers stay whole.
    public static func valueStyle(_ values: [Double], unit: String?) -> NumberStyle {
        let finite = values.filter { $0.isFinite }.map(abs)
        guard let peak = finite.max(), peak > 0 else { return NumberStyle(precision: .decimals(0), unit: unit) }
        if finite.allSatisfy({ abs($0 - $0.rounded()) < 1e-9 }) { return NumberStyle(precision: .decimals(0), unit: unit) }
        if peak >= 1e6 || peak < 1e-3 { return NumberStyle(precision: .significant(3), unit: unit) }
        let decimals = Swift.max(0, Swift.min(6, 3 - Int(floor(log10(peak)))))
        return NumberStyle(precision: .decimals(decimals), unit: unit)
    }

    // MARK: - Page text

    /// The sentence of an `IN THIS APP` line without its leading engraving (the view engraves the words itself).
    public static func inThisAppSentence(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.uppercased().hasPrefix("IN THIS APP") { t = String(t.dropFirst("IN THIS APP".count)) }
        return t.trimmingCharacters(in: CharacterSet(charactersIn: " ·:—-").union(.whitespacesAndNewlines))
    }

    /// `All kernel details`, `All GPU details`, `All silicon details` (SPEC §4.3).
    public static func detailsTitle(_ floor: Floor, tabTitle: String?) -> String {
        let word = tabTitle ?? floor.title
        let shown = word == word.uppercased() ? word : word.lowercased()
        return "All \(shown == "pixels" ? "pixel" : shown) details"
    }

    /// Placeholder words that must never reach the screen (ARCHITECTURE §5.1 honestyViolations' list).
    public static let placeholderMarkers = ["todo", "lorem", "placeholder", "tbd", "fixme"]
    public static func placeholderWords(in text: String) -> [String] {
        let lowered = text.lowercased()
        return placeholderMarkers.filter { marker in
            lowered.components(separatedBy: CharacterSet.alphanumerics.inverted).contains(marker)
        }
    }

    // MARK: - Every figure and block kind (coverage of the gallery and its tests)

    public static func figureKind(_ f: FigureSpec) -> String {
        switch f {
        case .plot: "plot"
        case .heatmap: "heatmap"
        case .texelGrid: "texelGrid"
        case .dispatchOverlay: "dispatchOverlay"
        case .passTiles: "passTiles"
        case .psfField: "psfField"
        case .toolBars: "toolBars"
        case .code: "code"
        case .pair: "pair"
        }
    }

    public static func blockKind(_ b: ContentBlock) -> String {
        switch b {
        case .paragraph: "paragraph"
        case .equation: "equation"
        case .values: "values"
        case .table: "table"
        case .code: "code"
        case .figure: "figure"
        case .note: "note"
        case .chips: "chips"
        case .sources: "sources"
        case .disclosure: "disclosure"
        }
    }

    public static let allFigureKinds: Set<String> = ["plot", "heatmap", "texelGrid", "dispatchOverlay", "passTiles", "psfField",
                                                     "toolBars", "code", "pair"]
    public static let allBlockKinds: Set<String> = ["paragraph", "equation", "values", "table", "code", "figure", "note", "chips",
                                                    "sources", "disclosure"]

    /// Every figure in a page (its own, its tabs', and those inside detail blocks and pairs), depth first.
    public static func figures(in page: FloorPage) -> [FigureSpec] {
        var out: [FigureSpec] = []
        func visit(_ f: FigureSpec) {
            out.append(f)
            if case .pair(let a, let b) = f { visit(a); visit(b) }
        }
        if let f = page.figure { visit(f) }
        for t in page.tabs ?? [] { if let f = t.figure { visit(f) } }
        for b in blocks(in: page) { if case .figure(let f) = b { visit(f) } }
        return out
    }

    /// Every block in a page (details of the page and its tabs, recursively through disclosures).
    public static func blocks(in page: FloorPage) -> [ContentBlock] {
        var out: [ContentBlock] = []
        func visit(_ b: ContentBlock) {
            out.append(b)
            if case .disclosure(_, let inner) = b { inner.forEach(visit) }
        }
        page.details.forEach(visit)
        for t in page.tabs ?? [] { t.details.forEach(visit) }
        return out
    }

    /// Every badged value a page shows: its numbers, its tabs' numbers, tool-bar rows and value blocks.
    public static func badgedValues(in page: FloorPage) -> [BadgedValue] {
        var out = page.numbers.map(\.value)
        for t in page.tabs ?? [] { out += t.numbers.map(\.value) }
        for f in figures(in: page) { if case .toolBars(let bars) = f { out += bars.rows.map(\.value) } }
        for b in blocks(in: page) { if case .values(let rows) = b { out += rows.map(\.value) } }
        return out
    }

    /// Every view-bound string of a page (for the placeholder lint).
    public static func strings(in page: FloorPage) -> [String] {
        var out = [page.eyebrow, page.question, page.signature, page.inThisApp]
        out += [page.governingRule, page.emptyState].compactMap { $0 }
        out += page.numbers.flatMap { [$0.label, $0.value.text, $0.value.spoken] + [$0.value.caption, $0.value.unit].compactMap { $0 } }
        for t in page.tabs ?? [] { out.append(t.title); out += t.numbers.flatMap { [$0.label, $0.value.text, $0.value.spoken] } }
        for f in figures(in: page) {
            switch f {
            case .plot(let p):
                out += [p.xAxis.label, p.yAxis.label, p.accessibilitySummary] + p.series.map(\.name) + p.markers.map(\.label)
            case .heatmap(let h): out.append(h.caption)
            case .passTiles(let t): out += t.passes.flatMap { [$0.name, $0.summary] }
            case .toolBars(let b): out += b.rows.flatMap { [$0.label, $0.value.text, $0.value.spoken] }
            case .code(let c): out += [c.text] + Array(c.annotations.values)
            default: break
            }
        }
        for b in blocks(in: page) {
            switch b {
            case .paragraph(let s), .equation(let s): out.append(s)
            case .note(let s, _): out.append(s)
            case .chips(let c): out += c
            case .table(let t): out += t.columns + t.rows.flatMap { $0 } + [t.caption].compactMap { $0 }
            case .sources(let s): out += s.map(\.citation)
            case .disclosure(let title, _): out.append(title)
            case .code(let c): out.append(c.text)
            default: break
            }
        }
        return out
    }
}
// END MIRRORED
