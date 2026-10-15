import Foundation
import Testing
@testable import BlurCore

// OWNER: ANALYSIS. Fixtures for the ANALYSIS suites: configuration builders, a stub tool-convention provider and a small
// configurable operator that stands in for catalog entries this mirror does not register yet (box, SAT box, explicit heat
// equation, median, zoom, spin, the SwiftUI system blur). The fixtures follow the floor-key conventions requested from the
// FAM areas in Documentation/build/requests/ANALYSIS.md; they exercise the engines' rules, never replace the real entries,
// and their ids all start with "fixture-".

enum ANALYSIS_Fixtures {
    static let window = 894
    static let centre = PixelPoint(x: 447, y: 447)

    /// A configuration of a registered or fixture entry: its defaults, σ-held at `sigma` when given.
    static func configuration(_ op: any BlurOperator, variant: VariantID? = nil, sigma: Double? = nil,
                              parameters overrides: [ParameterKey: ParameterValue] = [:], settings: SilentSettings = .standard,
                              specimen: SpecimenID = "step-edges") -> RenderConfiguration {
        let entry = op.entry
        var parameters = entry.defaultParameters
        if let sigma { parameters = op.holdingSigma(sigma, current: parameters).parameters }
        for (k, v) in overrides { parameters[k] = v }
        return RenderConfiguration(blur: entry.id, variant: variant ?? entry.defaultVariant, parameters: parameters, settings: settings,
                                   specimen: specimen, specimenOptions: .standard, pan: .zero, probe: centre, windowSize: window)
    }

    static func gaussian(_ sigma: Double, variant: VariantID = GaussianOperator.linearSampled,
                         settings: SilentSettings = .standard) -> RenderConfiguration {
        configuration(GaussianOperator(), variant: variant, sigma: sigma, settings: settings)
    }

    static func stats(maxAbs: Double, ulp: Double, lsb: Double) -> DifferenceStats {
        DifferenceStats(maxAbs: maxAbs, rms: maxAbs / 3, argmax: PixelPoint(x: 3, y: 4), maxLSB8: lsb, maxULP16: ulp, count: 128 * 128)
    }

    static let device = DeviceStamp(deviceModel: "iPhone 15 Pro Max", gpuName: "Apple A17 Pro GPU", gpuFamily: "Apple9", osVersion: "iOS 27.0",
                                    osBuild: "24A5355p", isSimulator: false, date: Date(timeIntervalSince1970: 1_792_000_000),
                                    thermal: .nominal, lowPowerMode: false)

    // MARK: Fixture entries

    static let box = ANALYSIS_FixtureOperator.box()
    static let heat = ANALYSIS_FixtureOperator.heat()
    static let median = ANALYSIS_FixtureOperator.median()
    static let zoom = ANALYSIS_FixtureOperator.lineBlur(id: "fixture-zoom", name: "Zoom blur (fixture)", math: "zoom", radial: true)
    static let spin = ANALYSIS_FixtureOperator.lineBlur(id: "fixture-spin", name: "Spin blur (fixture)", math: "spin", radial: false)
    static let swiftUI = ANALYSIS_FixtureOperator.swiftUI()
    static let disc = ANALYSIS_FixtureOperator.disc()
    static let tent = ANALYSIS_FixtureOperator.tent()

    static var all: [any BlurOperator] { [GaussianOperator(), box, heat, median, zoom, spin, swiftUI, disc, tent] }

    /// An engine over the fixtures plus the real Gaussian, with deterministic tool conventions.
    static func engine(tools: (any ToolConventionProviding)? = ANALYSIS_StubTools()) -> DivergenceEngine {
        DivergenceEngine(operators: all, tools: tools)
    }

    /// Every honesty problem of every row line.
    static func violations(_ rows: [DivergenceEngine.Row]) -> [String] {
        rows.flatMap { row in row.line.honestyViolations.map { "\(row.floor.railLabel): \($0) in '\(row.line.text)'" } }
    }
}

