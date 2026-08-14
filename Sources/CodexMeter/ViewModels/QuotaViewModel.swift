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
