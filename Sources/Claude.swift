import Foundation
import AppKit
import SwiftUI
import Darwin

// MARK: - Model

/// One extra weekly window scoped to a model family (Opus, Sonnet, or a server-labelled bucket).
struct CCScopedWindow: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let window: QuotaWindow
}

struct CCUsage: Equatable {
    let fiveHour: QuotaWindow?
    let weekly: QuotaWindow?
    let scoped: [CCScopedWindow]
    let plan: String?
}

enum CCError: LocalizedError {
    case missingCLI, timeout, disconnected, notSignedIn, unavailable, server(String), invalidResponse, missingWindow
    var retryable: Bool {
        switch self {
        case .missingCLI, .notSignedIn, .invalidResponse, .missingWindow: return false
        case .server(let message): return !Self.isAuthentication(message)
        case .timeout, .disconnected, .unavailable: return true
        }
    }
    static func isAuthentication(_ message: String) -> Bool {
        let value = message.lowercased()
        return ["unauthorized", "authentication", "not logged in", "log in", "login", "sign in", "401", "oauth", "token expired"].contains { value.contains($0) }
    }
    var errorDescription: String? {
        switch self {
        case .missingCLI: return "未找到 Claude Code。请安装 Claude Code，或在设置中选择 claude 可执行文件。"
        case .timeout: return "连接超时，请检查网络后重试。"
        case .disconnected: return "Claude Code 连接已中断，请稍后重试。"
        case .notSignedIn: return "Claude Code 未使用 Claude 订阅账户登录（API Key 不提供套餐额度）。请点击连接完成登录后刷新。"
        case .unavailable: return "Claude 额度服务暂时未返回结果，将自动重试。"
        case .server(let message):
            if Self.isAuthentication(message) { return "Claude Code 登录状态需要更新，请重新连接后刷新。" }
            let value = message.lowercased()
            if value.contains("429") || value.contains("rate limit") || value.contains("too many") { return "额度查询暂时被限流，将自动重试。" }
            return "Claude 额度服务暂时未返回结果，将自动重试。"
        case .invalidResponse: return "Claude Code 返回的额度格式不兼容，请更新 Claude Code 或本应用。"
        case .missingWindow: return "当前账户没有返回五小时额度。请确认使用 Pro / Max 订阅登录。"
        }
    }
}

// MARK: - Client

