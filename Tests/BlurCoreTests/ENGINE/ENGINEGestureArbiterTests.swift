import Testing
import BlurCore

// OWNER: ENGINE. The arbiter matrix (ARCHITECTURE §5.10, SPEC §4.1.3): every priority conflict of
// handle > pinch > long-press loupe > pan > tap, the 8-pt slop and 0.35-s long-press boundaries, draining after a pinch,
// a loupe lifted outside the window, and cancellation. One window of 298 × 298 pt, like the 15 Pro Max Bench.

private let window = SIMD2<Double>(298, 298)
private let centreHandle = HandleTarget(id: "centre", centre: SIMD2(149, 149))

private struct Finger {
    var arbiter = SpecimenGestureArbiter(bounds: window)
    var handles: [HandleTarget] = []
    mutating func down(_ id: Int, _ x: Double, _ y: Double, at t: Double) -> [GestureIntent] {
        arbiter.handle(TouchEvent(phase: .began, touches: [TouchPoint(id: id, location: SIMD2(x, y))], time: t), handles: handles)
    }
    mutating func downTwo(_ a: SIMD2<Double>, _ b: SIMD2<Double>, at t: Double) -> [GestureIntent] {
        arbiter.handle(TouchEvent(phase: .began, touches: [TouchPoint(id: 1, location: a), TouchPoint(id: 2, location: b)], time: t),
                       handles: handles)
    }
    mutating func move(_ id: Int, _ x: Double, _ y: Double, at t: Double) -> [GestureIntent] {
        arbiter.handle(TouchEvent(phase: .moved, touches: [TouchPoint(id: id, location: SIMD2(x, y))], time: t), handles: handles)
    }
    mutating func up(_ id: Int, _ x: Double, _ y: Double, at t: Double) -> [GestureIntent] {
        arbiter.handle(TouchEvent(phase: .ended, touches: [TouchPoint(id: id, location: SIMD2(x, y))], time: t), handles: handles)
    }
    mutating func cancel(at t: Double) -> [GestureIntent] {
        arbiter.handle(TouchEvent(phase: .cancelled, touches: [], time: t), handles: handles)
    }
    mutating func tick(_ t: Double) -> [GestureIntent] { arbiter.tick(time: t) }
}

@Suite struct ENGINE_GestureArbiterMatrix {
    // MARK: Tap (priority 5) and the slop boundary

    @Test func tapPlacesProbeAtLiftPoint() {
        var f = Finger()
        #expect(f.down(1, 100, 100, at: 0).isEmpty)
        #expect(f.up(1, 103, 100, at: 0.12) == [.placeProbe(SIMD2(103, 100))])
        #expect(f.arbiter.state == .idle)
    }

    @Test func travelOfExactlyEightPointsIsStillATap() {
        var f = Finger()
        _ = f.down(1, 100, 100, at: 0)
        #expect(f.move(1, 108, 100, at: 0.05).isEmpty)                       // 8.0 pt: inside the slop (> 8 pans)
        #expect(f.up(1, 108, 100, at: 0.1) == [.placeProbe(SIMD2(108, 100))])
    }

    @Test func travelJustOverEightPointsPansWithTheWholeDelta() {
        var f = Finger()
        _ = f.down(1, 100, 100, at: 0)
        #expect(f.move(1, 108.125, 100, at: 0.05) == [.panBegan, .panMoved(delta: SIMD2(8.125, 0))])
        #expect(f.up(1, 108.125, 100, at: 0.1) == [.panEnded])
    }

    @Test func diagonalSlopIsEuclidean() {
        var f = Finger()
        _ = f.down(1, 100, 100, at: 0)
        #expect(f.move(1, 105.5, 105.5, at: 0.05).isEmpty)                   // 7.78 pt
        #expect(f.move(1, 105.75, 105.75, at: 0.06) == [.panBegan, .panMoved(delta: SIMD2(5.75, 5.75))])   // 8.13 pt
    }

    // MARK: Pan (priority 4)

    @Test func panDeltasSumToTheTotalTravel() {
        var f = Finger()
        _ = f.down(1, 10, 10, at: 0)
        var total = SIMD2<Double>(0, 0)
        for (i, x) in [30.0, 55, 55, 90].enumerated() {
            for intent in f.move(1, x, 20, at: 0.02 * Double(i + 1)) { if case .panMoved(let d) = intent { total += d } }
        }
        for intent in f.up(1, 100, 25, at: 0.2) { if case .panMoved(let d) = intent { total += d } }
        #expect(total == SIMD2(90, 15))
    }

