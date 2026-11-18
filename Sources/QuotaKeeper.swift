import AppKit
import SwiftUI

private struct KeeperReport: Decodable {
    let message: String
    let failed: Bool
    let lastAttempt: Double?
    let outcome: String?
}

@MainActor final class QuotaKeeper: ObservableObject {
    static let shared = QuotaKeeper()
    @Published var enabled = UserDefaults.standard.object(forKey: "quotaKeeperEnabled") as? Bool ?? true
    @Published private(set) var busy = false
    @Published private(set) var message = "等待检查额度"
    @Published private(set) var lastAttempt: Date?
    @Published private(set) var lastOutcome: String?
    @Published private(set) var checkedAt: Date?
    @Published private(set) var failed = false
    var onChange: (() -> Void)?
    private var timer: Timer?
    var summary: String { enabled ? (busy ? "自动触发 · 正在检查" : "自动触发 · \(failed ? "检查失败" : "已开启")") : "自动触发 · 已关闭" }
    var outcomeText: String {
        switch lastOutcome {
        case "success": return "成功"
        case "failed": return "失败，冷却中"
        case "timeout": return "超时，冷却中"
        case "attempting": return "已尝试，等待确认"
        default: return "尚未触发"
        }
    }
    func start() {
        timer?.invalidate()
        timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        check()
    }
    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: "quotaKeeperEnabled")
        onChange?()
        if value { check() }
    }
    func check() {
        guard enabled, !busy else { return }
        busy = true; onChange?()
        let executable = QuotaClient.executable(custom: UserDefaults.standard.string(forKey: "codexPath"))
        Task {
            do {
                let report = try await Task.detached(priority: .utility) {
                    try Self.invoke(executable: executable)
                }.value
                message = report.message
                failed = report.failed
                lastAttempt = report.lastAttempt.map { Date(timeIntervalSince1970: $0) }
                lastOutcome = report.outcome
            } catch {
                failed = true
                message = error.localizedDescription
            }
            checkedAt = Date(); busy = false; onChange?()
        }
    }
    nonisolated private static func invoke(executable: URL?) throws -> KeeperReport {
        guard let executable,
              let helper = Bundle.main.url(forResource: "bridge", withExtension: "py", subdirectory: "QuotaKeeper") else {
            throw NSError(domain: "QuotaKeeper", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到 Codex 或自动触发组件"])
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-B", helper.path, "tick"]
        var env = ProcessInfo.processInfo.environment
        env["QUOTA_CODEX_BIN"] = executable.path
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        // Helper bounds each RPC (40s) and the model call (120s).
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "QuotaKeeper", code: 2, userInfo: [NSLocalizedDescriptionKey: "自动触发组件退出，请确认 Python 3 与 Codex 可用"])
        }
        return try JSONDecoder().decode(KeeperReport.self, from: data)
    }
}

struct QuotaKeeperRow: View {
    @ObservedObject private var keeper = QuotaKeeper.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("满额时自动轻量触发", isOn: Binding(get: { keeper.enabled }, set: { keeper.setEnabled($0) }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 11, weight: .medium))
            HStack {
                Text(keeper.summary)
                Spacer()
                if keeper.busy { ProgressView().controlSize(.mini) }
                Button("检查") { keeper.check() }
                    .disabled(!keeper.enabled || keeper.busy)
                    .controlSize(.mini)
            }
            if keeper.enabled {
                Text(keeper.message)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let checked = keeper.checkedAt {
                    Text("最近检查：\(checked.formatted(date: .omitted, time: .standard)) · 每 5 分钟检查")
                }
            }
            if let date = keeper.lastAttempt {
                Text("最近触发：\(date.formatted(date: .abbreviated, time: .shortened)) · \(keeper.outcomeText)")
            }
            Text("满额时请求回复 OK，消耗少量套餐额度。实际重置时间以服务端为准。")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}
