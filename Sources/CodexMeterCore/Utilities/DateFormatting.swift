import Foundation

public enum DateFormatting {
    public static func resetDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 E HH:mm"
        return formatter.string(from: date)
    }

    public static func remaining(until date: Date, now: Date = Date()) -> String {
        let interval = date.timeIntervalSince(now)
        if interval <= 0 {
            return "即将刷新"
        }
        let totalMinutes = Int(interval / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        if days > 0 {
            return "还有 \(days)天 \(hours)小时"
        }
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "还有 \(hours)小时 \(minutes)分钟"
        }
        if minutes > 0 {
            return "还有 \(minutes)分钟"
        }
        return "即将刷新"
    }

    public static func relativeUpdated(from date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 45 {
            return "刚刚更新"
        }
        if seconds < 90 {
            return "1 分钟前更新"
        }
        if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes) 分钟前更新"
        }
        if seconds < 3600 * 24 {
            let hours = Int(seconds / 3600)
            return "\(hours) 小时前更新"
        }
        let days = Int(seconds / 86_400)
        return "\(days) 天前更新"
    }

    public static func clockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