/// Reads plan usage through Claude Code's own `get_usage` control request (stream-json SDK protocol).
/// The CLI does the authenticated call; this app never opens the keychain item or credential files,
/// and no prompt is sent, so no model request is made.
enum CCClient {
    static func executable(custom: String? = nil) -> URL? {
        let home = NSHomeDirectory()
        var candidates: [String?] = [custom,
            home + "/.local/bin/claude", home + "/.claude/local/claude",
            "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        // Claude desktop ships its own Claude Code build: prefer the newest installed version.
        let bundled = home + "/Library/Application Support/Claude/claude-code"
        let versions = ((try? FileManager.default.contentsOfDirectory(atPath: bundled)) ?? [])
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        for version in versions {
            let builds = (try? FileManager.default.contentsOfDirectory(atPath: bundled + "/" + version)) ?? []
            for build in builds.sorted() {
                candidates.append(bundled + "/" + version + "/" + build + "/claude.app/Contents/MacOS/claude")
            }
        }
        for path in candidates.compactMap({ $0 }) where !path.isEmpty {
            if FileManager.default.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    private static func date(_ raw: Any?) -> Double? {
        guard let text = raw as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = formatter.date(from: text) { return value.timeIntervalSince1970 }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)?.timeIntervalSince1970
    }

    private static func window(_ raw: Any?, minutes: Int?) -> QuotaWindow? {
        guard let object = raw as? [String: Any], let used = object["utilization"] as? NSNumber,
              CFGetTypeID(used) != CFBooleanGetTypeID(), used.doubleValue.isFinite else { return nil }
        // Utilization is "percentage used, 0-100"; values above 100 mean overage and clamp to empty.
        return QuotaWindow(usedPercent: min(100, max(0, used.doubleValue)), windowDurationMins: minutes, resetsAt: date(object["resets_at"]))
    }

    /// Parses the `response` object of a successful `get_usage` control response.
    static func parse(_ data: Data) throws -> CCUsage {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CCError.invalidResponse }
        let plan = root["subscription_type"] as? String
        guard let limits = root["rate_limits"] as? [String: Any] else {
            if root["rate_limits_available"] as? Bool == false { throw CCError.notSignedIn }
            if root.keys.contains("rate_limits") { throw CCError.unavailable }
            throw CCError.invalidResponse
        }
        var scoped: [CCScopedWindow] = []
        for (key, title) in [("seven_day_opus", "Opus 每周"), ("seven_day_sonnet", "Sonnet 每周")] {
            if let value = window(limits[key], minutes: 10080) { scoped.append(CCScopedWindow(title: title, window: value)) }
        }
        for row in limits["model_scoped"] as? [[String: Any]] ?? [] {
            guard let name = row["display_name"] as? String, !name.isEmpty, let value = window(row, minutes: 10080) else { continue }
            let title = name + " 每周"
            if !scoped.contains(where: { $0.title == title }) { scoped.append(CCScopedWindow(title: title, window: value)) }
        }
        let usage = CCUsage(fiveHour: window(limits["five_hour"], minutes: 300),
                            weekly: window(limits["seven_day"], minutes: 10080),
                            scoped: scoped, plan: plan)
        guard usage.fiveHour != nil else { throw CCError.missingWindow }
        return usage
    }

    static func fetch(custom: String? = nil, timeout: TimeInterval = 30) throws -> CCUsage {
        guard let executable = executable(custom: custom) else { throw CCError.missingCLI }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("claude-usage-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = executable
        // No prompt, tools, MCP servers, slash commands or saved transcript: this session only answers get_usage.
        process.arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                             "--strict-mcp-config", "--no-session-persistence", "--disable-slash-commands", "--tools", ""]
        process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        for key in environment.keys where key == "CLAUDECODE" || key == "ANTHROPIC_API_KEY" || (key.hasPrefix("CLAUDE_CODE_") && key != "CLAUDE_CODE_OAUTH_TOKEN") {
            environment.removeValue(forKey: key)
        }
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["DISABLE_AUTOUPDATER"] = "1"
        // Claude Code looks up its keychain login by account name; launchd-started apps may lack USER.
        if (environment["USER"] ?? "").isEmpty { environment["USER"] = NSUserName() }
        if (environment["LOGNAME"] ?? "").isEmpty { environment["LOGNAME"] = NSUserName() }
        if (environment["HOME"] ?? "").isEmpty { environment["HOME"] = NSHomeDirectory() }
        process.environment = environment
        try process.run()
        let deadline = Date().addingTimeInterval(max(0.01, timeout))
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            let grace = Date().addingTimeInterval(0.3)
            while process.isRunning && Date() < grace { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
            try? FileManager.default.removeItem(at: directory)
        }
        func send(_ id: String, _ request: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: ["type": "control_request", "request_id": id, "request": request])
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        try send("ab-init", ["subtype": "initialize"])
        var buffer = Data()
        while Date() < deadline {
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            let remainingMs = max(1, min(1_000, Int(deadline.timeIntervalSinceNow * 1_000)))
            let ready = poll(&descriptor, 1, Int32(remainingMs))
            if ready < 0 { if errno == EINTR { continue }; throw CCError.disconnected }
            if ready == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 65_536)
            let count = bytes.withUnsafeMutableBytes { Darwin.read(descriptor.fd, $0.baseAddress, $0.count) }
            if count < 0 { if errno == EINTR { continue }; throw CCError.disconnected }
            if count == 0 { throw CCError.disconnected }
            buffer.append(contentsOf: bytes.prefix(count))
            if buffer.count > 4_000_000 { throw CCError.disconnected }
            while let end = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: end)
                buffer.removeSubrange(...end)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      object["type"] as? String == "control_response",
                      let response = object["response"] as? [String: Any] else { continue }
                let id = response["request_id"] as? String
                if response["subtype"] as? String == "error" {
                    throw CCError.server(response["error"] as? String ?? "")
                }
                if id == "ab-init" {
                    try send("ab-usage", ["subtype": "get_usage", "skip_behaviors": true])
                } else if id == "ab-usage" {
                    guard let result = response["response"] else { throw CCError.invalidResponse }
                    return try parse(JSONSerialization.data(withJSONObject: result))
                }
            }
        }
        throw CCError.timeout
    }

    /// Opens Terminal with the official login command. The app never sees the OAuth exchange.
    @MainActor static func connect(custom: String? = nil) throws {
        guard let executable = executable(custom: custom) else { throw CCError.missingCLI }
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("QuotaCompanion")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let script = folder.appendingPathComponent("Connect-Claude-Code.command")
        let quoted = "'" + executable.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let text = """
        #!/bin/zsh
        cd "$(mktemp -d)" || exit 1
        echo '请在 Claude Code 官方登录流程中选择 Claude 订阅账户（Pro / Max）。完成后返回 agent battery 点击刷新。'
        \(quoted) auth login
        """
        try Data(text.utf8).write(to: script, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        NSWorkspace.shared.open(script)
    }
}

