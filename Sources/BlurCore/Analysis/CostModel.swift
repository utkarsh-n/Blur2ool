import Foundation

// OWNER: ANALYSIS. Research gpu-pipeline.md §4.1–§4.2 as code: MODELED DRAM bytes per pass, the bandwidth floor with the
// bandwidth's own honesty (the leak-derived 51.2 GB/s is `MODELED · weakSource`; a copy rate measured on this phone replaces
// it), COMPUTED cost curves (fetches per pixel against size for every GPU variant of an entry) and the §4.1 reference table.
//
// Traffic model (GPU §4.1, "ideal cache"): every texel comes from memory once per pass and neighbours share it. A pass reads
// its input once and writes its output once. Passes form a chain: pass i reads what pass i − 1 wrote (pass 0 reads the
// window), at that pass's output scale. Bytes per texel follow the intermediate format (rgba16Float 8 B, rgba8Unorm 4 B),
// except summed-area tables (RGBA fp32, 16 B; a 4-corner query reads the table twice, once per row pair r apart) and FFT
// planes (complex RGBA fp32, 32 B). CPU passes move no GPU bytes. With this model a separable Gaussian moves 4B per
// pixel, the 2-D direct gather 2B, dual Kawase L = 4 3.32B and a SAT box 2B + 80 B: the §4.1 table.

public struct CostModel: CostModeling {
    public init() {}

    /// Bytes per texel of an intermediate format.
    public static func bytesPerTexel(_ format: IntermediateFormat) -> Double { format == .rgba16Float ? 8 : 4 }
    /// RGBA fp32 summed-area table texel.
    public static let tableBytesPerTexel = 16.0
    /// Complex RGBA fp32 FFT plane texel.
    public static let complexBytesPerTexel = 32.0
    /// Source of every MODELED byte count.
    public static let source = SourceRef("gpu-pipeline.md §4.1 (ideal-cache DRAM bytes per pass)")
    /// Source of the leak-derived A17 Pro bandwidth.
    public static let bandwidthSource = SourceRef("gpu-pipeline.md §2.5 (LPDDR5-6400 × 64-bit, third-party; UNVERIFIED)")

    // MARK: Per-pass traffic

    /// MODELED bytes one pass reads and writes.
    public struct PassTraffic: Sendable, Hashable, Identifiable {
        public var id: Int
        public var name: String
        public var readBytes: Double
        public var writeBytes: Double
        public var bytes: Double { readBytes + writeBytes }
    }

    private enum Storage { case image, table, complex, none }

    private static func storage(of pass: PassDescriptor) -> Storage {
        if pass.kind == .cpu { return .none }
        if pass.kind == .fft { return .complex }
        let n = pass.name.uppercased()
        if n.contains("SAT") || n.contains("SCAN") || n.contains("PREFIX") || n.contains("TABLE") { return .table }
        return .image
    }

    private static func bytes(_ s: Storage, _ format: IntermediateFormat) -> Double {
        switch s {
        case .image: bytesPerTexel(format)
        case .table: tableBytesPerTexel
        case .complex: complexBytesPerTexel
        case .none: 0
        }
    }

    /// Reads and writes of every pass of `plan` at `size` (the full window for display, the preview size for previews).
    public func traffic(for plan: PassPlan, size: ImageSize, intermediate: IntermediateFormat) -> [PassTraffic] {
        let n = Double(size.pixelCount)
        var inputScale = 1.0
        var inputBytes = Self.bytesPerTexel(.rgba16Float)   // the window texture is always rgba16Float (ARCHITECTURE §4.1)
        var inputIsTable = false
        var result: [PassTraffic] = []
        for pass in plan.passes {
            let storage = Self.storage(of: pass)
            let s = pass.outputScale
            guard storage != .none else {
                result.append(PassTraffic(id: pass.id, name: pass.name, readBytes: 0, writeBytes: 0))
                continue
            }
            // A query of an RGBA fp32 table reads its corners from two rows r apart: the table twice (GPU §4.1 SAT row).
            let readFactor = inputIsTable && storage != .table && pass.fetchesPerPixel >= 4 ? 2.0 : 1.0
            let read = n * inputScale * inputScale * inputBytes * readFactor
            let outBytes = Self.bytes(storage, intermediate)
            let write = n * s * s * outBytes
            result.append(PassTraffic(id: pass.id, name: pass.name, readBytes: read, writeBytes: write))
            inputScale = s; inputBytes = outBytes; inputIsTable = storage == .table
        }
        return result
    }

