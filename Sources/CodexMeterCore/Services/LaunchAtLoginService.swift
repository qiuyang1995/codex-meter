import Foundation
import ServiceManagement

public enum LaunchAtLoginService {
    public static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    public static var statusDescription: String {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled: return "已开启"
            case .notRegistered: return "未开启"
            case .notFound: return "需要安装到应用程序文件夹后才能开机启动"
            case .requiresApproval: return "需要在系统设置中允许登录项"
            @unknown default: return "未知"
            }
        }
        return "当前系统不支持"
    }

    public static func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else { return }
        if enabled {
            try SMAppService.mainApp.register()
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}
