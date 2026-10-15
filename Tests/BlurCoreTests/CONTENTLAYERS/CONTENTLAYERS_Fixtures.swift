import Foundation
@testable import BlurCore

// OWNER: CONTENT-LAYERS. Test fixtures: a tool-conventions double with the research laws (so the rail's SLIDE can be
// checked while SEMANTICS is still a seed), fake operators covering every template class of SPEC §5.2 that no family has
// registered yet, contexts, Runs and a two-pass CPU trace record of guided descent A.

enum CONTENTLAYERS_Fixtures {
    static let phone = DeviceStamp(deviceModel: "iPhone 15 Pro Max", gpuName: "Apple A17 Pro GPU", gpuFamily: "Apple9", osVersion: "iOS 27.0",
                                   osBuild: "test", isSimulator: false, date: Date(timeIntervalSince1970: 1_760_400_000), thermal: .nominal, lowPowerMode: false)
    static let gaussian = GaussianOperator()

    static func parameters(_ op: any BlurOperator, _ overrides: [ParameterKey: ParameterValue] = [:]) -> ParameterValues {
        var p = op.entry.defaultParameters
        for (k, v) in overrides { p[k] = v }
        return p
    }

    static func configuration(_ op: any BlurOperator, variant: VariantID? = nil, parameters: ParameterValues? = nil, settings: SilentSettings = .standard,
                              specimen: SpecimenID = "night-city", probe: PixelPoint = PixelPoint(x: 447, y: 455), window: Int = 894) -> RenderConfiguration {
        RenderConfiguration(blur: op.entry.id, variant: variant ?? op.entry.defaultVariant, parameters: parameters ?? op.entry.defaultParameters,
                            settings: settings, specimen: specimen, specimenOptions: .standard, pan: .zero, probe: probe, windowSize: window)
    }

    static func context(_ config: RenderConfiguration, home: String = "swiftui", live: LiveFacts = LiveFacts(), content: OperatorContent? = nil,
                        compareB: RenderConfiguration? = nil) -> FloorContext {
        FloorContext(configuration: config, homeToolID: home, displayScale: 3, live: live, content: content, compareB: compareB)
    }

    // MARK: Runs

    static func run(_ op: any BlurOperator, _ config: RenderConfiguration, kind: RunKind = .display, timing: TimingSummary? = nil,
                    probe: ProbeReadout? = nil, dispatch: [PassDispatch] = [], shader: ShaderProvenance? = nil, quality: RenderQuality = .full,
                    gpu: GPUFacts? = nil, parity: ParitySummary? = nil) -> Run {
        let request = config.operatorRequest
        let plan = op.passPlan(request)
        return Run(kind: kind, generation: 1, slot: .a, configuration: config, resolvedVariant: op.resolveVariant(request), quality: quality,
                   device: phone, gpu: gpu, kernel: KernelSummary(sigmaEff: op.sigma(request), excessKurtosis: nil, fetchesPerPixel: plan.fetchesPerPixel,
                                                                  tapsPerAxis: nil, passNames: plan.passes.map(\.name)),
                   dispatch: dispatch, timing: timing, cost: nil, parity: parity, probe: probe, shape: nil, shader: shader, trace: nil,
                   calibration: nil, deviceProbe: nil)
    }

    static func timing(_ ms: Double = 0.61, perPass: [PassTiming] = []) -> TimingSummary {
        TimingSummary(method: .commandBuffer, warmups: 3, samples: 15, medianMilliseconds: ms, iqrMilliseconds: 0.02, perPass: perPass,
                      fusedMedianMilliseconds: nil, interleaved: false, thermalAtStart: .nominal, thermalAtEnd: .nominal, lowPowerMode: false,
                      overheadMilliseconds: 0.04)
    }

    static let a17 = GPUFacts(deviceName: "Apple A17 Pro GPU", familyName: "Apple9", maxThreadsPerThreadgroup: 1024, maxThreadgroupMemoryLength: 32_768,
                              supportsApple7: true, supports32BitFloatFiltering: true, readWriteTextureTier: 2, supportsStageBoundaryCounters: false,
                              isSimulator: false, forcedApple2Limits: false)

