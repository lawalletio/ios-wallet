import LaWalletKit
import SwiftUI

/// `/wallet/settings` — components/wallet/settings/settings-screen.tsx.
struct SettingsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var confirmRemove = false

    var body: some View {
        SettingsPage(title: t("settings.title"), onBack: { app.popToRoot() }) {
            GroupBox(label: t("settings.account")) {
                row(t("settings.myCards"), "credit-card", LW.mint, "settings.cards") { app.navigate(.cards) }
                SettingsRowDivider()
                row(t("settings.security"), "shield", LW.sun, "settings.security") { app.navigate(.security) }
                SettingsRowDivider()
                row(t("settings.remoteWallets"), "wallet", theme.preset.primary, "settings.remoteWallets") { app.navigate(.remoteWallets) }
                SettingsRowDivider()
                row(t("ios.instance.title"), "globe", LW.mint, "settings.instance", subtitle: app.instanceURL.host()) { app.navigate(.instance) }
            }
            GroupBox(label: t("settings.preferences")) {
                row(t("settings.language"), "languages", LW.foreground, "settings.language") { app.navigate(.language) }
                SettingsRowDivider()
                row(t("settings.currencies"), "coins", LW.sun, "settings.currencies") { app.navigate(.currencies) }
                SettingsRowDivider()
                row(t("settings.paymentSound"), "volume-2", LW.coral, "settings.paymentSound") { app.navigate(.paymentSound) }
            }
            GroupBox(label: t("settings.support")) {
                Link(destination: URL(string: "https://docs.lawallet.io")!) {
                    SettingsRow(title: t("settings.helpCenter"), icon: "life-buoy", color: LW.muted, external: true)
                }
                SettingsRowDivider()
                Link(destination: URL(string: "https://github.com/lawalletio/ios-wallet/issues")!) {
                    SettingsRow(title: t("settings.reportBug"), icon: "bot", color: LW.muted, external: true)
                }
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

    private func row(_ title: String, _ icon: String, _ color: Color, _ id: String, subtitle: String? = nil,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) { SettingsRow(title: title, icon: icon, color: color, subtitle: subtitle) }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                SettingsIsotype(size: 16)
                Text(app.communityName).font(LW.font(13, .semibold)).foregroundStyle(LW.foreground.opacity(0.75))
            }
            Text(t("settings.communityBy")).font(LW.font(12)).foregroundStyle(LW.muted)
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
            Text(t("settings.version", ["v": version])).font(LW.font(12)).foregroundStyle(LW.muted.opacity(0.8))
        }
        .padding(.vertical, 4)
    }
}

// MARK: shared settings chrome

/// Settings sub-page layout: pill header, scrolling column. The wallet tab bar is the root's fixed `NavTabbar`;
/// `tabbar` only reserves room for it. No background of its own — the route puts `AmbientBackground` behind every screen.
struct SettingsPage<Content: View>: View {
    let title: String
    var tabbar = true
    var onBack: (() -> Void)?
    var refresh: (() async -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            PillHeader(title: title, onBack: onBack)
            scroll
        }
    }

    @ViewBuilder private var scroll: some View {
        let s = ScrollView {
            VStack(alignment: .leading, spacing: 28) { content() }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, tabbar ? 150 : 32)
        }
        .scrollIndicators(.hidden)
        .lwSoftScrollEdges()
        if let refresh { s.refreshable { await refresh() } } else { s }
    }
}

/// Sentence-case muted label over a block (same rhythm as `GroupBox`).
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.content = content }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(LW.font(14, .semibold)).foregroundStyle(LW.muted).padding(.leading, 6)
            content()
        }
    }
}

