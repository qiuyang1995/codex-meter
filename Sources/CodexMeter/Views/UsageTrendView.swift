import SwiftUI
import CodexMeterCore

/// 原型图下方的"近 7 天用量"折线图卡片。
struct UsageTrendView: View {
    let points: [DailyUsagePoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("近 7 天用量")
                    .font(.system(size: 13.5, weight: .bold))
                Spacer()
                Text("单位: 额度 %")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if points.count >= 2 {
                DailyUsageChart(points: points)
                    .frame(height: 118)
            } else {
                Text("开始记录后，这里会显示近 7 天的每日用量趋势")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
                    .multilineTextAlignment(.center)
            }
        }
        .meterCard(padding: 14)
        .accessibilityLabel("近 7 天每日用量趋势")
    }
}

private struct DailyUsageChart: View {
    let points: [DailyUsagePoint]

    private let yLabelWidth: CGFloat = 24
    private let xLabelHeight: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let chartLeft = yLabelWidth + 6
            let chartWidth = proxy.size.width - chartLeft - 6
            let chartHeight = proxy.size.height - xLabelHeight
            let yMax = yAxisMax
            let gridValues = Array(stride(from: 0.0, through: yMax, by: 25.0))
            let coords = points.enumerated().map { index, point -> CGPoint in
                let x = chartLeft + chartWidth * CGFloat(index) / CGFloat(max(points.count - 1, 1))
                let y = chartHeight * CGFloat(1 - point.value / yMax)
                return CGPoint(x: x, y: y)
            }

            // 网格线与 Y 轴标签
            ForEach(gridValues, id: \.self) { value in
                let y = chartHeight * CGFloat(1 - value / yMax)
                Path { path in
                    path.move(to: CGPoint(x: chartLeft, y: y))
                    path.addLine(to: CGPoint(x: chartLeft + chartWidth, y: y))
                }
                .stroke(MeterTheme.track, lineWidth: 0.5)

                Text("\(Int(value))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: yLabelWidth, alignment: .trailing)
                    .position(x: yLabelWidth / 2, y: y)
            }

            // 渐变面积
            Path { path in
                guard let first = coords.first, let last = coords.last else { return }
                path.move(to: CGPoint(x: first.x, y: chartHeight))
                path.addLine(to: first)
                addSmoothLines(to: &path, through: coords)
                path.addLine(to: CGPoint(x: last.x, y: chartHeight))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [MeterTheme.accent.opacity(0.28), MeterTheme.accent.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // 折线
            Path { path in
                guard let first = coords.first else { return }
                path.move(to: first)
                addSmoothLines(to: &path, through: coords)
            }
            .stroke(MeterTheme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            // 数据点
            ForEach(Array(coords.enumerated()), id: \.offset) { index, coord in
                if index == coords.count - 1 {
                    Circle()
                        .strokeBorder(MeterTheme.accent, lineWidth: 2.5)
                        .background(Circle().fill(MeterTheme.cardBackground))
                        .frame(width: 11, height: 11)
                        .position(coord)
                } else {
                    Circle()
                        .fill(MeterTheme.accent)
                        .frame(width: 5.5, height: 5.5)
                        .position(coord)
                }
            }

            // X 轴日期标签
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                Text(point.label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .position(x: coords[index].x, y: chartHeight + xLabelHeight / 2 + 3)
            }
        }
    }

    private var yAxisMax: Double {
        let maxValue = points.map(\.value).max() ?? 0
        let stepped = (maxValue / 25.0).rounded(.up) * 25.0
        return min(100, max(75, stepped))
    }

    /// Catmull-Rom 平滑，贴近原型图的柔和曲线。
    private func addSmoothLines(to path: inout Path, through coords: [CGPoint]) {
        guard coords.count > 1 else { return }
        for index in 1..<coords.count {
            let current = coords[index]
            let previous = coords[index - 1]
            let before = index >= 2 ? coords[index - 2] : previous
            let after = index + 1 < coords.count ? coords[index + 1] : current
            let control1 = CGPoint(
                x: previous.x + (current.x - before.x) / 6,
                y: previous.y + (current.y - before.y) / 6
            )
            let control2 = CGPoint(
                x: current.x - (after.x - previous.x) / 6,
                y: current.y - (after.y - previous.y) / 6
            )
            path.addCurve(to: current, control1: control1, control2: control2)
        }
    }
}