    /// A live picture with every kind of Run data: timing, probe, compute-tile dispatch, shader provenance, parity.
    static func richLive(_ op: any BlurOperator, _ config: RenderConfiguration, shader: ShaderProvenance? = nil) -> LiveFacts {
        let request = config.operatorRequest
        let plan = op.passPlan(request)
        let dispatch = plan.passes.map { p in
            PassDispatch(passIndex: p.id, name: p.name, encoder: p.kind == .compute ? .compute : .render,
                         functionNames: ["b2_test_\(p.name.lowercased())"], threadsPerThreadgroup: p.kind == .compute ? [256, 1, 1] : [0, 0, 0],
                         threadgroups: p.kind == .compute ? [4, config.windowSize, 1] : [0, 0, 0], staticThreadgroupMemoryBytes: 0,
                         dynamicThreadgroupMemoryBytes: p.kind == .compute ? 2240 : 0, threadExecutionWidth: 32, pipelineMaxThreads: 1024,
                         outputSize: .square(config.windowSize), outputHasShaderWrite: p.kind == .compute, modeledBytes: 12.8e6)
        }
        let perPass = plan.passes.map { PassTiming(passIndex: $0.id, passName: $0.name, medianMilliseconds: 0.30, iqrMilliseconds: 0.01, samples: 15) }
        let probe = ProbeReadout(probe: config.probe, input: SIMD4(0, 0, 0, 1), output: SIMD4(0.0885, 0.0885, 0.0885, 1),
                                 perPass: plan.passes.map { _ in SIMD4(0.0885, 0.0885, 0.0885, 1) })
        let parity = ParitySummary(stats: DifferenceStats(maxAbs: 4.9e-4, rms: 2e-4, argmax: .zero, maxLSB8: 1, maxULP16: 2, count: 16_384),
                                   region: PixelRegion.centred(on: config.probe, side: 128, inside: .square(config.windowSize)),
                                   tolerance: .bilinear, passed: true)
        let r = run(op, config, kind: .timing, timing: timing(perPass: perPass), probe: probe, dispatch: dispatch, shader: shader, gpu: a17, parity: parity)
        return LiveFacts(run: r, timedRun: r)
    }

    // MARK: Content

    static func stepEdges(_ n: Int = 894) -> OperatorContent {
        StepEdgesGenerator().canvas(windowSize: n, margin: SpecimenGeometry.margin, options: .standard, text: nil).window(pan: .zero)
    }

    static func nightCity(_ n: Int = 894) -> OperatorContent {
        NightCityGenerator().canvas(windowSize: n, margin: SpecimenGeometry.margin, options: .standard, text: nil).window(pan: .zero)
    }

    /// A small deterministic test image: a vertical step plus a horizontal ramp and a few bright dots.
    static func smallImage(_ n: Int = 128) -> OperatorContent {
        var image = ImageBuffer(width: n, height: n)
        for y in 0..<n { for x in 0..<n {
            let v: Float = (x >= n / 2 ? 0.6 : 0.4) + Float(y) / Float(n) * 0.1 + ((x * 7 + y * 13) % 11 == 0 ? 0.3 : 0)
            image[x, y] = SIMD4(v, v, v, 1)
        } }
        return OperatorContent(image: image)
    }

    // MARK: Guided descent A, traced on the CPU (both passes, every fetch)

    static let descentAProbe = PixelPoint(x: 446, y: 300)
    static var descentAParameters: ParameterValues {
        parameters(gaussian, ["sigma": .double(4), "truncation": .choice("3"), "discretisation": .choice("sampled")])
    }
    static var descentAConfiguration: RenderConfiguration {
        configuration(gaussian, variant: GaussianOperator.linearSampled, parameters: descentAParameters, specimen: "step-edges", probe: descentAProbe)
    }

