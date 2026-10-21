import LaWalletKit
import SwiftUI

/// Counts for the recovery copy. The web plural helpers export their plural form; the singular is iOS-only.
enum RecoveryCopy {
    static func cards(_ n: Int) -> String { n == 1 ? t("ios.recover.oneCard") : t("activate.recover.merge.cards", ["n": "\(n)"]) }
    static func wallets(_ n: Int) -> String { n == 1 ? t("ios.recover.oneWallet") : t("activate.recover.merge.wallets", ["n": "\(n)"]) }
    static func vouchers(_ n: Int) -> String { n == 1 ? t("ios.recover.oneVoucher") : t("activate.recover.done.vouchers", ["n": "\(n)"]) }
    static func counts(cards: Int, wallets: Int) -> String { "\(Self.cards(cards)) · \(Self.wallets(wallets))" }
}

/// Small block listing addresses then "N cards · N wallets" (merge prompt sides, account-transfer "What moved").
private struct RecoverySideBlock: View {
    let label: String
    let addresses: [String]
    let cards: Int
    let wallets: Int
    var highlight = false
    var emptyAddresses: String?
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(LW.font(13, .semibold)).foregroundStyle(LW.muted)
            if addresses.isEmpty, let emptyAddresses {
                Text(emptyAddresses).font(LW.font(14)).foregroundStyle(LW.muted)
            }
            ForEach(addresses, id: \.self) { a in
                Text(a).font(LW.font(15, .medium)).foregroundStyle(LW.foreground).lineLimit(1).truncationMode(.middle)
            }
            Text(RecoveryCopy.counts(cards: cards, wallets: wallets)).font(LW.font(14)).foregroundStyle(LW.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .lwSurface(LW.Radius.surface - 8)
        .overlay {
            if highlight {
                RoundedRectangle(cornerRadius: LW.Radius.surface - 8, style: .continuous).strokeBorder(theme.preset.primary.opacity(0.5))
            }
        }
    }
}

// MARK: merge prompt (components/activate/recover-merge-dialog.tsx)

struct RecoverMergeSheet: View {
    let check: RecoveryCheck
    let onConfirm: () -> Void
    let onCancel: () -> Void
    private let m = "activate.recover.merge"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(t("\(m).title")).font(LW.font(22, .bold)).foregroundStyle(LW.foreground)
                    Text(t("\(m).body")).font(LW.font(14)).foregroundStyle(LW.muted).fixedSize(horizontal: false, vertical: true)
                }
                RecoverySideBlock(label: t("\(m).yours"), addresses: check.existing.lightningAddresses, cards: check.existing.cards,
                                  wallets: check.existing.remoteWallets, emptyAddresses: t("\(m).noAddress"))
                RecoverySideBlock(label: t("\(m).incoming"), addresses: check.incoming.lightningAddresses, cards: check.incoming.cards,
                                  wallets: check.incoming.remoteWallets, highlight: true, emptyAddresses: t("\(m).noAddress"))
                Text(t("\(m).keepsPrimary")).font(LW.font(13)).foregroundStyle(LW.muted).fixedSize(horizontal: false, vertical: true)
                Button(t("\(m).confirm"), action: onConfirm).buttonStyle(.lw(.theme))
                    .accessibilityIdentifier("recover.merge.confirm")
                Button(t("\(m).cancel"), action: onCancel).buttonStyle(.lw(.secondary))
                    .accessibilityIdentifier("recover.merge.cancel")
            }
            .padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: recovered (components/activate/recovered-dialog.tsx)

