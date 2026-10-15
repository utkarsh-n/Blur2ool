import Foundation
import BlurCore
import BlurGPU

// OWNER: GPUCHECK. The per-case report line, the summary tables and the JSON of ParityOutcome (ARCHITECTURE §3.2 item 6).
// Every number printed is what the run MEASURED on this Mac's GPU against BlurCore's CPU reference; nothing is estimated.

enum GPUCheckFormat {
    static func sci(_ x: Double) -> String { x.isFinite ? String(format: "%.2e", x) : (x.isNaN ? "nan" : (x > 0 ? "inf" : "-inf")) }
    static func signed(_ x: Double) -> String { x.isFinite ? String(format: "%+.2e", x) : sci(x) }
    static func num(_ x: Double) -> String {
        guard x.isFinite else { return sci(x) }
        return x == x.rounded() ? String(format: "%.0f", x) : String(format: "%.2f", x)
    }
    static func grouped(_ n: Int) -> String {
        let s = String(abs(n))
        var out = ""
        for (i, ch) in s.reversed().enumerated() { if i > 0 && i % 3 == 0 { out.append(",") }; out.append(ch) }
        return (n < 0 ? "-" : "") + String(out.reversed())
    }
    static func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }
    static func lpad(_ s: String, _ n: Int) -> String { s.count >= n ? s : String(repeating: " ", count: n - s.count) + s }
}

/// One judged case of the run.
struct GPUCheckRecord {
    var outcome: ParityOutcome
    var group: String
    var className: String
    var dispatch: GPUCheckEncodeAudit.Verdict?
    var isCanary = false
}

enum GPUCheckReport {
    /// `PASS|FAIL <blur>/<variant> @<size>: <case> · maxAbs · rms · lsb8 · ulp16 · traced=untraced · final=out`, then the
    /// class, the compared region, GPU ms, trace records, the dispatch audit, and the reason when it failed.
    static func line(_ r: GPUCheckRecord, status: String? = nil) -> String {
        let o = r.outcome, F = GPUCheckFormat.self
        var parts = ["\(status ?? (o.passed ? "PASS" : "FAIL")) \(o.caseName)"]
        if let s = o.evaluation?.stats {
            parts += ["maxAbs \(F.sci(s.maxAbs))", "rms \(F.sci(s.rms))", "lsb8 \(F.num(s.maxLSB8))", "ulp16 \(F.num(s.maxULP16))"]
        } else {
            parts += ["maxAbs –", "rms –", "lsb8 –", "ulp16 –"]
        }
        parts.append("traced=untraced " + (o.traced.map { $0.differingWords == 0 ? "yes" : "NO (\(F.grouped($0.differingWords)) fp16 words differ)" } ?? "n/a"))
        parts.append("final=out " + (o.traced.map { $0.finalSumMatchesOutput ? "yes" : "NO" } ?? "n/a"))
        parts.append(r.className)
        if let region = o.comparedRegions { parts.append(region) }
        if let ms = o.gpuMilliseconds { parts.append(String(format: "GPU %.2f ms", ms)) }
        if let t = o.traced {
            parts.append("overflow \(t.overflow) · final records \(t.missingFinalRecord ? "MISSING" : "every pass") · taps \(t.tapsPerTracedPass.map(String.init).joined(separator: "+"))")
        }
        if let d = r.dispatch, !d.summary.isEmpty { parts.append(d.summary) }
        if let e = o.evaluation, !e.passed {
            parts.append("failing \(F.grouped(e.failingChannels)) ch · worst excess \(F.signed(e.worstExcess)) over the allowance")
        }
        if let f = o.failure { parts.append(f) }
        return parts.joined(separator: " · ")
    }

    /// One row per factory (and seed): cases, passes, failures, worst ulp16 / maxAbs, classes, summed GPU ms.
    static func summaryTable(_ records: [GPUCheckRecord]) -> String {
        struct Row { var cases = 0, passed = 0, failed = 0, worstULP = 0.0, worstAbs = 0.0, ms = 0.0, classes: [String] = [] }
        var order: [String] = []
        var rows: [String: Row] = [:]
        for r in records {
            if rows[r.group] == nil { order.append(r.group); rows[r.group] = Row() }
            rows[r.group]!.cases += 1
            if r.outcome.passed { rows[r.group]!.passed += 1 } else { rows[r.group]!.failed += 1 }
            if let s = r.outcome.evaluation?.stats {
                rows[r.group]!.worstULP = max(rows[r.group]!.worstULP, s.maxULP16.isFinite ? s.maxULP16 : 0)
                rows[r.group]!.worstAbs = max(rows[r.group]!.worstAbs, s.maxAbs.isFinite ? s.maxAbs : 0)
            }
            rows[r.group]!.ms += r.outcome.gpuMilliseconds ?? 0
            if !rows[r.group]!.classes.contains(r.className) { rows[r.group]!.classes.append(r.className) }
        }
        let F = GPUCheckFormat.self
        let width = max(24, (order.map(\.count).max() ?? 0) + 2)
        var lines = [F.pad("blur/variant", width) + F.lpad("cases", 6) + F.lpad("pass", 6) + F.lpad("fail", 6)
                     + F.lpad("worst ulp16", 13) + F.lpad("worst maxAbs", 14) + F.lpad("GPU ms", 10) + "  classes"]
        var total = Row()
        for g in order {
            let r = rows[g]!
            total.cases += r.cases; total.passed += r.passed; total.failed += r.failed; total.ms += r.ms
            total.worstULP = max(total.worstULP, r.worstULP); total.worstAbs = max(total.worstAbs, r.worstAbs)
            lines.append(F.pad(g, width) + F.lpad("\(r.cases)", 6) + F.lpad("\(r.passed)", 6) + F.lpad("\(r.failed)", 6)
                         + F.lpad(F.num(r.worstULP), 13) + F.lpad(F.sci(r.worstAbs), 14) + F.lpad(String(format: "%.1f", r.ms), 10)
                         + "  " + r.classes.joined(separator: ", "))
        }
        lines.append(F.pad("TOTAL", width) + F.lpad("\(total.cases)", 6) + F.lpad("\(total.passed)", 6) + F.lpad("\(total.failed)", 6)
                     + F.lpad(F.num(total.worstULP), 13) + F.lpad(F.sci(total.worstAbs), 14) + F.lpad(String(format: "%.1f", total.ms), 10))
        return lines.joined(separator: "\n")
    }

