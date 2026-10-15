import Foundation
import Metal
import BlurCore
import BlurGPU

// OWNER: GPUCHECK (seed written by SKEL). The Mac GPU↔CPU parity CLI (ARCHITECTURE §3.2). Runs every registered parity
// case through ParityRunner (and the MRT seed of FAM-F6) and prints one line per case; exit 0 only if every case passes,
// 1 if any fails, 2 for a compile or setup error.
// usage: blur-gpucheck [--shaders <dir>] [--metallib <file.metallib>] [--filter <text>[,<text>…]] [--size <n>] [--safe-math]
//                      [--apple2-limits] [--json <file>] [--list] [--print-sha] [--manifest <ShaderManifest.json>]
// TODO(GPUCHECK): --regions, the mutation cases (§3.2 item 5, §7 rule 9), the report table, encodeLog-based dispatch
// assertions per pass (the seed counts dispatch2D calls against the plan's compute passes).

let arguments = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}
let shaderDirectory = URL(fileURLWithPath: option("--shaders") ?? "App/GPU/Shaders")
let filters = option("--filter").map { $0.split(separator: ",").map(String.init) }   // comma-separated alternatives
let sizes = option("--size").flatMap(Int.init).map { [$0] } ?? [256, 894]
func included(_ name: String) -> Bool { filters.map { f in f.contains { name.contains($0) } } ?? true }

/// The shader texts and their manifest, read without compiling (the combined SHA is ShaderManifest.assemble's).
func readManifest(_ directory: URL) throws -> ShaderManifest {
    let header = try String(contentsOf: directory.appendingPathComponent("B2Shared.h"), encoding: .utf8)
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".metal") }
    var files: [(name: String, text: String)] = []
    for name in names {
        let text = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
        if !text.contains("SwiftUI/SwiftUI.h") { files.append((name, text)) }
    }
    return ShaderManifest.make(header: header, files: files)
}

