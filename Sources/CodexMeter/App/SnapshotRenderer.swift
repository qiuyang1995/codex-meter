#if DEBUG
import AppKit
import SwiftUI
import CodexMeterCore

/// 开发辅助：`CodexMeter --snapshot 输出.png [dark]` 用模拟数据离屏渲染弹窗，
/// 用于和原型图比对，不进入正常应用流程。
@MainActor
enum SnapshotRenderer {
    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--snapshot"), arguments.count > index + 1 else {
            return false
        }
        let outputPath = arguments[index + 1]
        let dark = arguments.contains("dark")
        NSApplication.shared.setActivationPolicy(.prohibited)
        render(to: outputPath, dark: dark)
        return true
    }

    private static func render(to path: String, dark: Bool) {
        let defaults = UserDefaults(suiteName: "com.local.CodexMeter.preview") ?? .standard
        let settings = AppSettings(defaults: defaults)
        let service = CodexQuotaService(settings: settings, notifications: NotificationService.shared)

        let now = Date()
        let calendar = Calendar.current
        let resetAt = now.addingTimeInterval(4 * 86_400)
        let snapshot = CodexQuotaSnapshot(
            planType: "pro",
            usedPercent: 51,
            remainingPercent: 49,
            resetAt: resetAt,
            windowMinutes: 10_080,
            fetchedAt: now
        )
        var history: [QuotaHistoryPoint] = []
        for (offset, used) in [8.0, 15, 24, 33, 39, 45].enumerated() {
            let day = calendar.date(byAdding: .day, value: offset - 6, to: now) ?? now
            history.append(QuotaHistoryPoint(
                timestamp: day,
                usedPercent: used,
                remainingPercent: 100 - used,
                resetAt: resetAt
            ))
        }
        history.append(QuotaHistoryPoint(snapshot: snapshot))
        service.injectPreviewState(
            snapshot: snapshot,
            history: history,
            connectionState: .connected,
            lastSuccessfulRefresh: now
        )

        let viewModel = QuotaViewModel(service: service, settings: settings)
        let view = MenuBarContentView(viewModel: viewModel, onOpenSettings: {})
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()

        let bounds = hosting.bounds
        let scale: CGFloat = 2
        guard bounds.width > 0, bounds.height > 0,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(bounds.width * scale),
                pixelsHigh: Int(bounds.height * scale),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ) else {
            fputs("snapshot: failed to create bitmap\n", stderr)
            exit(1)
        }
        rep.size = bounds.size
        hosting.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            fputs("snapshot: failed to encode png\n", stderr)
            exit(1)
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            exit(0)
        } catch {
            fputs("snapshot: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
#endif
