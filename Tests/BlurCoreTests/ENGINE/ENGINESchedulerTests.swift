import Testing
import BlurCore

// OWNER: ENGINE. RenderScheduler (SPEC §4.1.6; ARCHITECTURE §5.10): every accepted change renders at once (preview while
// interacting), a full render 300 ms after the last change when the last one was a preview, then timing ONCE per
// generation; cancelMeasurements on every later change and on touchBegan; acknowledge is monotonic; isRendering drives the
// status row. CalibrationIdleScheduler (SPEC §2, §13.2): ≥ 10 s since launch AND ≥ 3 s since the last touch, no active
// control, thermal nominal or fair.

@Suite struct ENGINE_RenderScheduler {
    @Test func everyChangeRendersAtOnceAndFullWhenNotInteracting() {
        var s = RenderScheduler()
        #expect(s.requestChanged(at: 0, preview: .half, interacting: false) == [.render(quality: .full, generation: 1)])
        #expect(s.requestChanged(at: 0.01, preview: nil, interacting: false) == [.render(quality: .full, generation: 2)])
    }

    @Test func previewWhileInteractingThenOneFullRenderThenTimingOncePerGeneration() {
        var s = RenderScheduler()
        #expect(s.requestChanged(at: 0, preview: .half, interacting: true) == [.render(quality: .half, generation: 1)])
        #expect(s.requestChanged(at: 0.05, preview: .quarter, interacting: true) == [.render(quality: .quarter, generation: 2)])
        #expect(s.tick(at: 2).isEmpty)                                       // still interacting: never settles
        s.interactionEnded(at: 2)
        #expect(s.tick(at: 2.299).isEmpty)
        #expect(s.tick(at: 2.3) == [.render(quality: .full, generation: 2), .startTiming(generation: 2)])
        #expect(s.tick(at: 2.4).isEmpty)                                     // once per generation
        #expect(s.tick(at: 9).isEmpty)
    }

    @Test func aFullRenderIsNotRepeatedAtSettle() {
        var s = RenderScheduler()
        _ = s.requestChanged(at: 0, preview: nil, interacting: false)
        #expect(s.tick(at: 0.3) == [.startTiming(generation: 1)])
    }

    @Test func aChangeDuringMeasurementCancelsIt() {
        var s = RenderScheduler()
        _ = s.requestChanged(at: 0, preview: nil, interacting: false)
        _ = s.tick(at: 0.3)
        #expect(s.requestChanged(at: 0.5, preview: nil, interacting: false) == [.cancelMeasurements, .render(quality: .full, generation: 2)])
        #expect(s.requestChanged(at: 0.6, preview: nil, interacting: false) == [.render(quality: .full, generation: 3)])   // nothing left to cancel
        #expect(s.tick(at: 0.9) == [.startTiming(generation: 3)])
    }

    @Test func aTouchCancelsMeasurementAndReArmsIt() {
        var s = RenderScheduler()
        _ = s.requestChanged(at: 0, preview: nil, interacting: false)
        _ = s.tick(at: 0.3)
        #expect(s.touchBegan() == [.cancelMeasurements])
        #expect(s.touchBegan().isEmpty)                                      // only once
        s.interactionEnded(at: 1.0)                                          // released without changing anything
        #expect(s.tick(at: 1.2).isEmpty)
        #expect(s.tick(at: 1.3) == [.startTiming(generation: 1)])            // the cancelled timing runs again, same generation
    }

    @Test func aTouchAfterAFinishedMeasurementDoesNotRepeatIt() {
        var s = RenderScheduler()
        _ = s.requestChanged(at: 0, preview: nil, interacting: false)
        _ = s.tick(at: 0.3)
        s.measurementsFinished(generation: 1)
        #expect(s.touchBegan().isEmpty)
        s.interactionEnded(at: 1)
        #expect(s.tick(at: 2).isEmpty)
    }

