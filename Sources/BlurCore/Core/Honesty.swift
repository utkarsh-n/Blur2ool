import Foundation

// FROZEN — ARCHITECTURE.md §5.1. Honesty labels (BRIEF "Honesty rules"; SPEC §12).
// Every number that reaches the UI travels as a BadgedValue. Inputs (the hero, Stepper values, typed values) carry no badge.

/// The six provenance labels. On screen the WORD is primary; glyph and ink are redundant cues (SPEC §12.1).
public enum Provenance: String, Sendable, Codable, CaseIterable, Hashable {
    case live = "LIVE"
    case measured = "MEASURED"
    case computed = "COMPUTED"
    case modeled = "MODELED"
    case reference = "REFERENCE"
    case inferred = "INFERRED"

    /// The word printed in the badge capsule.
    public var word: String { rawValue }
    /// The word VoiceOver speaks after the value ("computed", "measured on iPhone 15 Pro Max").
    public func spokenPhrase(device: DeviceStamp?) -> String {
        switch self {
        case .live: "live"
        case .measured: device.map { "measured on \($0.spokenDevice)" } ?? "measured"
        case .computed: "computed"
        case .modeled: "modeled"
        case .reference: "reference"
        case .inferred: "inferred"
        }
    }
}

/// Qualifiers that travel with a value. None of them is a seventh badge (SPEC §12.1).
public struct Qualifiers: OptionSet, Sendable, Codable, Hashable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    /// The value itself is unknown: `text` holds words ("UNVERIFIED"), `value` must be nil.
    public static let unverified = Qualifiers(rawValue: 1 << 0)
    /// A number whose input is weak; `caption` says why ("UNVERIFIED PEAK"). Allowed only on MODELED or REFERENCE.
    public static let weakSource = Qualifiers(rawValue: 1 << 1)
    /// Two sources conflict; the UI shows the `SOURCES DISAGREE` caption under both rows.
    public static let sourcesDisagree = Qualifiers(rawValue: 1 << 2)
    /// Obtained in the iOS Simulator (Apple2-class GPU). Never a timing.
    public static let simulator = Qualifiers(rawValue: 1 << 3)
    /// Measured on another device (the research Mac) and shown on this one with that device's label.
    public static let notThisDevice = Qualifiers(rawValue: 1 << 4)
    /// Measured offscreen through `ImageRenderer`, not on screen.
    public static let offscreen = Qualifiers(rawValue: 1 << 5)
    /// An experimental path whose meaning is not yet confirmed (`ON-SCREEN · EXPERIMENTAL`).
    public static let experimental = Qualifiers(rawValue: 1 << 6)
    /// LIVE values computed on the CPU from the current image (adaptive weight maps): `LIVE · CPU`.
    public static let cpu = Qualifiers(rawValue: 1 << 7)
}

/// A citation: spec section, paper with year, vendor document, research file section, or URL.
public struct SourceRef: Sendable, Codable, Hashable {
    public var citation: String
    public var url: String?
    public init(_ citation: String, url: String? = nil) { self.citation = citation; self.url = url }
}

/// ProcessInfo.ThermalState as a portable value.
public enum ThermalLevel: String, Sendable, Codable, Hashable, CaseIterable {
    case nominal, fair, serious, critical, unknown
}

/// Where and when a MEASURED value was obtained. Required on every MEASURED number.
public struct DeviceStamp: Sendable, Codable, Hashable {
    public var deviceModel: String      // "iPhone 15 Pro Max", "Mac (Apple M1 Max)"
    public var gpuName: String          // MTLDevice.name
    public var gpuFamily: String        // "Apple9"
    public var osVersion: String        // "iOS 27.0"
    public var osBuild: String          // "24A5355p"
    public var isSimulator: Bool
    public var date: Date
    public var thermal: ThermalLevel    // at the start of the measurement
    public var lowPowerMode: Bool
    public init(deviceModel: String, gpuName: String, gpuFamily: String, osVersion: String, osBuild: String,
                isSimulator: Bool, date: Date, thermal: ThermalLevel, lowPowerMode: Bool) {
        self.deviceModel = deviceModel; self.gpuName = gpuName; self.gpuFamily = gpuFamily
        self.osVersion = osVersion; self.osBuild = osBuild; self.isSimulator = isSimulator
        self.date = date; self.thermal = thermal; self.lowPowerMode = lowPowerMode
    }

    /// "14 Oct" in the Gregorian calendar, UTC, independent of locale.
    public var dayLabel: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let parts = calendar.dateComponents([.day, .month], from: date)
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let month = months[Swift.max(0, Swift.min(11, (parts.month ?? 1) - 1))]
        return "\(parts.day ?? 1) \(month)"
    }
    /// The engraving that travels with MEASURED (SPEC §12.2 item 5): "iPhone 15 Pro Max · iOS 27.0 · 14 Oct".
    public var label: String {
        isSimulator ? "SIMULATOR (APPLE2 LIMITS) · \(osVersion) · \(dayLabel)" : "\(deviceModel) · \(osVersion) · \(dayLabel)"
    }
    public var spokenDevice: String { isSimulator ? "the Simulator" : deviceModel }
}

