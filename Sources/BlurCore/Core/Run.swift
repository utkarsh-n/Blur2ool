import Foundation

// FROZEN — ARCHITECTURE.md §5.7. The Run: one immutable record per acknowledged render or measurement (Engine §4.2; JF G-1).
// Screens only read Runs. Requested values live in the Bench state; everything output-derived follows the newest Run.

public enum RunKind: String, Sendable, Codable, Hashable, CaseIterable {
    case display, timing, trace, fingerprint, parity, calibration, probe
}

public enum RenderQuality: String, Sendable, Codable, Hashable {
    case full
    /// Half resolution while a control moves (SPEC §4.1.6); never timed, traced or parity-checked.
    case half
    /// Quarter resolution when even the half-resolution plan exceeds FetchBudget.preview (review fix E-7).
    case quarter
    public var scale: Double {
        switch self {
        case .full: 1
        case .half: 0.5
        case .quarter: 0.25
        }
    }
    /// Only full-resolution Runs publish PIXEL, loupe, pills, telemetry, Trace and parity (review fix P-36); previews
    /// update the image only, and the other readouts hold their last full values marked HELD.
    public var publishesMeasurements: Bool { self == .full }
}

/// Which image of the Bench a Run belongs to: A (crowns drive it), B, and C/D for Line-up.
public enum RunSlot: String, Sendable, Codable, Hashable, CaseIterable { case a, b, c, d }

/// The requested configuration of one image.
public struct RenderConfiguration: Sendable, Codable, Hashable {
    public var blur: BlurID
    /// The requested variant (the operator may resolve another one; see Run.resolvedVariant).
    public var variant: VariantID
    public var parameters: ParameterValues
    public var settings: SilentSettings
    public var specimen: SpecimenID
    public var specimenOptions: SpecimenOptions
    /// Integer pan of the canvas under the window (±margin, SPEC §4.1.3).
    public var pan: PixelPoint
    public var probe: PixelPoint
    /// Window side in device pixels (894 on the 15 Pro Max).
    public var windowSize: Int
    public init(blur: BlurID, variant: VariantID, parameters: ParameterValues, settings: SilentSettings, specimen: SpecimenID,
                specimenOptions: SpecimenOptions, pan: PixelPoint, probe: PixelPoint, windowSize: Int) {
        self.blur = blur; self.variant = variant; self.parameters = parameters; self.settings = settings
        self.specimen = specimen; self.specimenOptions = specimenOptions; self.pan = pan; self.probe = probe; self.windowSize = windowSize
    }
    public var operatorRequest: OperatorRequest {
        OperatorRequest(parameters: parameters, variant: variant, settings: settings, size: .square(windowSize))
    }
}

/// Runtime GPU limits (MEASURED from the device, or forced to Apple2 values by `blur-gpucheck --apple2-limits`).
public struct GPUFacts: Sendable, Codable, Hashable {
    public var deviceName: String
    public var familyName: String                  // "Apple9", "Apple7", "Apple2"
    public var maxThreadsPerThreadgroup: Int
    public var maxThreadgroupMemoryLength: Int
    public var supportsApple7: Bool                // SIMD-group reductions and scans allowed
    public var supports32BitFloatFiltering: Bool
    public var readWriteTextureTier: Int
    public var supportsStageBoundaryCounters: Bool
    public var isSimulator: Bool
    public var forcedApple2Limits: Bool
    public init(deviceName: String, familyName: String, maxThreadsPerThreadgroup: Int, maxThreadgroupMemoryLength: Int,
                supportsApple7: Bool, supports32BitFloatFiltering: Bool, readWriteTextureTier: Int,
                supportsStageBoundaryCounters: Bool, isSimulator: Bool, forcedApple2Limits: Bool) {
        self.deviceName = deviceName; self.familyName = familyName; self.maxThreadsPerThreadgroup = maxThreadsPerThreadgroup
        self.maxThreadgroupMemoryLength = maxThreadgroupMemoryLength; self.supportsApple7 = supportsApple7
        self.supports32BitFloatFiltering = supports32BitFloatFiltering; self.readWriteTextureTier = readWriteTextureTier
        self.supportsStageBoundaryCounters = supportsStageBoundaryCounters; self.isSimulator = isSimulator
        self.forcedApple2Limits = forcedApple2Limits
    }
    /// The Simulator's Apple2 limits (SDK §15): 512 threads, 16 KB threadgroup memory, no Apple7 features.
    public static func apple2(deviceName: String) -> GPUFacts {
        GPUFacts(deviceName: deviceName, familyName: "Apple2 (forced)", maxThreadsPerThreadgroup: 512,
                 maxThreadgroupMemoryLength: 16_384, supportsApple7: false, supports32BitFloatFiltering: false,
                 readWriteTextureTier: 0, supportsStageBoundaryCounters: false, isSimulator: false, forcedApple2Limits: true)
    }
}

