import Foundation

// FROZEN — ARCHITECTURE.md §5.2. Typed parameters with units, ranges, detents and formatting (SPEC §9),
// the five silent parameters every blur shares (SPEC §9.3) and the declared deck arrangement (SPEC §9.1).

public enum ParameterUnit: String, Sendable, Codable, Hashable, CaseIterable {
    case px, pt, cssPx, percent, degrees, cyclesPerPixel, fractionOfFullScale, ev, fNumber, nanometres,
         micrometres, millimetres, sceneUnits, timesWhite, ratio, texels, pixelsSquared, levels, intensityPerPixel, none

    /// Symbol printed after the value ("px", "%", "°", "c/px"); nil when none.
    public var symbol: String? {
        switch self {
        case .px: "px"
        case .pt: "pt"
        case .cssPx: "CSS px"
        case .percent: "%"
        case .degrees: "°"
        case .cyclesPerPixel: "c/px"
        case .ev: "EV"
        case .nanometres: "nm"
        case .micrometres: "µm"
        case .millimetres: "mm"
        case .timesWhite: "× white"
        case .texels: "texels"
        case .pixelsSquared: "px²"
        case .levels: "levels"
        case .fractionOfFullScale, .fNumber, .sceneUnits, .ratio, .intensityPerPixel, .none: nil
        }
    }
    /// Unit as VoiceOver speaks it.
    public var spokenName: String? {
        switch self {
        case .px: "pixels"
        case .pt: "points"
        case .cssPx: "CSS pixels"
        case .percent: "percent"
        case .degrees: "degrees"
        case .cyclesPerPixel: "cycles per pixel"
        case .fractionOfFullScale: "of full scale"
        case .ev: "stops of exposure"
        case .nanometres: "nanometres"
        case .micrometres: "micrometres"
        case .millimetres: "millimetres"
        case .sceneUnits: "scene units"
        case .timesWhite: "times white"
        case .texels: "texels"
        case .pixelsSquared: "square pixels"
        case .levels: "levels"
        case .intensityPerPixel: "intensity per pixel"
        case .fNumber, .ratio, .none: nil
        }
    }
}

/// How the FINE crown and the Stepper move a continuous value.
public enum StepScale: String, Sendable, Codable, Hashable {
    /// value ± fineStep, snapped to the fineStep grid.
    case linear
    /// Three detents per decade: … 0.01 · 0.02 · 0.05 · 0.1 … (log quantities: ε, noise-to-signal K).
    case oneTwoFive
    /// Photographic third stops: f = 2^(n/6); labels are the nominal markings (f/2.8).
    case thirdStops
}

/// A named stop of the SEMANTIC crown (20° detents). `id` marks stops whose value is replaced at runtime by a
/// measurement (the SwiftUI regime switch, "swiftui-regime-switch"); `provenance` labels stops that are claims.
public struct SemanticStop: Sendable, Codable, Hashable {
    public var value: Double
    public var label: String?
    public var id: String?
    public var provenance: Provenance?
    public init(_ value: Double, label: String? = nil, id: String? = nil, provenance: Provenance? = nil) {
        self.value = value; self.label = label; self.id = id; self.provenance = provenance
    }
}

/// A named meaning band ("Frosted" from 4 px). Blur2ool's own descriptive words, not a standard (SPEC §4.1.3).
public struct MeaningBand: Sendable, Codable, Hashable {
    public var lowerBound: Double
    public var name: String
    public init(from lowerBound: Double, _ name: String) { self.lowerBound = lowerBound; self.name = name }
}

public struct ContinuousSpec: Sendable, Codable, Hashable {
    public var range: ClosedRange<Double>
    /// One FINE crown detent (8°) and one Stepper step; also the display and spoken precision (Metro contract A.6).
    public var fineStep: Double
    public var decimals: Int
    public var scale: StepScale
    public var semanticStops: [SemanticStop]
    public var bands: [MeaningBand]
    public init(range: ClosedRange<Double>, fineStep: Double, decimals: Int, scale: StepScale = .linear,
                semanticStops: [SemanticStop] = [], bands: [MeaningBand] = []) {
        self.range = range; self.fineStep = fineStep; self.decimals = decimals; self.scale = scale
        self.semanticStops = semanticStops; self.bands = bands
    }

    public func clamped(_ v: Double) -> Double { Swift.min(Swift.max(v, range.lowerBound), range.upperBound) }

