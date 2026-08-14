import SwiftUI
import CodexMeterCore

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }
            notificationsTab
                .tabItem { Label("通知", systemImage: "bell") }
            codexTab
                .tabItem { Label("Codex", systemImage: "terminal") }
            aboutTab
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .padding(20)
        .frame(width: 520, height: 400)
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("开机自动启动", isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { viewModel.setLaunchAtLogin($0) }
                ))
                if let hint = viewModel.launchAtLoginHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("菜单栏") {
                Picker("显示", selection: $settings.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("刷新间隔") {
                Picker("刷新间隔", selection: $settings.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        .formStyle(.grouped)
    }

    private var notificationsTab: some View {
        Form {
            Section {
                Toggle("额度提醒", isOn: Binding(
                    get: { settings.notificationsEnabled },
                    set: { enabled in
                        settings.notificationsEnabled = enabled
                        if enabled {
                            viewModel.enableNotificationsAndRequest()
                        }
                    }
                ))
                Toggle("额度刷新后通知", isOn: $settings.notifyOnRefresh)
                    .disabled(settings.notificationsEnabled == false)
            }

            Section("提醒阈值") {
                thresholdRow(30)
                thresholdRow(15)
                thresholdRow(5)
                Text("同一周额度周期内，每个阈值只会提醒一次。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if settings.notificationsEnabled {
                viewModel.enableNotificationsAndRequest()
            }
        }
    }

    private var codexTab: some View {
        Form {
            Section("Codex CLI") {
                LabeledContent("路径") {
                    Text(viewModel.executablePath)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
                LabeledContent("状态") {
                    Text(viewModel.connectionLabel)
                }
                LabeledContent("套餐") {
                    Text(viewModel.planLabel)
                }
                HStack {
                    Button("重新检测") { viewModel.rediscover() }
                    Button("选择路径") { viewModel.chooseExecutable() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        VStack(spacing: 16) {
            CodexMark(size: 64, severity: .normal)
            Text("Codex Meter")
                .font(.system(size: 20, weight: .semibold))
            Text(viewModel.versionText)
                .foregroundStyle(.secondary)
            Text("本机 Codex 周额度监控")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Button("退出 Codex Meter", role: .destructive) {
                viewModel.quit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 28)
    }

    private func thresholdRow(_ value: Int) -> some View {
        Toggle("剩余 \(value)%", isOn: Binding(
            get: { settings.warningThresholds.contains(value) },
            set: { enabled in
                var next = Set(settings.warningThresholds)
                if enabled {
                    next.insert(value)
                } else {
                    next.remove(value)
                }
                settings.warningThresholds = next.sorted(by: >)
            }
        ))
        .disabled(settings.notificationsEnabled == false)
    }
}
