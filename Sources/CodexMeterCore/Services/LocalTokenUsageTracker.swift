import Foundation

public struct LocalTodayTokenUsage: Equatable, Sendable {
    public let day: Date
    public let tokens: Int64

    public init(day: Date, tokens: Int64) {
        self.day = day
        self.tokens = tokens
    }
}

/// Reads only metadata / token-count records. File offsets keep the five-second
/// refresh incremental; the actor keeps disk I/O and parsing off the UI actor.
public actor LocalTokenUsageTracker {
    private struct FileState {
        var offset: UInt64 = 0
        var pending = Data()
        var previousTotal: Int64?
        var events: [String: Int64] = [:]
        var modified: Date?
        var isOpenAI = true
    }

    private let root: URL
    private var day: Date?
    private var files: [String: FileState] = [:]
    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let secondsFormatter = ISO8601DateFormatter()

    public init(root: URL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"]
                               ?? NSHomeDirectory() + "/.codex", isDirectory: true)) {
        self.root = root
    }

    public func reset() {
        day = nil
        files.removeAll()
    }

    public func sample(now: Date = Date(), calendar: Calendar = .current) -> LocalTodayTokenUsage? {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        if day != start {
            day = start
            files.removeAll()
        }
        let manager = FileManager.default
        guard manager.isReadableFile(atPath: root.appendingPathComponent("sessions").path) else { return nil }
        var failed = false
        for directory in ["sessions", "archived_sessions"] {
            let directoryURL = root.appendingPathComponent(directory)
            guard manager.fileExists(atPath: directoryURL.path) else { continue }
            guard let enumerator = manager.enumerator(
                at: directoryURL, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles], errorHandler: { _, _ in failed = true; return true }
            ) else { return nil }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                if Task.isCancelled { return nil }
                do {
                    let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    guard let modified = values.contentModificationDate, modified >= start else { continue }
                    let size = UInt64(values.fileSize ?? 0)
                    var state = files[url.path] ?? FileState()
                    if state.offset == size && state.modified == modified { continue }
                    if size < state.offset || (size == state.offset && state.modified != modified) {
                        state = FileState()
                    }
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    try handle.seek(toOffset: state.offset)
                    while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
                        state.offset += UInt64(chunk.count)
                        state.pending.append(chunk)
                        while let newline = state.pending.firstIndex(of: 10) {
                            let line = state.pending[..<newline]
                            consume(Data(line), state: &state, start: start, end: end)
                            state.pending.removeSubrange(...newline)
                        }
                    }
                    state.modified = modified
                    files[url.path] = state
                } catch {
                    failed = true
                }
            }
        }
        guard !failed else { return nil }
        // Forks / archived copies may repeat the same timestamped usage event.
        // Count such copied records once across files, as well as within a file.
        var events: [String: Int64] = [:]
        for state in files.values where state.isOpenAI {
            events.merge(state.events) { max($0, $1) }
        }
        return LocalTodayTokenUsage(day: start, tokens: events.values.reduce(0, +))
    }

    private func consume(_ line: Data, state: inout FileState, start: Date, end: Date) {
        guard line.range(of: Data("\"token_count\"".utf8)) != nil
                || line.range(of: Data("\"session_meta\"".utf8)) != nil,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = object["payload"] as? [String: Any] else { return }
        if object["type"] as? String == "session_meta" {
            state.isOpenAI = (payload["model_provider"] as? String ?? "openai") == "openai"
            return
        }
        guard state.isOpenAI, object["type"] as? String == "event_msg",
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let usage = info["total_token_usage"] as? [String: Any],
              let total = (usage["total_tokens"] as? NSNumber)?.int64Value, total >= 0,
              let stamp = object["timestamp"] as? String,
              let timestamp = timestampFormatter.date(from: stamp) ?? secondsFormatter.date(from: stamp) else { return }
        let previous = state.previousTotal
        state.previousTotal = total
        guard timestamp >= start && timestamp < end else { return }
        let last = ((info["last_token_usage"] as? [String: Any])?["total_tokens"] as? NSNumber)?.int64Value
        let increment: Int64
        if let previous, total >= previous { increment = total - previous }
        else { increment = max(last ?? total, 0) }
        guard increment > 0 else { return }
        state.events["\(stamp)|\(total)|\(last ?? 0)"] = increment
    }
}
