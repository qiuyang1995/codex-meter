import AppKit
import Combine
import SwiftUI
import CodexMeterCore

@MainActor
final class StatusItemController: NSObject {
    private let viewModel: QuotaViewModel
    private let settings: AppSettings
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private let onOpenSettings: () -> Void

    init(viewModel: QuotaViewModel, settings: AppSettings, onOpenSettings: @escaping () -> Void) {
        self.viewModel = viewModel
        self.settings = settings
        self.onOpenSettings = onOpenSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        popover.behavior = .transient
        popover.animates = true
        let root = MenuBarContentView(viewModel: viewModel, onOpenSettings: { [weak self] in
            self?.popover.performClose(nil)
            onOpenSettings()
        })
        let hosting = NSHostingController(rootView: root)
        // 让 popover 跟随 SwiftUI 内容的真实尺寸；写死高度会导致弹出后
        // 内容撑大、popover 向上扩展盖住菜单栏图标。
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        if let button = statusItem.button {
            button.imagePosition = .imageLeft
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Codex Meter"
        }

        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshIcon()
            }
            .store(in: &cancellables)
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshIcon()
            }
            .store(in: &cancellables)

        refreshIcon()
    }

    func refreshIcon() {
        let showPercent = settings.menuBarDisplayMode == .iconAndPercent
        let image = MenuBarIconRenderer.image(
            severity: viewModel.severity,
            remainingText: viewModel.remainingText,
            showPercent: showPercent
        )
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageOnly
        if let remaining = viewModel.snapshot?.remainingPercent {
            statusItem.button?.toolTip = "Codex 本周剩余 \(PercentageFormatting.display(remaining))"
        } else {
            statusItem.button?.toolTip = "Codex Meter"
        }
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }
}
