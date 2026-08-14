#if DEBUG
import Foundation
import CodexMeterCore

enum PreviewSnapshots {
    static func make(
        remaining: Double,
        used: Double? = nil,
        resetAt: Date? = Date().addingTimeInterval(4 * 24 * 3600 + 21 * 3600),
        fetchedAt: Date = Date()
    ) -> CodexQuotaSnapshot {
        let usedPercent = used ?? (100 - remaining)
        return CodexQuotaSnapshot(
            planType: "plus",
            usedPercent: usedPercent,
            remainingPercent: remaining,
            resetAt: resetAt,
            windowMinutes: 10_080,
            fetchedAt: fetchedAt,
            limitId: "codex",
            accountType: "chatgpt"
        )
    }
}
#endif
