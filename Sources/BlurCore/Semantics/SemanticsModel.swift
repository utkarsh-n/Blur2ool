import Foundation

// OWNER: SEMANTICS (ARCHITECTURE §8.2). The data model behind `ToolConventions`: what one tool's blur control means.
// Research: stack-semantics.md (STACK) §0–§8, live-calibration.md (CAL) §4–§6, catalog-nonlinear.md B9, CATALOG P27.
// Every public type here starts with `Semantics` so that it can never collide with another area's file in BlurCore.

/// How a tool's own number `v` becomes a per-axis σ in device pixels. `u` is the unit scale: the display scale for
/// points, CSS px, dp and logical px, and 1 for image or device pixels (`SemanticsControl.scalesWithDisplay`).
public enum SemanticsLaw: Sendable, Hashable, Codable {
    /// σ = slope·v·u + offset·(offsetScales ? u : 1) for v > 0, and 0 for v ≤ 0. The offset is non-zero only for
    /// Skia's legacy "radius" (σ = 0.57735·r + 0.5) and GIMP 2.8 (σ = (r + 1)/3.329).
    case linear(slope: Double, offset: Double, offsetScales: Bool)
    /// SwiftUI `.blur(radius:)`: a ratio σ/(r·u) that switches regime (macOS law, or this phone's `CalibrationLaw`).
    case swiftUIBlur
    /// Core Image `CIBoxBlur`: a box of width W = 2⌈v/2⌉ − 1 (MEASURED, CAL §5.2), σ = √((W² − 1)/12). The typed
    /// value shown is W itself, the smallest "radius" that gives that width.
    case ciBoxWidth
    /// A discrete box of w taps (MPSImageBox, vImage, OpenCV `blur`): σ = √((w² − 1)/12); w odd.
    case boxWidth
    /// A discrete tent of width w, two boxes of (w + 1)/2 (MPSImageTent, vImage): σ = √((((w + 1)/2)² − 1)/6); w odd.
    case tentWidth
    /// SVG `feGaussianBlur` three-box rule for s ≥ 2: d = ⌊1.88·s + 0.5⌋, σ = √(Σ(dᵢ² − 1)/12) (Filter Effects 1 §9.14).
    case svgThreeBox
    /// Flutter Impeller: σ′ = min(σ, 500)·(1 − 3.4·10⁻³σ + 3.4·10⁻⁶σ²), sampled taps out to ⌊√3·(σ′ − 0.5)⌋.
    case impeller
    /// OpenCV `GaussianBlur(ksize: 2v + 1, sigmaX: 0)`: σ = 0.3·(v − 1) + 0.8 (= 0.15·ksize + 0.35).
    case opencvKernelRadius
    /// The same σ whatever is typed (ImageMagick `-blur r` without a sigma: σ = 1).
    case constant(Double)
}

/// What a tool's number is, for one blur.
public enum SemanticsMapping: Sendable, Hashable, Codable {
    /// A known law from the typed value to σ.
    case law(SemanticsLaw)
    /// The tool offers this blur, but how its number maps to σ is not established: words, never a number.
    /// `subject` names the number ("Photoshop Gaussian Blur radius").
    case unverified(subject: String)
    /// The tool offers this blur, but its number is not a σ (a style name, a blend weight, a rank window …).
    /// `words` is ALL CAPS for rows, `chip` is at most six characters for the SLIDE chip, `spoken` is the full phrase.
    case noSigma(words: String, chip: String, spoken: String)
}

/// Does the tool's kernel equal this blur's kernel? Decides the `≈` prefix and `SAME σ, DIFFERENT KERNEL` (SPEC §4.1.4).
public enum SemanticsKernelMatch: String, Sendable, Hashable, Codable {
    /// The tool computes this blur's kernel (up to its own truncation).
    case same
    /// The same σ, a different kernel shape: the typed value matches only σ.
    case sigmaOnly
    /// SwiftUI `.blur`: a sampled Gaussian below the regime switch, box³-like above it (CAL §5.1).
    case sameBelowSwitch
    /// The tool's kernel is not known; neither `same` nor `≈` is claimed.
    case unknown
}

