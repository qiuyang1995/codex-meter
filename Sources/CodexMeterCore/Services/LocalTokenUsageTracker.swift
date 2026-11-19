import CoreServices
import Foundation

public struct LocalTodayTokenUsage: Equatable, Sendable {
    public let day: Date
    public let tokens: Int64
    public let yesterdayTokens: Int64

    public init(day: Date, tokens: Int64, yesterdayTokens: Int64 = 0) {
        self.day = day
        self.tokens = tokens
        self.yesterdayTokens = yesterdayTokens
    }

    public func recentUsageByDay(now: Date, calendar: Calendar = .current) -> [Date: Int64] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let sampledDay = calendar.startOfDay(for: day)
        let sampledYesterday = calendar.date(byAdding: .day, value: -1, to: sampledDay)!
        return [sampledDay: tokens, sampledYesterday: yesterdayTokens]
            .filter { $0.key >= yesterday && $0.key <= today }
    }
}

/// File offsets keep log reads incremental and the actor keeps disk I/O off the UI actor.
public actor LocalTokenUsageTracker {
    private struct Cursor {
        var offset: UInt64 = 0
        var pending = Data()
        var modified: Date?
        var identifier: NSObject?

        mutating func read(_ url: URL, modified: Date, identifier: NSObject?, consume: (Data) -> Void) throws {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: offset)
            while !Task.isCancelled, let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
                offset += UInt64(chunk.count)
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 10) {
                    consume(Data(pending[..<newline]))
                    pending.removeSubrange(...newline)
                }
            }
            try Task.checkCancellation()
            self.modified = modified
            self.identifier = identifier
        }

        func requiresReset(size: UInt64, modified: Date, identity: NSObject?) -> Bool {
            identifier != identity || size < offset || (size == offset && self.modified != nil && self.modified != modified)
        }
    }

    private struct UsageEvent {
        let timestamp: Date
        let tokens: Int64
    }

    private struct FileState {
        var cursor = Cursor()
        var previousTotal: Int64?
        var events: [String: UsageEvent] = [:]
        var output = OutputRollout()
        var isOpenAI = true
    }

    private struct DesktopFileState {
        var cursor = Cursor()
        var timing = DesktopOutputTiming()
    }

    private static let usageMarkers = ["token_count", "session_meta"].map { Data(("\"" + $0 + "\"").utf8) }
    private static let outputMarkers = [
        "token_usage_record", "turn_context", "response_item", "item_completed", "task_started",
        "turn_started", "task_complete", "turn_aborted", "task_failed", "error", "stream_error"
    ].map { Data(("\"" + $0 + "\"").utf8) }
    private static let resourceKeys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey]

    private let root: URL
    private let desktopLogs: URL?
    private var outputHistory: OutputSpeedHistory
    private var day: Date?
    private var files: [String: FileState] = [:]
    private var desktopFiles: [String: DesktopFileState] = [:]
    private weak var watcher: SessionLogWatcher?
    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let secondsFormatter = ISO8601DateFormatter()

    public init(
        root: URL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"]
                        ?? NSHomeDirectory() + "/.codex", isDirectory: true),
        desktopLogs: URL? = nil,
        outputHistoryURL: URL? = nil
    ) {
        self.root = root
        self.desktopLogs = desktopLogs
        self.outputHistory = OutputSpeedHistory(url: outputHistoryURL)
    }

    public func reset() {
        day = nil
        files.removeAll()
    }

    public func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let paths = ["sessions", "archived_sessions"].map { root.appendingPathComponent($0, isDirectory: true) }
            + [desktopLogs].compactMap { $0 }
        let watcher = SessionLogWatcher(paths: paths, continuation: continuation)
        self.watcher = watcher
        continuation.onTermination = { _ in watcher.stop() }
        continuation.yield()
        return stream
    }

    public func savedOutputSpeeds(now: Date = Date()) -> [OutputTokenSpeed] {
        outputHistory.recent(at: now)
    }

    public func sample(now: Date = Date(), calendar: Calendar = .current) -> LocalTodayTokenUsage? {
        var watchedFiles: Set<String> = []
        let since = desktopLogs.map { _ in now.addingTimeInterval(-OutputSpeedHistory.retention) }
        let usage = readSessions(now: now, calendar: calendar, since: since, watchedFiles: &watchedFiles)
        watcher?.watchFiles(watchedFiles)
        return usage
    }

    public func sampleWithOutputSpeeds(
        now: Date? = nil,
        calendar: Calendar = .current
    ) -> (usage: LocalTodayTokenUsage?, speeds: [OutputTokenSpeed]) {
        let startedAt = now ?? Date()
        let since = startedAt.addingTimeInterval(-OutputSpeedHistory.retention)
        var watchedFiles: Set<String> = []
        let usage = readSessions(now: startedAt, calendar: calendar, since: desktopLogs == nil ? nil : since,
                                 watchedFiles: &watchedFiles)
        if let desktopLogs, !Task.isCancelled {
            readDesktopLogs(at: desktopLogs, since: since, now: startedAt, watchedFiles: &watchedFiles)
        }
        watcher?.watchFiles(watchedFiles)
        let sampledAt = now ?? Date()
        guard !Task.isCancelled else { return (usage, outputHistory.recent(at: sampledAt)) }

        var witnesses: [OutputItemIdentity: [OutputTimingWitness]] = [:]
        for state in desktopFiles.values {
            for (key, values) in state.timing.witnesses { witnesses[key, default: []].append(contentsOf: values) }
        }
        var validated: [String: OutputSpeedCandidate] = [:]
        var conflicts: Set<String> = []
        for state in files.values where state.isOpenAI {
            for (id, candidate) in state.output.candidates {
                guard candidate.measurement.completedAt >= since,
                      let evidence = witnesses[candidate.firstItem], candidate.isCorroborated(by: evidence) else { continue }
                if let previous = validated[id], previous != candidate { conflicts.insert(id) }
                validated[id] = candidate
            }
        }
        let measurements = validated.filter { !conflicts.contains($0.key) }.values.map(\.measurement)
        return (usage, outputHistory.record(measurements, at: sampledAt))
    }

    private func readSessions(
        now: Date, calendar: Calendar, since: Date?, watchedFiles: inout Set<String>
    ) -> LocalTodayTokenUsage? {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -1, to: today)!
        let end = calendar.date(byAdding: .day, value: 1, to: today)!
        if day != today {
            day = today
            files.removeAll()
        }
        let manager = FileManager.default
        guard manager.isReadableFile(atPath: root.appendingPathComponent("sessions").path) else { return nil }
        var failed = false
        for directory in ["sessions", "archived_sessions"] {
            let directoryURL = root.appendingPathComponent(directory)
            guard manager.fileExists(atPath: directoryURL.path) else { continue }
            guard let enumerator = manager.enumerator(at: directoryURL, includingPropertiesForKeys: Array(Self.resourceKeys),
                                                      options: [.skipsHiddenFiles], errorHandler: { _, _ in failed = true; return true })
            else { return nil }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                if Task.isCancelled { return nil }
                do {
                    let values = try url.resourceValues(forKeys: Self.resourceKeys)
                    guard let modified = values.contentModificationDate, modified >= min(start, since ?? start) else { continue }
                    if modified >= start { watchedFiles.insert(url.path) }
                    let identifier = values.fileResourceIdentifier as? NSObject
                    let size = UInt64(values.fileSize ?? 0)
                    var state = files[url.path] ?? FileState()
                    if state.cursor.requiresReset(size: size, modified: modified, identity: identifier) { state = FileState() }
                    if state.cursor.offset == size && state.cursor.modified == modified { continue }
                    var cursor = state.cursor
                    try cursor.read(url, modified: modified, identifier: identifier) { line in
                        consume(line, state: &state, start: start, end: end, since: since)
                    }
                    state.cursor = cursor
                    files[url.path] = state
                } catch is CancellationError {
                    return nil
                } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                    continue // A session can move to the archive while being enumerated.
                } catch {
                    failed = true
                }
            }
        }
        guard !failed else { return nil }
        // Forks / archived copies may repeat the same timestamped usage event.
        var events: [String: UsageEvent] = [:]
        for state in files.values where state.isOpenAI {
            events.merge(state.events) { $0.tokens >= $1.tokens ? $0 : $1 }
        }
        let totals = events.values.reduce(into: (today: Int64(0), yesterday: Int64(0))) { totals, event in
            if event.timestamp >= today { totals.today += event.tokens }
            else { totals.yesterday += event.tokens }
        }
        return LocalTodayTokenUsage(day: today, tokens: totals.today, yesterdayTokens: totals.yesterday)
    }

    private func readDesktopLogs(at root: URL, since: Date, now: Date, watchedFiles: inout Set<String>) {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(Self.resourceKeys),
                                                              options: [.skipsHiddenFiles]) else { return }
        for case let url as URL in enumerator where url.pathExtension == "log" && url.lastPathComponent.hasPrefix("codex-desktop-") {
            if Task.isCancelled { return }
            guard let values = try? url.resourceValues(forKeys: Self.resourceKeys),
                  let modified = values.contentModificationDate, modified >= since else { continue }
            if modified >= now.addingTimeInterval(-24 * 3600) { watchedFiles.insert(url.path) }
            let identifier = values.fileResourceIdentifier as? NSObject
            let size = UInt64(values.fileSize ?? 0)
            var state = desktopFiles[url.path] ?? DesktopFileState()
            if state.cursor.requiresReset(size: size, modified: modified, identity: identifier) { state = DesktopFileState() }
            if state.cursor.offset == size && state.cursor.modified == modified { continue }
            var cursor = state.cursor
            do {
                try cursor.read(url, modified: modified, identifier: identifier) { line in
                    state.timing.consume(line, parseDate: parseDate)
                }
                state.cursor = cursor
                desktopFiles[url.path] = state
            } catch is CancellationError {
                return
            } catch {
                desktopFiles.removeValue(forKey: url.path)
            }
        }
        desktopFiles = desktopFiles.filter { ($0.value.cursor.modified ?? .distantPast) >= since }
    }

    private func parseDate(_ value: String) -> Date? {
        timestampFormatter.date(from: value) ?? secondsFormatter.date(from: value)
    }

    private func consume(_ line: Data, state: inout FileState, start: Date, end: Date, since: Date?) {
        guard Self.usageMarkers.contains(where: { line.range(of: $0) != nil })
              || (since != nil && Self.outputMarkers.contains { line.range(of: $0) != nil }),
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = object["type"] as? String,
              let payload = object["payload"] as? [String: Any] else { return }
        if type == "session_meta" {
            state.isOpenAI = (payload["model_provider"] as? String ?? "openai") == "openai"
            return
        }
        guard state.isOpenAI, let stamp = object["timestamp"] as? String, let timestamp = parseDate(stamp) else { return }
        if let since { state.output.consume(type: type, payload: payload, at: timestamp, since: since) }
        guard type == "event_msg", payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let usage = info["total_token_usage"] as? [String: Any],
              let total = (usage["total_tokens"] as? NSNumber)?.int64Value, total >= 0 else { return }
        let previous = state.previousTotal
        state.previousTotal = total
        guard timestamp >= start && timestamp < end else { return }
        let last = ((info["last_token_usage"] as? [String: Any])?["total_tokens"] as? NSNumber)?.int64Value
        let increment: Int64
        if let previous, total >= previous { increment = total - previous }
        else { increment = max(last ?? total, 0) }
        guard increment > 0 else { return }
        state.events["\(stamp)|\(total)|\(last ?? 0)"] = UsageEvent(timestamp: timestamp, tokens: increment)
    }
}

