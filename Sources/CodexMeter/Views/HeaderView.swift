import SwiftUI
import CodexMeterCore

struct HeaderView: View {
    let state: CodexConnectionState
    let severity: QuotaSeverity
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            CodexMark(size: 34, severity: state == .connected ? severity : .normal)

            VStack(alignment: .leading, spacing: 3) {
                Text("Codex Meter")
                    .font(.system(size: 15.4, weight: .semibold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(MeterTheme.statusDot(state, severity: severity))
                        .frame(width: 5, height: 5)
                    Text(subtitle)
                        .font(.system(size: 9.9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12.1, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 25, height: 25)
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
            return "已连接 · 同步正常"
        default:
            return state.headerTitle
        }
    }
}