/// iOS-style rounded icon tile, tinted with its own color. Lives inside surfaces — no glass of its own.
struct SettingsIconTile: View {
    let icon: String
    var color: Color = LW.foreground
    var size: CGFloat = 32
    var body: some View {
        Icon(icon, size: size * 0.53).foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Navigation row with a brand-tinted icon tile (the main Settings list).
struct SettingsRow: View {
    let title: String
    let icon: String
    var color: Color = LW.foreground
    var subtitle: String?
    var external = false
    var body: some View {
        HStack(spacing: 14) {
            SettingsIconTile(icon: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LW.font(16, .medium)).foregroundStyle(LW.foreground)
                if let subtitle { Text(subtitle).font(LW.font(13)).foregroundStyle(LW.muted).lineLimit(1) }
            }
            Spacer(minLength: 8)
            Icon(external ? "external-link" : "chevron-right", size: 15).foregroundStyle(LW.muted.opacity(0.8))
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }
}

/// Hairline that starts at the row text, past a 32 pt icon tile (iOS grouped-list inset).
struct SettingsRowDivider: View {
    var body: some View { RowDivider().padding(.leading, 46) }
}

/// Radio row used by Language and Payment sound.
struct SettingsChoiceRow: View {
    let title: String
    var subtitle: String?
    let checked: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(LW.font(16, .medium)).foregroundStyle(LW.foreground)
                    if let subtitle { Text(subtitle).font(LW.font(13)).foregroundStyle(LW.muted) }
                }
                Spacer()
                if checked { Icon("check", size: 18).foregroundStyle(theme.preset.primary).transition(.scale.combined(with: .opacity)) }
            }
            .padding(.horizontal, 18).padding(.vertical, 8).frame(minHeight: 58).contentShape(Rectangle())
            .animation(.snappy(duration: 0.2), value: checked)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? [.isSelected] : [])
    }
}

/// Status capsule: `color.opacity(0.16)` fill + colored text, no rim (shadcn `<Badge>` variants mapped to the glass palette).
struct SettingsBadge: View {
    /// `outline` reads as muted (Disabled, tags); `info` is mint (LNCurl).
    enum Style { case primary, secondary, outline, info, success, warning, destructive }
    let text: String
    var style: Style = .secondary
    var icon: String?
    @Environment(\.theme) private var theme

    init(_ text: String, _ style: Style = .secondary, icon: String? = nil) { self.text = text; self.style = style; self.icon = icon }

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Icon(icon, size: 11) }
            Text(text).font(LW.font(12, .semibold)).lineLimit(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .foregroundStyle(colors.fg)
        .background(colors.bg, in: Capsule())
    }

    private var colors: (fg: Color, bg: Color) {
        switch style {
        case .primary: (theme.preset.primary, theme.preset.primary.opacity(0.16))
        case .secondary: (LW.foreground, Color.white.opacity(0.10))
        case .outline: (LW.muted, LW.muted.opacity(0.16))
        case .info: (LW.mint, LW.mint.opacity(0.16))
        case .success: (LW.incoming, LW.incoming.opacity(0.16))
        case .warning: (LW.sun, LW.sun.opacity(0.16))
        case .destructive: (LW.destructiveText, LW.coral.opacity(0.16))
        }
    }
}

/// Empty / error placeholder on a glass surface.
struct SettingsEmptyState<Actions: View>: View {
    var icon: String?
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        VStack(spacing: 14) {
            if let icon {
                Icon(icon, size: 22).foregroundStyle(LW.muted).frame(width: 48, height: 48).background(Color.white.opacity(0.08), in: Circle())
            }
            VStack(spacing: 4) {
                Text(title).font(LW.font(16, .semibold)).foregroundStyle(LW.foreground)
                Text(message).font(LW.font(14)).foregroundStyle(LW.muted).multilineTextAlignment(.center).frame(maxWidth: 260)
            }
            actions()
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 36)
        .lwSurface()
    }
}

struct SettingsIsotype: View {
    var size: CGFloat
    @Environment(AppModel.self) private var app
    var body: some View {
        ZStack {
            Color.white.opacity(0.08)
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
        case "BLOCKED", "REJECTED", "EXPIRED", "FAILED", "DEAD": .destructive
        case "PENDING", "UNKNOWN": .warning
        default: .secondary
        }
    }
}

extension String {
    var trimmedValue: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonBlank: String? { trimmedValue.isEmpty ? nil : trimmedValue }
}
