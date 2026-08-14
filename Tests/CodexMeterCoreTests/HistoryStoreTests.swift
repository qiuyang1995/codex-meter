import Foundation
import Testing
@testable import CodexMeterCore

@Suite("HistoryStore")
struct HistoryStoreTests {
    @Test("records first point and respects interval")
    func recordsFirstPointAndRespectsInterval() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-meter-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = HistoryStore(fileURL: url, minimumSampleInterval: 15 * 60, retention: 30 * 24 * 3600)
        let first = snapshot(at: Date(timeIntervalSince1970: 1_000), remaining: 90)
        var state = store.record(snapshot: first, previous: PersistedQuotaState())
        #expect(state.history.count == 1)

        let tooSoon = snapshot(at: Date(timeIntervalSince1970: 1_000 + 60), remaining: 88)
        state = store.record(snapshot: tooSoon, previous: state)
        #expect(state.history.count == 1)
        #expect(state.lastSnapshot?.remainingPercent == 88)

        let later = snapshot(at: Date(timeIntervalSince1970: 1_000 + 16 * 60), remaining: 80)
        state = store.record(snapshot: later, previous: state)
        #expect(state.history.count == 2)
    }

    private func snapshot(at date: Date, remaining: Double) -> CodexQuotaSnapshot {
        CodexQuotaSnapshot(
            planType: "plus",
            usedPercent: 100 - remaining,
            remainingPercent: remaining,
            resetAt: date.addingTimeInterval(86_400),
            windowMinutes: 10_080,
            fetchedAt: date
        )
    }
}
