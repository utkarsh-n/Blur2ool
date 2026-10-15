import Foundation

// OWNER: SEMANTICS. The data: which tools offer which blur, what their number is, and how sure we are.
// Every row cites its evidence. Badges follow BRIEF "Honesty rules": REFERENCE = spec, header or vendor source;
// MEASURED = fitted by the research probes on the research Mac (shown with `.notThisDevice` until this phone measures
// it); INFERRED = reasoned from indirect evidence; UNVERIFIED = words, never a number (SPEC §5.2 "Floor 1 and 2").

/// Citations used by the conventions (research file sections and the primary documents they quote).
public enum SemanticsSources {
    public static let cssBlur = SourceRef("W3C Filter Effects Module Level 1, “Filter Functions”, blur(): the length is the standard deviation (STACK §1.1)",
                                          url: "https://www.w3.org/TR/filter-effects-1/")
    public static let cssBackdrop = SourceRef("W3C Filter Effects Module Level 2 §2.1: backdrop-filter blur() with edgeMode mirror (STACK §1.4)",
                                              url: "https://drafts.csswg.org/filter-effects-2/")
    public static let cssBoxShadow = SourceRef("W3C CSS Backgrounds and Borders 3 §6.1.2 “Blurring Shadow Edges”: σ = half the blur radius (STACK §1.3)",
                                               url: "https://www.w3.org/TR/css-backgrounds-3/")
    public static let cssDropShadow = SourceRef("W3C Filter Effects Module Level 1, drop-shadow(): the third length is the standard deviation (catalog-nonlinear B9)",
                                                url: "https://www.w3.org/TR/filter-effects-1/")
    public static let svgBlur = SourceRef("W3C Filter Effects Module Level 1 §9.14 feGaussianBlur: stdDeviation; three boxes of d = ⌊1.88·s + 0.5⌋ for s ≥ 2 (STACK §1.2)",
                                          url: "https://www.w3.org/TR/filter-effects-1/")
    public static let swiftUIBlurMac = SourceRef("live-calibration.md §4.0, §5.1: ImageRenderer.cgImage edge fits, macOS 27.2, M1 Max")
    public static let swiftUIShadowMac = SourceRef("live-calibration.md §5.5: SwiftUI .shadow(radius:) σ ≈ 0.96·r, box-cubed-like")
    public static let caLayerStack = SourceRef("stack-semantics.md §3.3: CALayer.render(in:) probe, σ/shadowRadius 0.47–0.50")
    public static let caLayerCal = SourceRef("live-calibration.md §5.5: CALayer.shadowRadius r renders as CGContext blur 2r, σ ≈ 0.88–0.93·r")
    public static let cgShadow = SourceRef("live-calibration.md §5.5: CGContext.setShadow σ ≈ 0.44–0.47·blur, tent-like")
    public static let coreImage = SourceRef("live-calibration.md §5.2 and stack-semantics.md §3.4: Core Image impulse and edge fits, macOS 27.2")
    public static let coreImageHeaders = SourceRef("iOS 27 SDK CIFilterBuiltins.h and runtime CIFilter.attributes (stack-semantics.md §3.4)")
    public static let ciMaskedVariable = SourceRef("stack-semantics.md §3.4: CIMaskedVariableBlur σ ≈ 1.094·radius·mask, saturating near σ 49")
    public static let ciBlurredRectangle = SourceRef("catalog-nonlinear.md B9 (D7): CIBlurredRectangleGenerator takes σ directly")
    public static let mps = SourceRef("MPSImageConvolution.h (iOS 27 SDK): sigma is the standard deviation; MPSImageBox/Tent odd widths (STACK §3.5)")
    public static let mpsMeasured = SourceRef("live-calibration.md §5.3: MPSImageGaussianBlur σ/sigma 0.993–1.037, macOS 27.2")
    public static let vImage = SourceRef("Accelerate vImage Convolution.h (iOS 27 SDK): odd box and tent kernel widths (STACK §3.6)")
    public static let appleMaterials = SourceRef("iOS 27 SDK SwiftUI and UIKit headers: Material, UIBlurEffect.Style and glassEffect take a style, no radius (STACK §3.2)")
    public static let skia = SourceRef("AOSP hwui RenderEffect.cpp and utils/Blur.cpp: σ = 0.57735·radius + 0.5 (STACK §2.1, §2.3)",
                                       url: "https://cs.android.com/android/platform/superproject/+/main:frameworks/base/libs/hwui/utils/Blur.cpp")
    public static let surfaceFlinger = SourceRef("AOSP renderengine skia/filters: window blur at quarter resolution, Gaussian or Kawase per build (STACK §2.3)")
    public static let hwuiLegacy = SourceRef("AOSP hwui utils/Blur.cpp legacyConvertRadiusToSigma: σ = 0.3·r + 0.6 (STACK §2.3)")
    public static let compose = SourceRef("Jetpack Compose draw/Blur.kt: dp → px, then a RenderEffect blur (STACK §2.3; androidMain mapping not read)")
    public static let flutterBlur = SourceRef("Flutter dart:ui painting.dart ImageFilter.blur: sigmaX is the standard deviation (STACK §2.4)",
                                              url: "https://github.com/flutter/flutter/blob/master/engine/src/flutter/lib/ui/painting.dart")
    public static let flutterImpeller = SourceRef("Flutter Impeller sigma.cc and gaussian_blur_filter_contents.cc: ScaleSigma and √3·(σ′ − 0.5) taps (STACK §2.4)")
    public static let flutterShadow = SourceRef("Flutter dart:ui painting.dart Shadow.convertRadiusToSigma: r·0.57735 + 0.5 (read 2026-10-14)",
                                                url: "https://github.com/flutter/flutter/blob/master/engine/src/flutter/lib/ui/painting.dart")
    public static let figma = SourceRef("Figma Community staff reply, 30 July 2024, thread 22642: Dev Mode exports the blur value ÷ 2 (STACK §4.1)",
                                        url: "https://forum.figma.com/ask-the-community-7/background-blur-is-different-in-dev-mode-22642")
    public static let bjango = SourceRef("Bjango, “Blur radius comparison”, 11 January 2024: third-party measured factors (catalog-nonlinear B9)",
                                         url: "https://bjango.com/articles/blurradiuscomparison/")
    public static let sketch = SourceRef("stack-semantics.md §4.2: Sketch 98.3 sketchtool exports fitted on macOS 27.2")
    public static let sketchDocs = SourceRef("Sketch docs, “Layer and Background Blur”, “Motion and Zoom Blur” (STACK §4.2)",
                                             url: "https://www.sketch.com/docs/symbols-and-styles/styling/effects/")
    public static let photoshop = SourceRef("Adobe Photoshop “Filter effects reference”, Blur filters: labels only, no σ (STACK §4.3)",
                                            url: "https://helpx.adobe.com/photoshop/using/filter-effects-reference.html")
    public static let afterEffects = SourceRef("Adobe After Effects “Blur & Sharpen effects” (STACK §4.4)",
                                               url: "https://helpx.adobe.com/after-effects/using/blur-sharpen-effects.html")
    public static let affinity = SourceRef("affinity.help Gaussian Blur filter and Layer FX: “controls the extent of the effect” (STACK §4.5)",
                                           url: "https://affinity.help/photo/en-US.lproj/pages/Filters/filter_gaussianBlur.html")
    public static let gegl = SourceRef("GEGL operations/common/gaussian-blur.c: Size X/Y are std_dev_x/y; IIR for σ ≥ 1 (STACK §4.6)",
                                       url: "https://gitlab.gnome.org/GNOME/gegl")
    public static let gimpDocs = SourceRef("GIMP 2.10 filter dialogs (GEGL operations); σ mapping not established (STACK §4.6)")
    public static let gimp28 = SourceRef("GIMP 2.8 plug-ins/common/blur-gauss.c: std_dev = (r + 1)/√(2·ln 255) (STACK §4.6)",
                                         url: "https://gitlab.gnome.org/GNOME/gimp")
    public static let opencv = SourceRef("OpenCV 4.x imgproc smooth.dispatch.cpp: σ = sigmaX, or 0.15·ksize + 0.35 when sigmaX ≤ 0 (STACK §6.1)",
                                         url: "https://github.com/opencv/opencv")
    public static let imageMagick = SourceRef("ImageMagick MagickWand/mogrify.c: -blur r without a sigma keeps σ = 1 (STACK §6.2)",
                                              url: "https://github.com/ImageMagick/ImageMagick")
    public static let unity = SourceRef("Unity Graphics URP/HDRP source: Bloom Scatter, Max Iterations, Bokeh DoF (STACK §5.1)",
                                        url: "https://github.com/Unity-Technologies/Graphics")
    public static let unreal = SourceRef("Epic, “Bloom in Unreal Engine”; FPostProcessSettings (STACK §5.2)",
                                         url: "https://dev.epicgames.com/documentation/en-us/unreal-engine/bloom-in-unreal-engine")
    public static let threeSigma = SourceRef("Skia SkBlurEngine SigmaToRadius = ⌈3σ⌉ read backwards (STACK §2.2, §8 row 13)")
    public static let discMoment = SourceRef("COMPUTED: the per-axis second moment of a uniform disc of radius R is R/2 (catalog-spatial.md)")
}

