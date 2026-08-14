import Foundation

public enum CodexClientError: Error, Equatable, LocalizedError {
    case executableNotFound
    case notConnected
    case processExited(Int32)
    case timeout(String)
    case rpc(code: Int, message: String)
    case invalidResponse
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "未检测到 Codex CLI"
        case .notConnected:
            return "尚未连接到 Codex"
        case .processExited(let code):
            return "Codex App Server 已退出（\(code)）"
        case .timeout(let method):
            return "请求超时：\(method)"
        case .rpc(_, let message):
            return message
        case .invalidResponse:
            return "无法解析 Codex 响应"
        case .cancelled:
            return "已取消"
        }
    }

    public var isUnauthorized: Bool {
        switch self {
        case .rpc(let code, let message):
            let lowered = message.lowercased()
            return code == 401
                || lowered.contains("unauthorized")
                || lowered.contains("not logged")
                || lowered.contains("login")
        default:
            return false
        }
    }
}

public enum CodexQuotaError: Error, Equatable, LocalizedError {
    case weeklyLimitMissing
    case parseFailed

    public var errorDescription: String? {
        switch self {
        case .weeklyLimitMissing:
            return "未找到周额度"
        case .parseFailed:
            return "额度数据无法解析"
        }
    }
}
