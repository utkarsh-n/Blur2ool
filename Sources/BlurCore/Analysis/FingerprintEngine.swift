import Foundation

// OWNER: ANALYSIS. SPEC §7.4: the fingerprint vector (what Catalog › Fingerprints sorts by and LOOKS MOST LIKE compares),
// computed for every entry at the reference size σ_equiv = 4 px (equal second moment, CATALOG §7 convention) from the
// kernel as run (the entry's defaults, σ-held at 4 px), and taken from a MEASURED shape for ON THIS PHONE. Blank cells stay
// nil and read `— NOT YET COMPUTED`; the distance skips them. Also: the shared excess-kurtosis axis of SPEC §7.1 item 6.
//
// Cells (FingerprintVector):
//   excessKurtosisAxis  line-spread function (x marginal of the PSF) excess kurtosis
//   excessKurtosis45    the PSF projected on the 45° diagonal: separable vs isotropic (a separable box gives −0.6 there,
//                       −1.2 on the axis; a disc −1.0 on both)
//   minResponse         minimum of the signed discrete H(ν) on 0…0.5 c/px (local at the standard probe for LSV)
//   firstZero           first zero of that H, c/px
//   supportOverSigma    support radius of the line-spread function at 10⁻⁴ of its peak, over its σ
//   costExponent        p in fetches ∝ σ^p for the default variant, fitted over σ 4…16 px
//   shiftVariancePx     0 for LSI full-resolution plans (exactly shift-invariant); otherwise only measurable (nil)
// Tier S entries never get a vector from our Metal model (review fix P-31): their cells stay blank until measured.

public struct FingerprintEngine: FingerprintComputing {
    /// σ_equiv of every computed vector (SPEC §7.4), px.
    public static let referenceSigma = 4.0
    /// Window the reference requests describe (the 15 Pro Max window, SPEC §4.1.3).
    public static let referenceWindow = 894
    /// σ values (px) the cost exponent is fitted over (√2 steps from 4 to 16).
    public static let costFitSigmas: [Double] = [4, 4 * 2.0.squareRoot(), 8, 8 * 2.0.squareRoot(), 16]

    public init() {}

    // MARK: Reference request

    /// The request every computed vector uses: the entry's defaults σ-held at 4 px, its default variant, standard silent
    /// settings, an 894² window. Entries without a σ keep their defaults ("σ NOT DEFINED").
    public func referenceRequest(for op: any BlurOperator) -> OperatorRequest {
        let entry = op.entry
        let held = op.holdingSigma(Self.referenceSigma, current: entry.defaultParameters)
        return OperatorRequest(parameters: held.parameters, variant: entry.defaultVariant, settings: .standard,
                               size: .square(Self.referenceWindow))
    }

    /// The window centre for LSI blurs; a standard off-centre probe (three quarters across, mid height) for LSV blurs,
    /// whose PSF at the centre of a centred zoom or spin is the identity.
    public func referenceProbe(for linearity: LinearityClass) -> PixelPoint {
        let n = Self.referenceWindow
        return linearity == .lsv ? PixelPoint(x: 3 * n / 4, y: n / 2) : PixelPoint(x: n / 2, y: n / 2)
    }

    // MARK: FingerprintComputing

    public func vector(for op: any BlurOperator) -> FingerprintVector {
        let entry = op.entry
        guard entry.tier != .system && entry.linearity != .system else { return Self.blank(linearity: entry.linearity) }
        return vector(for: op, request: referenceRequest(for: op), probe: referenceProbe(for: entry.linearity))
    }

    /// The vector of `op` at an arbitrary request (Catalog › Fingerprints at the current σ; the card's dot on the axis).
    public func vector(for op: any BlurOperator, request: OperatorRequest, probe: PixelPoint) -> FingerprintVector {
        let entry = op.entry
        let linear = DivergenceEngine.isLinearClass(entry.linearity)
        let psf = linear ? op.psf(at: probe, request, content: nil) : nil
        let lsf = psf?.kernel.marginalX
        let kurtosisAxis = lsf.flatMap { AnalysisMath.moments($0)?.excessKurtosis }
        let kurtosis45 = psf.flatMap { AnalysisMath.projectedMoments($0.kernel, degrees: 45)?.excessKurtosis }
        let query = ResponseQuery(samples: 2049, point: entry.linearity == .lsv ? probe : nil)
        let curve = op.response(query, request, content: nil)
        let refine = entry.linearity == .lsv ? nil : lsf
        let minimum = curve.flatMap { AnalysisMath.minimum(of: $0, refineWith: refine)?.value }
        let zero = curve.flatMap { AnalysisMath.firstZero(of: $0, refineWith: refine) }
        let support = lsf.flatMap { AnalysisMath.supportOverSigma($0) }
        let plan = op.passPlan(request)
        let shift: Double? = entry.linearity == .lsi && !plan.passes.isEmpty && plan.passes.allSatisfy({ $0.outputScale == 1 }) ? 0 : nil
        return FingerprintVector(excessKurtosisAxis: kurtosisAxis, excessKurtosis45: kurtosis45, minResponse: minimum, firstZero: zero,
                                 supportOverSigma: support, linearity: entry.linearity, costExponent: costExponent(op, request: request),
                                 shiftVariancePx: shift)
    }