    /// The two linear-sampled passes at the probe, tap order centre, +o₁, −o₁, +o₂, … (KernelMath.linearSampledTable).
    static func descentARecord(source: TraceSource = .cpuReconstruction) -> TraceRecord {
        let request = descentAConfiguration.operatorRequest
        let k = gaussian.kernel(request), table = KernelMath.linearSampledTable(k)
        let window = stepEdges().image
        let origin = PixelPoint(x: descentAProbe.x - 32, y: descentAProbe.y - 32)
        let crop = window.crop(PixelRegion(origin: origin, size: .square(64)))
        let result = try! gaussian.reference(crop, request, auxiliary: .none, options: .exact)
        let hImage = result.intermediates[0]
        let local = PixelPoint(x: 32, y: 32), c = local.centre
        var order: [(Double, Double)] = [(0, table.weights[0])]
        for i in 1..<table.offsets.count { order += [(table.offsets[i], table.weights[i]), (-table.offsets[i], table.weights[i])] }
        func pass(_ id: Int, horizontal: Bool, image: ImageBuffer) -> TracePass {
            var sum = SIMD4<Double>.zero
            var taps: [TraceTap] = []
            for (n, (o, w)) in order.enumerated() {
                let u = horizontal ? c.x + o : c.x, v = horizontal ? c.y : c.y + o
                let fetched = image.bilinear(u, v, edge: .clamp)
                sum += fetched * w
                let t = (horizontal ? u : v) - 0.5
                let fraction = t - floor(t)
                taps.append(TraceTap(id: n, position: SIMD2(u + Double(origin.x), v + Double(origin.y)), offset: horizontal ? SIMD2(o, 0) : SIMD2(0, o),
                                     texels: [], requestedFraction: horizontal ? SIMD2(fraction, 0) : SIMD2(0, fraction), quantizedFraction: nil,
                                     weight: w, fetched: fetched, contribution: fetched * w, runningSum: sum))
            }
            let plan = gaussian.passPlan(request)
            return TracePass(id: id, descriptor: plan.passes[id], source: source, pixel: descentAProbe, taps: taps, truncatedTapCount: 0,
                             outputAtProbe: sum, neighbourhoodIn: nil, neighbourhoodOut: nil)
        }
        let h = pass(0, horizontal: true, image: crop)
        let v = pass(1, horizontal: false, image: hImage)
        return TraceRecord(blur: gaussian.entry.id, variant: GaussianOperator.linearSampled, parameters: request.parameters, settings: request.settings,
                           probe: descentAProbe, input: SIMD4<Double>(window[descentAProbe.x, descentAProbe.y]), passes: [h, v],
                           gpuOutput: source == .gpuRecord ? v.outputAtProbe : nil, cpuReference: v.outputAtProbe, differenceULP16: nil,
                           tracedEqualsUntraced: nil)
    }
}

// MARK: - Tool conventions double (the research laws: STACK §8, CAL §5; SPEC §5.3 A floor 1)

struct CONTENTLAYERS_FakeTools: ToolConventionProviding {
    var all: [ToolConvention] {
        [ToolConvention(id: "swiftui", toolName: "SwiftUI", controlName: ".blur(radius:)", unit: .pt, provenance: .inferred,
                        source: SourceRef("live-calibration.md §5.1 (MEASURED offscreen, macOS 27.2)"),
                        lawDescription: "σ = r·scale below ≈ 5 px, 0.90·r·scale above"),
         ToolConvention(id: "css", toolName: "CSS", controlName: "blur()", unit: .cssPx, provenance: .reference,
                        source: SourceRef("CSS Filter Effects Level 1"), lawDescription: "σ = value (CSS px = pt)"),
         ToolConvention(id: "figma", toolName: "Figma", controlName: "Layer blur", unit: .pt, provenance: .inferred,
                        source: SourceRef("stack-semantics.md §4.1"), lawDescription: "σ = value / 2"),
         ToolConvention(id: "photoshop", toolName: "Photoshop", controlName: "Gaussian Blur Radius", unit: .px, provenance: .reference,
                        source: SourceRef("stack-semantics.md §4"), lawDescription: nil)]
    }

