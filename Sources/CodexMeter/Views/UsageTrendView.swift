import SwiftUI
import CodexMeterCore

/// 周/月日历热力图，每个日期格对应一天的 Token 用量。
struct UsageTrendView: View {
    @ObservedObject var viewModel: QuotaViewModel
    @State private var period: TokenUsagePeriod = {
#if DEBUG
        if CommandLine.arguments.contains("--snapshot-week") { return .week }
#endif
        return .month
    }()
    @State private var anchor: Date = {
#if DEBUG
        if CommandLine.arguments.contains("--snapshot-six-rows") {
            return Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        }
#endif
        return Date()
    }()
    @State private var selectedDay: Date?
    @State private var hoveredDay: Date? = {
#if DEBUG
        if CommandLine.arguments.contains("--snapshot-hover") { return Calendar.current.startOfDay(for: Date()) }
#endif
        return nil
    }()
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    private var days: [Date] { period.days(containing: anchor, calendar: calendar) }
    private var range: DateInterval { period.interval(containing: anchor, calendar: calendar) }
    private var leadingBlanks: Int { (calendar.component(.weekday, from: range.start) + 5) % 7 }
    private var usage: [Date: Int64] { viewModel.tokenUsageByDay }
    private var today: Date { calendar.startOfDay(for: viewModel.tick) }
    private var canGoForward: Bool { range.end <= today }
    private var canGoBack: Bool { usage.keys.min().map { $0 < range.start } ?? false }

    var body: some View {
        let visibleDays = days
        let indexedUsage = usage
        let maximum = max(visibleDays.compactMap { indexedUsage[$0] }.max() ?? 0, 1)
        let detailDay = selectedDay
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                summary("累计 Token", value: viewModel.lifetimeTokenText, caption: viewModel.lifetimeTokenCaption)
                Divider().frame(height: 40)
                summary("单日峰值", value: viewModel.peakTokenText, caption: "已获取的历史")
            }
            Divider()
            HStack {
                Text("每日用量").font(.system(size: 13.2, weight: .semibold))
                Spacer()
                HStack(spacing: 2) {
                    ForEach(TokenUsagePeriod.allCases, id: \.self) { item in
                        Button {
                            period = item
                            selectedDay = nil
                            hoveredDay = nil
                        } label: {
                            Text(item.rawValue)
                                .font(.system(size: 11.0, weight: .medium))
                                .foregroundStyle(period == item ? MeterTheme.accent : .secondary)
                                .frame(width: 30, height: 20)
                                .background(period == item ? MeterTheme.cardBackground : .clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .accessibilityAddTraits(period == item ? [.isSelected] : [])
                    }
                }
                .padding(2)
                .background(MeterTheme.track.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            }
            if usage.isEmpty {
                Text("暂无 Token 用量数据")
                    .font(.system(size: 11.0)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 65)
            } else {
                HStack {
                    navigationButton("chevron.left", enabled: canGoBack, offset: -1)
                    Spacer()
                    Text(periodTitle).font(.system(size: 11.0, weight: .semibold)).monospacedDigit()
                    Spacer()
                    navigationButton("chevron.right", enabled: canGoForward, offset: 1)
                }
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) {
                        Text($0).font(.system(size: 9.4)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.bottom, 1)
                    }
                    ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 20) }
                    ForEach(visibleDays, id: \.self) { day in
                        dayCell(day, value: indexedUsage[day], maximum: maximum)
                    }
                    ForEach(0..<((7 - (leadingBlanks + days.count) % 7) % 7), id: \.self) { _ in
                        Color.clear.frame(height: 20)
                    }
                }
                HStack {
                    Text(detailDay.map { dateLabel($0, format: "M月d日") } ?? "悬停查看 · 点击固定")
                    Spacer(minLength: 3)
                    Text(detailDay.map { day in
                        day > today ? "尚未到来" : indexedUsage[day].map { "\(TokenFormatting.display(Double($0))) Tokens" } ?? "无用量记录"
                    } ?? "")
                }
                .font(.system(size: 9.9)).monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(height: 13)
                .lineLimit(1)
                HStack(spacing: 5) {
                    Text("少")
                    ForEach(0..<5) { level in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(MeterTheme.blue.opacity(0.12 + Double(level) * 0.2))
                            .frame(width: 8, height: 8)
                    }
                    Text("多")
                    Spacer()
                    Text("点击可固定详情")
                }
                .font(.system(size: 8.8)).foregroundStyle(.secondary)
            }
        }
    }

    private func summary(_ title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 9.9)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22.0, weight: .semibold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(.system(size: 8.8)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dayCell(_ day: Date, value: Int64?, maximum: Int64) -> some View {
        let future = day > today
        let intensity = value.map { 0.14 + 0.7 * Double($0) / Double(maximum) } ?? 0
        let highlighted = (hoveredDay ?? selectedDay ?? today) == day
        return Button { selectedDay = day } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 9.9, weight: highlighted ? .semibold : .regular))
                .foregroundStyle(future ? Color.secondary : (intensity > 0.6 ? .white : .primary))
                .frame(maxWidth: .infinity).frame(height: 20)
                .background(
                    future || value == nil ? MeterTheme.track.opacity(0.35) : MeterTheme.blue.opacity(intensity),
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(highlighted ? MeterTheme.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(CalendarDayButtonStyle())
        .disabled(future)
        .onHover { inside in
            if inside { hoveredDay = day }
            else if hoveredDay == day { hoveredDay = nil }
        }
        .overlay(alignment: tooltipAlignment(day)) {
            if hoveredDay == day {
                VStack(alignment: .leading, spacing: 3) {
                    Text(dateLabel(day, format: "M月d日"))
                        .foregroundStyle(.secondary)
                    Text(value.map { "\(TokenFormatting.display(Double($0))) Tokens" } ?? "无用量记录")
                        .fontWeight(.semibold)
                }
                .font(.system(size: 11.0))
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(MeterTheme.cardBorder, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                .fixedSize()
                .offset(y: -53)
                .allowsHitTesting(false)
            }
        }
        .zIndex(hoveredDay == day ? 1 : 0)
        .accessibilityLabel("\(calendar.component(.month, from: day))月\(calendar.component(.day, from: day))日，\(value.map { "\($0) Tokens" } ?? "无用量记录")")
    }

    private func tooltipAlignment(_ day: Date) -> Alignment {
        let column = (calendar.component(.weekday, from: day) + 5) % 7
        if column < 2 { return .topLeading }
        if column > 4 { return .topTrailing }
        return .top
    }

    private var periodTitle: String {
        if period == .month { return dateLabel(range.start, format: "yyyy年M月") }
        let last = calendar.date(byAdding: .day, value: -1, to: range.end)!
        return "\(dateLabel(range.start, format: "M月d日")) — \(dateLabel(last, format: "M月d日"))"
    }

    private func dateLabel(_ date: Date, format: String) -> String {
        if format == "yyyy年M月" {
            return "\(calendar.component(.year, from: date))年\(calendar.component(.month, from: date))月"
        }
        return "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日"
    }

    private func navigationButton(_ icon: String, enabled: Bool, offset: Int) -> some View {
        Button {
            anchor = calendar.date(byAdding: period == .month ? .month : .weekOfYear, value: offset, to: range.start)!
            selectedDay = nil
            hoveredDay = nil
        } label: {
            Image(systemName: icon).font(.system(size: 9.9, weight: .semibold))
                .frame(width: 20, height: 20)
                .background(MeterTheme.track.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityLabel(offset < 0 ? "上一\(period.rawValue)" : "下一\(period.rawValue)")
    }
}

private struct CalendarDayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
    }
}