    @Test func panNeverBecomesALoupe() {
        var f = Finger()
        _ = f.down(1, 10, 10, at: 0)
        _ = f.move(1, 40, 10, at: 0.1)
        #expect(f.tick(0.6).isEmpty)
        #expect(f.move(1, 41, 10, at: 0.7) == [.panMoved(delta: SIMD2(1, 0))])
    }

    // MARK: Long-press loupe (priority 3) and its boundary

    @Test func longPressBoundaryIsInclusiveAtThreeHundredFiftyMilliseconds() {
        var f = Finger()
        _ = f.down(1, 50, 60, at: 1.0)
        #expect(f.tick(1.349).isEmpty)
        #expect(f.tick(1.35) == [.loupeBegan(SIMD2(50, 60))])
        #expect(f.tick(1.5).isEmpty)                                         // fires once
    }

    @Test func liftBeforeTheLongPressIsATap() {
        var f = Finger()
        _ = f.down(1, 50, 60, at: 0)
        #expect(f.up(1, 50, 60, at: 0.34) == [.placeProbe(SIMD2(50, 60))])
    }

    @Test func liftAfterTheLongPressWithoutATickIsALoupeThatPlacesTheProbe() {
        var f = Finger()
        _ = f.down(1, 50, 60, at: 0)
        #expect(f.up(1, 50, 60, at: 0.36) == [.loupeBegan(SIMD2(50, 60)), .loupeEnded(placeProbeAt: SIMD2(50, 60))])
    }

    @Test func movingAfterTheLongPressWithoutATickSlidesTheLoupeNotThePan() {
        var f = Finger()
        _ = f.down(1, 50, 60, at: 0)
        #expect(f.move(1, 90, 60, at: 0.4) == [.loupeBegan(SIMD2(50, 60)), .loupeMoved(SIMD2(90, 60))])
    }

    @Test func loupeSlidesAndLiftsInsideToPlaceTheProbe() {
        var f = Finger()
        _ = f.down(1, 50, 60, at: 0)
        _ = f.tick(0.4)
        #expect(f.move(1, 70, 80, at: 0.5) == [.loupeMoved(SIMD2(70, 80))])
        #expect(f.up(1, 70, 80, at: 0.6) == [.loupeEnded(placeProbeAt: SIMD2(70, 80))])
    }

    @Test func loupeLiftedOutsideTheWindowIsCancelled() {
        var f = Finger()
        _ = f.down(1, 280, 60, at: 0)
        _ = f.tick(0.4)
        #expect(f.move(1, 310, 60, at: 0.5) == [.loupeMoved(SIMD2(310, 60))])
        #expect(f.up(1, 310, 60, at: 0.6) == [.loupeEnded(placeProbeAt: nil)])
    }

    @Test func loupeLiftedAboveTheWindowIsCancelledAndTheRightEdgeIsOutside() {
        var a = Finger()
        _ = a.down(1, 20, 5, at: 0); _ = a.tick(0.4)
        #expect(a.up(1, 20, -1, at: 0.5) == [.loupeMoved(SIMD2(20, -1)), .loupeEnded(placeProbeAt: nil)])
        var b = Finger()
        _ = b.down(1, 290, 20, at: 0); _ = b.tick(0.4)
        #expect(b.up(1, 298, 20, at: 0.5) == [.loupeMoved(SIMD2(298, 20)), .loupeEnded(placeProbeAt: nil)])   // x = width is outside
    }

    // MARK: Handles (priority 1) and the hit radius

    @Test func handleHitRadiusIsTwentyTwoPointsInclusive() {
        var inside = Finger(); inside.handles = [centreHandle]
        #expect(inside.down(1, 171, 149, at: 0) == [.handleBegan("centre")])
        var outside = Finger(); outside.handles = [centreHandle]
        #expect(outside.down(1, 171.01, 149, at: 0).isEmpty)
        #expect(outside.up(1, 171.01, 149, at: 0.1) == [.placeProbe(SIMD2(171.01, 149))])
    }

