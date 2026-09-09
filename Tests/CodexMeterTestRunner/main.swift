import Foundation
import CodexMeterCore

@main
enum TestRunner {
    static func main() async {
        var failures = 0
        let cases: [(String, () throws -> Void)] = [
            ("usage.calendar", testTokenCalendar),
            ("usage.lifetime", testLifetimeTokens),
            ("parser.weeklyOnly", testWeeklyOnlyWindow),
            ("parser.prefersWeekly", testPrefersWeeklyOverFiveHourWindow),
            ("parser.weeklyPrimary", testWeeklyInPrimary),
            ("parser.weeklySecondary", testWeeklyInSecondary),
            ("parser.missingResetAt", testMissingResetAtDoesNotCrash),
            ("parser.unknownFields", testUnknownFieldsAreIgnored),
            ("parser.clampHigh", testUsedPercentAbove100IsClamped),
            ("parser.clampLow", testUsedPercentBelowZeroIsClamped),
            ("parser.snakeCase", testSnakeCaseWindowMinutes),
            ("parser.byLimitId", testWeeklyInRateLimitsByLimitId),
            ("parser.remainingFallback", testMissingUsedPercentFallsBackToRemaining),
            ("parser.fiveHourRemainingFallback", testFiveHourRemainingFallback),
            ("parser.tokenUsage", testTokenUsageBuckets),
            ("parser.emptyTokenUsage", testEmptyTokenUsage),
            ("pace.normalBehind", testNormalWhenUsageBehindTime),
            ("pace.normalSlightlyAhead", testNormalWhenUsageSlightlyAhead),
            ("pace.slightlyFast", testSlightlyFast),
            ("pace.tooFast", testTooFastWhenUsageFarAheadOfTime),
            ("pace.elapsed", testElapsedPercentFromResetWindow),
            ("pace.unknown", testElapsedPercentUnknownWithoutReset),
            ("notify.oncePerWindow", testEachThresholdFiresOncePerWindow),
            ("notify.lowerThresholds", testLowerThresholdsCanStillFire),
            ("notify.resetAllowsAgain", testResetAllowsThresholdsAgain),
            ("notify.disabled", testDisabledNotificationsSuppressThresholds),
            ("cycle.singleGlitch", testSingleGlitchDoesNotReset),
            ("cycle.twoConfirmations", testTwoConfirmationsReset),
            ("cycle.needsTwoSamples", testResetAtChangeStillNeedsTwoSamples),
            ("history.interval", testRecordsFirstPointAndRespectsInterval)
        ]

        for (name, body) in cases {
            do {
                try body()
                print("PASS  \(name)")
            } catch {
                failures += 1
                print("FAIL  \(name): \(error)")
            }
        }

        do {
            try await testLocalTokenUsage()
            print("PASS  usage.localIncremental")
        } catch {
            failures += 1
            print("FAIL  usage.localIncremental: \(error)")
        }
        let total = cases.count + 1
        print("----")
        print("\(total - failures) passed, \(failures) failed, \(total) total")
        if failures > 0 {
            exit(1)
        }
        print("TESTS PASSED")
    }
}

struct ExpectationFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #fileID, line: UInt = #line) throws {
    if condition() == false {
        throw ExpectationFailure(message: "\(file):\(line) \(message)")
    }
}

func snapshotJSON(_ json: String) throws -> CodexQuotaSnapshot {
    try CodexQuotaParser.parseRateLimits(json: json)
}

func testWeeklyOnlyWindow() throws {
    let snapshot = try snapshotJSON("""
    {"rateLimits":{"primary":{"usedPercent":32,"windowDurationMins":10080,"resetsAt":1787205408}}}
    """)
    try expect(snapshot.usedPercent == 32, "used should be 32")
    try expect(snapshot.remainingPercent == 68, "remaining should be 68")
    try expect(snapshot.fiveHourUsedPercent == nil, "5-hour window should be absent")
    try expect(snapshot.windowMinutes == 10080, "window should be weekly")
    try expect(snapshot.resetAt?.timeIntervalSince1970 == 1_787_205_408, "reset timestamp")
}

func testPrefersWeeklyOverFiveHourWindow() throws {
    let snapshot = try snapshotJSON("""
    {"rateLimits":{"primary":{"usedPercent":80,"windowDurationMins":300,"resetsAt":1786617000},"secondary":{"usedPercent":32,"windowDurationMins":10080,"resetsAt":1787205408}}}
    """)
    try expect(snapshot.windowMinutes == 10080, "should pick weekly")
    try expect(snapshot.usedPercent == 32, "used should come from weekly")
    try expect(snapshot.remainingPercent == 68, "remaining should be 68")
    try expect(snapshot.fiveHourUsedPercent == 80, "5-hour used should be 80")
    try expect(snapshot.fiveHourRemainingPercent == 20, "5-hour remaining should be 20")
    try expect(snapshot.fiveHourResetAt?.timeIntervalSince1970 == 1_786_617_000, "5-hour reset timestamp")
}

