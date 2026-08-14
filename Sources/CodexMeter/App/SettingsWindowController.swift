import AppKit
import SwiftUI
import CodexMeterCore

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: SettingsViewModel
    private let settings: AppSettings

    init(viewModel: SettingsViewModel, settings: AppSettings) {
        self.viewModel = viewModel
        self.settings = settings
        let hosting = NSHostingController(
            rootView: SettingsView(viewModel: viewModel, settings: settings)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Codex Meter 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 520, height: 420))
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