/// Deterministic tool conventions (SPEC §4.1.4 and STACK §8 shapes): CSS offers only Gaussian blurs (σ = value · scale,
/// REFERENCE); SwiftUI offers its own layer blur and σ-matches a Gaussian (σ ≈ 0.90·r·scale above 5 px, INFERRED,
/// OFFSCREEN); neither offers a box blur. Photoshop is UNVERIFIED for everything.
struct ANALYSIS_StubTools: ToolConventionProviding {
    var all: [ToolConvention] {
        [ToolConvention(id: "css", toolName: "CSS", controlName: "filter: blur()", unit: .cssPx, provenance: .reference,
                        source: SourceRef("Filter Effects Module Level 1"), lawDescription: "σ = value"),
         ToolConvention(id: "swiftui", toolName: "SwiftUI", controlName: ".blur(radius:)", unit: .pt, provenance: .inferred,
                        source: SourceRef("live-calibration.md §5.1"), lawDescription: "σ ≈ 0.90·r·scale above ≈ 5 px")]
    }

    func typedValue(toolID: String, blur: BlurID, sigmaPx: Double, displayScale: Double, measuredLaw: CalibrationLaw?) -> BadgedValue {
        let gaussianFamily: Set<BlurID> = ["gaussian-blur", "fixture-heat"]
        switch toolID {
        case "css" where gaussianFamily.contains(blur):
            return .number(sigmaPx / displayScale, .decimals(1, unit: "CSS px", spokenUnit: "CSS pixels"), .reference,
                           source: SourceRef("Filter Effects Module Level 1"))
        case "swiftui" where blur == "fixture-swiftui" || gaussianFamily.contains(blur):
            let r = sigmaPx <= 5 ? sigmaPx / displayScale : sigmaPx / (0.9 * displayScale)
            return .number(r, .decimals(1, unit: "pt", spokenUnit: "points"), .inferred, qualifiers: .offscreen, caption: "OFFSCREEN")
        case "photoshop":
            return .unverified("Photoshop mapping")
        default:
            return .words("—", spoken: "not offered in \(toolID)")
        }
    }

    func sigmaPx(toolID: String, blur: BlurID, typed value: Double, displayScale: Double, measuredLaw: CalibrationLaw?) -> BadgedValue {
        .unverified("reverse mapping")
    }
}

/// A small, honest stand-in for one catalog entry: real kernels and plans, catalog facts reduced to what the engines read.
struct ANALYSIS_FixtureOperator: BlurOperator {
    let entry: CatalogEntry
    let kernelOf: @Sendable (OperatorRequest) -> Kernel2D?
    let sigmaOf: @Sendable (OperatorRequest) -> Double?
    let planOf: @Sendable (OperatorRequest) -> PassPlan
    let keyOf: @Sendable (Floor, OperatorRequest) -> FloorKey
    let hold: @Sendable (Double, ParameterValues) -> (ParameterValues, Double?)

    func passPlan(_ request: OperatorRequest) -> PassPlan { planOf(request) }
    func psf(at point: PixelPoint, _ request: OperatorRequest, content: OperatorContent?) -> PSF? {
        kernelOf(request).map { PSF(kernel: $0, isLocal: entry.linearity == .lsv, point: entry.linearity == .lsv ? point : nil, provenance: .computed) }
    }
    func response(_ query: ResponseQuery, _ request: OperatorRequest, content: OperatorContent?) -> ResponseCurve? {
        guard let k = kernelOf(request) else { return nil }
        let f = query.frequencies
        return ResponseCurve(kind: .signedTransfer, frequencies: f, values: KernelMath.response(k.marginalX, frequencies: f))
    }
    func sigma(_ request: OperatorRequest) -> Double? { sigmaOf(request) }
    func holdingSigma(_ sigma: Double, current: ParameterValues) -> SigmaHoldResult {
        let (p, achieved) = hold(sigma, current)
        let line: BadgedLine = achieved == nil ? .words("σ NOT DEFINED")
            : SigmaHoldResult.standardLine(held: sigma, converted: [], achieved: achieved, isClamped: false)
        return SigmaHoldResult(parameters: p, requestedSigma: sigma, achievedSigma: achieved, statusLine: line)
    }
    func reference(_ input: ImageBuffer, _ request: OperatorRequest, auxiliary: AuxiliaryInputs,
                   options: ReferenceOptions) throws -> ReferenceResult { throw ReferenceError.notImplemented("fixture") }
    func traceReconstruction(probe: PixelPoint, input: ImageBuffer, _ request: OperatorRequest, auxiliary: AuxiliaryInputs) -> TraceRecord {
        TraceRecord(blur: entry.id, variant: request.variant, parameters: request.parameters, settings: request.settings, probe: probe,
                    input: .zero, passes: [], gpuOutput: nil, cpuReference: .zero, differenceULP16: nil, tracedEqualsUntraced: nil)
    }
    func uniqueNumber(_ request: OperatorRequest) -> LabeledValue {
        LabeledValue(id: "unique", label: "UNIQUE", value: .words("FIXTURE"))
    }
    func floorKey(_ floor: Floor, _ request: OperatorRequest) -> FloorKey { keyOf(floor, request) }

