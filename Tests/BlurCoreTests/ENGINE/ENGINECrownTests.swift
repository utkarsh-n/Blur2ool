import Testing
import BlurCore

// OWNER: ENGINE. Metro Station's crown tests (Tests/MetronomeCoreTests/CrownDetentTrackerTests.swift, build 14) ported
// verbatim against the verbatim tracker, plus the three Metro contract rules stated on their own (≤ 1 step per update,
// 18 % reversal hysteresis, the first touch never changes the value) and the ≤ 20 detents/s rate limiter (Metro §10).

@Suite("ENGINE_CrownDetentTracker — Metro Station's relative crown gestures")
struct ENGINE_CrownDetentTracker {
    @Test func touchDownHasNoJumpAndFractionalTravelIsHeld() {
        var crown = CrownDetentTracker(detentDegrees: 8)
        crown.begin(angleDegrees: 120)
        #expect(crown.update(angleDegrees: 120) == 0)
        for jitter in [120.3, 119.8, 120.1, 119.9, 120.0] {
            #expect(crown.update(angleDegrees: jitter) == 0)
        }
        #expect(crown.update(angleDegrees: 125) == 0)
        #expect(crown.residualDegrees == 5)
        #expect(crown.update(angleDegrees: 129) == 1)
        #expect(crown.residualDegrees == 1)
        #expect(crown.update(angleDegrees: 135) == 0)
        #expect(crown.update(angleDegrees: 136) == 1)
        #expect(crown.residualDegrees == 0)
    }

    @Test func reversingDirectionRequiresExtraTravelWithoutBoundaryChatter() {
        var crown = CrownDetentTracker(detentDegrees: 20)
        crown.begin(angleDegrees: 0)
        #expect(crown.update(angleDegrees: 20) == 1)
        for jitter in [19.5, 20.5, 19.8, 20.0] {
            #expect(crown.update(angleDegrees: jitter) == 0)
        }
        #expect(crown.update(angleDegrees: 0) == 0) // Twenty degrees back is inside reversal hysteresis.
        #expect(crown.update(angleDegrees: -3.7) == -1)
        #expect(crown.lastDirection == -1)
        #expect(abs(crown.residualDegrees) < 0.2)
        #expect(crown.update(angleDegrees: -23.7) == -1)
    }

    @Test func seamCrossingsKeepDirectionAndFineGaugeThreshold() {
        var clockwise = CrownDetentTracker(detentDegrees: 8)
        clockwise.begin(angleDegrees: 179)
        #expect(clockwise.update(angleDegrees: -177) == 0)
        #expect(clockwise.update(angleDegrees: -173) == 1)
        var counterclockwise = CrownDetentTracker(detentDegrees: 8)
        counterclockwise.begin(angleDegrees: -179)
        #expect(counterclockwise.update(angleDegrees: 177) == 0)
        #expect(counterclockwise.update(angleDegrees: 173) == -1)
        let spacing = 300.0 / 210
        var rim = CrownDetentTracker(detentDegrees: spacing)
        rim.begin(angleDegrees: 0)
        #expect(rim.update(angleDegrees: spacing * 0.55) == 0)
        #expect(rim.update(angleDegrees: spacing) == 1)
    }

