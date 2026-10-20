import Foundation

public struct JSONRPCNotification: Sendable {
    public var method: String
    public var paramsJSON: Data?

    public init(method: String, paramsJSON: Data? = nil) {
        self.method = method
        self.paramsJSON = paramsJSON
    }

    public func paramsObject() -> Any? {
        guard let paramsJSON else { return nil }
        return try? JSONSerialization.jsonObject(with: paramsJSON)
    }
}

/// Persistent `codex app-server` JSON-RPC client over stdin/stdout.
///
/// One long-lived process per app session. All pipe I/O is serialized through this actor.
public actor CodexAppServerClient {
    public struct InitializeResult: Sendable {
        public var userAgent: String?
        public var codexHome: String?
        public var platformOs: String?
    }

    private struct Pending {
        var continuation: CheckedContinuation<Data, Error>
        var timeoutTask: Task<Void, Never>
    }

    private let clientName = "codex_meter"
    private let clientTitle = "Codex Meter"
    private let clientVersion = "1.2.0"

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var buffer = Data()
    private var nextRequestID = 1
    private var pending: [Int: Pending] = [:]
    private var notificationContinuations: [UUID: AsyncStream<JSONRPCNotification>.Continuation] = [:]
    private var isInitialized = false
    private var currentExecutable: URL?
    private var processGeneration: UUID?

    public init() {}

    public func running() -> Bool {
        process?.isRunning == true
    }

    public func notifications() -> AsyncStream<JSONRPCNotification> {
        let id = UUID()
        return AsyncStream { continuation in
            notificationContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeNotification(id) }
            }
        }
    }

    public func start(executable: URL, forceRestart: Bool = false) async throws -> InitializeResult {
        if !forceRestart, process?.isRunning == true, currentExecutable == executable, isInitialized {
            return InitializeResult(userAgent: nil, codexHome: nil, platformOs: nil)
        }
        await stop(sendTerminate: true)
        currentExecutable = executable
        try launch(executable: executable)
        let initialized = try await performInitialize()
        isInitialized = true
        AppLog.codex.info("Codex App Server initialized")
        return initialized
    }

    public func stop(sendTerminate: Bool = true) async {
        // Ignore delayed stdout and exit callbacks from this process after a restart.
        processGeneration = nil
        failAllPending(CodexClientError.cancelled)
        isInitialized = false
        stdinHandle?.readabilityHandler = nil
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        if sendTerminate, let process, process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(1.5)
            while process.isRunning && Date() < deadline {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            if process.isRunning {
                process.interrupt()
                kill(process.processIdentifier, SIGKILL)
            }
        }
        try? stdinHandle?.close()
        try? stdoutHandle?.close()
        try? stderrHandle?.close()
        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil
        buffer = Data()
    }

    public func request(method: String, params: Any? = nil, timeout: TimeInterval = 20) async throws -> Data {
        guard process?.isRunning == true, isInitialized else {
            throw CodexClientError.notConnected
        }
        let id = nextRequestID
        nextRequestID += 1
        var payload: [String: Any] = [
            "id": id,
            "method": method
        ]
        if let params {
            payload["params"] = params
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let timeoutTask = Task { [weak self] in
                let nanos = UInt64(max(timeout, 1) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                await self?.fail(id: id, error: CodexClientError.timeout(method))
            }
            pending[id] = Pending(continuation: continuation, timeoutTask: timeoutTask)
            do {
                try write(payload)
                AppLog.codex.debug("RPC → \(method, privacy: .public)")
            } catch {
                timeoutTask.cancel()
                pending.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    public func notify(method: String, params: Any? = nil) throws {
        var payload: [String: Any] = ["method": method]
        if let params {
            payload["params"] = params
        }
        try write(payload)
    }

    private func launch(executable: URL) throws {
        let process = Process()
        let generation = UUID()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())

        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "dumb"
        // Keep logs off stdout so they cannot break JSONL.
        environment["RUST_LOG"] = environment["RUST_LOG"] ?? "error"
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { await self?.handleTermination(status: status, generation: generation) }
        }

        try process.run()
        self.processGeneration = generation
        self.process = process
        self.stdinHandle = stdin.fileHandleForWriting
        self.stdoutHandle = stdout.fileHandleForReading
        self.stderrHandle = stderr.fileHandleForReading

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.ingest(data, generation: generation) }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.ingestStderr(data, generation: generation) }
        }

        AppLog.codex.info("Started Codex App Server pid=\(process.processIdentifier)")
    }

    private func performInitialize() async throws -> InitializeResult {
        let params: [String: Any] = [
            "clientInfo": [
                "name": clientName,
                "title": clientTitle,
                "version": clientVersion
            ]
        ]
        // initialize is allowed before the initialized flag is set.
        isInitialized = true
        let result: Data
        do {
            result = try await request(method: "initialize", params: params, timeout: 15)
        } catch {
            isInitialized = false
            throw error
        }
        try notify(method: "initialized")

        let decoded = (try? JSONSerialization.jsonObject(with: result)) ?? [:]
        let object = JSONValue.object(decoded) ?? [:]
        return InitializeResult(
            userAgent: JSONValue.string(object, keys: ["userAgent", "user_agent"]),
            codexHome: JSONValue.string(object, keys: ["codexHome", "codex_home"]),
            platformOs: JSONValue.string(object, keys: ["platformOs", "platform_os"])
        )
    }

    private func write(_ payload: [String: Any]) throws {
        guard let stdinHandle else {
            throw CodexClientError.notConnected
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        var line = data
        line.append(0x0A)
        try stdinHandle.write(contentsOf: line)
    }

    private func ingest(_ data: Data, generation: UUID) {
        guard processGeneration == generation else { return }
        if data.isEmpty {
            return
        }
        buffer.append(data)
        while let newline = buffer.firstRange(of: Data([0x0A])) {
            let line = buffer.subdata(in: buffer.startIndex..<newline.lowerBound)
            buffer.removeSubrange(buffer.startIndex...newline.lowerBound)
            if line.isEmpty { continue }
            handleLine(line)
        }
    }

    private func ingestStderr(_ data: Data, generation: UUID) {
        guard processGeneration == generation else { return }
        guard data.isEmpty == false,
              let text = String(data: data, encoding: .utf8),
              text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            return
        }
        let lowered = text.lowercased()
        if lowered.contains("token") || lowered.contains("authorization") || lowered.contains("cookie") || lowered.contains("bearer") {
            AppLog.codex.debug("app-server stderr redacted")
            return
        }
        AppLog.codex.debug("app-server stderr: \(text.prefix(400), privacy: .public)")
    }

    private func handleLine(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            AppLog.codex.error("Ignored non-JSON stdout line")
            return
        }

        if let id = intID(object["id"]), object["method"] == nil {
            if let errorObject = JSONValue.object(object["error"]) {
                let code = JSONValue.int(errorObject, keys: ["code"]) ?? -1
                let message = JSONValue.string(errorObject, keys: ["message"]) ?? "RPC error"
                fail(id: id, error: CodexClientError.rpc(code: code, message: message))
                return
            }
            let encoded: Data
            if let result = object["result"], !(result is NSNull) {
                encoded = (try? JSONSerialization.data(withJSONObject: result)) ?? Data("{}".utf8)
            } else {
                encoded = Data("{}".utf8)
            }
            succeed(id: id, result: encoded)
            return
        }

        if let method = object["method"] as? String {
            if object["id"] != nil {
                // Server-initiated request. This client does not handle approvals.
                if let id = object["id"] {
                    let reply: [String: Any] = [
                        "id": id,
                        "error": [
                            "code": -32601,
                            "message": "Method not found"
                        ]
                    ]
                    try? write(reply)
                }
                return
            }
            let paramsJSON: Data?
            if let params = object["params"], !(params is NSNull) {
                paramsJSON = try? JSONSerialization.data(withJSONObject: params)
            } else {
                paramsJSON = nil
            }
            let notification = JSONRPCNotification(method: method, paramsJSON: paramsJSON)
            for continuation in notificationContinuations.values {
                continuation.yield(notification)
            }
        }
    }

    private func succeed(id: Int, result: Data) {
        guard let item = pending.removeValue(forKey: id) else { return }
        item.timeoutTask.cancel()
        item.continuation.resume(returning: result)
    }

    private func fail(id: Int, error: Error) {
        guard let item = pending.removeValue(forKey: id) else { return }
        item.timeoutTask.cancel()
        item.continuation.resume(throwing: error)
    }

    private func failAllPending(_ error: Error) {
        let items = pending
        pending.removeAll()
        for item in items.values {
            item.timeoutTask.cancel()
            item.continuation.resume(throwing: error)
        }
    }

    private func handleTermination(status: Int32, generation: UUID) {
        guard processGeneration == generation else { return }
        processGeneration = nil
        AppLog.codex.error("Codex App Server exited with status \(status)")
        isInitialized = false
        failAllPending(CodexClientError.processExited(status))
        process = nil
        for continuation in notificationContinuations.values {
            let payload = try? JSONSerialization.data(withJSONObject: ["status": status])
            continuation.yield(JSONRPCNotification(method: "internal/processExited", paramsJSON: payload))
        }
    }

    private func removeNotification(_ id: UUID) {
        notificationContinuations[id]?.finish()
        notificationContinuations.removeValue(forKey: id)
    }

    private func intID(_ any: Any?) -> Int? {
        if let int = any as? Int { return int }
        if let number = any as? NSNumber { return number.intValue }
        if let string = any as? String { return Int(string) }
        return nil
    }
}