    @Test func aStaleFinishDoesNotClearTheCurrentMeasurement() {
        var s = RenderScheduler()
        _ = s.requestChanged(at: 0, preview: nil, interacting: false)
        _ = s.tick(at: 0.3)
        _ = s.requestChanged(at: 0.4, preview: nil, interacting: false)
        _ = s.tick(at: 0.7)                                                  // measuring generation 2
        s.measurementsFinished(generation: 1)                                // late report from the cancelled generation
        #expect(s.touchBegan() == [.cancelMeasurements])
    }

    @Test func acknowledgeIsMonotonic() {
        var s = RenderScheduler()
        for t in 1...3 { _ = s.requestChanged(at: Double(t), preview: nil, interacting: false) }
        #expect(s.acknowledge(2) == true)
        #expect(s.acknowledge(1) == false)                                           // a stale render never overwrites a newer one
        #expect(s.acknowledge(2) == true)                                            // the full render of the same generation may follow its preview
        #expect(s.acknowledge(3) == true)
        #expect(s.acknowledge(2) == false)
        #expect(s.lastAcknowledged == 3)
    }

    @Test func isRenderingUntilTheCurrentGenerationIsAcknowledged() {
        var s = RenderScheduler()
        #expect(!s.isRendering)
        _ = s.requestChanged(at: 0, preview: nil, interacting: false)
        _ = s.requestChanged(at: 0.01, preview: nil, interacting: false)
        #expect(s.isRendering)
        #expect(s.isStale(1) && !s.isStale(2))
        _ = s.acknowledge(1)
        #expect(s.isRendering)                                               // an older frame arrived: still rendering
        _ = s.acknowledge(2)
        #expect(!s.isRendering)
    }

    @Test func settleTimeIsConfigurableAndCountsFromTheLastChange() {
        var s = RenderScheduler(settleSeconds: 0.5)
        _ = s.requestChanged(at: 0, preview: nil, interacting: false)
        _ = s.requestChanged(at: 0.4, preview: nil, interacting: false)
        #expect(s.tick(at: 0.8).isEmpty)
        #expect(s.tick(at: 0.9) == [.startTiming(generation: 2)])
    }
}

@Suite struct ENGINE_CalibrationIdleGate {
    @Test func needsTenSecondsSinceLaunch() {
        let gate = CalibrationIdleScheduler(launchTime: 100)
        #expect(!gate.mayRun(at: 109.99, thermal: .nominal))
        #expect(gate.mayRun(at: 110, thermal: .nominal))
    }

    @Test func needsThreeSecondsSinceTheLastTouch() {
        var gate = CalibrationIdleScheduler(launchTime: 0)
        gate.noteTouch(at: 20)
        #expect(!gate.mayRun(at: 22.99, thermal: .nominal))
        #expect(gate.mayRun(at: 23, thermal: .nominal))
    }

    @Test func bothConditionsAtOnce() {
        var gate = CalibrationIdleScheduler(launchTime: 0)
        gate.noteTouch(at: 9)
        #expect(!gate.mayRun(at: 10.5, thermal: .nominal))                   // 10 s since launch but only 1.5 s idle
        #expect(gate.mayRun(at: 12, thermal: .nominal))
    }

    @Test func noActiveControl() {
        var gate = CalibrationIdleScheduler(launchTime: 0)
        gate.setControlActive(true)
        #expect(!gate.mayRun(at: 60, thermal: .nominal))
        gate.setControlActive(false)
        #expect(gate.mayRun(at: 60, thermal: .nominal))
    }

    @Test func thermalNominalOrFairOnly() {
        let gate = CalibrationIdleScheduler(launchTime: 0)
        #expect(gate.mayRun(at: 60, thermal: .nominal) && gate.mayRun(at: 60, thermal: .fair))
        for level in [ThermalLevel.serious, .critical, .unknown] { #expect(!gate.mayRun(at: 60, thermal: level)) }
    }

    @Test func touchTimesOnlyMoveForward() {
        var gate = CalibrationIdleScheduler(launchTime: 0)
        gate.noteTouch(at: 30)
        gate.noteTouch(at: 25)                                               // a late, older timestamp
        #expect(gate.lastTouch == 30)
        #expect(!gate.mayRun(at: 32, thermal: .nominal))
    }
}
