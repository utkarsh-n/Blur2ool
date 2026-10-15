import Foundation

// OWNER: CALIBRATION (ARCHITECTURE §5.13; SPEC §4.8, §13). What the Calibrate sheet and the measuring half share, kept
// pure so it is unit-tested on the Mac: each subject's parameter (label, unit, range, default), the edge canvas geometry
// (MeasurePSF's, so the phone renders exactly what the research Mac rendered), the basic set and the sweep, and the
// macOS 27.2 reference numbers of research/live-calibration.md (CAL) that a phone measurement is shown beside.

// MARK: - Subjects

public extension CalibrationSubject {
    /// The API's parameter name, ALL CAPS (the Stepper label).
    var parameterLabel: String {
        switch self {
        case .swiftUIBlur, .swiftUIShadow, .ciGaussianBlur, .ciBoxBlur, .ciDiscBlur, .ciBokehBlur, .ciMotionBlur,
             .ciMaskedVariableBlur: "RADIUS"
        case .caLayerShadow: "SHADOW RADIUS"
        case .cgContextShadow: "BLUR"
        case .ciZoomBlur: "AMOUNT"
        case .mpsGaussianBlur: "SIGMA"
        case .mpsBox, .mpsTent, .vImageBox, .vImageTent: "KERNEL RADIUS"
        }
    }
    /// The symbol in σ / (r·scale).
    var parameterSymbol: String {
        switch self {
        case .cgContextShadow: "b"
        case .mpsGaussianBlur: "σ"
        default: "r"
        }
    }
    /// Points (scaled by the display scale) or device pixels.
    var parameterIsPoints: Bool { [.swiftUIBlur, .swiftUIShadow, .caLayerShadow].contains(self) }
    var parameterUnit: String { parameterIsPoints ? "pt" : "px" }
    var parameterSpokenUnit: String { parameterIsPoints ? "points" : "pixels" }
    /// The Stepper's range and step (the API's own unit).
    var parameterRange: ClosedRange<Double> {
        switch self {
        case .swiftUIBlur, .swiftUIShadow, .caLayerShadow: 0.5...96
        case .cgContextShadow: 1...128
        case .mpsBox, .mpsTent, .vImageBox, .vImageTent: 1...64
        default: 0.5...100
        }
    }
    var parameterStep: Double { [.mpsBox, .mpsTent, .vImageBox, .vImageTent].contains(self) ? 1 : 0.5 }
    var parameterDecimals: Int { parameterStep >= 1 ? 0 : 1 }
    /// The Calibrate sheet's starting value (the API's documented default where one exists; CAL §9).
    var defaultParameter: Double {
        switch self {
        case .swiftUIBlur: 2
        case .swiftUIShadow: 4
        case .caLayerShadow: 3
        case .cgContextShadow: 6
        case .ciGaussianBlur, .ciBoxBlur: 10
        case .ciDiscBlur: 8
        case .ciBokehBlur, .ciMotionBlur, .ciZoomBlur: 20
        case .ciMaskedVariableBlur: 5
        case .mpsGaussianBlur, .mpsBox, .mpsTent, .vImageBox, .vImageTent: 4
        }
    }
    /// SwiftUI and Core Animation results are offscreen renders of an on-screen API (SPEC §12.2 item 9): OFFSCREEN.
    var isOffscreenRenderOfOnScreenAPI: Bool { [.swiftUIBlur, .swiftUIShadow, .caLayerShadow].contains(self) }
    /// Shadows blur an alpha mask: the edge is read from alpha, and colour space does not apply (CAL §5.5).
    var isShadow: Bool { [.swiftUIShadow, .caLayerShadow, .cgContextShadow].contains(self) }
    /// Subjects with a single σ along the edge normal. Zoom blur is space-variant by design and the masked variable
    /// blur depends on its mask: an edge fit is still shown, but the law has no meaning (CAL §5.2).
    var hasSingleSigma: Bool { ![.ciZoomBlur, .ciMaskedVariableBlur].contains(self) }
    /// Render paths offered in the PATH menu (SPEC §13.3: SwiftUI only).
    var paths: [CalibrationPath] {
        switch self {
        case .swiftUIBlur, .swiftUIShadow: [.imageRendererCGImage, .imageRendererRenderInto, .drawHierarchyOnScreen]
        case .caLayerShadow: [.coreAnimationRenderInContext]
        case .cgContextShadow: [.coreGraphics]
        case .ciGaussianBlur, .ciBoxBlur, .ciDiscBlur, .ciBokehBlur, .ciMotionBlur, .ciZoomBlur, .ciMaskedVariableBlur: [.coreImageContext]
        case .mpsGaussianBlur, .mpsBox, .mpsTent: [.metalPerformanceShaders]
        case .vImageBox, .vImageTent: [.vImage]
        }
    }
    var defaultPath: CalibrationPath { paths[0] }
}

