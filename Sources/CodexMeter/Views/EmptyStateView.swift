import SwiftUI

struct EmptyStateView: View {
    let kind: QuotaViewModel.EmptyKind
    let onRetry: () -> Void
    let onChoosePath: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 52, height: 52)
                .background(.quaternary.opacity(0.5), in: Circle())

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("重新检测", action: onRetry)
                    .keyboardShortcut("r", modifiers: .command)
                if kind == .missingCLI {
                    Button("选择 Codex App", action: onChoosePath)
                }
            }
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 12)
    }

    private var icon: String {
        switch kind {
        case .loading: return "ellipsis.circle"
        case .missingCLI: return "shippingbox"
        case .notLoggedIn: return "person.crop.circle.badge.questionmark"
        case .unavailable: return "icloud.slash"
        }
    }

    private var title: String {
        switch kind {
        case .loading: return "正在准备"
        case .missingCLI: return "未检测到 Codex"
        case .notLoggedIn: return "Codex 尚未登录"
        case .unavailable: return "暂时无法获取额度"
        }
    }

    private var message: String {
        switch kind {
        case .loading:
            return "正在连接本机 Codex，并读取当前账户额度。"
        case .missingCLI:
            return "请安装并登录官方 Codex／ChatGPT App，\n或选择已安装的 App。也支持 Codex CLI。"
        case .notLoggedIn:
            return "请先在 Codex 中完成 ChatGPT 登录。"
        case .unavailable:
            return "无法从 Codex App Server 读取周额度。\n请稍后重试。"
        }
    }
}
