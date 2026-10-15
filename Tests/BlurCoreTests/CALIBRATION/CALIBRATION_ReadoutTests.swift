import Foundation
import Testing
@testable import BlurCore

// OWNER: CALIBRATION. HONEST (ARCHITECTURE §8.1): every BadgedValue and BadgedLine the Calibrate sheet shows passes
// honestyViolations; SwiftUI-derived values carry OFFSCREEN on value, caption and spoken phrase (SPEC §12.2 item 9); the
// drawHierarchy path stays EXPERIMENTAL; Mac values are MEASURED · NOT THIS DEVICE with the Mac's stamp; nothing is
// shown before a measurement except NOT YET MEASURED and an INFERRED prediction. Also the canvas and plan geometry.

enum CALIBRATION_ReadoutFixture {
    static func allViolations(_ rows: [CalibrationReadoutRow]) -> [String] {
        rows.flatMap { row in row.badgedValues.flatMap(\.honestyViolations).map { "\(row.id): \($0)" }
            + (row.note?.honestyViolations ?? []).map { "\(row.id) note: \($0)" } }
    }
    static func result(_ subject: CalibrationSubject, path: CalibrationPath? = nil, parameter: Double = 2) -> CalibrationResult {
        let base = CALIBRATION_SweepFixture.result(radius: parameter)
        var request = base.request
        request.subject = subject
        request.path = path ?? subject.defaultPath
        request.displayScale = subject.parameterIsPoints ? 3 : 1
        var fit = base.fit
        fit.excessKurtosis45 = fit.excessKurtosis / 2
        fit.encodedMidpoint = 0.5
        return CalibrationResult(request: request, fit: fit, device: CALIBRATION_Synthetic.phone, durationMilliseconds: 41)
    }
}

@Suite struct CALIBRATION_Honesty {
    typealias F = CALIBRATION_ReadoutFixture

    @Test(arguments: CalibrationSubject.allCases)
    func everyRowOfEverySubjectIsHonest(subject: CalibrationSubject) {
        let result = F.result(subject)
        let border = CalibrationBorderFinding(borderAlpha: 0.53, outsideAlpha: 0.2, opaqueRequested: false)
        let rows = CalibrationReadout.rows(result, border: subject == .swiftUIBlur ? border : nil)
        #expect(F.allViolations(rows).isEmpty, "\(F.allViolations(rows))")
        #expect(F.allViolations(CalibrationReadout.pendingRows(result.request)).isEmpty)
        #expect(CalibrationReadout.header(result).honestyViolations.isEmpty)
        let sweep = CalibrationSweepModel.make(subject: subject, path: result.request.path, displayScale: 3, results: [result])
        #expect(sweep.allBadgedValues.flatMap(\.honestyViolations).isEmpty)
    }

    @Test func swiftUIValuesCarryOffscreenEverywhere() {
        let rows = CalibrationReadout.rows(F.result(.swiftUIBlur))
        let measured = rows.flatMap(\.badgedValues).filter { $0.provenance == .measured && $0.device == CALIBRATION_Synthetic.phone }
        #expect(!measured.isEmpty)
        for v in measured where v.caption != "WALL CLOCK, NOT GPU TIME" {
            #expect(v.qualifiers.contains(.offscreen), "\(v.text)")
            #expect(v.caption == "OFFSCREEN" && v.spoken.contains("offscreen"), "\(v.spoken)")
        }
        let sigma = rows.first { $0.id == "sigma" }!.values[0].value
        #expect(sigma.unit == "px" && sigma.device?.label == "iPhone 15 Pro Max · iOS 27.0 · 14 Oct")
    }

    @Test func headerTimeAndDayAreBothUTC() {
        let header = CalibrationReadout.header(F.result(.swiftUIBlur))
        #expect(header.text == "RESULT · 12:00 UTC · iPhone 15 Pro Max · iOS 27.0 · 14 Oct", "\(header.text)")
        #expect(header.honestyViolations.isEmpty)
    }

    @Test func coreImageValuesAreNotOffscreen() {
        let rows = CalibrationReadout.rows(F.result(.ciGaussianBlur))
        #expect(rows.flatMap(\.badgedValues).allSatisfy { !$0.qualifiers.contains(.offscreen) })
    }

    @Test func drawHierarchyStaysExperimentalUntilItsCaptureTestPasses() {
        let result = F.result(.swiftUIBlur, path: .drawHierarchyOnScreen)
        let before = CalibrationReadout.rows(result).first { $0.id == "sigma" }!.values[0].value
        #expect(before.qualifiers.contains(.experimental) && before.caption == "ON-SCREEN · EXPERIMENTAL")
        let after = CalibrationReadout.rows(result, onScreenVerified: true).first { $0.id == "sigma" }!.values[0].value
        #expect(!after.qualifiers.contains(.experimental) && after.caption == "ON-SCREEN CAPTURE")
    }

    @Test func macReferenceIsMeasuredNotThisDevice() throws {
        let rows = CalibrationReadout.rows(F.result(.swiftUIBlur, parameter: 2))
        let mac = try #require(rows.first { $0.id == "mac" }?.values.first?.value)
        #expect(mac.provenance == .measured && mac.qualifiers.contains(.notThisDevice) && mac.device == CalibrationMacReference.device)
        #expect(mac.text == "0.906", "2 pt × 3 = 6 px: the Mac's σ/r at 6 px (CAL §4.18)")
        #expect(mac.device?.label == "Mac (Apple M1 Max) · macOS 27.2 · 13 Oct")
        let delta = try #require(rows.first { $0.id == "delta" }?.values.first?.value)
        #expect(delta.provenance == .computed && delta.unit == "%")
    }