    @Test func largeJumpsCannotQueueFloodsAndResetDiscardsOldGesture() {
        var crown = CrownDetentTracker(detentDegrees: 8)
        crown.begin(angleDegrees: 0)
        #expect(crown.update(angleDegrees: 145) == 1)
        #expect(abs(crown.residualDegrees) < crown.detentDegrees)
        for _ in 0..<20 { #expect(crown.update(angleDegrees: 145) == 0) }
        #expect(crown.update(angleDegrees: .nan) == 0)
        #expect(crown.update(angleDegrees: .infinity) == 0)
        #expect(crown.update(angleDegrees: 152) == 1) // One held fractional degree plus seven fresh degrees.
        crown.reset()
        #expect(crown.residualDegrees == 0 && crown.lastDirection == 0)
        #expect(crown.update(angleDegrees: -120) == 0)
        #expect(crown.update(angleDegrees: -128) == -1)
        let invalid = CrownDetentTracker(detentDegrees: .nan, hysteresisDegrees: .infinity)
        #expect(invalid.detentDegrees == 8 && invalid.hysteresisDegrees == 1.44)
    }

    // MARK: The three contract rules, stated on their own (Metro contract A / SPEC §4.1.5)

    @Test func atMostOneStepPerUpdateWhateverTheTravel() {
        for detent in [8.0, 20.0] {
            var crown = CrownDetentTracker(detentDegrees: detent)
            crown.begin(angleDegrees: 0)
            var angle = 0.0
            for step in [3.0, 90, 170, 7, 179, 45] {
                angle += step
                #expect(abs(crown.update(angleDegrees: angle)) <= 1)
            }
        }
    }

    @Test func reversalHysteresisIsEighteenPercentOfADetent() {
        let fine = CrownDetentTracker(detentDegrees: 8), semantic = CrownDetentTracker(detentDegrees: 20)
        #expect(abs(fine.hysteresisDegrees - 1.44) < 1e-12)
        #expect(abs(semantic.hysteresisDegrees - 3.6) < 1e-12)
        var crown = CrownDetentTracker(detentDegrees: 8)
        crown.begin(angleDegrees: 0)
        #expect(crown.update(angleDegrees: 8) == 1)
        // Reversing needs 8 + 1.44 = 9.44° of travel: 9.43° is not enough, 9.45° is.
        #expect(crown.update(angleDegrees: 8 - 9.43) == 0)
        #expect(crown.update(angleDegrees: 8 - 9.45) == -1)
        // Continuing in the same direction needs only the plain 8° detent again.
        #expect(crown.update(angleDegrees: 8 - 9.45 - 7.9) == 0)
        #expect(crown.update(angleDegrees: 8 - 9.45 - 8.1) == -1)
    }

    @Test func theFirstTouchNeverChangesTheValue() {
        for start in [-179.0, -45, 0, 33.3, 120, 179.9] {
            var crown = CrownDetentTracker(detentDegrees: 8)
            crown.begin(angleDegrees: start)
            #expect(crown.update(angleDegrees: start) == 0)
            #expect(crown.residualDegrees == 0)
        }
        // A tracker that never saw `begin` treats its first update as the touch-down too.
        var fresh = CrownDetentTracker(detentDegrees: 8)
        #expect(fresh.update(angleDegrees: 90) == 0)
        #expect(fresh.update(angleDegrees: 98) == 1)
    }
}

@Suite struct ENGINE_DetentRateLimiter {
    @Test func atMostTwentyAcceptedDetentsPerSecond() {
        var limiter = DetentRateLimiter()
        // A 120 Hz flood for one second (121 attempts at t = 0 … 1.0).
        let accepted = (0...120).filter { limiter.admit(at: Double($0) / 120) }.count
        #expect(accepted <= 21)                               // t = 0, 0.05 … 1.0 inclusive: 21 instants in a closed second
        var window = DetentRateLimiter()
        let inOneSecond = (0..<120).filter { window.admit(at: Double($0) / 120) }.count
        #expect(inOneSecond <= 20)                            // half-open second [0, 1): never more than 20
        #expect(inOneSecond == 20)                            // and the limiter does not drop below its rate
    }

    @Test func theFiftyMillisecondBoundary() {
        var limiter = DetentRateLimiter(maxEventsPerSecond: 20)
        #expect(abs(limiter.minimumInterval - 0.05) < 1e-12)
        #expect(limiter.admit(at: 10) == true)
        #expect(limiter.admit(at: 10.0499) == false)
        #expect(limiter.admit(at: 10.05) == true)
        #expect(limiter.admit(at: 10.06) == false)                    // measured from the last ACCEPTED detent
        #expect(limiter.admit(at: 10.1) == true)
    }

    @Test func rejectedDetentsDoNotDelayTheNextOne() {
        var limiter = DetentRateLimiter()
        #expect(limiter.admit(at: 0) == true)
        for t in stride(from: 0.001, to: 0.05, by: 0.001) { #expect(limiter.admit(at: t) == false) }
        #expect(limiter.admit(at: 0.05) == true)
    }

    @Test func resetForgetsTheLastDetentAndSillyRatesAreClamped() {
        var limiter = DetentRateLimiter()
        #expect(limiter.admit(at: 5) == true)
        limiter.reset()
        #expect(limiter.admit(at: 5.001) == true)
        let slow = DetentRateLimiter(maxEventsPerSecond: 0)   // clamped to 1 per second, never divide by zero
        #expect(slow.minimumInterval == 1)
    }
}
