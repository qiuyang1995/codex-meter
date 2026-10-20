import Foundation

public struct PersistedQuotaState: Codable, Equatable, Sendable {
    public var accountId: String?
    public var lastSnapshot: CodexQuotaSnapshot?
    public var history: [QuotaHistoryPoint]
    public var lastSuccessfulRefresh: Date?
    public var notificationState: NotificationState

    public init(
        accountId: String? = nil,
        lastSnapshot: CodexQuotaSnapshot? = nil,
        history: [QuotaHistoryPoint] = [],
        lastSuccessfulRefresh: Date? = nil,
        notificationState: NotificationState = NotificationState()
    ) {
        self.accountId = accountId
        self.lastSnapshot = lastSnapshot
        self.history = history
        self.lastSuccessfulRefresh = lastSuccessfulRefresh
        self.notificationState = notificationState
    }
}

public final class HistoryStore: @unchecked Sendable {
    public static let shared = HistoryStore()

    public let minimumSampleInterval: TimeInterval
    public let retention: TimeInterval
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()

    public init(
        fileURL: URL? = nil,
        minimumSampleInterval: TimeInterval = 15 * 60,
        retention: TimeInterval = 30 * 24 * 60 * 60
    ) {
        self.minimumSampleInterval = minimumSampleInterval
        self.retention = retention
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let fileURL {
            self.fileURL = fileURL
        } else {
            let root = HistoryStore.applicationSupportDirectory()
            self.fileURL = root.appendingPathComponent("quota-state.json")
        }
    }

    public func load() -> PersistedQuotaState {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return PersistedQuotaState()
        }
        do {
            let data = try Data(contentsOf: fileURL)
            var state = try decoder.decode(PersistedQuotaState.self, from: data)
            state.history = pruned(state.history, now: Date())
            return state
        } catch {
            AppLog.storage.error("Failed to load quota cache: \(error.localizedDescription, privacy: .public)")
            return PersistedQuotaState()
        }
    }

    @discardableResult
    public func record(snapshot: CodexQuotaSnapshot, previous: PersistedQuotaState) -> PersistedQuotaState {
        var next = previous
        next.lastSnapshot = snapshot
        next.lastSuccessfulRefresh = snapshot.fetchedAt

        let shouldAppend: Bool
        if let last = next.history.last {
            shouldAppend = snapshot.fetchedAt.timeIntervalSince(last.timestamp) >= minimumSampleInterval
        } else {
            shouldAppend = true
        }
        if shouldAppend {
            next.history.append(QuotaHistoryPoint(snapshot: snapshot))
        }
        next.history = pruned(next.history, now: snapshot.fetchedAt)
        save(next)
        return next
    }

    public func saveNotificationState(_ notificationState: NotificationState, previous: PersistedQuotaState) -> PersistedQuotaState {
        var next = previous
        next.notificationState = notificationState
        save(next)
        return next
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL)
    }

    public func save(_ state: PersistedQuotaState) {
        lock.lock()
        defer { lock.unlock() }
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            AppLog.storage.error("Failed to save quota cache: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func pruned(_ history: [QuotaHistoryPoint], now: Date) -> [QuotaHistoryPoint] {
        let cutoff = now.addingTimeInterval(-retention)
        return history.filter { $0.timestamp >= cutoff }
    }

    public static func applicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("com.local.CodexMeter", isDirectory: true)
    }
}
