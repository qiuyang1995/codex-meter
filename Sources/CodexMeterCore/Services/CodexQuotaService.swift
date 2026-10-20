import Foundation
import Combine
import UserNotifications

@MainActor
public final class CodexQuotaService: ObservableObject {
    @Published public private(set) var connectionState: CodexConnectionState = .detecting
    @Published public private(set) var snapshot: CodexQuotaSnapshot?
    @Published public private(set) var history: [QuotaHistoryPoint] = []
    @Published public private(set) var lastSuccessfulRefresh: Date?
    @Published public private(set) var lastErrorMessage: String?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var executableURL: URL?
    @Published public private(set) var accountId: String?
    @Published public private(set) var planType: String?
    @Published public private(set) var dailyTokenUsage: [AccountTokenUsageDailyBucket] = []

    @Published public private(set) var localTodayUsage: LocalTodayTokenUsage?
    private let localUsageTracker = LocalTokenUsageTracker()
    private var localUsageTask: Task<Void, Never>?

    @Published public private(set) var resetCredits: RateLimitResetCredits?
    @Published public private(set) var lifetimeTokens: Int64?

    public let settings: AppSettings
    public let locator: CodexExecutableLocator
    public let client: CodexAppServerClient
    public let store: HistoryStore
    public let notifications: NotificationService

    private var persist = PersistedQuotaState()
    private var cycleDetector = CycleDetector()
    private var pollTask: Task<Void, Never>?
    private var notificationListenTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var settingsCancellable: AnyCancellable?
    private var stopped = false
    private let reconnectDelays: [TimeInterval] = [1, 2, 5, 10, 30]

    public init(
        settings: AppSettings,
        locator: CodexExecutableLocator = CodexExecutableLocator(),
        client: CodexAppServerClient = CodexAppServerClient(),
        store: HistoryStore = .shared,
        notifications: NotificationService
    ) {
        self.settings = settings
        self.locator = locator
        self.client = client
        self.store = store
        self.notifications = notifications
        settingsCancellable = settings.$refreshInterval
            .dropFirst()
            .sink { [weak self] _ in
                self?.restartPolling()
            }
    }

#if DEBUG
    /// 仅供预览 / 截图渲染注入模拟状态，不触发任何网络或子进程。
    public func injectPreviewState(
        snapshot: CodexQuotaSnapshot?,
        history: [QuotaHistoryPoint],
        dailyTokenUsage: [AccountTokenUsageDailyBucket] = [],
        localTodayUsage: LocalTodayTokenUsage? = nil,
        resetCredits: RateLimitResetCredits? = nil,
        connectionState: CodexConnectionState,
        lastSuccessfulRefresh: Date?
    ) {
        self.snapshot = snapshot
        self.history = history
        self.dailyTokenUsage = dailyTokenUsage
        self.localTodayUsage = localTodayUsage
        self.resetCredits = resetCredits
        self.connectionState = connectionState
        self.lastSuccessfulRefresh = lastSuccessfulRefresh
        self.accountId = nil
        self.planType = snapshot?.planType
    }
#endif

