import Foundation
import os

/// Structured loggers. Never write tokens, cookies, or Authorization headers.
public enum AppLog {
    public static let subsystem = "com.local.CodexMeter"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let codex = Logger(subsystem: subsystem, category: "codex")
    public static let quota = Logger(subsystem: subsystem, category: "quota")
    public static let storage = Logger(subsystem: subsystem, category: "storage")
    public static let notification = Logger(subsystem: subsystem, category: "notification")
}
