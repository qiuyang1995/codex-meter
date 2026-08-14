import AppKit
import Combine
import Foundation
import CodexMeterCore

@MainActor
final class SettingsViewModel: ObservableObject {
    let service: CodexQuotaService
    let settings: AppSettings

    @Published var launchAtLogin: Bool
    @Published var launchAtLoginHint: String?

    private var cancellables = Set<AnyCancellable>()

    init(service: CodexQuotaService, settings: AppSettings) {
        self.service = service
        self.settings = settings
        self.launchAtLogin = LaunchAtLoginService.isEnabled
        self.launchAtLoginHint = LaunchAtLoginService.statusDescription == "已开启" || LaunchAtLoginService.statusDescription == "未开启"
            ? nil
            : LaunchAtLoginService.statusDescription

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        service.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var executablePath: String {
        settings.executableOverride
            ?? service.executableURL?.path
            ?? settings.cachedExecutable
            ?? "未设置"
    }

    var connectionLabel: String {
        service.connectionState.headerTitle
    }

    var planLabel: String {
        if let plan = service.snapshot?.displayPlan ?? service.planType.flatMap(CodexQuotaSnapshot.prettyPlan) {
            return "Plan: \(plan)"
        }
        return "Plan: 暂不可用"
    }

    var versionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(enabled)
            launchAtLogin = LaunchAtLoginService.isEnabled
            let status = LaunchAtLoginService.statusDescription
            launchAtLoginHint = (status == "已开启" || status == "未开启") ? nil : status
        } catch {
            launchAtLogin = LaunchAtLoginService.isEnabled
            launchAtLoginHint = error.localizedDescription
        }
    }

    func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.title = "选择 Codex 可执行文件"
        panel.prompt = "选择"
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        if panel.runModal() == .OK, let url = panel.url {
            Task { await service.setExecutableOverride(url.path) }
        }
    }

    func rediscover() {
        Task { await service.rediscover() }
    }

    func enableNotificationsAndRequest() {
        settings.notificationsEnabled = true
        Task {
            _ = await NotificationService.shared.requestAuthorizationIfNeeded()
        }
    }

    func quit() {
        Task {
            await service.shutdown()
            NSApp.terminate(nil)
        }
    }
}
