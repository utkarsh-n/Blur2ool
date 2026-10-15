import Foundation

// FROZEN — ARCHITECTURE.md §5.11. Layer content model (SPEC §5): pages are DATA generated from BlurCore and rendered by
// App/Content (UI-LAYERS). One model feeds the Bench rail and pills, the Layers pages, the Trace panels, the Divergence
// rows and the Field guide (JF M-12).

public enum SeriesStyle: String, Sendable, Codable, Hashable { case solid, dashed, dotted, dashDot, stems, points, quiet }

public enum SeriesRole: String, Sendable, Codable, Hashable {
    /// Primary data (discrete taps, DFT of the taps).
    case primary
    /// Quiet reference (continuous kernel or response).
    case reference
    /// Depth trace: the effective kernel after all passes (wave secondary ink).
    case depth
    /// Compare series B, C, D (dashed, dotted, dash-dot).
    case comparisonB, comparisonC, comparisonD
    /// Measured points (this phone), filled; `reference` dashed for the Mac.
    case measured
}

public struct PlotAxis: Sendable, Codable, Hashable {
    public var label: String
    public var unit: String?
    /// Spoken and printed as "normalized" when true (Metro contract A.21).
    public var normalized: Bool
    public var range: ClosedRange<Double>?
    public var logarithmic: Bool
    public init(label: String, unit: String? = nil, normalized: Bool = false, range: ClosedRange<Double>? = nil,
                logarithmic: Bool = false) {
        self.label = label; self.unit = unit; self.normalized = normalized; self.range = range; self.logarithmic = logarithmic
    }
}

public struct PlotSeries: Sendable, Codable, Hashable {
    public var name: String
    public var xs: [Double]
    public var ys: [Double]
    public var style: SeriesStyle
    public var role: SeriesRole
    public var provenance: Provenance
    public init(name: String, xs: [Double], ys: [Double], style: SeriesStyle, role: SeriesRole, provenance: Provenance) {
        precondition(xs.count == ys.count)
        self.name = name; self.xs = xs; self.ys = ys; self.style = style; self.role = role; self.provenance = provenance
    }
}

public enum MarkerKind: String, Sendable, Codable, Hashable {
    /// −3 dB tick (carrier ink).
    case minus3dB
    case halfAmplitude, firstZero, probe, supportBracket
    /// The SwiftUI regime switch: hollow while INFERRED, filled when MEASURED.
    case regimeSwitch
    case custom
}

public struct PlotMarker: Sendable, Codable, Hashable {
    public var x: Double
    public var label: String
    public var kind: MarkerKind
    public var provenance: Provenance?
    public init(x: Double, label: String, kind: MarkerKind, provenance: Provenance? = nil) {
        self.x = x; self.label = label; self.kind = kind; self.provenance = provenance
    }
}

public struct PlotSpec: Sendable, Codable, Hashable {
    public var xAxis: PlotAxis
    public var yAxis: PlotAxis
    public var series: [PlotSeries]
    public var markers: [PlotMarker]
    /// Draw y = 0 and shade values below it (signed responses: negative lobes shaded AND dashed, SPEC §4.1.3).
    public var showsZeroLine: Bool
    /// One-sentence summary for VoiceOver and the AXChartDescriptor.
    public var accessibilitySummary: String
    public init(xAxis: PlotAxis, yAxis: PlotAxis, series: [PlotSeries], markers: [PlotMarker] = [], showsZeroLine: Bool = false,
                accessibilitySummary: String) {
        self.xAxis = xAxis; self.yAxis = yAxis; self.series = series; self.markers = markers
        self.showsZeroLine = showsZeroLine; self.accessibilitySummary = accessibilitySummary
    }
}

public struct HeatmapSpec: Sendable, Codable, Hashable {
    public var width: Int
    public var height: Int
    public var values: [Double]
    public var signed: Bool
    public var centre: PixelPoint?
    public var caption: String
    public var provenance: Provenance
    public init(width: Int, height: Int, values: [Double], signed: Bool, centre: PixelPoint?, caption: String, provenance: Provenance) {
        precondition(values.count == width * height)
        self.width = width; self.height = height; self.values = values; self.signed = signed; self.centre = centre
        self.caption = caption; self.provenance = provenance
    }
}

public enum TexelChannel: String, Sendable, Codable, Hashable { case luma, red, green, blue, alpha }

/// A copy of texel values around the probe (never drawn on the specimen itself).
public struct TexelGridSpec: Sendable, Codable, Hashable {
    public var size: Int                 // 9 or 17
    public var origin: PixelPoint        // top-left texel in window pixels
    public var channel: TexelChannel
    public var values: [Double]          // size × size, linear light
    public var weights: [Double]?        // per-texel weights of the current pass (amber bars)
    public var highlighted: [PixelPoint] // probe, fetch positions
    public var provenance: Provenance
    public init(size: Int, origin: PixelPoint, channel: TexelChannel, values: [Double], weights: [Double]?,
                highlighted: [PixelPoint], provenance: Provenance) {
        self.size = size; self.origin = origin; self.channel = channel; self.values = values; self.weights = weights
        self.highlighted = highlighted; self.provenance = provenance
    }
}