public enum SemanticsCatalog {
    /// The research Mac every MEASURED convention was fitted on (CAL §4: macOS 27.2 (26B5101f), MacBookPro18,2, M1 Max),
    /// 13 October 2026. Values carry `.notThisDevice` until this phone's Calibrate replaces them.
    public static let researchMac = DeviceStamp(deviceModel: "Mac (Apple M1 Max)", gpuName: "Apple M1 Max", gpuFamily: "Apple7",
                                                osVersion: "macOS 27.2", osBuild: "26B5101f", isSimulator: false,
                                                date: Date(timeIntervalSince1970: 1_791_892_800), thermal: .unknown, lowPowerMode: false)

    /// Settings › Home tool, in SPEC §4.7 order (SwiftUI pt · CSS px · Figma · Sketch · Photoshop · Core Image · Android ·
    /// Flutter · GIMP · OpenCV).
    public static let homeToolIDs = ["swiftui", "css", "figma", "sketch", "photoshop", "coreimage", "android", "flutter", "gimp", "opencv"]

    /// The drop-shadow CONVENTION menu (SPEC §9.4 `drop-shadow`, P27), then Photoshop's layer style.
    public static let shadowConventionIDs = ["css-box-shadow", "css-drop-shadow", "calayer-shadow", "cgcontext-shadow", "swiftui-shadow",
                                             "figma-shadow", "sketch-shadow", "photoshop-shadow"]

    /// Floor 1 bar order after the home tool.
    public static let barOrder = ["swiftui", "css", "figma", "sketch", "photoshop", "coreimage", "mps", "android", "flutter", "gimp",
                                  "gimp-2.8", "opencv", "imagemagick", "svg", "aftereffects", "affinity", "vimage", "compose", "unity", "unreal"]

    public static let tools: [SemanticsTool] = [
        SemanticsTool(id: "swiftui", name: "SwiftUI", label: "SWIFTUI", unit: .pt, primaryBlur: "gaussian-blur"),
        SemanticsTool(id: "css", name: "CSS", label: "CSS", unit: .cssPx, primaryBlur: "gaussian-blur"),
        SemanticsTool(id: "svg", name: "SVG", label: "SVG", unit: .cssPx, primaryBlur: "gaussian-blur"),
        SemanticsTool(id: "figma", name: "Figma", label: "FIGMA", unit: .px, primaryBlur: "gaussian-blur"),
        SemanticsTool(id: "sketch", name: "Sketch", label: "SKETCH", unit: .pt, primaryBlur: "gaussian-blur"),
        SemanticsTool(id: "photoshop", name: "Photoshop", label: "PHOTOSHOP", unit: .px, primaryBlur: "gaussian-blur"),
        SemanticsTool(id: "aftereffects", name: "After Effects", label: "AFTER EFFECTS", unit: .px, primaryBlur: "gaussian-blur"),
        SemanticsTool(id: "affinity", name: "Affinity", label: "AFFINITY", unit: .px, primaryBlur: "gaussian-blur"),
        SemanticsTool(id: "coreimage", name: "Core Image", label: "CORE IMAGE", unit: .px, primaryBlur: "gaussian-blur"),
        SemanticsTool(id: "mps", name: "Metal Performance Shaders", label: "MPS", unit: .px, primaryBlur: "gaussian-blur"),
        SemanticsTool(id: "vimage", name: "vImage", label: "VIMAGE", unit: .px, primaryBlur: "box-blur"),
        SemanticsTool(id: "android", name: "Android", label: "ANDROID", unit: .px, primaryBlur: "gaussian-blur"),
        SemanticsTool(id: "compose", name: "Jetpack Compose", label: "COMPOSE", unit: .none, primaryBlur: "gaussian-blur"),
        SemanticsTool(id: "flutter", name: "Flutter", label: "FLUTTER", unit: .px, primaryBlur: "gaussian-blur"),
        SemanticsTool(id: "gimp", name: "GIMP", label: "GIMP", unit: .px, primaryBlur: "gaussian-blur"),
        SemanticsTool(id: "gimp-2.8", name: "GIMP 2.8", label: "GIMP 2.8", unit: .px, primaryBlur: "gaussian-blur"),
        SemanticsTool(id: "opencv", name: "OpenCV", label: "OPENCV", unit: .px, primaryBlur: "gaussian-blur"),
        SemanticsTool(id: "imagemagick", name: "ImageMagick", label: "IMAGEMAGICK", unit: .px, primaryBlur: "gaussian-blur"),
        SemanticsTool(id: "unity", name: "Unity", label: "UNITY", unit: .none, primaryBlur: "bloom"),
        SemanticsTool(id: "unreal", name: "Unreal Engine", label: "UNREAL", unit: .none, primaryBlur: "bloom"),
        SemanticsTool(id: "css-box-shadow", name: "CSS box-shadow", label: "CSS BOX-SHADOW", unit: .cssPx, primaryBlur: "drop-shadow", isShadowConvention: true),
        SemanticsTool(id: "css-drop-shadow", name: "CSS drop-shadow()", label: "CSS DROP-SHADOW()", unit: .cssPx, primaryBlur: "drop-shadow", isShadowConvention: true),
        SemanticsTool(id: "calayer-shadow", name: "CALayer.shadowRadius", label: "CALAYER", unit: .pt, primaryBlur: "drop-shadow", isShadowConvention: true),
        SemanticsTool(id: "cgcontext-shadow", name: "CGContext.setShadow", label: "CGCONTEXT", unit: .px, primaryBlur: "drop-shadow", isShadowConvention: true),
        SemanticsTool(id: "swiftui-shadow", name: "SwiftUI .shadow", label: "SWIFTUI .SHADOW", unit: .pt, primaryBlur: "drop-shadow", isShadowConvention: true),
        SemanticsTool(id: "figma-shadow", name: "Figma drop shadow", label: "FIGMA SHADOW", unit: .px, primaryBlur: "drop-shadow", isShadowConvention: true),
        SemanticsTool(id: "sketch-shadow", name: "Sketch shadow", label: "SKETCH SHADOW", unit: .pt, primaryBlur: "drop-shadow", isShadowConvention: true),
        SemanticsTool(id: "photoshop-shadow", name: "Photoshop Drop Shadow", label: "PHOTOSHOP SHADOW", unit: .px, primaryBlur: "drop-shadow", isShadowConvention: true),
    ]

    public static let controls: [SemanticsControl] =
        swiftUI + css + svg + figma + sketch + photoshop + afterEffects + affinity + coreImage + mps + vImage + android + compose
        + flutter + gimp + gimp28 + opencv + imageMagick + unity + unreal + shadowConventions