func testWeeklyInPrimary() throws {
    let snapshot = try snapshotJSON("""
    {"rateLimits":{"primary":{"usedPercent":12,"windowDurationMins":10080,"resetsAt":1787205408},"secondary":{"usedPercent":44,"windowDurationMins":300}}}
    """)
    try expect(snapshot.usedPercent == 12, "primary weekly used")
    try expect(snapshot.remainingPercent == 88, "remaining")
}

func testWeeklyInSecondary() throws {
    let snapshot = try snapshotJSON("""
    {"rateLimits":{"primary":{"usedPercent":91,"windowDurationMins":300},"secondary":{"usedPercent":55,"windowDurationMins":10080}}}
    """)
    try expect(snapshot.windowMinutes == 10080, "secondary weekly")
    try expect(snapshot.usedPercent == 55, "used")
    try expect(snapshot.remainingPercent == 45, "remaining")
}

func testMissingResetAtDoesNotCrash() throws {
    let snapshot = try snapshotJSON("""
    {"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":10080}}}
    """)
    try expect(snapshot.resetAt == nil, "reset missing")
    try expect(snapshot.remainingPercent == 80, "remaining")
}

func testUnknownFieldsAreIgnored() throws {
    let snapshot = try snapshotJSON("""
    {"rateLimits":{"limitId":"codex","brandNewField":{"nested":true},"primary":{"usedPercent":4,"windowDurationMins":10080,"resetsAt":1787205408,"mystery":"ok"}},"futureArray":[1,2,3]}
    """)
    try expect(snapshot.usedPercent == 4, "used")
    try expect(snapshot.remainingPercent == 96, "remaining")
    try expect(snapshot.limitId == "codex", "limit id")
}

func testUsedPercentAbove100IsClamped() throws {
    let snapshot = try snapshotJSON("""
    {"rateLimits":{"primary":{"usedPercent":150,"windowDurationMins":10080}}}
    """)
    try expect(snapshot.usedPercent == 100, "clamped used")
    try expect(snapshot.remainingPercent == 0, "clamped remaining")
}

func testUsedPercentBelowZeroIsClamped() throws {
    let snapshot = try snapshotJSON("""
    {"rateLimits":{"primary":{"usedPercent":-10,"windowDurationMins":10080}}}
    """)
    try expect(snapshot.usedPercent == 0, "clamped used")
    try expect(snapshot.remainingPercent == 100, "clamped remaining")
}

func testSnakeCaseWindowMinutes() throws {
    let snapshot = try snapshotJSON("""
    {"rate_limits":{"secondary":{"used_percent":40,"window_minutes":10080,"resets_at":1787205408}}}
    """)
    try expect(snapshot.usedPercent == 40, "used")
    try expect(snapshot.remainingPercent == 60, "remaining")
    try expect(snapshot.resetAt != nil, "reset parsed")
}

func testWeeklyInRateLimitsByLimitId() throws {
    let snapshot = try snapshotJSON("""
    {"rateLimits":{"primary":{"usedPercent":99,"windowDurationMins":300}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","planType":"plus","primary":{"usedPercent":4,"windowDurationMins":10080,"resetsAt":1787205408}}}}
    """)
    try expect(snapshot.usedPercent == 4, "used from codex bucket")
    try expect(snapshot.planType == "plus", "plan")
}

func testMissingUsedPercentFallsBackToRemaining() throws {
    let snapshot = try snapshotJSON("""
    {"rateLimits":{"primary":{"remainingPercent":72,"windowDurationMins":10080}}}
    """)
    try expect(snapshot.remainingPercent == 72, "remaining")
    try expect(snapshot.usedPercent == 28, "used derived")
}

func testFiveHourRemainingFallback() throws {
    let snapshot = try snapshotJSON("""
    {"rateLimits":{"primary":{"remainingPercent":65,"windowDurationMins":300,"resetsAt":1786617000},"secondary":{"usedPercent":28,"windowDurationMins":10080}}}
    """)
    try expect(snapshot.fiveHourUsedPercent == 35, "5-hour used derived from remaining")
    try expect(snapshot.fiveHourRemainingPercent == 65, "5-hour remaining")
}