    /// One FINE detent per `detents` (sign = direction). Clamped; turning past an end returns the end value.
    public func stepped(from v: Double, by detents: Int) -> Double {
        guard detents != 0 else { return clamped(v) }
        switch scale {
        case .linear:
            let n = (v / fineStep).rounded() + Double(detents)
            return clamped((n * fineStep * 1e9).rounded() / 1e9)
        case .oneTwoFive:
            let grid = ContinuousSpec.oneTwoFiveGrid(in: range)
            return ContinuousSpec.move(on: grid, from: v, by: detents) ?? clamped(v)
        case .thirdStops:
            let n = (6 * log2(Swift.max(v, 1e-9))).rounded() + Double(detents)
            return clamped(pow(2, n / 6))
        }
    }

    /// One SEMANTIC detent: the next named stop strictly beyond `v` in the direction of `detents` (one stop per call).
    public func semanticStepped(from v: Double, by detents: Int, stops override: [SemanticStop]? = nil) -> Double {
        let values = (override ?? semanticStops).map(\.value).filter { range.contains($0) }.sorted()
        guard detents != 0, !values.isEmpty else { return clamped(v) }
        if detents > 0 { return values.first { $0 > v + 1e-9 } ?? clamped(v) }
        return values.last { $0 < v - 1e-9 } ?? clamped(v)
    }

    /// The meaning band containing `v` (highest lower bound ≤ v).
    public func band(for v: Double) -> MeaningBand? { bands.filter { $0.lowerBound <= v }.max { $0.lowerBound < $1.lowerBound } }

    /// The nominal label for third-stop values ("f/2.8"), nil for other scales.
    public func nominalLabel(for v: Double) -> String? {
        guard scale == .thirdStops else { return nil }
        let marks = [1.0, 1.1, 1.2, 1.4, 1.6, 1.8, 2, 2.2, 2.5, 2.8, 3.2, 3.5, 4, 4.5, 5, 5.6, 6.3, 7.1, 8, 9, 10, 11, 13, 14,
                     16, 18, 20, 22, 25, 29, 32]
        let n = Int((6 * log2(Swift.max(v, 1e-9))).rounded())
        guard n >= 0, n < marks.count else { return nil }
        let m = marks[n]
        return m == m.rounded() ? "f/\(Int(m))" : "f/\(m)"
    }

    private static func oneTwoFiveGrid(in range: ClosedRange<Double>) -> [Double] {
        var grid: [Double] = []
        var decade = pow(10, floor(log10(Swift.max(range.lowerBound, 1e-12))))
        while decade <= range.upperBound * 10 {
            for m in [1.0, 2, 5] {
                let v = m * decade
                if v >= range.lowerBound * (1 - 1e-9) && v <= range.upperBound * (1 + 1e-9) { grid.append(v) }
            }
            decade *= 10
        }
        return grid
    }
    private static func move(on grid: [Double], from v: Double, by detents: Int) -> Double? {
        guard !grid.isEmpty else { return nil }
        let nearest = grid.indices.min { abs(log(grid[$0] / Swift.max(v, 1e-12))) < abs(log(grid[$1] / Swift.max(v, 1e-12))) } ?? 0
        return grid[Swift.min(Swift.max(nearest + detents, 0), grid.count - 1)]
    }
}

public enum IntegerParity: String, Sendable, Codable, Hashable { case any, odd, even }

public struct IntegerSpec: Sendable, Codable, Hashable {
    public var range: ClosedRange<Int>
    public var step: Int
    public var parity: IntegerParity
    /// Counts carry their noun ("32 samples"); magnitudes carry a unit instead (ParameterSpec.unit).
    public var noun: CountNoun?
    public var semanticStops: [Int]
    public init(range: ClosedRange<Int>, step: Int = 1, parity: IntegerParity = .any, noun: CountNoun? = nil,
                semanticStops: [Int] = []) {
        self.range = range; self.step = step; self.parity = parity; self.noun = noun; self.semanticStops = semanticStops
    }
    public func clamped(_ v: Int) -> Int { Swift.min(Swift.max(v, range.lowerBound), range.upperBound) }
    /// One detent or Stepper press; respects `step` and parity; clamped.
    public func stepped(from v: Int, by detents: Int) -> Int {
        var next = v + detents * Swift.max(1, step)
        switch parity {
        case .odd where next % 2 == 0: next += detents > 0 ? 1 : -1
        case .even where next % 2 != 0: next += detents > 0 ? 1 : -1
        default: break
        }
        return clamped(next)
    }
    public func semanticStepped(from v: Int, by detents: Int) -> Int {
        let stops = semanticStops.filter { range.contains($0) }.sorted()
        guard detents != 0, !stops.isEmpty else { return clamped(v) }
        if detents > 0 { return stops.first { $0 > v } ?? clamped(v) }
        return stops.last { $0 < v } ?? clamped(v)
    }
}