    func typedValue(toolID: String, blur: BlurID, sigmaPx: Double, displayScale: Double, measuredLaw: CalibrationLaw?) -> BadgedValue {
        guard sigmaPx > 0 else { return .unverified(toolID + " mapping") }
        let pt = NumberStyle.decimals(2, unit: "pt", spokenUnit: "points")
        switch toolID {
        case "swiftui":
            let r = sigmaPx <= 5 ? sigmaPx / displayScale : sigmaPx / (0.90 * displayScale)
            return .number(r, pt, .inferred, source: SourceRef("live-calibration.md §5.1"), caption: "MACOS LAW")
        case "css": return .number(sigmaPx / displayScale, NumberStyle.decimals(2, unit: "CSS px", spokenUnit: "CSS pixels"), .reference,
                                   source: SourceRef("CSS Filter Effects Level 1"))
        case "figma": return .number(2 * sigmaPx / displayScale, pt, .inferred)
        default: return .unverified(toolID + " mapping")
        }
    }

    func sigmaPx(toolID: String, blur: BlurID, typed value: Double, displayScale: Double, measuredLaw: CalibrationLaw?) -> BadgedValue {
        let px = ContentStyle.px2
        switch toolID {
        case "swiftui":
            let s = value * displayScale
            return .number(s <= 5 ? s : 0.90 * s, px, .inferred)
        case "css": return .number(value * displayScale, px, .reference, source: SourceRef("CSS Filter Effects Level 1"))
        case "figma": return .number(value / 2 * displayScale, px, .inferred)
        default: return .unverified(toolID + " mapping")
        }
    }
}

// MARK: - Fake operators for the template classes no family has registered in this mirror

enum CONTENTLAYERS_Kind: String, CaseIterable {
    case rank, adaptive, spaceVariant, system, globalFFT, atlas, gather2D, sparse, pde, stochastic, derived, recursive
}

struct CONTENTLAYERS_FakeOperator: BlurOperator {
    let kind: CONTENTLAYERS_Kind

