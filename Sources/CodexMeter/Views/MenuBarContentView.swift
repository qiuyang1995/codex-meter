import AppKit
import SwiftUI
import CodexMeterCore

struct MenuBarContentView: View {
    @ObservedObject var viewModel: QuotaViewModel
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderView(
                state: viewModel.connectionState,
                severity: viewModel.severity,
                onSettings: onOpenSettings
            )
            .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 8) { content }

            footer
        }
        .padding(14)
        .frame(width: MeterTheme.popoverWidth)
        .background(MeterTheme.popoverBackground)
    }

    @ViewBuilder
    private var content: some View {
        if let kind = viewModel.emptyKind {
            EmptyStateView(
                kind: kind,
                onRetry: {
                    if kind == .missingCLI {
                        viewModel.rediscover()
                    } else {
                        viewModel.refresh()
                    }
                },
                onChoosePath: chooseExecutable
            )
            .meterCard(padding: 14)
        } else if viewModel.showsQuota {
            StatCardsView(todayTitle: viewModel.todayTokenTitle, todayTokenText: viewModel.todayTokenText, weekTokenText: viewModel.weekTokenText)
            Divider()
            PlanCardView(viewModel: viewModel)
            Divider()
            UsageTrendView(viewModel: viewModel)

            if let alert = viewModel.alertText {
                AlertBannerView(text: alert)
            }
        } else {
            ErrorStateView(message: viewModel.lastErrorMessage ?? "暂时无法获取额度") {
                viewModel.refresh()
            }
            .meterCard(padding: 14)
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Divider()
            HStack(spacing: 7) {
                Image(systemName: "arrow.clockwise").font(.system(size: 12.1))
                Text(viewModel.updatedText).font(.system(size: 9.9)).foregroundStyle(.secondary)
                Spacer()
                Button("刷新数据") { viewModel.refresh() }
                    .font(.system(size: 11.0, weight: .medium))
                    .foregroundStyle(MeterTheme.accent)
                    .buttonStyle(.plain)
                    .disabled(viewModel.isRefreshing)
            }
        }
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "选择 Codex 可执行文件"
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.setExecutable(url)
        }
    }

}

@MainActor
enum CodexLauncher {
    static func open() {
        let workspace = NSWorkspace.shared
        let appURL = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            workspace.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        if let url = workspace.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        if let executable = AppSettings.shared.cachedExecutable
            ?? AppSettings.shared.executableOverride {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["app"]
            try? process.run()
            return
        }
        if let fallback = URL(string: "https://chatgpt.com/codex") {
            workspace.open(fallback)
        }
    }
}
