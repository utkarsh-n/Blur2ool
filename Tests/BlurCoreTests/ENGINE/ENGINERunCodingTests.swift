import Foundation
import Testing
import BlurCore

// OWNER: ENGINE. The Run is the app's one immutable record (ARCHITECTURE §5.7) and the Run log is persisted and exported
// as JSON (SPEC §4.7 Runs, §13.3). These tests round-trip a Run with EVERY optional field populated through the
// coders the app uses (RunLogCoding), including the non-finite numbers Runs legitimately carry.

private let stamp = DeviceStamp(deviceModel: "iPhone 15 Pro Max", gpuName: "Apple A17 Pro GPU", gpuFamily: "Apple9", osVersion: "iOS 27.0",
                                osBuild: "24A5355p", isSimulator: false, date: Date(timeIntervalSinceReferenceDate: 782_000_000.25),
                                thermal: .nominal, lowPowerMode: false)

private func fullRun(parity tolerance: ParityTolerance = .bilinear) -> Run {
    let configuration = RenderConfiguration(
        blur: "gaussian-blur", variant: "gaussian-linear-sampling",
        parameters: ParameterValues(["sigma": .double(12), "truncation": .choice("3"), "discretisation": .choice("sampled"),
                                     "offsets": .intList([0, 1, 2, 2, 3]), "centre": .point(x: 447, y: 447), "on": .bool(true),
                                     "samples": .int(32)]),
        settings: SilentSettings(colourSpace: .srgbEncoded, edgeMode: .mirror, alphaMode: .straight),
        specimen: "night-city", specimenOptions: SpecimenOptions(exposureEV: 2, choices: ["intensity": "100"], seed: 7),
        pan: PixelPoint(x: -36, y: 12), probe: PixelPoint(x: 447, y: 455), windowSize: 894)
    let pass = PassDescriptor(id: 0, name: "H", kind: .fragment, fetchesPerPixel: 37, tapsPerPixel: 73, traceable: true,
                              summary: "horizontal, bilinear pairs")
    let tap = TraceTap(id: 0, position: SIMD2(447.5, 455.5), offset: .zero, texels: [TexelContribution(texel: PixelPoint(x: 447, y: 455), fraction: 1)],
                       requestedFraction: SIMD2(0.4941, 0), quantizedFraction: SIMD2(0.4922, 0), weight: 0.03332,
                       fetched: SIMD4(0.02, 0.02, 0.02, 1), contribution: SIMD4(0.0006664, 0.0006664, 0.0006664, 0.03332),
                       runningSum: SIMD4(0.0006664, 0.0006664, 0.0006664, 0.03332), dropped: false, extras: ["rank": 3])
    let trace = TraceRecord(blur: configuration.blur, variant: configuration.variant, parameters: configuration.parameters,
                            settings: configuration.settings, probe: configuration.probe, input: SIMD4(0.02, 0.02, 0.02, 1),
                            passes: [TracePass(id: 0, descriptor: pass, source: .gpuRecord, pixel: configuration.probe, taps: [tap],
                                               truncatedTapCount: 0, outputAtProbe: SIMD4(0.0885, 0.0885, 0.0885, 1),
                                               neighbourhoodIn: [SIMD4(0, 0, 0, 1)], neighbourhoodOut: nil)],
                            gpuOutput: SIMD4(0.0885, 0.0885, 0.0885, 1), cpuReference: SIMD4(0.08851, 0.08851, 0.08851, 1),
                            differenceULP16: 1, tracedEqualsUntraced: true)
    let fit = PSFFit(sigmaPx: 11.1, sigmaPerParameterPixel: 0.9, lsqSigmaPx: 11.05, excessKurtosis: -0.45, excessKurtosis45: -0.4,
                     extentPx: 40, supportPx: 36, centreSpreadPx: 0.02, sigmaSpreadPercent: 0.4, encodedMidpoint: 0.5,
                     shapeName: "box³-like", models: [ModelFit(model: .gaussian, sigmaPx: 11.1, rmsResidualPercent: 0.8)],
                     lsf: [0.1, 0.3, 0.1])
    let calibration = CalibrationResult(request: CalibrationRequest(subject: .swiftUIBlur, path: .imageRendererCGImage, parameter: 4,
                                                                    displayScale: 3),
                                        fit: fit, device: stamp, durationMilliseconds: 812.5)
    let probe = DeviceProbeResult(kind: .bilinearSubTexelBits,
                                  rows: [LabeledValue(id: "bits", label: "SUB-TEXEL BITS", value: .number(8, .integer(), .measured, device: stamp))],
                                  numbers: ["subTexelBits": 8, "roundsToNearest": 1], device: stamp)
    let timing = TimingSummary(method: .stageBoundaryCounters, warmups: 3, samples: 15, medianMilliseconds: 0.61, iqrMilliseconds: 0.02,
                               perPass: [PassTiming(passIndex: 0, passName: "H", medianMilliseconds: 0.31, iqrMilliseconds: 0.01, samples: 15)],
                               fusedMedianMilliseconds: 0.6, interleaved: true, thermalAtStart: .nominal, thermalAtEnd: .fair,
                               lowPowerMode: false, overheadMilliseconds: 0.04, stopReason: .gpuTimeBudget)
    let stats = DifferenceStats(maxAbs: 9.77e-4, rms: 3.87e-4, argmax: PixelPoint(x: 3, y: 4), maxLSB8: 1, maxULP16: 2, count: 16_384)
    return Run(kind: .display, generation: 42, slot: .b, configuration: configuration,
               resolvedVariant: VariantResolution(variant: "gaussian-separable", reason: "RENORMALISE NEEDS WHOLE TAPS · USING SEPARABLE"),
               quality: .full, device: stamp,
               gpu: GPUFacts(deviceName: "Apple A17 Pro GPU", familyName: "Apple9", maxThreadsPerThreadgroup: 1024,
                             maxThreadgroupMemoryLength: 32_768, supportsApple7: true, supports32BitFloatFiltering: false,
                             readWriteTextureTier: 2, supportsStageBoundaryCounters: false, isSimulator: false, forcedApple2Limits: false),
               kernel: KernelSummary(sigmaEff: 11.86, excessKurtosis: -0.01, fetchesPerPixel: 74, tapsPerAxis: 73, passNames: ["H", "V"],
                                     uploadedWeights: [0.06, 0.12], uploadedOffsets: [0, 1.49]),
               dispatch: [PassDispatch(passIndex: 0, name: "H", encoder: .render, functionNames: ["b2_f2_gauss_linear_fs"],
                                       threadsPerThreadgroup: [0, 0, 0], threadgroups: [0, 0, 0], staticThreadgroupMemoryBytes: 0,
                                       dynamicThreadgroupMemoryBytes: 0, threadExecutionWidth: 32, pipelineMaxThreads: 1024,
                                       outputSize: .square(894), outputHasShaderWrite: false, modeledBytes: 12_787_776)],
               timing: timing,
               cost: CostSummary(bytesMoved: 25_575_552, perPassBytes: [12_787_776, 12_787_776], bandwidth: .a17ProLeak, floorMilliseconds: 0.5),
               parity: ParitySummary(stats: stats, region: PixelRegion(origin: PixelPoint(x: 383, y: 391), size: .square(128)),
                                     tolerance: tolerance, passed: true),
               probe: ProbeReadout(probe: configuration.probe, input: SIMD4(0.02, 0.02, 0.02, 1), output: SIMD4(0.0885, 0.0885, 0.0885, 1),
                                   perPass: [SIMD4(0.05, 0.05, 0.05, 1)]),
               shape: ShapeMeasurement(sigmaPx: 11.9, excessKurtosisAxis: 0.01, excessKurtosis45: 0.02, shiftSpreadPx: 0, minResponse: -0.0012,
                                       millisecondsPerMegapixel: 0.77),
               shader: ShaderProvenance(combinedSHA256: String(repeating: "a", count: 64), fileName: "F2Gaussian.metal",
                                        fileSHA256: String(repeating: "b", count: 64), functionNames: ["b2_f2_gauss_linear_fs"],
                                        mathMode: "fast", languageVersion: "4.1", traced: true),
               trace: trace, calibration: calibration, deviceProbe: probe,
               createdAt: Date(timeIntervalSinceReferenceDate: 782_000_123.456), notes: ["launch+12.4 s"])
}