public enum PassEncoderKind: String, Sendable, Codable, Hashable { case render, compute, blit, mps, coreImage }

/// What one GPU pass actually dispatched (COMPUTED geometry; limits read from the pipeline are MEASURED).
public struct PassDispatch: Sendable, Codable, Hashable {
    public var passIndex: Int
    public var name: String
    public var encoder: PassEncoderKind
    /// Metal function names used by this pass ("b2_f2_gauss_linear_fs").
    public var functionNames: [String]
    /// [x, y, z]; [0, 0, 0] for render, blit and MPS passes.
    public var threadsPerThreadgroup: [Int]
    public var threadgroups: [Int]
    public var staticThreadgroupMemoryBytes: Int
    public var dynamicThreadgroupMemoryBytes: Int
    /// `threadExecutionWidth` of the pipeline (SIMD width).
    public var threadExecutionWidth: Int
    /// `maxTotalThreadsPerThreadgroup` of the pipeline.
    public var pipelineMaxThreads: Int
    public var outputSize: ImageSize
    /// True when the output texture carries `.shaderWrite` (no lossless compression on Apple9, REFERENCE TT 111431).
    public var outputHasShaderWrite: Bool
    /// MODELED bytes read + written by this pass.
    public var modeledBytes: Double
    public init(passIndex: Int, name: String, encoder: PassEncoderKind, functionNames: [String], threadsPerThreadgroup: [Int],
                threadgroups: [Int], staticThreadgroupMemoryBytes: Int, dynamicThreadgroupMemoryBytes: Int,
                threadExecutionWidth: Int, pipelineMaxThreads: Int, outputSize: ImageSize, outputHasShaderWrite: Bool,
                modeledBytes: Double) {
        self.passIndex = passIndex; self.name = name; self.encoder = encoder; self.functionNames = functionNames
        self.threadsPerThreadgroup = threadsPerThreadgroup; self.threadgroups = threadgroups
        self.staticThreadgroupMemoryBytes = staticThreadgroupMemoryBytes; self.dynamicThreadgroupMemoryBytes = dynamicThreadgroupMemoryBytes
        self.threadExecutionWidth = threadExecutionWidth; self.pipelineMaxThreads = pipelineMaxThreads; self.outputSize = outputSize
        self.outputHasShaderWrite = outputHasShaderWrite; self.modeledBytes = modeledBytes
    }
}

public struct PassTiming: Sendable, Codable, Hashable {
    public var passIndex: Int
    public var passName: String
    public var medianMilliseconds: Double
    public var iqrMilliseconds: Double
    public var samples: Int
    public init(passIndex: Int, passName: String, medianMilliseconds: Double, iqrMilliseconds: Double, samples: Int) {
        self.passIndex = passIndex; self.passName = passName; self.medianMilliseconds = medianMilliseconds
        self.iqrMilliseconds = iqrMilliseconds; self.samples = samples
    }
}