    // MARK: Lookup

    private static let toolIndex: [String: SemanticsTool] = Dictionary(uniqueKeysWithValues: tools.map { ($0.id, $0) })
    private static let controlIndex: [String: [BlurID: SemanticsControl]] = {
        var index: [String: [BlurID: SemanticsControl]] = [:]
        for c in controls { index[c.toolID, default: [:]][c.blur] = c }
        return index
    }()

    public static func tool(_ id: String) -> SemanticsTool? { toolIndex[id] }
    public static func control(toolID: String, blur: BlurID) -> SemanticsControl? { controlIndex[toolID]?[blur] }
    public static func controls(toolID: String) -> [SemanticsControl] { controls.filter { $0.toolID == toolID } }
    /// Every control that offers `blur`, in bar order (where the blur lives when no design tool offers it).
    public static func controls(for blur: BlurID) -> [SemanticsControl] {
        let order = Dictionary(uniqueKeysWithValues: (barOrder + shadowConventionIDs).enumerated().map { ($1, $0) })
        return controls.filter { $0.blur == blur }.sorted { (order[$0.toolID] ?? 99) < (order[$1.toolID] ?? 99) }
    }
    public static func offer(toolID: String, blur: BlurID) -> SemanticsOffer {
        guard let t = tool(toolID) else { return .unknownTool(toolID) }
        return control(toolID: toolID, blur: blur).map(SemanticsOffer.offered) ?? .notOffered(t)
    }

    // MARK: Builders

    private static let mac: Qualifiers = [.notThisDevice]
    private static func linear(_ slope: Double, _ offset: Double = 0, offsetScales: Bool = true) -> SemanticsMapping {
        .law(.linear(slope: slope, offset: offset, offsetScales: offsetScales))
    }
    private static func unverified(_ tool: String, _ blur: BlurID, _ name: String, unit: ParameterUnit = .px, scales: Bool = false,
                                   subject: String, source: SourceRef, caption: String = "UNDOCUMENTED") -> SemanticsControl {
        SemanticsControl(toolID: tool, blur: blur, controlName: name, unit: unit, scalesWithDisplay: scales,
                         mapping: .unverified(subject: subject), provenance: nil, source: source, kernelMatch: .unknown, caption: caption)
    }
    private static func noSigma(_ tool: String, _ blur: BlurID, _ name: String, unit: ParameterUnit = .none, words: String, chip: String,
                                spoken: String, provenance: Provenance = .reference, source: SourceRef,
                                measuredOn: DeviceStamp? = nil) -> SemanticsControl {
        SemanticsControl(toolID: tool, blur: blur, controlName: name, unit: unit, scalesWithDisplay: false,
                         mapping: .noSigma(words: words, chip: chip, spoken: spoken), provenance: provenance, source: source,
                         measuredOn: measuredOn, qualifiers: measuredOn == nil ? [] : mac, kernelMatch: .unknown)
    }

    // MARK: SwiftUI (pt)

    static let swiftUIBlurControl = SemanticsControl(
        toolID: "swiftui", blur: "gaussian-blur", controlName: ".blur(radius:)", unit: .pt, scalesWithDisplay: true,
        mapping: .law(.swiftUIBlur), provenance: .measured, source: SemanticsSources.swiftUIBlurMac, measuredOn: researchMac,
        qualifiers: [.notThisDevice, .offscreen], kernelMatch: .sameBelowSwitch, calibrationSubject: .swiftUIBlur,
        lawDescription: "σ ≈ r·scale up to ≈ 5 px, ≈ 0.90·r·scale above (box-cubed-like, resampled)",
        kernelNote: "BOX-CUBED-LIKE ABOVE THE SWITCH")

    static let swiftUI: [SemanticsControl] = [
        swiftUIBlurControl,
        { var c = swiftUIBlurControl; c.blur = "swiftui-layer-blur"; c.kernelMatch = .same; return c }(),
        SemanticsControl(toolID: "swiftui", blur: "drop-shadow", controlName: ".shadow(radius:)", unit: .pt, scalesWithDisplay: true,
                         mapping: linear(0.96), provenance: .measured, source: SemanticsSources.swiftUIShadowMac, measuredOn: researchMac,
                         qualifiers: [.notThisDevice, .offscreen], kernelMatch: .sigmaOnly, calibrationSubject: .swiftUIShadow,
                         lawDescription: "σ ≈ 0.96·r·scale", kernelNote: "BOX-CUBED-LIKE KERNEL"),
        noSigma("swiftui", "apple-uiblureffect", "Material (.ultraThinMaterial …)", words: "STYLE, NO RADIUS", chip: "STYLE",
                spoken: "SwiftUI materials take a style name, not a radius", source: SemanticsSources.appleMaterials),
        noSigma("swiftui", "liquid-glass", ".glassEffect(_:in:)", words: "STYLE, NO RADIUS", chip: "STYLE",
                spoken: "Liquid Glass takes a style, not a radius", source: SemanticsSources.appleMaterials),
    ]

    // MARK: Web

    static let css: [SemanticsControl] = [
        SemanticsControl(toolID: "css", blur: "gaussian-blur", controlName: "filter: blur()", unit: .cssPx, scalesWithDisplay: true,
                         mapping: linear(1), provenance: .reference, source: SemanticsSources.cssBlur, kernelMatch: .same,
                         lawDescription: "σ = value (CSS px × display scale)"),
        SemanticsControl(toolID: "css", blur: "css-backdrop-filter", controlName: "backdrop-filter: blur()", unit: .cssPx,
                         scalesWithDisplay: true, mapping: linear(1), provenance: .reference, source: SemanticsSources.cssBackdrop,
                         kernelMatch: .same, lawDescription: "σ = value (CSS px × display scale), mirrored edges"),
        SemanticsControl(toolID: "css", blur: "drop-shadow", controlName: "box-shadow blur radius", unit: .cssPx, scalesWithDisplay: true,
                         mapping: linear(0.5), provenance: .reference, source: SemanticsSources.cssBoxShadow, kernelMatch: .same,
                         lawDescription: "σ = value ÷ 2"),
    ]

    static let svg: [SemanticsControl] = [
        SemanticsControl(toolID: "svg", blur: "gaussian-blur", controlName: "<feGaussianBlur stdDeviation>", unit: .cssPx,
                         scalesWithDisplay: true, mapping: linear(1), provenance: .reference, source: SemanticsSources.svgBlur,
                         kernelMatch: .same, lawDescription: "σ = stdDeviation (user units)"),
        SemanticsControl(toolID: "svg", blur: "iterated-box", controlName: "<feGaussianBlur stdDeviation> (three-box rule)", unit: .cssPx,
                         scalesWithDisplay: true, mapping: .law(.svgThreeBox), provenance: .computed, source: SemanticsSources.svgBlur,
                         kernelMatch: .same, lawDescription: "d = ⌊1.88·s + 0.5⌋, σ = √(Σ(d² − 1)/12): about 6 % under s",
                         caption: "WHERE THE THREE-BOX RULE IS USED"),
        SemanticsControl(toolID: "svg", blur: "drop-shadow", controlName: "<feDropShadow stdDeviation>", unit: .cssPx,
                         scalesWithDisplay: true, mapping: linear(1), provenance: .reference, source: SemanticsSources.cssDropShadow,
                         kernelMatch: .same, lawDescription: "σ = stdDeviation"),
    ]

    // MARK: Design tools

