import Foundation
import Testing
@testable import CodexMeterCore

@Suite("UsagePace")
struct UsagePaceTests {
    @Test("normal when usage behind time")
    func normalWhenUsageBehindTime() {
        #expect(UsagePace.evaluate(usedPercent: 30, elapsedPercent: 50) == .normal)
    }

    @Test("normal when usage slightly ahead")
    func normalWhenUsageSlightlyAhead() {
        #expect(UsagePace.evaluate(usedPercent: 58, elapsedPercent: 50) == .normal)
    }

    @Test("slightly fast")
    func slightlyFast() {
        #expect(UsagePace.evaluate(usedPercent: 65, elapsedPercent: 50) == .slightlyFast)
    }

    @Test("too fast when usage far ahead of time")
    func tooFastWhenUsageFarAheadOfTime() {
        #expect(UsagePace.evaluate(usedPercent: 65, elapsedPercent: 30) == .tooFast)
    }

    @Test("elapsed percent from reset window")
    func elapsedPercentFromResetWindow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let windowMinutes = 10_080
        let resetAt = now.addingTimeInterval(TimeInterval((windowMinutes / 2) * 60))
        let elapsed = UsagePace.elapsedPercent(resetAt: resetAt, windowMinutes: windowMinutes, now: now)
        #expect(abs((elapsed ?? -1) - 50) < 0.2)
    }

    @Test("elapsed percent unknown without reset")
    func elapsedPercentUnknownWithoutReset() {
        #expect(UsagePace.elapsedPercent(resetAt: nil, windowMinutes: 10080) == nil)
    }
}
