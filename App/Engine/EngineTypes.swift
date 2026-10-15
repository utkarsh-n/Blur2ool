import Foundation
import BlurCore

// FROZEN — ARCHITECTURE.md §5.9. App-side value types: navigation, Bench view state, compare state, status row,
// launch scenarios. App/Engine/EngineTypes.swift; owner SKEL (no logic here).

/// Root NavigationStack pushes (SPEC §3).
public enum Route: Hashable, Sendable {
    case layers(Floor)
    case trace
}
/// Pushes inside the Catalog sheet's own NavigationStack (Tier 3 atlas pages are never on the Bench).
public enum CatalogRoute: Hashable, Sendable { case atlasPage(BlurID) }
/// Pushes inside the Field guide sheet's own NavigationStack (Calibrate from This phone is a push, not a second sheet).
public enum FieldGuideRoute: Hashable, Sendable { case calibrate(CalibrationSubject), honestyLegend(Provenance?), lensNote }

public enum CatalogTab: String, Sendable, Hashable, CaseIterable { case blurs, fingerprints, divergence, lessons }
public enum FieldGuideTab: String, Sendable, Hashable, CaseIterable { case guide, thisPhone, runs, settings }

/// Every sheet comes from ONE `.sheet(item:)` driven by this enum (METRO §F.5 item 3). Sheets never stack.
public enum SheetDestination: Identifiable, Hashable, Sendable {
    case catalog(CatalogTab)
    case fingerprint(BlurID)
    case fieldGuide(FieldGuideTab, BlurID?)
    case calibrate(CalibrationSubject)
    public var id: String {
        switch self {
        case .catalog(let t): "catalog.\(t.rawValue)"
        case .fingerprint(let b): "fingerprint.\(b.rawValue)"
        case .fieldGuide(let t, let b): "fieldGuide.\(t.rawValue).\(b?.rawValue ?? "-")"
        case .calibrate(let s): "calibrate.\(s.rawValue)"
        }
    }
}

/// Compare holds A (the Bench configuration) and B (and C, D for Line-up) over one specimen and one probe (SPEC §8.2).
public struct CompareState: Sendable, Codable, Hashable {
    public var b: RenderConfiguration
    /// C and D for Line-up (empty otherwise).
    public var extra: [RenderConfiguration]
    public var axis: CompareAxis
    public var match: MatchRule
    public var view: CompareView
    /// Divider position 0…1 (B left of it, A right).
    public var split: Double
    /// Crowns drive B while true (status row: DRIVING B).
    public var drivingB: Bool
    public init(b: RenderConfiguration, extra: [RenderConfiguration] = [], axis: CompareAxis = .operator, match: MatchRule = .sigma,
                view: CompareView = .wipe, split: Double = 0.5, drivingB: Bool = false) {
        self.b = b; self.extra = extra; self.axis = axis; self.match = match; self.view = view; self.split = split; self.drivingB = drivingB
    }
}

/// One legal B choice for the current axis (the B menu lists only these).
public struct CompareChoice: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var configuration: RenderConfiguration
    public var disabledReason: String?
    public init(id: String, title: String, configuration: RenderConfiguration, disabledReason: String? = nil) {
        self.id = id; self.title = title; self.configuration = configuration; self.disabledReason = disabledReason
    }
}

/// Presentation-only state of the image window (never changes the blur).
public struct WindowViewState: Sendable, Codable, Hashable {
    /// 1, 2, 4 or 8 after a pinch settles (live values in between while pinching).
    public var zoom: Double
    /// Centre of the magnified view, in window pixels.
    public var zoomCentre: SIMD2<Double>
    /// Before/after split position 0…1, or nil when the split is off.
    public var split: Double?
    /// A pass tile is selected: show that pass's intermediate (`PASS 1 OF 2 · INTERMEDIATE`).
    public var shownPass: Int?
    /// The Metal loupe's centre in window pixels while it is open.
    public var loupe: PixelPoint?
    public init(zoom: Double = 1, zoomCentre: SIMD2<Double> = SIMD2(447, 447), split: Double? = 0.5, shownPass: Int? = nil,
                loupe: PixelPoint? = nil) {
        self.zoom = zoom; self.zoomCentre = zoomCentre; self.split = split; self.shownPass = shownPass; self.loupe = loupe
    }
}

/// Requested vs acknowledged (Metro contract A.13).
public enum RenderPhase: Sendable, Hashable {
    case idle
    case rendering(pass: Int, of: Int)
    case preview
    case timing
}

