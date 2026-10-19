import LaWalletKit
import SwiftUI

/// `/wallet/settings/cards` — components/wallet/settings/cards-screen.tsx.
struct CardsScreen: View {
    @Environment(AppModel.self) private var app
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
                SettingsEmptyState(title: t("settings.cardsScreen.errorTitle"), message: t("settings.cardsScreen.tryAgain"), dashed: false) {
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
                VStack(spacing: 12) {
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

    // MARK: card tile

    private func tile(_ card: Card) -> some View {
        let name = Self.name(card, t("settings.cardsScreen.fallbackName"))
        let blocked = card.blocked ?? false
        let enabled = enabledOverride[card.id] ?? card.isActive
        let status = blocked ? "Blocked" : enabled ? "Active" : "Disabled"
        let linkNeeded = card.defaultRemoteWalletId != nil && !blocked && card.remoteWalletId != card.defaultRemoteWalletId
        let image = URL(string: card.design.imageUrl, relativeTo: app.endpoint)

        return Color.clear
            .aspectRatio(1.55, contentMode: .fit)
            .frame(minHeight: 176)
            .overlay {
                ZStack {
                    LW.secondary
                    if image != nil { RemoteImage(url: image) } else { Icon("credit-card", size: 32).foregroundStyle(LW.muted) }
                }
                .grayscale(blocked || !enabled ? 1 : 0)
                .opacity(blocked || !enabled ? 0.8 : 1)
            }
            .overlay {
                LinearGradient(colors: [LW.background.opacity(0.05), LW.background.opacity(0.3), LW.background.opacity(0.85)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay {
                VStack {
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            SettingsBadge(t("settings.cardsScreen.status.\(status)"), status == "Active" ? .primary : .secondary)
                                .accessibilityLabel(t("settings.cardsScreen.statusLabel", ["status": t("settings.cardsScreen.status.\(status)")]))
                            if linkNeeded { linkButton(card, name) }
                        }
                    }
                    Spacer()
                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(LW.font(18, .semibold)).lineLimit(1)
                            Text(card.design.description.nonBlank ?? Self.shortId(card.id)).font(LW.font(12)).foregroundStyle(LW.muted).lineLimit(1)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.ultraThinMaterial.opacity(0.6)).background(LW.background.opacity(0.65))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Spacer(minLength: 0)
                        Toggle("", isOn: Binding(get: { enabled }, set: { next in Task { await toggle(card, name, next) } }))
                            .labelsHidden()
                            .disabled(pending.contains(card.id) || blocked)
                            .accessibilityLabel(t(enabled ? "settings.cardsScreen.disable" : "settings.cardsScreen.enable", ["name": name]))
                            .accessibilityIdentifier("cards.toggle.\(card.id)")
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(LW.background.opacity(0.7)).clipShape(Capsule())
                    }
                }
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(LW.border.opacity(0.4)))
            .animation(.easeOut(duration: 0.2), value: enabled)
    }

    private func linkButton(_ card: Card, _ name: String) -> some View {
        Button { Task { await link(card, name) } } label: {
            HStack(spacing: 6) {
                if linkPending.contains(card.id) { ProgressView().controlSize(.mini) } else { Icon("link-2", size: 14) }
                Text(t("settings.cardsScreen.linkToWallet")).font(LW.font(12, .semibold))
            }
            .padding(.horizontal, 12).frame(height: 36)
            .background(LW.background.opacity(0.75)).clipShape(Capsule())
            .overlay(Capsule().strokeBorder(LW.border.opacity(0.4)))
        }
        .foregroundStyle(LW.foreground)
        .disabled(linkPending.contains(card.id))
    }

    private var skeleton: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12).fill(LW.secondary).frame(width: 96, height: 62)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4).fill(LW.secondary).frame(width: 112, height: 18)
                        RoundedRectangle(cornerRadius: 4).fill(LW.secondary).frame(width: 144, height: 14)
                    }
                    Spacer()
                }
                .padding(12).background(LW.card).clipShape(RoundedRectangle(cornerRadius: 16)).shimmer()
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
