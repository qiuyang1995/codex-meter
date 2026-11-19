import SwiftUI
import CodexMeterCore

struct StatCardsView: View {
    let todayTitle: String
    let todayTokenText: String?
    let weekTokenText: String?

    var body: some View {
        HStack(spacing: 10) {
            metric(todayTitle, value: todayTokenText, icon: "chart.bar.xaxis", color: MeterTheme.blue)
                .help(todayTitle.contains("实时") ? "本机 Codex 日志写入后更新，仅统计本机记录。" : "Codex 返回的每日用量可能有延迟")
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

struct TokenRateCardView: View {
    let speeds: [OutputTokenSpeed]
    private var latest: OutputTokenSpeed? { speeds.last }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text("输出 Token 速度")
                } icon: {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(MeterTheme.accent)
                }
                .font(.system(size: 11, weight: .semibold))
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(latest.map { speedText($0) } ?? "—")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("Tokens/s").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Text("最近一次输出")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .frame(width: 128, alignment: .leading)
            .accessibilityElement(children: .combine)

            Divider().frame(height: 47)

            VStack(spacing: 3) {
                sparkline.frame(height: 25)
                Text(speeds.isEmpty ? "输出历史" : "最近 \(speeds.count) 次").font(.system(size: 10))
                Text(latest.map { "完成 \(timeText($0.completedAt))" } ?? "暂无可测量的输出")
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
        .meterCard(padding: 9)
    }

    private func speedText(_ measurement: OutputTokenSpeed) -> String {
        measurement.tokensPerSecond.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.twoDigits).day(.twoDigits)
            .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)
            .locale(Locale(identifier: "zh_CN")))
    }

    private var sparkline: some View {
        let peak = speeds.lazy.map(\.tokensPerSecond).max() ?? 1
        return GeometryReader { geometry in
            let width = max(1, geometry.size.width / 30 - 1.5)
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(speeds, id: \.responseID) { measurement in
                    let details = "\(timeText(measurement.completedAt)) · \(speedText(measurement)) Tokens/s"
                    Rectangle()
                        .fill(MeterTheme.purple.opacity(0.7))
                        .frame(width: width, height: max(1, 25 * CGFloat(measurement.tokensPerSecond / peak)))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .help(details)
                        .accessibilityLabel(details)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
