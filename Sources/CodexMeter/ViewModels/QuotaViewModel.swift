import Combine
import Foundation
import SwiftUI
import CodexMeterCore

@MainActor
final class QuotaViewModel: ObservableObject {
    let service: CodexQuotaService
    let settings: AppSettings

    @Published private(set) var tick = Date()
    @Published private(set) var tokenUsageByDay: [Date: Int64] = [:]

    private var historicalTokenUsageByDay: [Date: Int64] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var timer: AnyCancellable?

    init(service: CodexQuotaService, settings: AppSettings) {
        self.service = service
        self.settings = settings

        // 仅在接口数据变化时建立日期索引；悬停和周/月切换只查表。
        service.$dailyTokenUsage
            .removeDuplicates()
            .map { TokenUsageStatistics.byDay($0) }
            .combineLatest(service.$localTodayUsage.removeDuplicates())
            .sink { [weak self] historical, local in
                self?.historicalTokenUsageByDay = historical
                var usage = historical
                if let local, Calendar.current.isDateInToday(local.day) { usage[local.day] = local.tokens }
                self?.tokenUsageByDay = usage
            }
            .store(in: &cancellables)

        service.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        timer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                self?.tick = date
            }
    }

    var snapshot: CodexQuotaSnapshot? { service.snapshot }
    var history: [QuotaHistoryPoint] { service.history }
    var connectionState: CodexConnectionState { service.connectionState }
    var isRefreshing: Bool { service.isRefreshing }
    var lastSuccessfulRefresh: Date? { service.lastSuccessfulRefresh }
    var lastErrorMessage: String? { service.lastErrorMessage }
    var executablePath: String? { service.executableURL?.path }
    var planType: String? { service.planType ?? service.snapshot?.displayPlan }
    var dailyTokenUsage: [AccountTokenUsageDailyBucket] { service.dailyTokenUsage }

    var remainingText: String {
        guard let snapshot else { return "—" }
        return PercentageFormatting.display(snapshot.remainingPercent)
    }

    var menuBarRemainingText: String {
        guard let snapshot else { return "—" }
        return PercentageFormatting.display(snapshot.fiveHourRemainingPercent ?? snapshot.remainingPercent)
    }

    var menuBarSeverity: QuotaSeverity {
        guard let snapshot else { return .unknown }
        return QuotaSeverity.from(remainingPercent: snapshot.fiveHourRemainingPercent ?? snapshot.remainingPercent)
    }

    private var startOfWeek: Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar.dateInterval(of: .weekOfYear, for: tick)!.start
    }

    var usedText: String {
        guard let snapshot else { return "—" }
        return PercentageFormatting.display(snapshot.usedPercent)
    }

    var remainingValue: Double {
        snapshot?.remainingPercent ?? 0
    }

    var usedValue: Double {
        snapshot?.usedPercent ?? 0
    }

    var severity: QuotaSeverity {
        snapshot?.severity ?? .unknown
    }

    var fiveHourUsedValue: Double? { snapshot?.fiveHourUsedPercent }

    var fiveHourUsedText: String? {
        snapshot?.fiveHourUsedPercent.map(PercentageFormatting.display)
    }

    var fiveHourRemainingText: String? {
        snapshot?.fiveHourRemainingPercent.map(PercentageFormatting.display)
    }

    var fiveHourSeverity: QuotaSeverity {
        guard let remaining = snapshot?.fiveHourRemainingPercent else { return .unknown }
        return QuotaSeverity.from(remainingPercent: remaining)
    }

    var fiveHourResetText: String? {
        quotaResetText(for: snapshot?.fiveHourResetAt)
    }

    var weeklyResetText: String {
        quotaResetText(for: snapshot?.resetAt) ?? "刷新时间未知"
    }

    var elapsedPercent: Double? {
        guard let snapshot else { return nil }
        return UsagePace.elapsedPercent(
            resetAt: snapshot.resetAt,
            windowMinutes: snapshot.windowMinutes,
            now: tick
        )
    }

    var pace: UsagePace {
        guard let snapshot, let elapsedPercent else { return .unknown }
        return UsagePace.evaluate(usedPercent: snapshot.usedPercent, elapsedPercent: elapsedPercent)
    }

    var resetDateText: String {
        guard let resetAt = snapshot?.resetAt else { return "刷新时间未知" }
        return DateFormatting.resetDate(resetAt)
    }

    var resetCountdownText: String? {
        guard let resetAt = snapshot?.resetAt else { return nil }
        return DateFormatting.remaining(until: resetAt, now: tick)
    }

    var updatedText: String {
        if let lastSuccessfulRefresh {
            if connectionState == .offlineCached {
                return "最后更新：\(DateFormatting.clockTime(lastSuccessfulRefresh))"
            }
            return DateFormatting.relativeUpdated(from: lastSuccessfulRefresh, now: tick)
        }
        return "尚未更新"
    }

    var showsQuota: Bool {
        snapshot != nil
    }

    // MARK: - 原型图布局所需的派生数据

    var planName: String {
        if let plan = snapshot?.displayPlan ?? planType.map(CodexQuotaSnapshot.prettyPlan) {
            return "Codex \(plan)"
        }
        return "Codex"
    }

    /// 顶部套餐卡右侧的整数百分比，如 "51%"。
    var usedPercentBadgeText: String {
        guard let snapshot else { return "—" }
        return "\(Int(snapshot.usedPercent.rounded()))%"
    }

    var todayTokenTitle: String {
        guard let local = service.localTodayUsage, Calendar.current.isDateInToday(local.day) else { return "今日消耗" }
        return "今日 · 本机实时"
    }

    var todayTokenText: String? {
        guard !tokenUsageByDay.isEmpty else { return nil }
        let today = Calendar.current.startOfDay(for: tick)
        guard let tokens = tokenUsageByDay[today] else { return nil }
        return TokenFormatting.display(Double(tokens))
    }

    /// 本周 token 按本地时区从周一零点累计至今日。
    var weekTokenText: String? {
        guard !tokenUsageByDay.isEmpty else { return nil }
        let today = Calendar.current.startOfDay(for: tick)
        let total = tokenUsageByDay.reduce(Int64(0)) { partial, entry in
            partial + (entry.key >= startOfWeek && entry.key <= today ? entry.value : 0)
        }
        return TokenFormatting.display(Double(total))
    }

    var refreshScheduleText: String {
        guard let resetAt = snapshot?.resetAt else {
            return "每周刷新一次 · 下次刷新时间未知"
        }
        return "每周刷新一次 · 下次刷新: \(Self.weekdayClockFormatter.string(from: resetAt))"
    }

    private func quotaResetText(for date: Date?) -> String? {
        guard let date else { return nil }
        let remaining = DateFormatting.remaining(until: date, now: tick)
        let countdown = remaining.hasPrefix("还有") ? String(remaining.dropFirst(2)) + "后重置" : "即将重置"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDate(date, inSameDayAs: tick) ? "HH:mm" : "M月d日 HH:mm"
        return "\(countdown)（\(formatter.string(from: date))）"
    }

    var lifetimeTokenText: String {
        let historicalTotal = service.lifetimeTokens ?? (historicalTokenUsageByDay.isEmpty ? nil : historicalTokenUsageByDay.values.reduce(0, +))
        var total = historicalTotal
        if let local = service.localTodayUsage, Calendar.current.isDateInToday(local.day) {
            // Replace the server's delayed today bucket instead of adding it twice.
            total = max((historicalTotal ?? 0) - (historicalTokenUsageByDay[local.day] ?? 0), 0) + local.tokens
        }
        return total.map { TokenFormatting.display(Double($0)) } ?? "—"
    }

    var lifetimeTokenCaption: String {
        if let local = service.localTodayUsage, Calendar.current.isDateInToday(local.day) { return "含本机今日用量" }
        return service.lifetimeTokens == nil ? "已获取的历史" : "全部历史"
    }

    var peakTokenText: String {
        tokenUsageByDay.values.max().map { TokenFormatting.display(Double($0)) } ?? "—"
    }

    /// 预警条文案；无需预警时为 nil。
    var alertText: String? {
        guard let snapshot else { return nil }
        switch snapshot.severity {
        case .danger:
            return "额度提醒: 本周额度即将耗尽"
        case .severe:
            return "额度提醒: 本周额度剩余不足，请放慢使用节奏"
        default:
            break
        }
        guard let elapsed = elapsedPercent, elapsed > 1, snapshot.usedPercent > 1 else {
            return nil
        }
        let windowDays = Double(snapshot.windowMinutes ?? 10_080) / 1440.0
        let elapsedDays = max(windowDays * elapsed / 100.0, 0.01)
        let ratePerDay = snapshot.usedPercent / elapsedDays
        let threshold = 90.0
        guard snapshot.usedPercent < threshold, ratePerDay > 0 else { return nil }
        let daysToThreshold = (threshold - snapshot.usedPercent) / ratePerDay
        let daysRemaining = windowDays - elapsedDays
        if daysToThreshold < daysRemaining {
            let days = max(1, Int(daysToThreshold.rounded()))
            return "额度提醒: 预计 \(days) 天后接近本周上限"
        }
        return nil
    }

    private static let weekdayClockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "E HH:mm"
        return formatter
    }()

    var emptyKind: EmptyKind? {
        if snapshot != nil { return nil }
        switch connectionState {
        case .missingCLI:
            return .missingCLI
        case .notLoggedIn:
            return .notLoggedIn
        case .unavailable:
            return .unavailable
        case .detecting, .connecting, .reading:
            return .loading
        case .connected, .offlineCached:
            return snapshot == nil ? .unavailable : nil
        }
    }

    func refresh() {
        Task { await service.refresh(forceReconnect: true) }
    }

    func rediscover() {
        Task { await service.rediscover() }
    }

    func setExecutable(_ url: URL) {
        Task { await service.setExecutableOverride(url.path) }
    }

    enum EmptyKind {
        case loading
        case missingCLI
        case notLoggedIn
        case unavailable
    }
}

enum TokenFormatting {
    static func display(_ value: Double) -> String {
        if value >= 100_000_000 {
            return Self.decimal(value / 100_000_000) + "亿"
        }
        if value >= 10_000 {
            return Self.decimal(value / 10_000) + "万"
        }
        return Self.integerFormatter.string(from: NSNumber(value: Int64(value.rounded()))) ?? "0"
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".0", with: "")
    }

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