public extension CalibrationPath {
    var title: String {
        switch self {
        case .imageRendererCGImage: "ImageRenderer.cgImage"
        case .imageRendererRenderInto: "ImageRenderer.render(into:)"
        case .drawHierarchyOnScreen: "drawHierarchy (experiment)"
        case .coreImageContext: "CIContext"
        case .metalPerformanceShaders: "Metal Performance Shaders"
        case .vImage: "vImage"
        case .coreGraphics: "CGContext (offscreen)"
        case .coreAnimationRenderInContext: "CALayer.render(in:)"
        }
    }
}

public extension CalibrationColourMode {
    var title: String {
        switch self {
        case .nonLinear: "Non-linear (sRGB)"
        case .linear: "Linear"
        case .extendedLinear: "Extended linear"
        }
    }
    /// The space the blur sums in, which is the space the edge is read back in (CAL §3.2).
    var readsEncoded: Bool { self == .nonLinear }
}

// MARK: - Canvas (MeasurePSF's geometry, in points)

/// The black | white step canvas of Tools/calibrate/MeasurePSF.swift: an analysis half-window `reach` of 6·p + 8 pt (the
/// plateaus are reached for σ ≤ ≈ 1.2·p), plus a `margin` of 4·p + 8 pt so a blur that fades to transparent at the canvas
/// border (opaque: false) never reaches the 16 centre rows or the analysis window.
public struct CalibrationCanvas: Sendable, Hashable {
    public var reach: Double
    public var margin: Double
    public var width: Double
    public var height: Double
    public var scale: Double

    public init(parameter p: Double, scale: Double) {
        reach = Swift.max(8, (6 * p).rounded(.up) + 8)
        margin = Swift.max(8, (4 * p).rounded(.up) + 8)
        width = 2 * (reach + margin) + 4
        height = Swift.max(32, 2 * margin + 16)
        self.scale = scale
    }
    /// The step's x in points for a whole-device-pixel phase (CAL §3.3): reach + margin + 2 + phase / scale.
    public func edgeX(phase: Int) -> Double { reach + margin + 2 + Double(phase) / scale }
    /// Device pixels per render.
    public var pixels: Double { (width * scale).rounded(.up) * (height * scale).rounded(.up) }
    /// The analysis half-window in device pixels.
    public var windowPx: Double { reach * scale }
    /// The 45° twin: wide enough that the diagonal ESF (√2 longer along a row) keeps its plateaus.
    public var diagonalWidth: Double { 2 * ((reach * 2.0.squareRoot()).rounded(.up) + margin) + 4 }
}

// MARK: - Plans

public enum CalibrationPlan {
    /// SPEC §13.2: radii 0.5, 1, 2, 3, 4, 8 pt × 4 phases, `.nonLinear`, at the display scale.
    public static let basicSetRadii: [Double] = [0.5, 1, 2, 3, 4, 8]
    public static let phases = 4
    /// CAL §4.18's 34 radii (pt for SwiftUI): fine below the ≈ 5-px switch, then octaves to 96.
    public static let swiftUISweepRadii: [Double] = [0.25, 0.5, 0.75, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5, 5.5, 6, 6.5, 7, 7.5, 8,
                                                     9, 10, 11, 12, 14, 16, 20, 24, 28, 32, 40, 48, 56, 64, 80, 96]
    /// CAL §4.18's shadow parameters.
    public static let shadowSweepParameters: [Double] = [0.5, 1, 1.5, 2, 3, 4, 5, 6, 8, 10, 12, 16, 20, 24, 32, 48, 64]
    public static let pixelSweepParameters: [Double] = [1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64]