    // MARK: CostModeling

    public func cost(for plan: PassPlan, size: ImageSize, intermediate: IntermediateFormat, bandwidth: BandwidthAssumption) -> CostSummary {
        let perPass = traffic(for: plan, size: size, intermediate: intermediate).map(\.bytes)
        let total = perPass.reduce(0, +)
        let floor = bandwidth.gigabytesPerSecond > 0 ? total / (bandwidth.gigabytesPerSecond * 1e9) * 1000 : .infinity
        return CostSummary(bytesMoved: total, perPassBytes: perPass, bandwidth: bandwidth, floorMilliseconds: floor)
    }

    /// Fetches per pixel against size, one series per GPU variant of the entry (the Algorithm floor's cost plot).
    /// `sizes` are σ values in px (σ-held, SPEC §8.1; x = the achieved σ); entries without a σ use their primary
    /// parameter in its own px unit. A variant's series stops where the operator would run another variant (2-D direct
    /// above σ 8). The running variant is the solid primary series; up to three others are B, C and D.
    public func costCurve(for op: any BlurOperator, request: OperatorRequest, sizes: [Double]) -> [PlotSeries] {
        let entry = op.entry
        let running = op.resolveVariant(request).variant
        let gpuVariants = entry.variants.filter(\.runsOnGPU)
        let variants = gpuVariants.filter { $0.id == running } + gpuVariants.filter { $0.id != running }   // running first, then catalog order
        let others: [(SeriesStyle, SeriesRole)] = [(.dashed, .comparisonB), (.dotted, .comparisonC), (.dashDot, .comparisonD)]
        var series: [PlotSeries] = []
        var otherIndex = 0
        for variant in variants {
            var xs: [Double] = [], ys: [Double] = []
            for size in sizes {
                guard let held = AnalysisMath.parameters(for: op, entry: entry, size: size, base: request.parameters) else { return [] }
                let r = AnalysisMath.request(request, parameters: held.parameters, variant: variant.id)
                guard op.resolveVariant(r).variant == variant.id else { continue }
                xs.append(held.x); ys.append(op.passPlan(r).fetchesPerPixel)
            }
            guard !xs.isEmpty else { continue }
            let (style, role): (SeriesStyle, SeriesRole)
            if variant.id == running { (style, role) = (.solid, .primary) }
            else if otherIndex < others.count { (style, role) = others[otherIndex]; otherIndex += 1 }
            else { (style, role) = (.quiet, .reference) }
            series.append(PlotSeries(name: variant.displayName, xs: xs, ys: ys, style: style, role: role, provenance: .computed))
        }
        return series
    }