    @Test func nearestOfTwoOverlappingHandlesWins() {
        var f = Finger()
        f.handles = [HandleTarget(id: "a", centre: SIMD2(100, 100)), HandleTarget(id: "b", centre: SIMD2(120, 100))]
        #expect(f.down(1, 112, 100, at: 0) == [.handleBegan("b")])
    }

    @Test func handleDragNeverPansAndNeverOpensTheLoupe() {
        var f = Finger(); f.handles = [centreHandle]
        _ = f.down(1, 150, 150, at: 0)
        #expect(f.move(1, 200, 150, at: 0.1) == [.handleMoved("centre", SIMD2(200, 150))])
        #expect(f.tick(1.0).isEmpty)
        #expect(f.up(1, 200, 150, at: 1.1) == [.handleEnded("centre")])
    }

    @Test func handleBeatsPinchAndTheOtherFingerDrains() {
        var f = Finger(); f.handles = [centreHandle]
        _ = f.down(1, 150, 150, at: 0)
        #expect(f.down(2, 40, 40, at: 0.1).isEmpty)                          // no zoomBegan: handle > pinch
        #expect(f.move(2, 10, 10, at: 0.15).isEmpty)
        #expect(f.move(1, 160, 150, at: 0.2) == [.handleMoved("centre", SIMD2(160, 150))])
        #expect(f.up(1, 160, 150, at: 0.3) == [.handleEnded("centre")])
        #expect(f.arbiter.state == .draining)
        #expect(f.move(2, 80, 10, at: 0.4).isEmpty)                          // the leftover finger never pans
        #expect(f.up(2, 80, 10, at: 0.5).isEmpty)
        #expect(f.arbiter.state == .idle)
    }

    // MARK: Pinch (priority 2) over loupe, pan and tap

    @Test func pinchBeatsTap() {
        var f = Finger()
        _ = f.down(1, 100, 100, at: 0)
        #expect(f.down(2, 200, 100, at: 0.05) == [.zoomBegan(centre: SIMD2(150, 100))])
        #expect(f.up(1, 100, 100, at: 0.1) == [.zoomEnded])                  // no probe placed
        #expect(f.up(2, 200, 100, at: 0.12).isEmpty)
    }

    @Test func pinchBeatsPan() {
        var f = Finger()
        _ = f.down(1, 100, 100, at: 0)
        _ = f.move(1, 120, 100, at: 0.05)
        #expect(f.down(2, 220, 100, at: 0.1) == [.panEnded, .zoomBegan(centre: SIMD2(170, 100))])
    }

    @Test func pinchBeatsLoupeWhichClosesWithoutMovingTheProbe() {
        var f = Finger()
        _ = f.down(1, 100, 100, at: 0)
        _ = f.tick(0.4)
        #expect(f.down(2, 140, 100, at: 0.5) == [.loupeEnded(placeProbeAt: nil), .zoomBegan(centre: SIMD2(120, 100))])
    }