public struct ChoiceOption: Sendable, Codable, Hashable, Identifiable {
    public var id: String
    public var label: String
    /// A disabled option stays visible; this is its accessibility hint and one-line caption.
    public var disabledReason: String?
    public init(_ id: String, _ label: String, disabledReason: String? = nil) {
        self.id = id; self.label = label; self.disabledReason = disabledReason
    }
}

public struct ChoiceSpec: Sendable, Codable, Hashable {
    public var options: [ChoiceOption]
    public init(_ options: [ChoiceOption]) { self.options = options }
    /// 2–4 options → segmented picker (32 pt); 5 or more → Menu (44 pt) (SPEC §9.1).
    public var prefersMenu: Bool { options.count >= 5 }
}

/// A per-pass integer sequence edited with event tiles (Kawase offsets "0 1 2 2 3"); its length is another parameter.
public struct SequenceSpec: Sendable, Codable, Hashable {
    public var elementRange: ClosedRange<Int>
    public var lengthKey: ParameterKey
    public init(elementRange: ClosedRange<Int>, lengthKey: ParameterKey) { self.elementRange = elementRange; self.lengthKey = lengthKey }
}

public enum ParameterKind: Sendable, Codable, Hashable {
    case continuous(ContinuousSpec)
    case integer(IntegerSpec)
    case choice(ChoiceSpec)
    case toggle
    case sequence(SequenceSpec)
    /// A window position in window pixels, driven by an on-image handle with Stepper twins.
    case position
}

public enum ParameterValue: Sendable, Codable, Hashable {
    case double(Double)
    case int(Int)
    case choice(String)
    case bool(Bool)
    case intList([Int])
    case point(x: Double, y: Double)
}

/// Where a value applies: to the blur (default) or to the test image (the EXPOSURE crown of exponential-blur).
public enum ParameterScope: Sendable, Codable, Hashable {
    case blur
    case specimenExposure
}

public struct ParameterSpec: Sendable, Codable, Hashable, Identifiable {
    public var key: ParameterKey
    public var id: ParameterKey { key }
    /// ALL-CAPS label ("SIGMA", "RADIUS", "SAMPLES").
    public var label: String
    public var spokenLabel: String
    public var unit: ParameterUnit
    public var kind: ParameterKind
    public var defaultValue: ParameterValue
    public var scope: ParameterScope
    /// One line shown in the Parameters panel under the control, when needed ("σ = √(r(r+2)/6)").
    public var note: String?
    public init(key: ParameterKey, label: String, spokenLabel: String, unit: ParameterUnit, kind: ParameterKind,
                defaultValue: ParameterValue, scope: ParameterScope = .blur, note: String? = nil) {
        self.key = key; self.label = label; self.spokenLabel = spokenLabel; self.unit = unit; self.kind = kind
        self.defaultValue = defaultValue; self.scope = scope; self.note = note
    }
    /// The readout unit line ("SIGMA · PX").
    public var unitLine: String { [label, unit.symbol?.uppercased()].compactMap { $0 }.joined(separator: " · ") }
    /// How the value is printed and spoken (display precision = fine step).
    public var numberStyle: NumberStyle {
        switch kind {
        case .continuous(let c): .decimals(c.decimals, unit: unit.symbol, spokenUnit: unit.spokenName)
        case .integer(let i): .integer(noun: i.noun, unit: i.noun == nil ? unit.symbol : nil, spokenUnit: unit.spokenName)
        default: .decimals(0)
        }
    }
}

/// A full set of parameter values for one blur.
public struct ParameterValues: Sendable, Codable, Hashable {
    public var storage: [ParameterKey: ParameterValue]
    public init(_ storage: [ParameterKey: ParameterValue] = [:]) { self.storage = storage }
    public subscript(key: ParameterKey) -> ParameterValue? {
        get { storage[key] }
        set { storage[key] = newValue }
    }
    public func double(_ key: ParameterKey) -> Double? {
        switch storage[key] {
        case .double(let v): v
        case .int(let v): Double(v)
        default: nil
        }
    }
    public func int(_ key: ParameterKey) -> Int? {
        switch storage[key] {
        case .int(let v): v
        case .double(let v): Int(v.rounded())
        default: nil
        }
    }
    public func choice(_ key: ParameterKey) -> String? { if case .choice(let v) = storage[key] { return v }; return nil }
    public func bool(_ key: ParameterKey) -> Bool? { if case .bool(let v) = storage[key] { return v }; return nil }
    public func intList(_ key: ParameterKey) -> [Int]? { if case .intList(let v) = storage[key] { return v }; return nil }
    public func point(_ key: ParameterKey) -> SIMD2<Double>? {
        if case .point(let x, let y) = storage[key] { return SIMD2(x, y) }; return nil
    }
}