    public func vector(measured: ShapeMeasurement, linearity: LinearityClass) -> FingerprintVector {
        func finite(_ v: Double) -> Double? { v.isFinite ? v : nil }
        return FingerprintVector(excessKurtosisAxis: finite(measured.excessKurtosisAxis), excessKurtosis45: finite(measured.excessKurtosis45),
                                 minResponse: finite(measured.minResponse), firstZero: nil, supportOverSigma: nil, linearity: linearity,
                                 costExponent: nil, shiftVariancePx: finite(measured.shiftSpreadPx))
    }

    public func nearest(to vector: FingerprintVector, among ops: [any BlurOperator]) -> (blur: BlurID, distance: Double)? {
        ranked(to: vector, among: ops).first.map { ($0.blur, $0.distance) }
    }

    // MARK: Ranking

    /// One candidate of LOOKS MOST LIKE.
    public struct Match: Sendable, Hashable {
        public var blur: BlurID
        /// Normalised RMS distance over the cells both vectors fill (0 = identical).
        public var distance: Double
        /// Number of numeric cells both vectors fill (the linearity cell is not counted).
        public var sharedCells: Int
    }

    /// Every candidate with at least one shared numeric cell, nearest first (ties keep the input order).
    public func ranked(to vector: FingerprintVector, among ops: [any BlurOperator]) -> [Match] {
        ranked(to: vector, among: ops.map { ($0.entry.id, self.vector(for: $0)) })
    }

    /// The same over vectors computed earlier (the app caches the catalog's vectors off the main actor).
    public func ranked(to vector: FingerprintVector, among vectors: [(blur: BlurID, vector: FingerprintVector)]) -> [Match] {
        let matches = vectors.enumerated().compactMap { i, item -> (Int, Match)? in
            guard let d = Self.distance(vector, item.vector) else { return nil }
            return (i, Match(blur: item.blur, distance: d.distance, sharedCells: d.sharedCells))
        }
        return matches.sorted { $0.1.distance != $1.1.distance ? $0.1.distance < $1.1.distance : $0.0 < $1.0 }.map(\.1)
    }

    /// Normalisation of each cell: one unit of distance is the span the catalog's landmarks cover (COMPUTED).
    public struct Scales: Sendable, Hashable {
        /// Excess kurtosis: the shared axis −1.2 (box) … +3 (Laplace).
        public var kurtosis = 4.2
        /// Minimum of H: the box's continuous −0.217, the deepest lobe of a common blur.
        public var minResponse = 0.217
        /// First zero: Nyquist, 0.5 c/px.
        public var firstZero = 0.5
        /// Support over σ is compared as a log ratio: a factor of 4 is one unit.
        public var supportLogRatio = log(4.0)
        /// Cost exponent: O(1) … O(r²).
        public var costExponent = 2.0
        /// Shift variance: the mip chain's ±7.5 px snap (CATALOG P7).
        public var shiftPx = 7.5
        /// Linearity class: a different class counts as one unit.
        public var linearity = 1.0
    }

    public static let scales = Scales()

    /// Normalised RMS distance over the cells both vectors fill. The linearity cell counts only when both classes are
    /// known (`.system` means "internals not exposed", a blank). nil when no numeric cell is shared.
    public static func distance(_ a: FingerprintVector, _ b: FingerprintVector, scales: Scales = scales) -> (distance: Double, sharedCells: Int)? {
        var terms: [Double] = []
        func add(_ x: Double?, _ y: Double?, _ scale: Double) {
            guard let x, let y, x.isFinite, y.isFinite else { return }
            terms.append((x - y) / scale)
        }
        add(a.excessKurtosisAxis, b.excessKurtosisAxis, scales.kurtosis)
        add(a.excessKurtosis45, b.excessKurtosis45, scales.kurtosis)
        add(a.minResponse, b.minResponse, scales.minResponse)
        add(a.firstZero, b.firstZero, scales.firstZero)
        if let x = a.supportOverSigma, let y = b.supportOverSigma, x > 0, y > 0, x.isFinite, y.isFinite {
            terms.append(log(x / y) / scales.supportLogRatio)
        }
        add(a.costExponent, b.costExponent, scales.costExponent)
        add(a.shiftVariancePx, b.shiftVariancePx, scales.shiftPx)
        let numeric = terms.count
        guard numeric > 0 else { return nil }
        if a.linearity != .system && b.linearity != .system { terms.append(a.linearity == b.linearity ? 0 : scales.linearity) }
        let rms = (terms.reduce(0) { $0 + $1 * $1 } / Double(terms.count)).squareRoot()
        return (rms, numeric)
    }

