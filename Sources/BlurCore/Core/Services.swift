import Foundation

// FROZEN — ARCHITECTURE.md §5.5. Service seams between BlurCore areas. The skeleton ships minimal working conformers
// under the type names listed in Registry.swift; the owning area replaces the implementation behind the same name.

/// SPEC §5: builds the seven pages, the rail chips and the pills from operator facts, generic templates and live Runs.
/// Owner: CONTENT-LAYERS (`FloorPageBuilder`).
public protocol FloorPageBuilding: Sendable {
    func pages(for op: any BlurOperator, context: FloorContext) -> [FloorPage]
    func page(_ floor: Floor, for op: any BlurOperator, context: FloorContext) -> FloorPage
    func railChips(for op: any BlurOperator, context: FloorContext) -> [RailChip]
    func pills(for op: any BlurOperator, context: FloorContext) -> PillContent
}

/// SPEC §6.3: turns a TraceRecord into steps with sub-steps. Owner: CONTENT-LAYERS (`TraceScripter`).
public protocol TraceScripting: Sendable {
    func steps(for record: TraceRecord, op: any BlurOperator, context: FloorContext) -> [TraceStep]
}

/// SPEC §8.4: the first floor where two configurations part ways. Owner: ANALYSIS (`DivergenceEngine`).
public protocol DivergenceComputing: Sendable {
    /// Seven rows, one per floor; the first `.differs` is reported as `.partsWays`.
    func compare(_ a: RenderConfiguration, _ b: RenderConfiguration, homeToolID: String, displayScale: Double) -> [FloorComparison]
}

/// SPEC §7.4: what the matrix sorts by and LOOKS MOST LIKE compares. Blank cells stay nil ("— NOT YET COMPUTED").
public struct FingerprintVector: Sendable, Codable, Hashable {
    public var excessKurtosisAxis: Double?
    public var excessKurtosis45: Double?
    public var minResponse: Double?
    public var firstZero: Double?
    /// Support radius at 10⁻⁴ of peak, divided by σ.
    public var supportOverSigma: Double?
    public var linearity: LinearityClass
    /// Fetches ∝ r^p.
    public var costExponent: Double?
    /// Edge-centre spread over 4 phases, px.
    public var shiftVariancePx: Double?
    public init(excessKurtosisAxis: Double?, excessKurtosis45: Double?, minResponse: Double?, firstZero: Double?,
                supportOverSigma: Double?, linearity: LinearityClass, costExponent: Double?, shiftVariancePx: Double?) {
        self.excessKurtosisAxis = excessKurtosisAxis; self.excessKurtosis45 = excessKurtosis45; self.minResponse = minResponse
        self.firstZero = firstZero; self.supportOverSigma = supportOverSigma; self.linearity = linearity
        self.costExponent = costExponent; self.shiftVariancePx = shiftVariancePx
    }
}

/// Owner: ANALYSIS (`FingerprintEngine`).
public protocol FingerprintComputing: Sendable {
    /// COMPUTED at the reference size σ_equiv = 4 px (equal second moment; CATALOG §7 convention).
    func vector(for op: any BlurOperator) -> FingerprintVector
    /// The same statistics from a measured shape (ON THIS PHONE).
    func vector(measured: ShapeMeasurement, linearity: LinearityClass) -> FingerprintVector
    /// LOOKS MOST LIKE: nearest catalog entry to a vector, with its distance.
    func nearest(to vector: FingerprintVector, among ops: [any BlurOperator]) -> (blur: BlurID, distance: Double)?
}

/// One tool's meaning of its blur number (STACK §8: the 16 meanings of "radius"). Owner: SEMANTICS (`ToolConventions`).
public struct ToolConvention: Sendable, Codable, Hashable, Identifiable {
    public var id: String                  // "swiftui", "css", "figma", "photoshop", "coreimage", "android", "flutter", …
    public var toolName: String            // "SwiftUI"
    public var controlName: String         // ".blur(radius:)"
    public var unit: ParameterUnit
    public var provenance: Provenance
    public var source: SourceRef
    /// "σ = r·scale below ≈ 5 px, 0.90·r·scale above"; nil when the mapping is UNVERIFIED (shown as words).
    public var lawDescription: String?
    public init(id: String, toolName: String, controlName: String, unit: ParameterUnit, provenance: Provenance,
                source: SourceRef, lawDescription: String?) {
        self.id = id; self.toolName = toolName; self.controlName = controlName; self.unit = unit
        self.provenance = provenance; self.source = source; self.lawDescription = lawDescription
    }
}