    /// JSON array of ParityOutcome. Non-finite numbers (reportOnly allowances, empty comparisons) are written as the
    /// strings "inf", "-inf" and "nan" so the file always parses.
    static func writeJSON(_ outcomes: [ParityOutcome], to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        try encoder.encode(outcomes).write(to: URL(fileURLWithPath: path))
    }

    /// `out.json` → `out.mutations.json`.
    static func mutationsPath(_ json: String) -> String {
        json.hasSuffix(".json") ? String(json.dropLast(5)) + ".mutations.json" : json + ".mutations.json"
    }
}

/// The mutation results: one verdict per (factory, size, class, specimen, defect).
struct GPUCheckMutationResult {
    enum Verdict: String { case caught = "FAIL-as-expected", survived = "PASS — MUTATION SURVIVED", controlFailed = "CONTROL FAILED",
                           notApplicable = "N/A", error = "ERROR" }
    var factory: String
    var size: Int
    var className: String
    var specimen: String
    var kind: GPUCheckMutationKind
    var verdict: Verdict
    var detail: String
    var outcome: ParityOutcome?
}

enum GPUCheckMutationReport {
    static func line(_ m: GPUCheckMutationResult) -> String {
        let F = GPUCheckFormat.self
        var parts = ["\(m.verdict.rawValue) mutation \(m.kind.label) · \(m.className) · \(m.factory) @\(m.size) · \(m.specimen)"]
        if let e = m.outcome?.evaluation {
            parts.append("maxAbs \(F.sci(e.stats.maxAbs)) · ulp16 \(F.num(e.stats.maxULP16)) · lsb8 \(F.num(e.stats.maxLSB8))")
            parts.append(e.passed ? "every channel within the allowance (closest: \(F.signed(e.worstExcess)))"
                                  : "failing \(F.grouped(e.failingChannels)) ch · worst excess \(F.signed(e.worstExcess))")
        }
        if let region = m.outcome?.comparedRegions { parts.append(region) }
        if !m.detail.isEmpty { parts.append(m.detail) }
        if m.verdict == .survived { parts.append("GATE FAILURE: the class is too loose here") }
        return parts.joined(separator: " · ")
    }

    /// Class × defect × specimen: caught/judged per cell, with S (survived), E (error), C (control failed), N (n/a).
    static func table(_ results: [GPUCheckMutationResult]) -> (text: String, uncovered: [String], survived: Int, errors: Int) {
        let F = GPUCheckFormat.self
        let specimens = GPUCheckMutationSpecimen.all.map(\.label)
        var classes: [String] = []
        for r in results where !classes.contains(r.className) { classes.append(r.className) }
        let columns = GPUCheckMutationKind.allCases.flatMap { k in specimens.map { (k, $0) } }
        let header = F.pad("class", 22) + columns.map { F.lpad("\($0.0.label) · \($0.1 == specimens[0] ? "NC+4" : "SE45")", 22) }.joined()
        var lines = [header]
        var uncovered: [String] = []
        var survived = 0, errors = 0
        for c in classes {
            var row = F.pad(c, 22)
            for (kind, specimen) in columns {
                let cell = results.filter { $0.className == c && $0.kind == kind && $0.specimen == specimen }
                let caught = cell.filter { $0.verdict == .caught }.count
                let s = cell.filter { $0.verdict == .survived }.count
                let e = cell.filter { $0.verdict == .error }.count
                let cf = cell.filter { $0.verdict == .controlFailed }.count
                let na = cell.filter { $0.verdict == .notApplicable }.count
                survived += s; errors += e
                var text = "\(caught)/\(caught + s + e)"
                if s > 0 { text += " S\(s)" }
                if e > 0 { text += " E\(e)" }
                if cf > 0 { text += " C\(cf)" }
                if na > 0 { text += " N\(na)" }
                if caught == 0 && s == 0 && e == 0 && !cell.isEmpty {
                    text += " UNCOVERED"
                    uncovered.append("\(c) · \(kind.label) · \(specimen)")
                }
                row += F.lpad(text, 22)
            }
            lines.append(row)
        }
        lines.append("cells: caught/judged · S survived (gate failure) · E error · C control failed (not judged) · N not applicable · "
                     + "UNCOVERED = no factory of this class could be judged for this defect")
        return (lines.joined(separator: "\n"), uncovered, survived, errors)
    }
}
