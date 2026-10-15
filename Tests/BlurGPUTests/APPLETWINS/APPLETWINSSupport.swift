import Foundation
import Metal
import Testing
import BlurCore
@testable import BlurGPU

// OWNER: APPLE-TWINS. Shared helpers for the APPLETWINS suites (Mac GPU, no simulator). The twins never use our shader
// library, so the GPUContext gets a one-function library compiled here: these tests do not depend on any other area's
// .metal files. Every measured number is printed as `APPLETWINS · MEASURED (Mac) · …` with the Mac's DeviceStamp, and its
// BadgedValue is checked for honesty, so the core-test log is the record copied into progress-APPLE-TWINS.md.

enum APPLETWINS_Support {
    @MainActor static func context() throws -> GPUContext? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let library = try device.makeLibrary(source: "kernel void appletwins_tests_unused() {}", options: nil)
        return try GPUContext(device: device, library: library,
                              manifest: ShaderManifest(files: [:], combinedSHA256: "appletwins-tests"))
    }

    /// The Mac this test ran on, as a MEASURED value's DeviceStamp.
    static func macStamp(gpuName: String, gpuFamily: String) -> DeviceStamp {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        var build = [CChar](repeating: 0, count: 64), length = build.count
        let osBuild = sysctlbyname("kern.osversion", &build, &length, nil, 0) == 0
            ? String(decoding: build.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) : ""
        let thermal: ThermalLevel
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = .nominal
        case .fair: thermal = .fair
        case .serious: thermal = .serious
        case .critical: thermal = .critical
        @unknown default: thermal = .unknown
        }
        return DeviceStamp(deviceModel: "Mac (\(gpuName))", gpuName: gpuName, gpuFamily: gpuFamily,
                           osVersion: "macOS \(v.majorVersion).\(v.minorVersion)", osBuild: osBuild, isSimulator: false,
                           date: Date(), thermal: thermal, lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    @MainActor static func stamp(_ context: GPUContext) -> DeviceStamp {
        macStamp(gpuName: context.device.name, gpuFamily: GPUContext.familyName(context.device))
    }

    /// Prints one MEASURED (Mac) record and checks that every number in it is an honest MEASURED BadgedValue.
    static func record(_ what: String, _ values: [(label: String, value: Double, style: NumberStyle)], stamp: DeviceStamp,
                       note: String? = nil) {
        let badged = values.map { BadgedValue.number($0.value, $0.style, .measured, device: stamp) }
        for b in badged { #expect(b.honestyViolations.isEmpty, "\(what): \(b.honestyViolations)") }
        let body = zip(values, badged).map { "\($0.label) \($1.textWithUnit)" }.joined(separator: " · ")
        print("APPLETWINS · MEASURED (Mac) · \(stamp.label) · \(what) · \(body)" + (note.map { " · \($0)" } ?? ""))
    }

    static func request(_ subject: CalibrationSubject, _ parameter: Double, phases: Int = 1,
                        colourMode: CalibrationColourMode = .linear) -> CalibrationRequest {
        let path: CalibrationPath
        switch AppleTwinCatalog.facts(subject)?.framework {
        case .metalPerformanceShaders?: path = .metalPerformanceShaders
        case .vImage?: path = .vImage
        default: path = .coreImageContext
        }
        return CalibrationRequest(subject: subject, path: path, parameter: parameter, displayScale: 1, colourMode: colourMode,
                                  phases: phases)
    }

    /// Edge samples for one subject and parameter, with the moment fit of phase 0 and of its 45° twin.
    @MainActor static func edge(_ runner: AppleTwinRunner, _ subject: CalibrationSubject, _ parameter: Double, phases: Int = 1,
                                colourMode: CalibrationColourMode = .linear, context: GPUContext) async throws
        -> (fit: AppleTwinEdgeFit, fit45: AppleTwinEdgeFit?, samples: [EdgeSamples]) {
        let samples = try await runner.edgeSamples(request(subject, parameter, phases: phases, colourMode: colourMode), context: context)
        let first = try #require(samples.first)
        let fit = AppleTwinAnalysis.edgeFit(esf: first.esf, edgePosition: first.edgePosition)
        let fit45 = first.esf45.map { AppleTwinAnalysis.edgeFit(esf: $0, edgePosition: first.edgePosition) }
        return (fit, fit45, samples)
    }

    /// A deterministic test image (premultiplied, opaque, values in 0…1).
    static func pattern(width: Int, height: Int, seed: UInt32 = 7) -> [SIMD4<Float>] {
        (0..<(width * height)).map { i in
            let x = UInt32(i % width), y = UInt32(i / width)
            return SIMD4(NoiseHash.uniform(x: x, y: y, seed: seed), NoiseHash.uniform(x: x, y: y, seed: seed &+ 1),
                         NoiseHash.uniform(x: x, y: y, seed: seed &+ 2), 1)
        }
    }

    static func maxAbs(_ d: SIMD4<Float>) -> Float { Swift.max(Swift.max(abs(d.x), abs(d.y)), Swift.max(abs(d.z), abs(d.w))) }

    static let three = NumberStyle.decimals(3)
    static let px3 = NumberStyle.decimals(3, unit: "px", spokenUnit: "pixels")
    static let two = NumberStyle.decimals(2)
    static let integer = NumberStyle.integer()
}
