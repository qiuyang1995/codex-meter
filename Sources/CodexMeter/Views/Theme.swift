import SwiftUI
import CodexMeterCore

enum MeterTheme {
    static let popoverWidth: CGFloat = 380
    static let cornerRadius: CGFloat = 20
    static let cardRadius: CGFloat = 14

    static func emphasis(_ severity: QuotaSeverity) -> Color {
        switch severity {
        case .normal:
            return Color.purple
        case .warning:
            return Color.orange
        case .severe:
            return Color(red: 0.90, green: 0.42, blue: 0.20)
        case .danger:
            return Color.red
        case .unknown:
            return Color.secondary
        }
    }

    static func statusDot(_ state: CodexConnectionState, severity: QuotaSeverity) -> Color {
        switch state {
        case .connected:
            return emphasis(severity == .unknown ? .normal : severity)
        case .offlineCached:
            return Color.orange
        case .detecting, .connecting, .reading:
            return Color.secondary
        case .missingCLI, .notLoggedIn, .unavailable:
            return Color.red.opacity(0.85)
        }
    }
}

struct CodexMark: View {
    var size: CGFloat = 28
    var severity: QuotaSeverity = .normal

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(MeterTheme.emphasis(severity == .unknown ? .normal : severity).gradient)
            Text("C")
                .font(.system(size: size * 0.56, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: MeterTheme.emphasis(severity == .unknown ? .normal : severity).opacity(0.25), radius: 4, y: 1)
    }
}