do {
    if arguments.contains("--print-sha") {
        let manifest = try readManifest(shaderDirectory)
        if let path = option("--manifest") {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let listed = try JSONDecoder().decode([String: [String: String]].self, from: data)["files"] ?? [:]
            let mismatched = listed.filter { manifest.files[$0.key] != $0.value }.keys.sorted()
            let missing = manifest.files.keys.filter { listed[$0] == nil }.sorted()
            print(mismatched.isEmpty && missing.isEmpty
                  ? "manifest: \(listed.count) files, every SHA-256 matches"
                  : "manifest MISMATCH: \(mismatched.joined(separator: ", ")) missing: \(missing.joined(separator: ", "))")
        }
        print("SHA \(manifest.combinedSHA256)")
        exit(0)
    }
    guard let device = MTLCreateSystemDefaultDevice() else { print("no Metal device"); exit(2) }
    let started = Date()
    let library: any MTLLibrary
    let manifest: ShaderManifest
    if let metallib = option("--metallib") {
        library = try device.makeLibrary(URL: URL(fileURLWithPath: metallib))
        manifest = try readManifest(shaderDirectory)
        print("loaded \(metallib) (per-file offline compile, \(library.functionNames.count) functions) in \(String(format: "%.2f", Date().timeIntervalSince(started))) s · combined SHA-256 of the sources \(manifest.combinedSHA256)")
    } else {
        let compiled = try ParityRunner.compileLibrary(device: device, shaderDirectory: shaderDirectory, safeMath: arguments.contains("--safe-math"))
        library = compiled.library
        manifest = compiled.manifest
        print("compiled \(compiled.source.utf8.count) bytes of MSL as one translation unit in \(String(format: "%.2f", Date().timeIntervalSince(started))) s · combined SHA-256 \(manifest.combinedSHA256)")
    }
    let context = try GPUContext(device: device, library: library, manifest: manifest,
                                 mathMode: arguments.contains("--safe-math") ? "safe" : "fast",
                                 forceApple2Limits: arguments.contains("--apple2-limits"), recordsDispatches: true)
    print("device \(device.name) · \(context.facts.familyName) · max threads \(context.facts.maxThreadsPerThreadgroup) · threadgroup memory \(context.facts.maxThreadgroupMemoryLength) B")
    try await context.prepareCommonPipelines()
    var outcomes: [ParityOutcome] = []
    func report(_ outcome: ParityOutcome, extra: String = "") {
        let e = outcome.evaluation
        let traced = outcome.traced.map { $0.differingWords == 0 ? "yes" : "NO (\($0.differingWords) words)" } ?? "n/a"
        let final = outcome.traced.map { $0.finalSumMatchesOutput ? "yes" : "NO" } ?? "n/a"
        let records = outcome.traced.map { "overflow \($0.overflow) · final records \($0.missingFinalRecord ? "MISSING" : "every pass") · taps \($0.tapsPerTracedPass.map(String.init).joined(separator: "+"))" } ?? ""
        print(String(format: "%@ %@ maxAbs %.2e rms %.2e lsb8 %.0f ulp16 %.2f traced=untraced %@ final=out %@ %@%@%@",
                     outcome.passed ? "PASS" : "FAIL", outcome.caseName, e?.stats.maxAbs ?? .nan, e?.stats.rms ?? .nan,
                     e?.stats.maxLSB8 ?? .nan, e?.stats.maxULP16 ?? .nan, traced, final, records, extra,
                     outcome.failure.map { " · " + $0 } ?? ""))
    }
    for factory in GPUPipelineRegistry.factories {
        for size in sizes {
            for parityCase in factory.parityCases(size) {
                let name = "\(factory.blur)/\(factory.variant) @\(size): \(parityCase.name)"
                guard included(name) else { continue }
                if arguments.contains("--list") { print(name); continue }
                // Every compute pass must go through GPUContext.dispatch2D (§4.4): count the dispatches this case made.
                let before = context.dispatchLog.count
                var outcome = await ParityRunner.run(parityCase, factory: factory, context: context)
                outcome.caseName = name
                var extra = ""
                if let op = BlurRegistry.op(parityCase.configuration.blur) {
                    let compute = op.passPlan(parityCase.configuration.operatorRequest).passes.filter { $0.kind == .compute }.count
                    if compute > 0 {
                        let renders = 1 + (parityCase.checkTraced ? parityCase.probes.count : 0)
                        let made = context.dispatchLog.count - before
                        extra = " · dispatch2D \(made)/\(compute * renders)"
                        if made != compute * renders && outcome.failure == nil {
                            outcome.failure = "compute passes bypassed dispatch2D (\(made) of \(compute * renders) dispatches logged)"
                        }
                        if let last = context.dispatchLog.last { extra += " (\(last))" }
                    }
                }
                outcomes.append(outcome)
                report(outcome, extra: extra)
            }
        }
    }
    // Seeds that are not registered pipelines (ARCHITECTURE §9.1 item 5): FAM-F6's two-attachment MRT pass.
    for size in sizes {
        let names = F6HexLineSeed.cases(size).flatMap { ["\(F6HexLineSeed.label) @\(size): \($0.name) · T1", "\(F6HexLineSeed.label) @\(size): \($0.name) · T2"] }
        if arguments.contains("--list") { names.filter(included).forEach { print($0) }; continue }
        for outcome in await F6HexLineSeed.parityOutcomes(windowSize: size, context: context, include: included) {
            outcomes.append(outcome)
            report(outcome)
        }
    }
    if arguments.contains("--list") { exit(0) }
    if let json = option("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(outcomes).write(to: URL(fileURLWithPath: json))
    }
    let failed = outcomes.filter { !$0.passed }.count
    print("\(outcomes.count - failed) passed, \(failed) failed · \(String(format: "%.1f", Date().timeIntervalSince(started))) s\(arguments.contains("--apple2-limits") ? " · Apple2 limits forced" : "")")
    exit(failed == 0 && !outcomes.isEmpty ? 0 : 1)
} catch {
    print("blur-gpucheck: \(error)")
    exit(2)
}
