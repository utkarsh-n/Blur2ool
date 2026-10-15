import XCTest
import Metal
@testable import Blur2ool
import BlurCore
import BlurGPU

// OWNER: ENGINE. App tests that run on the phone under the simulator hold (`Tools/build.sh device-build-for-testing` +
// `device-session "test --area ENGINE"`):
// • LaunchScenario.parse and BenchModel.handleLaunch for EVERY scenario (routes, sheets, Compare, -B2Param keys, settle).
// • BenchSnapshot JSON round trip and restoration from UserDefaults.
// • A preview Run never updates PIXEL, loupe, rail, pills or telemetry (lastFull only; HELD while it shows).
// • The engine on the A17 Pro: a real render (probe readout, kernel summary, provenance), a traced render (LIVE GPU records
//   whose final record equals the output), budgeted timing, in-app parity, the CPU reference, and the 10-second rule.
// • RunLogStore persistence/export and AppSettings persistence.
@MainActor
final class ENGINE_AppTests: XCTestCase {

    // MARK: Fixtures

    private func context() throws -> GPUContext {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let library = try XCTUnwrap(device.makeDefaultLibrary(), "the app's default.metallib")
        let manifest = Bundle.main.resourceURL.flatMap { ShaderManifest.load(from: $0.appendingPathComponent("ShaderSources"))?.manifest }
            ?? ShaderManifest(files: [:], combinedSHA256: "")
        return try GPUContext(device: device, library: library, manifest: manifest)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ENGINE-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeBench(windowSize n: Int = 256, runLog: RunLogStore? = nil) throws -> BenchModel {
        let gpu = try context()
        let coordinator = RenderCoordinator(gpu: gpu, specimens: SpecimenStore())
        coordinator.deviceStamp = { AppEnvironment.deviceStamp(gpu: gpu.device) }
        let snapshot = BenchSnapshot(configuration: BenchModel.defaultConfiguration(windowSize: n), view: WindowViewState(), compare: nil,
                                     firstLaunchDone: true)
        let settings = AppSettings()
        settings.coachingLineArmed = false
        return BenchModel(renderer: coordinator, settings: settings, telemetry: TelemetryModel(), runLog: runLog ?? RunLogStore(directory: nil),
                          restoring: snapshot)
    }

    private func gaussian(_ n: Int = 256, sigma: Double = 4, variant: VariantID = GaussianOperator.separable,
                          specimen: SpecimenID = "step-edges", probe: PixelPoint? = nil) -> RenderConfiguration {
        let c = SpecimenGeometry.centre(windowSize: n)
        return RenderConfiguration(blur: GaussianOperator.id, variant: variant,
                                   parameters: ParameterValues(["sigma": .double(sigma), "truncation": .choice("3"), "discretisation": .choice("sampled")]),
                                   settings: .standard, specimen: specimen, specimenOptions: .standard, pan: .zero,
                                   probe: probe ?? PixelPoint(x: c.x - 1, y: c.y - 40), windowSize: n)
    }

    private func waitUntil(_ seconds: Double, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    // MARK: LaunchScenario.parse

    func testParseEveryScenarioWithEveryFlag() {
        for scenario in LaunchScenario.allCases {
            let parsed = LaunchScenario.parse(["Blur2ool", "-B2Scenario", scenario.rawValue, "-B2Blur", "box-blur", "-B2Specimen", "step-edges",
                                               "-B2Floor", "4", "-B2Param", "sigma=4", "-B2Param", "settle=1", "-B2Param", "probe=10,20"])
            XCTAssertEqual(parsed?.scenario, scenario, scenario.rawValue)
            XCTAssertEqual(parsed?.blur, "box-blur")
            XCTAssertEqual(parsed?.specimen, "step-edges")
            XCTAssertEqual(parsed?.floor, .kernel)
            XCTAssertEqual(parsed?.parameters, ["sigma": "4", "settle": "1", "probe": "10,20"])
        }
    }

    func testParseRejectsWhatIsNotAScenario() {
        XCTAssertNil(LaunchScenario.parse([]))
        XCTAssertNil(LaunchScenario.parse(["-B2Scenario"]))                                  // flag without a value
        XCTAssertNil(LaunchScenario.parse(["-B2Scenario", "not-a-screen"]))
        let partial = LaunchScenario.parse(["-B2Scenario", "bench", "-B2Floor", "9", "-B2Param", "novalue", "-B2Param", "a=b=c"])
        XCTAssertNil(partial?.floor)                                                          // floors are 1…7
        XCTAssertEqual(partial?.parameters, ["a": "b=c"])                                     // "novalue" ignored; first "=" splits
        XCTAssertEqual(LaunchScenario.parse(["-B2Scenario", "first-launch"])?.scenario, .firstLaunch)
        XCTAssertEqual(LaunchScenario.parse(["-B2Scenario", "content-gallery"])?.scenario, .contentGallery)
    }

    // MARK: handleLaunch for every case

    func testHandleLaunchRoutesEveryScenario() throws {
        for scenario in LaunchScenario.allCases {
            let bench = try makeBench()
            let launch = LaunchScenario.Launch(scenario: scenario, blur: nil, specimen: "step-edges", floor: .gpu,
                                               parameters: ["sigma": "4.5", "probe": "30,40"])
            bench.handleLaunch(launch)
            XCTAssertEqual(bench.configuration.blur, GaussianOperator.id, scenario.rawValue)
            XCTAssertEqual(bench.configuration.specimen, "step-edges", scenario.rawValue)
            XCTAssertEqual(bench.configuration.parameters.double("sigma"), 4.5, scenario.rawValue)
            XCTAssertEqual(bench.configuration.probe, PixelPoint(x: 30, y: 40), scenario.rawValue)
            XCTAssertEqual(bench.isFirstLaunch, scenario == .firstLaunch, scenario.rawValue)
            switch scenario {
            case .bench, .firstLaunch, .accessibility, .gallery, .contentGallery:
                XCTAssertEqual(bench.path, [], scenario.rawValue); XCTAssertNil(bench.sheet, scenario.rawValue); XCTAssertNil(bench.compare)
            case .loupe:
                XCTAssertNil(bench.sheet); XCTAssertEqual(bench.path, [])                    // the loupe opens on the first full Run
            case .compare:
                XCTAssertNotNil(bench.compare, "compare enters Compare with a legal B")
                if let state = bench.compare {
                    XCTAssertTrue(bench.legalChoices(axis: state.axis).contains { $0.configuration == state.b }, "B is a legal choice")
                }
            case .layers: XCTAssertEqual(bench.path, [.layers(.gpu)])
            case .trace: XCTAssertEqual(bench.path, [.trace])
            case .catalog: XCTAssertEqual(bench.sheet, .catalog(.blurs))
            case .fingerprints: XCTAssertEqual(bench.sheet, .catalog(.fingerprints))
            case .divergence: XCTAssertEqual(bench.sheet, .catalog(.divergence))
            case .lessons: XCTAssertEqual(bench.sheet, .catalog(.lessons))
            case .fingerprint: XCTAssertEqual(bench.sheet, .fingerprint(GaussianOperator.id))
            case .fieldGuide: XCTAssertEqual(bench.sheet, .fieldGuide(.guide, GaussianOperator.id))
            case .thisPhone: XCTAssertEqual(bench.sheet, .fieldGuide(.thisPhone, nil))
            case .runs: XCTAssertEqual(bench.sheet, .fieldGuide(.runs, nil))
            case .settings: XCTAssertEqual(bench.sheet, .fieldGuide(.settings, nil))
            case .calibrate: XCTAssertEqual(bench.sheet, .calibrate(.swiftUIBlur))
            }
        }
    }

    func testLaunchParametersAndSettleDeferTheFinalState() throws {
        let bench = try makeBench()
        bench.handleLaunch(LaunchScenario.Launch(scenario: .trace, blur: GaussianOperator.id, specimen: "impulse", floor: nil,
                                                 parameters: ["settle": "1", "variant": "gaussian-separable", "ev": "4", "split": "off",
                                                              "zoom": "4", "opt.intensity": "100", "edge": "mirror", "colour": "srgb",
                                                              "sigma": "999"]))
        XCTAssertEqual(bench.path, [], "settle=1 waits for the settled Run before pushing")
        XCTAssertEqual(bench.configuration.variant, GaussianOperator.separable)
        XCTAssertEqual(bench.configuration.specimenOptions.exposureEV, 4)
        XCTAssertEqual(bench.configuration.specimenOptions.choices["intensity"], "100")
        XCTAssertEqual(bench.configuration.settings.edgeMode, .mirror)
        XCTAssertEqual(bench.configuration.settings.colourSpace, .srgbEncoded)
        XCTAssertEqual(bench.configuration.parameters.double("sigma"), 64, "parameters clamp to their range")
        XCTAssertNil(bench.view.split)
        XCTAssertEqual(bench.view.zoom, 4)
        let compare = try makeBench()
        compare.handleLaunch(LaunchScenario.Launch(scenario: .compare, blur: nil, specimen: nil, floor: nil,
                                                   parameters: ["axis": "implementation", "bvariant": "cpu", "view": "difference16"]))
        XCTAssertEqual(compare.compare?.axis, .implementation)
        XCTAssertEqual(compare.compare?.view, .difference16)
        XCTAssertTrue(compare.compare?.b.variant.rawValue.hasPrefix(RenderCoordinator.cpuReferencePrefix) ?? false)
    }

    // MARK: BenchSnapshot

    func testBenchSnapshotJSONRoundTripAndRestore() throws {
        let a = gaussian(894, sigma: 12, variant: GaussianOperator.linearSampled, specimen: "night-city", probe: PixelPoint(x: 447, y: 455))
        var b = a
        b.variant = GaussianOperator.separable
        let snapshot = BenchSnapshot(configuration: a,
                                     view: WindowViewState(zoom: 4, zoomCentre: SIMD2(400, 300), split: 0.25, shownPass: 1, loupe: PixelPoint(x: 1, y: 2)),
                                     compare: CompareState(b: b, axis: .implementation, match: .none, view: .difference256, split: 0.3, drivingB: true),
                                     firstLaunchDone: true)
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(BenchSnapshot.self, from: data), snapshot)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ENGINE-\(UUID().uuidString)"))
        defaults.set(data, forKey: BenchModel.snapshotKey)
        XCTAssertEqual(BenchModel.restoredSnapshot(windowSize: 894, settings: .standard, defaults: defaults), snapshot)
        defaults.set(Data("not json".utf8), forKey: BenchModel.snapshotKey)
        let fallback = BenchModel.restoredSnapshot(windowSize: 810, settings: .standard, defaults: defaults)
        XCTAssertFalse(fallback.firstLaunchDone)
        XCTAssertEqual(fallback.configuration.windowSize, 810)
        XCTAssertEqual(fallback.configuration.blur, GaussianOperator.id)
        XCTAssertEqual(fallback.configuration.parameters.double("sigma"), 12)
    }

    // MARK: Previews publish the image only

    private func syntheticRun(_ configuration: RenderConfiguration, generation: UInt64, quality: RenderQuality, output: Double,
                              sigma: Double) -> Run {
        let stamp = AppEnvironment.deviceStamp(gpu: MTLCreateSystemDefaultDevice()!)
        return Run(kind: .display, generation: generation, slot: .a, configuration: configuration,
                   resolvedVariant: VariantResolution(variant: configuration.variant), quality: quality, device: stamp, gpu: nil,
                   kernel: KernelSummary(sigmaEff: sigma, excessKurtosis: 0, fetchesPerPixel: 50, tapsPerAxis: 25, passNames: ["H", "V"]),
                   dispatch: [], timing: nil, cost: nil, parity: nil,
                   probe: quality == .full ? ProbeReadout(probe: configuration.probe, input: SIMD4(0, 0, 0, 1), output: SIMD4(output, output, output, 1)) : nil,
                   shape: nil, shader: nil, trace: nil, calibration: nil, deviceProbe: nil)
    }

    func testAPreviewRunNeverUpdatesPixelLoupeOrTelemetry() async throws {
        let bench = try makeBench()
        let config = bench.configuration
        let full = syntheticRun(config, generation: 1, quality: .full, output: 0.45, sigma: 3.96)
        bench.publish(full)
        let ok1 = await waitUntil(5) { !bench.railChips.isEmpty }
        XCTAssertTrue(ok1, "rail chips from the full Run")
        let chips = bench.railChips, pills = bench.pills
        let sigma = bench.telemetry.sigmaEff, gpu = bench.telemetry.gpu, parity = bench.telemetry.parity
        XCTAssertEqual(sigma?.value, 3.96)
        XCTAssertFalse(bench.isHeld)
        XCTAssertFalse(bench.telemetry.isHeld)
        let pixel = chips.first { $0.floor == .pixels }?.value

        var moved = config
        moved.parameters["sigma"] = .double(9)
        let preview = syntheticRun(moved, generation: 2, quality: .half, output: 0.99, sigma: 4.5)
        bench.publish(preview)
        try? await Task.sleep(for: .milliseconds(400))                                     // any async readout work would have landed
        XCTAssertEqual(bench.acknowledged[.a], preview, "the image follows the preview")
        XCTAssertEqual(bench.lastFull[.a], full, "measurement-derived values follow the last FULL Run")
        XCTAssertEqual(bench.railChips, chips, "rail (incl. PIXEL) unchanged by a preview")
        XCTAssertEqual(bench.railChips.first { $0.floor == .pixels }?.value, pixel)
        XCTAssertEqual(bench.pills, pills)
        XCTAssertEqual(bench.telemetry.sigmaEff, sigma)
        XCTAssertEqual(bench.telemetry.gpu, gpu)
        XCTAssertEqual(bench.telemetry.parity, parity)
        XCTAssertNil(bench.loupe)
        XCTAssertTrue(bench.isHeld, "readouts are HELD while the preview shows")
        XCTAssertTrue(bench.telemetry.isHeld)
    }

    func testPreviewDoesNotChangeARealLoupeReading() async throws {
        let bench = try makeBench()
        let config = gaussian()
        let full = try await XCTUnwrapAsync(try await bench.renderer.render(RenderRequest(configuration: config, slot: .a, quality: .full, generation: 1,
                                                                                         kind: .display, traced: false)))
        bench.publish(full)
        await bench.setLoupe(config.probe)
        let reading = try XCTUnwrap(bench.loupe, "the loupe reads the full output")
        XCTAssertEqual(reading.texels.count, 196)
        XCTAssertEqual(reading.centreLinear.provenance, .live)
        XCTAssertEqual(reading.centreCode8.provenance, .computed)
        XCTAssertTrue(reading.centreLinear.honestyViolations.isEmpty && reading.centreCode8.honestyViolations.isEmpty)
        let preview = try await XCTUnwrapAsync(try await bench.renderer.render(RenderRequest(configuration: config, slot: .a, quality: .half,
                                                                                            generation: 2, kind: .display, traced: false)))
        XCTAssertEqual(preview.quality, .half)
        XCTAssertNil(preview.probe, "previews carry no probe readout")
        XCTAssertNil(preview.trace)
        bench.publish(preview)
        XCTAssertEqual(bench.loupe, reading)
        XCTAssertEqual(bench.lastFull[.a], full)
        // The newest full output is what readTexels serves, never the 128² preview.
        let probe = try await bench.renderer.readTexels(slot: .a, pass: nil, region: PixelRegion(origin: config.probe, size: .square(1)))
        XCTAssertEqual(probe.first.map { Double($0.x) }, full.probe?.output.x)
    }

    // MARK: The engine on this phone's GPU

    func testRenderProducesAnHonestRun() async throws {
        let gpu = try context()
        let coordinator = RenderCoordinator(gpu: gpu, specimens: SpecimenStore())
        coordinator.deviceStamp = { AppEnvironment.deviceStamp(gpu: gpu.device) }
        let changes = ENGINE_Counter()
        coordinator.onDisplayChanged = { changes.value += 1 }
        XCTAssertNil(coordinator.displayTexture(slot: .a, pass: nil))
        let config = gaussian(variant: GaussianOperator.linearSampled)
        let run = try await XCTUnwrapAsync(try await coordinator.render(RenderRequest(configuration: config, slot: .a, quality: .full, generation: 1,
                                                                                     kind: .display, traced: false)))
        XCTAssertGreaterThanOrEqual(changes.value, 2, "the sharp input first, then the blurred output")
        XCTAssertNotNil(coordinator.inputTexture(slot: .a))
        XCTAssertEqual(coordinator.displayTexture(slot: .a, pass: nil)?.width, 256)
        XCTAssertEqual(run.quality, .full)
        XCTAssertFalse(run.device.isSimulator)
        XCTAssertEqual(run.kernel.passNames, ["H", "V"])
        XCTAssertEqual(run.kernel.sigmaEff ?? 0, 3.963, accuracy: 0.001)
        XCTAssertNotNil(run.kernel.uploadedWeights)
        XCTAssertEqual(run.shader?.fileName, "F2Gaussian.metal")
        XCTAssertEqual(run.probe?.perPass.count, 2)
        let probe = try XCTUnwrap(run.probe)
        // SPEC §5.3 A: σ 4 at the step edge's probe is 0.4500 linear (within the bilinear class).
        XCTAssertEqual(probe.output.x, 0.45, accuracy: 0.002)
        XCTAssertEqual(probe.input.x, 0, accuracy: 1e-6)
        // A stale generation never renders over a newer one.
        let stale = try await coordinator.render(RenderRequest(configuration: config, slot: .a, quality: .full, generation: 0, kind: .display, traced: false))
        XCTAssertNil(stale)
    }

    func testTracedRenderCarriesLiveGPURecordsMatchingTheOutput() async throws {
        let gpu = try context()
        let coordinator = RenderCoordinator(gpu: gpu, specimens: SpecimenStore())
        coordinator.deviceStamp = { AppEnvironment.deviceStamp(gpu: gpu.device) }
        let config = gaussian()
        let run = try await XCTUnwrapAsync(try await coordinator.render(RenderRequest(configuration: config, slot: .a, quality: .full, generation: 1,
                                                                                     kind: .trace, traced: true)))
        let record = try XCTUnwrap(run.trace, "a traced render carries its TraceRecord")
        XCTAssertEqual(run.shader?.traced, true)
        XCTAssertEqual(record.passes.count, 2)
        for pass in record.passes {
            XCTAssertEqual(pass.source, .gpuRecord, "GPU records are LIVE (SPEC §6.4 rule 1)")
            XCTAssertEqual(pass.source.provenance, .live)
            XCTAssertEqual(pass.truncatedTapCount, 0)
            XCTAssertEqual(pass.taps.count, 25, "σ 4, k 3: 25 integer taps per pass")
            XCTAssertEqual(pass.neighbourhoodIn?.count, 81)
            XCTAssertEqual(pass.neighbourhoodOut?.count, 81)
        }
        let output = try XCTUnwrap(run.probe?.output)
        let final = try XCTUnwrap(record.passes.last?.outputAtProbe)
        // The final record is the value the pass stores; the texture holds it as fp16. The store's rounding rule is the
        // device's (the M1 Max rounds toward zero, requests/SKEL.md item 1), so allow one fp16 ulp and print what happened.
        for ch in 0..<4 {
            let stored = Float(final[ch]), shown = Float(output[ch])
            let ulp = HalfFloat.ulp(Swift.max(abs(stored), 1.0 / 16384))
            XCTAssertLessThanOrEqual(abs(stored - shown), ulp, "final record \(stored) vs stored output \(shown), channel \(ch)")
        }
        print("ENGINE_AppTests: traced final record \(final.x) → stored \(output.x) (fp16 nearest \(HalfFloat.round(Float(final.x))))")
        XCTAssertEqual(record.gpuOutput, output)
        XCTAssertLessThanOrEqual(record.differenceULP16 ?? .infinity, 2, "GPU vs BlurCore within exactF32 (2 fp16 ulps)")
    }

    func testTimingIsBudgetedMeasuredAndNoted() async throws {
        if GPUServices.timing == nil { GPUServices.timing = TimingService() }
        let gpu = try context()
        let coordinator = RenderCoordinator(gpu: gpu, specimens: SpecimenStore())
        coordinator.deviceStamp = { AppEnvironment.deviceStamp(gpu: gpu.device) }
        coordinator.launchUptime = ProcessInfo.processInfo.systemUptime - 30
        let config = gaussian()
        let runs = try await coordinator.time(config, slot: .a, interleavedWith: nil)
        let run = try XCTUnwrap(runs.first)
        let timing = try XCTUnwrap(run.timing)
        XCTAssertEqual(run.kind, .timing)
        XCTAssertGreaterThanOrEqual(timing.samples, 3)
        XCTAssertLessThanOrEqual(timing.samples, 15)
        XCTAssertGreaterThan(timing.medianMilliseconds, 0)
        XCTAssertTrue(run.notes.contains { $0.hasPrefix("launch+") })
        let shown = BenchModel.millisecondsValue(timing.medianMilliseconds, samples: timing.samples, device: run.device)
        XCTAssertEqual(shown.provenance, .measured)
        XCTAssertTrue(shown.honestyViolations.isEmpty, "\(shown.honestyViolations)")
        print("ENGINE_AppTests: Gaussian separable σ 4 @256 on \(run.device.label): median \(timing.medianMilliseconds) ms, n \(timing.samples)")
        XCTAssertTrue(RenderCoordinator.isTimeable(config))
    }

    func testInAppParityOnThisPhone() async throws {
        let gpu = try context()
        let coordinator = RenderCoordinator(gpu: gpu, specimens: SpecimenStore())
        coordinator.deviceStamp = { AppEnvironment.deviceStamp(gpu: gpu.device) }
        // Integer-tap separable Gaussian: exactF32, judged without the sub-texel rule.
        let separable = try await XCTUnwrapAsync(try await coordinator.parity(gaussian(), slot: .a))
        XCTAssertFalse(separable.tolerance.reportOnly)
        XCTAssertTrue(separable.passed, "GPU vs BlurCore on the A17 Pro: max \(separable.stats.maxAbs), \(separable.stats.maxULP16) ulp16")
        XCTAssertEqual(separable.region.size, .square(128))
        print("ENGINE_AppTests: in-app parity separable σ 4: maxAbs \(separable.stats.maxAbs) · ulp16 \(separable.stats.maxULP16) · LSB8 \(separable.stats.maxLSB8)")
        // Linear-sampled (bilinear class) stays report-only until this phone's sub-texel rule is measured.
        let linear = try await XCTUnwrapAsync(try await coordinator.parity(gaussian(variant: GaussianOperator.linearSampled), slot: .a))
        XCTAssertTrue(linear.tolerance.reportOnly)
        XCTAssertEqual(linear.tolerance.name, RenderCoordinator.subTexelPendingName)
        let value = BenchModel.parityValue(linear, device: AppEnvironment.deviceStamp(gpu: gpu.device))
        XCTAssertEqual(value.text, "SUB-TEXEL RULE NOT YET MEASURED")
        XCTAssertTrue(value.honestyViolations.isEmpty)
        print("ENGINE_AppTests: in-app parity linear-sampled σ 4 (report only): maxAbs \(linear.stats.maxAbs) · ulp16 \(linear.stats.maxULP16)")
    }

    func testCPUReferenceRendersAsCompareB() async throws {
        let gpu = try context()
        let coordinator = RenderCoordinator(gpu: gpu, specimens: SpecimenStore())
        coordinator.deviceStamp = { AppEnvironment.deviceStamp(gpu: gpu.device) }
        var config = gaussian()
        config.variant = RenderCoordinator.cpuReferenceVariant(of: GaussianOperator.separable)
        let run = try await XCTUnwrapAsync(try await coordinator.render(RenderRequest(configuration: config, slot: .b, quality: .full, generation: 1,
                                                                                     kind: .display, traced: false)))
        XCTAssertEqual(run.probe?.output.x ?? 0, 0.45, accuracy: 0.001)
        XCTAssertNotNil(coordinator.displayTexture(slot: .b, pass: nil))
        XCTAssertNotNil(coordinator.cpuReferenceMilliseconds(slot: .b))
    }

    // MARK: The Bench loop on this phone: RENDERING… only while in flight; nothing measures in the first 10 s

    func testBenchLoopRendersThenTimesOnlyAfterTenSeconds() async throws {
        if GPUServices.timing == nil { GPUServices.timing = TimingService() }
        let log = RunLogStore(directory: nil)
        let bench = try makeBench(runLog: log)
        bench.configureWindow(points: 256.0 / 3, scale: 3)
        bench.setSpecimen("step-edges", options: .standard)
        bench.start()
        let ok2 = await waitUntil(15) { bench.lastFull[.a] != nil }
        XCTAssertTrue(ok2, "first full Run")
        let ok3 = await waitUntil(5) { if case .rendering = bench.status { false } else { true } }
        XCTAssertTrue(ok3,
                      "RENDERING… goes away once the render is back: \(bench.status.text)")
        try? await Task.sleep(for: .seconds(1.5))                                         // settled, but < 10 s since launch
        XCTAssertTrue(log.runs(of: .timing).isEmpty, "no timing in the first 10 s")
        XCTAssertEqual(bench.telemetry.gpu?.text, "–.––")
        // Pretend the app launched 20 s ago: the next settle times the blur.
        bench.launchUptime = ProcessInfo.processInfo.systemUptime - 20
        bench.setParameter("sigma", .double(5))
        if case .rendering = bench.status {} else { XCTFail("an accepted change shows RENDERING… at once: \(bench.status.text)") }
        let ok4 = await waitUntil(20) { !log.runs(of: .timing).isEmpty }
        XCTAssertTrue(ok4, "timing after settle")
        let timed = try XCTUnwrap(log.runs(of: .timing).last)
        let seconds = timed.notes.compactMap { note -> Double? in
            guard note.hasPrefix("launch+") else { return nil }
            return Double(note.dropFirst("launch+".count).replacingOccurrences(of: " s", with: ""))
        }.first
        XCTAssertGreaterThanOrEqual(seconds ?? 0, 10)
        let ok5 = await waitUntil(5) { bench.telemetry.gpu?.provenance == .measured && bench.telemetry.gpu?.value != nil }
        XCTAssertTrue(ok5,
                      "the GPU readout turns MEASURED after settle")
        XCTAssertTrue(log.runs(of: .display).contains { $0.quality == .full }, "the settled display Run is logged")
        for chip in bench.railChips { XCTAssertTrue(chip.value.honestyViolations.isEmpty, "\(chip.floor): \(chip.value.honestyViolations)") }
        XCTAssertTrue(bench.status.line.honestyViolations.isEmpty, bench.status.text)
    }

    /// The `compare` scenario as the app runs it (894 px, Night City, A and B on the GPU): every render comes back,
    /// RENDERING… clears, and the status row carries Compare's MIN H line.
    func testCompareScenarioAtFullSizeSettles() async throws {
        let bench = try makeBench(windowSize: 894)
        bench.handleLaunch(LaunchScenario.Launch(scenario: .compare, blur: nil, specimen: nil, floor: nil, parameters: ["settle": "1"]))
        bench.configureWindow(points: 298, scale: 3)
        XCTAssertEqual(bench.configuration.windowSize, 894)
        XCTAssertNotNil(bench.compare)
        let began = Date()
        bench.start()
        var timeline: [String] = []
        let rendered = await waitUntil(20) {
            timeline.append(String(format: "%.2f %@", Date().timeIntervalSince(began), bench.status.text))
            return bench.lastFull[.a] != nil && bench.lastFull[.b] != nil
        }
        XCTAssertTrue(rendered, "A and B rendered")
        let idle = await waitUntil(10) { if case .rendering = bench.status { false } else { true } }
        print("ENGINE_AppTests: compare @894 first full A+B after \(String(format: "%.2f", Date().timeIntervalSince(began))) s; " +
              "status \(bench.status.text); timeline head \(timeline.prefix(3)) tail \(timeline.suffix(2))")
        XCTAssertTrue(idle, "RENDERING… clears: \(bench.status.text)")
        XCTAssertNil(bench.lastError)
        XCTAssertTrue(bench.status.text.contains("MIN H"), bench.status.text)
        XCTAssertTrue(bench.status.line.honestyViolations.isEmpty, "\(bench.status.line.honestyViolations)")
    }

    /// Nothing is committed to the GPU while the app is not active; the newest request renders when it is active again.
    func testNoGPUWorkWhileInactive() async throws {
        let bench = try makeBench()
        bench.configureWindow(points: 256.0 / 3, scale: 3)
        bench.start()
        let first = await waitUntil(15) { bench.lastFull[.a] != nil }
        XCTAssertTrue(first)
        let idle = await waitUntil(5) { if case .rendering = bench.status { false } else { true } }
        XCTAssertTrue(idle)
        let generation = bench.renderer.displayGeneration
        bench.setAppActive(false)
        bench.setParameter("sigma", .double(6))
        try? await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(bench.renderer.displayGeneration, generation, "no GPU work while inactive")
        if case .rendering = bench.status { XCTFail("RENDERING… is shown only while a render is in flight") }
        bench.setAppActive(true)
        let caughtUp = await waitUntil(10) { bench.lastFull[.a]?.configuration.parameters.double("sigma") == 6 }
        XCTAssertTrue(caughtUp, "the newest request renders once active again")
    }

    /// The app's own persisted Run log on this phone (what `Export JSON` writes): no timing Run measured in the first
    /// 10 s after its launch. Runs from builds before ENGINE's (no `launch+` note) are counted and skipped.
    func testPersistedRunLogHasNoTimingInTheFirstTenSeconds() async throws {
        let support = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        let store = RunLogStore(directory: support.appendingPathComponent("Blur2ool", isDirectory: true))
        await store.waitUntilLoaded()
        let exported = try RunLogCoding.exportDecoder().decode([Run].self, from: store.exportJSON())
        let timings = exported.filter { $0.kind == .timing }
        let noted = timings.compactMap { run -> Double? in
            guard let note = run.notes.first(where: { $0.hasPrefix("launch+") }) else { return nil }
            return Double(note.dropFirst("launch+".count).replacingOccurrences(of: " s", with: "").replacingOccurrences(of: ",", with: ""))
        }
        print("ENGINE_AppTests: persisted Run log: \(exported.count) runs, \(timings.count) timing, \(noted.count) with launch notes, " +
              "earliest \(noted.min().map { String(format: "%.1f", $0) } ?? "–") s after launch")
        for seconds in noted { XCTAssertGreaterThanOrEqual(seconds, 10, "a timing Run measured \(seconds) s after launch") }
    }

    /// The idle-gate work (ARCHITECTURE §5.8 rule 6, §4.3): the hero dozen's default pipelines specialise in the
    /// background, and the one automatic device probe either lands as a `.probe` Run or reports that it cannot run yet.
    func testIdleGateWorkPrewarmsAndProbes() async throws {
        let gpu = try context()
        let coordinator = RenderCoordinator(gpu: gpu, specimens: SpecimenStore())
        coordinator.deviceStamp = { AppEnvironment.deviceStamp(gpu: gpu.device) }
        let heroes = BlurRegistry.operators.filter { $0.entry.heroOrder != nil && GPUPipelineRegistry.factory($0.entry.id, $0.entry.defaultVariant) != nil }
        let prepared = await coordinator.prewarmHeroDozen(windowSize: 894) { true }
        XCTAssertEqual(prepared, heroes.count, "every registered hero pipeline prepared")
        let stopped = await coordinator.prewarmHeroDozen(windowSize: 894) { false }
        XCTAssertEqual(stopped, 0, "stops when told to")
        if GPUServices.probes == nil { GPUServices.probes = DeviceProbeService() }
        if let run = await coordinator.runDeviceProbe(.bilinearSubTexelBits) {
            XCTAssertEqual(run.kind, .probe)
            XCTAssertEqual(run.deviceProbe?.kind, .bilinearSubTexelBits)
            print("ENGINE_AppTests: sub-texel probe: \(run.deviceProbe?.numbers ?? [:])")
        } else {
            print("ENGINE_AppTests: sub-texel probe not available yet (DeviceProbeService reports it unbuilt)")
        }
    }

    // MARK: Persistence

    func testRunLogPersistsExportsAndErasesMeasurements() async throws {
        let directory = temporaryDirectory()
        let store = RunLogStore(directory: directory)
        await store.waitUntilLoaded()
        let config = gaussian()
        let display = syntheticRun(config, generation: 1, quality: .full, output: 0.45, sigma: 3.96)
        let timing = Run(kind: .timing, generation: 1, slot: .a, configuration: config, resolvedVariant: display.resolvedVariant, quality: .full,
                         device: display.device, gpu: nil, kernel: display.kernel, dispatch: [],
                         timing: TimingSummary(method: .commandBuffer, warmups: 3, samples: 15, medianMilliseconds: 0.2, iqrMilliseconds: 0.01,
                                               perPass: [], fusedMedianMilliseconds: nil, interleaved: false, thermalAtStart: .nominal,
                                               thermalAtEnd: .nominal, lowPowerMode: false),
                         cost: nil, parity: ParitySummary(stats: DifferenceStats(maxAbs: 0, rms: 0, argmax: .zero, maxLSB8: 0, maxULP16: 0, count: 1),
                                                          region: PixelRegion(origin: .zero, size: .square(1)), tolerance: .reportOnly, passed: true),
                         probe: nil, shape: nil, shader: nil, trace: nil, calibration: nil, deviceProbe: nil)
        store.append(display)
        store.append(timing)
        await store.flush()
        let reopened = RunLogStore(directory: directory)
        await reopened.waitUntilLoaded()
        XCTAssertEqual(reopened.runs, [display, timing], "the log survives a relaunch (∞ tolerance included)")
        var moved = config
        moved.probe = PixelPoint(x: 1, y: 1)
        XCTAssertEqual(reopened.latestTimed(for: moved)?.id, timing.id, "the probe does not change timing")
        let exported = try RunLogCoding.exportDecoder().decode([Run].self, from: reopened.exportJSON())
        XCTAssertEqual(exported.map(\.id), [display.id, timing.id])
        reopened.eraseMeasurements()
        XCTAssertEqual(reopened.runs.map(\.kind), [.display])
    }

    func testSettingsPersistIndependentlyOfEachOther() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ENGINE-settings-\(UUID().uuidString)"))
        let settings = AppSettings()
        settings.homeToolID = "css"; settings.matchSigmaOnSwitch = false; settings.displayMode = .edr
        settings.previewsWhileMoving = false; settings.coachingLineArmed = false
        settings.save(to: defaults)
        let loaded = AppSettings()
        loaded.load(from: defaults)
        XCTAssertEqual(loaded.homeToolID, "css")
        XCTAssertFalse(loaded.matchSigmaOnSwitch)
        XCTAssertEqual(loaded.displayMode, .edr)
        XCTAssertEqual(loaded.silentDefaults.preview, .alwaysFull)
        XCTAssertFalse(loaded.coachingLineArmed)
        // A blob from an older build with fewer keys keeps every default it does not mention.
        defaults.set(Data(#"{"homeToolID":"figma"}"#.utf8), forKey: AppSettings.defaultsKey)
        let partial = AppSettings()
        partial.load(from: defaults)
        XCTAssertEqual(partial.homeToolID, "figma")
        XCTAssertTrue(partial.matchSigmaOnSwitch)
        XCTAssertTrue(partial.coachingLineArmed)
    }
}

/// A reference box for counting callbacks from @MainActor closures.
@MainActor final class ENGINE_Counter { var value = 0 }

/// XCTUnwrap for an async throwing expression (XCTest has no async overload of the autoclosure).
@MainActor
private func XCTUnwrapAsync<T>(_ value: T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    try XCTUnwrap(value, message, file: file, line: line)
}
