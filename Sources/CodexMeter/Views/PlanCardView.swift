import SwiftUI
import CodexMeterCore

struct PlanCardView: View {
    @ObservedObject var viewModel: QuotaViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.planName).font(.system(size: 13.2, weight: .semibold))
            if let remaining = viewModel.snapshot?.fiveHourRemainingPercent {
                quotaRow("5 小时剩余", icon: "clock", remaining: remaining,
                         reset: viewModel.fiveHourResetText ?? "重置时间未知")
            }
            quotaRow("本周剩余", icon: "calendar", remaining: viewModel.remainingValue,
                     reset: viewModel.weeklyResetText)
        }
    }

    private func quotaRow(_ title: String, icon: String, remaining: Double, reset: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.system(size: 11.0, weight: .medium))
                    .frame(width: 78, alignment: .leading)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(MeterTheme.track)
                        Capsule().fill(MeterTheme.accentGradient)
                            .frame(width: geometry.size.width * CGFloat(PercentageFormatting.clamped(remaining) / 100))
                    }
                }.frame(height: 5)
                Text(PercentageFormatting.display(remaining))
                    .font(.system(size: 12.1, weight: .semibold, design: .rounded))
                    .foregroundStyle(MeterTheme.accent)
                    .frame(width: 36, alignment: .trailing)
            }
            Text(reset).font(.system(size: 9.9)).foregroundStyle(.secondary)
                .padding(.leading, 18)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
