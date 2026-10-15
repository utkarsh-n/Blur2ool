import Foundation

// FROZEN — ARCHITECTURE.md §5.1. Change only through Documentation/build/requests/<AREA>.md.
// Stable identifiers (CATALOG.md §0: canonical ids and variant ids), pixel geometry and the seven floors.

/// Shared string coding key so that dictionaries keyed by these identifiers encode as JSON objects.
public struct StringCodingKey: CodingKey, Sendable {
    public var stringValue: String
    public var intValue: Int? { nil }
    public init(_ string: String) { stringValue = string }
    public init?(stringValue: String) { self.stringValue = stringValue }
    public init?(intValue: Int) { return nil }
}

/// A canonical catalog id ("gaussian-blur"). Never shown on screen; the display name is.
public struct BlurID: RawRepresentable, Hashable, Comparable, Sendable, Codable, CodingKeyRepresentable,
                      ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public var description: String { rawValue }
    public var codingKey: any CodingKey { StringCodingKey(rawValue) }
    public init?<T: CodingKey>(codingKey: T) { rawValue = codingKey.stringValue }
    public static func < (a: BlurID, b: BlurID) -> Bool { a.rawValue < b.rawValue }
}

/// A variant id ("gaussian-linear-sampling"): an implementation strategy of a catalog entry.
public struct VariantID: RawRepresentable, Hashable, Comparable, Sendable, Codable, CodingKeyRepresentable,
                         ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public var description: String { rawValue }
    public var codingKey: any CodingKey { StringCodingKey(rawValue) }
    public init?<T: CodingKey>(codingKey: T) { rawValue = codingKey.stringValue }
    public static func < (a: VariantID, b: VariantID) -> Bool { a.rawValue < b.rawValue }
}

/// A test-image id ("night-city"). SPEC §11.
public struct SpecimenID: RawRepresentable, Hashable, Comparable, Sendable, Codable, CodingKeyRepresentable,
                          ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public var description: String { rawValue }
    public var codingKey: any CodingKey { StringCodingKey(rawValue) }
    public init?<T: CodingKey>(codingKey: T) { rawValue = codingKey.stringValue }
    public static func < (a: SpecimenID, b: SpecimenID) -> Bool { a.rawValue < b.rawValue }
}

/// A parameter key inside one catalog entry ("sigma", "radius", "samples", "centreX").
public struct ParameterKey: RawRepresentable, Hashable, Comparable, Sendable, Codable, CodingKeyRepresentable,
                            ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public var description: String { rawValue }
    public var codingKey: any CodingKey { StringCodingKey(rawValue) }
    public init?<T: CodingKey>(codingKey: T) { rawValue = codingKey.stringValue }
    public static func < (a: ParameterKey, b: ParameterKey) -> Bool { a.rawValue < b.rawValue }
}

/// A pixel of the image window (0…N−1), y down. Its centre is at (x + 0.5, y + 0.5) in texel coordinates.
public struct PixelPoint: Sendable, Codable, Hashable {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
    public static let zero = PixelPoint(x: 0, y: 0)
    /// Texel-centre coordinates of this pixel.
    public var centre: SIMD2<Double> { SIMD2(Double(x) + 0.5, Double(y) + 0.5) }
}

public struct ImageSize: Sendable, Codable, Hashable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }
    public static func square(_ n: Int) -> ImageSize { ImageSize(width: n, height: n) }
    public var pixelCount: Int { width * height }
    public func contains(_ p: PixelPoint) -> Bool { p.x >= 0 && p.y >= 0 && p.x < width && p.y < height }
}

/// An axis-aligned pixel rectangle (origin = top-left pixel).
public struct PixelRegion: Sendable, Codable, Hashable {
    public var origin: PixelPoint
    public var size: ImageSize
    public init(origin: PixelPoint, size: ImageSize) { self.origin = origin; self.size = size }
    /// A `side` × `side` square centred on `centre`, shifted to lie inside `bounds` when possible.
    public static func centred(on centre: PixelPoint, side: Int, inside bounds: ImageSize) -> PixelRegion {
        let s = Swift.min(side, Swift.min(bounds.width, bounds.height))
        let x = Swift.min(Swift.max(centre.x - s / 2, 0), bounds.width - s)
        let y = Swift.min(Swift.max(centre.y - s / 2, 0), bounds.height - s)
        return PixelRegion(origin: PixelPoint(x: x, y: y), size: .square(s))
    }
    public func contains(_ p: PixelPoint) -> Bool {
        p.x >= origin.x && p.y >= origin.y && p.x < origin.x + size.width && p.y < origin.y + size.height
    }
}

/// The seven floors (SPEC §5). Raw values are the floor numbers shown on screen.
public enum Floor: Int, Sendable, Codable, CaseIterable, Comparable, Hashable {
    case slide = 1, api, math, kernel, algorithm, gpu, pixels
    public static func < (a: Floor, b: Floor) -> Bool { a.rawValue < b.rawValue }

    /// Rail chip label on the Bench, at most 5 characters (SPEC §4.1.4).
    public var railLabel: String {
        switch self {
        case .slide: "SLIDE"
        case .api: "API"
        case .math: "MATH"
        case .kernel: "KERNL"
        case .algorithm: "ALGO"
        case .gpu: "GPU"
        case .pixels: "PIXEL"
        }
    }
    /// Trace floor-selector tile label (SPEC §4.4).
    public var tileLabel: String {
        switch self {
        case .kernel: "KERNEL"
        default: railLabel
        }
    }
    /// Title word: "Floor 4 · Kernel".
    public var title: String {
        switch self {
        case .slide: "Slide"
        case .api: "API"
        case .math: "Math"
        case .kernel: "Kernel"
        case .algorithm: "Algorithm"
        case .gpu: "GPU"
        case .pixels: "Pixels"
        }
    }
    /// Page eyebrow: "FLOOR 4 · KERNEL".
    public var eyebrow: String { "FLOOR \(rawValue) · \(title.uppercased())" }
    /// The floor's one question, the same for every blur (SPEC §5.1).
    public var question: String {
        switch self {
        case .slide: "What would you type, and in which tool, to get this blur here?"
        case .api: "What call does that become, and what does each argument mean?"
        case .math: "What continuous operator is this, and what does it do to each frequency?"
        case .kernel: "What finite numbers stand in for the curve, and what did that cost?"
        case .algorithm: "In what order, in how many passes, with what in-between images, is it computed?"
        case .gpu: "Which thread computed this pixel, what did it fetch, and what did it cost on this phone?"
        case .pixels: "What went in, what came out, how was it encoded, and does the CPU agree?"
        }
    }
}
