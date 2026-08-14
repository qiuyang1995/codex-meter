import AppKit
import CodexMeterCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // NSApplication 不持有 delegate；没有 nib 时必须自己实例化并强引用，
    // 否则 @main 展开成的 NSApplicationMain 找不到 delegate，启动后不会执行任何代码。
    private static var sharedDelegate: AppDelegate?

    static func main() {
#if DEBUG
        if SnapshotRenderer.runIfRequested() { return }
#endif
        let app = NSApplication.shared
        let delegate = AppDelegate()
        sharedDelegate = delegate
        app.delegate = delegate
        app.run()
    }

    private var service: CodexQuotaService?
    private var quotaViewModel: QuotaViewModel?
    private var settingsViewModel: SettingsViewModel?
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NotificationService.shared.configure()

        let settings = AppSettings.shared
        let service = CodexQuotaService(settings: settings, notifications: NotificationService.shared)
        let quotaViewModel = QuotaViewModel(service: service, settings: settings)
        let settingsViewModel = SettingsViewModel(service: service, settings: settings)

        self.service = service
        self.quotaViewModel = quotaViewModel
        self.settingsViewModel = settingsViewModel
        self.settingsWindow = SettingsWindowController(viewModel: settingsViewModel, settings: settings)
        self.statusItem = StatusItemController(
            viewModel: quotaViewModel,
            settings: settings,
            onOpenSettings: { [weak self] in
                self?.settingsWindow?.show()
            }
        )

        service.start()
        AppLog.app.info("Codex Meter launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        let client = service?.client
        let group = DispatchGroup()
        group.enter()
        Task.detached {
            await client?.stop()
            group.leave()
        }
        _ = group.wait(timeout: .now() + 1.5)
        AppLog.app.info("Codex Meter terminated")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow?.show()
        return false
    }
}
