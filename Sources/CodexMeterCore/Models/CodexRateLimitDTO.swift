import Foundation

/// Loose DTO that mirrors Codex App Server rate-limit payloads without binding UI to schema details.
public struct CodexRateLimitWindowDTO: Equatable, Sendable {
    public var usedPercent: Double?
    public var remainingPercent: Double?
    public var windowMinutes: Int?
    public var resetsAt: Date?
}

public struct CodexRateLimitBucketDTO: Equatable, Sendable {
    public var limitId: String?
    public var limitName: String?
    public var planType: String?
    public var windows: [CodexRateLimitWindowDTO]
}

public struct CodexRateLimitDTO: Equatable, Sendable {
    public var planType: String?
    public var buckets: [CodexRateLimitBucketDTO]
    public var windows: [CodexRateLimitWindowDTO]
}
