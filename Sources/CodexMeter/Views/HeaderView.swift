import SwiftUI
import CodexMeterCore

struct HeaderView: View {
    let state: CodexConnectionState
    let severity: QuotaSeverity
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            CodexMark(size: 30, severity: state == .connected ? severity : .normal)

            VStack(alignment: .leading, spacing: 2) {
                Text("Codex")
                    .font(.system(size: 16, weight: .semibold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(MeterTheme.statusDot(state, severity: severity))
                        .frame(width: 6, height: 6)
                    Text(state.headerTitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(.quaternary.opacity(0.6), in: Circle())
            }
            .buttonStyle(.plain)
            .help("设置")
        }
    }
}
