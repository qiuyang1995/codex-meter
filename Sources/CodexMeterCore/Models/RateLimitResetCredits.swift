import Foundation

public struct RateLimitResetCredit: Equatable, Sendable, Identifiable {
    public let id: String
    public let resetType: String
    public let status: String
    public let expiresAt: Date?
    public let title: String?

    public init(id: String, resetType: String, status: String, expiresAt: Date?, title: String? = nil) {
        self.id = id
        self.resetType = resetType
        self.status = status
        self.expiresAt = expiresAt
        self.title = title
    }

    public var displayTitle: String {
        resetType == "codexRateLimits" ? "完全重置（每周 + 5 小时）" : (title ?? "额度重置")
    }
}

public struct RateLimitResetCredits: Equatable, Sendable {
    public let availableCount: Int
    // nil means the server returned the count without detail rows.
    public let credits: [RateLimitResetCredit]?

    public init(availableCount: Int, credits: [RateLimitResetCredit]?) {
        self.availableCount = max(availableCount, 0)
        self.credits = credits
    }

    public func availableCredits(at now: Date) -> [RateLimitResetCredit] {
        (credits ?? []).filter { $0.status == "available" && ($0.expiresAt.map { $0 > now } ?? true) }
            .sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
    }

    public func availableCount(at now: Date) -> Int {
        let expired = (credits ?? []).filter { $0.status == "available" && ($0.expiresAt.map { $0 <= now } ?? false) }.count
        return max(0, availableCount - expired)
    }
}