// MARK: - Silent parameters shared by every blur (SPEC §9.3; ARCHITECTURE §4.2–§4.3)

public enum ColourSpace: String, Sendable, Codable, Hashable, CaseIterable { case linearLight, srgbEncoded }

/// Index mapping is identical on CPU and GPU (`b2_map_index` in B2Shared.h; ARCHITECTURE §4.3).
public enum EdgeMode: String, Sendable, Codable, Hashable, CaseIterable {
    case clamp, mirror, wrap, zero, renormalise

    /// The value of the function constant B2_EDGE_MODE (index 2).
    public var shaderIndex: UInt32 {
        switch self {
        case .clamp: 0
        case .mirror: 1
        case .wrap: 2
        case .zero: 3
        case .renormalise: 4
        }
    }
    /// Maps an index into [0, n); nil means "contributes zero" (zero) or "dropped" (renormalise).
    public func map(_ i: Int, count n: Int) -> Int? {
        precondition(n > 0)
        if i >= 0 && i < n { return i }
        switch self {
        case .clamp: return Swift.min(Swift.max(i, 0), n - 1)
        case .mirror:
            let period = 2 * n
            let j = ((i % period) + period) % period
            return j < n ? j : period - 1 - j
        case .wrap: return ((i % n) + n) % n
        case .zero, .renormalise: return nil
        }
    }
}

public enum AlphaMode: String, Sendable, Codable, Hashable, CaseIterable { case premultiplied, straight }
public enum AccumulatorPrecision: String, Sendable, Codable, Hashable, CaseIterable { case fp32, fp16 }
/// `rgba8Unorm` intermediates appear only on the Compare › Precision axis.
public enum IntermediateFormat: String, Sendable, Codable, Hashable, CaseIterable { case rgba16Float, rgba8Unorm }
/// Summed-area tables: plain fp32 (the precision trap, default) or mean-centred (the fix); Compare › Precision axis.
public enum SATCentring: String, Sendable, Codable, Hashable, CaseIterable { case plain, meanCentred }
public enum PreviewPolicy: String, Sendable, Codable, Hashable, CaseIterable { case halfWhileMoving, alwaysFull }

public struct SilentSettings: Sendable, Codable, Hashable {
    public var colourSpace: ColourSpace
    public var edgeMode: EdgeMode
    public var alphaMode: AlphaMode
    public var accumulator: AccumulatorPrecision
    public var intermediate: IntermediateFormat
    public var satCentring: SATCentring
    public var preview: PreviewPolicy
    public init(colourSpace: ColourSpace = .linearLight, edgeMode: EdgeMode = .clamp, alphaMode: AlphaMode = .premultiplied,
                accumulator: AccumulatorPrecision = .fp32, intermediate: IntermediateFormat = .rgba16Float,
                satCentring: SATCentring = .plain, preview: PreviewPolicy = .halfWhileMoving) {
        self.colourSpace = colourSpace; self.edgeMode = edgeMode; self.alphaMode = alphaMode; self.accumulator = accumulator
        self.intermediate = intermediate; self.satCentring = satCentring; self.preview = preview
    }
    public static let standard = SilentSettings()
}

// MARK: - Deck arrangements (SPEC §9.1). Declared per entry in BlurCore, never inferred from live values.

public enum DeckArrangement: Sendable, Codable, Hashable {
    /// A: FINE (cyan, 8°) + SEMANTIC (amber, 20°) crowns on the same parameter.
    case crownPair(ParameterKey)
    /// B: FINE crown (magnitude) + ANGLE crown (cyan, 8° = 1°, semantic snaps at the symmetry stops).
    case fineAndAngle(fine: ParameterKey, angle: ParameterKey)
    /// C: two crowns, two continuous parameters (the second one amber, with its own name and detents).
    case twoCrowns(first: ParameterKey, second: ParameterKey)
    /// D: FINE crown on the left; a column of Stepper (48 pt) above a segmented picker or Menu (32–44 pt).
    case crownAndColumn(fine: ParameterKey, stepper: ParameterKey?, picker: ParameterKey?)
    /// E: no crown: event tiles or a segmented picker (and/or) above a Stepper.
    case tilesAndStepper(tiles: ParameterKey?, picker: ParameterKey?, stepper: ParameterKey?)
    /// The slot stays reserved and shows one engraved line.
    case none(message: String)
}
