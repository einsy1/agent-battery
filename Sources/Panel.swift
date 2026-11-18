import SwiftUI
import AppKit

// MARK: - Apple Design System & Color Logic
//
// Following Apple HIG (Deference, Clarity, Depth & the 90/10 Monochrome Rule):
// - In "Apple Native (原生克制)" mode (default):
//   1. Surfaces & Cards are 100% neutral translucent glass (never tinted green/purple).
//   2. Typography, Numbers, Icons & Badges use strict monochrome hierarchy (.primary / .secondary / .tertiary).
//   3. Color is reserved strictly (10%) for the quantitative data fill (Apple Battery Green when healthy,
//      Apple Warm Amber when <= 15%, and calm neutral/slate for secondary bars).
// - In "Cyber Dual-Tone (极客双色 - 保留版)" mode:
//   Preserves the Emerald + Violet dual-accent look as an optional style.

enum ColorPhilosophy: String, CaseIterable, Identifiable {
    case appleHIG = "appleHIG"
    case cyberDual = "cyberDual"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .appleHIG: return "原生克制 (Apple HIG)"
        case .cyberDual: return "极客双色 (保留版)"
        }
    }
}

enum ThemePalette {
    // Apple HIG Semantic Colors (macOS System Battery Palette)
    static let appleGreen = Color(red: 0.17, green: 0.78, blue: 0.45)
    static let appleAmber = Color(red: 0.96, green: 0.60, blue: 0.14)

    // Cyber Dual-Tone Colors (Preserved from previous version)
    static let codexMint = Color(red: 0.06, green: 0.78, blue: 0.56)
    static let codexCyan = Color(red: 0.04, green: 0.72, blue: 0.86)
    static let agViolet = Color(red: 0.62, green: 0.38, blue: 0.98)
    static let agIndigo = Color(red: 0.42, green: 0.40, blue: 0.96)
    static let agPink = Color(red: 0.92, green: 0.36, blue: 0.68)
}

// MARK: - Native Frosted & Liquid Glass Materials

struct FrostedBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 20
    var tint: Color? = nil
    var borderTint: Color? = nil
    var isFocused: Bool = false
    var padding: CGFloat = 15
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let inner = content.padding(padding)
        let strokeTop: Color = borderTint?.opacity(0.6)
            ?? .white.opacity(reduceTransparency ? 0.10 : (isFocused ? 0.38 : 0.20))
        let strokeBottom: Color = borderTint?.opacity(0.18)
            ?? .primary.opacity(isFocused ? 0.16 : 0.07)

        if #available(macOS 26.0, *), !reduceTransparency {
            inner
                .background {
                    if let tint {
                        shape.fill(
                            LinearGradient(
                                colors: [tint.opacity(0.09), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    } else if isFocused {
                        shape.fill(Color.primary.opacity(0.035))
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [strokeTop, strokeBottom, .white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: (borderTint != nil || isFocused) ? 1.15 : 0.8
                    )
                )
        } else {
            inner
                .background {
                    if reduceTransparency {
                        shape.fill(Color(nsColor: .controlBackgroundColor))
                    } else {
                        ZStack {
                            shape.fill(.ultraThinMaterial)
                            shape.fill(Color.primary.opacity(isFocused ? 0.055 : 0.025))
                            if let tint {
                                shape.fill(
                                    LinearGradient(
                                        colors: [tint.opacity(0.10), .clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            }
                        }
                    }
                }
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [strokeTop, strokeBottom, .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: (borderTint != nil || isFocused) ? 1.15 : 0.8
                    )
                )
        }
    }
}

struct RecessedWell<Content: View>: View {
    var cornerRadius: CGFloat = 13
    var padding: CGFloat = 11
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.05), lineWidth: 0.6)
            )
    }
}

// MARK: - Shared Interactive & Telemetry Components

struct HoverIconButton: View {
    let systemName: String
    var label: String? = nil
    var isSpinning: Bool = false
    var helpText: String
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4.5) {
                Image(systemName: systemName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .symbolEffect(.rotate, options: .repeating, isActive: isSpinning && !reduceMotion)
                    .contentTransition(.symbolEffect(.replace))
                if let label {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(hovered ? .primary : .secondary)
            .padding(.horizontal, label == nil ? 0 : 10)
            .frame(minWidth: 28, minHeight: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(.primary.opacity(hovered ? 0.10 : 0.05))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.primary.opacity(hovered ? 0.16 : 0.07), lineWidth: 0.6)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { hovered = isHovering }
        }
        .help(helpText)
        .accessibilityLabel(helpText)
    }
}

struct SettingsActionRow: View {
    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String?
    let trailingIcon: String
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(iconTint)
                    .frame(width: 24, height: 24)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                Image(systemName: trailingIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(hovered ? .secondary : .tertiary)
                    .offset(x: hovered ? 1.5 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.primary.opacity(hovered ? 0.06 : 0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.primary.opacity(hovered ? 0.10 : 0.045), lineWidth: 0.6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { hovered = isHovering }
        }
    }
}

struct TelemetryProgressBar: View {
    var value: Double
    var startColor: Color
    var endColor: Color
    var height: CGFloat = 7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let clamped = min(100, max(0, value))
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.primary.opacity(0.08))
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [startColor, endColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(clamped > 0 ? height : 0, (geometry.size.width - 3) * clamped / 100))
                    .padding(1.5)
                    .animation(reduceMotion ? nil : .spring(response: 0.65, dampingFraction: 0.84), value: clamped)
            }
        }
        .frame(height: height)
    }
}

