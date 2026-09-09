import SwiftUI

struct StatCardsView: View {
    let todayTitle: String
    let todayTokenText: String?
    let weekTokenText: String?

    var body: some View {
        HStack(spacing: 10) {
            metric(todayTitle, value: todayTokenText, icon: "chart.bar.xaxis", color: MeterTheme.blue)
                .help(todayTitle.contains("实时") ? "本机 Codex 日志，每 5 秒检查。模型返回并写入日志后计入；不含其他设备或云端任务。" : "Codex 返回的每日用量可能有延迟")
            Divider().frame(height: 36)
            metric("本周消耗", value: weekTokenText, icon: "calendar", color: MeterTheme.accent)
        }
        .meterCard(padding: 9)
    }

    private func metric(_ title: String, value: String?, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.system(size: 11.0, weight: .medium))
                .foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value ?? "—").font(.system(size: 20.9, weight: .semibold, design: .rounded))
                Text("Tokens").font(.system(size: 9.4)).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
