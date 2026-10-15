import Foundation
import Metal
import BlurCore

// FROZEN — ARCHITECTURE.md §5.8. Metal-side value types. Sendable ones may cross actors; the structs holding textures
// or buffers are deliberately NOT Sendable and live on the main actor only.

/// A typed function-constant value at a fixed index (indices: B2Shared.h and ARCHITECTURE §6.2).
public enum FunctionConstantValue: Sendable, Hashable {
    case bool(Bool), uint(UInt32), int(Int32), float(Float)
}

public struct FunctionConstant: Sendable, Hashable {
    public var index: Int
    public var value: FunctionConstantValue
    public init(_ index: Int, _ value: FunctionConstantValue) { self.index = index; self.value = value }
}

/// Function-constant values for one specialization. Shared indices 0–3 are fixed in B2Shared.h; each family file owns
/// a block of 8 indices (ARCHITECTURE §6.2) for `family`.
public struct FunctionConstants: Sendable, Hashable {
    public var traceProbe: Bool          // B2_TRACE_PROBE, index 0
    public var halfAccumulate: Bool      // B2_HALF_ACCUM, index 1
    public var edgeMode: EdgeMode        // B2_EDGE_MODE, index 2
    public var direction: UInt32         // B2_DIRECTION, index 3 (0 horizontal, 1 vertical, 2+ family-defined)
    public var family: [FunctionConstant]
    public init(traceProbe: Bool = false, halfAccumulate: Bool = false, edgeMode: EdgeMode = .clamp, direction: UInt32 = 0,
                family: [FunctionConstant] = []) {
        self.traceProbe = traceProbe; self.halfAccumulate = halfAccumulate; self.edgeMode = edgeMode
        self.direction = direction; self.family = family
    }
    public var cacheKey: String {
        "t\(traceProbe ? 1 : 0)h\(halfAccumulate ? 1 : 0)e\(edgeMode.shaderIndex)d\(direction)" + family.map { "|\($0.index)=\($0.value)" }.joined()
    }
    /// The Metal values object (indices 0–3 always set, so every shared declaration is defined).
    public func metalValues() -> MTLFunctionConstantValues {
        let v = MTLFunctionConstantValues()
        var trace = traceProbe, half = halfAccumulate, edge = edgeMode.shaderIndex, dir = direction
        v.setConstantValue(&trace, type: .bool, index: 0)
        v.setConstantValue(&half, type: .bool, index: 1)
        v.setConstantValue(&edge, type: .uint, index: 2)
        v.setConstantValue(&dir, type: .uint, index: 3)
        for c in family {
            switch c.value {
            case .bool(var b): v.setConstantValue(&b, type: .bool, index: c.index)
            case .uint(var u): v.setConstantValue(&u, type: .uint, index: c.index)
            case .int(var i): v.setConstantValue(&i, type: .int, index: c.index)
            case .float(var f): v.setConstantValue(&f, type: .float, index: c.index)
            }
        }
        return v
    }
}

public enum TextureFormat: String, Sendable, Codable, Hashable {
    case rgba16Float, rgba8Unorm, r16Float, r32Float, rg16Float, rg32Float, rgba32Float
    public var metal: MTLPixelFormat {
        switch self {
        case .rgba16Float: .rgba16Float
        case .rgba8Unorm: .rgba8Unorm
        case .r16Float: .r16Float
        case .r32Float: .r32Float
        case .rg16Float: .rg16Float
        case .rg32Float: .rg32Float
        case .rgba32Float: .rgba32Float
        }
    }
    public var bytesPerPixel: Int {
        switch self {
        case .rgba16Float: 8
        case .rgba8Unorm, .r32Float, .rg16Float: 4
        case .r16Float: 2
        case .rg32Float: 8
        case .rgba32Float: 16
        }
    }
    /// 32-bit float formats are never sampled with a linear filter (ARCHITECTURE §4.4 rule 4).
    public var filterable: Bool { ![.r32Float, .rg32Float, .rgba32Float].contains(self) }
}

public struct TextureRole: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let read = TextureRole(rawValue: 1 << 0)
    /// Only for compute outputs: removes lossless compression on Apple9 (REFERENCE, Tech Talk 111431).
    public static let computeWrite = TextureRole(rawValue: 1 << 1)
    public static let renderTarget = TextureRole(rawValue: 1 << 2)
}

public struct TextureSpec: Sendable, Hashable {
    public var width: Int
    public var height: Int
    public var format: TextureFormat
    public var roles: TextureRole
    public var mipmapped: Bool
    /// `.shared` storage; default `.private` (readback always goes through a blit, ARCHITECTURE §4.1).
    public var shared: Bool
    public init(width: Int, height: Int, format: TextureFormat = .rgba16Float, roles: TextureRole, mipmapped: Bool = false,
                shared: Bool = false) {
        self.width = width; self.height = height; self.format = format; self.roles = roles; self.mipmapped = mipmapped; self.shared = shared
    }
}

public struct TraceRequest: Sendable, Hashable {
    /// The probe in window pixels.
    public var probe: PixelPoint
    /// Capacity per pass (taps + the final flags = 2 record); extra taps increment the header's overflow count.
    public var maxTapsPerPass: Int
    public init(probe: PixelPoint, maxTapsPerPass: Int) { self.probe = probe; self.maxTapsPerPass = maxTapsPerPass }
    /// Capacity sized from the plan (`PassPlan.traceCapacity`: the largest traced tapsPerPixel + 1), so a correct
    /// kernel never overflows (review fix E-13). ParityRunner, TraceSession and the app always use this.
    public static func sized(probe: PixelPoint, plan: PassPlan) -> TraceRequest {
        TraceRequest(probe: probe, maxTapsPerPass: plan.traceCapacity)
    }
}

