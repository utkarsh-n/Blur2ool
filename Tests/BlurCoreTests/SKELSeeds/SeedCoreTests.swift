import Foundation
import Testing
@testable import BlurCore

// OWNER: SKEL. CPU tests of the seeds the skeleton added (ARCHITECTURE §9.1): the v0 Night City, the compute-tile budget,
// the MRT seed's reference, and the honesty of everything the seed builders put on screen (PLAN S9). These live beside
// Tests/BlurCoreTests/SKEL (which must stay byte-identical to Documentation/interfaces) and run with `core-test --area SKEL`.

@Suite struct SKEL_NightCityV0 {
    @Test func registeredAndDeterministic() {
        #expect(SpecimenRegistry.generator("night-city") != nil)
        let a = NightCityGenerator().canvas(windowSize: 256, margin: SpecimenGeometry.margin, options: .standard, text: nil)
        let b = NightCityGenerator().canvas(windowSize: 256, margin: SpecimenGeometry.margin, options: .standard, text: nil)
        #expect(a.image == b.image)
        #expect(a.image.width == 256 + 512)
    }

    @Test func referenceLightAndProbeAt894() {
        let canvas = NightCityGenerator().canvas(windowSize: 894, margin: SpecimenGeometry.margin, options: .standard, text: nil)
        let window = canvas.window(pan: .zero).image
        #expect(canvas.defaultProbe == PixelPoint(x: 447, y: 455))
        #expect(window[447, 447] == SIMD4<Float>(100, 100, 100, 1))                  // the reference light at c
        #expect(window[447, 455] == SIMD4<Float>(0, 0, 0, 1))                        // SPEC §11 rule 2: IN = 0 at the probe
        let peak = window.pixels.map { $0.max() }.max() ?? 0
        #expect(peak <= 1000 && peak >= 100)                                          // HDR, below fp16's 65,504 even at +6 EV
        let lights = window.pixels.filter { $0.x >= 2 }.count
        #expect(lights >= 20)                                                         // a few HDR lights inside the window
        let buildings = window.pixels.filter { $0.x > 0.0199 && $0.x < 0.0601 }.count
        #expect(buildings > 10_000)                                                   // dark silhouettes 0.02–0.06
    }

    @Test func exposureIsNotInTheCanvas() {
        let lit = NightCityGenerator().canvas(windowSize: 128, margin: SpecimenGeometry.margin, options: SpecimenOptions(exposureEV: 4), text: nil)
        let plain = NightCityGenerator().canvas(windowSize: 128, margin: SpecimenGeometry.margin, options: .standard, text: nil)
        #expect(lit.image == plain.image && lit.options.exposureEV == 0)
    }
}

@Suite struct SKEL_ComputeTileFixture {
    @Test func tileBytesAndPlan() {   // SPEC §5.3 A floor 6: (256 + 2·12) × 8 B = 2,240 B
        #expect(GaussianOperator.computeTileBytes(radius: 12) == 2240)
        #expect(GaussianOperator.tileBudgetRadius == 896)
        let request = OperatorRequest(parameters: ParameterValues(["sigma": .double(4), "truncation": .choice("3")]),
                                      variant: GaussianOperator.computeTile, size: .square(894))
        let plan = GaussianOperator().passPlan(request)
        #expect(plan.passes.map(\.kind) == [.compute, .compute])
        #expect(plan.supportRadius == 12 && plan.passes.allSatisfy(\.traceable))
        #expect(GaussianOperator().resolveVariant(request).variant == GaussianOperator.computeTile)
    }
}

@Suite struct SKEL_HexLineSeedReference {
    @Test func offsetsAreTheSPECDirections() {
        let o = F6HexLineSeedReference.offsets()
        #expect(o.count == 32)
        #expect(o[0] == SIMD2<Float>(0, -0.5) && o[15] == SIMD2<Float>(0, -15.5))     // ↑, first tap half a step out
        #expect(abs(Double(o[16].x) - 0.4330127) < 1e-6 && o[16].y == 0.25)          // ↘ = (cos 30°, sin 30°)·½
    }

    @Test func uniformImageStaysUniformOnBothAttachments() {
        let input = ImageBuffer(width: 40, height: 40, fill: SIMD4(0.25, 0.5, 0.75, 1))
        let region = PixelRegion(origin: PixelPoint(x: 4, y: 4), size: .square(8))
        let out = F6HexLineSeedReference.passOne(input, region: region, edge: .clamp, options: .parity)
        #expect(out.t1.pixels.allSatisfy { $0 == SIMD4(0.25, 0.5, 0.75, 1) })
        #expect(out.t2.pixels.allSatisfy { $0 == SIMD4(0.25, 0.5, 0.75, 1) })
    }

    @Test func attachmentsDifferOnAnImpulse() {   // T1 sees only the ↑ line; T2 is half ↑ plus half ↘
        var input = ImageBuffer(width: 48, height: 48)
        input[24, 24] = SIMD4(1, 1, 1, 1)
        let all = PixelRegion(origin: .zero, size: .square(48))
        let out = F6HexLineSeedReference.passOne(input, region: all, edge: .zero, options: .exact)
        #expect(out.t1[24, 30].x > 0 && abs(out.t2[24, 30].x - out.t1[24, 30].x / 2) < 1e-7)
        #expect(out.t1[16, 19].x == 0 && out.t2[16, 19].x > 0)
    }
}

/// PLAN S9: nothing the seeds put on screen shows a fabricated number, and every number carries its badge.
@Suite struct SKEL_HonestSeeds {
    static let stamp = DeviceStamp(deviceModel: "iPhone 15 Pro Max", gpuName: "Apple A17 Pro GPU", gpuFamily: "Apple9", osVersion: "iOS 27.0",
                                   osBuild: "seed", isSimulator: false, date: Date(timeIntervalSince1970: 1_760_400_000), thermal: .nominal,
                                   lowPowerMode: false)