    /// The cost curve as a plot: x σ (px) or the primary parameter, y fetches per pixel on a log axis.
    public func costPlot(for op: any BlurOperator, request: OperatorRequest, sizes: [Double] = CostModel.standardSizes) -> PlotSpec? {
        let series = costCurve(for: op, request: request, sizes: sizes)
        guard !series.isEmpty else { return nil }
        let entry = op.entry
        let hasSigma = op.holdingSigma(sizes.first ?? 4, current: request.parameters).achievedSigma != nil
        let xAxis = hasSigma ? PlotAxis(label: "σ", unit: "px")
            : PlotAxis(label: entry.primarySpec?.label ?? "SIZE", unit: entry.primarySpec?.unit.symbol)
        let style = NumberStyle.significant(3)
        let parts = series.map { s -> String in
            let lo = s.ys.first ?? 0, hi = s.ys.last ?? 0
            return "\(s.name) \(style.text(lo)) to \(style.text(hi))"
        }
        let summary = "Fetches per pixel against \(hasSigma ? "sigma" : xAxis.label.lowercased()) for \(series.count) "
            + (series.count == 1 ? "algorithm" : "algorithms") + ", computed: " + parts.joined(separator: "; ") + "."
        return PlotSpec(xAxis: xAxis, yAxis: PlotAxis(label: "FETCHES / PX", logarithmic: true), series: series,
                        accessibilitySummary: summary)
    }

    /// σ values (px) of the standard cost plot.
    public static let standardSizes: [Double] = [0.5, 1, 2, 4, 8, 16, 32, 64]

    // MARK: Bandwidth

    /// The bandwidth the floors use: this phone's measured compute-copy rate when the This-phone probe has run (a blit
    /// copy can be inflated by lossless compression, GPU §2.6), then the blit rate, else the leak-derived 51.2 GB/s
    /// (MODELED · weakSource). The device travels separately because `BandwidthAssumption` has no stamp.
    public static func bandwidth(from probes: [DeviceProbeResult]) -> (assumption: BandwidthAssumption, device: DeviceStamp?) {
        for (kind, label) in [(DeviceProbeKind.copyBandwidthCompute, "compute copy measured on this phone"),
                              (DeviceProbeKind.copyBandwidthBlit, "blit copy measured on this phone")] {
            if let probe = probes.last(where: { $0.kind == kind }), let gbps = probe.numbers["gigabytesPerSecond"], gbps.isFinite, gbps > 0 {
                return (BandwidthAssumption(gigabytesPerSecond: gbps, label: label, provenance: .measured, qualifiers: []), probe.device)
            }
        }
        return (.a17ProLeak, nil)
    }

    // MARK: Badged readouts

    /// BYTES (MODELED, ideal cache), FLOOR (MODELED; `weakSource` when the bandwidth is assumed) and BANDWIDTH (its own
    /// badge: MODELED · weakSource `UNVERIFIED PEAK`, or MEASURED with the device that measured it).
    public func readout(_ summary: CostSummary, bandwidthDevice: DeviceStamp? = nil) -> [LabeledValue] {
        let bw = summary.bandwidth
        let measured = bw.provenance == .measured && bandwidthDevice != nil
        let weak = !measured && (bw.qualifiers.contains(.weakSource) || bw.provenance != .measured)
        let bytes = BadgedValue.number(summary.bytesMoved / 1e6, NumberStyle(precision: .decimals(1), unit: "MB", spokenUnit: "megabytes"),
                                       .modeled, source: Self.source, caption: "IDEAL CACHE")
        let floor = BadgedValue.number(summary.floorMilliseconds, .decimals(2, unit: "ms", spokenUnit: "milliseconds"), .modeled,
                                       qualifiers: weak ? .weakSource : [], source: weak ? Self.bandwidthSource : Self.source,
                                       caption: weak ? "UNVERIFIED PEAK" : "AT THE MEASURED COPY RATE")
        let gbStyle = NumberStyle(precision: .decimals(1), unit: "GB/s", spokenUnit: "gigabytes per second")
        let bandwidth: BadgedValue = measured
            ? .number(bw.gigabytesPerSecond, gbStyle, .measured, device: bandwidthDevice, caption: bw.label.uppercased())
            : .number(bw.gigabytesPerSecond, gbStyle, .modeled, qualifiers: .weakSource, source: Self.bandwidthSource,
                      caption: "UNVERIFIED PEAK")
        return [LabeledValue(id: "bytesMoved", label: "BYTES", value: bytes),
                LabeledValue(id: "floorMilliseconds", label: "BANDWIDTH FLOOR", value: floor),
                LabeledValue(id: "bandwidth", label: "BANDWIDTH", value: bandwidth)]
    }

