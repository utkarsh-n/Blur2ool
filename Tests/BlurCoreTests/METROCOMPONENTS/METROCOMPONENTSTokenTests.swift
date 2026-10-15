import Foundation
import Testing

// OWNER: METRO-COMPONENTS (PLAN §4 METRO-COMPONENTS acceptance 2; ARCHITECTURE §5.14; JF G-21; PLAN S15). Pure token
// checks on the Mac: they read Documentation/metro-station-design-tokens.json (mirrored by Tools/build.sh) and the Swift
// sources of App/DesignSystem as TEXT (the app target is not part of the SwiftPM package), and assert that
//   1. every Blur2ool token annotated `// manifest <path>` equals the manifest value at <path>;
//   2. every token line carries a provenance comment (`// manifest …` or `// spec …`);
//   3. the verbatim starter's palette and metrics equal the manifest (lens opacity 0.48, and 1.0 under Reduce
//      Transparency, unchanged: JF G-21);
//   4. every manifest colour is named exactly once across the starter and the Blur2ool extension;
//   5. no component file re-types a colour literal or a manifest RGB triple (tokens are referenced by name).

private enum Paths {
    /// The mirror root: <root>/Tests/BlurCoreTests/METROCOMPONENTS/<this file>.
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let manifest = root.appendingPathComponent("Documentation/metro-station-design-tokens.json")
    static let designSystem = root.appendingPathComponent("App/DesignSystem")
    static let palette = designSystem.appendingPathComponent("InstrumentPalette+Blur2ool.swift")
    static let starter = designSystem.appendingPathComponent("InstrumentDesignSystem.swift")
    /// The component files METRO-COMPONENTS owns (ARCHITECTURE §5.14), minus the token file itself.
    static let components = ["HonestyBadge", "BadgedValueText", "DecimalParameterStepper", "InstrumentCrown", "InstrumentSignalPill",
                             "InstrumentEventTiles", "InstrumentFloatingActionGroup", "SpecimenHousing", "FootprintGlyph",
                             "ComponentGallery"].map { designSystem.appendingPathComponent("\($0).swift") }
}

private enum Manifest {
    static func load() throws -> [String: Any] {
        let data = try Data(contentsOf: Paths.manifest)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    /// `colors/surface.metalLight` → manifest["colors"]["surface.metalLight"]; `hapticDetents/fineUp/intensity` likewise.
    static func value(_ json: [String: Any], _ path: String) -> Any? {
        var node: Any? = json
        for key in path.split(separator: "/").map(String.init) {
            guard let dict = node as? [String: Any] else { return nil }
            node = dict[key]
        }
        return node
    }
    static func number(_ any: Any?) -> Double? { (any as? NSNumber)?.doubleValue }
    static func rgb(_ any: Any?) -> [Double]? {
        guard let colour = any as? [String: Any], let rgb = colour["rgb"] as? [Any] else { return nil }
        let values = rgb.compactMap { ($0 as? NSNumber)?.doubleValue }
        return values.count == 3 ? values : nil
    }
}

/// One `static let name = value // manifest path` (or `// spec citation`) line of a token file.
private struct TokenLine {
    var line: Int
    var name: String
    var valueSource: String
    var manifestPath: String?
    var specCitation: String?

    /// `Color(red: 0.055, green: 0.073, blue: 0.090)` → [0.055, 0.073, 0.090].
    var rgb: [Double]? {
        let pattern = /Color\(red:\s*([0-9.]+),\s*green:\s*([0-9.]+),\s*blue:\s*([0-9.]+)\)/
        guard let m = valueSource.firstMatch(of: pattern) else { return nil }
        return [Double(m.1), Double(m.2), Double(m.3)].compactMap { $0 }
    }
    var number: Double? { Double(valueSource.trimmingCharacters(in: .whitespaces)) }

    static func parse(_ text: String) -> [TokenLine] {
        let pattern = /^\s*(?:public\s+)?static\s+let\s+(\w+)\s*(?::\s*[\w.]+)?\s*=\s*(.+?)\s*(?:\/\/\s*(.*))?$/
        var out: [TokenLine] = []
        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            guard let m = String(raw).firstMatch(of: pattern) else { continue }
            let comment = m.3.map(String.init) ?? ""
            var token = TokenLine(line: index + 1, name: String(m.1), valueSource: String(m.2))
            if comment.hasPrefix("manifest ") {
                token.manifestPath = String(comment.dropFirst("manifest ".count)).trimmingCharacters(in: .whitespaces)
            } else if comment.hasPrefix("spec ") {
                token.specCitation = String(comment.dropFirst("spec ".count)).trimmingCharacters(in: .whitespaces)
            }
            out.append(token)
        }
        return out
    }
}

@Suite struct METROCOMPONENTS_TokenParity {
    @Test func manifestIsMirroredAndIsEditionOne() throws {
        let json = try Manifest.load()
        #expect(json["edition"] as? String == "1.0")
        #expect(json["name"] as? String == "Metro Station SwiftUI Design System")
        #expect((json["colors"] as? [String: Any])?.count == 25)
    }

    @Test func everyAnnotatedTokenEqualsItsManifestValue() throws {
        let json = try Manifest.load()
        let tokens = TokenLine.parse(try String(contentsOf: Paths.palette, encoding: .utf8))
        let annotated = tokens.filter { $0.manifestPath != nil }
        #expect(annotated.count >= 60, "only \(annotated.count) manifest-annotated tokens")
        var checked = 0
        for token in annotated {
            let path = token.manifestPath!
            let entry = Manifest.value(json, path)
            if let rgb = token.rgb {
                let expected = try #require(Manifest.rgb(entry), "\(token.name) (line \(token.line)): no colour at manifest \(path)")
                #expect(rgb == expected, "\(token.name) (line \(token.line)): Swift \(rgb) ≠ manifest \(path) \(expected)")
            } else {
                let value = try #require(token.number, "\(token.name) (line \(token.line)): value '\(token.valueSource)' is not a literal")
                let expected = try #require(Manifest.number(entry), "\(token.name) (line \(token.line)): no number at manifest \(path)")
                #expect(abs(value - expected) < 1e-12, "\(token.name) (line \(token.line)): Swift \(value) ≠ manifest \(path) \(expected)")
            }
            checked += 1
        }
        #expect(checked == annotated.count)
    }

