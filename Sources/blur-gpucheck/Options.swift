import Foundation

// OWNER: GPUCHECK. Command-line options of the Mac GPU↔CPU parity CLI (ARCHITECTURE §3.2). Parsing is strict: an unknown
// option or a missing value is a setup error (exit 2), so a typo never silently runs a smaller gate.

enum GPUCheckRegions: Equatable, Sendable {
    /// ParityRegionPolicy.standard: the whole window at ≤ 256, 128 × 128 crops at the probes above (review fix E-8).
    case standard
    case full
    case crops(side: Int)
}

enum GPUCheckMutationMode: Equatable, Sendable {
    case off
    /// The registered parity cases, then the mutation cases (ARCHITECTURE §3.2 item 5, §7 rule 9).
    case with
    /// Only the mutation cases (and their unmutated controls).
    case only
}

enum GPUCheckMutationScope: String, Sendable {
    /// Every registered factory × every judged tolerance class it publishes (default; what INTEGRATE runs).
    case every
    /// The first registered factory per tolerance class (a quick look).
    case representative
}

struct GPUCheckUsageError: Error, CustomStringConvertible {
    let description: String
}

struct GPUCheckOptions: Sendable {
    var shaders = "App/GPU/Shaders"
    var metallib: String?
    var filters: [String]?
    var sizes = [256, 894]
    var safeMath = false
    var apple2Limits = false
    var regions = GPUCheckRegions.standard
    var json: String?
    var list = false
    var printSHA = false
    var manifest: String?
    var mutations = GPUCheckMutationMode.off
    var mutationScope = GPUCheckMutationScope.every
    var canary = false
    var seeds = true
    var help = false

    /// True when a case name passes `--filter` (comma-separated alternatives, plain substrings).
    func includes(_ name: String) -> Bool {
        guard let filters else { return true }
        return filters.contains { name.contains($0) }
    }

    static func parse(_ arguments: [String]) throws -> GPUCheckOptions {
        var o = GPUCheckOptions()
        var i = 0
        func value(_ name: String) throws -> String {
            guard i + 1 < arguments.count, !arguments[i + 1].hasPrefix("--") else {
                throw GPUCheckUsageError(description: "\(name) needs a value (see --help)")
            }
            i += 1
            return arguments[i]
        }
        while i < arguments.count {
            let a = arguments[i]
            switch a {
            case "--shaders": o.shaders = try value(a)
            case "--metallib": o.metallib = try value(a)
            case "--filter":
                let parts = try value(a).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                guard !parts.isEmpty else { throw GPUCheckUsageError(description: "--filter needs at least one non-empty text") }
                o.filters = (o.filters ?? []) + parts
            case "--size":
                let text = try value(a)
                let sizes = text.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                guard !sizes.isEmpty, sizes.count == text.split(separator: ",").count, sizes.allSatisfy({ $0 >= 16 && $0 <= 4096 }) else {
                    throw GPUCheckUsageError(description: "--size takes window sides 16…4096, comma-separated (got '\(text)')")
                }
                o.sizes = sizes
            case "--safe-math": o.safeMath = true
            case "--apple2-limits": o.apple2Limits = true
            case "--regions":
                let text = try value(a)
                switch text {
                case "standard": o.regions = .standard
                case "full": o.regions = .full
                case "crops": o.regions = .crops(side: 128)
                default:
                    if text.hasPrefix("crops:"), let side = Int(text.dropFirst(6)), side >= 8 { o.regions = .crops(side: side) }
                    else { throw GPUCheckUsageError(description: "--regions takes full, crops, crops:<side> or standard (got '\(text)')") }
                }
            case "--json": o.json = try value(a)
            case "--list": o.list = true
            case "--print-sha": o.printSHA = true
            case "--manifest": o.manifest = try value(a)
            case "--mutations": o.mutations = o.mutations == .only ? .only : .with
            case "--mutations-only": o.mutations = .only
            case "--mutation-scope":
                let text = try value(a)
                guard let scope = GPUCheckMutationScope(rawValue: text) else {
                    throw GPUCheckUsageError(description: "--mutation-scope takes every or representative (got '\(text)')")
                }
                o.mutationScope = scope
            case "--canary": o.canary = true
            case "--no-seeds": o.seeds = false
            case "--help", "-h": o.help = true
            default: throw GPUCheckUsageError(description: "unknown option '\(a)' (see --help)")
            }
            i += 1
        }
        return o
    }

