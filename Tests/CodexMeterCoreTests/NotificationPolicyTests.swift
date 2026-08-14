import Foundation
import Testing
@testable import CodexMeterCore

@Suite("NotificationPolicy")
struct NotificationPolicyTests {
    @Test("each threshold fires once per window")
    func eachThresholdFiresOncePerWindow() {
        var state = NotificationState()
        let first = snapshot(remaining: 29, reset: 100)
        let decision1 = NotificationPolicy.evaluate(
            snapshot: first,
            previous: state,
            notificationsEnabled: true,
            notifyOnRefresh: true,
            thresholds: [30, 15, 5],
            cycleDidReset: false
        )
        #expect(decision1.notifications == [.remaining(threshold: 30)])
        state = decision1.nextState

        let second = snapshot(remaining: 28, reset: 100)
        let decision2 = NotificationPolicy.evaluate(
            snapshot: second,
            previous: state,
            notificationsEnabled: true,
            notifyOnRefresh: true,
            thresholds: [30, 15, 5],
            cycleDidReset: false
        )
        #expect(decision2.notifications.isEmpty)
    }

    @Test("lower thresholds can still fire")
    func lowerThresholdsCanStillFire() {
        let state = NotificationState(windowKey: "reset-100", firedThresholds: [30])
        let snap = snapshot(remaining: 4, reset: 100)
        let decision = NotificationPolicy.evaluate(
            snapshot: snap,
            previous: state,
            notificationsEnabled: true,
            notifyOnRefresh: false,
            thresholds: [30, 15, 5],
            cycleDidReset: false
        )
        #expect(decision.notifications == [
            .remaining(threshold: 15),
            .remaining(threshold: 5)
        ])
        #expect(Set(decision.nextState.firedThresholds) == [30, 15, 5])
    }

    @Test("reset allows thresholds again")
    func resetAllowsThresholdsAgain() {
        let previous = NotificationState(windowKey: "reset-100", firedThresholds: [30, 15, 5], firedRefresh: true)
        let snap = snapshot(remaining: 96, reset: 200)
        let decision = NotificationPolicy.evaluate(
            snapshot: snap,
            previous: previous,
            notificationsEnabled: true,
            notifyOnRefresh: true,
            thresholds: [30, 15, 5],
            cycleDidReset: true
        )
        #expect(decision.notifications == [.weeklyRefreshed])
        #expect(decision.nextState.windowKey == snap.windowKey)
        #expect(decision.nextState.firedThresholds.isEmpty)
    }

    @Test("disabled notifications suppress thresholds")
    func disabledNotificationsSuppressThresholds() {
        let snap = snapshot(remaining: 4, reset: 100)
        let decision = NotificationPolicy.evaluate(
            snapshot: snap,
            previous: NotificationState(),
            notificationsEnabled: false,
            notifyOnRefresh: true,
            thresholds: [30, 15, 5],
            cycleDidReset: false
        )
        #expect(decision.notifications.isEmpty)
    }

    private func snapshot(remaining: Double, reset: TimeInterval) -> CodexQuotaSnapshot {
        CodexQuotaSnapshot(
            planType: "plus",
            usedPercent: 100 - remaining,
            remainingPercent: remaining,
            resetAt: Date(timeIntervalSince1970: reset),
            windowMinutes: 10_080,
            fetchedAt: Date(timeIntervalSince1970: reset - 1000)
        )
    }
}

@Suite("CycleDetector")
struct CycleDetectorTests {
    @Test("single glitch does not reset")
    func singleGlitchDoesNotReset() {
        var detector = CycleDetector()
        let first = make(used: 80, reset: 100)
        #expect(detector.observe(first) == false)
        let glitch = make(used: 3, reset: 999)
        #expect(detector.observe(glitch) == false)
    }

    @Test("two confirmations reset")
    func twoConfirmationsReset() {
        var detector = CycleDetector()
        #expect(detector.observe(make(used: 80, reset: 100)) == false)
        #expect(detector.observe(make(used: 4, reset: 200)) == false)
        #expect(detector.observe(make(used: 5, reset: 200)) == true)
    }

    @Test("resetAt change still needs two samples")
    func resetAtChangeStillNeedsTwoSamples() {
        var detector = CycleDetector()
        #expect(detector.observe(make(used: 70, reset: 100)) == false)
        #expect(detector.observe(make(used: 2, reset: 200)) == false)
        #expect(detector.observe(make(used: 3, reset: 200)) == true)
    }

    private func make(used: Double, reset: TimeInterval) -> CodexQuotaSnapshot {
        CodexQuotaSnapshot(
            planType: "plus",
            usedPercent: used,
            remainingPercent: 100 - used,
            resetAt: Date(timeIntervalSince1970: reset),
            windowMinutes: 10_080,
            fetchedAt: Date()
        )
    }
}
