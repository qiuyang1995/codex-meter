import Foundation

public enum QuotaSeverity: String, Equatable, Sendable {
    case normal
    case warning
    case severe
    case danger
    case unknown

    public static func from(remainingPercent: Double?) -> QuotaSeverity {
        guard let remainingPercent else { return .unknown }
        if remainingPercent > 30 { return .normal }
        if remainingPercent > 15 { return .warning }
        if remainingPercent > 5 { return .severe }
        return .danger
    }
}