struct RecoveredView: View {
    let recovery: RecoveredAccount
    let claimAddress: Bool
    let onContinue: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    /// Missing key = loading, `.some(nil)` = unavailable.
    @State private var balances: [String: Int?] = [:]
    private let d = "activate.recover.done"

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    Icon("check-circle-2", size: 28).foregroundStyle(theme.preset.primary)
                        .frame(width: 64, height: 64).background(theme.preset.primary.opacity(0.16), in: Circle())
                    Text(t("\(d).title")).font(LW.font(28, .bold)).tracking(-0.6).foregroundStyle(LW.foreground)
                        .accessibilityIdentifier("recover.done.title")
                    Text(t(recovery.mergedIntoExisting ? "\(d).merged" : "\(d).body")).font(LW.font(15)).foregroundStyle(LW.muted)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 24)

                VStack(spacing: 4) {
                    Text(t("\(d).totalBalance")).font(LW.font(13, .semibold)).foregroundStyle(LW.muted)
                    totalBalance
                }
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .lwSurface(LW.Radius.surface - 4)

                section("zap", t("\(d).addresses")) {
                    if recovery.lightningAddresses.isEmpty { row(t("\(d).none"), muted: true) }
                    ForEach(Array(recovery.lightningAddresses.enumerated()), id: \.element) { i, a in
                        if i > 0 { RowDivider() }
                        row(a)
                    }
                }
                section("credit-card", t("\(d).cards")) {
                    if recovery.cards.isEmpty { row(t("\(d).none"), muted: true) }
                    ForEach(Array(recovery.cards.enumerated()), id: \.element.id) { i, c in
                        if i > 0 { RowDivider() }
                        HStack(spacing: 12) {
                            if let url = app.onbImageURL(c.designImageUrl) {
                                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.06) }
                                    .frame(width: 40, height: 25).clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }
                            Text(c.title?.nonBlank ?? t("\(d).untitledCard")).font(LW.font(15, .medium)).foregroundStyle(LW.foreground).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 18).frame(minHeight: 48)
                    }
                }
                section("wallet", t("\(d).wallets")) {
                    if recovery.remoteWallets.isEmpty { row(t("\(d).none"), muted: true) }
                    ForEach(Array(recovery.remoteWallets.enumerated()), id: \.element.id) { i, w in
                        if i > 0 { RowDivider() }
                        HStack(spacing: 8) {
                            Text(w.name).font(LW.font(15, .medium)).foregroundStyle(LW.foreground).lineLimit(1)
                            if w.isDefault { SettingsBadge(t("\(d).defaultWallet"), .primary) }
                            Spacer(minLength: 8)
                            walletBalance(w.id)
                        }
                        .padding(.horizontal, 18).frame(minHeight: 48)
                    }
                }
                if recovery.vouchers > 0 {
                    Text(RecoveryCopy.vouchers(recovery.vouchers)).font(LW.font(14)).foregroundStyle(LW.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 6)
                }
                Button(t(claimAddress ? "\(d).claimAddress" : "\(d).openWallet"), action: onContinue)
                    .buttonStyle(.lw(.theme, height: 56))
                    .accessibilityIdentifier("recover.done.continue")
                    .padding(.top, 4).padding(.bottom, 12)
            }
        }
        .scrollIndicators(.hidden)
        .task { await loadBalances() }
    }

    @ViewBuilder private var totalBalance: some View {
        let values = recovery.remoteWallets.map { balances[$0.id] ?? nil }
        let loading = recovery.remoteWallets.contains { balances[$0.id] == nil }
        if let total = RecoveredAccount.total(values) {
            Text(t("common.sats", ["n": total.formatted()])).font(LW.font(28, .semibold)).monospacedDigit().foregroundStyle(LW.foreground)
        } else if loading {
            ProgressView().tint(LW.muted).frame(height: 34)
        } else {
            Text(t(recovery.remoteWallets.isEmpty ? "\(d).none" : "\(d).unavailable")).font(LW.font(15)).foregroundStyle(LW.muted)
        }
    }

    @ViewBuilder private func walletBalance(_ id: String) -> some View {
        switch balances[id] {
        case .none: ProgressView().controlSize(.small).tint(LW.muted)
        case .some(.none): Text(t("\(d).unavailable")).font(LW.font(14)).foregroundStyle(LW.muted)
        case .some(.some(let sats)): Text(t("common.sats", ["n": sats.formatted()])).font(LW.font(14, .medium)).monospacedDigit()
        }
    }

    private func section<C: View>(_ icon: String, _ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) { Icon(icon, size: 14); Text(title).font(LW.font(14, .semibold)) }
                .foregroundStyle(LW.muted).padding(.leading, 6)
            VStack(spacing: 0) { content() }.lwSurface(LW.Radius.surface - 4)
        }
    }

    private func row(_ label: String, muted: Bool = false) -> some View {
        Text(label).font(LW.font(15, muted ? .regular : .medium)).foregroundStyle(muted ? LW.muted : LW.foreground)
            .lineLimit(1).truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).frame(minHeight: 48)
    }

    private func loadBalances() async {
        let api = app.api
        await withTaskGroup(of: (String, Int?).self) { group in
            for w in recovery.remoteWallets {
                group.addTask { (w.id, try? await api.remoteWalletBalance(w.id)) }
            }
            for await (id, sats) in group { balances[id] = .some(sats) }
        }
    }
}

// MARK: old owner notice (components/wallet/account-transferred-dialog.tsx)

struct AccountTransferSheet: View {
    let transfer: AccountTransfer
    let onDismissed: () -> Void
    @Environment(AppModel.self) private var app
    @State private var busy = false
    @State private var error: String?
    private let a = "settings.accountTransfer"

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Icon("shield", size: 24).foregroundStyle(LW.destructiveText)
                    .frame(width: 52, height: 52).background(LW.coral.opacity(0.16), in: Circle())
                Text(t("\(a).title")).font(LW.font(22, .bold)).foregroundStyle(LW.foreground).multilineTextAlignment(.center)
                    .accessibilityIdentifier("accountTransfer.title")
                Text(t("\(a).body", ["date": date, "card": transfer.cardTitle?.nonBlank ?? t("\(a).unnamedCard")]))
                    .font(LW.font(15)).foregroundStyle(LW.muted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                RecoverySideBlock(label: t("\(a).moved"), addresses: transfer.lightningAddresses, cards: transfer.cards, wallets: transfer.remoteWallets)
                Text(t("\(a).notYou")).font(LW.font(13)).foregroundStyle(LW.muted).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ErrorText(message: error)
                Button { Task { await dismiss() } } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView().controlSize(.small) }
                        Text(t("\(a).dismiss"))
                    }
                }
                .buttonStyle(.lw(.primary))
                .disabled(busy)
                .accessibilityIdentifier("accountTransfer.dismiss")
            }
            .padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var date: String {
        guard let d = SettingsFormat.date(transfer.transferredAt) else { return String(transfer.transferredAt.prefix(10)) }
        return d.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: Locale(identifier: app.language)))
    }

    private func dismiss() async {
        busy = true
        error = nil
        do {
            try await app.api.dismissAccountTransfer()
            onDismissed()
            await app.refreshMe()
        } catch {
            self.error = error.localizedDescription.nonBlank ?? t("ios.common.error")
            busy = false
        }
    }
}