    @Test func everyTokenLineCarriesItsProvenance() throws {
        let tokens = TokenLine.parse(try String(contentsOf: Paths.palette, encoding: .utf8))
        #expect(tokens.count >= 100, "only \(tokens.count) token lines parsed")
        for token in tokens {
            let ok = token.manifestPath.map { !$0.isEmpty } ?? false || token.specCitation.map { $0.count >= 8 } ?? false
            #expect(ok, "\(token.name) (line \(token.line)) has neither `// manifest <path>` nor `// spec <citation>`")
        }
        let names = tokens.map(\.name)
        #expect(Set(names).count == names.count, "a token name is declared twice")
    }

    /// The verbatim starter (SKEL's copy, never edited) against the manifest: its 13 colours and its metrics.
    @Test func starterTokensEqualTheManifest() throws {
        let json = try Manifest.load()
        let tokens = Dictionary(TokenLine.parse(try String(contentsOf: Paths.starter, encoding: .utf8)).map { ($0.name, $0) },
                                uniquingKeysWith: { a, _ in a })
        let colours = ["canvas": "surface.canvas", "content": "surface.content", "actionCyan": "accent.actionCyan",
                       "actionAmber": "accent.actionAmber", "instrumentCyan": "accent.instrumentCyan",
                       "instrumentAmber": "accent.instrumentAmber", "displayInk": "text.display", "secondaryInk": "text.secondary",
                       "wave": "signal.wavePrimary", "waveDepth": "signal.waveSecondary", "spectrum": "signal.spectrumPrimary",
                       "spectrumDepth": "signal.spectrumSecondary", "carrier": "signal.carrier"]
        for (name, key) in colours {
            let token = try #require(tokens[name], "starter has no InstrumentPalette.\(name)")
            let expected = try #require(Manifest.rgb(Manifest.value(json, "colors/" + key)))
            #expect(token.rgb == expected, "starter \(name) \(token.rgb ?? []) ≠ manifest \(key) \(expected)")
        }
        let metrics = ["panelInset": "componentSpacing/panelInset", "panelRadius": "radii/contentPanel",
                       "controlTarget": "layout/secondaryTargetMin", "stepperHeight": "layout/stepperMinHeight",
                       "lensDiameterRatio": "gauge/lensDiameterRatio", "lensOpacity": "opacity/lensComposite"]
        for (name, path) in metrics {
            let token = try #require(tokens[name], "starter has no InstrumentMetrics.\(name)")
            let expected = try #require(Manifest.number(Manifest.value(json, path)))
            #expect(token.number == expected, "starter \(name) \(token.valueSource) ≠ manifest \(path) \(expected)")
        }
    }

    /// JF G-21: the lens composite opacity is 0.48, and exactly 1.0 under Reduce Transparency, in the manifest AND the code.
    @Test func lensOpacityIsUnchanged() throws {
        let json = try Manifest.load()
        #expect(Manifest.number(Manifest.value(json, "opacity/lensComposite")) == 0.48)
        #expect(Manifest.number(Manifest.value(json, "opacity/lensCompositeReduceTransparency")) == 1)
        let starter = try String(contentsOf: Paths.starter, encoding: .utf8)
        #expect(starter.contains("public static let lensOpacity: Double = 0.48"))
        #expect(starter.contains(".opacity(reduceTransparency ? 1 : InstrumentMetrics.lensOpacity)"))
        let palette = TokenLine.parse(try String(contentsOf: Paths.palette, encoding: .utf8))
        #expect(palette.first { $0.name == "lensCompositeReduceTransparency" }?.number == 1)
        #expect(!palette.contains { $0.name == "lensOpacity" }, "the extension must not shadow the starter's lens opacity")
    }

    @Test func everyManifestColourIsNamedExactlyOnce() throws {
        let json = try Manifest.load()
        let manifestColours = try #require(json["colors"] as? [String: Any])
        let declared = (TokenLine.parse(try String(contentsOf: Paths.starter, encoding: .utf8))
                        + TokenLine.parse(try String(contentsOf: Paths.palette, encoding: .utf8))).compactMap(\.rgb)
        for (key, entry) in manifestColours {
            let rgb = try #require(Manifest.rgb(entry))
            let count = declared.filter { $0 == rgb }.count
            #expect(count == 1, "manifest colour \(key) \(rgb) is declared \(count) times (want exactly 1)")
        }
        #expect(declared.count == manifestColours.count, "\(declared.count) Swift colours for \(manifestColours.count) manifest colours")
    }

    /// "Named from the manifest, never re-typed literals": components use the names, never `Color(red:…)` or an RGB triple.
    @Test func noComponentRetypesAColourLiteral() throws {
        let json = try Manifest.load()
        let triples = try #require(json["colors"] as? [String: Any]).values.compactMap(Manifest.rgb)
        for file in Paths.components {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("Color(red:"), "\(file.lastPathComponent) re-types a colour literal; use an InstrumentPalette token")
            for rgb in triples {
                let literal = rgb.map { String($0) }.joined(separator: ", ")
                #expect(!text.contains(literal), "\(file.lastPathComponent) contains the manifest triple \(literal)")
            }
        }
    }
}