    var entry: CatalogEntry {
        let sigmaSpec = ParameterSpec(key: "sigma", label: "SIGMA", spokenLabel: "sigma", unit: .px,
                                      kind: .continuous(ContinuousSpec(range: 0.3...64, fineStep: 0.1, decimals: 1)), defaultValue: .double(2))
        let radiusSpec = ParameterSpec(key: "radius", label: "RADIUS", spokenLabel: "radius", unit: .px,
                                       kind: .integer(IntegerSpec(range: 1...8)), defaultValue: .int(1))
        let centre = ParameterSpec(key: "centre", label: "CENTRE", spokenLabel: "centre", unit: .px, kind: .position, defaultValue: .point(x: 64, y: 64))
        let card = CardRows(psfShape: CardRow("test", .computed), response: CardRow("test", .computed), edges: CardRow("test", .computed),
                            cost: CardRow("test", .computed), artifacts: CardRow("test", .computed), usedIn: CardRow("tests", .reference, source: SourceRef("tests")))
        let t: (Tier, Verdict, LinearityClass, PropertyFlags, CostClass, AlgorithmClass, String, [ParameterSpec], ParameterKey)
        switch kind {
        case .rank: t = (.tier1, .rankFilter, .nonlinear, [.shiftInvariant], .constant, .selection, "rank", [radiusSpec], "radius")
        case .adaptive: t = (.tier1, .adaptiveBlur, .nonlinear, [.shiftInvariant, .edgePreserving, .dataDependent], .quadraticR, .adaptiveWeighted, "w·f", [sigmaSpec], "sigma")
        case .spaceVariant: t = (.tier1, .lsvBlur, .lsv, [.linear], .samples, .spaceVariantGather, "ray", [sigmaSpec, centre], "sigma")
        case .system: t = (.system, .trueBlur, .system, [], .capture, .system, "sys",
                           [ParameterSpec(key: "radius", label: "RADIUS", spokenLabel: "radius", unit: .pt,
                                          kind: .continuous(ContinuousSpec(range: 0...20, fineStep: 0.1, decimals: 1)), defaultValue: .double(4))], "radius")
        case .globalFFT: t = (.tier2, .trueBlur, .lsi, [.linear, .shiftInvariant], .global, .globalFFT, "FFT", [sigmaSpec], "sigma")
        case .atlas: t = (.tier3, .trueBlur, .lsi, [.linear, .shiftInvariant, .positiveKernel], .linearR, .atlasOnly, "G", [sigmaSpec], "sigma")
        case .gather2D: t = (.tier1, .trueBlur, .lsi, [.linear, .shiftInvariant, .isotropic, .positiveKernel], .quadraticR, .gather2D, "disc", [sigmaSpec], "sigma")
        case .sparse: t = (.tier1, .trueBlur, .lsi, [.linear, .shiftInvariant, .positiveKernel], .logN, .sparseIterated, "G", [sigmaSpec], "sigma")
        case .pde: t = (.tier1, .trueBlur, .lsi, [.linear, .shiftInvariant, .positiveKernel], .iterative, .iterativePDE, "PDE", [sigmaSpec], "sigma")
        case .stochastic: t = (.tier1, .blurInExpectation, .expectation, [], .samples, .stochastic, "rect", [sigmaSpec], "sigma")
        case .derived: t = (.tier1, .notABlur, .lsi, [.linear, .shiftInvariant], .linearR, .derived, "G", [sigmaSpec], "sigma")
        case .recursive: t = (.tier1, .trueBlur, .lsi, [.linear, .shiftInvariant, .positiveKernel, .separable], .constant, .recursive, "exp", [sigmaSpec], "sigma")
        }
        let variant: VariantID = VariantID(rawValue: "contentlayers-" + kind.rawValue + "-v")
        return CatalogEntry(id: BlurID(rawValue: "contentlayers-" + kind.rawValue), displayName: "Test " + kind.rawValue, family: .f1, tier: t.0,
                            verdict: t.1, linearity: t.2, separability: kind == .recursive ? .yes : .no, properties: t.3, costClass: t.4, algorithmClass: t.5,
                            signature: "A test entry for the \(kind.rawValue) template.", mathSymbol: t.6, glyph: GlyphSpec(.none), parameters: t.7,
                            primary: t.8, deck: .none(message: "TEST"),
                            variants: [VariantDescriptor(id: variant, displayName: "Test", tier: t.0, algorithmClass: t.5, costClass: t.4, runsOnGPU: t.0 != .tier3)],
                            defaultVariant: variant, defaultSpecimen: "night-city", handles: [],
                            appleTwins: kind == .system ? [AppleTwinSpec(id: "SwiftUI.blur", call: ".blur(radius: r)", mapping: "σ ≈ r·scale", provenance: .inferred,
                                                                         source: SourceRef("tests"), subject: .swiftUIBlur)] : [],
                            tell: TellSpec(specimen: "night-city", text: "test"), neighbours: [], traceDepth: .full, heroOrder: nil, card: card,
                            unverified: [], detailReference: "tests", sources: [SourceRef("tests")])
    }

    func sigmaValue(_ r: OperatorRequest) -> Double { r.parameters.double("sigma") ?? 2 }

