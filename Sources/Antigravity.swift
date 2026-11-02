import Foundation

struct AGQuota: Identifiable {
    var id: String { name }
    let name: String
    let remaining: Double
    let reset: Date?
    var group: String = ""
    var window: String = ""
    var groupKey: String { group.isEmpty ? name : group }
    var windowTitle: String {
        switch window { case "5h": return "五小时可用量"; case "weekly": return "每周可用量"; default: return group.isEmpty ? "模型可用量" : "独立可用量" }
    }
    static func groupTitle(_ key: String) -> String {
        switch key { case "Gemini Models": return "Gemini 模型"; case "Claude and GPT models": return "Claude / GPT 模型"; default: return key }
    }
    static func overview(_ quotas: [AGQuota], group: String, now: Date = Date()) -> Double? {
        let selected = quotas.filter { $0.groupKey == group }
        guard !selected.isEmpty, selected.allSatisfy({ $0.reset == nil || $0.reset! > now }) else { return nil }
        return selected.map(\.remaining).min()
    }
}
enum AGError: LocalizedError {
    case notRunning, unavailable, hostAuthentication
    var errorDescription: String? {
        switch self {
        case .hostAuthentication: return "已检测到 Gemini 内置 Antigravity。请先点击连接完成官方 CLI 登录，再刷新真实额度。"
        case .notRunning: return "请打开并登录 Antigravity，再刷新。未发现本机额度服务。"
        case .unavailable: return "本机 Antigravity 未返回可验证的额度。服务版本或连接协议可能不兼容。"
        }
    }
}
struct AGClient {
    static func parse(_ data: Data) throws -> [AGQuota] {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let status = root["userStatus"] as? [String: Any] ?? root
        let config = status["cascadeModelConfigData"] as? [String: Any] ?? [:]
        let models = config["clientModelConfigs"] as? [[String: Any]] ?? []
        let values = models.compactMap { model -> AGQuota? in
            guard let info = model["quotaInfo"] as? [String: Any],
                  let fraction = info["remainingFraction"] as? NSNumber,
                  CFGetTypeID(fraction) != CFBooleanGetTypeID(),
                  fraction.doubleValue.isFinite, (0...1).contains(fraction.doubleValue),
                  let name = model["label"] as? String ?? model["displayName"] as? String else { return nil }
            let reset = (info["resetTime"] as? String).flatMap { raw -> Date? in
                let formatter = ISO8601DateFormatter()
                if let date = formatter.date(from:raw) { return date }
                formatter.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
                return formatter.date(from:raw)
            }
            return AGQuota(name: name, remaining: fraction.doubleValue * 100, reset: reset)
        }
        guard !values.isEmpty else { throw AGError.unavailable }
        // Duplicate labels cannot create unstable SwiftUI identities.
        return Dictionary(values.map { ($0.name, $0) }, uniquingKeysWith: { a,b in a.remaining < b.remaining ? a : b }).values.sorted { $0.name < $1.name }
    }
    private static func run(_ path: String, _ args: [String]) throws -> String {
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath:path); p.arguments = args
        p.standardOutput = out; p.standardError = FileHandle.nullDevice
        try p.run(); let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return String(decoding:data,as:UTF8.self)
    }
    static func fetch() async throws -> [AGQuota] {
        let listing = try run("/bin/ps",["-axo","pid=,uid=,args="])
        let embeddedHost = listing.split(separator:"\n").contains { $0.contains("Gemini.app/Contents/Helpers/agy") && $0.contains("--use_host_auth") }
        let rows = listing.split(separator:"\n").filter { $0.lowercased().contains("language_server") && $0.lowercased().contains("antigravity") }
        guard !rows.isEmpty else { throw embeddedHost ? AGError.hostAuthentication : AGError.notRunning }
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 2; sessionConfig.timeoutIntervalForResource = 3
        sessionConfig.connectionProxyDictionary = [:]
        let session = URLSession(configuration:sessionConfig)
        defer { session.invalidateAndCancel() }
        let deadline = Date().addingTimeInterval(12)
        for row in rows.prefix(3) {
            let parts = row.split(whereSeparator:{$0.isWhitespace})
            guard parts.count > 3, let pid = Int(parts[0]), let uid = UInt32(parts[1]), uid == getuid(),
                  let tokenIndex = parts.firstIndex(of:"--csrf_token"), tokenIndex + 1 < parts.count else { continue }
            let token = String(parts[tokenIndex+1])
            let portsText = try run("/usr/sbin/lsof",["-nP","-a","-p",String(pid),"-iTCP","-sTCP:LISTEN","-Fn"])
            let ports = Set(portsText.split(separator:"\n").filter{$0.hasPrefix("n")}.compactMap{Int($0.split(separator:":").last ?? "")}).sorted().prefix(6)
            for port in ports {
                guard Date() < deadline else { throw AGError.unavailable }
                // Only same-user loopback services; never send the local token to an external host.
                let url = URL(string:"http://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus")!
                var request = URLRequest(url:url); request.httpMethod = "POST"
                request.setValue("application/json",forHTTPHeaderField:"Content-Type")
                request.setValue("1",forHTTPHeaderField:"Connect-Protocol-Version")
                request.setValue(token,forHTTPHeaderField:"x-codeium-csrf-token")
                request.httpBody = Data("{\"metadata\":{\"ideName\":\"antigravity\",\"extensionName\":\"antigravity\",\"locale\":\"en\"}}".utf8)
                if let (data,response) = try? await session.data(for:request), (response as? HTTPURLResponse)?.statusCode == 200,
                   data.count < 1_000_000, let result = try? parse(data) { return result }
            }
        }
        throw AGError.unavailable
    }
}
import CoreFoundation

@MainActor final class AGStore: ObservableObject {
    @Published var quotas: [AGQuota] = []
    @Published var error: String?
    @Published var loading = false
    @Published var updated: Date?
    private var timer: Timer?
    var onChange: (() -> Void)?
    @Published private(set) var selectedGroupKey = UserDefaults.standard.string(forKey:"agSelectedGroup") ?? "Gemini Models"
    var groups: [String] {
        Array(Set(quotas.map(\.groupKey))).sorted {
            func order(_ s:String) -> Int { s == "Gemini Models" ? 0 : s.lowercased().contains("gemini") ? 1 : 2 }
            return order($0) == order($1) ? $0 < $1 : order($0) < order($1)
        }
    }
    var selectedGroup: String { groups.contains(selectedGroupKey) ? selectedGroupKey : groups.first ?? selectedGroupKey }
    func selectGroup(_ key: String) {
        guard groups.contains(key) else { return }
        selectedGroupKey = key; UserDefaults.standard.set(key,forKey:"agSelectedGroup"); onChange?()
    }
    var remaining: Double? {
        guard error == nil, let updated, Date().timeIntervalSince(updated) < 600 else { return nil }
        return AGQuota.overview(quotas,group:selectedGroup)
    }
    func refresh() {
        guard !loading else { return }; loading = true; timer?.invalidate()
        Task { [self] in
            do {
                if FileManager.default.isExecutableFile(atPath:AGCLI.executable) {
                    quotas = try await Task.detached(priority:.utility) { try AGCLI.fetch() }.value
                } else { quotas = try await AGClient.fetch() }
                error = nil; updated = Date()
            }
            catch { self.error = error.localizedDescription }
            loading = false; onChange?()
            timer = Timer(timeInterval:180,repeats:false) { [weak self] _ in Task { @MainActor in self?.refresh() } }
            if let timer { RunLoop.main.add(timer,forMode:.common) }
        }
    }
}
