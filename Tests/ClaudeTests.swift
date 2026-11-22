import AppKit
import Foundation

@main struct ClaudeTests {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        Task { @MainActor in
            func check(_ condition: Bool, _ name: String) { precondition(condition, name); print("PASS \(name)") }
            func rejects(_ json: String, _ expected: (CCError) -> Bool, _ name: String) {
                do { _ = try CCClient.parse(Data(json.utf8)); preconditionFailure(name) }
                catch let error as CCError { check(expected(error), name) }
                catch { preconditionFailure(name) }
            }

            let full = #"{"session":{"total_cost_usd":0},"subscription_type":"max","rate_limits_available":true,"rate_limits":{"five_hour":{"utilization":37.5,"resets_at":"2099-01-01T05:00:00.250Z"},"seven_day":{"utilization":12,"resets_at":"2099-01-07T00:00:00Z"},"seven_day_opus":{"utilization":80,"resets_at":null},"seven_day_sonnet":null,"model_scoped":[{"display_name":"Fable","utilization":104,"resets_at":"2099-01-07T00:00:00Z"},{"display_name":"Ghost","utilization":null,"resets_at":null}]},"behaviors":null}"#
            let usage = try! CCClient.parse(Data(full.utf8))
            check(usage.fiveHour?.remaining == 62.5 && usage.fiveHour?.windowDurationMins == 300, "five-hour utilization becomes remaining percentage")
            check(usage.fiveHour?.resetsAt == Date(timeIntervalSince1970: 4_070_926_800.25).timeIntervalSince1970, "fractional ISO reset time parses exactly")
            check(usage.weekly?.remaining == 88 && usage.weekly?.resetDate != nil, "weekly window and reset survive parsing")
            check(usage.plan == "max", "subscription type is carried for the plan badge")
            check(usage.scoped.map(\.title) == ["Opus 每周", "Fable 每周"], "model windows keep server order and skip null utilization")
            check(usage.scoped.last?.window.remaining == 0, "overage above 100% clamps to empty, never negative")

            rejects(#"{"subscription_type":null,"rate_limits_available":false,"rate_limits":null}"#, { if case .notSignedIn = $0 { return true }; return false }, "API key or signed-out session asks to connect")
            rejects(#"{"subscription_type":"pro","rate_limits_available":true,"rate_limits":null}"#, { if case .unavailable = $0 { return $0.retryable }; return false }, "temporarily missing limits retry instead of showing zero")
            rejects(#"{"rate_limits":{"seven_day":{"utilization":5}}}"#, { if case .missingWindow = $0 { return true }; return false }, "weekly alone cannot stand in for the five-hour window")
            rejects(#"{"rate_limits":{"five_hour":{"utilization":true}}}"#, { if case .missingWindow = $0 { return true }; return false }, "boolean utilization is not measured quota")
            rejects("not json", { if case .invalidResponse = $0 { return true }; return false }, "malformed output is incompatible, not empty")
            check(!CCError.server("401 Unauthorized").retryable && CCError.server("503").retryable, "auth errors stop retrying; server errors retry")

            let calls = Counter()
            let store = CCStore(fetcher: { _ in
                if calls.next() == 2 { throw CCError.notSignedIn }
                return try CCClient.parse(Data(full.utf8))
            })
            store.refresh()
            while store.loading { try? await Task.sleep(nanoseconds: 20_000_000) }
            check(store.menuRemaining == 62.5 && !store.needsConnect && store.error == nil, "store shows current Claude Code quota")
            store.refresh()
            while store.loading { try? await Task.sleep(nanoseconds: 20_000_000) }
            check(store.needsConnect && store.menuRemaining == nil && store.error != nil, "sign-out clears quota from the menu bar and offers login")
            check(StatusDisplayMode.claude.target(codex: 10, antigravity: 20, claude: 30) == 30, "Claude Code menu mode uses Claude quota")
            check(StatusDisplayMode.claude.target(codex: 10, antigravity: 20, claude: nil) == nil, "missing Claude quota never falls back to another service")
            exit(0)
        }
        application.run()
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
}
