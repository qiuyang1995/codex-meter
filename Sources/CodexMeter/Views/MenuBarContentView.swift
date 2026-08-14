import AppKit
import SwiftUI
import CodexMeterCore

struct MenuBarContentView: View {
    @ObservedObject var viewModel: QuotaViewModel
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderView(
                state: viewModel.connectionState,
                severity: viewModel.severity,
                onSettings: onOpenSettings
            )
            .padding(.bottom, 2)

            content

            footer
        }
        .padding(16)
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
            StatCardsView(
                todayUsedText: viewModel.todayUsedText,
                weekUsedText: viewModel.usedText,
                remainingText: viewModel.remainingText,
                paceTitle: viewModel.pace.title,
                updatedText: viewModel.updatedText,
                resetCountdownText: viewModel.resetCountdownText
            )

            PlanCardView(
                planName: viewModel.planName,
                usedPercent: viewModel.usedValue,
                usedText: viewModel.usedText,
                usedBadgeText: viewModel.usedPercentBadgeText,
                severity: viewModel.severity,
                refreshScheduleText: viewModel.refreshScheduleText
            )

            UsageTrendView(points: viewModel.dailyUsage)

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
        HStack(spacing: 0) {
            Button(action: { viewModel.refresh() }) {
                HStack(spacing: 7) {
                    if viewModel.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text("刷新数据")
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRefreshing)
            .help("立即读取 Codex 周额度")

            Divider()
                .frame(height: 22)

            Button(action: openCodex) {
                HStack(spacing: 7) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MeterTheme.accent)
                    Text("查看详情")
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("打开本机 Codex")
        }
        .background(
            MeterTheme.cardBackground,
            in: RoundedRectangle(cornerRadius: MeterTheme.cardRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MeterTheme.cardRadius, style: .continuous)
                .strokeBorder(MeterTheme.cardBorder, lineWidth: 1)
        )
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
