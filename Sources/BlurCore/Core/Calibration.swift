import Foundation

// FROZEN — ARCHITECTURE.md §5.13. Calibration API, the pure half (SPEC §13): requests, edge samples, fits, laws.
// The app renders and reads back (App/Calibration, @MainActor, ImageRenderer); BlurCore fits (CALIBRATION's PSFFitter).

public enum CalibrationSubject: String, Sendable, Codable, Hashable, CaseIterable {
    case swiftUIBlur, swiftUIShadow, caLayerShadow, cgContextShadow,
         ciGaussianBlur, ciBoxBlur, ciDiscBlur, ciBokehBlur, ciMotionBlur, ciZoomBlur, ciMaskedVariableBlur,
         mpsGaussianBlur, mpsBox, mpsTent, vImageBox, vImageTent
    /// Calibrate's API menu title ("SwiftUI .blur(radius:)").
    public var title: String {
        switch self {
        case .swiftUIBlur: "SwiftUI .blur(radius:)"
        case .swiftUIShadow: "SwiftUI .shadow(radius:)"
        case .caLayerShadow: "CALayer.shadowRadius"
        case .cgContextShadow: "CGContext.setShadow"
        case .ciGaussianBlur: "CIGaussianBlur"
        case .ciBoxBlur: "CIBoxBlur"
        case .ciDiscBlur: "CIDiscBlur"
        case .ciBokehBlur: "CIBokehBlur"
        case .ciMotionBlur: "CIMotionBlur"
        case .ciZoomBlur: "CIZoomBlur"
        case .ciMaskedVariableBlur: "CIMaskedVariableBlur"
        case .mpsGaussianBlur: "MPSImageGaussianBlur"
        case .mpsBox: "MPSImageBox"
        case .mpsTent: "MPSImageTent"
        case .vImageBox: "vImage box"
        case .vImageTent: "vImage tent"
        }
    }
    /// Subjects measured through SwiftUI/Core Animation on the main actor (ImageRenderer, render(in:), CG).
    public var isMainActorRendered: Bool { [.swiftUIBlur, .swiftUIShadow, .caLayerShadow, .cgContextShadow].contains(self) }
}

public enum CalibrationPath: String, Sendable, Codable, Hashable, CaseIterable {
    /// ImageRenderer.cgImage — default for SwiftUI subjects (CAL §5.1 item 7).
    case imageRendererCGImage
    /// ImageRenderer.render(rasterizationScale:renderer:) — a different blur (σ ≈ 0.98·r on the Mac).
    case imageRendererRenderInto
    /// UIView.drawHierarchy(afterScreenUpdates: true) — EXPERIMENTAL; results labelled as such.
    case drawHierarchyOnScreen
    case coreImageContext, metalPerformanceShaders, vImage, coreGraphics, coreAnimationRenderInContext
}

public enum CalibrationColourMode: String, Sendable, Codable, Hashable, CaseIterable { case nonLinear, linear, extendedLinear }

public struct CalibrationRequest: Sendable, Codable, Hashable {
    public var subject: CalibrationSubject
    public var path: CalibrationPath
    /// The API's own parameter in its own unit (pt for SwiftUI and CALayer, px for Core Image/MPS/vImage).
    public var parameter: Double
    public var displayScale: Double
    public var colourMode: CalibrationColourMode
    /// Whole-device-pixel edge phases; > 1 detects resampling (CAL §3.3).
    public var phases: Int
    public var opaque: Bool?
    public init(subject: CalibrationSubject, path: CalibrationPath, parameter: Double, displayScale: Double,
                colourMode: CalibrationColourMode = .nonLinear, phases: Int = 4, opaque: Bool? = nil) {
        self.subject = subject; self.path = path; self.parameter = parameter; self.displayScale = displayScale
        self.colourMode = colourMode; self.phases = phases; self.opaque = opaque
    }
}

/// Edge-spread samples read back from one rendered edge, in the blur's working space.
public struct EdgeSamples: Sendable, Codable, Hashable {
    /// One value per device pixel along the edge normal (normalised so the dark plateau is 0 and the bright one 1).
    public var esf: [Double]
    /// Position of the unblurred edge in device pixels from esf[0].
    public var edgePosition: Double
    public var phase: Int
    /// sRGB-encoded value at the edge centre (0.5 gamma-space blend, ≈ 0.735 linear-light blend).
    public var encodedMidpoint: Double?
    /// The same edge at 45° (separable vs isotropic), when rendered.
    public var esf45: [Double]?
    public init(esf: [Double], edgePosition: Double, phase: Int, encodedMidpoint: Double?, esf45: [Double]? = nil) {
        self.esf = esf; self.edgePosition = edgePosition; self.phase = phase; self.encodedMidpoint = encodedMidpoint; self.esf45 = esf45
    }
}

public enum PSFModel: String, Sendable, Codable, Hashable, CaseIterable {
    case gaussian
    /// Gaussian hard-truncated at ±2.3σ (SDK §4's reading of SwiftUI's large-radius kernel).
    case truncatedGaussian
    /// Three equal boxes (CAL §5.1's reading).
    case boxCubed
}

