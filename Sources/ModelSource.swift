import AppKit
import SwiftUI

private struct ModelSourceStatus: Decodable {
    let model: String
    let provider: String

    var title: String {
        if provider == "openai" { return model.isEmpty ? "ChatGPT" : "ChatGPT · \(model)" }
        switch model {
        case "deepseek-flash": return "DeepSeek Flash"
        case "deepseek-v4-pro": return "DeepSeek V4 Pro"
        default: return model.isEmpty ? provider : model
        }
    }
}

struct ModelSourceRow: View {
    @State private var status: ModelSourceStatus?
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Codex 默认模型")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Menu(status?.title ?? "选择模型源") {
                    Button("ChatGPT（恢复原设置）") { run("chatgpt") }
                    Button("DeepSeek Flash（V4.1-Flash-1017）") { run("flash") }
                    Button("DeepSeek V4 Pro") { run("pro") }
                    Divider()
                    Button("更新 DeepSeek API Key…") {
                        if let key = promptForKey() { run("key", key: key) }
                    }
                }
                .fixedSize()
                .disabled(busy)
            }
            if let message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let status, status.provider != "openai" {
                Text("Codex 百分比显示 ChatGPT 套餐额度")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .modelSourcePanelOpened)) { _ in refresh() }
    }

    private func refresh() {
        guard !busy else { return }
        run("status")
    }

    private func promptForKey() -> String? {
        let alert = NSAlert()
        alert.messageText = "DeepSeek API Key"
        alert.informativeText = "输入 DeepSeek API Key。agent battery 会将它存入 macOS 钥匙串。"
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "sk-…"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    private func run(_ action: String, key: String? = nil) {
        guard !busy else { return }
        busy = true
        if action != "status" { message = nil }
        let codex = QuotaClient.executable(custom: UserDefaults.standard.string(forKey: "codexPath"))
        Task { @MainActor in
            do {
                let outcome = try await Task.detached {
                    try Self.invoke(action, codex: codex, key: key)
                }.value
                busy = false
                if outcome.code == 3, action == "flash" || action == "pro" {
                    guard let key = promptForKey() else { return }
                    busy = true
                    try await Task.detached {
                        let result = try Self.invoke("key", codex: codex, key: key)
                        guard result.code == 0 else { throw ModelSourceError(result.text) }
                    }.value
                    busy = false
                    run(action)
                    return
                }
                guard outcome.code == 0 else { throw ModelSourceError(outcome.text) }
                if action == "status" {
                    status = try JSONDecoder().decode(ModelSourceStatus.self, from: Data(outcome.text.utf8))
                } else {
                    message = action == "key"
                        ? "Key 已保存。下次启动 Codex 时生效。"
                        : "配置已更新。新开 Codex CLI 会话或重启桌面端后生效。"
                    refresh()
                }
            } catch {
                busy = false
                message = error.localizedDescription
            }
        }
    }

    nonisolated private static func invoke(_ action: String, codex: URL?, key: String?) throws -> (code: Int32, text: String) {
        guard let helper = Bundle.main.url(forResource: "switcher", withExtension: "py", subdirectory: "ModelSwitcher") else {
            throw ModelSourceError("找不到模型切换组件，请重新构建 agent battery。")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-B", helper.path, action]
        if let codex { process.arguments?.append(contentsOf: ["--codex", codex.path]) }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        let output = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = key == nil ? FileHandle.nullDevice : input
        try process.run()
        if let key {
            input.fileHandleForWriting.write(Data((key + "\n").utf8))
            try input.fileHandleForWriting.close()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private struct ModelSourceError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message.isEmpty ? "模型切换失败。" : message }
}

extension Notification.Name {
    static let modelSourcePanelOpened = Notification.Name("modelSourcePanelOpened")
}
