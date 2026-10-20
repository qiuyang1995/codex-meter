import Foundation
import CodexMeterCore

@main
enum TestRunner {
    @MainActor static func main() async {
        if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--fixture-app-server" {
            runFixtureAppServer(root: URL(fileURLWithPath: CommandLine.arguments[2]))
            return
        }
        var failures = 0
        let cases: [(String, () throws -> Void)] = [
            ("quota.preferredIdentity", testPreferredIdentity),
            ("locator.updatedBundle", testUpdatedBundleDiscovery),
            ("locator.freshInstallAndAppSelection", testFreshInstallAndAppSelection),
            ("quota.accountNullShape", testAccountNullShape),
            ("quota.rateLimitIdentity", testRateLimitIdentity),
            ("quota.accountIdentity", testAccountIdentity),
            ("quota.resetCredits", testResetCredits),
            ("usage.weeklyTotals", testWeeklyTokenTotals),
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

        let asyncCases: [(String, () async throws -> Void)] = [
            ("usage.localIncremental", testLocalTokenUsage),
            ("quota.refreshFlow", testAccountRefreshFlow)
        ]
        for (name, body) in asyncCases {
            do {
                try await body()
                print("PASS  \(name)")
            } catch {
                failures += 1
                print("FAIL  \(name): \(error)")
            }
        }
        let total = cases.count + asyncCases.count
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

func testWeeklyTokenTotals() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    let daily: [Date: Int64] = [date(2026, 8, 30): 10, date(2026, 8, 31): 20,
                              date(2026, 9, 6): 30, date(2026, 9, 14): 40,
                              date(2026, 9, 16): 50, date(2026, 9, 17): 999]
    let weeks = TokenUsageStatistics.byWeek(daily, through: date(2026, 9, 16), calendar: calendar)
    try expect(weeks.count == 4, "includes missing historical weeks")
    try expect(weeks.map(\.tokens) == [10, 50, nil, 90], "Monday to Sunday totals, cross-month and partial current week; excludes future")
    try expect(weeks[1].start == date(2026, 8, 31), "Monday boundary")
    let year = TokenUsageStatistics.byWeek([date(2026, 12, 31): 7, date(2027, 1, 1): 8], through: date(2027, 1, 1), calendar: calendar)
    try expect(year.count == 1 && year[0].tokens == 15 && year[0].start == date(2026, 12, 28), "one week crosses year")
    let dst = TokenUsageStatistics.byWeek([date(2026, 3, 2): 1, date(2026, 3, 8): 2, date(2026, 3, 9): 0], through: date(2026, 3, 9), calendar: calendar)
    try expect(dst.map(\.tokens) == [3, 0] && dst[0].end == date(2026, 3, 9), "DST and explicit zero")
    try expect(TokenUsageStatistics.byWeek([:], through: Date(), calendar: calendar).isEmpty, "empty data")
}

func testResetCredits() throws {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    func parse(_ json: String) throws -> RateLimitResetCredits? {
        try CodexQuotaParser.parseResetCredits(data: Data(json.utf8))
    }
    let summary = try parse(#"{"rateLimitResetCredits":{"availableCount":2,"credits":[{"id":"second","resetType":"codexRateLimits","status":"available","expiresAt":1790200000},{"id":"first","resetType":"codexRateLimits","status":"available","expiresAt":1790100000}]}}"#)
    try expect(summary?.availableCount(at: now) == 2, "available count")
    try expect(summary?.availableCredits(at: now).map(\.id) == ["first", "second"], "soonest expiration first")
    try expect(summary?.availableCredits(at: now).first?.displayTitle == "完全重置（每周 + 5 小时）", "localized reset type")
    try expect(summary?.availableCount(at: Date(timeIntervalSince1970: 1_790_100_000)) == 1, "hide credit exactly at expiry")
    try expect(summary?.availableCount(at: Date(timeIntervalSince1970: 1_790_200_000)) == 0, "hide section after all expire")
    let zero = try parse(#"{"rateLimitResetCredits":{"availableCount":0,"credits":[]}}"#)
    try expect(zero?.availableCount(at: now) == 0, "zero hides section")
    let absent = try parse("{}")
    let null = try parse(#"{"rateLimitResetCredits":null}"#)
    try expect(absent == nil && null == nil, "old servers / unavailable metadata hide section")
    let countOnly = try parse(#"{"rateLimitResetCredits":{"availableCount":3,"credits":null}}"#)
    try expect(countOnly?.availableCount(at: now) == 3 && countOnly?.credits == nil, "count-only response remains visible")
    let limited = try parse(#"{"rateLimitResetCredits":{"availableCount":3,"credits":[{"id":"a","resetType":"unknown","title":"特殊重置","status":"available","expiresAt":null},{"id":"b","resetType":"codexRateLimits","status":"redeemed","expiresAt":null}]}}"#)
    try expect(limited?.availableCount(at: now) == 3 && limited?.availableCredits(at: now).count == 1, "capped details and redeemed status")
    try expect(limited?.availableCredits(at: now).first?.displayTitle == "特殊重置", "unknown type preserves server title")
    try expect(limited?.availableCredits(at: now).first?.expiresAt == nil, "nonexpiring credit")
}

func testAccountIdentity() throws {
    let nested = CodexQuotaParser.decodeAccount(Data(#"{"account":{"id":"acct-new","type":"chatgpt","planType":"pro"}}"#.utf8))
    try expect(nested.accountId == "acct-new" && nested.accountType == "chatgpt" && nested.planType == "pro" && nested.loggedIn, "nested account identity")
    let alternate = CodexQuotaParser.decodeAccount(Data(#"{"account":{"account_id":"acct-2","type":"chatgpt"}}"#.utf8))
    try expect(alternate.accountId == "acct-2", "snake-case account identity")
    let topLevel = CodexQuotaParser.decodeAccount(Data(#"{"accountId":"acct-top","requiresOpenaiAuth":false}"#.utf8))
    try expect(topLevel.accountId == "acct-top" && topLevel.loggedIn, "top-level account identity")
    let subject = CodexQuotaParser.decodeAccount(Data(#"{"account":{"type":"chatgpt","sub":"acct-sub"}}"#.utf8))
    try expect(subject.accountId == "acct-sub", "subject account identity")
    let missing = CodexQuotaParser.decodeAccount(Data(#"{"account":{"type":"chatgpt"}}"#.utf8))
    try expect(missing.accountId == nil && missing.loggedIn, "missing identity remains usable")
}

func testRateLimitIdentity() throws {
    let top = CodexQuotaParser.parseAccountId(data: Data(#"{"accountId":"acct-rate"}"#.utf8))
    try expect(top == "acct-rate", "rate limit top-level account id")
    let nested = CodexQuotaParser.parseAccountId(data: Data(#"{"account":{"email":"new@example.com"}}"#.utf8))
    try expect(nested == "new@example.com", "rate limit nested account id")
    let absent = CodexQuotaParser.parseAccountId(data: Data(#"{"rateLimits":{}}"#.utf8))
    try expect(absent == nil, "missing rate limit account id")
}

func testAccountNullShape() throws {
    let decoded = CodexQuotaParser.decodeAccount(Data(#"{"account":null,"requiresOpenaiAuth":true}"#.utf8))
    try expect(decoded.accountId == nil && decoded.requiresAuth && !decoded.loggedIn, "account null is deferred until rate limits")
    let rate = CodexQuotaParser.parseAccountId(data: Data(#"{"accountId":"fixture-account","rateLimits":{}}"#.utf8))
    try expect(rate != nil, "rate limits supplies account id")
}

func testPreferredIdentity() throws {
    let metadata = Data(#"{"account":{"type":"chatgpt","email":"first@example.test","planType":"plus"}}"#.utf8)
    let quota = Data(#"{"accountId":"fixture-first"}"#.utf8)
    let id = CodexQuotaParser.preferredAccountId(accountData: metadata, rateLimitsData: quota)
    try expect(id == "fixture-first", "quota UUID takes priority over metadata email")
    try expect(CodexQuotaParser.preferredAccountId(accountData: nil, rateLimitsData: quota) == id, "missing metadata does not change owner")
    try expect(CodexQuotaParser.preferredAccountId(accountData: metadata, rateLimitsData: Data("{}".utf8)) == "first@example.test", "older servers can fall back to metadata")
    try expect(CodexQuotaParser.preferredAccountId(accountData: Data(#"{"account":null}"#.utf8), rateLimitsData: Data("{}".utf8)) == nil, "unknown identity is not fabricated")
}

func testUpdatedBundleDiscovery() throws {
    let locator = CodexExecutableLocator()
    let updated = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
    let candidates = locator.candidatePaths(override: "/custom/codex", cached: "/removed/codex")
    try expect(candidates.first == "/custom/codex", "explicit executable override retains priority")
    try expect(candidates.contains(updated), "new CodexCLI bundle is discoverable")
    try expect(candidates.contains("/Applications/ChatGPT.app/Contents/Resources/codex"), "old app bundles remain supported")
    try expect(candidates.contains("/Applications/Codex.app/Contents/Resources/codex"), "Codex app name is supported")
    let home = NSHomeDirectory()
    try expect(candidates.contains("\(home)/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"), "user-installed Codex app is supported")
}

// This executable can also act as a local JSON-RPC server. Tests launch a new
// process for every connection and log synthetic requests to verify real restarts.
private func runFixtureAppServer(root: URL) {
    func append(_ text: String) {
        let file = root.appendingPathComponent("requests.log")
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data((text + "\n").utf8))
            try? handle.close()
        }
    }
    let pid = ProcessInfo.processInfo.processIdentifier
    append("launch \(pid)")
    while let line = readLine() {
        guard let data = line.data(using: .utf8),
              let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = request["id"], let method = request["method"] as? String else { continue }
        let params = request["params"] as? [String: Any]
        append("\(method) \(pid) refresh=\(params?["refreshToken"] as? Bool ?? false)")
        let mode = (try? String(contentsOf: root.appendingPathComponent("mode"), encoding: .utf8)) ?? "first"
        let second = mode.hasPrefix("second")
        let owner = second ? "fixture-second" : "fixture-first"
        var result: [String: Any] = [:]
        var error: [String: Any]?
        switch method {
        case "initialize": result = ["userAgent": "fixture"]
        case "account/read":
            if mode == "metadata_error" || mode == "second_without_metadata" {
                error = ["code": 401, "message": "account metadata unavailable: not logged in"]
            } else if mode == "metadata_null" || mode == "anonymous" || mode == "unauthorized" {
                result = ["account": NSNull(), "requiresOpenaiAuth": true]
            } else {
                result = ["account": ["type": "chatgpt", "email": second ? "second@example.test" : "first@example.test", "planType": "plus"], "requiresOpenaiAuth": true]
            }
        case "account/rateLimits/read":
            if mode == "unauthorized" { error = ["code": 401, "message": "not logged in"] }
            result = [
                "accountId": mode == "anonymous" ? NSNull() : owner as Any,
                "rateLimits": ["limitId": "codex", "planType": "plus",
                    "primary": ["usedPercent": 25, "windowDurationMins": 300, "resetsAt": 1_900_000_000],
                    "secondary": ["usedPercent": second ? 70 : 40, "windowDurationMins": 10080, "resetsAt": 1_900_600_000]],
                "rateLimitResetCredits": ["availableCount": second ? 0 : 1, "credits": NSNull()]
            ]
        case "account/usage/read":
            result = ["summary": ["lifetimeTokens": second ? 2000 : 1000], "dailyUsageBuckets": []]
        default: error = ["code": -32601, "message": "Method not found"]
        }
        let response: [String: Any] = error.map { ["id": id, "error": $0] } ?? ["id": id, "result": result]
        if let encoded = try? JSONSerialization.data(withJSONObject: response) {
            try? FileHandle.standardOutput.write(contentsOf: encoded + Data([10]))
        }
    }
}

@MainActor
func testAccountRefreshFlow() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let executable = root.appendingPathComponent("codex")
    func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
    let runner = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
    let script = "#!/bin/sh\nexec \(quote(runner)) --fixture-app-server \(quote(root.path))\n"
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    func mode(_ value: String) throws { try Data(value.utf8).write(to: root.appendingPathComponent("mode")) }
    func requests() -> [String] {
        ((try? String(contentsOf: root.appendingPathComponent("requests.log"), encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }
    func launches() -> [String] { requests().filter { $0.hasPrefix("launch ") } }
    let suite = "CodexMeter.account-refresh-test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.register(defaults: ["settings.executableOverride": executable.path, "settings.notificationsEnabled": false])
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let store = HistoryStore(fileURL: root.appendingPathComponent("cache.json"))
    let oldSnapshot = CodexQuotaSnapshot(planType: "plus", usedPercent: 40, remainingPercent: 60,
        resetAt: Date(timeIntervalSince1970: 1_900_600_000), windowMinutes: 10080, fetchedAt: Date().addingTimeInterval(-1200))
    store.save(PersistedQuotaState(accountId: "fixture-first", lastSnapshot: oldSnapshot,
                                  history: [QuotaHistoryPoint(snapshot: oldSnapshot)]))
    let client = CodexAppServerClient()
    let service = CodexQuotaService(settings: settings, client: client, store: store, notifications: NotificationService())
    do {
        try mode("first")
        service.start()
        let deadline = Date().addingTimeInterval(8)
        while service.connectionState != .connected && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try expect(service.connectionState == .connected && service.accountId == "fixture-first", "email and quota UUID connect successfully")
        try expect(launches().count == 1, "same UUID with an email must not restart")
        try expect(service.history.count == 2, "same-account cached history is preserved")

        await service.refresh(forceReconnect: true)
        try expect(launches().count == 2 && Set(launches()).count == 2, "force refresh starts a different process")
        let running = await client.running()
        try expect(running && service.connectionState == .connected, "old exit callback must not invalidate restarted process")
        try expect(requests().filter { $0.hasPrefix("account/read ") }.allSatisfy { $0.hasSuffix("refresh=true") }, "refresh asks for refreshed account metadata")

        try mode("metadata_null")
        await service.refresh()
        try expect(service.connectionState == .connected && launches().count == 2, "null metadata still reads valid quotas")
        try mode("metadata_error")
        await service.refresh()
        try expect(service.connectionState == .connected && service.lastErrorMessage == nil, "metadata error does not block authenticated quotas")

        try mode("second_without_metadata")
        await service.refresh()
        try expect(service.connectionState == .connected && service.accountId == "fixture-second", "quota owner detects account change without metadata")
        try expect(launches().count == 3 && Set(launches()).count == 3, "account switch restarts exactly once")
        try expect(service.snapshot?.remainingPercent == 30 && service.lifetimeTokens == 2000, "new account quota and token summary replace old data")
        try expect(service.resetCredits?.availableCount == 0, "old account reset credits are removed")
        let stored = store.load()
        try expect(stored.accountId == "fixture-second" && stored.history.count == 1 && stored.history.first?.usedPercent == 70, "old account disk history is cleared and new owner persisted")

        try mode("second")
        await service.refresh()
        try expect(launches().count == 3 && service.accountId == "fixture-second", "subsequent email metadata keeps canonical UUID")
        try mode("anonymous")
        await service.refresh()
        try expect(service.connectionState == .connected && service.accountId == "fixture-second" && launches().count == 3, "missing identity does not erase last owner or block valid quota")
        try mode("unauthorized")
        await service.refresh()
        try expect(service.connectionState != .connected && service.lastErrorMessage == "Codex 尚未登录", "unauthorized quota endpoint is still reported")
    } catch {
        await service.shutdown()
        throw error
    }
    await service.shutdown()
}

func testFreshInstallAndAppSelection() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let manager = FileManager.default
    let layouts = [
        "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        "Contents/Resources/codex-cli/bin/codex",
        "Contents/Resources/codex",
        "Contents/MacOS/codex"
    ]
    for (index, layout) in layouts.enumerated() {
        let app = root.appendingPathComponent("Custom Location/Official App \(index).app")
        let executable = app.appendingPathComponent(layout)
        try manager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let locator = CodexExecutableLocator(applicationURLs: [app])
        try expect(locator.resolve() == executable, "fresh user with no cached path can find layout \(index)")
        try expect(locator.resolve(cached: root.appendingPathComponent("removed-cli").path) == executable, "stale cached path falls back to app \(index)")
        try expect(locator.validatedExecutable(at: app.path) == executable, "selecting app package resolves CLI \(index)")
        try expect(locator.validatedExecutable(at: executable.path) == executable, "direct CLI selection still works \(index)")
        try expect(locator.resolve(override: app.path) == executable, "app package override is accepted \(index)")
        try manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: executable.path)
        try expect(locator.validatedExecutable(at: app.path) == nil, "non-executable bundled file is rejected")
    }
    let notAnApp = root.appendingPathComponent("Ordinary Folder")
    try manager.createDirectory(at: notAnApp, withIntermediateDirectories: true)
    try expect(CodexExecutableLocator(applicationURLs: []).validatedExecutable(at: notAnApp.path) == nil, "ordinary directories are not executable")
}