    func context(_ op: any BlurOperator, specimen: SpecimenID, timed: Bool) -> FloorContext {
        let entry = op.entry
        let config = RenderConfiguration(blur: entry.id, variant: entry.defaultVariant, parameters: entry.defaultParameters, settings: .standard,
                                         specimen: specimen, specimenOptions: .standard, pan: .zero, probe: PixelPoint(x: 447, y: 455),
                                         windowSize: 894)
        var live = LiveFacts()
        if timed {
            let timing = TimingSummary(method: .commandBuffer, warmups: 3, samples: 15, medianMilliseconds: 0.61, iqrMilliseconds: 0.02,
                                       perPass: [], fusedMedianMilliseconds: nil, interleaved: false, thermalAtStart: .nominal,
                                       thermalAtEnd: .nominal, lowPowerMode: false)
            let plan = op.passPlan(config.operatorRequest)
            live.timedRun = Run(kind: .timing, generation: 1, slot: .a, configuration: config, resolvedVariant: op.resolveVariant(config.operatorRequest),
                                quality: .full, device: Self.stamp, gpu: nil,
                                kernel: KernelSummary(sigmaEff: op.sigma(config.operatorRequest), excessKurtosis: nil,
                                                      fetchesPerPixel: plan.fetchesPerPixel, tapsPerAxis: nil, passNames: plan.passes.map(\.name)),
                                dispatch: [], timing: timing, cost: nil, parity: nil,
                                probe: ProbeReadout(probe: config.probe, input: .zero, output: SIMD4(0.0885, 0.0885, 0.0885, 1)),
                                shape: nil, shader: nil, trace: nil, calibration: nil, deviceProbe: nil)
            live.run = live.timedRun
        }
        return FloorContext(configuration: config, homeToolID: "swiftui", displayScale: 3, live: live)
    }

    @Test func seedPagesRailChipsAndPillsAreHonest() {
        let placeholders = ["todo", "lorem", "placeholder", "tbd", "fixme"]
        for op in BlurRegistry.operators {
            for specimen: SpecimenID in ["night-city", "step-edges"] {
                for timed in [false, true] {
                    let ctx = context(op, specimen: specimen, timed: timed)
                    for page in BlurServices.floors.pages(for: op, context: ctx) {
                        #expect(page.numbers.count <= 6, "\(op.entry.id) \(page.eyebrow)")
                        #expect(page.eyebrow == page.floor.eyebrow && page.question == page.floor.question)
                        for row in page.numbers { #expect(row.value.honestyViolations.isEmpty, "\(page.eyebrow) \(row.label): \(row.value.honestyViolations)") }
                        let words = [page.eyebrow, page.question, page.signature, page.inThisApp, page.emptyState ?? ""].joined(separator: " ").lowercased()
                        for p in placeholders { #expect(!words.contains(p), "\(page.eyebrow) contains \(p)") }
                    }
                    let chips = BlurServices.floors.railChips(for: op, context: ctx)
                    #expect(chips.map(\.floor) == Floor.allCases)
                    for chip in chips { #expect(chip.value.honestyViolations.isEmpty, "\(chip.floor.railLabel): \(chip.value.honestyViolations)") }
                    let gpu = chips.first { $0.floor == .gpu }!.value
                    if timed { #expect(gpu.provenance == .measured && gpu.device != nil && gpu.value == 0.61) }
                    else { #expect(gpu.value == nil && gpu.text == "–.––") }                    // not yet measured, never a number
                    let pills = BlurServices.floors.pills(for: op, context: ctx)
                    for badge in [pills.kernel.badge, pills.freq.badge].compactMap({ $0 }) { #expect(badge.honestyViolations.isEmpty) }
                }
            }
        }
    }

    @Test func statusLinesAreHonest() {
        for op in BlurRegistry.operators {
            let entry = op.entry
            let request = OperatorRequest(parameters: entry.defaultParameters, variant: entry.defaultVariant, size: .square(894))
            #expect(op.passPlan(request).phase.honestyViolations.isEmpty, "\(entry.id) phase line")
            #expect(op.holdingSigma(12, current: entry.defaultParameters).statusLine.honestyViolations.isEmpty)
            #expect(op.holdingSigma(80, current: entry.defaultParameters).statusLine.honestyViolations.isEmpty)
            for variant in entry.variants {
                // σ 4 keeps every variant unresolved (2-D direct switches to separable above σ 8).
                let parameters = op.holdingSigma(4, current: entry.defaultParameters).parameters
                let line = op.passPlan(OperatorRequest(parameters: parameters, variant: variant.id, size: .square(894))).phase
                if variant.displayName.contains(where: \.isNumber) {
                    // Known issue for INTEGRATE (Documentation/build/requests/SKEL.md item 2): PassPlan.phase (frozen Kernels.swift)
                    // puts the algorithm name in a .text segment, so a variant name with a digit ("2-D direct") trips the lint.
                    withKnownIssue("PassPlan.phase puts '\(variant.displayName)' in a .text segment") {
                        #expect(line.honestyViolations.isEmpty)
                    }
                } else {
                    #expect(line.honestyViolations.isEmpty, "\(variant.id) phase line")
                }
            }
        }
        // The seed status rows the Bench shows (BenchModel): coaching line and rendering line, words only.
        #expect(BadgedLine.words("TURN A CROWN · DRAG THE IMAGE · TAP A BLUR").honestyViolations.isEmpty)
        #expect(BadgedLine.words("RENDERING…").honestyViolations.isEmpty)
    }
}
