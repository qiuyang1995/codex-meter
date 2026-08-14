import Foundation

/// Confirms a weekly-window rollover without treating a single glitchy payload as a reset.
public struct CycleDetector: Equatable, Sendable {
    public struct Pending: Equatable, Sendable {
        public var windowKey: String
        public var usedPercent: Double
        public var confirmations: Int
    }

    public var lastConfirmed: CodexQuotaSnapshot?
    public var pending: Pending?

    public init(lastConfirmed: CodexQuotaSnapshot? = nil) {
        self.lastConfirmed = lastConfirmed
    }

    public mutating func observe(_ snapshot: CodexQuotaSnapshot) -> Bool {
        guard let previous = lastConfirmed else {
            lastConfirmed = snapshot
            pending = nil
            return false
        }

        let looksLikeNewWindow = isLikelyNewWindow(previous: previous, current: snapshot)
        guard looksLikeNewWindow else {
            pending = nil
            lastConfirmed = snapshot
            return false
        }

        if let pending, pending.windowKey == snapshot.windowKey {
            self.pending = Pending(
                windowKey: snapshot.windowKey,
                usedPercent: snapshot.usedPercent,
                confirmations: pending.confirmations + 1
            )
        } else {
            self.pending = Pending(
                windowKey: snapshot.windowKey,
                usedPercent: snapshot.usedPercent,
                confirmations: 1
            )
        }

        if (self.pending?.confirmations ?? 0) >= 2 {
            lastConfirmed = snapshot
            self.pending = nil
            return true
        }
        return false
    }

    private func isLikelyNewWindow(previous: CodexQuotaSnapshot, current: CodexQuotaSnapshot) -> Bool {
        if let previousReset = previous.resetAt, let currentReset = current.resetAt {
            let delta = abs(currentReset.timeIntervalSince(previousReset))
            if delta >= 60 {
                return true
            }
        }
        return previous.usedPercent >= 50 && current.usedPercent <= 8
    }

}
