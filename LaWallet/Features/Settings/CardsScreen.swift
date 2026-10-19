import LaWalletKit
import SwiftUI

/// `/wallet/settings/cards` — components/wallet/settings/cards-screen.tsx.
struct CardsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var cards: [Card]?
    @State private var failed = false
    @State private var pending: Set<String> = []
    @State private var linkPending: Set<String> = []
    /// Optimistic switch state while the PATCH is in flight.
    @State private var enabledOverride: [String: Bool] = [:]

    private var sorted: [Card] {
        (cards ?? []).sorted {
            if ($0.blocked ?? false) != ($1.blocked ?? false) { return !($0.blocked ?? false) }
            if ($0.disabled ?? false) != ($1.disabled ?? false) { return !($0.disabled ?? false) }
            return Self.name($0, "").localizedCompare(Self.name($1, "")) == .orderedAscending
        }
    }

    var body: some View {
        SettingsPage(title: t("settings.myCards"), refresh: load) {
            if cards == nil && !failed {
                skeleton
            } else if failed {
                SettingsEmptyState(title: t("settings.cardsScreen.errorTitle"), message: t("settings.cardsScreen.tryAgain")) {
                    Button { Task { await load() } } label: { Label { Text(t("common.retry")) } icon: { Icon("refresh-cw", size: 16) } }
                        .buttonStyle(.lw(.outline, height: 40, fullWidth: false))
                }
            } else if sorted.isEmpty {
                SettingsEmptyState(icon: "credit-card", title: t("settings.cardsScreen.emptyTitle"), message: t("settings.cardsScreen.emptyBody")) {
                    Button { app.navigate(.scan) } label: { Label { Text(t("ios.set.cards.activate")) } icon: { Icon("scan-qr-code", size: 16) } }
                        .buttonStyle(.lw(.outline, height: 40, fullWidth: false))
                        .accessibilityIdentifier("cards.activate")
                }
            } else {
                VStack(spacing: 30) {
                    ForEach(sorted) { card in tile(card) }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(t("settings.cardsScreen.available"))
                .accessibilityIdentifier("cards.list")
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            cards = try await app.api.cards()
            failed = false
        } catch {
            if cards == nil { failed = true } else { app.show(.error, error.localizedDescription) }
        }
    }

    static func name(_ card: Card, _ fallback: String) -> String {
        card.title?.nonBlank ?? card.design.description.nonBlank ?? fallback
    }

    // MARK: card tile — the design floats in a glass rim; status + switch sit on a glass row underneath

    private func tile(_ card: Card) -> some View {
        let name = Self.name(card, t("settings.cardsScreen.fallbackName"))
        let blocked = card.blocked ?? false
        let enabled = enabledOverride[card.id] ?? card.isActive
        let status = blocked ? "Blocked" : enabled ? "Active" : "Disabled"
        let linkNeeded = card.defaultRemoteWalletId != nil && !blocked && card.remoteWalletId != card.defaultRemoteWalletId
        let image = URL(string: card.design.imageUrl, relativeTo: app.endpoint)
        let art = RoundedRectangle(cornerRadius: 18, style: .continuous)

        return VStack(spacing: 12) {
            Color.clear
                .aspectRatio(1.586, contentMode: .fit)
                .overlay {
                    ZStack {
                        Color.white.opacity(0.06)
                        if image != nil { RemoteImage(url: image) } else { Icon("credit-card", size: 32).foregroundStyle(LW.muted) }
                    }
                    .grayscale(blocked || !enabled ? 1 : 0)
                    .opacity(blocked || !enabled ? 0.7 : 1)
                }
                .clipShape(art)
                .overlay(art.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.06)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75))
                .padding(6)
                .lwSurface(24)
                .overlay(alignment: .topTrailing) { if linkNeeded { linkButton(card, name).padding(16) } }
                .shadow(color: .black.opacity(0.45), radius: 26, y: 16)
                .padding(.horizontal, 4)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(LW.font(16, .semibold)).foregroundStyle(LW.foreground).lineLimit(1)
                    Text(card.design.description.nonBlank ?? Self.shortId(card.id)).font(LW.font(13)).foregroundStyle(LW.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                SettingsBadge(t("settings.cardsScreen.status.\(status)"), blocked ? .destructive : enabled ? .primary : .outline)
                    .accessibilityLabel(t("settings.cardsScreen.statusLabel", ["status": t("settings.cardsScreen.status.\(status)")]))
                Toggle("", isOn: Binding(get: { enabled }, set: { next in Task { await toggle(card, name, next) } }))
                    .labelsHidden()
                    .tint(theme.preset.primary)
                    .disabled(pending.contains(card.id) || blocked)
                    .accessibilityLabel(t(enabled ? "settings.cardsScreen.disable" : "settings.cardsScreen.enable", ["name": name]))
                    .accessibilityIdentifier("cards.toggle.\(card.id)")
            }
            .padding(.leading, 18).padding(.trailing, 14).padding(.vertical, 12)
            .lwSurface(LW.Radius.surface - 4)
        }
        .animation(.easeOut(duration: 0.2), value: enabled)
    }

    private func linkButton(_ card: Card, _ name: String) -> some View {
        Button { Task { await link(card, name) } } label: {
            HStack(spacing: 6) {
                if linkPending.contains(card.id) { ProgressView().controlSize(.mini) } else { Icon("link-2", size: 14) }
                Text(t("settings.cardsScreen.linkToWallet")).font(LW.font(13, .semibold))
            }
            .padding(.horizontal, 14).frame(height: 36).contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(LW.foreground)
        .lwGlass(in: Capsule(), interactive: true)
        .disabled(linkPending.contains(card.id))
    }

    private var skeleton: some View {
        VStack(spacing: 30) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.06)).aspectRatio(1.586, contentMode: .fit)
                    RoundedRectangle(cornerRadius: LW.Radius.surface - 4, style: .continuous).fill(Color.white.opacity(0.06)).frame(height: 62)
                }
                .shimmer()
            }
        }
        .accessibilityLabel(t("settings.cardsScreen.loading"))
    }

    // MARK: actions

    private func toggle(_ card: Card, _ name: String, _ enabled: Bool) async {
        pending.insert(card.id)
        enabledOverride[card.id] = enabled
        defer { pending.remove(card.id); enabledOverride[card.id] = nil }
        do {
            let updated = try await app.api.setCardEnabled(card.id, enabled)
            replace(updated)
            app.show(.success, t(enabled ? "settings.cardsScreen.enabledToast" : "settings.cardsScreen.disabledToast", ["name": name]))
        } catch {
            app.show(.error, error.localizedDescription.nonBlank ?? t("settings.cardsScreen.updateFailed"))
        }
    }

    private func link(_ card: Card, _ name: String) async {
        guard let walletId = card.defaultRemoteWalletId else { return }
        linkPending.insert(card.id)
        defer { linkPending.remove(card.id) }
        do {
            replace(try await app.api.setCardWallet(card.id, remoteWalletId: walletId))
            app.show(.success, t("settings.cardsScreen.linkedToast", ["name": name]))
        } catch {
            app.show(.error, error.localizedDescription.nonBlank ?? t("settings.cardsScreen.linkFailed"))
        }
    }

    private func replace(_ card: Card) {
        guard let i = cards?.firstIndex(where: { $0.id == card.id }) else { return }
        cards?[i] = card
    }

    static func shortId(_ id: String) -> String { id.count <= 12 ? id : "\(id.prefix(6))...\(id.suffix(4))" }
}
