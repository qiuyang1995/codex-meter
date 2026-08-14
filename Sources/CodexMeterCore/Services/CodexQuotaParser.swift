import Foundation

public enum CodexQuotaParser {
    public static let weeklyWindowMinutes = 10_080

    public static func parseRateLimits(
        data: Data,
        fetchedAt: Date = Date(),
        planTypeHint: String? = nil,
        accountType: String? = nil
    ) throws -> CodexQuotaSnapshot {
        let object = try jsonObject(from: data)
        return try parseRateLimits(
            object: object,
            fetchedAt: fetchedAt,
            planTypeHint: planTypeHint,
            accountType: accountType
        )
    }

    public static func parseRateLimits(
        json: String,
        fetchedAt: Date = Date(),
        planTypeHint: String? = nil,
        accountType: String? = nil
    ) throws -> CodexQuotaSnapshot {
        guard let data = json.data(using: .utf8) else {
            throw CodexQuotaError.parseFailed
        }
        return try parseRateLimits(
            data: data,
            fetchedAt: fetchedAt,
            planTypeHint: planTypeHint,
            accountType: accountType
        )
    }

    public static func parseRateLimits(
        object: Any,
        fetchedAt: Date = Date(),
        planTypeHint: String? = nil,
        accountType: String? = nil
    ) throws -> CodexQuotaSnapshot {
        let dto = decodeDTO(from: object)
        guard let weekly = selectWeeklyWindow(from: dto) else {
            throw CodexQuotaError.weeklyLimitMissing
        }

        let used: Double
        let remaining: Double
        if let usedPercent = weekly.window.usedPercent {
            used = PercentageFormatting.clamped(usedPercent)
            remaining = PercentageFormatting.clamped(100 - used)
        } else if let remainingPercent = weekly.window.remainingPercent {
            remaining = PercentageFormatting.clamped(remainingPercent)
            used = PercentageFormatting.clamped(100 - remaining)
        } else {
            throw CodexQuotaError.weeklyLimitMissing
        }

        return CodexQuotaSnapshot(
            planType: weekly.planType ?? dto.planType ?? planTypeHint,
            usedPercent: used,
            remainingPercent: remaining,
            resetAt: weekly.window.resetsAt,
            windowMinutes: weekly.window.windowMinutes ?? Self.weeklyWindowMinutes,
            fetchedAt: fetchedAt,
            limitId: weekly.limitId,
            accountType: accountType
        )
    }

    public static func decodeAccount(_ data: Data) -> (accountType: String?, planType: String?, requiresAuth: Bool, loggedIn: Bool) {
        guard let object = (try? jsonObject(from: data)) as? [String: Any] else {
            return (nil, nil, true, false)
        }
        let requiresAuth = JSONValue.bool(object, keys: ["requiresOpenaiAuth", "requires_openai_auth"]) ?? true
        guard let account = JSONValue.object(JSONValue.value(object, keys: ["account"])) else {
            return (nil, nil, requiresAuth, false)
        }
        let type = JSONValue.string(account, keys: ["type"])
        let plan = JSONValue.string(account, keys: ["planType", "plan_type"])
        return (type, plan, requiresAuth, type != nil)
    }

    public static func decodeDTO(from object: Any) -> CodexRateLimitDTO {
        var buckets: [CodexRateLimitBucketDTO] = []
        var windows: [CodexRateLimitWindowDTO] = []
        var planType: String?

        func ingestSnapshot(_ snapshot: [String: Any], limitIdHint: String? = nil) {
            let bucket = decodeBucket(snapshot, limitIdHint: limitIdHint)
            buckets.append(bucket)
            windows.append(contentsOf: bucket.windows)
            if planType == nil {
                planType = bucket.planType
            }
        }

        if let root = JSONValue.object(object) {
            if let snapshot = JSONValue.object(JSONValue.value(root, keys: ["rateLimits", "rate_limits"])) {
                ingestSnapshot(snapshot)
            } else if looksLikeSnapshot(root) {
                ingestSnapshot(root)
            }

            if let map = JSONValue.object(JSONValue.value(root, keys: ["rateLimitsByLimitId", "rate_limits_by_limit_id"])) {
                for (key, value) in map {
                    if let snapshot = JSONValue.object(value) {
                        ingestSnapshot(snapshot, limitIdHint: key)
                    }
                }
            }

            // Some payloads nest windows as an array.
            if let list = JSONValue.array(JSONValue.value(root, keys: ["windows", "rateLimitWindows", "rate_limit_windows"])) {
                windows.append(contentsOf: list.compactMap { JSONValue.object($0).flatMap(decodeWindow) })
            }
        }

        return CodexRateLimitDTO(planType: planType, buckets: buckets, windows: windows)
    }

