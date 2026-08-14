import AppKit
import SwiftUI
import CodexMeterCore

struct MenuBarContentView: View {
    @ObservedObject var viewModel: QuotaViewModel
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HeaderView(
                state: viewModel.connectionState,
                severity: viewModel.severity,
                onSettings: onOpenSettings
            )

            content

            footer
        }
        .padding(18)
        .frame(width: MeterTheme.popoverWidth)
        .background(.regularMaterial)
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
        } else if viewModel.showsQuota {
            QuotaHeroView(
                remainingText: viewModel.remainingText,
                remainingValue: viewModel.remainingValue,
                usedValue: viewModel.usedValue,
                severity: viewModel.severity,
                resetDateText: viewModel.resetDateText,
                resetCountdownText: viewModel.resetCountdownText
            )

            UsagePaceView(
                usedText: viewModel.usedText,
                elapsedPercent: viewModel.elapsedPercent,
                pace: viewModel.pace
            )

            UsageTrendView(points: viewModel.history)
        } else {
            ErrorStateView(message: viewModel.lastErrorMessage ?? "暂时无法获取额度") {
                viewModel.refresh()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.refresh()
            } label: {
                HStack(spacing: 5) {
                    if viewModel.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("刷新")
                }
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isRefreshing)
            .help("立即读取 Codex 周额度")

            Text(viewModel.updatedText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Button("打开 Codex", action: openCodex)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("打开本机 Codex")
        }
        .font(.system(size: 12.5))
        .padding(.top, 2)
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

    private func openCodex() {
        CodexLauncher.open()
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
