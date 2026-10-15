import Foundation

// FROZEN — ARCHITECTURE.md §5.3. Catalog descriptors (CATALOG.md §1–§2, §6; SPEC §7, §10).
// Everything static about one entry lives in CatalogEntry; behaviour lives in its BlurOperator (§5.5).

public enum Family: String, Sendable, Codable, Hashable, CaseIterable {
    case f1 = "F1", f2 = "F2", f3 = "F3", f4 = "F4", f5 = "F5", f6 = "F6", f7 = "F7", f8 = "F8", f9 = "F9",
         f10 = "F10", f11 = "F11", contrast = "C"

    public var title: String {
        switch self {
        case .f1: "Box, tent & running sums"
        case .f2: "Gaussian & approximations"
        case .f3: "Pyramids & Kawase"
        case .f4: "Kernel shapes & the frequency domain"
        case .f5: "Directional & motion"
        case .f6: "Lens & bokeh"
        case .f7: "Spatially varying & stochastic"
        case .f8: "Edge-preserving & nonlinear"
        case .f9: "Diffusion"
        case .f10: "UI materials"
        case .f11: "Uses of blur"
        case .contrast: "Contrast (not blurs)"
        }
    }
    /// The family's question (CATALOG §1), shown beside the Catalog section eyebrow.
    public var question: String {
        switch self {
        case .f1: "What is the simplest average, and how do sums make it O(1)?"
        case .f2: "What is the reference blur, and what does each shortcut cost in accuracy?"
        case .f3: "How do real-time engines get huge blurs for a few fetches, and what do they give up?"
        case .f4: "What happens when the kernel is not bell-shaped, or is defined by its spectrum?"
        case .f5: "What if the blur has a direction, or comes from movement in time?"
        case .f6: "What does an optical system do to a point of light?"
        case .f7: "What if the amount of blur changes across the image, or is random?"
        case .f8: "What if the weights depend on the pixel values?"
        case .f9: "What if blur is a process in time?"
        case .f10: "What do designers' \"blur\" controls actually build?"
        case .f11: "What is built from a blur but is not itself a blur?"
        case .contrast: "What looks like a blur, sits next to one in a menu, or inverts one, but fails the blur test?"
        }
    }
    /// "F1 · BOX, TENT & RUNNING SUMS".
    public var eyebrow: String { "\(rawValue) · \(title.uppercased())" }
}

public enum Tier: String, Sendable, Codable, Hashable, CaseIterable {
    case tier1, tier2, tier3, system
    /// Catalog chip text (SPEC §4.5).
    public var chip: String {
        switch self {
        case .tier1: "TIER 1 · LIVE"
        case .tier2: "TIER 2 · LIVE"
        case .tier3: "TIER 3 · PLOTS"
        case .system: "SYSTEM · MEASURED"
        }
    }
    /// Tier 3 entries are never on the blur strip and never on the Bench (SPEC §4.1.2, §10.4).
    public var runsLive: Bool { self != .tier3 }
}

/// CATALOG §1 verdict vocabulary.
public enum Verdict: String, Sendable, Codable, Hashable, CaseIterable {
    case trueBlur, adaptiveBlur, rankFilter, blurInExpectation, lsvBlur, composite, blurDerived, notABlur
    public var chip: String {
        switch self {
        case .trueBlur: "TRUE BLUR"
        case .adaptiveBlur: "ADAPTIVE BLUR"
        case .rankFilter: "RANK FILTER"
        case .blurInExpectation: "BLUR IN EXPECTATION"
        case .lsvBlur: "LSV BLUR"
        case .composite: "COMPOSITE"
        case .blurDerived: "BLUR-DERIVED"
        case .notABlur: "NOT A BLUR"
        }
    }
}

public enum LinearityClass: String, Sendable, Codable, Hashable, CaseIterable {
    /// Linear shift-invariant.
    case lsi
    /// Linear shift-variant (zoom, spin, motion fields, variable blur, depth of field).
    case lsv
    /// Nonlinear (adaptive weights, rank, PDE with edge stopping).
    case nonlinear
    /// Blur in expectation (stochastic).
    case expectation
    /// Apple system implementation: internals not exposed.
    case system
    public var chip: String {
        switch self {
        case .lsi: "LSI"
        case .lsv: "LSV"
        case .nonlinear: "NL"
        case .expectation: "E"
        case .system: "SYS"
        }
    }
}

