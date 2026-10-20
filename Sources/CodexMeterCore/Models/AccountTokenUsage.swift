import Foundation

public struct AccountTokenUsageDailyBucket: Equatable, Sendable {
    public var startDate: String
    public var tokens: Int64

    public init(startDate: String, tokens: Int64) {
        self.startDate = startDate
        self.tokens = tokens
    }
}

/// 本地日历中的周/月范围及每日用量；缺失日期不伪装成零用量。
public enum TokenUsagePeriod: String, CaseIterable, Sendable {
    case week = "周"
    case month = "月"

    public func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        var calendar = calendar
        calendar.firstWeekday = 2
        return calendar.dateInterval(of: self == .week ? .weekOfYear : .month, for: date)!
    }

    public func days(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let range = interval(containing: date, calendar: calendar)
        var days: [Date] = []
        var day = range.start
        while day < range.end {
            days.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return days
    }
}

public enum TokenUsageStatistics {
    public static func byDay(_ buckets: [AccountTokenUsageDailyBucket], calendar: Calendar = .current) -> [Date: Int64] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return buckets.reduce(into: [:]) { result, bucket in
            guard let date = formatter.date(from: String(bucket.startDate.prefix(10))) else { return }
            result[calendar.startOfDay(for: date)] = bucket.tokens
        }
    }
}

public struct WeeklyTokenUsage: Equatable, Sendable, Identifiable {
    public let start: Date
    public let end: Date
    public let tokens: Int64?
    public var id: Date { start }
}

extension TokenUsageStatistics {
    /// Each bucket covers Monday through Sunday; missing weeks remain unknown.
    public static func byWeek(_ daily: [Date: Int64], through now: Date, calendar: Calendar = .current) -> [WeeklyTokenUsage] {
        let today = calendar.startOfDay(for: now)
        let valid = daily.filter { $0.key <= today }
        guard let earliest = valid.keys.min() else { return [] }
        var totals: [Date: Int64] = [:]
        for (day, tokens) in valid {
            let start = TokenUsagePeriod.week.interval(containing: day, calendar: calendar).start
            totals[start, default: 0] += tokens
        }
        var start = TokenUsagePeriod.week.interval(containing: earliest, calendar: calendar).start
        var result: [WeeklyTokenUsage] = []
        while start <= today {
            let end = calendar.date(byAdding: .day, value: 7, to: start)!
            result.append(WeeklyTokenUsage(start: start, end: end, tokens: totals[start]))
            start = end
        }
        return result
    }
}