    // MARK: Entry builder

    static func entry(id: BlurID, name: String, linearity: LinearityClass = .lsi, verdict: Verdict = .trueBlur, tier: Tier = .tier1,
                      algorithm: AlgorithmClass = .separableFIR, cost: CostClass = .linearR, primary: ParameterSpec,
                      variants: [VariantDescriptor]) -> CatalogEntry {
        let row = CardRow("fixture", .computed)
        return CatalogEntry(id: id, displayName: name, family: .f1, tier: tier, verdict: verdict, linearity: linearity, separability: .yes,
                            properties: [], costClass: cost, algorithmClass: algorithm, signature: "Fixture.", mathSymbol: "fx",
                            glyph: GlyphSpec(.none), parameters: [primary], primary: primary.key, deck: .crownPair(primary.key),
                            variants: variants, defaultVariant: variants[0].id, defaultSpecimen: "step-edges", handles: [], appleTwins: [],
                            tell: TellSpec(specimen: "step-edges", text: "Fixture."), neighbours: [], traceDepth: .full, heroOrder: nil,
                            card: CardRows(psfShape: row, response: row, edges: row, cost: row, artifacts: row, usedIn: row),
                            unverified: [], detailReference: "fixture", sources: [])
    }

    static func variant(_ id: VariantID, _ name: String, _ algorithm: AlgorithmClass = .separableFIR, _ cost: CostClass = .linearR,
                        tier: Tier = .tier1) -> VariantDescriptor {
        VariantDescriptor(id: id, displayName: name, tier: tier, algorithmClass: algorithm, costClass: cost, runsOnGPU: true)
    }

    static func integerSpec(_ key: ParameterKey, _ label: String, range: ClosedRange<Int>, _ value: Int, unit: ParameterUnit = .px) -> ParameterSpec {
        ParameterSpec(key: key, label: label, spokenLabel: label.lowercased(), unit: unit, kind: .integer(IntegerSpec(range: range)),
                      defaultValue: .int(value))
    }

    static func continuousSpec(_ key: ParameterKey, _ label: String, range: ClosedRange<Double>, _ value: Double,
                               unit: ParameterUnit = .px) -> ParameterSpec {
        ParameterSpec(key: key, label: label, spokenLabel: label.lowercased(), unit: unit,
                      kind: .continuous(ContinuousSpec(range: range, fineStep: 0.1, decimals: 1)), defaultValue: .double(value))
    }

    static func twoPass(_ name: String, taps: Double, fetches: Double, radius: Int, kind: PassKind = .fragment) -> PassPlan {
        PassPlan(algorithmName: name, passes: [
            PassDescriptor(id: 0, name: "H", kind: kind, fetchesPerPixel: fetches, tapsPerPixel: taps, traceable: true, summary: "horizontal"),
            PassDescriptor(id: 1, name: "V", kind: kind, fetchesPerPixel: fetches, tapsPerPixel: taps, traceable: true, summary: "vertical")],
                 supportRadius: radius)
    }

    // MARK: Fixtures

