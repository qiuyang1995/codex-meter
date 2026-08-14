import SwiftUI
import CodexMeterCore

struct QuotaProgressView: View {
    let remaining: Double
    let used: Double
    let severity: QuotaSeverity

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(MeterTheme.emphasis(severity).gradient)
                        .frame(width: max(6, proxy.size.width * CGFloat(PercentageFormatting.clamped(remaining) / 100)))
                        .animation(.easeInOut(duration: 0.28), value: remaining)
                }
            }
            .frame(height: 8)

            HStack {
                Text("已使用 \(PercentageFormatting.display(used))")
                Spacer()
                Text("剩余 \(PercentageFormatting.display(remaining))")
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
        }
    }
}