private final class SessionLogWatcher: @unchecked Sendable {
    private final class Signal {
        let continuation: AsyncStream<Void>.Continuation

        init(_ continuation: AsyncStream<Void>.Continuation) {
            self.continuation = continuation
        }
    }

    private let queue = DispatchQueue(label: "com.local.CodexMeter.session-logs", qos: .utility)
    private let continuation: AsyncStream<Void>.Continuation
    private let timer: DispatchSourceTimer
    private var stream: FSEventStreamRef?
    private var fileSources: [String: DispatchSourceFileSystemObject] = [:]
    private var fileChangeQueued = false
    private var stopped = false

    init(paths: [URL], continuation: AsyncStream<Void>.Continuation) {
        self.continuation = continuation
        timer = DispatchSource.makeTimerSource(queue: queue)
        let signal = Signal(continuation)
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(signal).toOpaque(),
            retain: { pointer in
                guard let pointer else { return nil }
                return UnsafeRawPointer(Unmanaged<Signal>.fromOpaque(pointer).retain().toOpaque())
            },
            release: { pointer in
                if let pointer { Unmanaged<Signal>.fromOpaque(pointer).release() }
            },
            copyDescription: nil
        )
        let watchedPaths = paths.map { $0.resolvingSymlinksInPath().path }
        let flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer
        if let stream = FSEventStreamCreate(nil, { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<Signal>.fromOpaque(info).takeUnretainedValue().continuation.yield()
        }, &context, watchedPaths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.15, UInt32(flags)) {
            FSEventStreamSetDispatchQueue(stream, queue)
            if FSEventStreamStart(stream) {
                self.stream = stream
            } else {
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
            }
        }
        // Periodic reconciliation also advances the daily totals at midnight.
        timer.schedule(deadline: .now() + 5, repeating: 5, leeway: .milliseconds(100))
        timer.setEventHandler { continuation.yield() }
        timer.activate()
    }

    // FSEvents discovers new files, but can coalesce writes until a writer closes
    // its descriptor. Vnode notifications also observe writes to a file held open.
    func watchFiles(_ paths: Set<String>) {
        queue.async { [self] in
            guard !stopped else { return }
            for path in fileSources.keys.filter({ !paths.contains($0) }) {
                fileSources.removeValue(forKey: path)?.cancel()
            }
            for path in paths where fileSources[path] == nil {
                let descriptor = open(path, O_EVTONLY | O_CLOEXEC)
                guard descriptor >= 0 else { continue }
                let source = DispatchSource.makeFileSystemObjectSource(
                    fileDescriptor: descriptor, eventMask: [.write, .extend, .rename, .delete, .revoke], queue: queue
                )
                source.setEventHandler { [weak self] in
                    guard let self, let flags = self.fileSources[path]?.data else { return }
                    if !flags.isDisjoint(with: [.rename, .delete, .revoke]) {
                        self.fileSources.removeValue(forKey: path)?.cancel()
                    }
                    self.signalFileChange()
                }
                source.setCancelHandler { close(descriptor) }
                // Catch bytes written between the initial read and installing the file watch.
                source.setRegistrationHandler { [weak self] in self?.continuation.yield() }
                fileSources[path] = source
                source.activate()
            }
        }
    }

    private func signalFileChange() {
        guard !fileChangeQueued else { return }
        fileChangeQueued = true
        // The vnode signal can arrive before the append is visible to a reader.
        queue.asyncAfter(deadline: .now() + .milliseconds(20)) { [weak self] in
            guard let self, !self.stopped else { return }
            self.fileChangeQueued = false
            self.continuation.yield()
        }
    }

    func stop() {
        queue.async { [self] in
            stopped = true
            timer.cancel()
            for source in fileSources.values { source.cancel() }
            fileSources.removeAll()
            if let stream {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                self.stream = nil
            }
        }
    }
}