func testTokenUsageBuckets() throws {
    let data = Data("""
    {"dailyUsageBuckets":[{"startDate":"2026-08-16","tokens":12345},{"startDate":"2026-08-17","tokens":67890}],"summary":{"lifetimeTokens":80235}}
    """.utf8)
    let buckets = try CodexQuotaParser.parseTokenUsage(data: data)
    try expect(buckets.count == 2, "two daily buckets")
    try expect(buckets[0] == AccountTokenUsageDailyBucket(startDate: "2026-08-16", tokens: 12_345), "first bucket")
    try expect(buckets[1].tokens == 67_890, "second bucket")
}

func testEmptyTokenUsage() throws {
    let data = Data(#"{"dailyUsageBuckets":null,"summary":{}}"#.utf8)
    let buckets = try CodexQuotaParser.parseTokenUsage(data: data)
    try expect(buckets.isEmpty, "null daily buckets should be empty")
}

func testNormalWhenUsageBehindTime() throws {
    try expect(UsagePace.evaluate(usedPercent: 30, elapsedPercent: 50) == .normal, "normal")
}

func testNormalWhenUsageSlightlyAhead() throws {
    try expect(UsagePace.evaluate(usedPercent: 58, elapsedPercent: 50) == .normal, "still normal")
}

func testSlightlyFast() throws {
    try expect(UsagePace.evaluate(usedPercent: 65, elapsedPercent: 50) == .slightlyFast, "slightly fast")
}

func testTooFastWhenUsageFarAheadOfTime() throws {
    try expect(UsagePace.evaluate(usedPercent: 65, elapsedPercent: 30) == .tooFast, "too fast")
}

func testElapsedPercentFromResetWindow() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let windowMinutes = 10_080
    let resetAt = now.addingTimeInterval(TimeInterval((windowMinutes / 2) * 60))
    let elapsed = UsagePace.elapsedPercent(resetAt: resetAt, windowMinutes: windowMinutes, now: now)
    try expect(abs((elapsed ?? -1) - 50) < 0.2, "elapsed about 50")
}

func testElapsedPercentUnknownWithoutReset() throws {
    try expect(UsagePace.elapsedPercent(resetAt: nil, windowMinutes: 10080) == nil, "unknown")
}

func makeSnapshot(remaining: Double, reset: TimeInterval) -> CodexQuotaSnapshot {
    CodexQuotaSnapshot(
        planType: "plus",
        usedPercent: 100 - remaining,
        remainingPercent: remaining,
        resetAt: Date(timeIntervalSince1970: reset),
        windowMinutes: 10_080,
        fetchedAt: Date(timeIntervalSince1970: reset - 1000)
    )
}

func testEachThresholdFiresOncePerWindow() throws {
    var state = NotificationState()
    let decision1 = NotificationPolicy.evaluate(
        snapshot: makeSnapshot(remaining: 29, reset: 100),
        previous: state,
        notificationsEnabled: true,
        notifyOnRefresh: true,
        thresholds: [30, 15, 5],
        cycleDidReset: false
    )
    try expect(decision1.notifications == [.remaining(threshold: 30)], "first 30%")
    state = decision1.nextState
    let decision2 = NotificationPolicy.evaluate(
        snapshot: makeSnapshot(remaining: 28, reset: 100),
        previous: state,
        notificationsEnabled: true,
        notifyOnRefresh: true,
        thresholds: [30, 15, 5],
        cycleDidReset: false
    )
    try expect(decision2.notifications.isEmpty, "no repeat")
}

func testLowerThresholdsCanStillFire() throws {
    let decision = NotificationPolicy.evaluate(
        snapshot: makeSnapshot(remaining: 4, reset: 100),
        previous: NotificationState(windowKey: "reset-100", firedThresholds: [30]),
        notificationsEnabled: true,
        notifyOnRefresh: false,
        thresholds: [30, 15, 5],
        cycleDidReset: false
    )
    try expect(decision.notifications == [.remaining(threshold: 15), .remaining(threshold: 5)], "15 and 5")
    try expect(Set(decision.nextState.firedThresholds) == [30, 15, 5], "all fired")
}

func testResetAllowsThresholdsAgain() throws {
    let snap = makeSnapshot(remaining: 96, reset: 200)
    let decision = NotificationPolicy.evaluate(
        snapshot: snap,
        previous: NotificationState(windowKey: "reset-100", firedThresholds: [30, 15, 5], firedRefresh: true),
        notificationsEnabled: true,
        notifyOnRefresh: true,
        thresholds: [30, 15, 5],
        cycleDidReset: true
    )
    try expect(decision.notifications == [.weeklyRefreshed], "refresh notice")
    try expect(decision.nextState.windowKey == snap.windowKey, "new window")
    try expect(decision.nextState.firedThresholds.isEmpty, "thresholds cleared")
}