    static let figma: [SemanticsControl] = [
        SemanticsControl(toolID: "figma", blur: "gaussian-blur", controlName: "Layer blur", unit: .px, scalesWithDisplay: true,
                         mapping: linear(0.5), provenance: .inferred, source: SemanticsSources.figma, kernelMatch: .unknown,
                         lawDescription: "σ = value ÷ 2 (from Dev Mode's CSS export; renderer not measured)"),
        SemanticsControl(toolID: "figma", blur: "css-backdrop-filter", controlName: "Background blur", unit: .px, scalesWithDisplay: true,
                         mapping: linear(0.5), provenance: .inferred, source: SemanticsSources.figma, kernelMatch: .unknown,
                         lawDescription: "σ = value ÷ 2 (Dev Mode exports backdrop-filter: blur(value ÷ 2))"),
        SemanticsControl(toolID: "figma", blur: "variable-progressive-blur", controlName: "Layer blur › Progressive (start, end)",
                         unit: .px, scalesWithDisplay: true, mapping: linear(0.5), provenance: .inferred, source: SemanticsSources.figma,
                         kernelMatch: .unknown, lawDescription: "σ = value ÷ 2 at each end", caption: "AT EACH END"),
        SemanticsControl(toolID: "figma", blur: "drop-shadow", controlName: "Drop shadow › Blur", unit: .px, scalesWithDisplay: true,
                         mapping: linear(1 / (2 * 1.136)), provenance: .reference, source: SemanticsSources.bjango, qualifiers: [.weakSource],
                         kernelMatch: .unknown, lawDescription: "σ ≈ 0.44·value (value = 1.136 × the matching CSS box-shadow blur)",
                         caption: "THIRD-PARTY MEASUREMENT"),
    ]

    static let sketch: [SemanticsControl] = [
        SemanticsControl(toolID: "sketch", blur: "gaussian-blur", controlName: "Layer blur (Gaussian)", unit: .pt, scalesWithDisplay: true,
                         mapping: linear(1), provenance: .measured, source: SemanticsSources.sketch, measuredOn: researchMac,
                         qualifiers: mac, kernelMatch: .sigmaOnly, lawDescription: "σ = value, cut at about ±2.5σ, gamma-space",
                         kernelNote: "TRUNCATED GAUSSIAN"),
        SemanticsControl(toolID: "sketch", blur: "anisotropic-gaussian", controlName: "Motion blur (Blur, Angle)", unit: .pt,
                         scalesWithDisplay: true, mapping: linear(0.96), provenance: .measured, source: SemanticsSources.sketch,
                         measuredOn: researchMac, qualifiers: mac, kernelMatch: .same, lawDescription: "σ ≈ 0.96·value along the angle"),
        SemanticsControl(toolID: "sketch", blur: "linear-motion-blur", controlName: "Motion blur (Blur, Angle)", unit: .pt,
                         scalesWithDisplay: true, mapping: linear(0.96), provenance: .measured, source: SemanticsSources.sketch,
                         measuredOn: researchMac, qualifiers: mac, kernelMatch: .sigmaOnly, lawDescription: "σ ≈ 0.96·value along the angle",
                         kernelNote: "GAUSSIAN STREAK, NOT A BOX"),
        SemanticsControl(toolID: "sketch", blur: "variable-progressive-blur", controlName: "Layer blur › Linear / Radial Progressive",
                         unit: .pt, scalesWithDisplay: true, mapping: linear(1), provenance: .inferred, source: SemanticsSources.sketch,
                         kernelMatch: .unknown, lawDescription: "σ = value at the strong end (uniform blur MEASURED; progressive INFERRED)"),
        unverified("sketch", "radial-zoom-blur", "Zoom blur (Blur, centre)", unit: .pt, scales: true, subject: "Sketch zoom blur amount",
                   source: SemanticsSources.sketchDocs),
        unverified("sketch", "css-backdrop-filter", "Background blur", unit: .pt, scales: true, subject: "Sketch background blur",
                   source: SemanticsSources.sketchDocs, caption: "NOT MEASURED"),
    ]

    static let photoshop: [SemanticsControl] = [
        unverified("photoshop", "gaussian-blur", "Gaussian Blur › Radius", subject: "Photoshop Gaussian Blur radius",
                   source: SemanticsSources.photoshop, caption: "UNDOCUMENTED · COMMUNITY CLAIMS CONFLICT"),
        unverified("photoshop", "box-blur", "Box Blur › Radius", subject: "Photoshop Box Blur radius", source: SemanticsSources.photoshop),
        unverified("photoshop", "linear-motion-blur", "Motion Blur › Distance", subject: "Photoshop Motion Blur distance",
                   source: SemanticsSources.photoshop),
        unverified("photoshop", "radial-zoom-blur", "Radial Blur › Zoom › Amount", unit: .none, subject: "Photoshop Radial Blur zoom amount",
                   source: SemanticsSources.photoshop),
        unverified("photoshop", "spin-blur", "Radial Blur › Spin › Amount", unit: .none, subject: "Photoshop Radial Blur spin amount",
                   source: SemanticsSources.photoshop),
        unverified("photoshop", "path-blur", "Blur Gallery › Path Blur › Speed", unit: .none, subject: "Photoshop Path Blur speed",
                   source: SemanticsSources.photoshop),
        unverified("photoshop", "tilt-shift", "Blur Gallery › Tilt-Shift › Blur", subject: "Photoshop Tilt-Shift blur",
                   source: SemanticsSources.photoshop),
        unverified("photoshop", "variable-progressive-blur", "Blur Gallery › Field Blur › Blur", subject: "Photoshop Field Blur",
                   source: SemanticsSources.photoshop),
        unverified("photoshop", "surface-blur", "Surface Blur › Radius, Threshold", subject: "Photoshop Surface Blur radius",
                   source: SemanticsSources.photoshop),
        unverified("photoshop", "frosted-glass-noise", "Stylize › Diffuse / Distort › Glass", unit: .none,
                   subject: "Photoshop Glass distortion", source: SemanticsSources.photoshop),
        unverified("photoshop", "fft-convolution", "Shape Blur › Radius", subject: "Photoshop Shape Blur radius",
                   source: SemanticsSources.photoshop),
        unverified("photoshop", "unsharp-mask", "Unsharp Mask › Radius", subject: "Photoshop Unsharp Mask radius",
                   source: SemanticsSources.photoshop),
        SemanticsControl(toolID: "photoshop", blur: "disc-blur", controlName: "Lens Blur › Iris Radius", unit: .px, scalesWithDisplay: false,
                         mapping: linear(0.5), provenance: .inferred, source: SemanticsSources.photoshop, kernelMatch: .unknown,
                         lawDescription: "aperture radius R, σ = R ÷ 2 for a round iris", caption: "IRIS SHAPE SETS THE KERNEL"),
        SemanticsControl(toolID: "photoshop", blur: "polygonal-bokeh", controlName: "Lens Blur › Iris Radius (hexagon)", unit: .px,
                         scalesWithDisplay: false, mapping: linear((5.0 / 24).squareRoot()), provenance: .inferred,
                         source: SemanticsSources.photoshop, kernelMatch: .unknown,
                         lawDescription: "hexagon circumradius R, σ = R·√(5/24) = 0.456·R", caption: "IRIS SHAPE SETS THE KERNEL"),
        noSigma("photoshop", "average-blur", "Blur › Average", words: "NO PARAMETER", chip: "NONE",
                spoken: "Photoshop's Average takes no parameter", source: SemanticsSources.photoshop),
        noSigma("photoshop", "depth-of-field-coc", "Lens Blur (depth map)", words: "VARIES WITH DEPTH", chip: "DEPTH",
                spoken: "Photoshop's Lens Blur sets the blur per pixel from a depth map", source: SemanticsSources.photoshop),
        noSigma("photoshop", "median", "Noise › Median › Radius", unit: .px, words: "WINDOW, NO σ", chip: "NO σ",
                spoken: "Photoshop's Median radius sets a window, not a sigma", source: SemanticsSources.photoshop),
        noSigma("photoshop", "morphology", "Other › Maximum / Minimum › Radius", unit: .px, words: "WINDOW, NO σ", chip: "NO σ",
                spoken: "Photoshop's Maximum and Minimum radius sets a window, not a sigma", source: SemanticsSources.photoshop),
        noSigma("photoshop", "pixelate", "Pixelate › Mosaic › Cell Size", unit: .px, words: "CELL SIZE", chip: "CELL",
                spoken: "Photoshop's Mosaic takes a cell size, not a sigma", source: SemanticsSources.photoshop),
        SemanticsControl(toolID: "photoshop", blur: "drop-shadow", controlName: "Layer Style › Drop Shadow › Size", unit: .px,
                         scalesWithDisplay: false, mapping: linear(1 / (2 * 1.136)), provenance: .reference, source: SemanticsSources.bjango,
                         qualifiers: [.weakSource], kernelMatch: .unknown, lawDescription: "σ ≈ 0.44·size (factor 1.136 against CSS)",
                         caption: "THIRD-PARTY MEASUREMENT"),
    ]

