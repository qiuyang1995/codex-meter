import SwiftUI
import CodexMeterCore

struct UsagePaceView: View {
    let usedText: String
    let elapsedPercent: Double?
    let pace: UsagePace

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本周使用")
                .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 0) {
                metric("已使用", usedText)
                Divider().frame(height: 28)
                metric("本周已过去", elapsedPercent.map(PercentageFormatting.display) ?? "暂不可用")
                Divider().frame(height: 28)
                metric("使用节奏", pace.title)
            }

            if let hint = pace.hint {
                Text(hint)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}