func testDisabledNotificationsSuppressThresholds() throws {
    let decision = NotificationPolicy.evaluate(
        snapshot: makeSnapshot(remaining: 4, reset: 100),
        previous: NotificationState(),
        notificationsEnabled: false,
        notifyOnRefresh: true,
        thresholds: [30, 15, 5],
        cycleDidReset: false
    )
    try expect(decision.notifications.isEmpty, "suppressed")
}

func makeCycle(used: Double, reset: TimeInterval) -> CodexQuotaSnapshot {
    CodexQuotaSnapshot(
        planType: "plus",
        usedPercent: used,
        remainingPercent: 100 - used,
        resetAt: Date(timeIntervalSince1970: reset),
        windowMinutes: 10_080,
        fetchedAt: Date()
    )
}

func testSingleGlitchDoesNotReset() throws {
    var detector = CycleDetector()
    try expect(detector.observe(makeCycle(used: 80, reset: 100)) == false, "seed")
    try expect(detector.observe(makeCycle(used: 3, reset: 999)) == false, "single glitch")
}

func testTwoConfirmationsReset() throws {
    var detector = CycleDetector()
    try expect(detector.observe(makeCycle(used: 80, reset: 100)) == false, "seed")
    try expect(detector.observe(makeCycle(used: 4, reset: 200)) == false, "first new")
    try expect(detector.observe(makeCycle(used: 5, reset: 200)) == true, "confirmed")
}

func testResetAtChangeStillNeedsTwoSamples() throws {
    var detector = CycleDetector()
    try expect(detector.observe(makeCycle(used: 70, reset: 100)) == false, "seed")
    try expect(detector.observe(makeCycle(used: 2, reset: 200)) == false, "first")
    try expect(detector.observe(makeCycle(used: 3, reset: 200)) == true, "second")
}

func testRecordsFirstPointAndRespectsInterval() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("codex-meter-test-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let store = HistoryStore(fileURL: url, minimumSampleInterval: 15 * 60, retention: 30 * 24 * 3600)
    let first = CodexQuotaSnapshot(planType: "plus", usedPercent: 10, remainingPercent: 90, resetAt: Date(timeIntervalSince1970: 86_400), windowMinutes: 10_080, fetchedAt: Date(timeIntervalSince1970: 1_000))
    var state = store.record(snapshot: first, previous: PersistedQuotaState())
    try expect(state.history.count == 1, "first point")

    let tooSoon = CodexQuotaSnapshot(planType: "plus", usedPercent: 12, remainingPercent: 88, resetAt: Date(timeIntervalSince1970: 86_400), windowMinutes: 10_080, fetchedAt: Date(timeIntervalSince1970: 1_060))
    state = store.record(snapshot: tooSoon, previous: state)
    try expect(state.history.count == 1, "interval respected")
    try expect(state.lastSnapshot?.remainingPercent == 88, "latest snapshot updated")

    let later = CodexQuotaSnapshot(planType: "plus", usedPercent: 20, remainingPercent: 80, resetAt: Date(timeIntervalSince1970: 86_400), windowMinutes: 10_080, fetchedAt: Date(timeIntervalSince1970: 1_000 + 16 * 60))
    state = store.record(snapshot: later, previous: state)
    try expect(state.history.count == 2, "second point recorded")
}

func testTokenCalendar() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    let september = TokenUsagePeriod.month.days(containing: date(2026, 9, 9), calendar: calendar)
    try expect(september.count == 30, "September length")
    try expect(calendar.component(.weekday, from: september[0]) == 3, "September starts Tuesday")
    let sunday = TokenUsagePeriod.week.days(containing: date(2026, 9, 13), calendar: calendar)
    try expect(sunday.count == 7 && calendar.component(.day, from: sunday[0]) == 7, "Sunday stays in Monday week")
    let monday = TokenUsagePeriod.week.days(containing: date(2026, 9, 14), calendar: calendar)
    try expect(calendar.component(.day, from: monday[0]) == 14, "Monday begins new week")
    try expect(TokenUsagePeriod.month.days(containing: date(2024, 2, 9), calendar: calendar).count == 29, "leap month")
    let dst = TokenUsagePeriod.week.days(containing: date(2026, 3, 8), calendar: calendar)
    try expect(dst.count == 7 && dst.allSatisfy { calendar.component(.hour, from: $0) == 0 }, "DST retains local midnight")
    let year = TokenUsagePeriod.week.days(containing: date(2027, 1, 1), calendar: calendar)
    try expect(calendar.component(.year, from: year[0]) == 2026, "week crosses year")
    let buckets = TokenUsageStatistics.byDay([.init(startDate: "2026-09-09", tokens: 0), .init(startDate: "bad", tokens: 10)], calendar: calendar)
    try expect(buckets.count == 1 && buckets[calendar.startOfDay(for: date(2026, 9, 9))] == 0, "zero distinct from missing and local date preserved")
}