/// The second reading of a control whose sources disagree (`CALayer.shadowRadius`, SPEC §17 item 7).
public struct SemanticsAlternate: Sendable, Hashable, Codable {
    public var label: String
    public var law: SemanticsLaw
    public var provenance: Provenance
    public var source: SourceRef
    public var measuredOn: DeviceStamp?
    public var lawDescription: String
    public init(label: String, law: SemanticsLaw, provenance: Provenance, source: SourceRef, measuredOn: DeviceStamp?,
                lawDescription: String) {
        self.label = label; self.law = law; self.provenance = provenance; self.source = source
        self.measuredOn = measuredOn; self.lawDescription = lawDescription
    }
}

/// One tool's control for one blur: what you type, in which unit, and what σ it gives.
public struct SemanticsControl: Sendable, Hashable, Codable, Identifiable {
    public var id: String { toolID + "/" + blur.rawValue }
    public var toolID: String
    public var blur: BlurID
    /// The control as the tool names it (".blur(radius:)", "CIBoxBlur inputRadius", "Gaussian Blur › Radius").
    public var controlName: String
    public var unit: ParameterUnit
    /// Printed unit when `ParameterUnit` has no symbol for it ("dp").
    public var unitSymbolOverride: String?
    public var spokenUnitOverride: String?
    /// True when the number is in points, CSS px, dp or logical px (× display scale to reach device px).
    public var scalesWithDisplay: Bool
    public var mapping: SemanticsMapping
    /// nil only for `.unverified` mappings (the value is words).
    public var provenance: Provenance?
    public var source: SourceRef
    /// The device a MEASURED law was measured on (the research Mac until this phone measures it).
    public var measuredOn: DeviceStamp?
    public var qualifiers: Qualifiers
    public var kernelMatch: SemanticsKernelMatch
    /// The calibration subject whose phone `CalibrationLaw` replaces this control's law (ratio laws only).
    public var calibrationSubject: CalibrationSubject?
    /// "σ = value ÷ 2"; nil when the mapping is UNVERIFIED.
    public var lawDescription: String?
    /// A standing caption ("THIRD-PARTY MEASUREMENT", "IMPELLER BLURS LESS").
    public var caption: String?
    /// The caption for a σ-only match ("SAME σ, DIFFERENT KERNEL" unless the control says otherwise).
    public var matchCaption: String
    /// The tool's kernel in words, for reverse mode ("BOX-CUBED-LIKE KERNEL", "GAUSSIAN STREAK, NOT A BOX").
    public var kernelNote: String?
    /// Widths and kernel sizes are whole numbers.
    public var integerValued: Bool
    /// Reachable σ range in the tool's own unit (σ_px / u): Skia's +0.5 floor, CIMaskedVariableBlur's cap.
    public var minSigmaUnits: Double?
    public var maxSigmaUnits: Double?
    /// The other reading when two sources disagree.
    public var alternate: SemanticsAlternate?

    public init(toolID: String, blur: BlurID, controlName: String, unit: ParameterUnit, unitSymbolOverride: String? = nil,
                spokenUnitOverride: String? = nil, scalesWithDisplay: Bool, mapping: SemanticsMapping, provenance: Provenance?,
                source: SourceRef, measuredOn: DeviceStamp? = nil, qualifiers: Qualifiers = [], kernelMatch: SemanticsKernelMatch,
                calibrationSubject: CalibrationSubject? = nil, lawDescription: String? = nil, caption: String? = nil,
                matchCaption: String = "SAME σ, DIFFERENT KERNEL", kernelNote: String? = nil, integerValued: Bool = false,
                minSigmaUnits: Double? = nil, maxSigmaUnits: Double? = nil, alternate: SemanticsAlternate? = nil) {
        self.toolID = toolID; self.blur = blur; self.controlName = controlName; self.unit = unit
        self.unitSymbolOverride = unitSymbolOverride; self.spokenUnitOverride = spokenUnitOverride
        self.scalesWithDisplay = scalesWithDisplay; self.mapping = mapping; self.provenance = provenance; self.source = source
        self.measuredOn = measuredOn; self.qualifiers = qualifiers; self.kernelMatch = kernelMatch
        self.calibrationSubject = calibrationSubject; self.lawDescription = lawDescription; self.caption = caption
        self.matchCaption = matchCaption; self.kernelNote = kernelNote; self.integerValued = integerValued
        self.minSigmaUnits = minSigmaUnits; self.maxSigmaUnits = maxSigmaUnits; self.alternate = alternate
    }