    static let afterEffects: [SemanticsControl] = [
        unverified("aftereffects", "gaussian-blur", "Gaussian Blur › Blurriness", subject: "After Effects Gaussian Blur blurriness",
                   source: SemanticsSources.afterEffects),
        unverified("aftereffects", "box-blur", "Fast Box Blur › Blur Radius (Iterations 1)", subject: "After Effects Fast Box Blur radius",
                   source: SemanticsSources.afterEffects, caption: "BOX WIDTH UNDOCUMENTED"),
        unverified("aftereffects", "iterated-box", "Fast Box Blur › Blur Radius, Iterations", subject: "After Effects Fast Box Blur radius",
                   source: SemanticsSources.afterEffects, caption: "BOX WIDTH UNDOCUMENTED"),
        unverified("aftereffects", "linear-motion-blur", "Directional Blur › Blur Length", subject: "After Effects Directional Blur length",
                   source: SemanticsSources.afterEffects),
        unverified("aftereffects", "radial-zoom-blur", "Radial Blur › Zoom › Amount", unit: .none, subject: "After Effects Radial Blur amount",
                   source: SemanticsSources.afterEffects),
        unverified("aftereffects", "spin-blur", "Radial Blur › Spin › Amount", unit: .none, subject: "After Effects Radial Blur amount",
                   source: SemanticsSources.afterEffects),
        unverified("aftereffects", "bilateral", "Bilateral Blur › Radius, Threshold", subject: "After Effects Bilateral Blur radius",
                   source: SemanticsSources.afterEffects),
        unverified("aftereffects", "variable-progressive-blur", "Compound Blur › Maximum Blur", subject: "After Effects Compound Blur maximum",
                   source: SemanticsSources.afterEffects),
        unverified("aftereffects", "bloom", "Glow › Glow Radius", subject: "After Effects Glow radius", source: SemanticsSources.afterEffects),
        unverified("aftereffects", "drop-shadow", "Drop Shadow › Softness", subject: "After Effects Drop Shadow softness",
                   source: SemanticsSources.afterEffects),
        SemanticsControl(toolID: "aftereffects", blur: "disc-blur", controlName: "Camera Lens Blur › Blur Radius", unit: .px,
                         scalesWithDisplay: false, mapping: linear(0.5), provenance: .inferred, source: SemanticsSources.afterEffects,
                         kernelMatch: .unknown, lawDescription: "aperture radius R, σ = R ÷ 2 for a round iris",
                         caption: "IRIS SHAPE SETS THE KERNEL"),
    ]

    static let affinity: [SemanticsControl] = [
        unverified("affinity", "gaussian-blur", "Gaussian Blur › Radius", subject: "Affinity Gaussian Blur radius", source: SemanticsSources.affinity),
        unverified("affinity", "box-blur", "Box Blur › Radius", subject: "Affinity Box Blur radius", source: SemanticsSources.affinity),
        unverified("affinity", "linear-motion-blur", "Motion Blur › Radius", subject: "Affinity Motion Blur radius", source: SemanticsSources.affinity),
        unverified("affinity", "radial-zoom-blur", "Zoom Blur › Radius", subject: "Affinity Zoom Blur radius", source: SemanticsSources.affinity),
        unverified("affinity", "disc-blur", "Lens Blur › Radius", subject: "Affinity Lens Blur radius", source: SemanticsSources.affinity),
        unverified("affinity", "bilateral", "Bilateral Blur › Radius", subject: "Affinity Bilateral Blur radius", source: SemanticsSources.affinity),
        unverified("affinity", "depth-of-field-coc", "Depth of Field › Radius", subject: "Affinity Depth of Field radius",
                   source: SemanticsSources.affinity),
        noSigma("affinity", "median", "Median Blur › Radius", unit: .px, words: "WINDOW, NO σ", chip: "NO σ",
                spoken: "Affinity's Median radius sets a window, not a sigma", source: SemanticsSources.affinity),
    ]

    // MARK: Apple frameworks (image px)

    static let coreImage: [SemanticsControl] = [
        SemanticsControl(toolID: "coreimage", blur: "gaussian-blur", controlName: "CIGaussianBlur inputRadius", unit: .px,
                         scalesWithDisplay: false, mapping: linear(1), provenance: .measured, source: SemanticsSources.coreImage,
                         measuredOn: researchMac, qualifiers: mac, kernelMatch: .same, calibrationSubject: .ciGaussianBlur,
                         lawDescription: "σ = radius (docs say only “area of effect”)"),
        SemanticsControl(toolID: "coreimage", blur: "box-blur", controlName: "CIBoxBlur inputRadius", unit: .px, scalesWithDisplay: false,
                         mapping: .law(.ciBoxWidth), provenance: .measured, source: SemanticsSources.coreImage, measuredOn: researchMac,
                         qualifiers: mac, kernelMatch: .same, lawDescription: "box width = 2⌈r/2⌉ − 1: the “radius” is a diameter",
                         integerValued: true),
        SemanticsControl(toolID: "coreimage", blur: "disc-blur", controlName: "CIDiscBlur inputRadius", unit: .px, scalesWithDisplay: false,
                         mapping: linear(0.5), provenance: .measured, source: SemanticsSources.coreImage, measuredOn: researchMac,
                         qualifiers: mac, kernelMatch: .same, calibrationSubject: .ciDiscBlur,
                         lawDescription: "disc radius = r, σ = r ÷ 2 (CIBokehBlur at default ring and softness is identical)"),
        SemanticsControl(toolID: "coreimage", blur: "anisotropic-gaussian", controlName: "CIMotionBlur inputRadius", unit: .px,
                         scalesWithDisplay: false, mapping: linear(1), provenance: .measured, source: SemanticsSources.coreImage,
                         measuredOn: researchMac, qualifiers: mac, kernelMatch: .same, calibrationSubject: .ciMotionBlur,
                         lawDescription: "a one-pixel line with Gaussian weights, σ = r along inputAngle"),
        SemanticsControl(toolID: "coreimage", blur: "linear-motion-blur", controlName: "CIMotionBlur inputRadius", unit: .px,
                         scalesWithDisplay: false, mapping: linear(1), provenance: .measured, source: SemanticsSources.coreImage,
                         measuredOn: researchMac, qualifiers: mac, kernelMatch: .sigmaOnly, calibrationSubject: .ciMotionBlur,
                         lawDescription: "σ = r along inputAngle, Gaussian-weighted", kernelNote: "GAUSSIAN STREAK, NOT A BOX"),
        SemanticsControl(toolID: "coreimage", blur: "variable-progressive-blur", controlName: "CIMaskedVariableBlur inputRadius", unit: .px,
                         scalesWithDisplay: false, mapping: linear(1.094), provenance: .measured, source: SemanticsSources.ciMaskedVariable,
                         measuredOn: researchMac, qualifiers: mac, kernelMatch: .same, calibrationSubject: .ciMaskedVariableBlur,
                         lawDescription: "σ ≈ 1.094·r·mask, saturating near σ 49", caption: "AT FULL MASK", maxSigmaUnits: 49),
        { var c = unverified("coreimage", "radial-zoom-blur", "CIZoomBlur inputAmount", unit: .none, subject: "CIZoomBlur amount",
                             source: SemanticsSources.coreImage, caption: "SOURCES DISAGREE")
          c.qualifiers = [.sourcesDisagree]
          c.lawDescription = nil
          return c }(),
        unverified("coreimage", "bloom", "CIBloom inputRadius", subject: "CIBloom radius", source: SemanticsSources.coreImageHeaders,
                   caption: "NOT MEASURED"),
        unverified("coreimage", "unsharp-mask", "CIUnsharpMask inputRadius", subject: "CIUnsharpMask radius",
                   source: SemanticsSources.coreImageHeaders, caption: "NOT MEASURED"),
        unverified("coreimage", "guided", "CIGuidedFilter inputRadius", subject: "CIGuidedFilter radius",
                   source: SemanticsSources.coreImageHeaders, caption: "NOT MEASURED"),
        unverified("coreimage", "joint-bilateral", "CIEdgePreserveUpsampleFilter", unit: .none, subject: "CIEdgePreserveUpsampleFilter",
                   source: SemanticsSources.coreImageHeaders, caption: "JOINT BILATERAL IS INFERRED"),
        unverified("coreimage", "depth-of-field-coc", "CIDepthBlurEffect", unit: .none, subject: "CIDepthBlurEffect aperture",
                   source: SemanticsSources.coreImageHeaders, caption: "NOT MEASURED"),
        noSigma("coreimage", "median", "CIMedianFilter", words: "FIXED WINDOW", chip: "FIXED",
                spoken: "Core Image's median has no parameter; it behaves as a three by three window", provenance: .measured,
                source: SemanticsSources.coreImage, measuredOn: researchMac),
        noSigma("coreimage", "morphology", "CIMorphologyMaximum / Minimum inputRadius", unit: .px, words: "RADIUS, NO σ", chip: "NO σ",
                spoken: "Core Image's morphology radius sets a circular window, not a sigma", source: SemanticsSources.coreImageHeaders),
        noSigma("coreimage", "average-blur", "CIAreaAverage", words: "NO PARAMETER", chip: "NONE",
                spoken: "Core Image's area average takes no parameter", source: SemanticsSources.coreImageHeaders),
        noSigma("coreimage", "pixelate", "CIPixellate inputScale", unit: .px, words: "CELL SIZE", chip: "CELL",
                spoken: "Core Image's pixellate takes a cell size, not a sigma", source: SemanticsSources.coreImageHeaders),
        SemanticsControl(toolID: "coreimage", blur: "drop-shadow", controlName: "CIBlurredRectangleGenerator inputSigma", unit: .px,
                         scalesWithDisplay: false, mapping: linear(1), provenance: .reference, source: SemanticsSources.ciBlurredRectangle,
                         kernelMatch: .same, lawDescription: "σ = inputSigma"),
    ]

