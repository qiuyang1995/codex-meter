import Foundation

public struct OutputTokenSpeed: Codable, Equatable, Sendable {
    public let responseID: String
    public let completedAt: Date
    public let outputTokens: Int64
    public let duration: TimeInterval

    public init(responseID: String, completedAt: Date, outputTokens: Int64, duration: TimeInterval) {
        self.responseID = responseID
        self.completedAt = completedAt
        self.outputTokens = outputTokens
        self.duration = duration
    }

    public var tokensPerSecond: Double { Double(outputTokens) / duration }
}

struct OutputSpeedHistory {
    static let retention: TimeInterval = 7 * 24 * 3600
    private let url: URL?
    private var records: [OutputTokenSpeed]?
    private var needsSave = false

    init(url: URL?) { self.url = url }

    mutating func recent(at now: Date) -> [OutputTokenSpeed] {
        if records == nil {
            records = url.flatMap { try? Data(contentsOf: $0) }
                .flatMap { try? JSONDecoder().decode([OutputTokenSpeed].self, from: $0) }?
                .filter { $0.outputTokens > 0 && $0.duration > 0 && $0.tokensPerSecond.isFinite } ?? []
        }
        return Array((records ?? []).lazy.filter { $0.completedAt <= now }.suffix(30))
    }

    mutating func record(_ measurements: [OutputTokenSpeed], at now: Date) -> [OutputTokenSpeed] {
        _ = recent(at: now)
        let previous = records ?? []
        var ids = Set(previous.map(\.responseID))
        let sorted = (previous + measurements.filter { ids.insert($0.responseID).inserted }).sorted {
            if $0.completedAt == $1.completedAt { return $0.responseID < $1.responseID }
            return $0.completedAt < $1.completedAt
        }
        let latest = sorted.last { $0.completedAt <= now }
        let cutoff = now.addingTimeInterval(-Self.retention)
        let retained = sorted.filter { $0.completedAt >= cutoff || $0 == latest }
        records = retained
        needsSave = needsSave || retained != previous
        if needsSave, let url {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(retained).write(to: url, options: .atomic)
                needsSave = false
            } catch {
                AppLog.storage.error("Failed to save local output speed history: \(error.localizedDescription, privacy: .public)")
            }
        }
        return recent(at: now)
    }
}

struct OutputItemIdentity: Hashable {
    let thread: String
    let turn: String
    let item: String
}

struct OutputTimingWitness {
    let activityAt: Date
    let deliveredCompletionAt: Date?
}

struct OutputSpeedCandidate: Equatable {
    let firstItem: OutputItemIdentity
    let start: Date
    let firstEnd: Date
    let measurement: OutputTokenSpeed

    func isCorroborated(by witnesses: [OutputTimingWitness]) -> Bool {
        witnesses.contains { witness in
            guard start < witness.activityAt else { return false }
            if witness.activityAt < firstEnd { return true }
            guard let completion = witness.deliveredCompletionAt else { return false }
            return witness.activityAt <= completion && firstEnd <= completion
        }
    }
}

/// Associates one upstream response with its ordered generated items. Tool results
/// and execution lifecycle events are outside this interval.
struct OutputRollout {
    private struct Item {
        let id: String
        let kind: String
        let recordedAt: Date
    }

    private struct Timing: Equatable {
        let thread: String
        let start: Date
        let end: Date
    }

    private var turn: String?
    private var items: [Item] = []
    private var timings: [String: Timing] = [:]
    private var seenResponses: Set<String> = []
    private var damaged = false
    private(set) var candidates: [String: OutputSpeedCandidate] = [:]

    mutating func consume(type: String, payload: [String: Any], at date: Date, since: Date) {
        let kind = payload["type"] as? String
        switch type {
        case "turn_context":
            begin(payload["turn_id"] as? String)
        case "response_item":
            guard let kind, turn != nil,
                  kind == "reasoning" || kind == "function_call" || kind == "custom_tool_call"
                    || (kind == "message" && payload["role"] as? String == "assistant") else { return }
            guard let id = payload["id"] as? String, !id.isEmpty, items.count < 1000 else {
                damaged = true
                return
            }
            if items.contains(where: { $0.id == id }) { damaged = true }
            items.append(Item(id: id, kind: kind, recordedAt: date))
        case "token_usage_record":
            guard let id = payload["response_id"] as? String, !id.isEmpty,
                  seenResponses.insert(id).inserted else { return }
            defer { clearPending() }
            guard !damaged, let turn, payload["turn_id"] as? String == turn,
                  let thread = payload["thread_id"] as? String, !thread.isEmpty,
                  let usage = payload["usage"] as? [String: Any],
                  let output = usage["output_tokens"] as? Int64, output > 0,
                  let first = items.first, first.kind == "reasoning",
                  let timing = timings[first.id], timing.thread == thread, timing.start < timing.end
            else { return }
            var end = timing.end
            for item in items {
                if let bounds = timings[item.id] {
                    guard bounds.thread == thread, bounds.start >= timing.start,
                          bounds.end <= item.recordedAt.addingTimeInterval(0.001) else { return }
                    end = max(end, bounds.end)
                } else {
                    guard item.recordedAt >= timing.start else { return }
                    end = max(end, item.recordedAt)
                }
            }
            guard end >= since, end <= date.addingTimeInterval(0.001) else { return }
            candidates[id] = OutputSpeedCandidate(
                firstItem: OutputItemIdentity(thread: thread, turn: turn, item: first.id),
                start: timing.start,
                firstEnd: timing.end,
                measurement: OutputTokenSpeed(
                    responseID: id, completedAt: end, outputTokens: output,
                    duration: end.timeIntervalSince(timing.start)
                )
            )
        case "event_msg":
            switch kind {
            case "task_started", "turn_started":
                begin(payload["turn_id"] as? String)
            case "task_complete", "turn_aborted", "task_failed":
                begin(nil)
            case "error", "stream_error":
                damaged = true
            case "item_completed":
                guard turn != nil, payload["turn_id"] as? String == turn,
                      let thread = payload["thread_id"] as? String,
                      let item = payload["item"] as? [String: Any],
                      let itemKind = item["type"] as? String, ["Reasoning", "AgentMessage"].contains(itemKind),
                      let id = item["id"] as? String,
                      let start = payload["started_at_ms"] as? Int64,
                      let end = payload["completed_at_ms"] as? Int64, start > 0, end >= start else { return }
                let bounds = Timing(thread: thread,
                                    start: Date(timeIntervalSince1970: Double(start) / 1000),
                                    end: Date(timeIntervalSince1970: Double(end) / 1000))
                if let existing = timings[id], existing != bounds { damaged = true }
                timings[id] = bounds
            default:
                break
            }
        default:
            break
        }
    }

