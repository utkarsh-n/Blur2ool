import Foundation
import BlurCore

// OWNER: APPLE-TWINS. What each Apple twin is, in words the UI can print beside it (floor 2 twins, Compare › Apple,
// Calibrate): the call the runner actually issues, its own parameter and unit, the parameter → kernel mapping with its
// badge and source, the API's edge policy and blend space. Mappings come from research CAL §4.0/§5.2–§5.4 (MEASURED on
// macOS 27.2, M1 Max) or are exact consequences of the API's definition (COMPUTED). A twin is always Apple's own code
// run in-process; nothing here describes Blur2ool's kernels, and the app never presents a twin as one of ours.

public enum AppleTwinFramework: String, Sendable, Codable, Hashable, CaseIterable {
    case coreImage = "Core Image"
    case metalPerformanceShaders = "Metal Performance Shaders"
    case vImage = "vImage (Accelerate)"
}

public struct AppleTwinFacts: Sendable, Codable, Hashable, Identifiable {
    public var id: CalibrationSubject { subject }
    public var subject: CalibrationSubject
    public var framework: AppleTwinFramework
    /// The call as code, with the runner's parameter in place of `r` ("CIFilter.gaussianBlur() · radius = r").
    public var call: String
    /// The API's own parameter and unit, as the runner receives it in `run(_:parameter:…)`.
    public var parameterName: String
    public var parameterUnit: String
    /// Parameter → kernel ("σ = inputRadius", "W = 2⌈r/2⌉ − 1").
    public var mapping: String
    public var mappingProvenance: Provenance
    /// What the API does past the image border, by default (the runner keeps that default unless asked).
    public var edgePolicy: String
    /// Which numbers the API averages.
    public var blendSpace: String
    /// Whether a full-resolution LTI kernel describes it (false for the zoom streak and the masked variable blur).
    public var isShiftInvariant: Bool
    public var source: SourceRef
    /// One line of caveats ("8-bit only", "law UNVERIFIED").
    public var note: String?
}

public enum AppleTwinCatalog {
    static let cal = "research live-calibration.md"