    static let mps: [SemanticsControl] = [
        SemanticsControl(toolID: "mps", blur: "gaussian-blur", controlName: "MPSImageGaussianBlur sigma", unit: .px, scalesWithDisplay: false,
                         mapping: linear(1), provenance: .measured, source: SemanticsSources.mpsMeasured, measuredOn: researchMac,
                         qualifiers: mac, kernelMatch: .same, calibrationSubject: .mpsGaussianBlur,
                         lawDescription: "σ = sigma (the header: “an approximate gaussian”, about 10 bits)"),
        SemanticsControl(toolID: "mps", blur: "box-blur", controlName: "MPSImageBox kernelWidth", unit: .px, scalesWithDisplay: false,
                         mapping: .law(.boxWidth), provenance: .reference, source: SemanticsSources.mps, kernelMatch: .same,
                         lawDescription: "box of w taps (odd), σ = √((w² − 1)/12)", integerValued: true),
        SemanticsControl(toolID: "mps", blur: "tent-blur", controlName: "MPSImageTent kernelWidth", unit: .px, scalesWithDisplay: false,
                         mapping: .law(.tentWidth), provenance: .reference, source: SemanticsSources.mps, kernelMatch: .same,
                         lawDescription: "two boxes of (w + 1)/2, σ = √((((w + 1)/2)² − 1)/6)", integerValued: true),
        noSigma("mps", "median", "MPSImageMedian kernelDiameter", unit: .px, words: "DIAMETER, NO σ", chip: "NO σ",
                spoken: "MPS median takes a window diameter, not a sigma", source: SemanticsSources.mps),
        noSigma("mps", "morphology", "MPSImageAreaMax / AreaMin kernelWidth", unit: .px, words: "WINDOW, NO σ", chip: "NO σ",
                spoken: "MPS area max and min take a window, not a sigma", source: SemanticsSources.mps),
        unverified("mps", "guided", "MPSImageGuidedFilter kernelDiameter", subject: "MPSImageGuidedFilter diameter",
                   source: SemanticsSources.mps, caption: "NOT MEASURED"),
    ]

    static let vImage: [SemanticsControl] = [
        SemanticsControl(toolID: "vimage", blur: "box-blur", controlName: "vImageBoxConvolve kernel_width", unit: .px, scalesWithDisplay: false,
                         mapping: .law(.boxWidth), provenance: .reference, source: SemanticsSources.vImage, kernelMatch: .same,
                         lawDescription: "box of w taps (odd), σ = √((w² − 1)/12)", integerValued: true),
        SemanticsControl(toolID: "vimage", blur: "tent-blur", controlName: "vImageTentConvolve kernel_width", unit: .px,
                         scalesWithDisplay: false, mapping: .law(.tentWidth), provenance: .reference, source: SemanticsSources.vImage,
                         kernelMatch: .same, lawDescription: "tent of width w (odd), σ = √((((w + 1)/2)² − 1)/6)", integerValued: true),
    ]

    // MARK: Android, Compose, Flutter

    static let android: [SemanticsControl] = [
        SemanticsControl(toolID: "android", blur: "gaussian-blur", controlName: "RenderEffect.createBlurEffect(radiusX, radiusY)", unit: .px,
                         scalesWithDisplay: false, mapping: linear(SemanticsMath.skiaSigmaScale, 0.5), provenance: .reference,
                         source: SemanticsSources.skia, kernelMatch: .same, lawDescription: "σ = 0.57735·r + 0.5 (Skia's legacy “radius”)"),
        SemanticsControl(toolID: "android", blur: "android-renderEffect", controlName: "RenderEffect.createBlurEffect(radiusX, radiusY)",
                         unit: .px, scalesWithDisplay: false, mapping: linear(SemanticsMath.skiaSigmaScale, 0.5), provenance: .reference,
                         source: SemanticsSources.skia, kernelMatch: .same, lawDescription: "σ = 0.57735·r + 0.5 (Skia's legacy “radius”)"),
        SemanticsControl(toolID: "android", blur: "drop-shadow", controlName: "Paint.setShadowLayer(radius)", unit: .px,
                         scalesWithDisplay: false, mapping: linear(SemanticsMath.skiaSigmaScale, 0.5), provenance: .reference,
                         source: SemanticsSources.skia, kernelMatch: .same, lawDescription: "σ = 0.57735·r + 0.5"),
        noSigma("android", "kawase-blur", "Window.setBackgroundBlurRadius (Kawase build)", unit: .px, words: "PASS SCHEDULE", chip: "PASSES",
                spoken: "the window compositor turns the radius into up to four Kawase passes, not a sigma",
                source: SemanticsSources.surfaceFlinger),
    ]

    static let compose: [SemanticsControl] = [
        SemanticsControl(toolID: "compose", blur: "gaussian-blur", controlName: "Modifier.blur(radius: Dp)", unit: .none,
                         unitSymbolOverride: "dp", spokenUnitOverride: "density-independent pixels", scalesWithDisplay: true,
                         mapping: linear(SemanticsMath.skiaSigmaScale, 0.5, offsetScales: false), provenance: .inferred,
                         source: SemanticsSources.compose, kernelMatch: .same,
                         lawDescription: "σ = 0.57735·(dp × density) + 0.5 px, density taken as this display's scale"),
        SemanticsControl(toolID: "compose", blur: "android-renderEffect", controlName: "Modifier.blur(radius: Dp)", unit: .none,
                         unitSymbolOverride: "dp", spokenUnitOverride: "density-independent pixels", scalesWithDisplay: true,
                         mapping: linear(SemanticsMath.skiaSigmaScale, 0.5, offsetScales: false), provenance: .inferred,
                         source: SemanticsSources.compose, kernelMatch: .same,
                         lawDescription: "σ = 0.57735·(dp × density) + 0.5 px, density taken as this display's scale"),
    ]