/// Every number that reaches the UI travels as a BadgedValue (build it with the factories in Formatting.swift).
public struct BadgedValue: Sendable, Codable, Hashable {
    /// The numeric value, or nil when only words are honest (UNVERIFIED, not yet measured).
    public var value: Double?
    /// The display text at the declared precision ("0.61", "UNVERIFIED", "–.––"), without the unit.
    public var text: String
    /// Unit symbol printed after the text ("ms", "px", "c/px"), or nil.
    public var unit: String?
    /// nil only for user inputs (`isInput`) and for pure words that make no claim.
    public var provenance: Provenance?
    public var qualifiers: Qualifiers
    public var source: SourceRef?
    /// Required when `provenance == .measured` and `value != nil`.
    public var device: DeviceStamp?
    /// Trailing caption in secondary ink ("UNVERIFIED PEAK", "SOURCES DISAGREE", "OFFSCREEN").
    public var caption: String?
    /// True for values the user set (hero, Stepper, typed): they carry no badge (SPEC §12.1).
    public var isInput: Bool
    /// The full VoiceOver phrase including the badge word ("0.61 milliseconds, measured on iPhone 15 Pro Max").
    public var spoken: String

    public init(value: Double?, text: String, unit: String? = nil, provenance: Provenance?, qualifiers: Qualifiers = [],
                source: SourceRef? = nil, device: DeviceStamp? = nil, caption: String? = nil, isInput: Bool = false,
                spoken: String) {
        self.value = value; self.text = text; self.unit = unit; self.provenance = provenance
        self.qualifiers = qualifiers; self.source = source; self.device = device; self.caption = caption
        self.isInput = isInput; self.spoken = spoken
    }

    /// Text with its unit ("0.61 ms").
    public var textWithUnit: String { unit.map { "\(text) \($0)" } ?? text }

    /// The honesty invariants of SPEC §12, checked by unit tests on all generated content (ARCHITECTURE §11.3).
    public var honestyViolations: [String] {
        var problems: [String] = []
        if provenance == .measured && value != nil && device == nil { problems.append("MEASURED number without a DeviceStamp") }
        if qualifiers.contains(.unverified) && value != nil { problems.append("UNVERIFIED value shown as a number") }
        if let d = device, d.isSimulator, unit == "ms", value != nil { problems.append("Simulator GPU milliseconds shown") }
        if provenance == .reference && source == nil { problems.append("REFERENCE value without a source") }
        if provenance == nil && value != nil && !isInput { problems.append("number without a badge") }
        if qualifiers.contains(.weakSource) && !(provenance == .modeled || provenance == .reference) {
            problems.append("weakSource qualifier on a \(provenance?.word ?? "missing") badge")
        }
        let lowered = (text + " " + spoken).lowercased()
        for marker in ["todo", "lorem", "placeholder", "tbd", "fixme"] where lowered.contains(marker) {
            problems.append("placeholder text '\(marker)'")
        }
        if spoken.isEmpty { problems.append("empty spoken text") }
        return problems
    }
}

/// A labelled row: "TAPS · 73 · = COMPUTED".
public struct LabeledValue: Sendable, Codable, Hashable, Identifiable {
    public var id: String
    /// ALL-CAPS mono label ("CENTRE WEIGHT").
    public var label: String
    public var value: BadgedValue
    public init(id: String, label: String, value: BadgedValue) { self.id = id; self.label = label; self.value = value }
}

/// One piece of a status or caption line (review fix E-51): plain words, a literal that may contain digits
/// (equations, coordinates, identifiers such as "3×3" or "(447, 455)", allow-listed on purpose), or a badged number.
public enum BadgedSegment: Sendable, Codable, Hashable {
    case text(String)
    case literal(String)
    case value(BadgedValue)
    public var text: String {
        switch self {
        case .text(let s), .literal(let s): s
        case .value(let v): v.textWithUnit
        }
    }
    public var spoken: String {
        switch self {
        case .text(let s), .literal(let s): s.lowercased()
        case .value(let v): v.spoken
        }
    }
}

/// A line of view-bound text in which every number travels as a BadgedValue (status row, σ-hold notice, captions,
/// MIN H lines, Difference MAX/RMS). `honestyViolations` also flags digits inside `.text` segments (the lint of
/// ARCHITECTURE §5.1 rule 4); put deliberate digits in `.literal`.
public struct BadgedLine: Sendable, Codable, Hashable {
    public var segments: [BadgedSegment]
    public init(_ segments: [BadgedSegment]) { self.segments = segments }
    /// A line of words only (digits in it are a lint violation).
    public static func words(_ text: String) -> BadgedLine { BadgedLine([.text(text)]) }
    public static let empty = BadgedLine([])
    public var text: String { segments.map(\.text).joined(separator: " ") }
    public var spoken: String { segments.map(\.spoken).joined(separator: " ") }
    public var values: [BadgedValue] { segments.compactMap { if case .value(let v) = $0 { v } else { nil } } }
    public var honestyViolations: [String] {
        var problems = values.flatMap(\.honestyViolations)
        for case .text(let s) in segments where s.contains(where: \.isNumber) {
            problems.append("digits in plain text '\(s)' (use a BadgedValue or a .literal)")
        }
        return problems
    }
}