    /// Facts for every subject the runner supports (SwiftUI and shadow subjects are measured on the main actor by
    /// CALIBRATION's ImageRenderer path and have no entry here).
    public static let all: [AppleTwinFacts] = [
        AppleTwinFacts(subject: .ciGaussianBlur, framework: .coreImage, call: "CIFilter.gaussianBlur() · radius = r",
                       parameterName: "inputRadius", parameterUnit: "px", mapping: "σ = inputRadius",
                       mappingProvenance: .measured,
                       edgePolicy: "transparent: pixels past the extent are clear black, so borders darken and lose alpha",
                       blendSpace: "linear light (default CIContext working space)", isShiftInvariant: true,
                       source: SourceRef("\(cal) §5.2 and calibration-macos.json (MEASURED, macOS 27.2): σ/r 0.997–1.007 for r ≥ 2, 1.037 at r = 1"),
                       note: "kernel truncated more as σ grows (10⁻⁴ of peak at 4.2σ for σ 8, 3.6σ for σ 64)"),
        AppleTwinFacts(subject: .ciBoxBlur, framework: .coreImage, call: "CIFilter.boxBlur() · radius = r",
                       parameterName: "inputRadius", parameterUnit: "px", mapping: "square box, W = 2⌈r/2⌉ − 1 px",
                       mappingProvenance: .measured, edgePolicy: "transparent past the extent",
                       blendSpace: "linear light (default CIContext working space)", isShiftInvariant: true,
                       source: SourceRef("\(cal) §5.2 (MEASURED, macOS 27.2)"),
                       note: "inputRadius behaves like a diameter; r ≤ 2 returns the image unchanged"),
        AppleTwinFacts(subject: .ciDiscBlur, framework: .coreImage, call: "CIFilter.discBlur() · radius = r",
                       parameterName: "inputRadius", parameterUnit: "px", mapping: "uniform disc of radius r, σ = r/2",
                       mappingProvenance: .measured, edgePolicy: "transparent past the extent",
                       blendSpace: "linear light (default CIContext working space)", isShiftInvariant: true,
                       source: SourceRef("\(cal) §5.2 (MEASURED, macOS 27.2): σ/r 0.500–0.502 for r ≥ 5"), note: nil),
        AppleTwinFacts(subject: .ciBokehBlur, framework: .coreImage,
                       call: "CIFilter.bokehBlur() · radius = r (ringAmount 0, ringSize 0.1, softness 1)",
                       parameterName: "inputRadius", parameterUnit: "px", mapping: "at its defaults identical to CIDiscBlur",
                       mappingProvenance: .measured, edgePolicy: "transparent past the extent",
                       blendSpace: "linear light (default CIContext working space)", isShiftInvariant: true,
                       source: SourceRef("\(cal) §5.2 (MEASURED, macOS 27.2): max |difference| 0 at r 4, 16, 40"),
                       note: "the runtime attributes list softness default 1 but slider maximum 0.4"),
        AppleTwinFacts(subject: .ciMotionBlur, framework: .coreImage, call: "CIFilter.motionBlur() · radius = r · angle = θ",
                       parameterName: "inputRadius", parameterUnit: "px",
                       mapping: "1-px line with Gaussian weights, σ = r along inputAngle, two-sided",
                       mappingProvenance: .measured, edgePolicy: "transparent past the extent",
                       blendSpace: "linear light (default CIContext working space)", isShiftInvariant: true,
                       source: SourceRef("\(cal) §5.2 (MEASURED, macOS 27.2): kurtosis −0.03 to −0.11"),
                       note: "not the uniform one-sided smear a moving camera makes"),
        AppleTwinFacts(subject: .ciZoomBlur, framework: .coreImage, call: "CIFilter.zoomBlur() · amount = a · center = window centre",
                       parameterName: "inputAmount", parameterUnit: "px",
                       mapping: "outward streak ∝ distance d: ≈ 0.079·d at amount 4, ≈ 0.357·d at amount 16",
                       mappingProvenance: .measured, edgePolicy: "transparent past the extent",
                       blendSpace: "linear light (default CIContext working space)", isShiftInvariant: false,
                       source: SourceRef("\(cal) §5.2 (MEASURED, macOS 27.2, d = 100–300 px)"),
                       note: "amount → length law UNVERIFIED (not linear in amount)"),
        AppleTwinFacts(subject: .ciMaskedVariableBlur, framework: .coreImage,
                       call: "CIFilter.maskedVariableBlur() · radius = r · mask = ramp",
                       parameterName: "inputRadius", parameterUnit: "px",
                       mapping: "the mask's green channel 0…1 takes the blur from none to the full radius r",
                       mappingProvenance: .reference, edgePolicy: "transparent past the extent",
                       blendSpace: "linear light (default CIContext working space)", isShiftInvariant: false,
                       source: SourceRef("Apple, CoreImage CIFilterBuiltins.h (iOS 27.0 / macOS 27.0 SDK), protocol CIMaskedVariableBlur, property mask"),
                       note: "not in CAL. MEASURED on the Mac by APPLETWINS_CoreImage (progress-APPLE-TWINS.md): with a white mask σ ≈ 1.14·r and excess kurtosis ≈ +1.0, heavier-tailed than a Gaussian; how it is built is INFERRED"),
        AppleTwinFacts(subject: .mpsGaussianBlur, framework: .metalPerformanceShaders, call: "MPSImageGaussianBlur(device:sigma: r)",
                       parameterName: "sigma", parameterUnit: "px", mapping: "σ = sigma",
                       mappingProvenance: .measured, edgePolicy: "MPSImageEdgeMode.zero (default): transparent",
                       blendSpace: "the numbers stored in the texture (no colour management)", isShiftInvariant: true,
                       source: SourceRef("\(cal) §5.3 (MEASURED, macOS 27.2): σ/sigma 0.993–0.998 for σ ≥ 4"),
                       note: "Apple: \"approximate Gaussian … ~10 bits of precision or less\""),
        AppleTwinFacts(subject: .mpsBox, framework: .metalPerformanceShaders, call: "MPSImageBox(device:kernelWidth: 2r + 1, kernelHeight: 2r + 1)",
                       parameterName: "half-width r (kernelWidth = 2r + 1)", parameterUnit: "px",
                       mapping: "exact square box of 2r + 1 taps, σ = √(((2r + 1)² − 1)/12)",
                       mappingProvenance: .computed, edgePolicy: "MPSImageEdgeMode.zero (default): transparent",
                       blendSpace: "the numbers stored in the texture (no colour management)", isShiftInvariant: true,
                       source: SourceRef("\(cal) §5.3 (MEASURED to 4 decimals, macOS 27.2)"), note: nil),
        AppleTwinFacts(subject: .mpsTent, framework: .metalPerformanceShaders, call: "MPSImageTent(device:kernelWidth: 2r + 1, kernelHeight: 2r + 1)",
                       parameterName: "half-width r (kernelWidth = 2r + 1)", parameterUnit: "px",
                       mapping: "separable tent = two boxes of r + 1 taps, σ = √(((r + 1)² − 1)/6)",
                       mappingProvenance: .computed, edgePolicy: "MPSImageEdgeMode.zero (default): transparent",
                       blendSpace: "the numbers stored in the texture (no colour management)", isShiftInvariant: true,
                       source: SourceRef("\(cal) §5.3 (MEASURED to 4 decimals, macOS 27.2)"), note: nil),
        AppleTwinFacts(subject: .vImageBox, framework: .vImage,
                       call: "vImageBoxConvolve_ARGB8888(…, kernel_height: 2r + 1, kernel_width: 2r + 1, …, kvImageEdgeExtend)",
                       parameterName: "half-width r (kernel 2r + 1)", parameterUnit: "px",
                       mapping: "exact square box of 2r + 1 taps on 8-bit values, σ = √(((2r + 1)² − 1)/12)",
                       mappingProvenance: .computed,
                       edgePolicy: "no default: the caller passes kvImageEdgeExtend (clamp), kvImageTruncateKernel or kvImageBackgroundColorFill",
                       blendSpace: "the 8-bit numbers in the buffer (the twin stores sRGB-encoded 8-bit, as 8-bit images do)",
                       isShiftInvariant: true, source: SourceRef("\(cal) §5.4 (MEASURED, macOS 27.2)"),
                       note: "8-bit only (Planar8 and ARGB8888): values above 1.0 clip before the blur"),
        AppleTwinFacts(subject: .vImageTent, framework: .vImage,
                       call: "vImageTentConvolve_ARGB8888(…, kernel_height: 2r + 1, kernel_width: 2r + 1, …, kvImageEdgeExtend)",
                       parameterName: "half-width r (kernel 2r + 1)", parameterUnit: "px",
                       mapping: "separable tent of 2r + 1 taps on 8-bit values, σ = √(((r + 1)² − 1)/6)",
                       mappingProvenance: .computed,
                       edgePolicy: "no default: the caller passes kvImageEdgeExtend (clamp), kvImageTruncateKernel or kvImageBackgroundColorFill",
                       blendSpace: "the 8-bit numbers in the buffer (the twin stores sRGB-encoded 8-bit, as 8-bit images do)",
                       isShiftInvariant: true, source: SourceRef("\(cal) §5.4 (MEASURED, macOS 27.2)"),
                       note: "8-bit only (Planar8 and ARGB8888): values above 1.0 clip before the blur"),
    ]