public protocol ToolConventionProviding: Sendable {
    var all: [ToolConvention] { get }
    /// What a person would type in `toolID` to get per-axis σ = `sigmaPx` for `blur` at `displayScale`. A measured
    /// SwiftUI law from this phone replaces the macOS law; unknown mappings return `.unverified`.
    func typedValue(toolID: String, blur: BlurID, sigmaPx: Double, displayScale: Double,
                    measuredLaw: CalibrationLaw?) -> BadgedValue
    /// Reverse mode ("you typed 10"): the σ in px produced by typing `value` in `toolID`.
    func sigmaPx(toolID: String, blur: BlurID, typed value: Double, displayScale: Double,
                 measuredLaw: CalibrationLaw?) -> BadgedValue
}

/// MODELED bytes and bandwidth floors (GPU §4.1–§4.2). Owner: ANALYSIS (`CostModel`).
public protocol CostModeling: Sendable {
    func cost(for plan: PassPlan, size: ImageSize, intermediate: IntermediateFormat, bandwidth: BandwidthAssumption) -> CostSummary
    /// Fetches per pixel against size for the family's algorithms (the Algorithm floor's cost plot).
    func costCurve(for op: any BlurOperator, request: OperatorRequest, sizes: [Double]) -> [PlotSeries]
}

/// Field guide pages with citations (SPEC §4.7 Guide tab). Owner: CONTENT-LAYERS (`FieldGuideLibrary`).
public protocol FieldGuideProviding: Sendable {
    func page(for op: any BlurOperator, context: FloorContext) -> FieldGuidePage
    /// HONESTY LABELS legend and THE LENS ON THIS INSTRUMENT (SPEC §12.4–§12.5).
    var honestyLegend: [ContentBlock] { get }
    var lensNote: [ContentBlock] { get }
}

// MARK: - Compare vocabulary and lessons (SPEC §8.2–§8.5). Lesson data is owned by CONTENT-LAYERS (`LessonLibrary`).

public enum CompareAxis: String, Sendable, Codable, Hashable, CaseIterable { case `operator`, implementation, precision, space, apple }
public enum MatchRule: String, Sendable, Codable, Hashable, CaseIterable { case sigma, fwhm, edgeWidth, cost, none }
public enum CompareView: String, Sendable, Codable, Hashable, CaseIterable {
    case wipe, flip, difference1, difference16, difference256, lineUp
    public var differenceGain: Double? {
        switch self {
        case .difference1: 1
        case .difference16: 16
        case .difference256: 256
        default: nil
        }
    }
}

public enum LessonKind: String, Sendable, Codable, Hashable { case pair, guidedDescent }

public struct Lesson: Sendable, Codable, Hashable, Identifiable {
    public var id: String                  // "P1" … "P30", "descent-A" … "descent-D"
    public var kind: LessonKind
    /// Hook title ("Why zoom blur spares a star").
    public var title: String
    public var setupLine: String
    /// A, then B (and C, D for Line-up). Guided descents use only A.
    public var configurations: [RenderConfiguration]
    public var axis: CompareAxis
    public var match: MatchRule
    public var view: CompareView?
    /// The "Look for" numbers with their badges.
    public var lookFor: [LabeledValue]
    /// Written into the status row until any control changes (numbers badged, review fix E-51).
    public var statusLine: BadgedLine
    public init(id: String, kind: LessonKind, title: String, setupLine: String, configurations: [RenderConfiguration],
                axis: CompareAxis, match: MatchRule, view: CompareView?, lookFor: [LabeledValue], statusLine: BadgedLine) {
        self.id = id; self.kind = kind; self.title = title; self.setupLine = setupLine; self.configurations = configurations
        self.axis = axis; self.match = match; self.view = view; self.lookFor = lookFor; self.statusLine = statusLine
    }
}
