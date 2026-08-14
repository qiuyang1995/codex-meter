import SwiftUI

/// 原型图中的琥珀色额度预警条。
struct AlertBannerView: View {
    let text: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(MeterTheme.warningIcon)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MeterTheme.warningForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MeterTheme.warningForeground.opacity(0.55))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(
            MeterTheme.warningBackground,
            in: RoundedRectangle(cornerRadius: MeterTheme.cardRadius, style: .continuous)
        )
    }
}
