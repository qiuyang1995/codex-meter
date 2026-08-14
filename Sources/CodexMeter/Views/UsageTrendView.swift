import SwiftUI
import CodexMeterCore

struct UsageTrendView: View {
    let points: [QuotaHistoryPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近使用")
                .font(.system(size: 13, weight: .semibold))

            if points.count < 2 {
                Text("开始记录后，这里会显示额度变化趋势")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            } else {
                Sparkline(values: points.map(\.remainingPercent))
                    .frame(height: 56)
            }
        }
    }
}

struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            let clamped = values.map { PercentageFormatting.clamped($0) }
            let minY = 0.0
            let maxY = 100.0
            let points = clamped.enumerated().map { index, value -> CGPoint in
                let x = proxy.size.width * CGFloat(index) / CGFloat(max(clamped.count - 1, 1))
                let y = proxy.size.height * CGFloat(1 - (value - minY) / (maxY - minY))
                return CGPoint(x: x, y: y)
            }

            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(Color.purple.opacity(0.85), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

            if let last = points.last {
                Circle()
                    .fill(Color.purple)
                    .frame(width: 6, height: 6)
                    .position(last)
            }
        }
        .padding(.vertical, 2)
        .accessibilityLabel("周额度剩余趋势")
    }
}