    /// Box of width 2r + 1: separable (default) or summed-area table; σ² = ((2r + 1)² − 1)/12; held to the nearest odd width.
    static func box() -> ANALYSIS_FixtureOperator {
        let separable: VariantID = "fixture-box-separable", sat: VariantID = "fixture-sat-box"
        let e = entry(id: "fixture-box", name: "Box blur (fixture)", primary: integerSpec("radius", "RADIUS", range: 1...128, 4),
                      variants: [variant(separable, "Separable"), variant(sat, "SAT", .runningSum, .constant)])
        @Sendable func r(_ q: OperatorRequest) -> Int { q.parameters.int("radius") ?? 4 }
        return ANALYSIS_FixtureOperator(
            entry: e,
            kernelOf: { q in let k = KernelMath.box(radius: r(q)); return Kernel2D(separable: k, k) },
            sigmaOf: { q in let w = Double(2 * r(q) + 1); return ((w * w - 1) / 12).squareRoot() },
            planOf: { q in
                let w = Double(2 * r(q) + 1)
                if q.variant == sat {
                    return PassPlan(algorithmName: "SAT", passes: [
                        PassDescriptor(id: 0, name: "SCAN ROWS", kind: .compute, fetchesPerPixel: 1, tapsPerPixel: 1, traceable: false, summary: "row prefix sums"),
                        PassDescriptor(id: 1, name: "SCAN COLUMNS", kind: .compute, fetchesPerPixel: 1, tapsPerPixel: 1, traceable: false, summary: "column prefix sums"),
                        PassDescriptor(id: 2, name: "QUERY", kind: .fragment, fetchesPerPixel: 4, tapsPerPixel: 4, traceable: true, summary: "4 corners")],
                                    supportRadius: r(q) + 1)
                }
                return twoPass("Separable", taps: w, fetches: w, radius: r(q))
            },
            keyOf: { floor, q in
                let w = Double(2 * r(q) + 1)
                switch floor {
                case .slide: return FloorKey(identity: ["radius"], numbers: [Double(r(q))], description: "r \(r(q))")
                case .math: return FloorKey(identity: ["rect"], numbers: [w], description: "rect")
                case .kernel: return FloorKey(identity: ["fir"], numbers: [w], description: "\(Int(w)) equal weights")
                case .gpu: return FloorKey(identity: [q.variant == sat ? "table" : "integer"], description: "integer fetches")
                default: return FloorKey(identity: [floor.railLabel], description: floor.title)
                }
            },
            hold: { sigma, current in
                var p = current
                let raw = (12 * sigma * sigma + 1).squareRoot()
                var w = Int(raw.rounded()); if w % 2 == 0 { w += raw > Double(w) ? 1 : -1 }
                w = max(3, w)
                p["radius"] = .int((w - 1) / 2)
                return (p, ((Double(w * w) - 1) / 12).squareRoot())
            })
    }

    /// Tent (triangle) of radius r: σ² = r(r + 2)/6.
    static func tent() -> ANALYSIS_FixtureOperator {
        let e = entry(id: "fixture-tent", name: "Tent blur (fixture)", primary: integerSpec("radius", "RADIUS", range: 1...128, 4),
                      variants: [variant("fixture-tent-separable", "Separable")])
        @Sendable func r(_ q: OperatorRequest) -> Int { q.parameters.int("radius") ?? 4 }
        return ANALYSIS_FixtureOperator(
            entry: e,
            kernelOf: { q in let k = KernelMath.tent(radius: r(q)); return Kernel2D(separable: k, k) },
            sigmaOf: { q in (Double(r(q) * (r(q) + 2)) / 6).squareRoot() },
            planOf: { q in twoPass("Separable", taps: Double(2 * r(q) + 1), fetches: Double(2 * r(q) + 1), radius: r(q)) },
            keyOf: { floor, q in FloorKey(identity: [floor == .math ? "tent" : floor.railLabel], numbers: [Double(r(q))], description: "tent") },
            hold: { sigma, current in
                var p = current
                let r = max(1, Int(((6 * sigma * sigma + 1).squareRoot() - 1).rounded()))
                p["radius"] = .int(r)
                return (p, (Double(r * (r + 2)) / 6).squareRoot())
            })
    }