public enum Separability: String, Sendable, Codable, Hashable {
    case yes, no, skew, approximate, notApplicable
}

public struct PropertyFlags: OptionSet, Sendable, Codable, Hashable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public static let linear = PropertyFlags(rawValue: 1 << 0)
    public static let shiftInvariant = PropertyFlags(rawValue: 1 << 1)
    public static let separable = PropertyFlags(rawValue: 1 << 2)
    public static let isotropic = PropertyFlags(rawValue: 1 << 3)
    /// Every kernel weight ≥ 0.
    public static let positiveKernel = PropertyFlags(rawValue: 1 << 4)
    /// Blurring twice equals blurring once with a larger parameter.
    public static let semigroup = PropertyFlags(rawValue: 1 << 5)
    /// H(ν) ≥ 0 everywhere: no contrast inversion.
    public static let nonNegativeResponse = PropertyFlags(rawValue: 1 << 6)
    public static let edgePreserving = PropertyFlags(rawValue: 1 << 7)
    public static let dataDependent = PropertyFlags(rawValue: 1 << 8)
}

public enum CostClass: String, Sendable, Codable, Hashable, CaseIterable {
    case constant = "O(1)", linearR = "O(r)", quadraticR = "O(r²)", logN = "O(log N)", samples = "O(S)",
         iterative = "ITER", search = "SEARCH", global = "FFT", capture = "CAPTURE", alu = "ALU"
    /// Classes that render a reduced-resolution preview while a control moves (SPEC §4.1.6), before parameter checks.
    public var isHeavyByDefault: Bool { [.quadraticR, .iterative, .search, .global].contains(self) }
}

/// Decides how floors and traces are shaped (SPEC §5.2, §6.5).
public enum AlgorithmClass: String, Sendable, Codable, Hashable, CaseIterable {
    case separableFIR, gather2D, skewSeparable, recursive, runningSum, sparseIterated, spaceVariantGather,
         adaptiveWeighted, selection, iterativePDE, globalFFT, stochastic, temporal, system, derived, atlasOnly
}

public enum TraceDepth: Sendable, Codable, Hashable {
    /// Every fetch, tap or iteration, from TRACE_PROBE records (Tier 1).
    case full
    /// One declared stage with GPU records (Tier 2); the string names the stage ("blur stage").
    case stage(String)
    /// Frequency steps instead of fetches (FFT-based entries).
    case spectrum
    /// No GPU trace; floors 3–6 are the INFERRED lane (Tier S).
    case inferredLane
    /// Floors 1–4 and a CPU floor 7 only (Tier 3).
    case atlasOnly
}

/// How the footprint glyph is drawn (blur strip, kernel well, catalog rows). Pure data; the app draws it.
public enum GlyphKind: String, Sendable, Codable, Hashable, CaseIterable {
    case rings, square, squareCorners, tent, disc, polygon, rays, arcs, segment, ellipse, diagonalTaps, pyramid,
         notchedRing, dashedCircle, cross, wave, grid, comet, squiggle, dots, sun, spectrum, diamond, none
}

public struct GlyphSpec: Sendable, Codable, Hashable {
    public var kind: GlyphKind
    /// Kind-specific numbers: polygon sides, segment angle in degrees, ring count, ellipse aspect …
    public var values: [Double]
    public init(_ kind: GlyphKind, _ values: [Double] = []) { self.kind = kind; self.values = values }
}

public enum HandleKind: String, Sendable, Codable, Hashable {
    /// ⊕ centre (zoom, spin, god rays' sun, cat's-eye swirl).
    case centre
    /// Two parallel focus lines (tilt-shift).
    case focusBand
    /// Ellipse centre plus one radius knob (iris blur).
    case irisEllipse
    /// Ramp start/end lines (variable blur).
    case rampEnds
    /// The Liquid Glass exhibit's shape grip.
    case glassGrip
}