    public func start() {
        stopped = false
        persist = store.load()
        accountId = persist.accountId
        snapshot = persist.lastSnapshot
        history = persist.history
        lastSuccessfulRefresh = persist.lastSuccessfulRefresh
        if let last = persist.lastSnapshot {
            cycleDetector.lastConfirmed = last
        }
        Task { await refresh() }
        restartPolling()
        localUsageTask?.cancel()
        localUsageTask = Task { [weak self, localUsageTracker] in
            while !Task.isCancelled {
                let usage = await localUsageTracker.sample()
                guard let self, !self.stopped, !Task.isCancelled else { return }
                if self.localTodayUsage != usage { self.localTodayUsage = usage }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    public func shutdown() async {
        stopped = true
        pollTask?.cancel()
        localUsageTask?.cancel()
        reconnectTask?.cancel()
        notificationListenTask?.cancel()
        refreshTask?.cancel()
        await client.stop()
    }

    public func refresh(forceReconnect: Bool = false) async {
        if let refreshTask {
            await refreshTask.value
            if forceReconnect == false {
                return
            }
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh(forceReconnect: forceReconnect)
        }
        refreshTask = task
        await task.value
        if refreshTask == task {
            refreshTask = nil
        }
    }

    public func rediscover() async {
        settings.cachedExecutable = nil
        await bootstrap(forceLocate: true)
    }

    public func setExecutableOverride(_ path: String?) async {
        settings.executableOverride = path
        settings.cachedExecutable = path
        await bootstrap(forceLocate: true)
    }

    private func bootstrap(forceLocate: Bool) async {
        guard stopped == false else { return }
        resetCredits = nil
        connectionState = .detecting
        lastErrorMessage = nil

        let found = locator.resolve(
            override: settings.executableOverride,
            cached: forceLocate ? nil : settings.cachedExecutable
        )
        executableURL = found
        guard let found else {
            connectionState = .missingCLI
            lastErrorMessage = "未检测到 Codex"
            return
        }
        settings.cachedExecutable = found.path
        reconnectAttempt = 0
        await connectAndRead(executable: found, forceRestart: forceLocate)
    }

    private func performRefresh(forceReconnect: Bool) async {
        guard stopped == false else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let running = await client.running()
        if forceReconnect || running == false {
            reconnectAttempt = 0
            reconnectTask?.cancel()
            if let executableURL {
                await connectAndRead(executable: executableURL, forceRestart: forceReconnect)
            } else {
                await bootstrap(forceLocate: false)
            }
            return
        }

        connectionState = snapshot == nil ? .reading : connectionState
        await readAccountAndLimits()
    }

    private func connectAndRead(executable: URL, forceRestart: Bool = false) async {
        guard stopped == false else { return }
        notificationListenTask?.cancel()
        connectionState = .connecting
        do {
            _ = try await client.start(executable: executable, forceRestart: forceRestart)
            listenForNotifications()
            reconnectAttempt = 0
            connectionState = .reading
            await readAccountAndLimits()
        } catch {
            handleFailure(error)
            scheduleReconnect()
        }
    }

    private func readAccountAndLimits() async {
        do {
            var planHint: String?
            var accountType: String?
            var accountData: Data?

            do {
                let account = try await client.request(method: "account/read", params: ["refreshToken": true], timeout: 20)
                accountData = account
                let decoded = CodexQuotaParser.decodeAccount(account)
                planHint = decoded.planType
                accountType = decoded.accountType
            } catch {
                // Account metadata can be unavailable while the quota read is authenticated.
                // Only a failure from the quota endpoint should block quota display.
                guard !stopped, !Task.isCancelled else { return }
                AppLog.quota.debug("Account metadata unavailable; continuing quota read")
            }

            // Some Codex builds return account: null even while rate limits are readable.
            // Read rate limits first; it carries the authoritative accountId.
            let result = try await client.request(method: "account/rateLimits/read", timeout: 30)
            guard !stopped, !Task.isCancelled else { return }
            if let newAccountId = CodexQuotaParser.preferredAccountId(accountData: accountData, rateLimitsData: result), newAccountId != accountId {
                if accountId != nil || persist.lastSnapshot != nil || !persist.history.isEmpty {
                    await handleAccountSwitch(to: newAccountId)
                    return
                }
                accountId = newAccountId
                persist.accountId = newAccountId
                store.save(persist)
            }
            try applyRateLimitResult(result, planHint: planHint, accountType: accountType)
            await readTokenUsage()
            guard !stopped, !Task.isCancelled else { return }
            connectionState = .connected
            lastErrorMessage = nil
            planType = snapshot?.planType ?? planHint
        } catch {
            handleFailure(error)
            if isProcessError(error) {
                scheduleReconnect()
            }
        }
    }

    private func readTokenUsage() async {
        do {
            let result = try await client.request(method: "account/usage/read", timeout: 30)
            guard !stopped, !Task.isCancelled else { return }
            let buckets = try CodexQuotaParser.parseTokenUsage(data: result)
            let total = try CodexQuotaParser.parseLifetimeTokens(data: result)
            dailyTokenUsage = buckets
            lifetimeTokens = total
        } catch {
            // Token usage is additive; older Codex versions may not expose this method.
            AppLog.quota.debug("Token usage unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func applyRateLimitResult(_ result: Data, planHint: String?, accountType: String?) throws {
        let parsed = try CodexQuotaParser.parseRateLimits(
            data: result,
            fetchedAt: Date(),
            planTypeHint: planHint,
            accountType: accountType
        )
        resetCredits = try CodexQuotaParser.parseResetCredits(data: result)
        applySnapshot(parsed)
    }

    private func applySnapshot(_ parsed: CodexQuotaSnapshot) {
        let reset = cycleDetector.observe(parsed)
        snapshot = parsed
        persist = store.record(snapshot: parsed, previous: persist)
        history = persist.history
        lastSuccessfulRefresh = parsed.fetchedAt
        planType = parsed.planType
        deliverNotifications(for: parsed, cycleDidReset: reset)
        AppLog.quota.info("Weekly remaining \(parsed.remainingPercent, format: .fixed(precision: 1))%")
    }

    private func deliverNotifications(for snapshot: CodexQuotaSnapshot, cycleDidReset: Bool) {
        let decision = NotificationPolicy.evaluate(
            snapshot: snapshot,
            previous: persist.notificationState,
            notificationsEnabled: settings.notificationsEnabled,
            notifyOnRefresh: settings.notifyOnRefresh,
            thresholds: settings.warningThresholds,
            cycleDidReset: cycleDidReset
        )
        persist = store.saveNotificationState(decision.nextState, previous: persist)
        // Permission is requested from Settings, never on first launch.
        guard settings.notificationsEnabled, decision.notifications.isEmpty == false else { return }
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }
            for event in decision.notifications {
                await notifications.deliver(event)
            }
        }
    }

    private func listenForNotifications() {
        notificationListenTask?.cancel()
        notificationListenTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.client.notifications()
            for await notification in stream {
                if Task.isCancelled { break }
                await self.handleServerNotification(notification)
            }
        }
    }

    private func handleServerNotification(_ notification: JSONRPCNotification) async {
        switch notification.method {
        case "account/rateLimits/updated":
            if let data = notification.paramsJSON,
               let parsed = try? CodexQuotaParser.parseRateLimits(data: data, fetchedAt: Date(), planTypeHint: planType) {
                applySnapshot(parsed)
                connectionState = .connected
                return
            }
            await refresh()
        case "account/updated":
            resetCredits = nil
            await refresh()
        case "internal/processExited":
            handleFailure(CodexClientError.processExited(-1))
            scheduleReconnect()
        default:
            break
        }
    }

    private func handleAccountSwitch(to newAccountId: String) async {
        AppLog.quota.info("Codex account changed; clearing previous account state")
        notificationListenTask?.cancel()
        reconnectTask?.cancel()
        persist = PersistedQuotaState(accountId: newAccountId)
        accountId = newAccountId
        snapshot = nil
        history = []
        dailyTokenUsage = []
        localTodayUsage = nil
        lifetimeTokens = nil
        resetCredits = nil
        planType = nil
        lastSuccessfulRefresh = nil
        cycleDetector = CycleDetector()
        store.clear()
        store.save(persist)
        await client.stop()
        await localUsageTracker.reset()
        guard let executable = executableURL ?? CodexExecutableLocator().resolve() else {
            connectionState = .missingCLI
            return
        }
        await connectAndRead(executable: executable)
    }

    private func applyNotLoggedIn() {
        resetCredits = nil
        lastErrorMessage = "Codex 尚未登录"
        connectionState = snapshot == nil ? .notLoggedIn : .offlineCached
    }

    private func handleFailure(_ error: Error) {
        resetCredits = nil
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        lastErrorMessage = message
        AppLog.quota.error("Quota update failed: \(message, privacy: .public)")

        if let clientError = error as? CodexClientError, clientError.isUnauthorized {
            applyNotLoggedIn()
            return
        }
        if connectionState == .missingCLI {
            return
        }
        if snapshot != nil {
            connectionState = .offlineCached
        } else {
            connectionState = .unavailable
        }
    }

    private func isProcessError(_ error: Error) -> Bool {
        if case .processExited = error as? CodexClientError { return true }
        if case .notConnected = error as? CodexClientError { return true }
        return false
    }

    private func scheduleReconnect() {
        guard stopped == false else { return }
        reconnectTask?.cancel()
        let delay = reconnectDelays[min(reconnectAttempt, reconnectDelays.count - 1)]
        reconnectAttempt += 1
        AppLog.codex.info("Reconnecting in \(delay, format: .fixed(precision: 0))s")
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.stopped == false, !Task.isCancelled else { return }
            if let executable = self.executableURL {
                await self.connectAndRead(executable: executable)
            } else {
                await self.bootstrap(forceLocate: true)
            }
        }
    }

    private func restartPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while let self, self.stopped == false {
                let interval = self.settings.refreshInterval.timeInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }
                await self.refresh(forceReconnect: false)
            }
        }
    }
}