@Suite struct ENGINE_RunJSON {
    @Test func everyFieldRoundTripsThroughTheStoreCoder() throws {
        let run = fullRun()
        let data = try RunLogCoding.storeEncoder().encode([run])
        let back = try RunLogCoding.storeDecoder().decode([Run].self, from: data)
        #expect(back == [run])
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"sigma\""))                                   // parameter keys encode as JSON object keys
        #expect(text.contains("\"subTexelBits\""))
    }

    @Test func reportOnlyParityCarriesInfinityAndStillRoundTrips() throws {
        let run = fullRun(parity: .reportOnly)
        #expect(run.parity?.tolerance.ulp16 == .infinity)
        #expect(throws: (any Error).self) { try JSONEncoder().encode(run) }   // why the app never uses a default encoder
        let back = try RunLogCoding.storeDecoder().decode(Run.self, from: RunLogCoding.storeEncoder().encode(run))
        #expect(back == run)
    }

    @Test func notANumberSurvivesAsNotANumber() throws {
        let original = fullRun()
        let nan = Run(kind: .timing, generation: 1, slot: .a, configuration: original.configuration, resolvedVariant: original.resolvedVariant,
                      quality: .full, device: stamp, gpu: nil,
                      kernel: KernelSummary(sigmaEff: nil, excessKurtosis: .nan, fetchesPerPixel: 74, tapsPerAxis: nil, passNames: []),
                      dispatch: [], timing: nil, cost: nil, parity: nil, probe: nil, shape: nil, shader: nil, trace: nil,
                      calibration: nil, deviceProbe: nil)
        let back = try RunLogCoding.storeDecoder().decode(Run.self, from: RunLogCoding.storeEncoder().encode(nan))
        #expect(back.kernel.excessKurtosis?.isNaN == true)
        #expect(back.id == nan.id && back.kind == .timing)
    }

    @Test func exportIsPrettyISO8601AndReadsBack() throws {
        let run = fullRun()
        let data = try RunLogCoding.exportEncoder().encode([run])
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\n"))
        #expect(text.contains(/"createdAt"\s*:\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z"/))   // ISO 8601, never raw seconds
        #expect(!text.contains("782000123.456"))
        let back = try RunLogCoding.exportDecoder().decode([Run].self, from: data)
        #expect(back.count == 1)
        #expect(abs(back[0].createdAt.timeIntervalSince(run.createdAt)) < 0.001)   // millisecond precision in the export
        #expect(back[0].configuration == run.configuration && back[0].timing == run.timing && back[0].trace == run.trace)
    }

    @Test func runsAreIdentifiableAndDistinct() {
        let a = fullRun(), b = fullRun()
        #expect(a.id != b.id)
        #expect(a != b)
    }
}