public struct HandleSpec: Sendable, Codable, Hashable {
    public var kind: HandleKind
    /// Parameters the handle writes (positions in window pixels, widths in px).
    public var parameters: [ParameterKey]
    public init(_ kind: HandleKind, parameters: [ParameterKey]) { self.kind = kind; self.parameters = parameters }
}

/// An Apple implementation of (nearly) the same operator, for the Apple axis, floor 2 twins and Tier S.
public struct AppleTwinSpec: Sendable, Codable, Hashable {
    public var id: String                      // "CIGaussianBlur", "MPSImageGaussianBlur", "SwiftUI.blur"
    public var call: String                    // code text shown on floor 2
    public var mapping: String                 // "σ = inputRadius", "W = 2⌈r/2⌉ − 1"
    public var provenance: Provenance          // MEASURED / REFERENCE / INFERRED
    public var source: SourceRef
    /// The measurement subject in Calibrate, when the app can run it on this phone.
    public var subject: CalibrationSubject?
    public init(id: String, call: String, mapping: String, provenance: Provenance, source: SourceRef,
                subject: CalibrationSubject?) {
        self.id = id; self.call = call; self.mapping = mapping; self.provenance = provenance
        self.source = source; self.subject = subject
    }
}

public struct VariantDescriptor: Sendable, Codable, Hashable, Identifiable {
    public var id: VariantID
    public var displayName: String             // "Linear-sampled"
    public var tier: Tier
    public var algorithmClass: AlgorithmClass
    public var costClass: CostClass
    /// False for CPU-only plots (Tier 3 variants such as `cubic-b-spline`).
    public var runsOnGPU: Bool
    /// True only for integer-tap FIR variants (SPEC §9.3 "Renormalise (FIR blurs only)").
    public var supportsRenormalise: Bool
    public var note: String?
    public init(id: VariantID, displayName: String, tier: Tier, algorithmClass: AlgorithmClass, costClass: CostClass,
                runsOnGPU: Bool, supportsRenormalise: Bool = false, note: String? = nil) {
        self.id = id; self.displayName = displayName; self.tier = tier; self.algorithmClass = algorithmClass
        self.costClass = costClass; self.runsOnGPU = runsOnGPU; self.supportsRenormalise = supportsRenormalise; self.note = note
    }
}

/// The fingerprint card's TELL box (SPEC §7.1 item 7): the one test that gives the blur away.
public struct TellSpec: Sendable, Codable, Hashable {
    public var specimen: SpecimenID
    public var text: String
    /// Parameters that `Show me` applies (σ-held when nil).
    public var parameters: ParameterValues?
    public var probe: PixelPoint?
    public init(specimen: SpecimenID, text: String, parameters: ParameterValues? = nil, probe: PixelPoint? = nil) {
        self.specimen = specimen; self.text = text; self.parameters = parameters; self.probe = probe
    }
}

/// One of the card's six fixed rows; the numbers in `text` are CATALOG's CHECKED values (SPEC §7.1 item 4).
public struct CardRow: Sendable, Codable, Hashable {
    public var text: String
    public var provenance: Provenance
    public var source: SourceRef?
    public var disclosure: String?
    public init(_ text: String, _ provenance: Provenance, source: SourceRef? = nil, disclosure: String? = nil) {
        self.text = text; self.provenance = provenance; self.source = source; self.disclosure = disclosure
    }
}

/// PSF SHAPE · RESPONSE · EDGES · COST · ARTIFACTS · USED IN, in this order, for every entry.
public struct CardRows: Sendable, Codable, Hashable {
    public var psfShape: CardRow
    public var response: CardRow
    public var edges: CardRow
    public var cost: CardRow
    public var artifacts: CardRow
    public var usedIn: CardRow
    public init(psfShape: CardRow, response: CardRow, edges: CardRow, cost: CardRow, artifacts: CardRow, usedIn: CardRow) {
        self.psfShape = psfShape; self.response = response; self.edges = edges
        self.cost = cost; self.artifacts = artifacts; self.usedIn = usedIn
    }
    public var ordered: [(label: String, row: CardRow)] {
        [("PSF SHAPE", psfShape), ("RESPONSE", response), ("EDGES", edges), ("COST", cost), ("ARTIFACTS", artifacts), ("USED IN", usedIn)]
    }
}

