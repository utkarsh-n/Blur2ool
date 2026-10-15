import Foundation

// OWNER: ENGINE. The one JSON configuration for the Run log (persisted store, `Export JSON`, tests). Runs carry
// non-finite numbers on purpose — `ParityTolerance.reportOnly` has ulp16 = ∞, a kurtosis can be NaN — and Foundation's
// default JSONEncoder throws on them, which would silently drop the whole log. Non-finite values are written as the
// strings "inf", "-inf" and "nan" and read back exactly.

public enum RunLogCoding {
    /// Persisted log: compact, dates as seconds since the reference date (exact round trip).
    public static func storeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return encoder
    }
    public static func storeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return decoder
    }
    /// `Export JSON` (Field guide › Runs): pretty, sorted keys, ISO 8601 dates with fractional seconds, so device numbers
    /// can replace research's Mac figures (SPEC §13.3, JF G-19).
    public static func exportEncoder() -> JSONEncoder {
        let encoder = storeEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoStyle.format(date))
        }
        return encoder
    }
    public static func exportDecoder() -> JSONDecoder {
        let decoder = storeDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            return try isoStyle.parse(text)
        }
        return decoder
    }
    private static let isoStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}
