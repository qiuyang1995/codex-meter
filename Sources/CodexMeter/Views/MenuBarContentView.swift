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

            if let credits = viewModel.service.resetCredits, credits.availableCount(at: viewModel.tick) > 0 {
                ResetCreditsView(summary: credits, now: viewModel.tick)
            }

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
        panel.treatsFilePackagesAsDirectories = false
        panel.title = "选择 Codex App 或可执行文件"
        panel.message = "可直接选择 Codex.app、ChatGPT.app，或 Codex CLI 可执行文件。"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
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


private struct ResetCreditsView: View {
    let summary: RateLimitResetCredits
    let now: Date
    @State private var expanded = true

    var body: some View {
        let credits = summary.availableCredits(at: now)
        let count = summary.availableCount(at: now)
        return DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(credits.enumerated()), id: \.element.id) { index, credit in
                    if index > 0 { Divider() }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(credit.displayTitle)
                            .font(.system(size: 11, weight: .medium))
                        Text(expirationText(credit.expiresAt))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if count > credits.count {
                    Text(credits.isEmpty ? "暂未获取到重置卡明细" : "另有 \(count - credits.count) 张重置卡暂无明细")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.padding(.top, 8)
        } label: {
            HStack {
                Text("使用限额重置").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("可用 \(count) 次")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(MeterTheme.green)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(MeterTheme.green.opacity(0.12), in: Capsule())
            }
        }
        .tint(MeterTheme.accent)
        .meterCard(padding: 10)
    }

    private func expirationText(_ date: Date?) -> String {
        guard let date else { return "无到期限制" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d HH:mm zzz"
        return "将于 \(formatter.string(from: date)) 到期"
    }
}