/// The fixed-height status row (SPEC §4.1.3): exactly one line, highest priority first. Readout only (JF M-14).
/// Every number in it travels as a BadgedValue inside a BadgedLine (review fix E-51).
public enum StatusLine: Sendable, Hashable {
    case rendering(BadgedLine)  // "RENDERING… PASS 2/2" (pass counter as a .literal)
    case notice(BadgedLine)     // σ-hold and switch notices; the σ-hold line stays in the readout's accessibility value
    case warning(BadgedLine)    // sampling and budget warnings ("TOO SLOW TO TIME · ≈ 700 ms MODELED")
    case lesson(BadgedLine)     // a lesson's look-for line, until a control changes
    case coaching(BadgedLine)   // first launch only
    case phase(BadgedLine)      // "74 FETCHES · 2 PASSES · LINEAR-SAMPLED" (PassPlan.phase)
    public var line: BadgedLine {
        switch self {
        case .rendering(let l), .notice(let l), .warning(let l), .lesson(let l), .coaching(let l), .phase(let l): l
        }
    }
    public var text: String { line.text }
}

/// Restorable per-device state (UserDefaults / @SceneStorage): later launches show it immediately (SPEC §2).
public struct BenchSnapshot: Sendable, Codable, Hashable {
    public var configuration: RenderConfiguration
    public var view: WindowViewState
    public var compare: CompareState?
    public var firstLaunchDone: Bool
    public init(configuration: RenderConfiguration, view: WindowViewState, compare: CompareState?, firstLaunchDone: Bool) {
        self.configuration = configuration; self.view = view; self.compare = compare; self.firstLaunchDone = firstLaunchDone
    }
}

/// The Trace's Jump menu (SPEC §6.1). Items that do not apply are hidden, not disabled.
public enum ProbeJump: String, Sendable, Hashable, CaseIterable {
    case featureProbe, brightestOutput, worstParity, inversionRing, edge, impulsePeak, corner, tileBoundary
    public var title: String {
        switch self {
        case .featureProbe: "Feature probe"
        case .brightestOutput: "Brightest output pixel"
        case .worstParity: "Worst parity pixel"
        case .inversionRing: "Predicted inversion ring"
        case .edge: "Edge"
        case .impulsePeak: "Impulse peak"
        case .corner: "Corner"
        case .tileBoundary: "Tile boundary"
        }
    }
}

/// Launch arguments for headless and on-device screenshots: `-B2Scenario <name> [-B2Blur <id>] [-B2Specimen <id>]
/// [-B2Floor <1…7>] [-B2Param key=value]`. ENGINE applies them in `BenchModel.handleLaunch` (ARCHITECTURE §11.4).
public enum LaunchScenario: String, Sendable, CaseIterable {
    case bench, firstLaunch = "first-launch", compare, layers, trace, catalog, fingerprints, divergence, lessons, fingerprint,
         fieldGuide = "field-guide", thisPhone = "this-phone", runs, settings, calibrate, loupe, accessibility,
         /// Every Metro component on one scrolling page (METRO-COMPONENTS' screenshot target).
         gallery,
         /// Every figure and block kind rendered from fixtures (CONTENT-VIEWS' screenshot target).
         contentGallery = "content-gallery"

    public struct Launch: Sendable, Hashable {
        public var scenario: LaunchScenario
        public var blur: BlurID?
        public var specimen: SpecimenID?
        public var floor: Floor?
        public var parameters: [String: String]
    }
    public static func parse(_ arguments: [String]) -> Launch? {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        guard let name = value("-B2Scenario"), let scenario = LaunchScenario(rawValue: name) else { return nil }
        var parameters: [String: String] = [:]
        for (i, a) in arguments.enumerated() where a == "-B2Param" && i + 1 < arguments.count {
            let parts = arguments[i + 1].split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { parameters[parts[0]] = parts[1] }
        }
        return Launch(scenario: scenario, blur: value("-B2Blur").map(BlurID.init(rawValue:)),
                      specimen: value("-B2Specimen").map(SpecimenID.init(rawValue:)),
                      floor: value("-B2Floor").flatMap(Int.init).flatMap(Floor.init(rawValue:)), parameters: parameters)
    }
}

/// The loupe's reading (SPEC §4.1.3): 14 × 14 output texels around its centre, LIVE, from a full-resolution Run only.
public struct LoupeReading: Sendable, Hashable {
    public var centre: PixelPoint
    public var texels: [SIMD4<Float>]
    /// 3 significant digits, the one probe-value precision used everywhere (review fix P-62).
    public var centreLinear: BadgedValue
    /// The sRGB 8-bit code of the centre (COMPUTED from the LIVE value).
    public var centreCode8: BadgedValue
    public init(centre: PixelPoint, texels: [SIMD4<Float>], centreLinear: BadgedValue, centreCode8: BadgedValue) {
        self.centre = centre; self.texels = texels; self.centreLinear = centreLinear; self.centreCode8 = centreCode8
    }
}

