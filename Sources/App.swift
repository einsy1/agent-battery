import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let store = QuotaStore()
    let ag = AGStore()
    let claude = CCStore()
    private var status: NSStatusItem!
    private let popover = NSPopover()
    private var wakeObserver: NSObjectProtocol?
    private var freshnessTimer: Timer?
    private var iconAnimation: Timer?
    private var wasRefreshing = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = status.button {
            button.target = self; button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        store.onChange = { [weak self] in self?.updateStatus() }
        ag.onChange = { [weak self] in self?.updateStatus() }
        claude.onChange = { [weak self] in self?.updateStatus() }
        QuotaKeeper.shared.onChange = { [weak self] in self?.updateStatus() }
        QuotaKeeper.shared.start()
        updateStatus()
        store.start()
        ag.refresh()
        claude.refresh()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.store.refresh(); self?.ag.refresh(); self?.claude.refresh(); QuotaKeeper.shared.check() }
        }
        freshnessTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store.updateFreshness(); self?.claude.updateFreshness(); self?.updateStatus() }
        }
        let firstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunched")
        UserDefaults.standard.set(true, forKey: "hasLaunched")
        if firstLaunch || ProcessInfo.processInfo.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.showPopover() }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover(); return true
    }
    func updateStatus() {
        guard let button = status.button else { return }
        let mode = store.displayMode
        let isRefreshing: Bool
        switch mode {
        case .codex: isRefreshing = store.loading
        case .claude: isRefreshing = claude.loading
        case .antigravity: isRefreshing = ag.loading
        case .both: isRefreshing = store.loading || ag.loading
        }
        let shouldStartAnim = isRefreshing && !wasRefreshing && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        wasRefreshing = isRefreshing
        if !isRefreshing {
            iconAnimation?.invalidate(); iconAnimation = nil
        }
        let target = mode.target(codex:store.menuRemaining,antigravity:ag.remaining,claude:claude.menuRemaining)
        func renderIcon(phase: Double = 0, refreshing: Bool = false) -> NSImage {
            mode == .both
                ? StatusIconRenderer.combined(style:store.iconStyle,codex:store.menuRemaining,gravity:ag.remaining,phase:phase,refreshing:refreshing)
                : StatusIconRenderer.image(style:store.iconStyle,remaining:target,phase:phase,refreshing:refreshing)
        }
        if shouldStartAnim && iconAnimation == nil {
            let start = Date()
            let duration = 0.65
            iconAnimation = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
                Task { @MainActor in
                    guard let self, let btn = self.status.button else { timer.invalidate(); return }
                    let elapsed = Date().timeIntervalSince(start)
                    if elapsed >= duration {
                        timer.invalidate()
                        self.iconAnimation = nil
                        btn.image = renderIcon(phase: 0, refreshing: false)
                    } else {
                        btn.image = renderIcon(phase: elapsed / duration, refreshing: true)
                    }
                }
            }
        } else if iconAnimation == nil {
            button.image = renderIcon()
        }
        button.font = .monospacedDigitSystemFont(ofSize:11,weight:.medium)
        let cached = (mode == .codex && store.cachedForMenu) || (mode == .claude && claude.cachedForMenu)
        button.title = mode != .both && store.showPercentage ? target.map { " \(cached ? "~" : "")\(Int($0))%" } ?? " —" : ""
        let codex = store.menuRemaining.map { "\(store.cachedForMenu ? "~" : "")\(Int($0))%" } ?? "—"
        let gravity = ag.remaining.map { "\(Int($0))%" } ?? "—"
        switch mode {
        case .codex: button.toolTip = "Codex · 五小时可用量 \(codex)"
        case .claude:
            let value = claude.menuRemaining.map { "\(claude.cachedForMenu ? "~" : "")\(Int($0))%" } ?? "—"
            button.toolTip = "Claude Code · 五小时可用量 \(value)"
        case .antigravity: button.toolTip = "Antigravity · \(AGQuota.groupTitle(ag.selectedGroup)) · 本组较低余量 \(gravity)"
        case .both:
            let positions = store.iconStyle == .ring ? "外 Codex · 内 AG" : store.iconStyle == .bars ? "上 Codex · 下 AG" : "左 Codex · 右 AG"
            button.toolTip = "Codex \(codex) · AG \(gravity)（\(AGQuota.groupTitle(ag.selectedGroup))）\n\(positions)"
        }
        button.toolTip = (button.toolTip ?? "") + "\n" + QuotaKeeper.shared.summary
        button.setAccessibilityLabel("\(mode.title) · \(store.iconStyle.title) · \(button.toolTip ?? "")")
    }
    @objc func togglePopover() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let refresh = NSMenuItem(title: "立即刷新", action: #selector(refresh), keyEquivalent: "r"); refresh.target = self
            menu.addItem(refresh); menu.addItem(.separator())
            let quit = NSMenuItem(title: "退出 agent battery", action: #selector(quit), keyEquivalent: "q"); quit.target = self
            menu.addItem(quit)
            status.menu = menu; status.button?.performClick(nil); status.menu = nil
        } else if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }
    @objc func refresh() { store.refresh(); ag.refresh(); claude.refresh() }
    @objc func quit() { NSApp.terminate(nil) }
    func showPopover() {
        guard let button = status.button else { return }
        if popover.isShown {
            popover.contentViewController?.view.window?.makeKey()
            return
        }
        if popover.contentViewController == nil {
            let controller = NSHostingController(rootView: QuotaPanel(store: store, ag: ag, claude: claude))
            controller.sizingOptions = [.preferredContentSize]
            popover.contentViewController = controller
        }
        store.refreshIfNeeded()
        claude.refreshIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NotificationCenter.default.post(name: .modelSourcePanelOpened, object: nil)
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        freshnessTimer?.invalidate()
        iconAnimation?.invalidate()
    }
}

@main struct Entry {
    static func main() {
        if CommandLine.arguments.contains("--ui-preview") {
            // Local UI inspection: do not start timers, login flows, or model calls.
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            app.appearance = NSAppearance(named: CommandLine.arguments.contains("--dark") ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 440),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "agent battery · 界面预览"
            window.contentViewController = NSHostingController(rootView: QuotaPanel(store: QuotaStore(), ag: AGStore(), claude: CCStore()))
            window.center()
            window.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
            app.run()
            return
        }
        if CommandLine.arguments.contains("--probe") {
            do {
                let response = try QuotaClient.fetch()
                let summary: [String: Any] = ["fiveHourRemaining": response.fiveHour?.remaining ?? -1,
                    "weeklyRemaining": response.weekly?.remaining ?? -1,
                    "resetTimestamp": response.fiveHour?.resetsAt ?? 0,
                    "windowMinutes": response.fiveHour?.windowDurationMins ?? 0]
                let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
                print(String(decoding: data, as: UTF8.self))
                exit(0)
            } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
        }
        if CommandLine.arguments.contains("--probe-claude") {
            // Real read-only check: prints plan windows, never credentials.
            do {
                let usage = try CCClient.fetch()
                let summary: [String: Any] = ["plan": usage.plan ?? "",
                    "fiveHourRemaining": usage.fiveHour?.remaining ?? -1,
                    "fiveHourReset": usage.fiveHour?.resetsAt ?? 0,
                    "weeklyRemaining": usage.weekly?.remaining ?? -1,
                    "weeklyReset": usage.weekly?.resetsAt ?? 0,
                    "scoped": usage.scoped.map { ["title": $0.title, "remaining": $0.window.remaining] }]
                let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
                print(String(decoding: data, as: UTF8.self))
                exit(0)
            } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