public enum TimingMethod: String, Sendable, Codable, Hashable {
    /// gpuEndTime − gpuStartTime of whole command buffers (one blur per command buffer).
    case commandBuffer
    /// Per-encoder timestamps where supportsCounterSampling(.atStageBoundary) (one encoder per pass).
    case stageBoundaryCounters
    /// One command buffer per pass (fallback for per-pass times without counters).
    case passIsolatedCommandBuffers
}

/// MEASURED on a named device; nil in the Simulator (its GPU times are meaningless, GPU §2.7 item 4).
/// Why a timing run stopped (review fix E-7: timing is budgeted and cancellable).
public enum TimingStopReason: String, Sendable, Codable, Hashable {
    /// The requested number of samples was reached (15 by default).
    case samplesReached
    /// Summed GPU time reached TimingRequest.maxGPUSeconds (at least `minSamples` were taken).
    case gpuTimeBudget
}

public struct TimingSummary: Sendable, Codable, Hashable {
    public var method: TimingMethod
    public var warmups: Int
    public var samples: Int
    /// Median of whole-blur command-buffer times, one encoder per pass.
    public var medianMilliseconds: Double
    public var iqrMilliseconds: Double
    public var perPass: [PassTiming]
    /// Median with all passes fused into the fewest encoders; the difference is shown as MEASUREMENT OVERHEAD.
    public var fusedMedianMilliseconds: Double?
    /// True when A and B were timed in interleaved ABAB order (Compare's ΔGPU).
    public var interleaved: Bool
    public var thermalAtStart: ThermalLevel
    public var thermalAtEnd: ThermalLevel
    public var lowPowerMode: Bool
    /// Median of the colour pre/post passes and window copy, timed separately; `medianMilliseconds` covers the blur
    /// passes only (review fix E-57). nil in linear premultiplied mode without exposure (no such passes).
    public var overheadMilliseconds: Double?
    public var stopReason: TimingStopReason
    public init(method: TimingMethod, warmups: Int, samples: Int, medianMilliseconds: Double, iqrMilliseconds: Double,
                perPass: [PassTiming], fusedMedianMilliseconds: Double?, interleaved: Bool, thermalAtStart: ThermalLevel,
                thermalAtEnd: ThermalLevel, lowPowerMode: Bool, overheadMilliseconds: Double? = nil,
                stopReason: TimingStopReason = .samplesReached) {
        self.method = method; self.warmups = warmups; self.samples = samples; self.medianMilliseconds = medianMilliseconds
        self.iqrMilliseconds = iqrMilliseconds; self.perPass = perPass; self.fusedMedianMilliseconds = fusedMedianMilliseconds
        self.interleaved = interleaved; self.thermalAtStart = thermalAtStart; self.thermalAtEnd = thermalAtEnd; self.lowPowerMode = lowPowerMode
        self.overheadMilliseconds = overheadMilliseconds; self.stopReason = stopReason
    }
    public var thermalChanged: Bool { thermalAtStart != thermalAtEnd }
}

/// COMPUTED from the operator for the resolved variant.
public struct KernelSummary: Sendable, Codable, Hashable {
    public var sigmaEff: Double?
    public var excessKurtosis: Double?
    public var fetchesPerPixel: Double
    public var tapsPerAxis: Int?
    public var passNames: [String]
    /// The exact 1-D weights and offsets uploaded to the GPU (Float of BlurCore's Double), when the variant uses tables.
    public var uploadedWeights: [Float]?
    public var uploadedOffsets: [Float]?
    public init(sigmaEff: Double?, excessKurtosis: Double?, fetchesPerPixel: Double, tapsPerAxis: Int?, passNames: [String],
                uploadedWeights: [Float]? = nil, uploadedOffsets: [Float]? = nil) {
        self.sigmaEff = sigmaEff; self.excessKurtosis = excessKurtosis; self.fetchesPerPixel = fetchesPerPixel
        self.tapsPerAxis = tapsPerAxis; self.passNames = passNames; self.uploadedWeights = uploadedWeights; self.uploadedOffsets = uploadedOffsets
    }
}

