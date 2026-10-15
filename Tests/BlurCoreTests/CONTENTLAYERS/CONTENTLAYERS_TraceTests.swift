import Foundation
import Testing
@testable import BlurCore

// OWNER: CONTENT-LAYERS. Acceptance (2): the Gaussian walk (guided descent A) has exactly 15 steps with the SPEC §6.3
// wording and 13 fetch sub-steps in steps 10 and 12; plus the per-class sub-steps of SPEC §6.5 and the trace honesty
// rules of §6.4 (GPU records LIVE, reconstructions COMPUTED, branches not forks, decimals always badged).

@Suite struct CONTENTLAYERS_TraceWalk {
    typealias F = CONTENTLAYERS_Fixtures
    static let scripter = TraceScripter(tools: CONTENTLAYERS_FakeTools())

    static func descentA(source: TraceSource = .cpuReconstruction, timed: Bool = false) -> (steps: [TraceStep], record: TraceRecord) {
        let record = F.descentARecord(source: source)
        let config = F.descentAConfiguration
        let live = timed ? F.richLive(F.gaussian, config) : LiveFacts()
        let steps = scripter.steps(for: record, op: F.gaussian, context: F.context(config, live: live, content: F.stepEdges()))
        return (steps, record)
    }

    @Test func gaussianWalkHasFifteenStepsInSPECWording() {
        let (steps, record) = Self.descentA()
        #expect(steps.count == 15)
        let expected = [
            "You would type 1.33 in SwiftUI",
            "1.33 pt × 3 = 4.0 px",
            "Linear light, clamp, premultiplied",
            "G with σ 4.0 px",
            "25 weights sampled",
            "Renormalised after cutting at ±12",
            "Split into H then V",
            "Merged into 13 bilinear fetches per pass",
            "Draw call issued for pass H",
            "13 fetches done",
            "Pass H written: 0.4500",
            "Pass V: 13 fetches, value unchanged",
            "GPU time not yet measured",
            "OUT 0.450 linear",
            "Encoded 179/255 for the display",
        ]
        #expect(steps.map(\.completed) == expected)
        #expect(steps.map(\.floor) == [.slide, .api, .api, .math, .kernel, .kernel, .algorithm, .algorithm, .gpu, .gpu, .gpu, .gpu, .gpu, .pixels, .pixels])
        #expect(steps.map(\.id) == Array(0..<15))
        // Steps 10 and 12: thirteen fetch sub-steps each; the running sum grows to the pass output.
        #expect(steps[9].subSteps.count == 13 && steps[11].subSteps.count == 13)
        #expect(steps.enumerated().allSatisfy { $0.offset == 9 || $0.offset == 11 || $0.element.subSteps.isEmpty })
        let sums = steps[9].subSteps.compactMap { $0.runningSum.map(ContentValues.scalar) }
        #expect(sums.count == 13 && abs((sums.last ?? 0) - 0.45) < 5e-5)
        #expect(steps[9].subSteps[6].completed == "fetch 7 of 13: w 0.07818 · v 0.000")
        #expect(steps[9].subSteps[6].next == "fetch 8 at +7.38 px")
        #expect(steps[9].subSteps[6].announcement.contains("Partial sum 0.399"))
        #expect(steps[9].subSteps.last?.next == "Pass H writes its value")
        #expect(steps[9].passIndex == 0 && steps[11].passIndex == 1)
        // Labels name the next unit of work; the walk ends with Finish and a closing lesson.
        #expect(steps[0].primaryLabel == "Next floor" && steps[1].primaryLabel == "Next step" && steps[8].primaryLabel == "Next fetch")
        #expect(steps[9].primaryLabel == "Next fetch" && steps[10].primaryLabel == "Next fetch" && steps[14].primaryLabel == "Finish")
        #expect(steps[8].next == "fetch 1 at 0.00 px")
        #expect(steps[9].phaseLine == "Step 10 / 15 · fragment (446, 300) · pass 1 of 2 · horizontal")
        #expect(steps[11].phaseLine == "Step 12 / 15 · fragment (446, 300) · pass 2 of 2 · vertical")
        let lesson = steps[14].closingLesson ?? ""
        #expect(lesson == "Seven floors, one pixel: you typed 1.33, the GPU fetched 26 times, and the pixel went from 0.000 to 0.450. The floor that most changed the answer was the one nobody shows: the colour space at the API floor (179 vs 115).")
        // Branches, not forks: the colour-space alternative beside the real path, COMPUTED.
        let colour = steps[2].branchValues.first { $0.id == "branch-colour" }
        #expect(colour?.label == "IF sRGB-ENCODED" && colour?.value.text == "115" && colour?.value.provenance == .computed)
        #expect(steps[14].branchValues.first?.value.text == "115")
        #expect(steps[2].panel.numbers.contains { $0.id == "real" && $0.value.text == "179" })
        // Honesty: every decimal in the narration has a badged twin; reconstructions are COMPUTED, never LIVE.
        let problems = ContentLint.violations(steps, record: record)
        #expect(problems.isEmpty, "\(problems)")
        #expect(steps[10].panel.numbers.first?.value.provenance == .computed)
        for step in steps { #expect(step.announcement.hasPrefix("Completed: ")) }
    }

    @Test func gpuRecordsAreLiveAndTimingIsMeasured() {
        let (steps, record) = Self.descentA(source: .gpuRecord, timed: true)
        #expect(steps.count == 15)
        #expect(steps[10].panel.numbers.first?.value.provenance == .live)
        #expect(steps[12].completed == "GPU time 0.61 ms" && steps[12].panel.numbers.first?.value.provenance == .measured)
        #expect(steps[9].panel.details.contains { if case .note(_, let p) = $0 { return p == .live }; return false })
        #expect(ContentLint.violations(steps, record: record).isEmpty)
    }

    @Test func partialRecordsSayWhatIsMissing() {
        // The skeleton seed's reconstruction covers pass H only: pass V is announced as not recorded, never invented.
        let config = F.descentAConfiguration
        let record = F.gaussian.traceReconstruction(probe: F.descentAProbe, input: F.stepEdges().image, config.operatorRequest, auxiliary: .none)
        let steps = Self.scripter.steps(for: record, op: F.gaussian, context: F.context(config))
        let v = steps.first { $0.passIndex == 1 }
        if record.passes.count == 1 {
            #expect(v?.completed == "Pass V is not recorded in this trace" && v?.subSteps.isEmpty == true)
        } else {
            #expect(v?.subSteps.count == 13)            // FAM-F2 has completed the reconstruction in this mirror
        }
        #expect(ContentLint.violations(steps, record: record).isEmpty)
    }

    @Test func twoDDirectWalk() {
        let config = F.configuration(F.gaussian, variant: GaussianOperator.direct2D, parameters: F.descentAParameters, specimen: "step-edges", probe: F.descentAProbe)
        var record = F.descentARecord()
        record.variant = GaussianOperator.direct2D
        let steps = Self.scripter.steps(for: record, op: F.gaussian, context: F.context(config))
        #expect(steps.contains { $0.completed == "One 2-D gather" })
        #expect(!steps.contains { $0.completed.hasPrefix("Merged into") })
    }

    @Test func perClassSubSteps() {
        let content = F.smallImage()
        let probe = PixelPoint(x: 70, y: 60)
        for kind in CONTENTLAYERS_Kind.allCases {
            let op = CONTENTLAYERS_FakeOperator(kind: kind)
            let config = F.configuration(op, probe: probe, window: 128)
            let record = op.traceReconstruction(probe: probe, input: content.image, config.operatorRequest, auxiliary: .none)
            let steps = Self.scripter.steps(for: record, op: op, context: F.context(config, content: content))
            #expect(!steps.isEmpty && steps.last?.primaryLabel == "Finish" && steps.last?.closingLesson != nil, "\(kind)")
            let problems = ContentLint.violations(steps, record: record)
            #expect(problems.isEmpty, "\(kind): \(problems)")
            let subs = steps.flatMap(\.subSteps)
            switch kind {
            case .rank:
                #expect(subs.first?.completed.hasPrefix("compare-exchange 1 of 9: v ") == true && subs.first?.completed.contains("rank") == true)
                #expect(steps.contains { $0.subSteps.count == 9 && $0.primaryLabel == "Next tap" })
            case .adaptive:
                #expect(subs.contains { $0.completed.contains("spatial") && $0.completed.contains("range") })
            case .pde:
                #expect(subs.first?.completed.hasPrefix("iteration 1 of") == true)
            case .spaceVariant:
                #expect(steps.contains { $0.completed.hasPrefix("The centre is ") })
            case .system:
                #expect(steps.contains { $0.completed == "We can measure its output, not follow its fetches" } && subs.isEmpty)
            case .atlas:
                #expect(steps.contains { $0.completed == "CPU only in this app: no GPU pass exists" })
            case .recursive:
                #expect(subs.first?.completed.hasSuffix("small contributions summarised") == true)
            case .globalFFT:
                #expect(subs.isEmpty || subs.first?.completed.hasPrefix("frequency") == true)
            default:
                break
            }
        }
    }
}