/// Dispatch geometry drawn over a COPY of the output (floor 6 Silicon).
public struct DispatchOverlaySpec: Sendable, Codable, Hashable {
    public var dispatch: PassDispatch
    public var apronTexels: Int
    public var probeThreadgroup: [Int]
    public var probeThreadInGroup: [Int]
    public var probeSIMDGroup: Int
    public var probeLane: Int
    public init(dispatch: PassDispatch, apronTexels: Int, probeThreadgroup: [Int], probeThreadInGroup: [Int],
                probeSIMDGroup: Int, probeLane: Int) {
        self.dispatch = dispatch; self.apronTexels = apronTexels; self.probeThreadgroup = probeThreadgroup
        self.probeThreadInGroup = probeThreadInGroup; self.probeSIMDGroup = probeSIMDGroup; self.probeLane = probeLane
    }
}

/// Event-tile row of passes (Algorithm floor); tapping a tile shows that pass's intermediate in the periscope.
public struct PassTilesSpec: Sendable, Codable, Hashable {
    public var passes: [PassDescriptor]
    /// MEASURED per-pass ms when a settled timing Run exists.
    public var timings: [PassTiming]
    public var selected: Int?
    public init(passes: [PassDescriptor], timings: [PassTiming], selected: Int?) {
        self.passes = passes; self.timings = timings; self.selected = selected
    }
}

/// 7 × 7 grid of local PSFs drawn at their positions (space-variant blurs: a lens spot diagram).
public struct PSFFieldSpec: Sendable, Codable, Hashable {
    public var gridSize: Int
    public var points: [PixelPoint]
    public var kernels: [Kernel2D]
    public init(gridSize: Int, points: [PixelPoint], kernels: [Kernel2D]) {
        precondition(points.count == kernels.count)
        self.gridSize = gridSize; self.points = points; self.kernels = kernels
    }
}

/// Floor 1 bars: the typed value per tool for the current blur, home tool first.
public struct ToolBarsSpec: Sendable, Codable, Hashable {
    public var rows: [LabeledValue]
    public var homeToolID: String
    /// `You typed ⇄ What you get` (SPEC §5.1 floor 1).
    public var reverseMode: Bool
    public init(rows: [LabeledValue], homeToolID: String, reverseMode: Bool) {
        self.rows = rows; self.homeToolID = homeToolID; self.reverseMode = reverseMode
    }
}

public struct CodeBlock: Sendable, Codable, Hashable {
    public var language: String          // "metal", "swift", "css"
    public var text: String
    public var highlightedLines: [Int]
    /// 1-based line → one-line explanation ("cooperative load of the apron").
    public var annotations: [Int: String]
    public var sha256: String?
    public init(language: String, text: String, highlightedLines: [Int] = [], annotations: [Int: String] = [:], sha256: String? = nil) {
        self.language = language; self.text = text; self.highlightedLines = highlightedLines
        self.annotations = annotations; self.sha256 = sha256
    }
}

public struct TableBlock: Sendable, Codable, Hashable {
    public var columns: [String]
    public var rows: [[String]]
    public var caption: String?
    public var provenance: Provenance?
    public init(columns: [String], rows: [[String]], caption: String? = nil, provenance: Provenance? = nil) {
        self.columns = columns; self.rows = rows; self.caption = caption; self.provenance = provenance
    }
}

public enum FigureSpec: Sendable, Codable, Hashable {
    case plot(PlotSpec)
    case heatmap(HeatmapSpec)
    case texelGrid(TexelGridSpec)
    case dispatchOverlay(DispatchOverlaySpec)
    case passTiles(PassTilesSpec)
    case psfField(PSFFieldSpec)
    case toolBars(ToolBarsSpec)
    case code(CodeBlock)
    /// Two figures side by side (IN | OUT texel grids on floor 7).
    indirect case pair(FigureSpec, FigureSpec)
}

public indirect enum ContentBlock: Sendable, Codable, Hashable {
    case paragraph(String)
    /// An equation in Unicode (callout mono, instrument cyan, units next to it).
    case equation(String)
    case values([LabeledValue])
    case table(TableBlock)
    case code(CodeBlock)
    case figure(FigureSpec)
    /// A one-line engraved note with its badge ("IN THIS APP …", "SOURCES DISAGREE").
    case note(String, Provenance?)
    case chips([String])
    case sources([SourceRef])
    case disclosure(title: String, blocks: [ContentBlock])
}