    public static func sweepParameters(_ subject: CalibrationSubject) -> [Double] {
        switch subject {
        case .swiftUIBlur: swiftUISweepRadii
        case .swiftUIShadow, .caLayerShadow, .cgContextShadow: shadowSweepParameters
        default: pixelSweepParameters
        }
    }
    /// The basic set's requests at this display scale.
    public static func basicSet(displayScale: Double) -> [CalibrationRequest] {
        basicSetRadii.map { CalibrationRequest(subject: .swiftUIBlur, path: .imageRendererCGImage, parameter: $0,
                                               displayScale: displayScale, colourMode: .nonLinear, phases: phases, opaque: false) }
    }
    /// Renders one measurement needs: one per phase, plus the 45° twin for edge-blur subjects.
    public static func renders(_ request: CalibrationRequest) -> Int {
        Swift.max(1, request.phases) + (request.subject.isShadow ? 0 : 1)
    }
}

// MARK: - macOS 27.2 reference (CAL §4, MEASURED on the research Mac, offscreen, scale 1)

public struct CalibrationReferencePoint: Sendable, Hashable {
    /// The parameter in device pixels (the Mac rendered at scale 1, so points = pixels).
    public var parameterPx: Double
    public var sigmaPx: Double
    public var kurtosis: Double?
    public var centreSpreadPx: Double?
    public var ratio: Double { parameterPx > 0 ? sigmaPx / parameterPx : 0 }
}

public enum CalibrationMacReference {
    /// The research Mac (CAL §2).
    public static let device = DeviceStamp(deviceModel: "Mac (Apple M1 Max)", gpuName: "Apple M1 Max", gpuFamily: "Apple7",
                                           osVersion: "macOS 27.2", osBuild: "26B5101f", isSimulator: false,
                                           date: Date(timeIntervalSince1970: 1_791_892_800), thermal: .nominal, lowPowerMode: false)
    public static let label = "MACOS 27.2 (M1 MAX)"