/// Everything static about one catalog entry.
public struct CatalogEntry: Sendable, Codable, Hashable, Identifiable {
    public var id: BlurID
    public var displayName: String
    public var family: Family
    public var tier: Tier
    public var verdict: Verdict
    public var linearity: LinearityClass
    public var separability: Separability
    public var properties: PropertyFlags
    public var costClass: CostClass
    public var algorithmClass: AlgorithmClass
    /// Verbatim from CATALOG §2 with the SPEC §17 truth fixes applied.
    public var signature: String
    /// Rail MATH chip text, ≤ 5 characters ("G", "rect", "tent", "disc", "hex", "exp", "ray", "arc", "rank", "w·f", "PDE", "FFT", "sys").
    public var mathSymbol: String
    public var glyph: GlyphSpec
    public var parameters: [ParameterSpec]
    /// The hero's parameter (requested value, no badge).
    public var primary: ParameterKey
    public var deck: DeckArrangement
    public var variants: [VariantDescriptor]
    public var defaultVariant: VariantID
    public var defaultSpecimen: SpecimenID
    public var handles: [HandleSpec]
    public var appleTwins: [AppleTwinSpec]
    public var tell: TellSpec
    /// NEAREST: two or three entries it is most often confused with (CATALOG §7).
    public var neighbours: [BlurID]
    public var traceDepth: TraceDepth
    /// Position in the blur strip's hero dozen (0…11), or nil.
    public var heroOrder: Int?
    public var card: CardRows
    /// Claims about this entry that stay UNVERIFIED, in words (Field guide).
    public var unverified: [String]
    /// Research file and sections holding the full entry ("LSI §2, §3, §4").
    public var detailReference: String
    public var sources: [SourceRef]

    public init(id: BlurID, displayName: String, family: Family, tier: Tier, verdict: Verdict, linearity: LinearityClass,
                separability: Separability, properties: PropertyFlags, costClass: CostClass, algorithmClass: AlgorithmClass,
                signature: String, mathSymbol: String, glyph: GlyphSpec, parameters: [ParameterSpec], primary: ParameterKey,
                deck: DeckArrangement, variants: [VariantDescriptor], defaultVariant: VariantID, defaultSpecimen: SpecimenID,
                handles: [HandleSpec], appleTwins: [AppleTwinSpec], tell: TellSpec, neighbours: [BlurID], traceDepth: TraceDepth,
                heroOrder: Int?, card: CardRows, unverified: [String], detailReference: String, sources: [SourceRef]) {
        self.id = id; self.displayName = displayName; self.family = family; self.tier = tier; self.verdict = verdict
        self.linearity = linearity; self.separability = separability; self.properties = properties; self.costClass = costClass
        self.algorithmClass = algorithmClass; self.signature = signature; self.mathSymbol = mathSymbol; self.glyph = glyph
        self.parameters = parameters; self.primary = primary; self.deck = deck; self.variants = variants
        self.defaultVariant = defaultVariant; self.defaultSpecimen = defaultSpecimen; self.handles = handles
        self.appleTwins = appleTwins; self.tell = tell; self.neighbours = neighbours; self.traceDepth = traceDepth
        self.heroOrder = heroOrder; self.card = card; self.unverified = unverified; self.detailReference = detailReference
        self.sources = sources
    }

    /// Tier 3 entries never appear on the blur strip (SPEC §4.1.2).
    public var isOnStrip: Bool { tier.runsLive }
    public func spec(_ key: ParameterKey) -> ParameterSpec? { parameters.first { $0.key == key } }
    public var primarySpec: ParameterSpec? { spec(primary) }
    public func variant(_ id: VariantID) -> VariantDescriptor? { variants.first { $0.id == id } }
    public var defaultParameters: ParameterValues {
        var values = ParameterValues()
        for p in parameters { values[p.key] = p.defaultValue }
        return values
    }
}