    // MARK: Badged cells (Catalog › Fingerprints matrix, the card's LOOKS MOST LIKE)

    /// Where a vector's numbers come from.
    public enum Evidence: Sendable, Hashable {
        /// From BlurCore's kernels (COMPUTED).
        case computed
        /// From GPU output or a Calibrate fit on a device (MEASURED, with the device; `.offscreen` for SwiftUI subjects).
        case measured(DeviceStamp, Qualifiers)
    }

    private static func badge(_ value: Double, _ style: NumberStyle, _ evidence: Evidence) -> BadgedValue {
        switch evidence {
        case .computed: .number(value, style, .computed)
        case .measured(let device, let qualifiers):
            .number(value, style, .measured, qualifiers: qualifiers, device: device,
                    caption: qualifiers.contains(.offscreen) ? "OFFSCREEN" : nil)
        }
    }

    /// The blank cell (SPEC §7.4, D R14): words, never an estimate.
    public static let notYetComputed = BadgedValue.words("— NOT YET COMPUTED", spoken: "not yet computed")

    /// The matrix row of a vector: eight labelled cells in a fixed order, blanks as `— NOT YET COMPUTED`.
    public func cells(for vector: FingerprintVector, evidence: Evidence) -> [LabeledValue] {
        let kurtosis = NumberStyle(precision: .decimals(2), explicitPlus: true)
        func cell(_ id: String, _ label: String, _ value: Double?, _ style: NumberStyle) -> LabeledValue {
            LabeledValue(id: id, label: label, value: value.map { Self.badge($0, style, evidence) } ?? Self.notYetComputed)
        }
        let linearity: BadgedValue = vector.linearity == .system
            ? .words("SYS", spoken: "system implementation, internals not exposed")
            : .words(vector.linearity.chip, spoken: Self.linearityPhrase(vector.linearity), evidence == .computed ? .computed : nil)
        return [
            cell("kurtosisAxis", "KURT AXIS", vector.excessKurtosisAxis, kurtosis),
            cell("kurtosis45", "KURT 45°", vector.excessKurtosis45, kurtosis),
            cell("minResponse", "MIN H", vector.minResponse, vector.minResponse.map(DivergenceEngine.minimumStyle) ?? .decimals(3)),
            cell("firstZero", "FIRST ZERO", vector.firstZero, .decimals(4, unit: "c/px", spokenUnit: "cycles per pixel")),
            cell("supportOverSigma", "SUPPORT / σ", vector.supportOverSigma, .decimals(2)),
            LabeledValue(id: "linearity", label: "CLASS", value: linearity),
            cell("costExponent", "COST r^p", vector.costExponent, .decimals(2)),
            cell("shiftVariancePx", "SHIFT", vector.shiftVariancePx, .decimals(2, unit: "px", spokenUnit: "pixels")),
        ]
    }

    /// LOOKS MOST LIKE's distance, `Δ 0.00`, badged as its vector (MEASURED when the vector was measured).
    public func distanceValue(_ distance: Double, evidence: Evidence) -> BadgedValue {
        Self.badge(distance, .decimals(2), evidence)
    }

    /// LOOKS MOST LIKE as a line: "<name> · Δ 0.07"; `NO SHARED CELLS` when nothing can be compared yet.
    public func looksMostLikeLine(_ match: Match?, displayName: String?, evidence: Evidence) -> BadgedLine {
        guard let match else { return .words("NO SHARED CELLS YET") }
        return BadgedLine([.literal(displayName ?? match.blur.rawValue), .text("· Δ"), .value(distanceValue(match.distance, evidence: evidence))])
    }

    private static func linearityPhrase(_ c: LinearityClass) -> String {
        switch c {
        case .lsi: "linear shift-invariant"
        case .lsv: "linear shift-variant"
        case .nonlinear: "nonlinear"
        case .expectation: "blur in expectation"
        case .system: "system implementation"
        }
    }

