import AppKit
import SwiftUI
import Combine
import Darwin

struct DeepSeekBalance: Decodable, Identifiable {
    let currency: String
    let total_balance: String
    let granted_balance: String
    let topped_up_balance: String
    var id: String { currency }
}

private struct DeepSeekReport: Decodable {
    let status: String
    let message: String?
    let is_available: Bool?
    let balances: [DeepSeekBalance]?
}

@MainActor final class DeepSeekStore: ObservableObject {
    static let shared = DeepSeekStore()
    @Published private(set) var loading = false
    @Published private(set) var status = "idle"
    @Published private(set) var message = "尚未查询"
    @Published private(set) var balances: [DeepSeekBalance] = []
    @Published private(set) var available = true
    @Published private(set) var updatedAt: Date?

    func refresh(force: Bool = false) {
        guard !loading, !CommandLine.arguments.contains("--ui-preview") else { return }
        if !force, let updatedAt, Date().timeIntervalSince(updatedAt) < 300 { return }
        loading = true
        Task {
            do {
                let report = try await Task.detached(priority: .utility) { try Self.fetch() }.value
                status = report.status
                message = report.message ?? ""
                balances = report.status == "ready" ? report.balances ?? [] : []
                available = report.is_available ?? false
                updatedAt = Date()
            } catch {
                status = "error"; balances = []; updatedAt = Date()
                message = "余额查询失败，请稍后重试"
            }
            loading = false
        }
    }

    nonisolated private static func fetch() throws -> DeepSeekReport {
        guard let helper = Bundle.main.url(forResource: "balance", withExtension: "py", subdirectory: "DeepSeek") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-B", helper.path]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardOutput = output
        try process.run()
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        let deadline = Date().addingTimeInterval(30)
        var data = Data()
        while Date() < deadline {
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            let ready = poll(&descriptor, 1, 200)
            if ready < 0 { if errno == EINTR { continue }; break }
            if ready == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = bytes.withUnsafeMutableBytes { Darwin.read(descriptor.fd, $0.baseAddress, $0.count) }
            if count == 0 { return try JSONDecoder().decode(DeepSeekReport.self, from: data) }
            if count < 0 { if errno == EINTR { continue }; break }
            data.append(contentsOf: bytes.prefix(count))
            if data.count > 65536 { break }
        }
        throw CocoaError(.fileReadUnknown)
    }
}

struct DeepSeekBalanceView: View {
    @ObservedObject private var store = DeepSeekStore.shared
    @State private var expanded = false
    @State private var saving = false
    @State private var keyError: String?
    private let timer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    var theme: PanelTheme = .bento
    var accent: Color = .primary

    var body: some View {
        Group {
            if theme == .bento {
                content.padding(16)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
            } else {
                GlassCard(cornerRadius: theme == .hud ? 18 : 20, padding: 16) { content }
            }
        }
        .onAppear { store.refresh() }
        .onReceive(timer) { _ in store.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .deepSeekKeyChanged)) { _ in store.refresh(force: true) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("账户余额", systemImage: "creditcard.fill")
                    .font(.headline).foregroundStyle(accent)
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Menu {
                    Button("配置或更新 API Key…", action: configureKey)
                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.secondary) }
                    .menuStyle(.borderlessButton).fixedSize().disabled(saving)
                    .help("配置 DeepSeek API Key").accessibilityLabel("DeepSeek 设置")
            }
            if store.status == "ready" {
                ForEach(store.balances) { balance in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(balance.currency == "CNY" ? "人民币" : "美元").font(.body)
                            Spacer()
                            Text(balance.total_balance)
                                .font(.system(size: 28, weight: .medium)).monospacedDigit()
                                .foregroundStyle(accent)
                        }
                        Text("可用余额 · \(balance.currency)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !store.available {
                    Label("当前余额不可用于 API 调用", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
                Divider()
                DisclosureGroup("余额明细", isExpanded: $expanded) {
                    ForEach(store.balances) { balance in
                        VStack(spacing: 8) {
                            HStack { Text("赠金"); Spacer(); Text("\(balance.granted_balance) \(balance.currency)").monospacedDigit() }
                            HStack { Text("充值余额"); Spacer(); Text("\(balance.topped_up_balance) \(balance.currency)").monospacedDigit() }
                        }.font(.callout).foregroundStyle(.secondary).padding(.top, 8)
                    }
                }.font(.callout)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("可用余额").font(.body)
                    Spacer()
                    Text("—").font(.system(size: 28, weight: .medium))
                }
                Text(store.loading ? "正在查询余额…" : store.message)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if store.status == "unconfigured" {
                    Button("配置 API Key…", action: configureKey).disabled(saving)
                }
            }
            if let keyError { Text(keyError).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func configureKey() {
        guard let key = ModelSourceRow.promptForKey() else { return }
        saving = true; keyError = nil
        Task { @MainActor in
            do {
                let result = try await Task.detached { try ModelSourceRow.invoke("key", codex: nil, key: key) }.value
                if result.code == 0 {
                    NotificationCenter.default.post(name: .deepSeekKeyChanged, object: nil)
                } else { keyError = "Key 保存失败，请重试" }
            } catch { keyError = "Key 保存失败，请重试" }
            saving = false
        }
    }
}

extension Notification.Name {
    static let deepSeekKeyChanged = Notification.Name("deepSeekKeyChanged")
}
