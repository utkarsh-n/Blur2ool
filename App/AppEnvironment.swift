import Foundation
import Observation
import Metal
import UIKit
import os
import BlurCore
import BlurGPU

// OWNER: ENGINE (ARCHITECTURE §5.9, §9.1 item 4, §11.1). Builds everything once at launch, without blocking the main
// thread on GPU work: GPUContext(device, makeDefaultLibrary(), ShaderManifest.load(<bundle>/ShaderSources)); the GPU
// services (GPUServices.timing = TimingService(), probes = DeviceProbeService(), shapes = ShapeService(),
// appleTwins = AppleTwinRunner()); settings, Run log, specimen store, RenderCoordinator, PresentRenderer, BenchModel and
// CalibrationService, wired together (the calibration idle-gate hooks, device probes for in-app parity, the launch time
// for "nothing measures in the first 10 s", the device stamp). Logs the B2BuildStamp (`B2BuildStamp <stamp>`, os_log
// category "launch") and writes it to Library/Caches/B2BuildStamp.txt, where `Tools/build.sh device-session` reads it.
// Scene life: when the app resigns active the Bench stops submitting GPU work (Metal refuses background work) and the
// snapshot, settings and Run log are written; when it is active again the newest request renders and measurements re-arm;
// a memory warning drops every rebuildable cache (canvases not on screen, timing/parity/strip work). Settings › Display
// (SDR / EDR) is forwarded to the presenter whenever it changes.

@MainActor @Observable
public final class AppEnvironment {
    public let launch: LaunchScenario.Launch?
    public let settings: AppSettings
    public let telemetry: TelemetryModel
    public let runLog: RunLogStore
    public let specimens: SpecimenStore
    public let gpu: GPUContext?
    public let renderer: RenderCoordinator?
    public let presenter: PresentRenderer?
    public let bench: BenchModel?
    public let calibration: CalibrationService
    /// "SHA-256 <hex>" when every bundled shader source matched its manifest, else "SOURCE CHECK FAILED · <reason>".
    public let shaderSourceCheck: String
    public let buildStamp: String
    public let startupFailure: String?
    /// `systemUptime` when the process started building its environment (the launch time of SPEC §2).
    public let launchUptime: Double
    /// This device's engraving (`iPhone 15 Pro Max · iOS 27.0 · 14 Oct`), nil without a Metal device.
    public var deviceStamp: DeviceStamp? { gpu.map { AppEnvironment.deviceStamp(gpu: $0.device) } }

    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    private init(launch: LaunchScenario.Launch?, settings: AppSettings, telemetry: TelemetryModel, runLog: RunLogStore, specimens: SpecimenStore,
                 gpu: GPUContext?, renderer: RenderCoordinator?, presenter: PresentRenderer?, bench: BenchModel?, calibration: CalibrationService,
                 shaderSourceCheck: String, buildStamp: String, startupFailure: String?, launchUptime: Double) {
        self.launch = launch; self.settings = settings; self.telemetry = telemetry; self.runLog = runLog; self.specimens = specimens
        self.gpu = gpu; self.renderer = renderer; self.presenter = presenter; self.bench = bench; self.calibration = calibration
        self.shaderSourceCheck = shaderSourceCheck; self.buildStamp = buildStamp; self.startupFailure = startupFailure
        self.launchUptime = launchUptime
    }