    @Test func modelCompetitionMarksExactlyOneWinner() throws {
        let row = try #require(CalibrationReadout.rows(F.result(.swiftUIBlur, parameter: 4)).first { $0.id == "models" })
        #expect(row.values.count == 3 && row.values.filter(\.isWinner).count == 1)
        #expect(row.values.map(\.sublabel) == ["GAUSSIAN", "BOX³", "TRUNC-G"])
        let shape = try #require(CalibrationReadout.rows(F.result(.swiftUIBlur, parameter: 4)).first { $0.id == "shape" }?.values.first?.value)
        #expect(shape.provenance == .inferred && shape.value == nil)
    }

    @Test func pendingRowsPredictWithoutClaimingAMeasurement() throws {
        let request = CalibrationRequest(subject: .swiftUIBlur, path: .imageRendererCGImage, parameter: 4, displayScale: 3)
        let rows = CalibrationReadout.pendingRows(request)
        let slot = try #require(rows.first { $0.id == "sigma" }?.values.first?.value)
        #expect(slot.value == nil && slot.text == "–.––" && slot.spoken == "not yet measured")
        let prediction = try #require(rows.first { $0.id == "prediction" }?.values.first?.value)
        #expect(prediction.provenance == .inferred && prediction.text == "10.80", "≈ 0.90 · 4 pt · 3 (SPEC §13.4: ≈ 10.8 px INFERRED)")
        let mps = CalibrationReadout.pendingRows(CalibrationRequest(subject: .mpsBox, path: .metalPerformanceShaders, parameter: 4, displayScale: 1))
        #expect(mps.first { $0.id == "prediction" }?.values.first?.value.provenance == .computed)
        #expect(mps.first { $0.id == "prediction" }?.values.first?.value.text == "2.58")
    }

    @Test func sweepModelSwitchIsInferredThenMeasured() throws {
        let empty = CalibrationSweepModel.make(subject: .swiftUIBlur, path: .imageRendererCGImage, displayScale: 3, results: [])
        let hollow = try #require(empty.switchParameter)
        #expect(!empty.switchIsMeasured && hollow.provenance == .inferred && hollow.text == "1.75", "5.25 px ÷ 3")
        #expect(empty.pending.count == 34 && empty.mac.count == 33, "34 radii; the Mac's r 0.25 had no blur")
        let sweep = CalibrationPlan.basicSetRadii.map { CALIBRATION_SweepFixture.result(radius: $0) }
        let model = CalibrationSweepModel.make(subject: .swiftUIBlur, path: .imageRendererCGImage, displayScale: 3, results: sweep)
        let filled = try #require(model.switchParameter)
        #expect(model.switchIsMeasured && filled.provenance == .measured && filled.text == "1.50")
        #expect(model.phone.count == 6 && model.pending.count == 28, "the six basic-set radii are all sweep radii")
    }
}

@Suite struct CALIBRATION_Geometry {
    @Test func canvasMatchesMeasurePSF() {
        let c = CalibrationCanvas(parameter: 8, scale: 3)
        #expect(c.reach == 56 && c.margin == 40 && c.width == 196 && c.height == 96)
        #expect(c.edgeX(phase: 0) == 98 && abs(c.edgeX(phase: 2) - (98 + 2.0 / 3)) < 1e-12)
        let small = CalibrationCanvas(parameter: 0.25, scale: 1)
        #expect(small.reach == 10 && small.margin == 9 && small.height == 34)
        #expect(CalibrationCanvas(parameter: 0, scale: 3).height == 32)
    }

    @Test func plansMatchTheSpec() {
        #expect(CalibrationPlan.basicSetRadii == [0.5, 1, 2, 3, 4, 8] && CalibrationPlan.phases == 4)
        #expect(CalibrationPlan.swiftUISweepRadii.count == 34, "SPEC §4.8: 34 radii × 4 phases")
        let basic = CalibrationPlan.basicSet(displayScale: 3)
        #expect(basic.allSatisfy { $0.subject == .swiftUIBlur && $0.colourMode == .nonLinear && $0.phases == 4 && $0.displayScale == 3 })
        #expect(CalibrationPlan.renders(basic[0]) == 5, "4 phases + the 45° twin")
        #expect(CalibrationSubject.allCases.allSatisfy { $0.paths.contains($0.defaultPath) && $0.parameterRange.contains($0.defaultParameter) })
    }

    @Test func estimateIsModeledFromMeasuredRenderTimes() throws {
        let results = CalibrationPlan.basicSetRadii.map { CALIBRATION_SweepFixture.result(radius: $0) }
        let rate = try #require(CalibrationEstimate.millisecondsPerPixel(results))
        #expect(rate > 0)
        let v = CalibrationEstimate.badged(CalibrationEstimate.seconds(CalibrationPlan.basicSet(displayScale: 3), msPerPixel: rate))
        #expect(v.provenance == .modeled && v.honestyViolations.isEmpty)
    }
}
