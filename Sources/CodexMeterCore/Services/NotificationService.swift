import Foundation
import UserNotifications

@MainActor
public final class NotificationService: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    public static let shared = NotificationService()

    public override init() {
        super.init()
    }

    public func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    public func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                AppLog.notification.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        default:
            return false
        }
    }

    public func deliver(_ kind: QuotaNotificationKind) async {
        let content = UNMutableNotificationContent()
        content.sound = .default
        switch kind {
        case .remaining(let threshold):
            if threshold <= 5 {
                content.title = "Codex 本周额度即将用尽"
                content.body = "本周剩余额度已不足 \(threshold)%。"
            } else {
                content.title = "Codex 本周额度剩余 \(threshold)%"
                content.body = "本周 Codex 额度还剩 \(threshold)% 左右。"
            }
        case .weeklyRefreshed:
            content.title = "Codex 周额度已刷新"
            content.body = "新的一周额度已经开始。"
        }

        let request = UNNotificationRequest(
            identifier: "codex-meter.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            AppLog.notification.error("Failed to deliver notification: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }
}
