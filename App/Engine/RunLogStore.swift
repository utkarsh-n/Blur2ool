import Foundation
import Observation
import BlurCore

// OWNER: ENGINE (frozen public API, ARCHITECTURE §5.9). The Run log (SPEC §4.7 Runs; JF G-19): every settled display Run,
// timing, parity, trace, fingerprint, calibration and device-probe Run, persisted as JSON in Application Support and
// exportable (`Export JSON`, ISO 8601 dates) so device numbers can replace research's Mac figures. Reading and writing
// never block the main actor: the file is decoded in a detached task at launch and written by a debounced, serialised
// detached writer. Non-finite numbers (report-only tolerances are ∞) are encoded as strings (RunLogCoding), because
// Foundation's default encoder throws on them and would silently drop the whole log. `deviceProbes` and `calibrations`
// (newest per kind / subject) feed LiveFacts; device probes from another OS build are not reused (they are "cached with
// OS build and date", SPEC §13.2), so a sub-texel rule measured before an iOS update never judges parity after it.

@MainActor @Observable
public final class RunLogStore {
    public private(set) var runs: [Run] = []
    /// True once the persisted log has been read (or there was none).
    public private(set) var isLoaded = false
    /// The OS build of this launch (`kern.osversion`); device probes from other builds are ignored. nil = accept all.
    public var currentOSBuild: String?
    /// Newest Runs kept (oldest dropped first).
    public static let capacity = 1_000

    @ObservationIgnored private let file: URL?
    @ObservationIgnored private var writeTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    public init(directory: URL? = nil) {
        file = directory?.appendingPathComponent("RunLog.json")
        guard let file else { isLoaded = true; return }
        loadTask = Task { [weak self] in
            let loaded = await Task.detached(priority: .utility) { () -> [Run] in
                guard let data = try? Data(contentsOf: file) else { return [] }
                return (try? RunLogCoding.storeDecoder().decode([Run].self, from: data)) ?? []
            }.value
            guard let self else { return }
            // Runs appended while the file was being read are newer: keep them after the loaded ones.
            let appendedMeanwhile = !self.runs.isEmpty
            self.runs = Self.trimmed(loaded + self.runs)
            self.isLoaded = true
            if appendedMeanwhile { self.schedulePersist() }
        }
    }

    /// Awaits the launch-time read of the persisted log (tests; the Runs tab shows whatever is there meanwhile).
    public func waitUntilLoaded() async { await loadTask?.value }

    public func append(_ run: Run) {
        runs.append(run)
        runs = Self.trimmed(runs)
        schedulePersist()
    }
    public func delete(_ ids: Set<UUID>) {
        runs.removeAll { ids.contains($0.id) }
        schedulePersist()
    }
    /// Settings › Erase measurements: removes every MEASURED record (timing, parity, calibration, device probes,
    /// fingerprint shapes); settled display and trace Runs stay, because they hold what was rendered, not a measurement.
    public func eraseMeasurements() {
        runs.removeAll { [.timing, .parity, .calibration, .probe, .fingerprint].contains($0.kind) }
        schedulePersist()
    }
    public func exportJSON() throws -> Data { try RunLogCoding.exportEncoder().encode(runs) }

    /// Newest per kind / subject, for LiveFacts.
    public var deviceProbes: [DeviceProbeResult] {
        var newest: [DeviceProbeKind: DeviceProbeResult] = [:]
        for run in runs {
            guard let p = run.deviceProbe else { continue }
            if let build = currentOSBuild, !p.device.osBuild.isEmpty, p.device.osBuild != build { continue }
            newest[p.kind] = p
        }
        return DeviceProbeKind.allCases.compactMap { newest[$0] }
    }
    public var calibrations: [CalibrationResult] {
        var newest: [CalibrationSubject: CalibrationResult] = [:]
        for run in runs { if let c = run.calibration { newest[c.request.subject] = c } }
        return CalibrationSubject.allCases.compactMap { newest[$0] }
    }
    /// The newest settled timing of exactly this configuration (the probe does not change timing, so it is ignored).
    public func latestTimed(for configuration: RenderConfiguration) -> Run? {
        let key = Self.timingKey(configuration)
        return runs.last { $0.kind == .timing && $0.timing != nil && Self.timingKey($0.configuration) == key }
    }
    /// Runs of one kind, newest last.
    public func runs(of kind: RunKind) -> [Run] { runs.filter { $0.kind == kind } }

    /// Writes now (scene going to the background); returns when the file is on disk.
    public func flush() async {
        debounceTask?.cancel(); debounceTask = nil
        startWrite()
        await writeTask?.value
    }

    // MARK: Persistence

    static func timingKey(_ configuration: RenderConfiguration) -> RenderConfiguration {
        var c = configuration
        c.probe = .zero
        return c
    }
    private static func trimmed(_ runs: [Run]) -> [Run] { runs.count > capacity ? Array(runs.suffix(capacity)) : runs }

    private func schedulePersist() {
        guard file != nil else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.startWrite()
        }
    }

    private func startWrite() {
        guard let file, isLoaded else { return }
        let snapshot = runs, previous = writeTask
        writeTask = Task.detached(priority: .utility) {
            await previous?.value
            guard let data = try? RunLogCoding.storeEncoder().encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }
}