    /// MODELED bytes of each pass ("H", "V" …), for pass tiles and floor 6.
    public func passReadout(_ plan: PassPlan, size: ImageSize, intermediate: IntermediateFormat) -> [LabeledValue] {
        traffic(for: plan, size: size, intermediate: intermediate).map {
            LabeledValue(id: "pass\($0.id)", label: $0.name.uppercased(),
                         value: .number($0.bytes / 1e6, NumberStyle(precision: .decimals(1), unit: "MB", spokenUnit: "megabytes"), .modeled,
                                        source: Self.source, caption: "IDEAL CACHE"))
        }
    }

    /// The fetch-rate time model for one frame (`FetchBudget.modeledFetchesPerSecond`, MODELED · weakSource).
    public func modeledFetchMilliseconds(_ plan: PassPlan, size: ImageSize) -> BadgedValue {
        let ms = plan.fetchesPerFrame(size) / FetchBudget.modeledFetchesPerSecond * 1000
        return .number(ms, ms < 10 ? .decimals(2, unit: "ms", spokenUnit: "milliseconds") : .decimals(0, unit: "ms", spokenUnit: "milliseconds"),
                       .modeled, qualifiers: .weakSource, source: SourceRef("ARCHITECTURE.md §5.5 FetchBudget (M1 Max gather rate scaled to A17 Pro)"),
                       caption: "UNVERIFIED GATHER RATE")
    }

    /// `TOO SLOW TO TIME · ≈ 140 ms MODELED` when a frame exceeds `FetchBudget.full` (review fix E-7), else nil.
    public func tooSlowToTimeLine(_ plan: PassPlan, size: ImageSize) -> BadgedLine? {
        guard plan.fetchesPerFrame(size) > FetchBudget.full else { return nil }
        return BadgedLine([.text("TOO SLOW TO TIME · ≈"), .value(modeledFetchMilliseconds(plan, size: size))])
    }

    // MARK: The GPU §4.1 reference table

    /// One row of gpu-pipeline.md §4.1, evaluated at a radius and storage format.
    public struct ReferenceRow: Sendable, Hashable, Identifiable {
        public var id: String
        public var algorithm: String
        public var passes: BadgedValue
        public var fetchesPerPixel: BadgedValue
        public var dramBytesPerPixel: BadgedValue
        public var fmasPerPixel: BadgedValue
        /// "quadratic", "linear", "linear, half the fetches", "none" …
        public var dependsOnRadius: String
        public var source: SourceRef
        /// The numbers behind the badges, for plots and tests.
        public var fetches: Double
        public var bytes: Double
        public var fmas: Double
    }

