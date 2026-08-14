import Foundation

public enum CodexConnectionState: Equatable, Sendable {
    case detecting
    case connecting
    case reading
    case connected
    case missingCLI
    case notLoggedIn
    case offlineCached
    case unavailable

    public var headerTitle: String {
        switch self {
        case .detecting:
            return "正在检测 Codex…"
        case .connecting:
            return "正在连接 Codex…"
        case .reading:
            return "正在读取额度…"
        case .connected:
            return "已连接"
        case .missingCLI:
            return "无法获取额度"
        case .notLoggedIn:
            return "无法获取额度"
        case .offlineCached:
            return "离线 · 显示上次数据"
        case .unavailable:
            return "无法获取额度"
        }
    }

    public var isErrorLike: Bool {
        switch self {
        case .missingCLI, .notLoggedIn, .unavailable, .offlineCached:
            return true
        default:
            return false
        }
    }
}