func testLifetimeTokens() throws {
    let data = Data(#"{"summary":{"lifetimeTokens":4490000000}}"#.utf8)
    let total = try CodexQuotaParser.parseLifetimeTokens(data: data)
    try expect(total == 4_490_000_000, "lifetime total beyond 32-bit")
    let absent = try CodexQuotaParser.parseLifetimeTokens(data: Data("{}".utf8))
    try expect(absent == nil, "missing total remains unavailable")
    let negative = try CodexQuotaParser.parseLifetimeTokens(data: Data(#"{"summary":{"lifetimeTokens":-1}}"#.utf8))
    try expect(negative == nil, "invalid total ignored")
}

func testLocalTokenUsage() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("sessions")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 12))!
    let file = directory.appendingPathComponent("old-session.jsonl")
    func event(_ timestamp: String, _ total: Int, _ last: Int) -> String {
        "{\"timestamp\":\"\(timestamp)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":\(total)},\"last_token_usage\":{\"total_tokens\":\(last)}}}}"
    }
    let metadata = "{\"type\":\"session_meta\",\"payload\":{\"model_provider\":\"openai\"}}\n"
    let before = event("2026-09-08T15:59:00.000Z", 100, 100)
    let first = event("2026-09-08T16:01:00.000Z", 160, 60)
    var contents = metadata + before + "\n" + first + "\n" + first + "\n"
    try Data(contents.utf8).write(to: file)
    try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
    let tracker = LocalTokenUsageTracker(root: root)
    var sample = await tracker.sample(now: now, calendar: calendar)
    try expect(sample?.tokens == 60, "local midnight baseline and duplicate cumulative record")
    sample = await tracker.sample(now: now, calendar: calendar)
    try expect(sample?.tokens == 60, "unchanged file does not count twice")

    let partial = event("2026-09-09T01:00:00.000Z", 200, 40)
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(partial.utf8))
    sample = await tracker.sample(now: now, calendar: calendar)
    try expect(sample?.tokens == 60, "partial final line waits for newline")
    try handle.write(contentsOf: Data("\n".utf8))
    try handle.close()
    sample = await tracker.sample(now: now, calendar: calendar)
    try expect(sample?.tokens == 100, "incremental appended line")
    contents += partial + "\n"

    let archive = root.appendingPathComponent("archived_sessions")
    try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
    try Data(contents.utf8).write(to: archive.appendingPathComponent("copy.jsonl"))
    // A fork with a copied first record must not count its inherited cumulative total.
    try Data((metadata + first + "\n").utf8).write(to: directory.appendingPathComponent("fork.jsonl"))
    sample = await tracker.sample(now: now, calendar: calendar)
    try expect(sample?.tokens == 100, "archived/forked event copies deduplicate")
    let restarted = LocalTokenUsageTracker(root: root)
    sample = await restarted.sample(now: now, calendar: calendar)
    try expect(sample?.tokens == 100, "app restart recovers today's count")

    let other = metadata.replacingOccurrences(of: "openai", with: "other") + event("2026-09-09T02:00:00.000Z", 999, 999) + "\n"
    try Data(other.utf8).write(to: directory.appendingPathComponent("other.jsonl"))
    sample = await tracker.sample(now: now, calendar: calendar)
    try expect(sample?.tokens == 100, "other model providers excluded")
    let reset = event("2026-09-09T03:00:00.000Z", 10, 10)
    let append = try FileHandle(forWritingTo: file)
    try append.seekToEnd()
    try append.write(contentsOf: Data((reset + "\n" + reset + "\n").utf8))
    try append.close()
    sample = await tracker.sample(now: now, calendar: calendar)
    try expect(sample?.tokens == 110, "counter reset and repeated reset record")

    let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
    sample = await tracker.sample(now: tomorrow, calendar: calendar)
    try expect(sample?.tokens == 0 && sample?.day == calendar.startOfDay(for: tomorrow), "daily rollover")
    let missing = LocalTokenUsageTracker(root: root.appendingPathComponent("missing"))
    sample = await missing.sample(now: now, calendar: calendar)
    try expect(sample == nil, "unavailable directory does not fabricate zero")
}