    /// Unit scale u for a display scale.
    public func unitScale(_ displayScale: Double) -> Double { scalesWithDisplay ? max(displayScale, 1e-9) : 1 }
    public var unitSymbol: String? { unitSymbolOverride ?? unit.symbol }
    public var spokenUnit: String? { spokenUnitOverride ?? unit.spokenName }
    /// The typed value's number style: whole numbers for widths, three significant digits otherwise.
    public var typedStyle: NumberStyle {
        integerValued ? .integer(unit: unitSymbol, spokenUnit: spokenUnit) : .significant(3, unit: unitSymbol, spokenUnit: spokenUnit)
    }
    public var isOfferedWithLaw: Bool { if case .law = mapping { true } else { false } }
}

/// A tool, a library or a shadow convention that someone types a blur number into.
public struct SemanticsTool: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    /// "SwiftUI", "Core Image", "GIMP 2.8", "CSS box-shadow".
    public var name: String
    /// ALL-CAPS mono label for rows and captions ("SWIFTUI", "CORE IMAGE").
    public var label: String
    public var unit: ParameterUnit
    /// The blur whose control describes the tool in `ToolConventionProviding.all` (usually the Gaussian).
    public var primaryBlur: BlurID
    /// A drop-shadow convention of P27 (CONVENTION menu of `drop-shadow`), not a general tool.
    public var isShadowConvention: Bool
    public init(id: String, name: String, label: String, unit: ParameterUnit, primaryBlur: BlurID, isShadowConvention: Bool = false) {
        self.id = id; self.name = name; self.label = label; self.unit = unit; self.primaryBlur = primaryBlur
        self.isShadowConvention = isShadowConvention
    }
}

/// Whether a tool offers a blur.
public enum SemanticsOffer: Sendable, Hashable {
    case offered(SemanticsControl)
    /// The tool does not offer this blur at all (SLIDE chip `—`, Compare `NOT IN <TOOL>`).
    case notOffered(SemanticsTool)
    /// No tool with this id.
    case unknownTool(String)
    public var control: SemanticsControl? { if case .offered(let c) = self { c } else { nil } }
    public var isOffered: Bool { control != nil }
}

/// One reading of a typed value or of σ: the value plus the law it came from (two readings when sources disagree).
public struct SemanticsReading: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    /// "CALAYER · STACK" style label for rows; the tool's own label for a single reading.
    public var label: String
    public var value: BadgedValue
    /// The law in words ("σ = r ÷ 2").
    public var lawDescription: String?
    public init(id: String, label: String, value: BadgedValue, lawDescription: String?) {
        self.id = id; self.label = label; self.value = value; self.lawDescription = lawDescription
    }
}

/// One row of "the same word radius means at least sixteen things" (STACK §8), for a typed value.
public struct SemanticsRadiusMeaning: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    /// ALL-CAPS row label ("CSS BLUR() · SVG · FLUTTER").
    public var label: String
    /// Who says "radius v" ("CSS blur(), SVG stdDeviation, Flutter sigmaX (Skia)").
    public var who: String
    /// What v actually is ("σ", "2σ: the shadow blur radius", "box width").
    public var what: String
    /// The kernel in words ("Gaussian", "box-cubed-like", "uniform disc").
    public var kernel: String
    /// σ in device pixels at this display.
    public var sigma: BadgedValue
    /// 10–90 % width of a hard edge through that kernel, device pixels.
    public var edgeWidth: BadgedValue
    public init(id: String, label: String, who: String, what: String, kernel: String, sigma: BadgedValue, edgeWidth: BadgedValue) {
        self.id = id; self.label = label; self.who = who; self.what = what; self.kernel = kernel; self.sigma = sigma; self.edgeWidth = edgeWidth
    }
}
