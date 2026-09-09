import Foundation

public struct CodexQuotaSnapshot: Equatable, Sendable, Codable {
    public var planType: String?
    public var usedPercent: Double
    public var remainingPercent: Double
    public var resetAt: Date?
    public var windowMinutes: Int?
    public var fetchedAt: Date
    public var limitId: String?
    public var accountType: String?
    public var fiveHourUsedPercent: Double?
    public var fiveHourRemainingPercent: Double?
    public var fiveHourResetAt: Date?

    public init(
        planType: String?,
        usedPercent: Double,
        remainingPercent: Double,
        resetAt: Date?,
        windowMinutes: Int?,
        fetchedAt: Date,
        limitId: String? = nil,
        accountType: String? = nil,
        fiveHourUsedPercent: Double? = nil,
        fiveHourRemainingPercent: Double? = nil,
        fiveHourResetAt: Date? = nil
    ) {
        self.planType = planType
        self.usedPercent = PercentageFormatting.clamped(usedPercent)
        self.remainingPercent = PercentageFormatting.clamped(remainingPercent)
        self.resetAt = resetAt
        self.windowMinutes = windowMinutes
        self.fetchedAt = fetchedAt
        self.limitId = limitId
        self.accountType = accountType
        self.fiveHourUsedPercent = fiveHourUsedPercent.map(PercentageFormatting.clamped)
        self.fiveHourRemainingPercent = fiveHourRemainingPercent.map(PercentageFormatting.clamped)
        self.fiveHourResetAt = fiveHourResetAt
    }

    public var severity: QuotaSeverity {
        QuotaSeverity.from(remainingPercent: remainingPercent)
    }

    public var windowKey: String {
        if let resetAt {
            return "reset-\(Int(resetAt.timeIntervalSince1970))"
        }
        return "unknown"
    }

    public var displayPlan: String? {
        guard let planType, !planType.isEmpty, planType.lowercased() != "unknown" else {
            return nil
        }
        return Self.prettyPlan(planType)
    }

    public static func prettyPlan(_ raw: String) -> String {
        switch raw.lowercased() {
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "prolite": return "Pro Lite"
        case "free": return "Free"
        case "go": return "Go"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        case "edu": return "Edu"
        default:
            return raw
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }
}

public struct QuotaHistoryPoint: Equatable, Sendable, Codable, Identifiable {
    public var timestamp: Date
    public var usedPercent: Double
    public var remainingPercent: Double
    public var resetAt: Date?

    public var id: Date { timestamp }

    public init(timestamp: Date, usedPercent: Double, remainingPercent: Double, resetAt: Date?) {
        self.timestamp = timestamp
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.resetAt = resetAt
    }

    public init(snapshot: CodexQuotaSnapshot) {
        self.init(
            timestamp: snapshot.fetchedAt,
            usedPercent: snapshot.usedPercent,
            remainingPercent: snapshot.remainingPercent,
            resetAt: snapshot.resetAt
        )
    }
}