/// The bandwidth a cost model assumes, with its own honesty.
public struct BandwidthAssumption: Sendable, Codable, Hashable {
    public var gigabytesPerSecond: Double
    /// "51.2 GB/s (leak-derived)" or "copy bandwidth measured on this phone".
    public var label: String
    public var provenance: Provenance
    public var qualifiers: Qualifiers
    public init(gigabytesPerSecond: Double, label: String, provenance: Provenance, qualifiers: Qualifiers) {
        self.gigabytesPerSecond = gigabytesPerSecond; self.label = label; self.provenance = provenance; self.qualifiers = qualifiers
    }
    /// gpu-pipeline §2.5: third-party LPDDR5-6400 × 64-bit figure; UNVERIFIED.
    public static let a17ProLeak = BandwidthAssumption(gigabytesPerSecond: 51.2, label: "51.2 GB/s (leak-derived)",
                                                       provenance: .modeled, qualifiers: .weakSource)
}

/// MODELED; the assumption travels with it.
public struct CostSummary: Sendable, Codable, Hashable {
    public var bytesMoved: Double
    public var perPassBytes: [Double]
    public var bandwidth: BandwidthAssumption
    public var floorMilliseconds: Double
    public init(bytesMoved: Double, perPassBytes: [Double], bandwidth: BandwidthAssumption, floorMilliseconds: Double) {
        self.bytesMoved = bytesMoved; self.perPassBytes = perPassBytes; self.bandwidth = bandwidth; self.floorMilliseconds = floorMilliseconds
    }
}

/// MEASURED: GPU output vs the BlurCore reference on a crop around the probe.
public struct ParitySummary: Sendable, Codable, Hashable {
    public var stats: DifferenceStats
    public var region: PixelRegion
    public var tolerance: ParityTolerance
    public var passed: Bool
    public init(stats: DifferenceStats, region: PixelRegion, tolerance: ParityTolerance, passed: Bool) {
        self.stats = stats; self.region = region; self.tolerance = tolerance; self.passed = passed
    }
}

/// LIVE: the probe's input and output read back from the GPU for this frame (linear light).
public struct ProbeReadout: Sendable, Codable, Hashable {
    public var probe: PixelPoint
    public var input: SIMD4<Double>
    public var output: SIMD4<Double>
    /// The probe's value after each pass (from the real intermediates), when read.
    public var perPass: [SIMD4<Double>]
    public init(probe: PixelPoint, input: SIMD4<Double>, output: SIMD4<Double>, perPass: [SIMD4<Double>] = []) {
        self.probe = probe; self.input = input; self.output = output; self.perPass = perPass
    }
}

/// MEASURED from GPU output (the fingerprint's ON THIS PHONE row, SPEC §7.1 item 10).
public struct ShapeMeasurement: Sendable, Codable, Hashable {
    public var sigmaPx: Double
    public var excessKurtosisAxis: Double
    public var excessKurtosis45: Double
    /// Edge-centre spread over 4 whole-pixel phases (shift-variance detector, CAL §3.3).
    public var shiftSpreadPx: Double
    public var minResponse: Double
    public var millisecondsPerMegapixel: Double?
    public init(sigmaPx: Double, excessKurtosisAxis: Double, excessKurtosis45: Double, shiftSpreadPx: Double, minResponse: Double,
                millisecondsPerMegapixel: Double?) {
        self.sigmaPx = sigmaPx; self.excessKurtosisAxis = excessKurtosisAxis; self.excessKurtosis45 = excessKurtosis45
        self.shiftSpreadPx = shiftSpreadPx; self.minResponse = minResponse; self.millisecondsPerMegapixel = millisecondsPerMegapixel
    }
}