    func passPlan(_ r: OperatorRequest) -> PassPlan {
        func pass(_ id: Int, _ name: String, _ taps: Double, kind: PassKind = .fragment, scale: Double = 1) -> PassDescriptor {
            PassDescriptor(id: id, name: name, kind: kind, fetchesPerPixel: taps, tapsPerPixel: taps, outputScale: scale, traceable: true, summary: "test pass")
        }
        switch kind {
        case .rank: return PassPlan(algorithmName: "Sorting network", passes: [pass(0, "SORT", 9)], supportRadius: 1)
        case .adaptive: return PassPlan(algorithmName: "Brute force", passes: [pass(0, "BF", 49, kind: .compute)], supportRadius: 3)
        case .spaceVariant: return PassPlan(algorithmName: "Gather", passes: [pass(0, "RAYS", 32, kind: .compute)], supportRadius: 40)
        case .system: return PassPlan(algorithmName: "System", passes: [pass(0, "SYS", 1, kind: .coreImage)])
        case .globalFFT: return PassPlan(algorithmName: "FFT", passes: [pass(0, "FFT ROWS", 10, kind: .compute), pass(1, "MULTIPLY", 1, kind: .compute),
                                                                     pass(2, "INVERSE", 10, kind: .compute)], supportRadius: nil)
        case .atlas: return PassPlan(algorithmName: "CPU", passes: [pass(0, "CPU", 25, kind: .cpu)], supportRadius: 6)
        case .gather2D: return PassPlan(algorithmName: "Gather", passes: [pass(0, "2-D", 49)], supportRadius: 3)
        case .sparse: return PassPlan(algorithmName: "Pyramid", passes: [pass(0, "↓1", 4, scale: 0.5), pass(1, "↓2", 4, scale: 0.25), pass(2, "↑2", 4, scale: 0.5),
                                                                       pass(3, "↑1", 4)], supportRadius: 12)
        case .pde: return PassPlan(algorithmName: "Explicit", passes: (0..<8).map { pass($0, "IT", 5, kind: .compute) }, supportRadius: 8)
        case .stochastic: return PassPlan(algorithmName: "Random neighbour", passes: [pass(0, "JITTER", 1)], supportRadius: 3)
        case .derived: return PassPlan(algorithmName: "Unsharp", passes: [pass(0, "H", 13), pass(1, "V", 13), pass(2, "MIX", 1)], supportRadius: 6)
        case .recursive: return PassPlan(algorithmName: "Recursive", passes: [pass(0, "CAUSAL", 3, kind: .compute), pass(1, "ANTICAUSAL", 3, kind: .compute)], supportRadius: nil)
        }
    }

    func kernel2D(_ r: OperatorRequest, at p: PixelPoint, content: OperatorContent?) -> Kernel2D? {
        let s = sigmaValue(r)
        switch kind {
        case .rank, .globalFFT: return nil
        case .adaptive:
            guard let image = content?.image, image.size.contains(p) else { return nil }
            let centre = ContentValues.scalar(image.fetch(p.x, p.y, edge: .clamp))
            var w = [Double](repeating: 0, count: 49)
            for dy in -3...3 { for dx in -3...3 {
                let v = ContentValues.scalar(image.fetch(p.x + dx, p.y + dy, edge: .clamp))
                w[(dy + 3) * 7 + dx + 3] = exp(-Double(dx * dx + dy * dy) / (2 * s * s)) * exp(-(v - centre) * (v - centre) / (2 * 0.1 * 0.1))
            } }
            let total = w.reduce(0, +)
            return Kernel2D(width: 7, height: 7, originX: 3, originY: 3, weights: w.map { $0 / total })
        case .spaceVariant:
            // A radial streak whose length grows with the distance from the centre (zoom-like, a = 0.1).
            let c = r.parameters.point("centre") ?? SIMD2(64, 64)
            let d = SIMD2(Double(p.x) + 0.5 - c.x, Double(p.y) + 0.5 - c.y)
            let len = Swift.max(1, Int((0.1 * (d.x * d.x + d.y * d.y).squareRoot()).rounded()))
            let angle = atan2(d.y, d.x)
            let size = 2 * len + 1
            var w = [Double](repeating: 0, count: size * size)
            for k in -len...len {
                let x = Int((Double(k) * cos(angle)).rounded()) + len, y = Int((Double(k) * sin(angle)).rounded()) + len
                w[y * size + x] += 1
            }
            let total = w.reduce(0, +)
            return Kernel2D(width: size, height: size, originX: len, originY: len, weights: w.map { $0 / total })
        case .gather2D:
            var w = [Double](repeating: 0, count: 49)
            for dy in -3...3 { for dx in -3...3 where dx * dx + dy * dy <= 9 { w[(dy + 3) * 7 + dx + 3] = 1 } }
            let total = w.reduce(0, +)
            return Kernel2D(width: 7, height: 7, originX: 3, originY: 3, weights: w.map { $0 / total })
        case .stochastic:
            let b = KernelMath.box(radius: 3)
            return Kernel2D(separable: b, b)
        case .derived:
            let g = KernelMath.gaussianSampled(sigma: s, truncation: 3)
            var k = Kernel2D(separable: g, g)
            k.weights = k.weights.map { -0.5 * $0 }
            k.weights[k.originY * k.width + k.originX] += 1.5
            return k
        case .recursive:
            let e = Kernel1D(weights: (-12...12).map { exp(-abs(Double($0)) / s) }, origin: 12).normalised
            return Kernel2D(separable: e, e)
        case .pde, .sparse, .atlas, .system:
            let g = KernelMath.gaussianSampled(sigma: kind == .system ? 4 : s, truncation: 3)
            return Kernel2D(separable: g, g)
        }
    }

