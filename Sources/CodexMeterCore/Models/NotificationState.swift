import Foundation

public struct NotificationState: Equatable, Sendable, Codable {
    public var windowKey: String
    public var firedThresholds: [Int]
    public var firedRefresh: Bool

    public init(windowKey: String = "", firedThresholds: [Int] = [], firedRefresh: Bool = false) {
        self.windowKey = windowKey
        self.firedThresholds = firedThresholds
        self.firedRefresh = firedRefresh
    }

    public var firedSet: Set<Int> {
        Set(firedThresholds)
    }
}

public enum QuotaNotificationKind: Equatable, Sendable {
    case remaining(threshold: Int)
    case weeklyRefreshed
}

public struct QuotaNotificationDecision: Equatable, Sendable {
    public var nextState: NotificationState
    public var notifications: [QuotaNotificationKind]

    public init(nextState: NotificationState, notifications: [QuotaNotificationKind]) {
        self.nextState = nextState
        self.notifications = notifications
    }
}

public enum NotificationPolicy {
    /// Decide which notifications to fire for a confirmed snapshot.
    /// A new weekly window resets per-threshold delivery.
    public static func evaluate(
        snapshot: CodexQuotaSnapshot,
        previous: NotificationState,
        notificationsEnabled: Bool,
        notifyOnRefresh: Bool,
        thresholds: [Int],
        cycleDidReset: Bool
    ) -> QuotaNotificationDecision {
        var state = previous
        var events: [QuotaNotificationKind] = []

        if cycleDidReset {
            state = NotificationState(windowKey: snapshot.windowKey)
            if notifyOnRefresh && notificationsEnabled {
                events.append(.weeklyRefreshed)
                state.firedRefresh = true
            }
        } else if state.windowKey.isEmpty {
            state.windowKey = snapshot.windowKey
        }

        guard notificationsEnabled else {
            return QuotaNotificationDecision(nextState: state, notifications: events)
        }

        let remaining = snapshot.remainingPercent
        let sorted = thresholds.sorted(by: >)
        var fired = state.firedSet
        for threshold in sorted {
            if remaining <= Double(threshold) && fired.contains(threshold) == false {
                events.append(.remaining(threshold: threshold))
                fired.insert(threshold)
            }
        }
        state.firedThresholds = fired.sorted(by: >)
        return QuotaNotificationDecision(nextState: state, notifications: events)
    }
}
