import Foundation

// FROZEN — ARCHITECTURE.md §5.1. One formatter for every number on screen (SPEC §15 copy rules, Metro contract A.6):
// display precision = spoken precision; integers are whole numbers with their noun; negative numbers use U+2212;
// very small or large values use "7.1·10⁻⁴". Areas never format numbers for display with their own code.

/// "32 samples", "1 pass".
public struct CountNoun: Sendable, Codable, Hashable {
    public var singular: String
    public var plural: String
    public init(_ singular: String, _ plural: String) { self.singular = singular; self.plural = plural }
    public func word(for value: Double) -> String { abs(value - 1) < 1e-12 ? singular : plural }
}

public struct NumberStyle: Sendable, Codable, Hashable {
    public enum Precision: Sendable, Codable, Hashable {
        /// Fixed decimals (0 = integer).
        case decimals(Int)
        /// Significant digits; scientific notation outside 10⁻³ … 10⁶.
        case significant(Int)
    }
    public var precision: Precision
    /// Unit symbol printed after the number ("px", "ms", "%", "c/px").
    public var unit: String?
    /// Unit as spoken ("pixels", "milliseconds"); falls back to `unit`.
    public var spokenUnit: String?
    /// For counts: the noun replaces the unit ("32 samples").
    public var noun: CountNoun?
    /// Thousands separators ("2,401").
    public var grouping: Bool
    /// Print "+" on positive values ("PAN +36 PX").
    public var explicitPlus: Bool

    public init(precision: Precision, unit: String? = nil, spokenUnit: String? = nil, noun: CountNoun? = nil,
                grouping: Bool = true, explicitPlus: Bool = false) {
        self.precision = precision; self.unit = unit; self.spokenUnit = spokenUnit; self.noun = noun
        self.grouping = grouping; self.explicitPlus = explicitPlus
    }
    public static func decimals(_ d: Int, unit: String? = nil, spokenUnit: String? = nil) -> NumberStyle {
        NumberStyle(precision: .decimals(d), unit: unit, spokenUnit: spokenUnit)
    }
    public static func integer(noun: CountNoun? = nil, unit: String? = nil, spokenUnit: String? = nil) -> NumberStyle {
        NumberStyle(precision: .decimals(0), unit: unit, spokenUnit: spokenUnit, noun: noun)
    }
    public static func significant(_ n: Int, unit: String? = nil, spokenUnit: String? = nil) -> NumberStyle {
        NumberStyle(precision: .significant(n), unit: unit, spokenUnit: spokenUnit)
    }

    /// The unit or noun printed after the number, for `value`.
    public func unitText(for value: Double) -> String? { noun.map { $0.word(for: value) } ?? unit }

    /// The number alone ("0.03332", "2,401", "−0.217", "7.1·10⁻⁴", "∞").
    public func text(_ value: Double) -> String {
        if value.isNaN { return "—" }
        if value.isInfinite { return value < 0 ? "−∞" : "∞" }
        var body: String
        switch precision {
        case .decimals(let d):
            body = NumberStyle.fixed(abs(value), decimals: Swift.max(0, d), grouping: grouping)
        case .significant(let n):
            let digits = Swift.max(1, n)
            if value == 0 { body = "0" } else {
                let e = Int(floor(log10(abs(value))))
                if e < -3 || e >= 6 {
                    var mantissa = abs(value) / pow(10, Double(e))
                    var exponent = e
                    if NumberStyle.fixed(mantissa, decimals: digits - 1, grouping: false).hasPrefix("10") {
                        mantissa /= 10; exponent += 1
                    }
                    body = NumberStyle.fixed(mantissa, decimals: digits - 1, grouping: false) + "·10" + NumberStyle.superscript(exponent)
                } else {
                    body = NumberStyle.fixed(abs(value), decimals: Swift.max(0, digits - 1 - e), grouping: grouping)
                }
            }
        }
        let isZero = body.allSatisfy { "0.,".contains($0) }
        if value < 0 && !isZero { body = "\u{2212}" + body } else if explicitPlus && value > 0 && !isZero { body = "+" + body }
        return body
    }

