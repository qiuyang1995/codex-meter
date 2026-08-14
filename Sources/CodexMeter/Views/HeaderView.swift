import SwiftUI
import CodexMeterCore

struct HeaderView: View {
    let state: CodexConnectionState
    let severity: QuotaSeverity
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CodexMark(size: 40, severity: state == .connected ? severity : .normal)

            VStack(alignment: .leading, spacing: 3) {
                Text("Codex 额度监控")
                    .font(.system(size: 16, weight: .bold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(MeterTheme.statusDot(state, severity: severity))
                        .frame(width: 7, height: 7)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(MeterTheme.cardBackground, in: Circle())
                    .overlay(Circle().strokeBorder(MeterTheme.cardBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("设置")
        }
    }

    private var subtitle: String {
        switch state {
        case .connected:
            return "今日同步正常"
        default:
            return state.headerTitle
        }
    }
}
