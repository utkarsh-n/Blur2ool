import Foundation
import Metal
import Testing
@testable import BlurCore
@testable import BlurGPU

// OWNER: GPU-MEASURE. Every DeviceProbeKind on the Mac GPU (ARCHITECTURE §8.2 acceptance): sub-texel bits = 8 and round
// to nearest on this Mac (→ ReferenceOptions.parity), mip impulse 0.25 then 0.0625, copy bandwidth > 0 with its label,
// compression A/B, FMA throughput, counter sampling points, traced = untraced; every row honest; the Simulator branch.

@MainActor
private func GPUMEASURE_probe(_ kind: DeviceProbeKind, _ context: GPUContext, service: DeviceProbeService = DeviceProbeService(),
                              stamp: DeviceStamp = GPUMEASURE_macStamp()) async throws -> DeviceProbeResult {
    let result = try await service.run(kind, context: context, device: stamp)
    print("GPUMEASURE probe \(kind.rawValue): " + result.numbers.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
    #expect(result.kind == kind && result.device == stamp)
    GPUMEASURE_expectHonest(result)
    return result
}

/// Rows pass `honestyViolations` and the content lint (labels, texts and captions: digits only where allowed).
func GPUMEASURE_expectHonest(_ result: DeviceProbeResult, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(!result.rows.isEmpty, sourceLocation: sourceLocation)
    #expect(Set(result.rows.map(\.id)).count == result.rows.count, "row ids are unique", sourceLocation: sourceLocation)
    for row in result.rows {
        #expect(row.value.honestyViolations.isEmpty, "\(row.label): \(row.value.honestyViolations)", sourceLocation: sourceLocation)
        let lint = ContentLint.violations(row.value, context: row.label) + ContentLint.digitViolations(row.label, context: "label")
            + (row.value.caption.map { ContentLint.digitViolations($0, context: "caption") } ?? [])
        #expect(lint.isEmpty, "\(lint)", sourceLocation: sourceLocation)
        #expect(row.label == row.label.uppercased(), sourceLocation: sourceLocation)
        if row.value.value != nil { #expect(row.value.provenance == .measured && row.value.device != nil, sourceLocation: sourceLocation) }
    }
}

@Suite(.serialized) struct GPUMEASURE_Probes {
    @MainActor @Test func subTexelBitsAreEightRoundedToNearestOnThisMac() async throws {
        guard let context = try GPUMEASURE_context() else { return }
        let r = try await GPUMEASURE_probe(.bilinearSubTexelBits, context)
        #expect(r.numbers["subTexelBits"] == 8 && r.numbers["roundsToNearest"] == 1)
        #expect(r.numbers["distinctValues"] == 257)
        #expect(r.numbers["subTexelBitsY"] == 8 && r.numbers["subTexelBitsWide"] == 8 && r.numbers["axesAgree"] == 1)
        #expect(abs((r.numbers["maxError"] ?? 1) - 1.0 / 512) < 1e-6, "research §2.3: max error 1.95·10⁻³")
        #expect(ReferenceOptions.forDevice([r]) == .parity, "this Mac's measured rule is blur-gpucheck's parity rule")
        #expect(r.rows.first?.value.text == "8" && r.rows.first?.value.unit == "bits")
    }

    @MainActor @Test func generateMipmapsIsATwoByTwoBox() async throws {
        guard let context = try GPUMEASURE_context() else { return }
        let r = try await GPUMEASURE_probe(.mipmapImpulse, context)
        #expect(r.numbers["level1Peak"] == 0.25 && r.numbers["level2Peak"] == 0.0625)
        #expect(r.numbers["level1NonZero"] == 1 && r.numbers["level2NonZero"] == 1 && r.numbers["box2x2"] == 1)
        #expect(r.rows.map(\.value.text).prefix(2) == ["0.2500", "0.0625"])
    }

    @MainActor @Test func copyBandwidthIsPositiveWithItsLabel() async throws {
        guard let context = try GPUMEASURE_context() else { return }
        for kind in [DeviceProbeKind.copyBandwidthBlit, .copyBandwidthCompute] {
            let r = try await GPUMEASURE_probe(kind, context)
            let gbps = try #require(r.numbers["gigabytesPerSecond"])
            #expect(gbps > 0 && gbps.isFinite)
            #expect(r.numbers["bytesPerCopy"] == Double(2 * 4096 * 2048 * 8))
            #expect(r.rows[0].value.unit == "GB/s" && r.rows[0].value.caption == "READ + WRITE OF A NOISE TEXTURE")
            let assumption = try #require(DeviceProbeService.bandwidthAssumption(r))
            #expect(assumption.provenance == .measured && assumption.gigabytesPerSecond == gbps)
            #expect(assumption.label == (kind == .copyBandwidthBlit ? "blit copy" : "compute copy") + " measured on Mac (Apple M1 Max)")
        }
    }

    @MainActor @Test func compressionABAndFMAThroughput() async throws {
        guard let context = try GPUMEASURE_context() else { return }
        let ab = try await GPUMEASURE_probe(.compressionAB, context)
        #expect((ab.numbers["compressedMilliseconds"] ?? 0) > 0 && (ab.numbers["uncompressedMilliseconds"] ?? 0) > 0)
        #expect((ab.numbers["ratio"] ?? 0) > 0)
        let fma = try await GPUMEASURE_probe(.fmaThroughput, context)
        #expect((fma.numbers["gigaflopsFP32"] ?? 0) > 100 && (fma.numbers["gigaflopsFP16"] ?? 0) > 100)
    }

    @MainActor @Test func counterSamplingPointsAndLimits() async throws {
        guard let context = try GPUMEASURE_context() else { return }
        let c = try await GPUMEASURE_probe(.counterSamplingPoints, context)
        #expect(c.numbers["atStageBoundary"] == 1 && c.numbers["timestampCounterSet"] == 1 && c.numbers["stageBoundaryResolved"] == 1)
        #expect(c.numbers["atDrawBoundary"] == 0 && c.numbers["atDispatchBoundary"] == 0 && c.numbers["atBlitBoundary"] == 0,
                "research §4.3: the M1 Max samples only at stage boundaries")
        #expect(abs((c.numbers["gpuTicksPerNanosecond"] ?? 0) - 1) < 1e-3, "GPU ticks are nanoseconds on the M1 Max")
        #expect(c.numbers["cpuTimestampIsNanoseconds"] == 1)
        let l = try await GPUMEASURE_probe(.limits, context)
        #expect(l.numbers["maxThreadsPerThreadgroup"] == Double(context.device.maxThreadsPerThreadgroup.width))
        #expect(l.numbers["maxThreadgroupMemoryLength"] == 32_768 && l.numbers["threadExecutionWidth"] == 32)
        #expect(l.numbers["supportsStageBoundaryCounters"] == 1)
    }

    @MainActor @Test func tracedEqualsUntracedOnTheGaussianStage() async throws {
        guard let context = try GPUMEASURE_context() else { return }
        let r = try await GPUMEASURE_probe(.tracedEqualsUntraced, context)
        #expect(r.numbers["equal"] == 1 && r.numbers["differingWords"] == 0 && r.numbers["finalSumMatchesOutput"] == 1)
        #expect((r.numbers["cases"] ?? 0) >= 2 && r.numbers["failures"] == 0)
        #expect(r.rows[0].value.text == "BIT-IDENTICAL")
    }

    /// `Measure everything`: every kind once, in the documented order.
    @MainActor @Test func measureEverythingCoversEveryKind() async throws {
        guard let context = try GPUMEASURE_context() else { return }
        #expect(Set(DeviceProbeService.everything) == Set(DeviceProbeKind.allCases) && DeviceProbeService.everything.count == DeviceProbeKind.allCases.count)
        let all = try await DeviceProbeService().runAll(context: context, device: GPUMEASURE_macStamp())
        #expect(all.map(\.kind) == DeviceProbeService.everything)
        for r in all { GPUMEASURE_expectHonest(r) }
    }

    /// The Simulator: timing probes say NO GPU TIMING IN SIMULATOR and publish no numbers (CostModel keeps its MODELED
    /// bandwidth); the arithmetic probes still measure, qualified `.simulator`. On-simulator run: DEFERRED-BY-HOLD.
    @MainActor @Test func simulatorBranchNeverReportsGPUTimes() async throws {
        guard let context = try GPUMEASURE_context() else { return }
        let service = DeviceProbeService(factsOverride: GPUMEASURE_simulatorFacts())
        let stamp = GPUMEASURE_macStamp(simulator: true)
        for kind in [DeviceProbeKind.copyBandwidthBlit, .copyBandwidthCompute, .compressionAB, .fmaThroughput] {
            let r = try await GPUMEASURE_probe(kind, context, service: service, stamp: stamp)
            #expect(r.numbers.isEmpty && r.rows.count == 1 && r.rows[0].value.text == "NO GPU TIMING IN SIMULATOR")
            #expect(DeviceProbeService.bandwidthAssumption(r) == nil)
        }
        let bits = try await GPUMEASURE_probe(.bilinearSubTexelBits, context, service: service, stamp: stamp)
        #expect(bits.rows.allSatisfy { $0.value.qualifiers.contains(.simulator) })
    }
}