    @Test func secondFingerAfterAnUnseenLongPressStillPinches() {
        var f = Finger()
        _ = f.down(1, 100, 100, at: 0)
        #expect(f.down(2, 140, 100, at: 0.5)
                == [.loupeBegan(SIMD2(100, 100)), .loupeEnded(placeProbeAt: nil), .zoomBegan(centre: SIMD2(120, 100))])
    }

    @Test func twoFingersLandingTogetherPinchAtTheirMidpoint() {
        var f = Finger()
        #expect(f.downTwo(SIMD2(100, 100), SIMD2(200, 200), at: 0) == [.zoomBegan(centre: SIMD2(150, 150))])
    }

    @Test func pinchScaleIsTheDistanceRatio() {
        var f = Finger()
        _ = f.downTwo(SIMD2(100, 100), SIMD2(200, 100), at: 0)
        #expect(f.move(2, 300, 100, at: 0.1) == [.zoomChanged(scale: 2, centre: SIMD2(200, 100))])
        #expect(f.move(1, 250, 100, at: 0.2) == [.zoomChanged(scale: 0.5, centre: SIMD2(275, 100))])
    }

    @Test func aThirdFingerNeverJoinsThePinch() {
        var f = Finger()
        _ = f.downTwo(SIMD2(100, 100), SIMD2(200, 100), at: 0)
        #expect(f.down(3, 150, 250, at: 0.1).isEmpty)
        #expect(f.move(3, 160, 250, at: 0.2).isEmpty)
    }

    // MARK: Draining after a pinch

    @Test func afterAPinchTheRemainingFingerIsIgnoredUntilAllLift() {
        var f = Finger()
        _ = f.downTwo(SIMD2(100, 100), SIMD2(200, 100), at: 0)
        #expect(f.up(2, 200, 100, at: 0.3) == [.zoomEnded])
        #expect(f.arbiter.state == .draining)
        #expect(f.move(1, 160, 100, at: 0.4).isEmpty)                        // no pan
        #expect(f.tick(2.0).isEmpty)                                         // no loupe
        #expect(f.down(4, 50, 50, at: 2.1).isEmpty)                          // a new finger while draining is ignored too
        #expect(f.up(1, 160, 100, at: 2.2).isEmpty)                          // no probe
        #expect(f.up(4, 50, 50, at: 2.3).isEmpty)
        #expect(f.arbiter.state == .idle)
        _ = f.down(5, 30, 30, at: 3)                                         // back to normal afterwards
        #expect(f.up(5, 30, 30, at: 3.1) == [.placeProbe(SIMD2(30, 30))])
    }

    @Test func bothPinchFingersLiftingTogetherReturnsToIdle() {
        var f = Finger()
        _ = f.downTwo(SIMD2(100, 100), SIMD2(200, 100), at: 0)
        let lifted = f.arbiter.handle(TouchEvent(phase: .ended, touches: [TouchPoint(id: 1, location: SIMD2(100, 100)),
                                                                           TouchPoint(id: 2, location: SIMD2(200, 100))], time: 0.2),
                                      handles: [])
        #expect(lifted == [.zoomEnded])
        #expect(f.arbiter.state == .idle)
    }

    @Test func aPinchThatStartedFromAPanDrainsTheLastFinger() {
        var f = Finger()
        _ = f.down(1, 100, 100, at: 0)
        _ = f.move(1, 130, 100, at: 0.05)
        _ = f.down(2, 230, 100, at: 0.1)
        #expect(f.up(1, 130, 100, at: 0.2) == [.zoomEnded])
        #expect(f.move(2, 260, 100, at: 0.3).isEmpty)
    }

    // MARK: Ticks, foreign lifts, cancellation

    @Test func ticksDoNothingOutsideAPendingTouch() {
        var f = Finger(); f.handles = [centreHandle]
        #expect(f.tick(5).isEmpty)
        _ = f.down(1, 150, 150, at: 6)
        #expect(f.tick(7).isEmpty)
    }

    @Test func cancellingClosesTheActiveGestureFirst() {
        var pan = Finger()
        _ = pan.down(1, 10, 10, at: 0); _ = pan.move(1, 40, 10, at: 0.1)
        #expect(pan.cancel(at: 0.2) == [.panEnded, .cancelled])
        #expect(pan.arbiter.state == .idle)
        var loupe = Finger()
        _ = loupe.down(1, 10, 10, at: 0); _ = loupe.tick(0.4)
        #expect(loupe.cancel(at: 0.5) == [.loupeEnded(placeProbeAt: nil), .cancelled])
        var handle = Finger(); handle.handles = [centreHandle]
        _ = handle.down(1, 150, 150, at: 0)
        #expect(handle.cancel(at: 0.1) == [.handleEnded("centre"), .cancelled])
        var pinch = Finger()
        _ = pinch.downTwo(SIMD2(1, 1), SIMD2(50, 50), at: 0)
        #expect(pinch.cancel(at: 0.1) == [.zoomEnded, .cancelled])
        var pending = Finger()
        _ = pending.down(1, 10, 10, at: 0)
        #expect(pending.cancel(at: 0.1) == [.cancelled])
        var idle = Finger()
        #expect(idle.cancel(at: 0).isEmpty)
    }

    @Test func boundsFollowTheWindowSize() {
        var f = Finger()
        f.arbiter.bounds = SIMD2(270, 270)                                   // a 402-pt-wide phone
        _ = f.down(1, 260, 20, at: 0); _ = f.tick(0.4)
        #expect(f.up(1, 275, 20, at: 0.5) == [.loupeMoved(SIMD2(275, 20)), .loupeEnded(placeProbeAt: nil)])
    }
}