    func psf(at point: PixelPoint, _ r: OperatorRequest, content: OperatorContent?) -> PSF? {
        guard let k = kernel2D(r, at: point, content: content) else { return nil }
        let local = kind == .spaceVariant || kind == .adaptive
        return PSF(kernel: k, isLocal: local, point: local ? point : nil, provenance: kind == .adaptive ? .live : .computed)
    }

    func response(_ q: ResponseQuery, _ r: OperatorRequest, content: OperatorContent?) -> ResponseCurve? {
        let f = q.frequencies
        switch kind {
        case .rank: return nil
        case .adaptive:
            let a = q.amplitude ?? 0.2
            let s = sigmaValue(r) * (1 - exp(-a / 0.1))
            return ResponseCurve(kind: .amplitudeTransfer(amplitude: a), frequencies: f, values: f.map { KernelMath.gaussianResponse(sigma: s, frequency: $0) })
        case .globalFFT:
            return ResponseCurve(kind: .signedTransfer, frequencies: f, values: f.map { $0 <= 0.1 ? 1 : 0 })
        case .spaceVariant:
            guard let k = kernel2D(r, at: q.point ?? PixelPoint(x: 100, y: 64), content: content) else { return nil }
            return ResponseCurve(kind: .local(q.point ?? .zero), frequencies: f, values: KernelMath.response(k, axisDegrees: q.axisDegrees, frequencies: f))
        default:
            guard let k = kernel2D(r, at: .zero, content: content) else { return nil }
            return ResponseCurve(kind: .signedTransfer, frequencies: f, values: KernelMath.response(k.marginalX, frequencies: f),
                                 provenance: kind == .system ? .modeled : .computed)
        }
    }

    func sigma(_ r: OperatorRequest) -> Double? {
        [.rank, .spaceVariant, .system, .adaptive].contains(kind) ? nil : kernel2D(r, at: .zero, content: nil)?.marginalX.sigma
    }

    func holdingSigma(_ sigma: Double, current: ParameterValues) -> SigmaHoldResult {
        var p = current
        if entry.spec("sigma") != nil { p["sigma"] = .double(sigma) }
        return SigmaHoldResult(parameters: p, requestedSigma: sigma, achievedSigma: entry.spec("sigma") != nil ? sigma : nil,
                               statusLine: .words("σ NOT DEFINED · TEST"))
    }

    func reference(_ input: ImageBuffer, _ r: OperatorRequest, auxiliary: AuxiliaryInputs, options: ReferenceOptions) throws -> ReferenceResult {
        switch kind {
        case .globalFFT: throw ReferenceError.notImplemented("test FFT")
        case .rank:
            var out = ImageBuffer(width: input.width, height: input.height)
            for y in 0..<input.height { for x in 0..<input.width {
                var v: [SIMD4<Float>] = []
                for dy in -1...1 { for dx in -1...1 { v.append(input.fetch(x + dx, y + dy, edge: .clamp)) } }
                out[x, y] = v.sorted { $0.x < $1.x }[4]
            } }
            return ReferenceResult(output: out, intermediates: [out])
        case .adaptive, .spaceVariant, .system:
            return ReferenceResult(output: input, intermediates: [input])
        default:
            guard let k = kernel2D(r, at: .zero, content: nil) else { throw ReferenceError.notImplemented("no kernel") }
            var out = ImageBuffer(width: input.width, height: input.height)
            for y in 0..<input.height { for x in 0..<input.width {
                var s = SIMD4<Double>.zero
                for j in 0..<k.height { for i in 0..<k.width where k[i, j] != 0 {
                    s += SIMD4<Double>(input.fetch(x + i - k.originX, y + j - k.originY, edge: .clamp)) * k[i, j]
                } }
                out[x, y] = SIMD4<Float>(s)
            } }
            return ReferenceResult(output: out, intermediates: [out])
        }
    }

