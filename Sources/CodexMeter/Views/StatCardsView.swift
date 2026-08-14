import SwiftUI
import CodexMeterCore

/// 原型图顶部的三张统计卡：今日消耗 / 本周消耗 / 剩余额度。
struct StatCardsView: View {
    let todayUsedText: String
    let weekUsedText: String
    let remainingText: String
    let paceTitle: String
    let updatedText: String
    let resetCountdownText: String?

    var body: some View {
        HStack(spacing: 10) {
            StatCard(
                icon: "chart.line.uptrend.xyaxis",
                tint: MeterTheme.blue,
                title: "今日消耗",
                value: todayUsedText,
                subtitle: updatedText
            )
            StatCard(
                icon: "calendar",
                tint: MeterTheme.purple,
                title: "本周消耗",
                value: weekUsedText,
                subtitle: "使用节奏\(paceTitle)"
            )
            StatCard(
                icon: "creditcard",
                tint: MeterTheme.green,
                title: "剩余额度",
                value: remainingText,
                subtitle: resetCountdownText ?? "刷新时间未知"
            )
        }
    }
}

private struct StatCard: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 19, height: 19)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 5.5, style: .continuous))
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .meterCard(padding: 11)
    }
}
