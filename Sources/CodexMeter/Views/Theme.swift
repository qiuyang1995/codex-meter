import AppKit
import SwiftUI
import CodexMeterCore

enum MeterTheme {
    static let popoverWidth: CGFloat = 340
    static let cardRadius: CGFloat = 9

    // MARK: - 原型图配色（浅色为准，深色做等价映射）

    static let accent = dynamic(light: NSColor(srgbRed: 0.32, green: 0.30, blue: 0.92, alpha: 1),
                                dark: NSColor(srgbRed: 0.55, green: 0.53, blue: 1.00, alpha: 1))

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(nsColor: NSColor(srgbRed: 0.43, green: 0.40, blue: 0.97, alpha: 1)),
                Color(nsColor: NSColor(srgbRed: 0.31, green: 0.28, blue: 0.90, alpha: 1))
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static var iconGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(nsColor: NSColor(srgbRed: 0.47, green: 0.42, blue: 1.00, alpha: 1)),
                Color(nsColor: NSColor(srgbRed: 0.29, green: 0.27, blue: 0.89, alpha: 1))
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static let popoverBackground = dynamic(light: NSColor(srgbRed: 0.988, green: 0.988, blue: 0.992, alpha: 1),
                                           dark: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1))
    static let cardBackground = dynamic(light: .white,
                                        dark: NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1))
    static let cardBorder = dynamic(light: NSColor(srgbRed: 0.89, green: 0.89, blue: 0.92, alpha: 1),
                                    dark: NSColor(white: 1, alpha: 0.12))
    static let track = dynamic(light: NSColor(srgbRed: 0.92, green: 0.92, blue: 0.94, alpha: 1),
                               dark: NSColor(white: 1, alpha: 0.14))

    static let green = dynamic(light: NSColor(srgbRed: 0.13, green: 0.72, blue: 0.36, alpha: 1),
                               dark: NSColor(srgbRed: 0.25, green: 0.82, blue: 0.47, alpha: 1))
    static let blue = dynamic(light: NSColor(srgbRed: 0.23, green: 0.51, blue: 0.96, alpha: 1),
                              dark: NSColor(srgbRed: 0.40, green: 0.63, blue: 1.00, alpha: 1))
    static let purple = dynamic(light: NSColor(srgbRed: 0.55, green: 0.36, blue: 0.96, alpha: 1),
                                dark: NSColor(srgbRed: 0.68, green: 0.53, blue: 1.00, alpha: 1))

    static let warningBackground = dynamic(light: NSColor(srgbRed: 0.99, green: 0.93, blue: 0.82, alpha: 1),
                                           dark: NSColor(srgbRed: 0.29, green: 0.23, blue: 0.10, alpha: 1))
    static let warningForeground = dynamic(light: NSColor(srgbRed: 0.58, green: 0.38, blue: 0.04, alpha: 1),
                                           dark: NSColor(srgbRed: 0.96, green: 0.78, blue: 0.42, alpha: 1))
    static let warningIcon = dynamic(light: NSColor(srgbRed: 0.96, green: 0.65, blue: 0.14, alpha: 1),
                                     dark: NSColor(srgbRed: 0.98, green: 0.73, blue: 0.28, alpha: 1))

    static func emphasis(_ severity: QuotaSeverity) -> Color {
        switch severity {
        case .normal:
            return accent
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
            switch severity {
            case .normal, .unknown:
                return green
            case .warning, .severe:
                return Color.orange
            case .danger:
                return Color.red
            }
        case .offlineCached:
            return Color.orange
        case .detecting, .connecting, .reading:
            return Color.secondary
        case .missingCLI, .notLoggedIn, .unavailable:
            return Color.red.opacity(0.85)
        }
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

// MARK: - 卡片样式（白底、细边框、圆角，同原型图）

struct MeterCardStyle: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                MeterTheme.cardBackground,
                in: RoundedRectangle(cornerRadius: MeterTheme.cardRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MeterTheme.cardRadius, style: .continuous)
                    .strokeBorder(MeterTheme.cardBorder, lineWidth: 1)
            )
    }
}

extension View {
    func meterCard(padding: CGFloat = 14) -> some View {
        modifier(MeterCardStyle(padding: padding))
    }
}

struct CodexMark: View {
    var size: CGFloat = 28
    var severity: QuotaSeverity = .normal

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(MeterTheme.iconGradient)
            Text("C")
                .font(.system(size: size * 0.56, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: MeterTheme.accent.opacity(0.3), radius: 5, y: 2)
    }
}
