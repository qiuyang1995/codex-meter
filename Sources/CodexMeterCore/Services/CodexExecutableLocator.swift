import AppKit
import Foundation

public struct CodexExecutableLocator: Sendable {
    private let applicationURLs: [URL]?

    public init(applicationURLs: [URL]? = nil) {
        self.applicationURLs = applicationURLs
    }

    public func resolve(override: String? = nil, cached: String? = nil) -> URL? {
        let candidates = candidatePaths(override: override, cached: cached)
        for path in candidates {
            if let url = validatedExecutable(at: path) {
                AppLog.codex.info("Located Codex executable at \(url.path, privacy: .public)")
                return url
            }
        }
        if let fromShell = loginShellWhich() {
            AppLog.codex.info("Located Codex via login shell at \(fromShell.path, privacy: .public)")
            return fromShell
        }
        AppLog.codex.error("Codex executable was not found")
        return nil
    }

    public func candidatePaths(override: String? = nil, cached: String? = nil) -> [String] {
        let home = NSHomeDirectory()
        var paths: [String] = []
        if let override, override.isEmpty == false {
            paths.append(override)
        }
        if let cached, cached.isEmpty == false {
            paths.append(cached)
        }
        let applications = applicationURLs ?? installedApplications(home: home)
        paths.append(contentsOf: applications.flatMap { bundledExecutablePaths(in: $0) })
        paths.append(contentsOf: [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.npm-global/bin/codex",
            "\(home)/.codex/plugins/.plugin-appserver/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "\(home)/Applications/ChatGPT.app/Contents/Resources/codex",
            "\(home)/.volta/bin/codex",
            "\(home)/.cargo/bin/codex"
        ])
        paths.append(contentsOf: nvmCodexPaths(home: home))
        return unique(paths)
    }

    public func validatedExecutable(at path: String) -> URL? {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue {
            guard url.pathExtension.lowercased() == "app" else { return nil }
            return bundledExecutablePaths(in: url).lazy.compactMap { validatedExecutable(at: $0) }.first
        }
        guard FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        return url
    }

    private func installedApplications(home: String) -> [URL] {
        let workspace = NSWorkspace.shared
        var applications: [URL] = []
        if let registered = workspace.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            applications.append(registered)
        }
        applications.append(contentsOf: workspace.runningApplications
            .filter { $0.bundleIdentifier == "com.openai.codex" }
            .compactMap(\.bundleURL))
        for directory in ["/Applications", "\(home)/Applications"] {
            for name in ["Codex.app", "ChatGPT.app"] {
                applications.append(URL(fileURLWithPath: directory).appendingPathComponent(name))
            }
        }
        return applications
    }

    private func bundledExecutablePaths(in application: URL) -> [String] {
        [
            "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "Contents/Resources/codex-cli/bin/codex",
            "Contents/Resources/codex",
            "Contents/MacOS/codex"
        ].map { application.appendingPathComponent($0).path }
    }

    public func loginShellWhich() -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "command -v codex"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.environment = ProcessInfo.processInfo.environment
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let line = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              line.isEmpty == false
        else {
            return nil
        }
        return validatedExecutable(at: line)
    }

    private func nvmCodexPaths(home: String) -> [String] {
        let versions = "\(home)/.nvm/versions/node"
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: versions) else {
            return []
        }
        return contents
            .sorted()
            .reversed()
            .map { "\(versions)/\($0)/bin/codex" }
    }

    private func unique(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for path in paths {
            let normalized = (path as NSString).standardizingPath
            if seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }
        return result
    }
}