    static let flutter: [SemanticsControl] = [
        SemanticsControl(toolID: "flutter", blur: "gaussian-blur", controlName: "ImageFilter.blur(sigmaX:)", unit: .px, scalesWithDisplay: true,
                         mapping: linear(1), provenance: .reference, source: SemanticsSources.flutterBlur, kernelMatch: .same,
                         lawDescription: "σ = sigmaX (logical px × display scale); Impeller rescales it (σ 10 → about 7.5)",
                         caption: "SKIA BACKEND · IMPELLER BLURS LESS"),
        SemanticsControl(toolID: "flutter", blur: "css-backdrop-filter", controlName: "BackdropFilter(ImageFilter.blur(sigmaX:))", unit: .px,
                         scalesWithDisplay: true, mapping: linear(1), provenance: .reference, source: SemanticsSources.flutterBlur,
                         kernelMatch: .same, lawDescription: "σ = sigmaX (logical px × display scale)",
                         caption: "SKIA BACKEND · IMPELLER BLURS LESS"),
        SemanticsControl(toolID: "flutter", blur: "drop-shadow", controlName: "BoxShadow(blurRadius:)", unit: .px, scalesWithDisplay: true,
                         mapping: linear(SemanticsMath.skiaSigmaScale, 0.5), provenance: .reference, source: SemanticsSources.flutterShadow,
                         kernelMatch: .same, lawDescription: "σ = 0.57735·blurRadius + 0.5 (logical px)", caption: "DOC SAYS σ · CODE CONVERTS"),
    ]

    // MARK: Libraries

    static let gimp: [SemanticsControl] = [
        SemanticsControl(toolID: "gimp", blur: "gaussian-blur", controlName: "Gaussian Blur › Size X / Size Y", unit: .px,
                         scalesWithDisplay: false, mapping: linear(1), provenance: .reference, source: SemanticsSources.gegl,
                         kernelMatch: .same, lawDescription: "σ = Size (GIMP 2.10 and 3.0, linear light)"),
        SemanticsControl(toolID: "gimp", blur: "iir-gaussian", controlName: "Gaussian Blur › Size (Filter: IIR)", unit: .px,
                         scalesWithDisplay: false, mapping: linear(1), provenance: .reference, source: SemanticsSources.gegl,
                         kernelMatch: .same, lawDescription: "σ = Size; Young–van Vliet IIR for σ ≥ 1"),
        unverified("gimp", "linear-motion-blur", "Motion Blur (Linear) › Length", subject: "GIMP linear motion blur length",
                   source: SemanticsSources.gimpDocs),
        unverified("gimp", "radial-zoom-blur", "Motion Blur (Zoom) › Factor", unit: .none, subject: "GIMP zoom motion blur factor",
                   source: SemanticsSources.gimpDocs),
        unverified("gimp", "spin-blur", "Motion Blur (Circular) › Angle", unit: .degrees, subject: "GIMP circular motion blur angle",
                   source: SemanticsSources.gimpDocs),
        unverified("gimp", "surface-blur", "Selective Gaussian Blur › Blur radius, Max. delta", subject: "GIMP selective Gaussian blur radius",
                   source: SemanticsSources.gimpDocs),
        unverified("gimp", "bilateral", "Bilateral Filter › Blur radius", subject: "GIMP bilateral filter radius",
                   source: SemanticsSources.gimpDocs),
        unverified("gimp", "frosted-glass-noise", "Noise › Spread › Amount", subject: "GIMP spread amount", source: SemanticsSources.gimpDocs),
        unverified("gimp", "unsharp-mask", "Enhance › Unsharp Mask › Radius", subject: "GIMP unsharp mask radius",
                   source: SemanticsSources.gimpDocs),
        noSigma("gimp", "median", "Median Blur › Radius", unit: .px, words: "WINDOW, NO σ", chip: "NO σ",
                spoken: "GIMP's median radius sets a window, not a sigma", source: SemanticsSources.gimpDocs),
        noSigma("gimp", "pixelate", "Pixelize › Block width", unit: .px, words: "CELL SIZE", chip: "CELL",
                spoken: "GIMP's Pixelize takes a block size, not a sigma", source: SemanticsSources.gimpDocs),
    ]

    static let gimp28: [SemanticsControl] = [
        SemanticsControl(toolID: "gimp-2.8", blur: "gaussian-blur", controlName: "Gaussian Blur › Blur Radius", unit: .px,
                         scalesWithDisplay: false, mapping: linear(1 / SemanticsMath.gimp28Divisor, 1 / SemanticsMath.gimp28Divisor),
                         provenance: .reference, source: SemanticsSources.gimp28, kernelMatch: .same,
                         lawDescription: "σ = (r + 1)/3.329: the Gaussian falls to 1/255 at r + 1"),
    ]

    static let opencv: [SemanticsControl] = [
        SemanticsControl(toolID: "opencv", blur: "gaussian-blur", controlName: "GaussianBlur(ksize: (0, 0), sigmaX:)", unit: .px,
                         scalesWithDisplay: false, mapping: linear(1), provenance: .reference, source: SemanticsSources.opencv,
                         kernelMatch: .same, lawDescription: "σ = sigmaX; ksize = 2·round(3σ) + 1 for 8-bit images (±4σ for float)"),
        SemanticsControl(toolID: "opencv", blur: "box-blur", controlName: "blur(ksize:)", unit: .px, scalesWithDisplay: false,
                         mapping: .law(.boxWidth), provenance: .reference, source: SemanticsSources.opencv, kernelMatch: .same,
                         lawDescription: "box of ksize taps, σ = √((k² − 1)/12)", integerValued: true),
        SemanticsControl(toolID: "opencv", blur: "bilateral", controlName: "bilateralFilter(d:, sigmaColor:, sigmaSpace:)", unit: .px,
                         scalesWithDisplay: false, mapping: linear(1), provenance: .reference, source: SemanticsSources.opencv,
                         kernelMatch: .sigmaOnly, lawDescription: "σs = sigmaSpace; on 8-bit input the range term uses encoded L1 colour distance",
                         matchCaption: "SAME PARAMETERS, DIFFERENT RANGE METRIC", kernelNote: "DIFFERENT RANGE METRIC"),
        noSigma("opencv", "median", "medianBlur(ksize:)", unit: .px, words: "WINDOW, NO σ", chip: "NO σ",
                spoken: "OpenCV's medianBlur takes a window size, not a sigma", source: SemanticsSources.opencv),
        noSigma("opencv", "morphology", "dilate / erode (kernel)", unit: .px, words: "WINDOW, NO σ", chip: "NO σ",
                spoken: "OpenCV's dilate and erode take a structuring element, not a sigma", source: SemanticsSources.opencv),
        noSigma("opencv", "nonlocal-means", "fastNlMeansDenoising(h:)", words: "FILTER STRENGTH", chip: "NO σ",
                spoken: "OpenCV's non-local means takes a filter strength h, not a sigma", source: SemanticsSources.opencv),
    ]

    static let imageMagick: [SemanticsControl] = [
        SemanticsControl(toolID: "imagemagick", blur: "gaussian-blur", controlName: "-blur 0x<sigma>", unit: .px, scalesWithDisplay: false,
                         mapping: linear(1), provenance: .reference, source: SemanticsSources.imageMagick, kernelMatch: .same,
                         lawDescription: "-blur 0xσ: σ = sigma; a bare -blur r keeps σ = 1"),
        unverified("imagemagick", "frosted-glass-noise", "-spread <amount>", subject: "ImageMagick spread amount",
                   source: SemanticsSources.imageMagick),
    ]