    /// Uniform disc of radius R px (2-D gather): σ = R/2 continuous.
    static func disc() -> ANALYSIS_FixtureOperator {
        let e = entry(id: "fixture-disc", name: "Disc blur (fixture)", algorithm: .gather2D, cost: .quadraticR,
                      primary: continuousSpec("radius", "RADIUS", range: 1...128, 8), variants: [variant("fixture-disc-gather", "Gather", .gather2D, .quadraticR)])
        @Sendable func discKernel(_ R: Double) -> Kernel2D {
            let n = Int(R.rounded(.up)), size = 2 * n + 1
            var w = [Double](repeating: 0, count: size * size)
            let sub = 8   // supersampled coverage, so the PSF is round, not stepped
            for y in 0..<size { for x in 0..<size {
                var inside = 0
                for j in 0..<sub { for i in 0..<sub {
                    let dx = Double(x - n) - 0.5 + (Double(i) + 0.5) / Double(sub), dy = Double(y - n) - 0.5 + (Double(j) + 0.5) / Double(sub)
                    if dx * dx + dy * dy <= R * R { inside += 1 }
                } }
                w[y * size + x] = Double(inside)
            } }
            let total = w.reduce(0, +)
            return Kernel2D(width: size, height: size, originX: n, originY: n, weights: w.map { $0 / total })
        }
        @Sendable func R(_ q: OperatorRequest) -> Double { q.parameters.double("radius") ?? 8 }
        return ANALYSIS_FixtureOperator(
            entry: e, kernelOf: { q in discKernel(R(q)) },
            sigmaOf: { q in AnalysisMath.axisSigmas(discKernel(R(q)))?.x },
            planOf: { q in
                let taps = Double(discKernel(R(q)).weights.filter { $0 > 0 }.count)
                return PassPlan(algorithmName: "Gather", passes: [PassDescriptor(id: 0, name: "2-D", kind: .fragment, fetchesPerPixel: taps,
                                                                                tapsPerPixel: taps, traceable: true, summary: "disc gather")],
                                supportRadius: Int(R(q).rounded(.up)))
            },
            keyOf: { floor, q in FloorKey(identity: [floor == .math ? "disc" : floor.railLabel], numbers: [R(q)], tolerance: 0.05, description: "disc") },
            hold: { sigma, current in var p = current; p["radius"] = .double(2 * sigma); return (p, sigma) })
    }

    /// Explicit 5-point heat equation at λ = ¼ (SPEC §17 item 1): t in px², 4t steps; per-axis variance 2t exactly.
    static func heat() -> ANALYSIS_FixtureOperator {
        let e = entry(id: "fixture-heat", name: "Heat equation (fixture)", algorithm: .iterativePDE, cost: .iterative,
                      primary: continuousSpec("time", "TIME", range: 0.25...512, 8, unit: .pixelsSquared),
                      variants: [variant("fixture-heat-explicit", "Explicit", .iterativePDE, .iterative)])
        @Sendable func steps(_ q: OperatorRequest) -> Int { max(1, Int(((q.parameters.double("time") ?? 8) * 4).rounded())) }
        @Sendable func kernel(_ n: Int) -> Kernel2D {
            // u ← u + ¼·(4-neighbour Laplacian) = ¼·(sum of the four neighbours): the centre weight is 1 − 4λ = 0.
            // One spare ring keeps the n-step support (radius n) away from the array edge.
            let c = n + 1, size = 2 * c + 1
            var w = [Double](repeating: 0, count: size * size)
            w[c * size + c] = 1
            for _ in 0..<n {
                var next = [Double](repeating: 0, count: size * size)
                for y in 1..<(size - 1) { for x in 1..<(size - 1) {
                    let i = y * size + x
                    next[i] = 0.25 * (w[i - 1] + w[i + 1] + w[i - size] + w[i + size])
                } }
                w = next
            }
            return Kernel2D(width: size, height: size, originX: c, originY: c, weights: w)
        }
        return ANALYSIS_FixtureOperator(
            entry: e, kernelOf: { q in kernel(steps(q)) },
            sigmaOf: { q in (2 * (q.parameters.double("time") ?? 8)).squareRoot() },
            planOf: { q in
                let n = steps(q)
                return PassPlan(algorithmName: "Explicit", passes: (0..<n).map {
                    PassDescriptor(id: $0, name: "STEP \($0 + 1)", kind: .fragment, fetchesPerPixel: 5, tapsPerPixel: 5, traceable: true, summary: "5-point")
                }, supportRadius: n)
            },
            keyOf: { floor, q in
                let t = q.parameters.double("time") ?? 8
                switch floor {
                case .math: return FloorKey(identity: ["gaussian"], numbers: [(2 * t).squareRoot()], tolerance: 0.05, description: "bell")
                case .kernel: return FloorKey(identity: ["explicit-5-point"], numbers: [t], description: "5-point steps")
                default: return FloorKey(identity: [floor.railLabel], description: floor.title)
                }
            },
            hold: { sigma, current in
                var p = current
                let t = (sigma * sigma / 2 * 4).rounded() / 4    // whole λ = ¼ steps
                p["time"] = .double(t)
                return (p, (2 * t).squareRoot())
            })
    }