    /// The spoken form, including the unit or noun ("minus 0.217", "32 samples", "7.1 times 10 to the minus 4").
    public func spoken(_ value: Double) -> String {
        var s = text(value)
            .replacingOccurrences(of: "\u{2212}∞", with: "minus infinity")
            .replacingOccurrences(of: "∞", with: "infinity")
            .replacingOccurrences(of: "\u{2212}", with: "minus ")
            .replacingOccurrences(of: ",", with: "")
        if let range = s.range(of: "·10") {
            let exponent = NumberStyle.unsuperscript(String(s[range.upperBound...]))
            s = String(s[..<range.lowerBound]) + " times 10 to the " + (exponent.hasPrefix("-") ? "minus " + exponent.dropFirst() : exponent)
        }
        if let n = noun { return s + " " + n.word(for: value) }
        if let u = spokenUnit ?? unit { return s + " " + u }
        return s
    }

    private static func fixed(_ v: Double, decimals: Int, grouping: Bool) -> String {
        let raw = String(format: "%.\(decimals)f", v)
        guard grouping, v >= 1000 else { return raw }
        let parts = raw.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        var integer = Array(parts[0])
        var grouped: [Character] = []
        while integer.count > 3 {
            grouped = [","] + Array(integer.suffix(3)) + grouped
            integer.removeLast(3)
        }
        let head = String(integer) + String(grouped)
        return parts.count > 1 ? head + "." + parts[1] : head
    }
    private static let superscripts: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵",
                                                       "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
    private static func superscript(_ n: Int) -> String { String(String(n).map { superscripts[$0] ?? $0 }) }
    private static func unsuperscript(_ s: String) -> String {
        let inverse = Dictionary(uniqueKeysWithValues: superscripts.map { ($1, $0) })
        return String(s.map { inverse[$0] ?? $0 })
    }
}

public extension BadgedValue {
    /// A badged number. MEASURED numbers must pass `device`.
    static func number(_ value: Double, _ style: NumberStyle, _ provenance: Provenance, qualifiers: Qualifiers = [],
                       source: SourceRef? = nil, device: DeviceStamp? = nil, caption: String? = nil) -> BadgedValue {
        var spoken = style.spoken(value) + ", " + provenance.spokenPhrase(device: device)
        if let caption { spoken += ", " + caption.lowercased() }
        return BadgedValue(value: value, text: style.text(value), unit: style.unitText(for: value), provenance: provenance,
                           qualifiers: qualifiers, source: source, device: device, caption: caption, spoken: spoken)
    }
    /// A value the user set (hero, Stepper, typed value): no badge.
    static func input(_ value: Double, _ style: NumberStyle) -> BadgedValue {
        BadgedValue(value: value, text: style.text(value), unit: style.unitText(for: value), provenance: nil,
                    isInput: true, spoken: style.spoken(value))
    }
    /// Words in place of a number ("N/A · RANK", "LINEAR-SAMPLED", "SOURCES DISAGREE").
    static func words(_ text: String, spoken: String? = nil, _ provenance: Provenance? = nil, qualifiers: Qualifiers = [],
                      source: SourceRef? = nil, device: DeviceStamp? = nil, caption: String? = nil) -> BadgedValue {
        let phrase = provenance.map { ", " + $0.spokenPhrase(device: device) } ?? ""
        return BadgedValue(value: nil, text: text, provenance: provenance, qualifiers: qualifiers, source: source,
                           device: device, caption: caption, spoken: (spoken ?? text.lowercased()) + phrase)
    }
    /// The value itself is unknown (SPEC §12.1): never a number.
    static func unverified(_ subject: String? = nil) -> BadgedValue {
        BadgedValue(value: nil, text: "UNVERIFIED", provenance: nil, qualifiers: .unverified,
                    spoken: subject.map { "\($0), unverified" } ?? "unverified")
    }
    /// A MEASURED slot that has no measurement yet ("–.––").
    static func notYetMeasured(_ placeholder: String = "–.––", unit: String? = nil) -> BadgedValue {
        BadgedValue(value: nil, text: placeholder, unit: unit, provenance: .measured, spoken: "not yet measured")
    }
}
