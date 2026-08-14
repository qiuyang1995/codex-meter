import Foundation

public enum PercentageFormatting {
    /// Integer-looking percent without a thousands separator, e.g. `68%`.
    public static func display(_ value: Double) -> String {
        let clamped = min(max(value, 0), 100)
        if abs(clamped - clamped.rounded()) < 0.05 {
            return "\(Int(clamped.rounded()))%"
        }
        return String(format: "%.1f%%", clamped)
    }

    public static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }
}
