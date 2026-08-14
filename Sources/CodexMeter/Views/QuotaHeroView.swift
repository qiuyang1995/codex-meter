import SwiftUI
import CodexMeterCore

struct QuotaHeroView: View {
    let remainingText: String
    let remainingValue: Double
    let usedValue: Double
    let severity: QuotaSeverity
    let resetDateText: String
    let resetCountdownText: String?

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 2) {
                Text(remainingText)
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .foregroundStyle(MeterTheme.emphasis(severity))
                    .animation(.easeInOut(duration: 0.25), value: remainingText)
                Text("本周剩余")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            QuotaProgressView(remaining: remainingValue, used: usedValue, severity: severity)

            VStack(alignment: .leading, spacing: 4) {
                Text("下次刷新")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Text(resetDateText)
                    .font(.system(size: 14, weight: .semibold))
                if let resetCountdownText {
                    Text(resetCountdownText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: MeterTheme.cardRadius, style: .continuous))
    }
}