/// LOOKS MOST LIKE (SPEC §7.1): the nearest catalog entry to a MEASURED shape, its distance badged (review fix E-51).
public struct NearestMatch: Sendable, Hashable {
    public var blur: BlurID
    public var distance: BadgedValue
    public init(blur: BlurID, distance: BadgedValue) { self.blur = blur; self.distance = distance }
}

/// Where the fingerprint strip and ON THIS PHONE come from (review fix P-31). Tier S entries never use `.metalModel`:
/// a card titled "SwiftUI .blur" shows the real modifier rendered offscreen, or nothing yet.
public enum FingerprintEvidence: Sendable, Hashable {
    /// Our Metal implementation of this entry, rendered now (LIVE). Tier 1/2 only.
    case metalModel
    /// The real Apple API rendered by ImageRenderer (MEASURED · OFFSCREEN) or a Calibrate result for this subject.
    case offscreenRender(DeviceStamp)
    /// Tier S before a calibration exists: the slots read NOT YET MEASURED.
    case notYetMeasured
}

/// Everything the fingerprint card shows (SPEC §7.1), assembled by ENGINE, drawn by UI-ATLAS.
public struct FingerprintCardModel: Sendable, Equatable {
    public var entry: CatalogEntry
    /// The UNIQUE row (SPEC §7.2).
    public var unique: LabeledValue
    /// Excess kurtosis of the LSF at the current parameters (COMPUTED) on the shared −1.2 … +3 axis.
    public var excessKurtosis: BadgedValue
    /// PSF (log intensity), STAR (36-cycle crop), EDGE (step profile): 128 × 128 renders at σ_equiv 4 px (engraved
    /// `AT σ 4 px`, review fix P-74); nil until rendered. Provenance per `stripEvidence`.
    public var strip: [ImageBuffer]?
    public var stripEvidence: FingerprintEvidence
    /// H for LSI, local H for LSV, T(ν, A) at A = 0.05 and 0.5 for adaptive; nil for rank filters.
    public var responses: [ResponseCurve]
    public var partsWays: [BlurID: FloorComparison]
    /// ON THIS PHONE (MEASURED on demand: GPU output for Tier 1/2, the CalibrationResult for Tier S); nil until measured.
    public var onThisPhone: ShapeMeasurement?
    public var onThisPhoneEvidence: FingerprintEvidence
    public var looksMostLike: NearestMatch?
    public init(entry: CatalogEntry, unique: LabeledValue, excessKurtosis: BadgedValue, strip: [ImageBuffer]?,
                stripEvidence: FingerprintEvidence, responses: [ResponseCurve], partsWays: [BlurID: FloorComparison],
                onThisPhone: ShapeMeasurement?, onThisPhoneEvidence: FingerprintEvidence, looksMostLike: NearestMatch?) {
        self.entry = entry; self.unique = unique; self.excessKurtosis = excessKurtosis; self.strip = strip
        self.stripEvidence = stripEvidence; self.responses = responses; self.partsWays = partsWays; self.onThisPhone = onThisPhone
        self.onThisPhoneEvidence = onThisPhoneEvidence; self.looksMostLike = looksMostLike
    }
    /// The honesty rule of review fix P-31: no Tier S field is LIVE.
    public var tierSViolations: [String] {
        guard entry.tier == .system else { return [] }
        var problems: [String] = []
        if stripEvidence == .metalModel { problems.append("Tier S strip drawn from the Metal model") }
        if onThisPhoneEvidence == .metalModel { problems.append("Tier S ON THIS PHONE from the Metal model") }
        if excessKurtosis.provenance == .live { problems.append("Tier S kurtosis labelled LIVE") }
        return problems
    }
}

/// One render request (ENGINE → RenderCoordinator).
public struct RenderRequest: Sendable, Hashable {
    public var configuration: RenderConfiguration
    public var slot: RunSlot
    public var quality: RenderQuality
    public var generation: UInt64
    public var kind: RunKind
    /// Render with the TRACE_PROBE specialization (the frame on screen while Trace is open IS the traced frame).
    public var traced: Bool
    public init(configuration: RenderConfiguration, slot: RunSlot, quality: RenderQuality, generation: UInt64, kind: RunKind, traced: Bool) {
        self.configuration = configuration; self.slot = slot; self.quality = quality; self.generation = generation
        self.kind = kind; self.traced = traced
    }
}