    public static func facts(_ subject: CalibrationSubject) -> AppleTwinFacts? { all.first { $0.subject == subject } }

    /// The kernel width the box/tent twins build from the half-width parameter (2·round(r) + 1, at least 1).
    public static func kernelWidth(halfWidth r: Double) -> Int { 2 * Swift.max(0, Int(r.rounded())) + 1 }

    /// CIBoxBlur's square box width for inputRadius r: W = 2⌈r/2⌉ − 1, at least 1 (CAL §5.2, MEASURED).
    public static func coreImageBoxWidth(radius r: Double) -> Int { Swift.max(1, 2 * Int((r / 2).rounded(.up)) - 1) }

    /// The σ (px) the documented or measured mapping predicts for `parameter`, or nil where no single σ exists
    /// (zoom streaks, masked variable blur). Provenance = the facts' `mappingProvenance`.
    public static func expectedSigma(_ subject: CalibrationSubject, parameter p: Double) -> Double? {
        switch subject {
        case .ciGaussianBlur, .ciMotionBlur, .mpsGaussianBlur: return p
        case .ciBoxBlur: return AppleTwinAnalysis.boxSigma(width: coreImageBoxWidth(radius: p))
        case .ciDiscBlur, .ciBokehBlur: return p / 2
        case .mpsBox, .vImageBox: return AppleTwinAnalysis.boxSigma(width: kernelWidth(halfWidth: p))
        case .mpsTent, .vImageTent: return AppleTwinAnalysis.tentSigma(halfWidth: Swift.max(0, Int(p.rounded())))
        default: return nil
        }
    }
}