    /// CAL §4.18, SwiftUI .blur, ImageRenderer.cgImage, .nonLinear, 4 phases: (r, σ, kurtosis, centre spread).
    public static let swiftUICGImage: [CalibrationReferencePoint] = zip4(
        CalibrationPlan.swiftUISweepRadii,
        [0.000, 0.460, 0.746, 0.994, 1.482, 2.002, 2.475, 2.845, 3.130, 3.940, 4.302, 4.626, 4.988, 5.439, 5.905, 6.339, 6.818,
         7.245, 8.169, 9.059, 9.852, 10.830, 12.622, 14.417, 18.049, 21.711, 25.345, 28.982, 36.215, 43.266, 50.503, 57.685,
         72.205, 86.590],
        [0.00, 1.72, 0.01, -0.06, -0.16, 0.01, -0.14, -0.36, -0.48, -0.14, -0.34, -0.41, -0.50, -0.48, -0.49, -0.49, -0.47,
         -0.50, -0.48, -0.49, -0.47, -0.45, -0.44, -0.45, -0.45, -0.46, -0.46, -0.46, -0.48, -0.45, -0.45, -0.45, -0.46, -0.45],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.15, 0.43, 1.00, 1.00, 1.00, 1.00, 1.40, 1.09, 0.12, 0.44, 1.00, 1.00, 1.07,
         0.49, 1.00, 1.00, 1.14, 0.36, 1.00, 1.00, 1.08, 1.15])
    /// CAL §4.18, the same view through ImageRenderer.render(rasterizationScale:) into a CGContext (≈ 0.98·r).
    public static let swiftUIRenderInto: [CalibrationReferencePoint] = zip4(
        CalibrationPlan.swiftUISweepRadii,
        [0.029, 0.465, 0.749, 0.998, 1.498, 1.990, 2.468, 2.977, 3.454, 3.962, 4.441, 4.913, 5.446, 5.907, 6.418, 6.891, 7.391,
         7.874, 8.866, 9.852, 10.817, 11.789, 13.751, 15.718, 19.646, 23.510, 27.425, 31.341, 39.177, 46.970, 54.800, 62.625,
         78.286, 93.947],
        [1211.26, 1.83, -0.02, -0.05, -0.03, -0.09, -0.16, -0.12, -0.17, -0.13, -0.17, -0.20, -0.19, -0.19, -0.18, -0.18, -0.19,
         -0.19, -0.19, -0.18, -0.21, -0.21, -0.21, -0.20, -0.21, -0.23, -0.23, -0.23, -0.23, -0.24, -0.24, -0.24, -0.24, -0.24],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.14, 0.43, 1.00, 1.00, 1.00, 1.00, 1.00, 1.10, 0.14, 0.43, 1.00, 1.00, 1.09,
         0.43, 1.00, 1.00, 1.09, 0.43, 1.00, 1.00, 1.10, 1.28])
    /// CAL §4.18 shadow table: CGContext.setShadow(blur:), CALayer.shadowRadius via render(in:), SwiftUI .shadow(radius:).
    public static let cgShadow = pairs(CalibrationPlan.shadowSweepParameters,
        [0.460, 0.460, 0.962, 0.962, 1.406, 1.851, 2.299, 2.742, 3.628, 4.501, 5.389, 7.148, 8.909, 10.683, 14.086, 21.135, 28.221])
    public static let caLayerShadow = pairs(CalibrationPlan.shadowSweepParameters,
        [0.460, 0.962, 1.406, 1.851, 2.742, 3.628, 4.501, 5.389, 7.148, 8.909, 10.683, 14.086, 17.618, 21.135, 28.221, 41.829, 56.486])
    public static let swiftUIShadow = pairs(CalibrationPlan.shadowSweepParameters,
        [0.567, 1.002, 1.470, 1.941, 2.895, 3.874, 4.800, 5.760, 7.712, 9.624, 11.541, 15.366, 19.265, 23.092, 30.733, 46.100, 61.515])

    /// The measured Mac points for a subject and path (CAL §4.6–§4.18; the pixel-native APIs at parameters 1, 4, 16).
    public static func points(_ subject: CalibrationSubject, path: CalibrationPath) -> [CalibrationReferencePoint] {
        switch subject {
        case .swiftUIBlur: path == .imageRendererRenderInto ? swiftUIRenderInto : swiftUICGImage
        case .swiftUIShadow: swiftUIShadow
        case .caLayerShadow: caLayerShadow
        case .cgContextShadow: cgShadow
        case .ciGaussianBlur: pairs([1, 4, 16], [1.037, 4.000, 15.943])
        case .ciBoxBlur: pairs([1, 4, 16], [0.000, 0.759, 4.322])
        case .ciDiscBlur, .ciBokehBlur: pairs([1, 4, 16], [0.629, 2.020, 8.004])
        case .ciMotionBlur: pairs([1, 4, 16], [1.040, 3.904, 15.883])
        case .mpsGaussianBlur: pairs([1, 4, 16], [1.037, 3.991, 15.888])
        case .mpsBox: pairs([1, 4, 16], [0.816, 2.582, 9.522])
        case .mpsTent: pairs([1, 4, 16], [0.707, 2.000, 6.928])
        case .vImageBox: pairs([1, 4, 16], [0.816, 2.580, 9.521])
        case .vImageTent: pairs([1, 4, 16], [0.708, 2.000, 6.947])
        case .ciZoomBlur, .ciMaskedVariableBlur: []
        }
    }

    /// The Mac point nearest (in log parameter) to `parameterPx`; nil when the subject has none.
    public static func nearest(_ subject: CalibrationSubject, path: CalibrationPath, parameterPx: Double) -> CalibrationReferencePoint? {
        guard parameterPx > 0 else { return nil }
        return points(subject, path: path).filter { $0.sigmaPx > 0 }
            .min { abs(log($0.parameterPx / parameterPx)) < abs(log($1.parameterPx / parameterPx)) }
    }

    /// The Mac's regime switch for SwiftUI .blur (CAL §4.18): between 5 px (spread 0.00) and 5.5 px (spread 0.15).
    public static let swiftUISwitchPx = 5.25

    public static let source = SourceRef("research/live-calibration.md §4 (MEASURED offscreen, macOS 27.2, M1 Max, scale 1)")

    private static func zip4(_ r: [Double], _ s: [Double], _ k: [Double], _ c: [Double]) -> [CalibrationReferencePoint] {
        r.indices.map { CalibrationReferencePoint(parameterPx: r[$0], sigmaPx: s[$0], kurtosis: k[$0], centreSpreadPx: c[$0]) }
    }
    private static func pairs(_ r: [Double], _ s: [Double]) -> [CalibrationReferencePoint] {
        r.indices.map { CalibrationReferencePoint(parameterPx: r[$0], sigmaPx: s[$0], kurtosis: nil, centreSpreadPx: nil) }
    }
}

