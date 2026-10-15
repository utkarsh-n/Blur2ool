import Foundation

// FROZEN — ARCHITECTURE.md §5.12. Pixel-trace model (SPEC §6). Per-fetch rows are GPU records (TRACE_PROBE, LIVE) or
// CPU reconstructions (COMPUTED) — never a CPU value labelled LIVE (JF M-6).

public enum TraceSource: String, Sendable, Codable, Hashable {
    /// Recorded by the GPU's TRACE_PROBE specialization for the frame on screen: LIVE.
    case gpuRecord
    /// Recomputed by BlurCore on the CPU: COMPUTED.
    case cpuReconstruction
    public var provenance: Provenance { self == .gpuRecord ? .live : .computed }
}

/// One texel blended by a fetch, with its bilinear weight.
public struct TexelContribution: Sendable, Codable, Hashable {
    public var texel: PixelPoint
    public var fraction: Double
    public init(texel: PixelPoint, fraction: Double) { self.texel = texel; self.fraction = fraction }
}

/// One tap (fetch, sample, compare-exchange, iteration) of one pass for the probe pixel.
public struct TraceTap: Sendable, Codable, Hashable, Identifiable {
    public var id: Int
    /// Sample position in source texel coordinates (texel centres at i + 0.5), in the pass's input texture.
    public var position: SIMD2<Double>
    /// Offset from the output pixel's centre, in input texels.
    public var offset: SIMD2<Double>
    /// 1 texel for integer fetches, up to 4 for bilinear fetches.
    public var texels: [TexelContribution]
    /// Bilinear fraction as requested (COMPUTED).
    public var requestedFraction: SIMD2<Double>?
    /// Bilinear fraction as the hardware quantizes it (MODELED from the measured sub-texel bits).
    public var quantizedFraction: SIMD2<Double>?
    public var weight: Double
    public var fetched: SIMD4<Double>
    public var contribution: SIMD4<Double>
    public var runningSum: SIMD4<Double>
    /// Dropped by `renormalise` at the border (recorded with weight 0).
    public var dropped: Bool
    /// Class-specific extras: "spatialWeight", "rangeWeight", "sectorVariance", "rank", "iteration" …
    public var extras: [String: Double]
    public init(id: Int, position: SIMD2<Double>, offset: SIMD2<Double>, texels: [TexelContribution],
                requestedFraction: SIMD2<Double>?, quantizedFraction: SIMD2<Double>?, weight: Double, fetched: SIMD4<Double>,
                contribution: SIMD4<Double>, runningSum: SIMD4<Double>, dropped: Bool = false, extras: [String: Double] = [:]) {
        self.id = id; self.position = position; self.offset = offset; self.texels = texels
        self.requestedFraction = requestedFraction; self.quantizedFraction = quantizedFraction; self.weight = weight
        self.fetched = fetched; self.contribution = contribution; self.runningSum = runningSum; self.dropped = dropped; self.extras = extras
    }
}

public struct TracePass: Sendable, Codable, Hashable, Identifiable {
    public var id: Int
    public var descriptor: PassDescriptor
    public var source: TraceSource
    /// The output pixel this pass computed for the probe (differs from the probe on pyramid levels).
    public var pixel: PixelPoint
    public var taps: [TraceTap]
    /// Taps beyond the record capacity, summarised in one row.
    public var truncatedTapCount: Int
    public var outputAtProbe: SIMD4<Double>
    /// 9 × 9 neighbourhoods before and after this pass, read from the real intermediate textures (gpuRecord) or computed.
    public var neighbourhoodIn: [SIMD4<Float>]?
    public var neighbourhoodOut: [SIMD4<Float>]?
    public init(id: Int, descriptor: PassDescriptor, source: TraceSource, pixel: PixelPoint, taps: [TraceTap],
                truncatedTapCount: Int, outputAtProbe: SIMD4<Double>, neighbourhoodIn: [SIMD4<Float>]?,
                neighbourhoodOut: [SIMD4<Float>]?) {
        self.id = id; self.descriptor = descriptor; self.source = source; self.pixel = pixel; self.taps = taps
        self.truncatedTapCount = truncatedTapCount; self.outputAtProbe = outputAtProbe
        self.neighbourhoodIn = neighbourhoodIn; self.neighbourhoodOut = neighbourhoodOut
    }
}