/// What the GPU reports when a command buffer finishes. Sendable: it is all a completion handler may capture.
public struct GPUCompletion: Sendable, Hashable {
    public var gpuStartTime: Double
    public var gpuEndTime: Double
    public var error: String?
    public init(gpuStartTime: Double, gpuEndTime: Double, error: String?) {
        self.gpuStartTime = gpuStartTime; self.gpuEndTime = gpuEndTime; self.error = error
    }
    public var milliseconds: Double { (gpuEndTime - gpuStartTime) * 1000 }
}

/// Auxiliary textures some blurs need (depth, velocity, guide, mask, sub-frames). Window-sized. Main actor only.
public struct GPUAuxiliaryTextures {
    public var depth: (any MTLTexture)?
    public var velocity: (any MTLTexture)?
    public var guide: (any MTLTexture)?
    public var mask: (any MTLTexture)?
    public var subFrames: [any MTLTexture]
    public var noiseSeed: UInt32
    public init(depth: (any MTLTexture)? = nil, velocity: (any MTLTexture)? = nil, guide: (any MTLTexture)? = nil,
                mask: (any MTLTexture)? = nil, subFrames: [any MTLTexture] = [], noiseSeed: UInt32 = 1) {
        self.depth = depth; self.velocity = velocity; self.guide = guide; self.mask = mask; self.subFrames = subFrames; self.noiseSeed = noiseSeed
    }
}

/// Inputs to one blur encode (after the colour pre-pass). Main actor only.
public struct GPUBlurInputs {
    /// N × N rgba16Float, linear (or encoded, per the pre-pass), premultiplied (or straight).
    public var source: any MTLTexture
    /// Same size and format; render target or compute-writable as the pipeline declares.
    public var destination: any MTLTexture
    public var request: OperatorRequest
    public var auxiliary: GPUAuxiliaryTextures
    public var quality: RenderQuality
    public init(source: any MTLTexture, destination: any MTLTexture, request: OperatorRequest,
                auxiliary: GPUAuxiliaryTextures = GPUAuxiliaryTextures(), quality: RenderQuality = .full) {
        self.source = source; self.destination = destination; self.request = request; self.auxiliary = auxiliary; self.quality = quality
    }
}

/// What an encode produced. Intermediates are kept so the Algorithm floor and Trace can show each pass. Main actor only.
public struct EncodedBlur {
    public var dispatch: [PassDispatch]
    /// One texture per pass output, in order; the last is the destination. Owned by the context's pool until recycled.
    public var intermediates: [any MTLTexture]
    /// Present when a TraceRequest was given: one header + taps block per traced pass (layout: TraceLayout).
    public var traceBuffer: (any MTLBuffer)?
    public var tracedPassIndices: [Int]
    /// The tables uploaded for this encode. For merged-tap variants these are pair weights and offsets, not the stems
    /// (the Kernel floor prints them per variant, review fix P-37).
    public var uploadedWeights: [Float]?
    public var uploadedOffsets: [Float]?
    /// The trace capacity per pass used for `traceBuffer` (TraceLayout.decode needs it).
    public var traceCapacity: Int
    /// Pool textures this encode allocated (colour pre/post intermediates). The caller hands the EncodedBlur back with
    /// `GPUContext.recycle(_:)` once it no longer shows its intermediates (review fix E-27).
    public var transientTextures: [(texture: any MTLTexture, spec: TextureSpec)]
    public init(dispatch: [PassDispatch], intermediates: [any MTLTexture], traceBuffer: (any MTLBuffer)?, tracedPassIndices: [Int],
                uploadedWeights: [Float]? = nil, uploadedOffsets: [Float]? = nil, traceCapacity: Int = 0,
                transientTextures: [(texture: any MTLTexture, spec: TextureSpec)] = []) {
        self.dispatch = dispatch; self.intermediates = intermediates; self.traceBuffer = traceBuffer
        self.tracedPassIndices = tracedPassIndices; self.uploadedWeights = uploadedWeights; self.uploadedOffsets = uploadedOffsets
        self.traceCapacity = traceCapacity; self.transientTextures = transientTextures
    }
}

/// A readback encoded into a render's own recorder (review fix E-26): decode after the recorder's completions.
/// Main actor only.
public struct PendingReadback {
    public let buffer: any MTLBuffer
    public let region: PixelRegion
    public let format: MTLPixelFormat
    public init(buffer: any MTLBuffer, region: PixelRegion, format: MTLPixelFormat) {
        self.buffer = buffer; self.region = region; self.format = format
    }
    public func decode() -> [SIMD4<Float>] {
        GPUContext.decodeRGBA(buffer: buffer, count: region.size.width * region.size.height, format: format)
    }
}

public enum GPUError: Error, Sendable, Equatable {
    case noDevice
    case noCommandQueue
    case missingFunction(String)
    case textureAllocationFailed(String)
    case bufferAllocationFailed
    case encoderUnavailable(String)
    case commandBufferFailed(String)
    case readbackFailed
    case unsupported(String)
    case budgetExceeded(String)
    /// `encode` found no prepared pipeline state for this key: it never compiles (review fix E-3). The coordinator keeps
    /// the previous Run on screen with RENDERING… and awaits `prepare`.
    case notPrepared(String)
}
