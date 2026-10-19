import LaWalletKit
import SwiftUI

/// `/wallet/settings` — components/wallet/settings/settings-screen.tsx.
struct SettingsScreen: View {
    @Environment(AppModel.self) private var app
    @State private var confirmRemove = false

    var body: some View {
        SettingsPage(title: t("settings.title"), isRoot: true, onBack: { app.popToRoot() }) {
            GroupBox(label: t("settings.account")) {
                row(t("settings.myCards"), "settings.cards") { app.navigate(.cards) }
                RowDivider()
                row(t("settings.security"), "settings.security") { app.navigate(.security) }
                RowDivider()
                row(t("settings.remoteWallets"), "settings.remoteWallets") { app.navigate(.remoteWallets) }
                RowDivider()
                row(t("ios.instance.title"), "settings.instance", subtitle: app.instanceURL.host()) { app.navigate(.instance) }
            }
            GroupBox(label: t("settings.preferences")) {
                row(t("settings.language"), "settings.language") { app.navigate(.language) }
                RowDivider()
                row(t("settings.currencies"), "settings.currencies") { app.navigate(.currencies) }
                RowDivider()
                row(t("settings.paymentSound"), "settings.paymentSound") { app.navigate(.paymentSound) }
            }
            GroupBox(label: t("settings.support")) {
                Link(destination: URL(string: "https://docs.lawallet.io")!) { NavRow(title: t("settings.helpCenter"), external: true) }
                RowDivider()
                Link(destination: URL(string: "https://github.com/lawalletio/ios-wallet/issues")!) { NavRow(title: t("settings.reportBug"), external: true) }
            }
            footer.frame(maxWidth: .infinity)
            SettingsSection(t("settings.dangerZone")) {
                Button(t("settings.removeWallet")) { confirmRemove = true }
                    .buttonStyle(.lw(.destructive))
                    .accessibilityIdentifier("settings.removeWallet")
            }
        }
        .alert(t("settings.removeWallet"), isPresented: $confirmRemove) {
            Button(t("common.cancel"), role: .cancel) {}
            Button(t("settings.removeWallet"), role: .destructive) { app.logout() }
        } message: { Text(t("settings.removeWalletConfirm")) }
    }

    private func row(_ title: String, _ id: String, subtitle: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) { NavRow(title: title, subtitle: subtitle) }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                SettingsIsotype(size: 16)
                Text(app.communityName).font(LW.font(14, .semibold))
            }
            Text(t("settings.communityBy")).font(LW.font(12)).foregroundStyle(LW.muted)
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
            Text(t("settings.version", ["v": version])).font(LW.font(12)).foregroundStyle(LW.muted)
        }
        .padding(.vertical, 8)
    }
}

// MARK: shared settings chrome

/// Settings sub-page layout: pill header, scrolling column, wallet tab bar (every web settings page has `<NavTabbar />`).
struct SettingsPage<Content: View>: View {
    let title: String
    var isRoot = false
    var tabbar = true
    var onBack: (() -> Void)?
    var refresh: (() async -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                PillHeader(title: title, onBack: onBack)
                scroll
            }
            if tabbar { SettingsTabbar(isRoot: isRoot) }
        }
    }

    @ViewBuilder private var scroll: some View {
        let s = ScrollView {
            VStack(alignment: .leading, spacing: 24) { content() }
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, tabbar ? 140 : 32)
        }
        if let refresh { s.refreshable { await refresh() } } else { s }
    }
}

struct SettingsTabbar: View {
    var isRoot = false
    @Environment(AppModel.self) private var app
    var body: some View {
        NavTabbar(active: .settings, onHome: { app.popToRoot() }, onScan: { app.navigate(.scan) }, onSettings: {
            guard !isRoot else { return }
            app.popToRoot()
            app.navigate(.settings)
        })
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.content = content }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(LW.font(14, .medium)).foregroundStyle(LW.muted).padding(.leading, 4)
            content()
        }
    }
}

/// Radio row used by Language and Payment sound.
struct SettingsChoiceRow: View {
    let title: String
    var subtitle: String?
    let checked: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(LW.font(16, .medium)).foregroundStyle(LW.foreground)
                    if let subtitle { Text(subtitle).font(LW.font(12)).foregroundStyle(LW.muted) }
                }
                Spacer()
                if checked { Icon("check").foregroundStyle(LW.foreground) }
            }
            .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 56).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? [.isSelected] : [])
    }
}