    private mutating func begin(_ newTurn: String?) {
        guard turn != newTurn else { return }
        turn = newTurn
        clearPending()
    }

    private mutating func clearPending() {
        items.removeAll(keepingCapacity: true)
        timings.removeAll(keepingCapacity: true)
        damaged = false
    }
}

/// Desktop notifications are independent evidence that the first reasoning item
/// actually streamed. Keep ownership and delivery order within one log file.
struct DesktopOutputTiming {
    private static let hostPattern = try! NSRegularExpression(pattern:
        #"^error=(?:null|"(?:[^"\\]|\\.)*") failureReason=(?:null|"(?:[^"\\]|\\.)*") hostId=([^\s=]+) server=[^\s=]+ status=(?:starting|ready|failed|cancelled) threadId=([A-Za-z0-9_-]+)$"#)
    private static let renderer = #"(?:(?: rendererWebContentsId=\d+ rendererWindowAppearance=[A-Za-z_-]+ rendererWindowFocused=(?:true|false) rendererWindowId=\d+ rendererWindowVisible=(?:true|false)))?"#
    private static let completionPattern = try! NSRegularExpression(pattern:
        #"^itemId=([A-Za-z0-9_-]+)"# + renderer
        + #" summary=\[(?:"(?:[^"\\]|\\.)*"(?:,"(?:[^"\\]|\\.)*")*)?\] summaryPartCount=\d+ threadId=([A-Za-z0-9_-]+) turnId=([A-Za-z0-9_-]+)$"#)
    private static let activityPattern = try! NSRegularExpression(pattern: #"^(\{[^{}]*\})"# + renderer + "$")
    private static let markers = ["mcp_server_startup_status_updated ", "Reasoning summary part added payload=",
                                  "Reasoning summary item completed ", "[file-logger] dropped "].map { Data($0.utf8) }

    private var hosts: [String: String] = [:]
    private var pending: [OutputItemIdentity: [Date]] = [:]
    private(set) var witnesses: [OutputItemIdentity: [OutputTimingWitness]] = [:]

    mutating func consume(_ bytes: Data, parseDate: (String) -> Date?) {
        guard Self.markers.contains(where: { bytes.range(of: $0) != nil }),
              let line = String(data: bytes, encoding: .utf8) else { return }
        if line.hasPrefix("[file-logger] dropped ") {
            hosts.removeAll()
            pending.removeAll()
            witnesses.removeAll()
            return
        }
        guard let space = line.firstIndex(of: " "), let date = parseDate(String(line[..<space])) else { return }
        let message = line[line.index(after: space)...]
        if let range = message.range(of: #"^(?:info|warning) \[AppServerConnection\] mcp_server_startup_status_updated "#, options: .regularExpression) {
            guard let fields = Self.groups(Self.hostPattern, String(message[range.upperBound...])) else { return }
            let (host, thread) = (fields[0], fields[1])
            if let previous = hosts[thread], previous != host {
                hosts[thread] = ""
                witnesses = witnesses.filter { $0.key.thread != thread }
                pending = pending.filter { $0.key.thread != thread }
            } else {
                hosts[thread] = host
            }
            return
        }
        guard let prefix = message.range(of: #"^info \[(?:host-app-server-manager|electron-message-handler)\] "#, options: .regularExpression) else { return }
        let body = message[prefix.upperBound...]
        let added = "Reasoning summary part added payload="
        let completed = "Reasoning summary item completed "
        if body.hasPrefix(added),
           let fields = Self.groups(Self.activityPattern, String(body.dropFirst(added.count))),
           let data = try? JSONSerialization.jsonObject(with: Data(fields[0].utf8)) as? [String: Any],
           let thread = data["threadId"] as? String, hosts[thread] == "local",
           let turn = data["turnId"] as? String, let item = data["itemId"] as? String,
           let index = data["summaryIndex"] as? Int, index >= 0 {
            let key = OutputItemIdentity(thread: thread, turn: turn, item: item)
            pending[key, default: []].append(date)
            witnesses[key, default: []].append(OutputTimingWitness(activityAt: date, deliveredCompletionAt: nil))
        } else if body.hasPrefix(completed),
                  let fields = Self.groups(Self.completionPattern, String(body.dropFirst(completed.count))),
                  hosts[fields[1]] == "local" {
            let key = OutputItemIdentity(thread: fields[1], turn: fields[2], item: fields[0])
            for activity in pending.removeValue(forKey: key) ?? [] where activity <= date {
                witnesses[key, default: []].append(OutputTimingWitness(activityAt: activity, deliveredCompletionAt: date))
            }
        }
    }

    private static func groups(_ regex: NSRegularExpression, _ text: String) -> [String]? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }
}