public struct ModelFit: Sendable, Codable, Hashable {
    public var model: PSFModel
    public var sigmaPx: Double
    /// RMS residual in % of the step.
    public var rmsResidualPercent: Double
    public init(model: PSFModel, sigmaPx: Double, rmsResidualPercent: Double) {
        self.model = model; self.sigmaPx = sigmaPx; self.rmsResidualPercent = rmsResidualPercent
    }
}

/// The fit of one measured edge set (CAL §3.3 estimators, ported from Tools/calibrate/MeasurePSF.swift).
public struct PSFFit: Sendable, Codable, Hashable {
    /// Moment σ of the LSF in device pixels.
    public var sigmaPx: Double
    /// σ / (parameter · displayScale): the law (SwiftUI ≈ 1.0 small, ≈ 0.90 large on macOS 27.2).
    public var sigmaPerParameterPixel: Double
    /// Least-squares erf σ as a sampled-equivalent σ.
    public var lsqSigmaPx: Double
    public var excessKurtosis: Double
    public var excessKurtosis45: Double?
    /// Visible extent at 1/255 (device px).
    public var extentPx: Double
    /// Support at 10⁻³ of the LSF peak (device px).
    public var supportPx: Double
    /// Spread of the edge centre over phases (the resampling detector; 0 = shift-invariant).
    public var centreSpreadPx: Double
    public var sigmaSpreadPercent: Double
    public var encodedMidpoint: Double?
    /// "gaussian", "box³-like", "tent-like", "box", "disc": an interpretation, labelled INFERRED on screen.
    public var shapeName: String
    /// Model competition (SPEC §13.3), sorted by residual (lowest first; the app marks it ✓).
    public var models: [ModelFit]
    /// The fitted line-spread function, for plotting beside the theory.
    public var lsf: [Double]
    public init(sigmaPx: Double, sigmaPerParameterPixel: Double, lsqSigmaPx: Double, excessKurtosis: Double,
                excessKurtosis45: Double?, extentPx: Double, supportPx: Double, centreSpreadPx: Double,
                sigmaSpreadPercent: Double, encodedMidpoint: Double?, shapeName: String, models: [ModelFit], lsf: [Double]) {
        self.sigmaPx = sigmaPx; self.sigmaPerParameterPixel = sigmaPerParameterPixel; self.lsqSigmaPx = lsqSigmaPx
        self.excessKurtosis = excessKurtosis; self.excessKurtosis45 = excessKurtosis45; self.extentPx = extentPx
        self.supportPx = supportPx; self.centreSpreadPx = centreSpreadPx; self.sigmaSpreadPercent = sigmaSpreadPercent
        self.encodedMidpoint = encodedMidpoint; self.shapeName = shapeName; self.models = models; self.lsf = lsf
    }
}

public struct CalibrationResult: Sendable, Codable, Hashable, Identifiable {
    public var id: UUID
    public var request: CalibrationRequest
    public var fit: PSFFit
    public var device: DeviceStamp
    public var durationMilliseconds: Double
    public init(id: UUID = UUID(), request: CalibrationRequest, fit: PSFFit, device: DeviceStamp, durationMilliseconds: Double) {
        self.id = id; self.request = request; self.fit = fit; self.device = device; self.durationMilliseconds = durationMilliseconds
    }
}

/// A parameter → σ law fitted from a sweep (SwiftUI `.blur`: σ ≈ r·s below the switch, ≈ 0.90·r·s above).
public struct CalibrationLaw: Sendable, Codable, Hashable {
    public var subject: CalibrationSubject
    /// σ / (parameter · scale) below the regime switch, if one exists.
    public var smallRatio: Double?
    /// σ / (parameter · scale) above the regime switch.
    public var largeRatio: Double
    /// Parameter (API unit) where the regime switches, or nil.
    public var switchParameter: Double?
    public var points: [CalibrationPoint]
    public var device: DeviceStamp
    public init(subject: CalibrationSubject, smallRatio: Double?, largeRatio: Double, switchParameter: Double?,
                points: [CalibrationPoint], device: DeviceStamp) {
        self.subject = subject; self.smallRatio = smallRatio; self.largeRatio = largeRatio
        self.switchParameter = switchParameter; self.points = points; self.device = device
    }
    /// σ in device pixels for a parameter, by this law.
    public func sigmaPx(parameter: Double, displayScale: Double) -> Double {
        let ratio = (switchParameter.map { parameter <= $0 } ?? false) ? (smallRatio ?? largeRatio) : largeRatio
        return ratio * parameter * displayScale
    }
}

public struct CalibrationPoint: Sendable, Codable, Hashable {
    public var parameter: Double
    public var sigmaPx: Double
    public var centreSpreadPx: Double
    public init(parameter: Double, sigmaPx: Double, centreSpreadPx: Double) {
        self.parameter = parameter; self.sigmaPx = sigmaPx; self.centreSpreadPx = centreSpreadPx
    }
}

/// Pure fitting math (CAL §3.3), implemented by CALIBRATION in Sources/BlurCore/Calibration/, unit-tested on the Mac
/// against CAL's macOS tables and MeasurePSF's self-check numbers.
public protocol PSFFitting: Sendable {
    func fit(_ samples: [EdgeSamples], request: CalibrationRequest) -> PSFFit
    /// A law from a sweep of results for one subject (nil when there are fewer than 3 points).
    func law(_ sweep: [CalibrationResult]) -> CalibrationLaw?
}