    public static func make(arguments: [String]) -> AppEnvironment {
        let launchUptime = ProcessInfo.processInfo.systemUptime
        let log = Logger(subsystem: "com.utkarsh.blur2ool", category: "launch")
        let launch = LaunchScenario.parse(arguments)
        let stamp = Bundle.main.object(forInfoDictionaryKey: "B2BuildStamp") as? String ?? "dev"
        log.info("B2BuildStamp \(stamp, privacy: .public)")
        recordBuildStamp(stamp)
        let settings = AppSettings()
        settings.load()
        let telemetry = TelemetryModel()
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let runLog = RunLogStore(directory: support?.appendingPathComponent("Blur2ool", isDirectory: true))
        runLog.currentOSBuild = osBuild()
        let specimens = SpecimenStore()

        var failure: String?
        var gpu: GPUContext?
        var check = "SOURCE CHECK FAILED · no Metal device"
        if let device = MTLCreateSystemDefaultDevice() {
            let shaderDirectory = Bundle.main.resourceURL?.appendingPathComponent("ShaderSources", isDirectory: true)
            let loaded = shaderDirectory.flatMap { ShaderManifest.load(from: $0) }
            check = loaded.map { "SHA-256 \($0.manifest.combinedSHA256)" } ?? "SOURCE CHECK FAILED · bundled sources missing or altered"
            if let library = device.makeDefaultLibrary() {
                do {
                    gpu = try GPUContext(device: device, library: library,
                                         manifest: loaded?.manifest ?? ShaderManifest(files: [:], combinedSHA256: ""))
                } catch { failure = "GPU context: \(error)" }
            } else {
                failure = "the app's default.metallib is missing"
            }
        } else {
            failure = "no Metal device"
        }
        // GPU-MEASURE and APPLE-TWINS implement these behind the frozen names (ARCHITECTURE §5.8, §8).
        GPUServices.timing = TimingService()
        GPUServices.probes = DeviceProbeService()
        GPUServices.shapes = ShapeService()
        GPUServices.appleTwins = AppleTwinRunner()
        let calibration = CalibrationService(runLog: runLog, gpu: gpu)

        var renderer: RenderCoordinator?, presenter: PresentRenderer?, bench: BenchModel?
        if let gpu {
            let coordinator = RenderCoordinator(gpu: gpu, specimens: specimens)
            coordinator.deviceStamp = { AppEnvironment.deviceStamp(gpu: gpu.device) }
            coordinator.deviceProbes = { [weak runLog] in runLog?.deviceProbes ?? [] }
            coordinator.launchUptime = launchUptime
            let present = PresentRenderer(coordinator: coordinator)
            present.options.displayMode = settings.displayMode
            coordinator.onDisplayChanged = { [weak present] in present?.requestRedraw() }
            let model = BenchModel(renderer: coordinator, settings: settings, telemetry: telemetry, runLog: runLog,
                                   restoring: BenchModel.restoredSnapshot(windowSize: 894, settings: settings.silentDefaults))
            model.launchUptime = launchUptime
            model.calibrationHooks = CalibrationIdleHooks(
                noteTouch: { [weak calibration] t in calibration?.noteTouch(at: t) },
                setControlActive: { [weak calibration] active in calibration?.setControlActive(active) },
                tick: { [weak calibration] t, thermal in calibration?.tick(now: t, thermal: thermal) })
            model.handleLaunch(launch)
            renderer = coordinator; presenter = present; bench = model
        }
        let environment = AppEnvironment(launch: launch, settings: settings, telemetry: telemetry, runLog: runLog, specimens: specimens, gpu: gpu,
                                         renderer: renderer, presenter: presenter, bench: bench, calibration: calibration,
                                         shaderSourceCheck: check, buildStamp: stamp, startupFailure: failure, launchUptime: launchUptime)
        if let gpu {
            log.info("GPU \(gpu.device.name, privacy: .public) · \(gpu.facts.familyName, privacy: .public) · shaders \(check, privacy: .public)")
        }
        environment.observeLifecycle()
        environment.followDisplayMode()
        return environment
    }

    // MARK: Scene life, memory, display mode

    private func observeLifecycle() {
        let center = NotificationCenter.default
        let resign: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.bench?.setAppActive(false)
                self?.persistEverything()
            }
        }
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main, using: resign))
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: resign))
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.bench?.setAppActive(true) }
        })
        observers.append(center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.specimens.evict(keeping: 1)
                self?.renderer?.releaseCaches()
            }
        })
    }

    /// Writes the restorable Bench state, the settings and the Run log (scene leaving the foreground).
    public func persistEverything() {
        bench?.persistNow()
        if launch == nil { settings.save() }
        let log = runLog
        Task { await log.flush() }
    }

    /// Settings › Display (SDR / EDR) reaches the presenter whenever it changes.
    private func followDisplayMode() {
        withObservationTracking { _ = settings.displayMode } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.presenter?.options.displayMode = self.settings.displayMode
                self.followDisplayMode()
            }
        }
    }

    // MARK: Build stamp and device stamp

    /// Writes the stamp where `Tools/build.sh device-session` reads it back (`devicectl device copy from … appDataContainer`).
    private static func recordBuildStamp(_ stamp: String) {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        try? Data((stamp + "\n").utf8).write(to: caches.appendingPathComponent("B2BuildStamp.txt"), options: .atomic)
    }

    /// `kern.osversion` ("24A5355p").
    static func osBuild() -> String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: Swift.max(size, 1))
        sysctlbyname("kern.osversion", &buffer, &size, nil, 0)
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// The engraving every MEASURED value carries: "iPhone 15 Pro Max · iOS 27.0 · 14 Oct".
    public static func deviceStamp(gpu: any MTLDevice) -> DeviceStamp {
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif
        return DeviceStamp(deviceModel: modelName(machine), gpuName: gpu.name, gpuFamily: GPUContext.familyName(gpu),
                           osVersion: "iOS " + UIDevice.current.systemVersion, osBuild: osBuild(), isSimulator: simulator, date: Date(),
                           thermal: BenchModel.thermalLevel(ProcessInfo.processInfo.thermalState),
                           lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    /// Marketing names for the identifiers this project meets; anything else shows its identifier (never a guess).
    static func modelName(_ machine: String) -> String {
        [ "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max", "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
          "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max" ][machine] ?? machine
    }
}