// MARK: - What each API's parameter predicts before this phone measures it

public struct CalibrationPrediction: Sendable, Hashable {
    public var sigmaPx: Double
    public var provenance: Provenance
    /// The law in words ("MACOS LAW 0.90·r·scale").
    public var lawText: String
    public var source: SourceRef?
}

public enum CalibrationLaws {
    /// The σ (device px) the research reading predicts for `parameter`, with its provenance: Mac-measured laws applied to
    /// this phone are INFERRED until it measures; an exact documented kernel is COMPUTED. nil when no single σ exists.
    public static func prediction(_ subject: CalibrationSubject, parameter p: Double, displayScale s: Double) -> CalibrationPrediction? {
        let px = subject.parameterIsPoints ? p * s : p
        let mac = SourceRef("research/live-calibration.md §4.0, §6 (MEASURED macOS 27.2, M1 Max)")
        func inferred(_ sigma: Double, _ law: String) -> CalibrationPrediction {
            CalibrationPrediction(sigmaPx: sigma, provenance: .inferred, lawText: law, source: mac)
        }
        switch subject {
        case .swiftUIBlur:
            return inferred(px <= 5 ? px : 0.90 * px, px <= 5 ? "MACOS LAW r·scale BELOW THE SWITCH" : "MACOS LAW 0.90·r·scale")
        case .swiftUIShadow: return inferred(0.96 * px, "MACOS LAW 0.96·r·scale")
        case .caLayerShadow: return inferred(0.90 * px, "MACOS LAW ≈ 0.90·r·scale (CG BLUR 2r)")
        case .cgContextShadow: return inferred(0.45 * px, "MACOS LAW ≈ 0.45·b")
        case .ciGaussianBlur, .ciMotionBlur: return inferred(px, "MACOS LAW σ = r")
        case .ciBoxBlur:
            let w = 2 * (p / 2).rounded(.up) - 1
            return inferred(((w * w - 1) / 12).squareRoot(), "MACOS LAW WIDTH 2⌈r/2⌉ − 1")
        case .ciDiscBlur, .ciBokehBlur: return inferred(px / 2, "MACOS LAW σ = r/2 (DISC)")
        case .mpsGaussianBlur:
            return CalibrationPrediction(sigmaPx: px, provenance: .reference, lawText: "DOCUMENTED σ = SIGMA",
                                         source: SourceRef("Apple, MPSImageGaussianBlur(device:sigma:)",
                                                           url: "https://developer.apple.com/documentation/metalperformanceshaders/mpsimagegaussianblur"))
        case .mpsBox, .vImageBox:
            let w = 2 * p.rounded() + 1
            return CalibrationPrediction(sigmaPx: ((w * w - 1) / 12).squareRoot(), provenance: .computed,
                                         lawText: "BOX OF WIDTH 2r + 1", source: nil)
        case .mpsTent, .vImageTent:
            let r = p.rounded()
            return CalibrationPrediction(sigmaPx: (((r + 1) * (r + 1) - 1) / 6).squareRoot(), provenance: .computed,
                                         lawText: "TENT OF WIDTH 2r + 1", source: nil)
        case .ciZoomBlur, .ciMaskedVariableBlur: return nil
        }
    }
}