/// A tab inside a floor page (floor 6: Shader · Silicon).
public struct FloorTab: Sendable, Codable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var dominantBadges: [Provenance]
    public var figure: FigureSpec?
    public var numbers: [LabeledValue]
    public var details: [ContentBlock]
    public init(id: String, title: String, dominantBadges: [Provenance], figure: FigureSpec?, numbers: [LabeledValue],
                details: [ContentBlock]) {
        self.id = id; self.title = title; self.dominantBadges = dominantBadges; self.figure = figure
        self.numbers = numbers; self.details = details
    }
}

/// What an operator contributes to one floor. The page builder (CONTENT-LAYERS) merges it with generic facts and live
/// Run values into a FloorPage. Empty fields fall back to generic content.
public struct FloorFacts: Sendable, Codable, Hashable {
    public var numbers: [LabeledValue]
    public var figure: FigureSpec?
    public var governingRule: String?
    public var details: [ContentBlock]
    public var tabs: [FloorTab]?
    /// Engraved reason when the floor has nothing honest to show ("N/A · NONLINEAR").
    public var emptyReason: String?
    public init(numbers: [LabeledValue] = [], figure: FigureSpec? = nil, governingRule: String? = nil, details: [ContentBlock] = [],
                tabs: [FloorTab]? = nil, emptyReason: String? = nil) {
        self.numbers = numbers; self.figure = figure; self.governingRule = governingRule; self.details = details
        self.tabs = tabs; self.emptyReason = emptyReason
    }
    public static let empty = FloorFacts()
}

/// One floor page, fully resolved, ready to render (SPEC §5.0 rules).
public struct FloorPage: Sendable, Codable, Hashable, Identifiable {
    public var id: Floor { floor }
    public var floor: Floor
    public var eyebrow: String              // "FLOOR 4 · KERNEL"
    public var question: String
    /// The catalog signature line shown in the page header (SPEC §7.3).
    public var signature: String
    public var dominantBadges: [Provenance]
    public var governingRule: String?
    public var figure: FigureSpec?
    /// At most six (SPEC §5.0 rule 2); the builder enforces it and tests check it.
    public var numbers: [LabeledValue]
    /// Everything else, inside `All … details` (the only element that grows).
    public var details: [ContentBlock]
    public var tabs: [FloorTab]?
    /// The closing `IN THIS APP` line: what on this page is LIVE / MEASURED / COMPUTED / MODELED / REFERENCE / INFERRED.
    public var inThisApp: String
    public var emptyState: String?
    public init(floor: Floor, eyebrow: String, question: String, signature: String, dominantBadges: [Provenance],
                governingRule: String?, figure: FigureSpec?, numbers: [LabeledValue], details: [ContentBlock],
                tabs: [FloorTab]?, inThisApp: String, emptyState: String?) {
        self.floor = floor; self.eyebrow = eyebrow; self.question = question; self.signature = signature
        self.dominantBadges = dominantBadges; self.governingRule = governingRule; self.figure = figure; self.numbers = numbers
        self.details = details; self.tabs = tabs; self.inThisApp = inThisApp; self.emptyState = emptyState
    }
}

/// A rail chip value (SPEC §4.1.4): text ≤ 6 characters, badge shown as a glyph only.
public struct RailChip: Sendable, Codable, Hashable, Identifiable {
    public var id: Floor { floor }
    public var floor: Floor
    public var value: BadgedValue
    /// Compare mode only: the floor comparison (first ≠ is `.partsWays`).
    public var comparison: FloorComparison?
    public init(floor: Floor, value: BadgedValue, comparison: FloorComparison?) {
        self.floor = floor; self.value = value; self.comparison = comparison
    }
}

/// One flanking pill's content (SPEC §4.1.3 "Pills"). Outline and title stay static; only the interior changes.
public struct PillPlot: Sendable, Codable, Hashable {
    /// "KERNEL", "FREQ", "LOCAL @ PROBE", "T(ν, A 0.20)".
    public var title: String
    /// nil → `emptyText` is engraved instead ("N/A · RANK", "INFERRED — NOT EXPOSED").
    public var plot: PlotSpec?
    public var emptyText: String?
    public var badge: BadgedValue?
    public init(title: String, plot: PlotSpec?, emptyText: String?, badge: BadgedValue?) {
        self.title = title; self.plot = plot; self.emptyText = emptyText; self.badge = badge
    }
}

public struct PillContent: Sendable, Codable, Hashable {
    /// Wave family (left): taps running downward from −extent to +extent.
    public var kernel: PillPlot
    /// Spectrum family (right): signed H from DC (bottom) to Nyquist (top).
    public var freq: PillPlot
    public init(kernel: PillPlot, freq: PillPlot) { self.kernel = kernel; self.freq = freq }
}

/// The Field guide page of one entry (SPEC §4.7 Guide tab).
public struct FieldGuidePage: Sendable, Codable, Hashable {
    public var blur: BlurID
    public var title: String
    public var blocks: [ContentBlock]
    public init(blur: BlurID, title: String, blocks: [ContentBlock]) { self.blur = blur; self.title = title; self.blocks = blocks }
}