    private static func selectWeeklyWindow(
        from dto: CodexRateLimitDTO
    ) -> (window: CodexRateLimitWindowDTO, planType: String?, limitId: String?)? {
        // Prefer the overall `codex` bucket, then any weekly window found anywhere.
        let preferred = dto.buckets.sorted { lhs, rhs in
            score(limitId: lhs.limitId) > score(limitId: rhs.limitId)
        }

        for bucket in preferred {
            if let weekly = bucket.windows.first(where: isWeekly) {
                return (weekly, bucket.planType ?? dto.planType, bucket.limitId)
            }
        }

        if let weekly = dto.windows.first(where: isWeekly) {
            return (weekly, dto.planType, nil)
        }
        return nil
    }

    private static func score(limitId: String?) -> Int {
        switch limitId?.lowercased() {
        case "codex": return 100
        case "default", "primary": return 50
        default: return 0
        }
    }

    public static func isWeekly(_ window: CodexRateLimitWindowDTO) -> Bool {
        window.windowMinutes == weeklyWindowMinutes
    }

    private static func decodeBucket(_ object: [String: Any], limitIdHint: String?) -> CodexRateLimitBucketDTO {
        var windows: [CodexRateLimitWindowDTO] = []
        let namedKeys = ["primary", "secondary", "weekly", "fiveHour", "five_hour", "hourly", "daily"]
        for key in namedKeys {
            if let child = JSONValue.object(JSONValue.value(object, keys: [key])),
               let window = decodeWindow(child) {
                windows.append(window)
            }
        }
        if let list = JSONValue.array(JSONValue.value(object, keys: ["windows"])) {
            windows.append(contentsOf: list.compactMap { JSONValue.object($0).flatMap(decodeWindow) })
        }
        // A snapshot itself might be a window.
        if windows.isEmpty, let window = decodeWindow(object), window.windowMinutes != nil || window.usedPercent != nil {
            windows.append(window)
        }
        return CodexRateLimitBucketDTO(
            limitId: JSONValue.string(object, keys: ["limitId", "limit_id"]) ?? limitIdHint,
            limitName: JSONValue.string(object, keys: ["limitName", "limit_name"]),
            planType: JSONValue.string(object, keys: ["planType", "plan_type"]),
            windows: windows
        )
    }

    private static func decodeWindow(_ object: [String: Any]) -> CodexRateLimitWindowDTO? {
        let used = JSONValue.double(object, keys: ["usedPercent", "used_percent", "used"])
        let remaining = JSONValue.double(object, keys: ["remainingPercent", "remaining_percent", "remaining"])
        let minutes = JSONValue.int(
            object,
            keys: ["windowDurationMins", "window_duration_mins", "windowMinutes", "window_minutes"]
        )
        let reset = JSONValue.date(
            fromUnix: JSONValue.value(object, keys: ["resetsAt", "resets_at", "resetAt", "reset_at"])
        )
        if used == nil && remaining == nil && minutes == nil && reset == nil {
            return nil
        }
        return CodexRateLimitWindowDTO(
            usedPercent: used,
            remainingPercent: remaining,
            windowMinutes: minutes,
            resetsAt: reset
        )
    }

    private static func looksLikeSnapshot(_ object: [String: Any]) -> Bool {
        JSONValue.value(object, keys: ["primary", "secondary", "limitId", "limit_id", "planType", "plan_type"]) != nil
    }

    private static func jsonObject(from data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw CodexQuotaError.parseFailed
        }
    }
}
