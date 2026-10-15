import Foundation

// FROZEN — ARCHITECTURE.md §5.5. The registries name every area-owned group catalog and service type. Areas fill
// their own types; they never edit this file (build/requests/<AREA>.md → INTEGRATE).

public enum BlurRegistry {
    /// Every catalog entry's operator, by implementation group (ARCHITECTURE §8 owners in comments).
    public static let operators: [any BlurOperator] =
        F1Catalog.operators          // FAM-F1: box, tent, iterated box, average (T3)
        + F2Catalog.operators        // FAM-F2: Gaussian (SKEL first), binomial, IIR; unsharp mask, DoG, Lanczos (T3)
        + F3Catalog.operators        // FAM-F3: Kawase, dual Kawase, pyramid
        + F4Catalog.operators        // FAM-F4: exponential, Lorentzian, low-pass, FFT convolution, Airy, Wiener
        + F5ACatalog.operators       // FAM-F5A: linear motion, anisotropic Gaussian, zoom, spin, path, streak
        + F5BCatalog.operators       // FAM-F5B: camera shake, velocity buffer, frame accumulation
        + F6Catalog.operators        // FAM-F6: disc (+ variants, defocus plot), polygonal, cat's-eye, anamorphic
        + F7Catalog.operators        // FAM-F7: depth of field, tilt-shift, variable blur, frosted glass
        + F8ACatalog.operators       // FAM-F8A: median, bilateral (+ variants), joint bilateral, guided
        + F8BCatalog.operators       // FAM-F8B: Kuwahara, domain transform, surface blur, NLM, mean-shift (T3), TV (T3)
        + F9Catalog.operators        // FAM-F9: heat equation, Perona–Malik, CED (T3); morphology, pixelate
        + F10Catalog.operators       // FAM-F10: SwiftUI blur, materials, Liquid Glass, CSS backdrop; Fluent/Android/vibrancy (T3)
        + F11Catalog.operators       // FAM-F11: drop shadow, bloom, god rays

    public static let byID: [BlurID: any BlurOperator] =
        Dictionary(operators.map { ($0.entry.id, $0) }, uniquingKeysWith: { first, _ in first })

    public static func op(_ id: BlurID) -> (any BlurOperator)? { byID[id] }
    public static func entry(_ id: BlurID) -> CatalogEntry? { byID[id]?.entry }

    /// Blur-strip order (SPEC §4.1.2): the hero dozen, then every other live entry by family F1…F11, then contrast.
    public static var stripOrder: [BlurID] {
        let live = operators.map(\.entry).filter(\.isOnStrip)
        let heroes = live.filter { $0.heroOrder != nil }.sorted { ($0.heroOrder ?? 0) < ($1.heroOrder ?? 0) }
        let order = Family.allCases
        let rest = live.filter { $0.heroOrder == nil }.enumerated().sorted { l, r in
            let a = order.firstIndex(of: l.element.family) ?? 0, b = order.firstIndex(of: r.element.family) ?? 0
            return a != b ? a < b : l.offset < r.offset
        }.map(\.element)
        return (heroes + rest).map(\.id)
    }
}

public enum SpecimenRegistry {
    /// Owner: TESTIMAGES (`SpecimenCatalog.generators` in Sources/BlurCore/Specimens/).
    public static let generators: [any SpecimenGenerating] = SpecimenCatalog.generators
    public static func generator(_ id: SpecimenID) -> (any SpecimenGenerating)? { generators.first { $0.descriptor.id == id } }
}

/// Service locator for BlurCore seams (owners in ARCHITECTURE §8).
public enum BlurServices {
    public static let floors: any FloorPageBuilding = FloorPageBuilder()          // CONTENT-LAYERS
    public static let traceScripts: any TraceScripting = TraceScripter()          // CONTENT-LAYERS
    public static let fieldGuide: any FieldGuideProviding = FieldGuideLibrary()   // CONTENT-LAYERS
    public static let lessons: [Lesson] = LessonLibrary.all                       // CONTENT-LAYERS
    public static let divergence: any DivergenceComputing = DivergenceEngine()    // ANALYSIS
    public static let fingerprints: any FingerprintComputing = FingerprintEngine() // ANALYSIS
    public static let costModel: any CostModeling = CostModel()                   // ANALYSIS
    public static let tools: any ToolConventionProviding = ToolConventions()      // SEMANTICS
    public static let psfFitter: any PSFFitting = PSFFitter()                     // CALIBRATION
}