struct SegmentedMatrixBar: View {
    var value: Double?
    var segments: Int = 10
    var activeColor: Color
    var height: CGFloat = 7.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let clamped = min(100, max(0, value ?? 0))
        let activeCount = value == nil ? 0 : Int(round((clamped / 100.0) * Double(segments)))
        HStack(spacing: 4) {
            ForEach(0..<segments, id: \.self) { index in
                let isLit = index < activeCount || (clamped > 0 && activeCount == 0 && index == 0)
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(isLit ? activeColor : Color.primary.opacity(0.08))
                    .frame(height: height)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.82), value: clamped)
    }
}

struct LiquidCapsuleTube: View {
    var fraction: Double
    var startColor: Color
    var endColor: Color
    var ready: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var sheen = false

    var body: some View {
        let clamped = min(1, max(0, fraction))
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.primary.opacity(0.07))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.11), lineWidth: 0.8)

                // Subtle 25% calibration ticks
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { idx in
                        Spacer()
                        if idx < 3 {
                            Rectangle()
                                .fill(.primary.opacity(0.07))
                                .frame(width: 1, height: 15)
                        }
                    }
                }
                .padding(.horizontal, 4)

                if ready && clamped > 0 {
                    let fillWidth = max(14, (geo.size.width - 6) * clamped)
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [startColor, endColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth, height: geo.size.height - 6)
                        .overlay(alignment: .top) {
                            Capsule()
                                .fill(.white.opacity(0.4))
                                .frame(height: 1.4)
                                .padding(.horizontal, 8)
                                .padding(.top, 2)
                        }
                        .overlay {
                            if !reduceMotion && !reduceTransparency {
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.clear, .white.opacity(0.24), .clear],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: 44)
                                    .rotationEffect(.degrees(20))
                                    .offset(x: sheen ? 190 : -190)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .padding(3)
                        .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.84), value: clamped)
                }
            }
        }
        .frame(height: 26)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.2).delay(0.2)) { sheen = true }
        }
    }
}

// MARK: - Main Popover Panel

struct QuotaPanel: View {
    @ObservedObject var store: QuotaStore
    @ObservedObject var ag: AGStore
    @AppStorage("panelService") private var selectedService = 0
    @AppStorage("colorPhilosophy") private var colorModeRaw = ColorPhilosophy.appleHIG.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var appeared = false
    @State private var showSettings = false
    @State private var showOtherGroups = false

    private var isCyber: Bool { colorModeRaw == ColorPhilosophy.cyberDual.rawValue }

    private var codexLow: Bool {
        guard let rem = store.fiveHour?.remaining else { return false }
        return store.unavailable || rem <= 15
    }

    private var agLow: Bool {
        guard let rem = ag.remaining else { return false }
        return rem <= 15
    }

    // Semantic Data Fill Colors (Apple HIG vs Cyber Dual-Tone)
    private var codexBarStart: Color {
        if codexLow { return ThemePalette.appleAmber }
        return isCyber ? ThemePalette.codexMint : ThemePalette.appleGreen
    }
    private var codexBarEnd: Color {
        if codexLow { return ThemePalette.appleAmber.opacity(0.85) }
        return isCyber ? ThemePalette.codexCyan : ThemePalette.appleGreen.opacity(0.85)
    }
    private var weeklyBarStart: Color {
        isCyber ? ThemePalette.codexMint : Color.primary.opacity(0.55)
    }
    private var weeklyBarEnd: Color {
        isCyber ? ThemePalette.codexCyan : Color.primary.opacity(0.40)
    }
    private var agBarStart: Color {
        if agLow { return ThemePalette.appleAmber }
        return isCyber ? ThemePalette.agViolet : ThemePalette.appleGreen
    }
    private var agBarEnd: Color {
        if agLow { return ThemePalette.appleAmber.opacity(0.85) }
        return isCyber ? ThemePalette.agPink : ThemePalette.appleGreen.opacity(0.85)
    }

