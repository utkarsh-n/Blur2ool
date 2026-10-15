import Foundation
import Metal
import BlurCore
import BlurGPU

// OWNER: GPUCHECK. Shader sources, their manifest (ARCHITECTURE §6.6), the library's function inventory, and the static
// half of the dispatch audit (§4.4 rule 1: dispatchThreadgroups only through GPUContext.dispatch2D, never dispatchThreads).

enum GPUCheckSetupError: Error, CustomStringConvertible {
    case shaders(String)
    case compile(String)
    case device(String)
    var description: String {
        switch self {
        case .shaders(let s): "shader sources: \(s)"
        case .compile(let s): "compile: \(s)"
        case .device(let s): "device: \(s)"
        }
    }
}

enum GPUCheckShaders {
    /// B2Shared.h and every `*.metal` in `directory` except SwiftUI shaders — the same selection as
    /// `ParityRunner.compileLibrary`, so the manifest here and the compiled source agree by construction.
    static func read(_ directory: URL) throws -> (header: String, files: [(name: String, text: String)]) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw GPUCheckSetupError.shaders("\(directory.path) is not a directory")
        }
        let headerURL = directory.appendingPathComponent("B2Shared.h")
        guard let header = try? String(contentsOf: headerURL, encoding: .utf8) else {
            throw GPUCheckSetupError.shaders("cannot read \(headerURL.path)")
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".metal") }
        guard !names.isEmpty else { throw GPUCheckSetupError.shaders("no .metal files in \(directory.path)") }
        var files: [(name: String, text: String)] = []
        for name in names {
            guard let text = try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8) else {
                throw GPUCheckSetupError.shaders("cannot read \(name) as UTF-8")
            }
            if !text.contains("SwiftUI/SwiftUI.h") { files.append((name, text)) }
        }
        return (header, files)
    }

    static func manifest(_ directory: URL) throws -> ShaderManifest {
        let sources = try read(directory)
        return ShaderManifest.make(header: sources.header, files: sources.files)
    }

    struct ManifestComparison {
        var matching: [String] = []
        var differing: [String] = []
        /// In the sources, not listed in the bundle's manifest.
        var unlisted: [String] = []
        /// Listed in the bundle's manifest, absent from the sources.
        var missing: [String] = []
        var matches: Bool { differing.isEmpty && unlisted.isEmpty && missing.isEmpty && !matching.isEmpty }
        var line: String {
            matches ? "manifest: \(matching.count) files, every SHA-256 matches"
                : "manifest MISMATCH: differing [\(differing.joined(separator: ", "))] · not in the manifest [\(unlisted.joined(separator: ", "))]"
                  + " · missing from the sources [\(missing.joined(separator: ", "))] · \(matching.count) matching"
        }
    }

    /// Compares per-file SHA-256s with a bundle's `ShaderManifest.json` (`{"files": {"<name>": "<sha256>"}}`).
    static func compare(_ manifest: ShaderManifest, withManifestAt url: URL) throws -> ManifestComparison {
        guard let data = try? Data(contentsOf: url),
              let listed = (try? JSONDecoder().decode([String: [String: String]].self, from: data))?["files"] else {
            throw GPUCheckSetupError.shaders("cannot read a {\"files\": {…}} manifest at \(url.path)")
        }
        var result = ManifestComparison()
        for (name, sha) in manifest.files.sorted(by: { $0.key < $1.key }) {
            switch listed[name] {
            case .none: result.unlisted.append(name)
            case .some(let other) where other == sha: result.matching.append(name)
            case .some: result.differing.append(name)
            }
        }
        result.missing = listed.keys.filter { manifest.files[$0] == nil }.sorted()
        return result
    }

    /// The B2Common functions every render may use (ARCHITECTURE §6.5).
    static let commonFunctions = ["b2_common_fullscreen_vs", "b2_common_colour_fs", "b2_common_window_fs",
                                  "b2_common_downsample2x_fs", "b2_common_copy_fs"]

    /// Functions a pipeline declares that the library lacks, per factory label.
    @MainActor
    static func missingFunctions(_ library: any MTLLibrary, factories: [GPUPipelineFactory]) -> (common: [String], perFactory: [String: [String]]) {
        let available = Set(library.functionNames)
        let common = commonFunctions.filter { !available.contains($0) }
        var perFactory: [String: [String]] = [:]
        for factory in factories {
            let missing = factory.make().functionNames.filter { !available.contains($0) }
            if !missing.isEmpty { perFactory["\(factory.blur)/\(factory.variant)"] = missing }
        }
        return (common, perFactory)
    }
}

/// The static half of the dispatch audit: Swift sources that encode compute work must dispatch only through
/// `GPUContext.dispatch2D` (ARCHITECTURE §4.4 rule 1, §6.3 rule 8). Scans `Sources/BlurGPU` and `App` under `root`
/// for direct `dispatchThreadgroups(` / `dispatchThreads(` calls outside GPUContext.swift. Comment lines are ignored.
enum GPUCheckStaticDispatchAudit {
    struct Result {
        var scannedFiles = 0
        var violations: [String] = []
        var available: Bool { scannedFiles > 0 }
    }

    static func scan(root: URL) -> Result {
        var result = Result()
        let fm = FileManager.default
        for folder in ["Sources/BlurGPU", "App"] {
            let base = root.appendingPathComponent(folder)
            guard let walker = fm.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let relative = url.path.hasPrefix(base.path + "/") ? folder + url.path.dropFirst(base.path.count) : url.path
                if relative.hasSuffix("BlurGPU/Core/GPUContext.swift") { continue }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                result.scannedFiles += 1
                for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    let code = line.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
                    if code.contains(".dispatchThreadgroups(") || code.contains(".dispatchThreads(") {
                        result.violations.append("\(relative):\(n + 1): \(line.trimmingCharacters(in: .whitespaces))")
                    }
                }
            }
        }
        return result
    }
}
