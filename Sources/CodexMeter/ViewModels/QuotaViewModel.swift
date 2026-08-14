import Combine
import Foundation
import SwiftUI
import CodexMeterCore

@MainActor
final class QuotaViewModel: ObservableObject {
    let service: CodexQuotaService
    let settings: AppSettings

    @Published private(set) var tick = Date()

    private var cancellables = Set<AnyCancellable>()
    private var timer: AnyCancellable?

    init(service: CodexQuotaService, settings: AppSettings) {
        self.service = service
        self.settings = settings

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

    var remainingText: String {
        guard let snapshot else { return "—" }
        return PercentageFormatting.display(snapshot.remainingPercent)
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

    /// 今日消耗：当前已用减去今天 0 点前最后一个采样点。
    var todayUsedPercent: Double? {
        guard let snapshot else { return nil }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: tick)
        let baseline = history.last(where: { $0.timestamp < startOfDay })
            ?? history.first(where: { $0.timestamp >= startOfDay })
        guard let baseline else { return nil }
        let delta = snapshot.usedPercent - baseline.usedPercent
        // 周期在今天内发生了重置时，本周期已用即今日消耗
        return delta < 0 ? snapshot.usedPercent : delta
    }

    var todayUsedText: String {
        guard let value = todayUsedPercent else { return "—" }
        return PercentageFormatting.display(value)
    }

    var refreshScheduleText: String {
        guard let resetAt = snapshot?.resetAt else {
            return "每周刷新一次 · 下次刷新时间未知"
        }
        return "每周刷新一次 · 下次刷新: \(Self.weekdayClockFormatter.string(from: resetAt))"
    }

    /// 近 7 天每日用量（取每天最后一个采样点的已用百分比）。
    var dailyUsage: [DailyUsagePoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: tick)
        var result: [DailyUsagePoint] = []
        for offset in -6...0 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            var value = history
                .last(where: { $0.timestamp >= day && $0.timestamp < nextDay })?
                .usedPercent
            if offset == 0, let snapshot {
                value = snapshot.usedPercent
            }
            if let value {
                result.append(DailyUsagePoint(
                    day: day,
                    label: Self.dayLabelFormatter.string(from: day),
                    value: value
                ))
            }
        }
        return result
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

    private static let dayLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
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

struct DailyUsagePoint: Identifiable, Equatable {
    let day: Date
    let label: String
    let value: Double

    var id: Date { day }
}
