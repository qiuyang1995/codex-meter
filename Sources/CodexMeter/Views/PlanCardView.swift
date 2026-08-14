import SwiftUI
import CodexMeterCore

/// 原型图中间的套餐卡：套餐名、本周使用进度条、刷新周期说明。
struct PlanCardView: View {
    let planName: String
    let usedPercent: Double
    let usedText: String
    let usedBadgeText: String
    let severity: QuotaSeverity
    let refreshScheduleText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(planName)
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                (Text("本周额度使用 ")
                    .foregroundColor(.secondary)
                 + Text(usedBadgeText)
                    .foregroundColor(MeterTheme.emphasis(severity))
                    .fontWeight(.bold))
                    .font(.system(size: 12.5))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(MeterTheme.track)
                    Capsule()
                        .fill(severity == .normal || severity == .unknown
                              ? AnyShapeStyle(MeterTheme.accentGradient)
                              : AnyShapeStyle(MeterTheme.emphasis(severity).gradient))
                        .frame(width: max(8, proxy.size.width * CGFloat(PercentageFormatting.clamped(usedPercent) / 100)))
                        .animation(.easeInOut(duration: 0.28), value: usedPercent)
                }
            }
            .frame(height: 8)

            HStack {
                (Text("已使用  ").foregroundColor(.secondary)
                 + Text(usedText).fontWeight(.semibold))
                    .font(.system(size: 12.5))
                Spacer()
                (Text("每周总额度 ").foregroundColor(.secondary)
                 + Text("100%").fontWeight(.semibold))
                    .font(.system(size: 12.5))
            }

            Divider()

            HStack(spacing: 7) {
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(refreshScheduleText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .meterCard(padding: 14)
    }
}
