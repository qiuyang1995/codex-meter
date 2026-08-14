import Foundation
import Combine

public enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case iconOnly
    case iconAndPercent

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .iconOnly: return "仅显示图标"
        case .iconAndPercent: return "显示剩余百分比"
        }
    }
}

public enum RefreshInterval: Int, CaseIterable, Identifiable, Sendable {
    case oneMinute = 60
    case fiveMinutes = 300
    case tenMinutes = 600
    case thirtyMinutes = 1_800

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .oneMinute: return "1 分钟"
        case .fiveMinutes: return "5 分钟"
        case .tenMinutes: return "10 分钟"
        case .thirtyMinutes: return "30 分钟"
        }
    }

    public var timeInterval: TimeInterval { TimeInterval(rawValue) }
}

@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private let defaults: UserDefaults
    private enum Key {
        static let menuBarDisplayMode = "settings.menuBarDisplayMode"
        static let refreshInterval = "settings.refreshInterval"
        static let notificationsEnabled = "settings.notificationsEnabled"
        static let notifyOnRefresh = "settings.notifyOnRefresh"
        static let warningThresholds = "settings.warningThresholds"
        static let executableOverride = "settings.executableOverride"
        static let cachedExecutable = "settings.cachedExecutable"
    }

    @Published public var menuBarDisplayMode: MenuBarDisplayMode {
        didSet { defaults.set(menuBarDisplayMode.rawValue, forKey: Key.menuBarDisplayMode) }
    }

    @Published public var refreshInterval: RefreshInterval {
        didSet { defaults.set(refreshInterval.rawValue, forKey: Key.refreshInterval) }
    }

    @Published public var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }

    @Published public var notifyOnRefresh: Bool {
        didSet { defaults.set(notifyOnRefresh, forKey: Key.notifyOnRefresh) }
    }

    @Published public var warningThresholds: [Int] {
        didSet { defaults.set(warningThresholds, forKey: Key.warningThresholds) }
    }

    @Published public var executableOverride: String? {
        didSet { defaults.set(executableOverride, forKey: Key.executableOverride) }
    }

    @Published public var cachedExecutable: String? {
        didSet { defaults.set(cachedExecutable, forKey: Key.cachedExecutable) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Key.menuBarDisplayMode),
           let mode = MenuBarDisplayMode(rawValue: raw) {
            menuBarDisplayMode = mode
        } else {
            menuBarDisplayMode = .iconOnly
        }

        if let raw = defaults.object(forKey: Key.refreshInterval) as? Int,
           let interval = RefreshInterval(rawValue: raw) {
            refreshInterval = interval
        } else {
            refreshInterval = .fiveMinutes
        }

        if defaults.object(forKey: Key.notificationsEnabled) == nil {
            notificationsEnabled = true
        } else {
            notificationsEnabled = defaults.bool(forKey: Key.notificationsEnabled)
        }

        if defaults.object(forKey: Key.notifyOnRefresh) == nil {
            notifyOnRefresh = true
        } else {
            notifyOnRefresh = defaults.bool(forKey: Key.notifyOnRefresh)
        }

        if let stored = defaults.array(forKey: Key.warningThresholds) as? [Int], !stored.isEmpty {
            warningThresholds = stored.sorted(by: >)
        } else {
            warningThresholds = [30, 15, 5]
        }

        executableOverride = defaults.string(forKey: Key.executableOverride)
        cachedExecutable = defaults.string(forKey: Key.cachedExecutable)
    }
}