    func traceReconstruction(probe: PixelPoint, input: ImageBuffer, _ r: OperatorRequest, auxiliary: AuxiliaryInputs) -> TraceRecord {
        let plan = passPlan(r)
        var taps: [TraceTap] = []
        var sum = SIMD4<Double>.zero
        if kind == .rank {
            var values: [(PixelPoint, SIMD4<Double>)] = []
            for dy in -1...1 { for dx in -1...1 { values.append((PixelPoint(x: probe.x + dx, y: probe.y + dy), SIMD4<Double>(input.fetch(probe.x + dx, probe.y + dy, edge: .clamp)))) } }
            let ranks = values.indices.sorted { values[$0].1.x < values[$1].1.x }
            for (n, (p, v)) in values.enumerated() {
                taps.append(TraceTap(id: n, position: p.centre, offset: SIMD2(Double(p.x - probe.x), Double(p.y - probe.y)), texels: [TexelContribution(texel: p, fraction: 1)],
                                     requestedFraction: nil, quantizedFraction: nil, weight: 0, fetched: v, contribution: .zero, runningSum: .zero,
                                     extras: ["rank": Double(ranks.firstIndex(of: n) ?? 0)]))
            }
            sum = values[ranks[4]].1
        } else if let k = kernel2D(r, at: probe, content: OperatorContent(image: input)) {
            var n = 0
            for j in 0..<k.height { for i in 0..<k.width where k[i, j] != 0 {
                let p = PixelPoint(x: probe.x + i - k.originX, y: probe.y + j - k.originY)
                let v = SIMD4<Double>(input.fetch(p.x, p.y, edge: .clamp))
                sum += v * k[i, j]
                var extras: [String: Double] = [:]
                if kind == .adaptive { extras = ["spatialWeight": 0.5, "rangeWeight": k[i, j] * 2] }
                if kind == .pde { extras = ["iteration": Double(n)] }
                taps.append(TraceTap(id: n, position: p.centre, offset: SIMD2(Double(i - k.originX), Double(j - k.originY)),
                                     texels: [TexelContribution(texel: p, fraction: 1)], requestedFraction: nil, quantizedFraction: nil, weight: k[i, j],
                                     fetched: v, contribution: v * k[i, j], runningSum: sum, extras: extras))
                n += 1
            } }
        }
        let pass = TracePass(id: 0, descriptor: plan.passes[0], source: .cpuReconstruction, pixel: probe, taps: taps, truncatedTapCount: 0,
                             outputAtProbe: sum, neighbourhoodIn: nil, neighbourhoodOut: nil)
        return TraceRecord(blur: entry.id, variant: r.variant, parameters: r.parameters, settings: r.settings, probe: probe,
                           input: SIMD4<Double>(input.fetch(probe.x, probe.y, edge: .clamp)), passes: [pass], gpuOutput: nil, cpuReference: sum,
                           differenceULP16: nil, tracedEqualsUntraced: nil)
    }

    func uniqueNumber(_ r: OperatorRequest) -> LabeledValue { LabeledValue(id: "unique", label: "UNIQUE", value: .number(0, .decimals(0), .computed)) }
    func floorKey(_ floor: Floor, _ r: OperatorRequest) -> FloorKey { FloorKey(identity: [kind.rawValue], description: kind.rawValue) }
}