    static let help = """
    blur-gpucheck — the Mac GPU↔CPU parity gate of Blur2ool (ARCHITECTURE §3.2, §7). Runs every registered
    GPUPipelineFactory × size × parityCases(size) on this Mac's GPU exactly as the app renders (window pass × 2^EV,
    colour pre-pass, pipeline, colour post-pass, half-rounded input) and compares with BlurCore's CPU reference.

    usage: blur-gpucheck [--shaders <dir>] [--metallib <file.metallib>] [--filter <text>[,<text>…]] [--size <n>[,<n>…]]
                         [--safe-math] [--apple2-limits] [--regions full|crops|crops:<side>|standard] [--json <out.json>]
                         [--list] [--print-sha] [--manifest <ShaderManifest.json>]
                         [--mutations | --mutations-only] [--mutation-scope every|representative] [--canary] [--no-seeds]

      --shaders <dir>      shader sources (default App/GPU/Shaders): B2Shared.h + every *.metal (SwiftUI shaders skipped),
                           compiled at runtime as ONE translation unit (ShaderManifest.assemble), MSL 4.1, fast math.
      --metallib <file>    load this library instead: the app's offline per-file compile (Tools/build.sh metal-check writes
                           $B2_BUILD_DIR/metal/macos.metallib with Xcode's fast-math flags). --shaders still names the
                           sources whose combined SHA-256 is printed.
      --filter <a,b>       run only cases whose name "<blur>/<variant> @<size>: <case>" contains one of the texts.
      --size <n[,n]>       window sides (default 256,894). At ≤ 256 the whole window is compared; above, 128 × 128
                           crops at the case's probes (ParityRegionPolicy.standard), unless --regions says otherwise.
      --safe-math          compile with mathMode .safe and precise fp32 functions (runtime compile only).
      --apple2-limits      force Apple2 limits (512 threads per threadgroup, 16,384 B threadgroup memory): dispatch2D
                           clamps threadgroups and throws budgetExceeded for oversized tiles, and every dispatch the
                           log records is checked against those limits. The hold-safe stand-in for the Simulator.
      --regions <r>        full = the whole window at every size; crops = 128² crops at the probes; standard (default).
      --json <out.json>    write the regular cases as a JSON array of ParityOutcome (non-finite numbers as strings
                           "inf"/"-inf"/"nan"); mutation cases go to <out>.mutations.json in the same format.
      --list               list every factory × size × case (and, with --mutations, every mutation case) and exit 0.
      --print-sha          print the combined SHA-256 of the sources and exit (no GPU needed). With --manifest, also
                           compare every per-file SHA-256 with a bundle's ShaderManifest.json (exit 1 on a mismatch).
      --manifest <json>    compare the per-file hashes of --shaders with a bundle's ShaderManifest.json (any mode).
      --mutations          after the regular cases, run the MUTATION cases (ARCHITECTURE §3.2 item 5, §7 rule 9): for
                           every judged tolerance class each factory publishes, a test-only factory wraps the real
                           pipeline with ONE deliberate defect — σ × 1.01 (wrong weights: the primary size parameter
                           × 1.01; integers that round back move by one), dropped tap (the last pass's smallest-weight
                           tap, taken from the tables the GPU received, subtracted on the GPU), skipped pass (the last
                           pass replaced by an identity copy of its input) — on Night City at +4 EV and on step edges
                           (45°, so that every axis-aligned pass crosses the edge). Each runs after an unmutated control
                           of the same configuration. Every mutation must FAIL ("FAIL-as-expected"); one that passes is
                           a gate failure (the class is too loose there).
      --mutations-only     only the mutation cases and their controls.
      --mutation-scope s   every (default): every factory × class; representative: the first factory per class.
      --canary             add a test-only factory whose CPU reference is deliberately wrong (the primary parameter × 1.25
                           in the reference only). Its case must FAIL, so a run with --canary exits 1: proof that the
                           gate can fail. Case names start with "canary".
      --no-seeds           skip the non-registered seeds (FAM-F6's two-attachment MRT seed).

    Report: one line per case — PASS|FAIL <blur>/<variant> @<size>: <case> · maxAbs · rms · lsb8 · ulp16 ·
    traced=untraced · final=out — then the class, compared region, GPU ms (MEASURED on this Mac), trace records and the
    dispatch audit (every compute pass must go through GPUContext.dispatch2D: compute encoders in the recorder's
    encodeLog vs dispatches in the context's dispatchLog, per encode), and a summary table.
    Exit status: 0 only if every case passes (and, with --mutations, every mutation fails as expected); 1 if any case
    fails, a mutation survives or errors, the dispatch audit fails or a manifest differs; 2 for a compile or setup error
    (unreadable or uncompilable shaders, no Metal device, bad options).
    """
}