    // MARK: The excess-kurtosis axis (SPEC §7.1 item 6)

    /// One labelled landmark on the shared axis −1.2 … +3.
    public struct Landmark: Sendable, Hashable, Identifiable {
        public var id: String
        /// Short axis label ("box", "box³", "Gaussian").
        public var label: String
        /// The catalog entry it stands for.
        public var blur: BlurID
        /// The continuous line-spread function's excess kurtosis, computed numerically from its density.
        public var value: Double
        /// The exact value it converges to (−6/5, −1, −3/5, −2/5, 0, 3), for the field guide's derivation line.
        public var exact: Double
        public var badge: BadgedValue
    }

    /// The axis landmarks, COMPUTED by integrating each continuous line-spread function (midpoint rule, 40,000 cells):
    /// box (uniform) −1.2 · disc (semicircle, the disc's chord length) −1.0 · tent (triangle) −0.6 · box³ (three boxes
    /// convolved) −0.4 · Gaussian 0 · Laplace (two-sided exponential, `exponential-blur`) +3.
    public static let kurtosisLandmarks: [Landmark] = computeLandmarks()

    private static func computeLandmarks() -> [Landmark] {
        let style = NumberStyle(precision: .decimals(1), explicitPlus: true)
        func landmark(_ id: String, _ label: String, _ blur: BlurID, exact: Double, support: Double,
                      _ density: (Double) -> Double) -> Landmark {
            let n = 40_000, h = 2 * support / Double(n)
            let xs = (0..<n).map { -support + (Double($0) + 0.5) * h }
            let value = AnalysisMath.moments(positions: xs, weights: xs.map { density($0) * h })?.excessKurtosis ?? .nan
            return Landmark(id: id, label: label, blur: blur, value: value, exact: exact, badge: .number(value, style, .computed))
        }
        func boxCubed(_ x: Double) -> Double {   // Irwin–Hall n = 3 on [−1.5, 1.5]
            let t = abs(x)
            if t <= 0.5 { return 0.75 - t * t }
            if t <= 1.5 { return 0.5 * (1.5 - t) * (1.5 - t) }
            return 0
        }
        return [
            landmark("box", "box", "box-blur", exact: -1.2, support: 1) { abs($0) <= 1 ? 0.5 : 0 },
            landmark("disc", "disc", "disc-blur", exact: -1.0, support: 1) { abs($0) < 1 ? 2 * (1 - $0 * $0).squareRoot() / .pi : 0 },
            landmark("tent", "tent", "tent-blur", exact: -0.6, support: 1) { Swift.max(0, 1 - abs($0)) },
            landmark("box3", "box³", "iterated-box", exact: -0.4, support: 1.5, boxCubed),
            landmark("gaussian", "Gaussian", "gaussian-blur", exact: 0, support: 12) { exp(-$0 * $0 / 2) / (2 * Double.pi).squareRoot() },
            landmark("laplace", "Laplace", "exponential-blur", exact: 3, support: 60) { exp(-abs($0)) / 2 },
        ]
    }

    /// The axis range the card draws (SPEC §7.1: −1.2 … +3).
    public static let kurtosisAxisRange: ClosedRange<Double> = -1.2...3

    // MARK: Helpers

    static func blank(linearity: LinearityClass) -> FingerprintVector {
        FingerprintVector(excessKurtosisAxis: nil, excessKurtosis45: nil, minResponse: nil, firstZero: nil, supportOverSigma: nil,
                          linearity: linearity, costExponent: nil, shiftVariancePx: nil)
    }

    /// p in fetches per pixel ∝ σ^p for the variant `request` resolves to, over σ 4…16 px (σ-held), or over the primary
    /// parameter in its own px unit for entries without a σ. Points where another variant would run are left out.
    func costExponent(_ op: any BlurOperator, request: OperatorRequest) -> Double? {
        let entry = op.entry
        let running = op.resolveVariant(request).variant
        var xs: [Double] = [], ys: [Double] = []
        for size in Self.costFitSigmas {
            guard let held = AnalysisMath.parameters(for: op, entry: entry, size: size, base: request.parameters) else { return nil }
            let r = AnalysisMath.request(request, parameters: held.parameters)
            guard op.resolveVariant(r).variant == running else { continue }
            let fetches = op.passPlan(r).fetchesPerPixel
            guard fetches > 0, fetches.isFinite else { continue }
            xs.append(held.x); ys.append(fetches)
        }
        guard ys.count >= 2 else { return nil }
        if Set(ys.map { ($0 * 1e9).rounded() }).count == 1 { return 0 }
        return AnalysisMath.logLogSlope(xs, ys)
    }
}