    /// GPU §4.1 at radius r (B from `format`; compute tile TG wide; dual Kawase with `levels`; gathers with `samples`).
    /// Fetches and FMAs are COMPUTED; bytes are MODELED (ideal cache); "≈" entries are MODELED.
    public static func referenceTable(radius r: Int, format: IntermediateFormat = .rgba16Float, threadgroupWidth tg: Int = 256,
                                      levels: Int = 4, samples: Int = 64) -> [ReferenceRow] {
        let B = bytesPerTexel(format), R = Double(r), taps = 2 * R + 1
        let integer = NumberStyle.integer(), one = NumberStyle.decimals(1), two = NumberStyle.decimals(2)
        let passNoun = CountNoun("pass", "passes")
        func row(_ id: String, _ name: String, passes: BadgedValue, fetches: Double, fetchStyle: NumberStyle, bytes: Double,
                 fmas: Double, fmaApprox: Bool = false, fmaCaption: String? = nil, _ depends: String) -> ReferenceRow {
            ReferenceRow(id: id, algorithm: name, passes: passes,
                         fetchesPerPixel: .number(fetches, fetchStyle, .computed, source: source),
                         dramBytesPerPixel: .number(bytes, NumberStyle(precision: .decimals(bytes == bytes.rounded() ? 0 : 1), unit: "B",
                                                                         spokenUnit: "bytes"), .modeled, source: source, caption: "IDEAL CACHE"),
                         fmasPerPixel: .number(fmas, integer, fmaApprox ? .modeled : .computed, source: source,
                                               caption: fmaCaption ?? (fmaApprox ? "APPROXIMATE" : nil)),
                         dependsOnRadius: depends, source: source, fetches: fetches, bytes: bytes, fmas: fmas)
        }
        func passes(_ n: Int) -> BadgedValue { .number(Double(n), .integer(noun: passNoun), .computed, source: source) }
        // Dual Kawase over L levels, per window pixel. S = Σ_{l=0}^{L−1} 4^−l is the area of levels 0…L−1.
        // Down passes read levels 0…L−1 and write 1…L; up passes read L…1 and write L−1…0 (the chain model above):
        // bytes = (4S − 2 + 2·4^−L)·B (3.32B at L = 4); fetches = 5 per down-pixel + 8 per up-pixel (12.3 at L = 4).
        let L = Double(levels)
        let S = (1 - pow(0.25, L)) / 0.75
        let downFetches = 5 * (S - 1 + pow(0.25, L))
        let upFetches = 8 * S
        let kawaseBytes = (4 * S - 2 + 2 * pow(0.25, L)) * B
        return [
            row("direct-2d", "Direct 2-D convolution", passes: passes(1), fetches: taps * taps, fetchStyle: integer, bytes: 2 * B,
                fmas: 4 * taps * taps, "quadratic"),
            row("separable", "Separable, discrete taps", passes: passes(2), fetches: 2 * taps, fetchStyle: integer, bytes: 4 * B,
                fmas: 8 * taps, "linear"),
            row("linear-sampled", "Separable, linear-sampled", passes: passes(2), fetches: 2 * (1 + 2 * (R / 2).rounded(.up)),
                fetchStyle: integer, bytes: 4 * B, fmas: 4 * taps, fmaApprox: true, "linear, half the fetches"),
            row("compute-tile", "Separable, compute tile (\(tg) wide)", passes: passes(2), fetches: 2 * (1 + 2 * R / Double(tg)),
                fetchStyle: two, bytes: 4 * B, fmas: 8 * taps, "linear (ALU); texture fetches nearly constant"),
            row("running-sum", "Running-sum box", passes: passes(2), fetches: 6, fetchStyle: integer, bytes: 4 * B, fmas: 16, "none"),
            row("sat", "Box via SAT (RGBA fp32 table)", passes: passes(3), fetches: 7, fetchStyle: integer,
                bytes: 2 * B + 5 * tableBytesPerTexel, fmas: 16, fmaApprox: true, "none"),
            row("dual-kawase", "Dual Kawase, \(levels) levels", passes: passes(2 * levels), fetches: downFetches + upFetches,
                fetchStyle: one, bytes: kawaseBytes, fmas: 13, fmaApprox: true, fmaCaption: "PER LEVEL-PIXEL", "σ set by levels and offset"),
            row("mip-chain", "Mip chain + one lookup", passes: .number(2, .integer(noun: passNoun), .computed, source: source,
                                                                       caption: "BLIT CHAIN + LOOKUP"),
                fetches: 1, fetchStyle: integer, bytes: (4.0 / 3.0) * B + 2 * B, fmas: 4, fmaApprox: true, "none"),
            row("gather", "Radial / bokeh gather, \(samples) samples", passes: passes(1), fetches: Double(samples), fetchStyle: integer,
                bytes: 2 * B, fmas: 4 * Double(samples), "samples and footprint area"),
        ]
    }
}
