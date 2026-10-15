import Foundation

// OWNER: TESTIMAGES. The registry of the 22 built-in test images (SPEC §11, in its table order; `SpecimenCatalog` is a frozen
// name read by `SpecimenRegistry.generators`) and the small helpers every generator shares: option specs and option
// lookup. Generators are pure, Sendable values; canvases are generated at 0 EV (exposure is applied at render time).

public enum SpecimenCatalog {
    public static let generators: [any SpecimenGenerating] = [
        NightCityGenerator(),          //  1 night-city
        SiemensStarGenerator(),        //  2 siemens-star
        ZonePlateGenerator(),          //  3 zone-plate
        StepEdgesGenerator(),          //  4 step-edges
        NoisyStepGenerator(),          //  5 noisy-step
        ImpulseGenerator(),            //  6 impulse
        ImpulseGridGenerator(),        //  7 impulse-grid
        CheckerboardGenerator(),       //  8 checkerboard
        StripesGenerator(),            //  9 stripes
        TextSpecimenGenerator(),       // 10 text
        RampGenerator(),               // 11 ramp
        NoiseFieldGenerator(),         // 12 noise-field
        AlphaShapeGenerator(),         // 13 alpha-shape
        EdgeBarGenerator(),            // 14 edge-bar
        RingsGenerator(),              // 15 rings
        MaterialBackdropGenerator(),   // 16 material-backdrop
        SceneDepthGenerator(),         // 17 scene-depth
        SceneMotionGenerator(),        // 18 scene-motion
        AerialGenerator(),             // 19 aerial
        SunAndBarsGenerator(),         // 20 sun-and-bars
        GuidePairGenerator(),          // 21 guide-pair
        PhotoGenerator(),              // 22 photo (the app supplies the pixels; see PhotoSpecimen)
    ]

    /// The ids in SPEC §11 order.
    public static var ids: [SpecimenID] { generators.map(\.descriptor.id) }
}

// MARK: - Option helpers

/// Builds the per-image menu options (`SpecimenDescriptor.options`). Values travel as strings in `SpecimenOptions.choices`.
public enum SpecimenOptionSpec {
    public static func choice(_ key: String, _ label: String, spoken: String, _ options: [(id: String, label: String)],
                              default value: String, note: String? = nil) -> ParameterSpec {
        ParameterSpec(key: ParameterKey(rawValue: key), label: label, spokenLabel: spoken, unit: .none,
                      kind: .choice(ChoiceSpec(options.map { ChoiceOption($0.id, $0.label) })), defaultValue: .choice(value),
                      note: note)
    }
    public static func percent(_ key: String, _ label: String, spoken: String, range: ClosedRange<Double>, step: Double,
                               default value: Double, note: String? = nil) -> ParameterSpec {
        ParameterSpec(key: ParameterKey(rawValue: key), label: label, spokenLabel: spoken, unit: .percent,
                      kind: .continuous(ContinuousSpec(range: range, fineStep: step, decimals: 0)), defaultValue: .double(value),
                      note: note)
    }
}

public extension SpecimenOptions {
    /// The string value of option `key`, or `fallback` when it is absent.
    func option(_ key: String, _ fallback: String) -> String { choices[key] ?? fallback }
    /// A numeric option ("0.20", "16"), or `fallback` when absent or unparsable.
    func number(_ key: String, _ fallback: Double) -> Double { choices[key].flatMap(Double.init) ?? fallback }
    /// The seed of a stochastic option: `seed` when the caller overrides it, else the image's documented seed.
    func noiseSeed(_ documented: UInt32) -> UInt32 { seed ?? documented }
}

/// Builds a canvas with the shared defaults (opaque black backdrop, no auxiliaries, options at 0 EV).
@inline(__always)
func makeSpecimenCanvas(_ id: SpecimenID, _ frame: SpecimenFrame, _ options: SpecimenOptions, image: ImageBuffer,
                        probe: PixelPoint, auxiliary: AuxiliaryInputs = .none,
                        backdrop: SIMD4<Float> = SIMD4(0, 0, 0, 1), caption: String? = nil) -> SpecimenCanvas {
    SpecimenCanvas(id: id, options: options.canvasOptions, windowSize: frame.windowSize, margin: frame.margin, image: image,
                   auxiliary: auxiliary, defaultProbe: probe, backdrop: backdrop, caption: caption)
}