    // MARK: Engines (no σ)

    static let unity: [SemanticsControl] = [
        noSigma("unity", "bloom", "URP Bloom › Scatter", words: "BLEND WEIGHT", chip: "BLEND",
                spoken: "Unity's Scatter blends mip levels; it is not a sigma", source: SemanticsSources.unity),
        noSigma("unity", "pyramid-blur", "URP Bloom (Gaussian filter) › Max Iterations", words: "MIP LEVELS", chip: "LEVELS",
                spoken: "Unity's bloom sets how many mip levels are summed, not a sigma", source: SemanticsSources.unity),
        noSigma("unity", "kawase-blur", "URP Bloom (Kawase filter)", words: "PASS OFFSETS", chip: "PASSES",
                spoken: "Unity's Kawase bloom sets pass offsets, not a sigma", source: SemanticsSources.unity),
        noSigma("unity", "dual-kawase", "URP Bloom (Dual filter)", words: "PYRAMID LEVELS", chip: "LEVELS",
                spoken: "Unity's dual filter bloom sets pyramid levels, not a sigma", source: SemanticsSources.unity),
        noSigma("unity", "depth-of-field-coc", "URP Bokeh Depth of Field (f-number, focal length)", words: "PHYSICAL CAMERA", chip: "PHYS.",
                spoken: "Unity's bokeh depth of field takes physical camera settings, not a sigma", source: SemanticsSources.unity),
        noSigma("unity", "polygonal-bokeh", "URP Bokeh Depth of Field › Blade Count", words: "PHYSICAL CAMERA", chip: "PHYS.",
                spoken: "Unity's bokeh shape comes from the blade count, not a sigma", source: SemanticsSources.unity),
        noSigma("unity", "anamorphic-bokeh", "HDRP Bloom › Anamorphic", words: "PHYSICAL CAMERA", chip: "PHYS.",
                spoken: "Unity's anamorphic stretch follows the physical camera, not a sigma", source: SemanticsSources.unity),
        noSigma("unity", "cats-eye-swirl-bokeh", "Physical Camera › Barrel Clipping", words: "PHYSICAL CAMERA", chip: "PHYS.",
                spoken: "Unity's cat's-eye bokeh comes from barrel clipping, not a sigma", source: SemanticsSources.unity),
    ]

    static let unreal: [SemanticsControl] = [
        unverified("unreal", "bloom", "Bloom (Standard) › Size", unit: .percent, subject: "Unreal bloom size",
                   source: SemanticsSources.unreal, caption: "DIAMETER IN PERCENT OF SCREEN WIDTH"),
        unverified("unreal", "pyramid-blur", "Bloom (Standard) › Bloom levels at half to one sixty-fourth resolution", unit: .percent,
                   subject: "Unreal bloom level sizes", source: SemanticsSources.unreal, caption: "DIAMETER IN PERCENT OF SCREEN WIDTH"),
        noSigma("unreal", "fft-convolution", "Bloom (Convolution) › Convolution Kernel", words: "KERNEL IMAGE", chip: "IMAGE",
                spoken: "Unreal's convolution bloom takes a kernel image, not a sigma", source: SemanticsSources.unreal),
        noSigma("unreal", "depth-of-field-coc", "Cinematic Depth of Field (aperture, focal distance)", words: "PHYSICAL CAMERA", chip: "PHYS.",
                spoken: "Unreal's cinematic depth of field takes physical camera settings, not a sigma", source: SemanticsSources.unreal),
    ]

    // MARK: Drop-shadow conventions (P27)

    static let shadowConventions: [SemanticsControl] = [
        SemanticsControl(toolID: "css-box-shadow", blur: "drop-shadow", controlName: "box-shadow: 0 0 <blur>", unit: .cssPx,
                         scalesWithDisplay: true, mapping: linear(0.5), provenance: .reference, source: SemanticsSources.cssBoxShadow,
                         kernelMatch: .same, lawDescription: "σ = blur ÷ 2"),
        SemanticsControl(toolID: "css-drop-shadow", blur: "drop-shadow", controlName: "filter: drop-shadow(0 0 <σ>)", unit: .cssPx,
                         scalesWithDisplay: true, mapping: linear(1), provenance: .reference, source: SemanticsSources.cssDropShadow,
                         kernelMatch: .same, lawDescription: "σ = the third length"),
        SemanticsControl(toolID: "calayer-shadow", blur: "drop-shadow", controlName: "CALayer.shadowRadius", unit: .pt,
                         scalesWithDisplay: true, mapping: linear(0.5), provenance: .measured, source: SemanticsSources.caLayerStack,
                         measuredOn: researchMac, qualifiers: [.notThisDevice, .sourcesDisagree], kernelMatch: .unknown,
                         calibrationSubject: .caLayerShadow, lawDescription: "σ = r ÷ 2 (STACK reading)", caption: "SOURCES DISAGREE",
                         alternate: SemanticsAlternate(label: "CALAYER · CAL", law: .linear(slope: 0.9, offset: 0, offsetScales: true),
                                                       provenance: .measured, source: SemanticsSources.caLayerCal, measuredOn: researchMac,
                                                       lawDescription: "σ ≈ 0.9·r, the CGContext blur of 2r (CAL reading)")),
        SemanticsControl(toolID: "cgcontext-shadow", blur: "drop-shadow", controlName: "CGContext.setShadow(offset:blur:color:)", unit: .px,
                         scalesWithDisplay: false, mapping: linear(0.45), provenance: .measured, source: SemanticsSources.cgShadow,
                         measuredOn: researchMac, qualifiers: mac, kernelMatch: .sigmaOnly, calibrationSubject: .cgContextShadow,
                         lawDescription: "σ ≈ 0.45·blur (0.44–0.47), base-space px", kernelNote: "TENT-LIKE KERNEL"),
        SemanticsControl(toolID: "swiftui-shadow", blur: "drop-shadow", controlName: ".shadow(radius:)", unit: .pt, scalesWithDisplay: true,
                         mapping: linear(0.96), provenance: .measured, source: SemanticsSources.swiftUIShadowMac, measuredOn: researchMac,
                         qualifiers: [.notThisDevice, .offscreen], kernelMatch: .sigmaOnly, calibrationSubject: .swiftUIShadow,
                         lawDescription: "σ ≈ 0.96·r·scale", kernelNote: "BOX-CUBED-LIKE KERNEL"),
        SemanticsControl(toolID: "figma-shadow", blur: "drop-shadow", controlName: "Drop shadow › Blur", unit: .px, scalesWithDisplay: true,
                         mapping: linear(1 / (2 * 1.136)), provenance: .reference, source: SemanticsSources.bjango, qualifiers: [.weakSource],
                         kernelMatch: .unknown, lawDescription: "σ ≈ 0.44·value (1.136 × the matching CSS box-shadow blur)",
                         caption: "THIRD-PARTY MEASUREMENT"),
        SemanticsControl(toolID: "sketch-shadow", blur: "drop-shadow", controlName: "Shadow › Blur", unit: .pt, scalesWithDisplay: true,
                         mapping: linear(1 / (2 * 1.042)), provenance: .reference, source: SemanticsSources.bjango, qualifiers: [.weakSource],
                         kernelMatch: .unknown, lawDescription: "σ ≈ 0.48·value (1.042 × the matching CSS box-shadow blur)",
                         caption: "THIRD-PARTY MEASUREMENT"),
        SemanticsControl(toolID: "photoshop-shadow", blur: "drop-shadow", controlName: "Layer Style › Drop Shadow › Size", unit: .px,
                         scalesWithDisplay: false, mapping: linear(1 / (2 * 1.136)), provenance: .reference, source: SemanticsSources.bjango,
                         qualifiers: [.weakSource], kernelMatch: .unknown, lawDescription: "σ ≈ 0.44·size (factor 1.136 against CSS)",
                         caption: "THIRD-PARTY MEASUREMENT"),
    ]
}