    /// Median of a (2r + 1)² window: a rank filter with no PSF, no response and no σ.
    static func median() -> ANALYSIS_FixtureOperator {
        let e = entry(id: "fixture-median", name: "Median (fixture)", linearity: .nonlinear, verdict: .rankFilter, algorithm: .selection,
                      cost: .quadraticR, primary: integerSpec("radius", "RADIUS", range: 1...16, 2),
                      variants: [variant("fixture-median-window", "Window", .selection, .quadraticR)])
        return ANALYSIS_FixtureOperator(
            entry: e, kernelOf: { _ in nil }, sigmaOf: { _ in nil },
            planOf: { q in
                let n = Double((2 * (q.parameters.int("radius") ?? 2) + 1) * (2 * (q.parameters.int("radius") ?? 2) + 1))
                return PassPlan(algorithmName: "Window", passes: [PassDescriptor(id: 0, name: "RANK", kind: .fragment, fetchesPerPixel: n,
                                                                                tapsPerPixel: n, traceable: true, summary: "sort")],
                                supportRadius: q.parameters.int("radius") ?? 2)
            },
            keyOf: { floor, q in FloorKey(identity: [floor == .math ? "rank" : floor.railLabel, "median"],
                                          numbers: [Double(q.parameters.int("radius") ?? 2)], description: floor == .math ? "rank" : "median window") },
            hold: { _, current in (current, nil) })
    }

    /// A space-variant line blur: radial (zoom) or tangential (spin) at the probe; no σ ("σ NOT DEFINED · SPACE-VARIANT").
    static func lineBlur(id: BlurID, name: String, math: String, radial: Bool) -> ANALYSIS_FixtureOperator {
        let e = entry(id: id, name: name, linearity: .lsv, verdict: .lsvBlur, algorithm: .spaceVariantGather, cost: .samples,
                      primary: continuousSpec("amount", "AMOUNT", range: 1...100, 10, unit: .percent),
                      variants: [variant(VariantID(rawValue: id.rawValue + "-gather"), "Gather", .spaceVariantGather, .samples)])
        return ANALYSIS_FixtureOperator(
            entry: e,
            kernelOf: { _ in
                // 9 taps along x (radial at a probe right of the centre) or along y (tangential there).
                let w = [Double](repeating: 1.0 / 9, count: 9)
                return radial ? Kernel2D(width: 9, height: 1, originX: 4, originY: 0, weights: w)
                    : Kernel2D(width: 1, height: 9, originX: 0, originY: 4, weights: w)
            },
            sigmaOf: { _ in nil },
            planOf: { _ in PassPlan(algorithmName: "Gather", passes: [PassDescriptor(id: 0, name: "GATHER", kind: .fragment, fetchesPerPixel: 32,
                                                                                    tapsPerPixel: 32, traceable: true, summary: "32 samples")],
                                    supportRadius: 64) },
            keyOf: { floor, q in FloorKey(identity: [floor == .math ? math : floor.railLabel], numbers: [q.parameters.double("amount") ?? 10],
                                          description: floor == .math ? (radial ? "scaling about the centre" : "rotation about the centre") : floor.title) },
            hold: { _, current in (current, nil) })
    }

    /// SwiftUI `.blur(radius:)` as a system entry: σ ≈ 0.90·r·scale (MEASURED macOS law), internals INFERRED.
    static func swiftUI() -> ANALYSIS_FixtureOperator {
        let e = entry(id: "fixture-swiftui", name: "SwiftUI .blur (fixture)", linearity: .system, tier: .system, algorithm: .system,
                      cost: .capture, primary: continuousSpec("radius", "RADIUS", range: 0...100, 10, unit: .pt),
                      variants: [variant("fixture-swiftui-system", "System", .system, .capture, tier: .system)])
        @Sendable func r(_ q: OperatorRequest) -> Double { q.parameters.double("radius") ?? 10 }
        return ANALYSIS_FixtureOperator(
            entry: e, kernelOf: { _ in nil }, sigmaOf: { q in 0.9 * r(q) * 3 },
            planOf: { _ in PassPlan(algorithmName: "System", passes: [PassDescriptor(id: 0, name: "SYSTEM", kind: .coreImage, fetchesPerPixel: 1,
                                                                                    tapsPerPixel: 1, traceable: false, summary: "render server")]) },
            keyOf: { floor, q in FloorKey(identity: [floor == .math ? "swiftui-inferred" : floor.railLabel], numbers: [r(q)],
                                          description: floor == .math ? "box³-like (INFERRED)" : floor.title) },
            hold: { sigma, current in var p = current; p["radius"] = .double(sigma / (0.9 * 3)); return (p, sigma) })
    }
}