    private var panelTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)).combined(with: .offset(y: 4)),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
        )
    }

    var body: some View {
        VStack(spacing: 13) {
            header

            ZStack(alignment: .top) {
                if showSettings {
                    settingsContent
                        .transition(panelTransition)
                } else {
                    switch store.panelTheme {
                    case .bento:
                        bentoThemeView
                            .transition(panelTransition)
                    case .ultra:
                        ultraThemeView
                            .transition(panelTransition)
                    case .capsule:
                        capsuleThemeView
                            .transition(panelTransition)
                    case .hud:
                        hudThemeView
                            .transition(panelTransition)
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: showSettings)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: store.panelTheme)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selectedService)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: colorModeRaw)

            if !showSettings {
                footer
                    .transition(.opacity)
            }
        }
        .padding(16)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                FrostedBackdrop()
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 4)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { appeared = true }
        }
        .alert(
            "设置",
            isPresented: Binding(
                get: { store.settingsError != nil },
                set: { if !$0 { store.settingsError = nil } }
            )
        ) {
            Button("好", role: .cancel) { store.settingsError = nil }
        } message: {
            Text(store.settingsError ?? "")
        }
    }

    // MARK: - Unified Top Header (Restrained Monochrome Hierarchy)

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: showSettings ? "slider.horizontal.3" : "battery.75percent")
                .font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(showSettings ? "设置" : "agent battery").font(.headline)
                Text(showSettings ? "外观、菜单栏与服务" : "查看 AI 服务可用额度")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if showSettings {
                Button("完成", action: returnToQuota).keyboardShortcut(.cancelAction)
            } else {
                Button { store.refresh(); ag.refresh() } label: {
                    if store.loading || ag.loading {
                        ProgressView().controlSize(.small).frame(width: 16, height: 16)
                    } else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(store.loading || ag.loading)
                .keyboardShortcut("r", modifiers: .command)
                .help("刷新额度（⌘R）").accessibilityLabel("刷新额度")
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .keyboardShortcut(",", modifiers: .command)
                    .help("设置（⌘,）").accessibilityLabel("设置")
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.regular)
    }

    private var bentoThemeView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("当前查看的服务", selection: $selectedService) {
                Text("Codex").tag(0)
                Text("Antigravity").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if selectedService == 0 {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("可用额度").font(.headline)
                        Spacer()
                        if let plan = store.response?.bucket?.planType { Text(plan.capitalized).font(.caption).foregroundStyle(.secondary) }
                    }
                    nativeQuotaRow("五小时", value: store.menuRemaining, reset: store.fiveHour?.resetDate)
                    Divider()
                    nativeQuotaRow("每周", value: store.freshness == .unavailable ? nil : store.weekly?.remaining, reset: store.weekly?.resetDate)
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
                if let error = store.error {
                    errorBanner(message: error, retryDate: store.nextRetryAt)
                } else if store.loading && store.response == nil {
                    Label("正在读取额度…", systemImage: "arrow.triangle.2.circlepath").font(.callout).foregroundStyle(.secondary)
                }
                if store.freshness == .cached {
                    Label("显示最近缓存，正在尝试更新", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                if let error = ag.error { agConnectBanner(error: error) }
                if ag.loading && ag.quotas.isEmpty {
                    HStack { ProgressView().controlSize(.small); Text("正在读取额度…") }.font(.callout)
                } else if ag.remaining != nil {
                    Picker("模型组", selection: Binding(get: { ag.selectedGroup }, set: { ag.selectGroup($0) })) {
                        ForEach(ag.groups, id: \.self) { Text(AGQuota.groupTitle($0)).tag($0) }
                    }
                    ForEach(ag.quotas.filter { $0.groupKey == ag.selectedGroup }) { quota in
                        nativeQuotaRow(quota.windowTitle, value: quota.remaining, reset: quota.reset)
                    }
                } else if ag.error == nil && !ag.loading {
                    Label("暂无有效额度，请刷新或在设置中连接服务。", systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func nativeQuotaRow(_ title: String, value: Double?, reset: Date?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.body)
                Spacer()
                Text(value.map { "\(Int($0.rounded()))%" } ?? "—")
                    .font(.system(size: 28, weight: .medium)).monospacedDigit()
            }
            if let value {
                ProgressView(value: value, total: 100)
                    .tint(value <= 15 ? Color.orange : Color.green)
                    .accessibilityLabel(title + "可用额度")
                    .accessibilityValue("\(Int(value.rounded()))%")
            } else {
                Capsule().fill(.quaternary).frame(height: 4).accessibilityHidden(true)
            }
            Text(value == nil ? "暂无有效数据" : reset.map { "重置于 " + $0.formatted(.dateTime.month().day().hour().minute()) } ?? "未提供重置时间")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var bentoCodexTile: some View {
        let isFocused = selectedService == 0
        let fiveRem = store.fiveHour?.remaining ?? 0
        let badgeText = codexLow ? "LOW" : (store.response?.bucket?.planType?.uppercased() ?? "OK")
        let dotColor = codexLow ? ThemePalette.appleAmber : ThemePalette.appleGreen

        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84)) {
                selectedService = 0
            }
        } label: {
            GlassCard(
                cornerRadius: 20,
                tint: isCyber ? ThemePalette.codexMint : nil,
                borderTint: isCyber && isFocused ? ThemePalette.codexMint : nil,
                isFocused: isFocused,
                padding: 14
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HStack(spacing: 5.5) {
                            Circle()
                                .fill(dotColor)
                                .frame(width: 5.5, height: 5.5)
                            Text("CODEX")
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .tracking(0.4)
                                .foregroundStyle(isFocused ? .primary : .secondary)
                        }
                        Spacer()
                        Text(badgeText)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(codexLow ? ThemePalette.appleAmber : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(store.fiveHour.map { "\(Int($0.remaining.rounded()))" } ?? "—")
                            .font(.system(size: 38, weight: .regular, design: .rounded))
                            .tracking(-1.2)
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                        if store.fiveHour != nil {
                            Text("%")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("5H")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 1)

                    TelemetryProgressBar(
                        value: fiveRem,
                        startColor: codexBarStart,
                        endColor: codexBarEnd,
                        height: 7
                    )

                    HStack {
                        Text("周 \(store.weekly.map { "\(Int($0.remaining.rounded()))%" } ?? "—")")
                        Spacer()
                        if let date = store.fiveHour?.resetDate {
                            Text("\(date.formatted(date: .omitted, time: .shortened)) 重置")
                        } else {
                            Text(store.loading ? "同步中" : "待同步")
                        }
                    }
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Codex 额度概览")
    }

    private var bentoAGTile: some View {
        let isFocused = selectedService == 1
        let agRem = ag.remaining ?? 0
        let weeklyQuota = ag.quotas.first { $0.groupKey == ag.selectedGroup && $0.window == "weekly" }?.remaining
        let secondaryGroup = ag.groups.first { $0 != ag.selectedGroup }
        let secondaryRem = secondaryGroup.flatMap { AGQuota.overview(ag.quotas, group: $0) }
        let dotColor = ag.remaining == nil ? Color.secondary : (agLow ? ThemePalette.appleAmber : (isCyber ? ThemePalette.agViolet : ThemePalette.appleGreen))

        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84)) {
                selectedService = 1
            }
        } label: {
            GlassCard(
                cornerRadius: 20,
                tint: isCyber ? ThemePalette.agViolet : nil,
                borderTint: isCyber && isFocused ? ThemePalette.agViolet : nil,
                isFocused: isFocused,
                padding: 14
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HStack(spacing: 5.5) {
                            Circle()
                                .fill(dotColor)
                                .frame(width: 5.5, height: 5.5)
                            Text("ANTIGRAVITY")
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .tracking(0.3)
                                .foregroundStyle(isFocused ? .primary : .secondary)
                        }
                        Spacer()
                        Text("PRO")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(ag.remaining.map { "\(Int($0.rounded()))" } ?? "—")
                            .font(.system(size: 38, weight: .regular, design: .rounded))
                            .tracking(-1.2)
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                        if ag.remaining != nil {
                            Text("%")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(AGQuota.groupTitle(ag.selectedGroup).replacingOccurrences(of: " 模型", with: ""))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 1)

                    TelemetryProgressBar(
                        value: agRem,
                        startColor: agBarStart,
                        endColor: agBarEnd,
                        height: 7
                    )

                    HStack {
                        Text("周 \(weeklyQuota.map { "\(Int($0.rounded()))%" } ?? "—")")
                        Spacer()
                        if let secRem = secondaryRem {
                            Text("Claude \(Int(secRem.rounded()))%")
                        } else {
                            Text(ag.groups.count > 1 ? "共 \(ag.groups.count) 组" : "已连接")
                        }
                    }
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Antigravity 额度概览")
    }

    private var bentoCodexDetailCard: some View {
        VStack(spacing: 10) {
            GlassCard(cornerRadius: 20, padding: 14) {
                VStack(alignment: .leading, spacing: 11) {
                    // Neutral Header
                    HStack {
                        Text("Codex 窗口遥测")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\((store.response?.bucket?.planType ?? "PLUS").uppercased()) PLAN")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    // Recessed Box 1: 5-Hour Rolling Window + 10-Segment Matrix
                    RecessedWell(cornerRadius: 13, padding: 11) {
                        VStack(alignment: .leading, spacing: 8) {
                            TimelineView(.periodic(from: .now, by: 30)) { context in
                                HStack {
                                    Text(store.unavailable && !store.stale ? "五小时窗口 · 当前受限" : "五小时滚动窗口 (300m)")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(store.fiveHour.map { "\(Int($0.remaining.rounded()))%" } ?? "—") · \(resetText(store.fiveHour?.resetDate, now: context.date))")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.primary)
                                }
                            }
                            SegmentedMatrixBar(
                                value: store.fiveHour?.remaining,
                                segments: 10,
                                activeColor: codexBarStart,
                                height: 7.5
                            )
                        }
                    }

                    // Recessed Box 2: Weekly Window + Graphic Progress Bar
                    RecessedWell(cornerRadius: 13, padding: 11) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("每周总额度窗口 (7d)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                HStack(spacing: 4) {
                                    Text(store.weekly.map { "\(Int($0.remaining.rounded()))%" } ?? "—")
                                        .foregroundStyle(.primary)
                                    if let date = store.weekly?.resetDate {
                                        Text("· \(date.formatted(.dateTime.month().day()))重置")
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                            }
                            TelemetryProgressBar(
                                value: store.weekly?.remaining ?? 0,
                                startColor: weeklyBarStart,
                                endColor: weeklyBarEnd,
                                height: 6.5
                            )
                        }
                    }
                }
            }

            if let error = store.error {
                errorBanner(message: error, retryDate: store.nextRetryAt)
            }
        }
    }

    // MARK: - SCHEME B: Apple Watch Ultra Concentric Rings + Matrix

    private var ultraThemeView: some View {
        let codexVal = store.fiveHour?.remaining ?? 0
        let agVal = ag.remaining ?? 0
        let innerRingColor = isCyber ? ThemePalette.agViolet : Color.primary.opacity(0.65)

        return VStack(spacing: 12) {
            GlassCard(cornerRadius: 20, padding: 15) {
                HStack(spacing: 15) {
                    ZStack {
                        Circle()
                            .stroke(.primary.opacity(0.08), lineWidth: 8)
                            .frame(width: 86, height: 86)
                        Circle()
                            .trim(from: 0, to: min(1, max(0.02, codexVal / 100)))
                            .stroke(
                                codexBarStart,
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 86, height: 86)

                        Circle()
                            .stroke(.primary.opacity(0.08), lineWidth: 6.5)
                            .frame(width: 62, height: 62)
                        Circle()
                            .trim(from: 0, to: min(1, max(0.02, agVal / 100)))
                            .stroke(
                                innerRingColor,
                                style: StrokeStyle(lineWidth: 6.5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 62, height: 62)

                        VStack(spacing: 1) {
                            Text(store.fiveHour.map { "\(Int($0.remaining.rounded()))%" } ?? "—")
                                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary)
                            Text(ag.remaining.map { "\(Int($0.rounded()))%" } ?? "—")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Circle().fill(codexBarStart).frame(width: 5.5, height: 5.5)
                                Text("外环 · Codex 5H")
                                    .font(.system(size: 11.5, weight: .medium))
                                Spacer()
                                Text(store.fiveHour.map { "\(Int($0.remaining.rounded()))%" } ?? "—")
                                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                            }
                            TimelineView(.periodic(from: .now, by: 30)) { context in
                                Text("\(resetText(store.fiveHour?.resetDate, now: context.date)) · 周 \(store.weekly.map { "\(Int($0.remaining.rounded()))%" } ?? "—")")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }

                        Divider().opacity(0.35)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Circle().fill(innerRingColor).frame(width: 5.5, height: 5.5)
                                Text("内环 · Antigravity")
                                    .font(.system(size: 11.5, weight: .medium))
                                Spacer()
                                Text(ag.remaining.map { "\(Int($0.rounded()))%" } ?? "—")
                                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                            }
                            HStack {
                                Text("关注：\(AGQuota.groupTitle(ag.selectedGroup))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                Spacer()
                                if !ag.groups.isEmpty {
                                    Menu {
                                        ForEach(ag.groups, id: \.self) { grp in
                                            Button(AGQuota.groupTitle(grp)) { ag.selectGroup(grp) }
                                        }
                                    } label: {
                                        Text("切换 ▾")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                    .menuStyle(.borderlessButton)
                                    .fixedSize()
                                }
                            }
                        }
                    }
                }
            }

            GlassCard(cornerRadius: 20, padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    RecessedWell(cornerRadius: 12, padding: 10) {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("Codex · 五小时窗口")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(store.fiveHour.map { "\(Int($0.remaining.rounded()))" } ?? "—") / 100")
                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.primary)
                            }
                            SegmentedMatrixBar(
                                value: store.fiveHour?.remaining,
                                segments: 14,
                                activeColor: codexBarStart,
                                height: 8
                            )
                        }
                    }

                    RecessedWell(cornerRadius: 12, padding: 10) {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("Codex · 每周窗口")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(store.weekly.map { "\(Int($0.remaining.rounded()))%" } ?? "—")")
                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.primary)
                            }
                            TelemetryProgressBar(
                                value: store.weekly?.remaining ?? 0,
                                startColor: weeklyBarStart,
                                endColor: weeklyBarEnd,
                                height: 6.5
                            )
                        }
                    }

                    RecessedWell(cornerRadius: 12, padding: 10) {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("Antigravity · \(AGQuota.groupTitle(ag.selectedGroup))")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(ag.remaining.map { "\(Int($0.rounded()))" } ?? "—") / 100")
                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.primary)
                            }
                            SegmentedMatrixBar(
                                value: ag.remaining,
                                segments: 14,
                                activeColor: agBarStart,
                                height: 8
                            )
                        }
                    }
                }
            }

            if let error = store.error {
                errorBanner(message: error, retryDate: store.nextRetryAt)
            }
            if let agErr = ag.error {
                agConnectBanner(error: agErr)
            }
        }
    }

    // MARK: - SCHEME C: Pure Apple Horizontal Liquid Capsule

    private var capsuleThemeView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                capsuleTabButton(
                    index: 0,
                    title: "Codex",
                    badge: store.fiveHour.map { "\(Int($0.remaining.rounded()))%" } ?? "—",
                    dotColor: codexBarStart
                )
                capsuleTabButton(
                    index: 1,
                    title: "Antigravity",
                    badge: ag.remaining.map { "\(Int($0.rounded()))%" } ?? "—",
                    dotColor: agBarStart
                )
            }

            if selectedService == 0 {
                GlassCard(cornerRadius: 20, tint: isCyber ? ThemePalette.codexMint : nil, padding: 15) {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack(alignment: .lastTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.stale ? (store.loading && store.response == nil ? "正在连接" : "等待更新") : "五小时可用量")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                                HStack(alignment: .firstTextBaseline, spacing: 2) {
                                    Text(store.fiveHour.map { "\(Int($0.remaining.rounded()))" } ?? "—")
                                        .font(.system(size: 46, weight: .regular, design: .rounded))
                                        .tracking(-1.5)
                                        .monospacedDigit()
                                        .foregroundStyle(.primary)
                                        .contentTransition(.numericText())
                                    if store.fiveHour != nil {
                                        Text("%")
                                            .font(.system(size: 18, weight: .medium, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Spacer()
                            TimelineView(.periodic(from: .now, by: 30)) { context in
                                HStack(spacing: 4.5) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 10, weight: .medium))
                                    Text(resetText(store.fiveHour?.resetDate, now: context.date))
                                        .font(.system(size: 10.5, weight: .medium))
                                        .monospacedDigit()
                                }
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.primary.opacity(0.06), in: Capsule())
                            }
                        }

                        LiquidCapsuleTube(
                            fraction: (store.fiveHour?.remaining ?? 0) / 100,
                            startColor: codexBarStart,
                            endColor: codexBarEnd,
                            ready: store.fiveHour != nil
                        )

                        RecessedWell(cornerRadius: 13, padding: 11) {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Label("每周可用量", systemImage: "calendar")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if let date = store.weekly?.resetDate {
                                        Text("\(date.formatted(.dateTime.month().day().hour().minute())) 重置")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                    }
                                    Text(store.weekly.map { "\(Int($0.remaining.rounded()))%" } ?? "—")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(.primary)
                                }
                                TelemetryProgressBar(
                                    value: store.weekly?.remaining ?? 0,
                                    startColor: weeklyBarStart,
                                    endColor: weeklyBarEnd,
                                    height: 6.5
                                )
                            }
                        }
                    }
                }

                if let error = store.error {
                    errorBanner(message: error, retryDate: store.nextRetryAt)
                }
            } else {
                agDetailCard(compact: false)
            }
        }
    }

    private func capsuleTabButton(index: Int, title: String, badge: String, dotColor: Color) -> some View {
        let isSelected = selectedService == index
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84)) {
                selectedService = index
            }
        } label: {
            HStack {
                Circle().fill(dotColor).frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
                Text(badge)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.08 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(isSelected ? 0.16 : 0.06), lineWidth: 0.8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - SCHEME D: Raycast / Linear High-Density All-in-One HUD

    private var hudThemeView: some View {
        VStack(spacing: 11) {
            GlassCard(cornerRadius: 18, tint: isCyber ? ThemePalette.codexMint : nil, padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Circle().fill(codexBarStart).frame(width: 6, height: 6)
                        Text("OPENAI CODEX")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text(resetText(store.fiveHour?.resetDate, now: context.date))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    RecessedWell(cornerRadius: 11, padding: 9.5) {
                        hudMetricRow(
                            title: "五小时窗口 (300m)",
                            subtitle: store.fiveHour?.resetDate.map { "\($0.formatted(date: .omitted, time: .shortened)) 重置" } ?? "",
                            value: store.fiveHour?.remaining,
                            startColor: codexBarStart,
                            endColor: codexBarEnd
                        )
                    }

                    RecessedWell(cornerRadius: 11, padding: 9.5) {
                        hudMetricRow(
                            title: "每周总额度 (7d)",
                            subtitle: store.weekly?.resetDate.map { "\($0.formatted(.dateTime.month().day())) 重置" } ?? "",
                            value: store.weekly?.remaining,
                            startColor: weeklyBarStart,
                            endColor: weeklyBarEnd
                        )
                    }
                }
            }

            GlassCard(cornerRadius: 18, tint: isCyber ? ThemePalette.agViolet : nil, padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Circle().fill(agBarStart).frame(width: 6, height: 6)
                        Text("GOOGLE ANTIGRAVITY")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                        Spacer()
                        if !ag.groups.isEmpty {
                            Menu {
                                ForEach(ag.groups, id: \.self) { grp in
                                    Button(AGQuota.groupTitle(grp)) { ag.selectGroup(grp) }
                                }
                            } label: {
                                Text("关注：\(AGQuota.groupTitle(ag.selectedGroup)) ▾")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                    }

                    if ag.quotas.isEmpty {
                        if let agErr = ag.error {
                            agConnectBanner(error: agErr)
                        } else {
                            Text(ag.loading ? "正在同步 Antigravity 额度…" : "暂无 Antigravity 额度数据")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        RecessedWell(cornerRadius: 11, padding: 9.5) {
                            VStack(spacing: 9) {
                                ForEach(ag.quotas) { quota in
                                    let rowLow = quota.remaining <= 15
                                    hudMetricRow(
                                        title: "\(AGQuota.groupTitle(quota.groupKey)) · \(quota.windowTitle.replacingOccurrences(of: "可用量", with: ""))",
                                        subtitle: quota.reset.map { "\($0.formatted(.dateTime.month().day().hour().minute()))" } ?? "",
                                        value: quota.remaining,
                                        startColor: rowLow ? ThemePalette.appleAmber : agBarStart,
                                        endColor: rowLow ? ThemePalette.appleAmber.opacity(0.85) : agBarEnd
                                    )
                                }
                            }
                        }
                    }
                }
            }

            if let error = store.error {
                errorBanner(message: error, retryDate: store.nextRetryAt)
            }
        }
    }

    private func hudMetricRow(title: String, subtitle: String, value: Double?, startColor: Color, endColor: Color) -> some View {
        VStack(spacing: 5.5) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                Text(value.map { "\(Int($0.rounded()))%" } ?? "—")
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            TelemetryProgressBar(value: value ?? 0, startColor: startColor, endColor: endColor, height: 6)
        }
    }

    // MARK: - Shared Antigravity Detail Card & Banners

    private func agDetailCard(compact: Bool) -> some View {
        GlassCard(cornerRadius: 20, tint: isCyber ? ThemePalette.agViolet : nil, padding: 14) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Text("Antigravity 模型组配额")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Spacer()
                    if !ag.groups.isEmpty {
                        Picker("关注模型组", selection: Binding(get: { ag.selectedGroup }, set: { ag.selectGroup($0) })) {
                            ForEach(ag.groups, id: \.self) { group in
                                Text(AGQuota.groupTitle(group)).tag(group)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .controlSize(.small)
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: 165, alignment: .trailing)
                    }
                }

                if !compact {
                    HStack(alignment: .lastTextBaseline) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(ag.remaining.map { "\(Int($0.rounded()))" } ?? "—")
                                .font(.system(size: 42, weight: .regular, design: .rounded))
                                .tracking(-1.4)
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                            if ag.remaining != nil {
                                Text("%")
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("当前组较低余量")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(.primary.opacity(0.06), in: Capsule())
                    }

                    LiquidCapsuleTube(
                        fraction: (ag.remaining ?? 0) / 100,
                        startColor: agBarStart,
                        endColor: agBarEnd,
                        ready: ag.remaining != nil
                    )
                }

                if let error = ag.error {
                    agConnectBanner(error: error)
                }

                if !ag.quotas.isEmpty {
                    quotaRows(ag.selectedGroup)

                    if ag.groups.count > 1 {
                        let otherGroups = ag.groups.filter { $0 != ag.selectedGroup }
                        VStack(alignment: .leading, spacing: 7) {
                            Button {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84)) {
                                    showOtherGroups.toggle()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9, weight: .bold))
                                        .rotationEffect(.degrees(showOtherGroups ? 90 : 0))
                                    Text("其他模型组（\(otherGroups.count)）")
                                        .font(.system(size: 11, weight: .medium))
                                    Spacer()
                                    Text(showOtherGroups ? "收起" : "展开")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 3)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if showOtherGroups {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 9) {
                                        ForEach(otherGroups, id: \.self) { group in
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(AGQuota.groupTitle(group))
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundStyle(.secondary)
                                                quotaRows(group)
                                            }
                                        }
                                    }
                                    .padding(.trailing, 2)
                                }
                                .frame(maxHeight: 150)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                }
            }
        }
    }

    private func quotaRows(_ group: String) -> some View {
        let items = ag.quotas.filter { $0.groupKey == group }
        return VStack(spacing: 8) {
            ForEach(items) { quota in
                let isPrimary5h = quota.window == "5h"
                let barStart = quota.remaining <= 15 ? ThemePalette.appleAmber : (isPrimary5h ? agBarStart : weeklyBarStart)
                let barEnd = quota.remaining <= 15 ? ThemePalette.appleAmber.opacity(0.85) : (isPrimary5h ? agBarEnd : weeklyBarEnd)
                RecessedWell(cornerRadius: 12, padding: 10) {
                    VStack(alignment: .leading, spacing: 6.5) {
                        HStack(spacing: 6) {
                            Text(quota.windowTitle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let date = quota.reset {
                                Text("重置：\(date.formatted(.dateTime.month().day().hour().minute()))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            Text("\(Int(quota.remaining.rounded()))%")
                                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                        TelemetryProgressBar(
                            value: quota.remaining,
                            startColor: barStart,
                            endColor: barEnd,
                            height: 6.5
                        )
                    }
                }
            }
        }
        .opacity(ag.error == nil ? 1 : 0.55)
    }

    private func agConnectBanner(error: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                    .padding(.top, 1)
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                do { try AGCLI.connect() } catch { ag.error = error.localizedDescription }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.key.fill")
                    Text("连接 Antigravity（Google 官方登录）")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6.5)
                .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(.primary.opacity(0.14), lineWidth: 0.7)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(9)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func errorBanner(message: String, retryDate: Date?) -> some View {
        GlassCard(cornerRadius: 14, padding: 10) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ThemePalette.appleAmber)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2.5) {
                    Text(message)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.88))
                    if let retry = retryDate {
                        Text("下次重试：\(retry.formatted(date: .omitted, time: .standard))")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Clean Minimal Status Footer

    private var footer: some View {
        let isAnyLoading = store.loading || ag.loading
        let hintText = selectedService == 0 ? "Codex" : "Antigravity"
        return HStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                HStack(spacing: 6) {
                    Circle()
                        .fill(isAnyLoading || (selectedService == 0 ? store.stale : ag.remaining == nil) ? Color.secondary : ThemePalette.appleGreen)
                        .frame(width: 5.5, height: 5.5)
                    Text(
                        isAnyLoading
                            ? "正在同步额度…"
                            : "\(selectedService == 0 ? freshness(now: context.date) : (ag.updated.map { "更新于 " + $0.formatted(date: .omitted, time: .shortened) } ?? "尚未同步")) · \(hintText)"
                    )
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }
            }
            Spacer()
            Text("v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""))
                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
        .padding(.top, 1)
    }

    // MARK: - Settings View

    private var panelThemePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("色彩与面板布局")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("色彩风格", selection: $colorModeRaw) {
                    ForEach(ColorPhilosophy.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 155)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
                ForEach(PanelTheme.allCases) { theme in
                    let isSelected = store.panelTheme == theme
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82)) {
                            store.setPanelTheme(theme)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: theme.iconName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .frame(width: 24, height: 24)
                                .background(
                                    Color.primary.opacity(isSelected ? 0.10 : 0.05),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                )
                            VStack(alignment: .leading, spacing: 1) {
                                Text(theme.title)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                    .foregroundStyle(.primary)
                                Text(theme.subtitle)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8.5)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(isSelected ? 0.09 : 0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    Color.primary.opacity(isSelected ? 0.28 : 0.06),
                                    lineWidth: isSelected ? 1.1 : 0.6
                                )
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("面板主题：\(theme.title)")
                    .accessibilityValue(isSelected ? "已选择" : "未选择")
                }
            }
        }
    }

    private var iconStylePicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("状态栏图标样式（立即生效）")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 7) {
                ForEach(StatusIconStyle.allCases) { style in
                    let isSelected = store.iconStyle == style
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                            store.setIconStyle(style)
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Image(
                                nsImage: store.displayMode == .both
                                    ? StatusIconRenderer.combined(style: style, codex: 77, gravity: 50)
                                    : StatusIconRenderer.image(style: style, remaining: 77)
                            )
                            .renderingMode(.template)
                            .frame(width: 26, height: 18)
                            Text(style.title)
                                .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(isSelected ? 0.09 : 0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    Color.primary.opacity(isSelected ? 0.28 : 0.06),
                                    lineWidth: isSelected ? 1.1 : 0.6
                                )
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("状态栏图标：\(style.title)")
                    .accessibilityValue(isSelected ? "已选择" : "未选择")
                }
            }
        }
    }

    private var preferenceToggles: some View {
        VStack(spacing: 9) {
            if store.displayMode != .both {
                HStack {
                    Label("菜单栏显示百分比", systemImage: "percent")
                        .font(.system(size: 11.5, weight: .medium))
                    Spacer()
                    Toggle(
                        "菜单栏显示百分比",
                        isOn: Binding(get: { store.showPercentage }, set: { store.setPercentage($0) })
                    )
                    .labelsHidden()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                Divider().opacity(0.35)
            }
            HStack {
                Label("登录时自动启动", systemImage: "power.circle")
                    .font(.system(size: 11.5, weight: .medium))
                Spacer()
                Toggle(
                    "登录时启动",
                    isOn: Binding(get: { store.launchAtLogin }, set: { _ in store.toggleLogin() })
                )
                .labelsHidden()
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: store.displayMode)
    }

    private func returnToQuota() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            showSettings = false
        }
    }

    private var settingsContent: some View {
        Form {
            Section("外观") {
                Picker("面板布局", selection: Binding(get: { store.panelTheme }, set: { store.setPanelTheme($0) })) {
                    ForEach(PanelTheme.allCases) { Text($0.title).tag($0) }
                }
                Picker("色彩", selection: $colorModeRaw) {
                    ForEach(ColorPhilosophy.allCases) { Text($0.title).tag($0.rawValue) }
                }
            }
            Section {
                Picker("显示范围", selection: Binding(get: { store.displayMode }, set: { store.setDisplayMode($0) })) {
                    ForEach(StatusDisplayMode.allCases) { Text($0.title).tag($0) }
                }
                Picker("图标样式", selection: Binding(get: { store.iconStyle }, set: { store.setIconStyle($0) })) {
                    ForEach(StatusIconStyle.allCases) { Text($0.title).tag($0) }
                }
                preferenceToggles
            } header: { Text("菜单栏") } footer: { Text("显示范围仅影响菜单栏，不改变当前查看的服务。") }
            Section("Codex") {
                ModelSourceRow()
                DisclosureGroup("满额自动触发") { QuotaKeeperRow() }
                Button("管理登录…", action: openCodex)
            }
            Section("Antigravity") {
                Button("连接或重新登录…") {
                    do { try AGCLI.connect() } catch { store.settingsError = error.localizedDescription }
                }
                Text("在官方 CLI 中完成 Google 登录后刷新额度。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                DisclosureGroup("高级") {
                    Button("选择 Codex 程序…") { store.selectExecutable() }
                    Text(UserDefaults.standard.string(forKey: "codexPath") ?? "自动检测本机程序")
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Text("agent battery " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("退出") { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: min(540, (NSScreen.main?.visibleFrame.height ?? 800) - 160))
    }

    // MARK: - Formatting Helpers

    private func resetText(_ date: Date?, now: Date) -> String {
        guard let date else { return "等待额度信息" }
        let minutes = max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
        if minutes == 0 { return "即将重置" }
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分后重置" : "\(minutes) 分钟后重置"
    }

    private func freshness(now: Date) -> String {
        guard let updated = store.updatedAt else { return "尚未同步" }
        let minutes = max(0, Int(now.timeIntervalSince(updated) / 60))
        return minutes < 1 ? "刚刚更新" : "\(minutes) 分钟前更新"
    }

    private func openCodex() {
        for path in ["/Applications/Codex.app", "/Applications/ChatGPT.app"] where FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
            return
        }
    }
}