/// shadcn `<Badge>` variants.
struct SettingsBadge: View {
    enum Style { case primary, secondary, outline, success, warning, destructive }
    let text: String
    var style: Style = .secondary
    var icon: String?
    @Environment(\.theme) private var theme

    init(_ text: String, _ style: Style = .secondary, icon: String? = nil) { self.text = text; self.style = style; self.icon = icon }

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Icon(icon, size: 11) }
            Text(text).font(LW.font(11, .semibold)).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundStyle(colors.fg)
        .background(colors.bg)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(colors.stroke))
    }

    private var colors: (fg: Color, bg: Color, stroke: Color) {
        switch style {
        case .primary: (theme.preset.primary, theme.preset.primary.opacity(0.15), theme.preset.primary.opacity(0.3))
        case .secondary: (LW.foreground, LW.secondary, .clear)
        case .outline: (LW.muted, .clear, LW.border)
        case .success: (LW.incoming, LW.incoming.opacity(0.12), LW.incoming.opacity(0.3))
        case .warning: (LW.gold, LW.gold.opacity(0.1), LW.gold.opacity(0.3))
        case .destructive: (LW.destructiveText, LW.destructive.opacity(0.15), LW.destructive.opacity(0.5))
        }
    }
}

/// Dashed empty / error placeholder (`border-dashed bg-card/40`).
struct SettingsEmptyState<Actions: View>: View {
    var icon: String?
    let title: String
    let message: String
    var dashed = true
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        VStack(spacing: 12) {
            if let icon {
                Icon(icon, size: 24).foregroundStyle(LW.muted).frame(width: 48, height: 48).background(LW.card).clipShape(Circle())
                    .overlay(Circle().strokeBorder(LW.border.opacity(0.5)))
            }
            VStack(spacing: 4) {
                Text(title).font(LW.font(16, .semibold))
                Text(message).font(LW.font(14)).foregroundStyle(LW.muted).multilineTextAlignment(.center).frame(maxWidth: 260)
            }
            actions()
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 40)
        .background(dashed ? LW.card.opacity(0.4) : LW.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if dashed { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(LW.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
        }
    }
}

struct SettingsIsotype: View {
    var size: CGFloat
    @Environment(AppModel.self) private var app
    var body: some View {
        ZStack {
            LW.card
            if let url = app.settings?.isotypo_url.flatMap({ URL(string: $0, relativeTo: app.endpoint) }) {
                RemoteImage(url: url, contentMode: .fit)
            } else {
                Image("isotypo").resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
    }
}

// MARK: formatting helpers

enum SettingsFormat {
    static var locale: Locale { Locale(identifier: L10n.shared.locale) }

    static func date(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(iso)) ?? (try? Date.ISO8601FormatStyle().parse(iso))
    }

    /// `Intl.RelativeTimeFormat(…, {style: 'short'})`.
    static func relative(_ iso: String?) -> String {
        guard let d = date(iso) else { return "—" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = locale
        return f.localizedString(for: d, relativeTo: Date())
    }

    static func shortDate(_ iso: String?) -> String {
        date(iso)?.formatted(.dateTime.day().month(.abbreviated).locale(locale)) ?? "—"
    }

    static func dateTime(_ iso: String?) -> String {
        date(iso)?.formatted(.dateTime.locale(locale)) ?? "—"
    }

    /// `formatMsats`: whole sats plus up to three msat decimals.
    static func msats(_ value: Double) -> String {
        (value / 1000).formatted(.number.precision(.fractionLength(0...3)).locale(locale)) + " sats"
    }

    static func percent(bps: Int) -> String { String(format: "%.2f%%", Double(bps) / 100) }

    /// Number typed on a decimal pad (accepts a comma separator).
    static func number(_ text: String) -> Double? { Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }

    /// `shared.forwarding.statuses.*`, else a humanized enum value.
    static func status(_ raw: String) -> String {
        let key = "shared.forwarding.statuses.\(raw.uppercased())"
        return L10n.shared.has(key) ? t(key) : raw.replacingOccurrences(of: "_", with: " ").lowercased().capitalized
    }

    /// Tone table from components/wallet/shared/forwarding-status.tsx.
    static func tone(_ raw: String) -> SettingsBadge.Style {
        switch raw.uppercased() {
        case "COMPLETED", "SUCCEEDED", "PAID", "SETTLED", "RETAINED": .success
        case "BLOCKED", "REJECTED", "EXPIRED", "FAILED": .destructive
        default: .secondary
        }
    }
}

extension String {
    var trimmedValue: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonBlank: String? { trimmedValue.isEmpty ? nil : trimmedValue }
}
