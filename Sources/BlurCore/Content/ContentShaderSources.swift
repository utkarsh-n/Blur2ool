import Foundation

// OWNER: CONTENT-LAYERS. The Shader tab of floor 6 (SPEC §4.3, §5.1; ARCHITECTURE §6.6): the exact `.metal` text that was
// compiled into the shipped library for the running variant. The app bundles the sources under `ShaderSources/` and
// stamps every Run with their SHA-256 (`ShaderProvenance`); this file reads the bundled copy, re-checks its SHA-256
// against the Run's stamp (Foundation only, no CryptoKit), and turns `// @explain:` comments and TRACE_PROBE lines into the
// listing's annotations and highlights. No source is ever recompiled on the device (JF M-5).

/// Where the Shader tab reads source text. The default reads the app bundle; tests inject fixed text.
public protocol ContentShaderSourceProviding: Sendable {
    /// The bundled source of `fileName` ("F2Gaussian.metal"), or nil when this build carries no copy.
    func source(fileName: String) -> String?
}

/// Reads `<bundle>/ShaderSources/<fileName>` (written at build time by Tools/shader-manifest.sh).
public struct ContentBundleShaderSources: ContentShaderSourceProviding {
    public init() {}
    public func source(fileName: String) -> String? {
        guard !fileName.isEmpty, !fileName.contains("/") else { return nil }
        let candidates = [Bundle.main.url(forResource: fileName, withExtension: nil, subdirectory: "ShaderSources"),
                          Bundle.main.resourceURL?.appendingPathComponent("ShaderSources").appendingPathComponent(fileName)]
        for url in candidates.compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) { return text }
        }
        return nil
    }
}

/// The parsed listing for the Shader tab.
public struct ContentShaderListing: Sendable, Hashable {
    public var code: CodeBlock
    /// Lines that call or test TRACE_PROBE (highlighted for traced builds).
    public var traceLines: [Int]
    public var functionLines: [String: Int]

    /// Parses `// @explain: <one line>` annotations (ARCHITECTURE §6.3 rule 12) and TRACE_PROBE lines.
    public static func parse(_ text: String, sha256: String?, traced: Bool, functions: [String]) -> ContentShaderListing {
        var annotations: [Int: String] = [:], trace: [Int] = [], found: [String: Int] = [:]
        for (i, line) in text.components(separatedBy: "\n").enumerated() {
            let n = i + 1
            if let r = line.range(of: "@explain:") {
                annotations[n] = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
            }
            if line.contains("TRACE_PROBE") || line.contains("b2_trace_tap") || line.contains("b2_trace_final") { trace.append(n) }
            for f in functions where found[f] == nil && line.contains(f + "(") { found[f] = n }
        }
        let highlighted = (traced ? trace : []) + found.values.sorted()
        return ContentShaderListing(code: CodeBlock(language: "metal", text: text, highlightedLines: Array(Set(highlighted)).sorted(),
                                                    annotations: annotations, sha256: sha256),
                                    traceLines: trace, functionLines: found)
    }
}

/// SHA-256 (FIPS 180-4) in plain Swift, so BlurCore can re-check the bundled source against the Run's stamp.
public enum ContentSHA256 {
    public static func hex(_ data: Data) -> String { digest(Array(data)).map { String(format: "%02x", $0) }.joined() }
    public static func hex(_ text: String) -> String { hex(Data(text.utf8)) }

    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]

    public static func digest(_ message: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var bytes = message
        let bitLength = UInt64(message.count) &* 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 { bytes.append(0) }
        for i in (0..<8).reversed() { bytes.append(UInt8(truncatingIfNeeded: bitLength >> (UInt64(i) * 8))) }
        var w = [UInt32](repeating: 0, count: 64)
        func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
        for chunk in stride(from: 0, to: bytes.count, by: 64) {
            for t in 0..<16 {
                let b = chunk + 4 * t
                w[t] = UInt32(bytes[b]) << 24 | UInt32(bytes[b + 1]) << 16 | UInt32(bytes[b + 2]) << 8 | UInt32(bytes[b + 3])
            }
            for t in 16..<64 {
                let s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >> 3)
                let s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >> 10)
                w[t] = w[t - 16] &+ s0 &+ w[t - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for t in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[t] &+ w[t]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
        return h.flatMap { v in (0..<4).map { UInt8(truncatingIfNeeded: v >> (24 - 8 * UInt32($0))) } }
    }
}
