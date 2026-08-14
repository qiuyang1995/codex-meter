import Foundation

public enum UsagePace: String, Equatable, Sendable {
    case normal
    case slightlyFast
    case tooFast
    case unknown

    public var title: String {
        switch self {
        case .normal: return "正常"
        case .slightlyFast: return "略快"
        case .tooFast: return "偏快"
        case .unknown: return "暂不可用"
        }
    }

    public var hint: String? {
        switch self {
        case .normal:
            return nil
        case .slightlyFast:
            return "消耗略快于时间进度"
        case .tooFast:
            return "按照当前速度，本周额度可能提前耗尽"
        case .unknown:
            return nil
        }
    }

    /// Compare weekly usage against elapsed window time.
    /// - Parameters:
    ///   - usedPercent: 0...100
    ///   - elapsedPercent: 0...100 of the current weekly window
    public static func evaluate(usedPercent: Double, elapsedPercent: Double) -> UsagePace {
        let used = PercentageFormatting.clamped(usedPercent)
        let elapsed = PercentageFormatting.clamped(elapsedPercent)
        let delta = used - elapsed
        if delta <= 10 { return .normal }
        if delta <= 25 { return .slightlyFast }
        return .tooFast
    }

    public static func elapsedPercent(
        resetAt: Date?,
        windowMinutes: Int?,
        now: Date = Date()
    ) -> Double? {
        guard let resetAt, let windowMinutes, windowMinutes > 0 else {
            return nil
        }
        let windowSeconds = TimeInterval(windowMinutes * 60)
        let start = resetAt.addingTimeInterval(-windowSeconds)
        let elapsed = now.timeIntervalSince(start)
        return PercentageFormatting.clamped((elapsed / windowSeconds) * 100)
    }
}