// MARK: - Store

@MainActor final class CCStore: ObservableObject {
    @Published private(set) var usage: CCUsage?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var loading = false
    @Published var error: String?
    @Published private(set) var nextRetryAt: Date?
    /// True when only the user can fix the error (install, log in, or choose a program).
    @Published private(set) var needsConnect = false
    var onChange: (() -> Void)?
    private let fetcher: @Sendable (String?) throws -> CCUsage
    private var timer: Timer?
    private var failures = 0
    private var lastAttempt: Date?
    private var allowCached = true
    init(fetcher: @escaping @Sendable (String?) throws -> CCUsage = { try CCClient.fetch(custom: $0) }) {
        self.fetcher = fetcher
    }
    var fiveHour: QuotaWindow? { usage?.fiveHour }
    var weekly: QuotaWindow? { usage?.weekly }
    var freshness: QuotaFreshness {
        RefreshPolicy.freshness(updatedAt: updatedAt, resetAt: fiveHour?.resetDate, hasError: error != nil, allowCached: allowCached)
    }
    var stale: Bool { freshness != .current }
    var menuRemaining: Double? { freshness == .unavailable ? nil : fiveHour?.remaining }
    var cachedForMenu: Bool { freshness == .cached }
    var unavailable: Bool { fiveHour?.remaining == 0 || weekly?.remaining == 0 }
    var customPath: String? { UserDefaults.standard.string(forKey: "claudePath") }
    func updateFreshness() { objectWillChange.send() }
    func refreshIfNeeded() {
        if lastAttempt.map({ Date().timeIntervalSince($0) >= 30 }) ?? true { refresh() }
    }
    func refresh() {
        guard !loading, !CommandLine.arguments.contains("--ui-preview") else { return }
        timer?.invalidate()
        loading = true; nextRetryAt = nil; lastAttempt = Date(); onChange?()
        let path = customPath, fetcher = self.fetcher
        Task { [self] in
            let result = await Task.detached(priority: .utility) { () -> Result<CCUsage, Error> in
                Result { try fetcher(path) }
            }.value
            loading = false
            var retryable = true
            switch result {
            case .success(let value):
                usage = value; updatedAt = Date(); error = nil; failures = 0; allowCached = true; needsConnect = false
            case .failure(let failure):
                error = failure.localizedDescription; failures += 1
                retryable = (failure as? CCError)?.retryable ?? true
                allowCached = retryable
                switch failure as? CCError {
                case .missingCLI?, .notSignedIn?: needsConnect = true
                case .server(let message)?: needsConnect = CCError.isAuthentication(message)
                default: needsConnect = false
                }
            }
            onChange?()
            var interval = error == nil ? RefreshPolicy.normalInterval : RefreshPolicy.retryInterval(failures: failures, retryable: retryable)
            if let reset = fiveHour?.resetDate, reset > Date() {
                interval = min(interval, max(2, reset.timeIntervalSinceNow + 2))
            }
            if error != nil { nextRetryAt = Date().addingTimeInterval(interval) }
            timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            if let timer { RunLoop.main.add(timer, forMode: .common) }
        }
    }
    func connect() {
        do { try CCClient.connect(custom: customPath) } catch { self.error = error.localizedDescription; needsConnect = true }
    }
    /// Returns an error message for the settings alert, or nil when a program was chosen.
    func selectExecutable() -> String? {
        let panel = NSOpenPanel()
        panel.title = "选择 claude 可执行文件"
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard FileManager.default.isExecutableFile(atPath: url.path) else { return "所选文件无法执行，请选择 claude 程序。" }
        UserDefaults.standard.set(url.path, forKey: "claudePath"); refresh()
        return nil
    }
}