public struct TraceRecord: Sendable, Codable, Hashable {
    public var blur: BlurID
    public var variant: VariantID
    public var parameters: ParameterValues
    public var settings: SilentSettings
    public var probe: PixelPoint
    /// The probe's input value (after the colour pre-pass), linear.
    public var input: SIMD4<Double>
    public var passes: [TracePass]
    /// The GPU's output at the probe for the frame on screen (LIVE); nil for CPU-only traces.
    public var gpuOutput: SIMD4<Double>?
    /// BlurCore's reference value (COMPUTED, Double).
    public var cpuReference: SIMD4<Double>
    public var differenceULP16: Double?
    /// Result of the traced-vs-untraced bit-exactness check for this frame, when it ran.
    public var tracedEqualsUntraced: Bool?
    public init(blur: BlurID, variant: VariantID, parameters: ParameterValues, settings: SilentSettings, probe: PixelPoint,
                input: SIMD4<Double>, passes: [TracePass], gpuOutput: SIMD4<Double>?, cpuReference: SIMD4<Double>,
                differenceULP16: Double?, tracedEqualsUntraced: Bool?) {
        self.blur = blur; self.variant = variant; self.parameters = parameters; self.settings = settings; self.probe = probe
        self.input = input; self.passes = passes; self.gpuOutput = gpuOutput; self.cpuReference = cpuReference
        self.differenceULP16 = differenceULP16; self.tracedEqualsUntraced = tracedEqualsUntraced
    }
}

/// One unit of `Next …` inside a step (a fetch, a tap, an iteration, a compare-exchange).
public struct TraceSubStep: Sendable, Codable, Hashable, Identifiable {
    public var id: Int
    /// Instrument-amber line: what this tap did ("fetch 7 of 13: w 0.07818 · v 0.000").
    public var completed: String
    /// Action-cyan line: what the next tap will do ("fetch 8 at +7.38 px").
    public var next: String
    /// The running partial result after this sub-step (Σ row), when it applies.
    public var runningSum: SIMD4<Double>?
    public var highlighted: [PixelPoint]
    /// Index into the current pass's `taps`, when the sub-step is a tap.
    public var tapIndex: Int?
    /// Spoken after the sub-step, fixed order (SPEC §6.6).
    public var announcement: String
    public init(id: Int, completed: String, next: String, runningSum: SIMD4<Double>?, highlighted: [PixelPoint],
                tapIndex: Int?, announcement: String) {
        self.id = id; self.completed = completed; self.next = next; self.runningSum = runningSum
        self.highlighted = highlighted; self.tapIndex = tapIndex; self.announcement = announcement
    }
}

/// One step of the walk (SPEC §6.3). Generated by CONTENT-LAYERS' TraceScripter from the pass graph and the record.
public struct TraceStep: Sendable, Codable, Hashable, Identifiable {
    public var id: Int
    public var floor: Floor
    public var completed: String
    public var next: String
    /// "Next floor", "Next pass", "Next fetch", "Next iteration", "Next tap", "Finish".
    public var primaryLabel: String
    public var subSteps: [TraceSubStep]
    public var passIndex: Int?
    /// The floor panel's content for this step only.
    public var panel: FloorFacts
    /// Branches, not forks: "if sRGB-encoded: 115/255" (COMPUTED).
    public var branchValues: [LabeledValue]
    /// "Step 10 / 15 · fragment (446, 300) · pass 1 of 2 · horizontal".
    public var phaseLine: String
    /// The one-sentence lesson on the last step.
    public var closingLesson: String?
    public var announcement: String
    public init(id: Int, floor: Floor, completed: String, next: String, primaryLabel: String, subSteps: [TraceSubStep],
                passIndex: Int?, panel: FloorFacts, branchValues: [LabeledValue], phaseLine: String, closingLesson: String?,
                announcement: String) {
        self.id = id; self.floor = floor; self.completed = completed; self.next = next; self.primaryLabel = primaryLabel
        self.subSteps = subSteps; self.passIndex = passIndex; self.panel = panel; self.branchValues = branchValues
        self.phaseLine = phaseLine; self.closingLesson = closingLesson; self.announcement = announcement
    }
}