/// REFERENCE ("it is the code"): which compiled source produced the Run (ARCHITECTURE §6.6).
public struct ShaderProvenance: Sendable, Codable, Hashable {
    /// SHA-256 of the concatenated shader source (B2Shared.h + all App/GPU/Shaders/*.metal; §6.6 rule).
    public var combinedSHA256: String
    /// The family file of the running variant ("F2Gaussian.metal") and its own SHA-256.
    public var fileName: String
    public var fileSHA256: String
    public var functionNames: [String]
    public var mathMode: String                    // "fast"
    public var languageVersion: String             // "4.1"
    public var traced: Bool
    public init(combinedSHA256: String, fileName: String, fileSHA256: String, functionNames: [String], mathMode: String,
                languageVersion: String, traced: Bool) {
        self.combinedSHA256 = combinedSHA256; self.fileName = fileName; self.fileSHA256 = fileSHA256
        self.functionNames = functionNames; self.mathMode = mathMode; self.languageVersion = languageVersion; self.traced = traced
    }
}

public enum DeviceProbeKind: String, Sendable, Codable, Hashable, CaseIterable {
    case limits, bilinearSubTexelBits, mipmapImpulse, copyBandwidthBlit, copyBandwidthCompute, compressionAB,
         fmaThroughput, counterSamplingPoints, tracedEqualsUntraced
}

/// One This-phone probe result (SPEC §4.7), cached with OS build and date.
public struct DeviceProbeResult: Sendable, Codable, Hashable {
    public var kind: DeviceProbeKind
    public var rows: [LabeledValue]
    /// Machine-readable numbers ("subTexelBits": 8, "gigabytesPerSecond": 31.2, "equal": 1).
    public var numbers: [String: Double]
    public var device: DeviceStamp
    public init(kind: DeviceProbeKind, rows: [LabeledValue], numbers: [String: Double], device: DeviceStamp) {
        self.kind = kind; self.rows = rows; self.numbers = numbers; self.device = device
    }
}

public struct Run: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public let kind: RunKind
    /// Monotonic request generation; only the newest generation may publish (METRO §F.2 item 3).
    public let generation: UInt64
    public let slot: RunSlot
    public let configuration: RenderConfiguration
    public let resolvedVariant: VariantResolution
    public let quality: RenderQuality
    public let device: DeviceStamp
    public let gpu: GPUFacts?
    public let kernel: KernelSummary
    public let dispatch: [PassDispatch]
    public let timing: TimingSummary?
    public let cost: CostSummary?
    public let parity: ParitySummary?
    public let probe: ProbeReadout?
    public let shape: ShapeMeasurement?
    public let shader: ShaderProvenance?
    public let trace: TraceRecord?
    public let calibration: CalibrationResult?
    public let deviceProbe: DeviceProbeResult?
    public let createdAt: Date
    public let notes: [String]
    public init(id: UUID = UUID(), kind: RunKind, generation: UInt64, slot: RunSlot, configuration: RenderConfiguration,
                resolvedVariant: VariantResolution, quality: RenderQuality, device: DeviceStamp, gpu: GPUFacts?,
                kernel: KernelSummary, dispatch: [PassDispatch], timing: TimingSummary?, cost: CostSummary?,
                parity: ParitySummary?, probe: ProbeReadout?, shape: ShapeMeasurement?, shader: ShaderProvenance?,
                trace: TraceRecord?, calibration: CalibrationResult?, deviceProbe: DeviceProbeResult?,
                createdAt: Date = Date(), notes: [String] = []) {
        self.id = id; self.kind = kind; self.generation = generation; self.slot = slot; self.configuration = configuration
        self.resolvedVariant = resolvedVariant; self.quality = quality; self.device = device; self.gpu = gpu
        self.kernel = kernel; self.dispatch = dispatch; self.timing = timing; self.cost = cost; self.parity = parity
        self.probe = probe; self.shape = shape; self.shader = shader; self.trace = trace; self.calibration = calibration
        self.deviceProbe = deviceProbe; self.createdAt = createdAt; self.notes = notes
    }
}
