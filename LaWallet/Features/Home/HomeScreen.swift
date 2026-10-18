import LaWalletKit
import SwiftUI

/// `/wallet` — components/wallet/home-screen.tsx.
struct HomeScreen: View {
    @Environment(AppModel.self) private var app
    @AppStorage("lawallet-balance-hidden") private var hidden = false
    @State private var tab = 0
    @State private var notice: NWCTransaction?

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    balance
                    actions
                    addressCard
                    activity
                }
                .padding(.bottom, 140)
            }
            .refreshable {
                await app.refreshMe()
                await app.wallet.refreshBalance()
                await app.wallet.loadTransactions(reset: true)
            }
            NavTabbar(active: .home, onHome: {}, onScan: { app.navigate(.scan) }, onSettings: { app.navigate(.settings) })
        }
        .overlay(alignment: .top) {
            if let notice { PaymentNotice(tx: notice).transition(.move(edge: .top).combined(with: .opacity)) }
        }
        .onChange(of: app.wallet.lastPayment) { _, tx in
            guard let tx else { return }
            withAnimation(.spring) { notice = tx }
            Task {
                try? await Task.sleep(for: .seconds(3.8))
                withAnimation { if notice == tx { notice = nil } }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 12) {
            Menu {
                if let pk = app.pubkey { Text(t("home.accountWithKey", ["short": String(NIP19.npub(pk).prefix(12)) + "…"])) }
                Button(role: .destructive) { app.logout() } label: { Label(t("home.logOut"), image: "lucide-log-out") }
            } label: {
                Avatar(pubkey: app.pubkey).frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("home.avatar")

            ZStack {
                if let logo = app.settings?.logotype_url.flatMap({ URL(string: $0, relativeTo: app.endpoint) }) {
                    RemoteImage(url: logo, contentMode: .fit).frame(height: 20)
                } else {
                    Image("logotype").resizable().scaledToFit().frame(height: 20)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(LW.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button { hidden.toggle() } label: {
                Icon(hidden ? "eye-off" : "eye").frame(width: 44, height: 44).background(LW.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .accessibilityLabel(t(hidden ? "home.showBalance" : "home.hideBalance"))
            .accessibilityIdentifier("home.toggleBalance")
        }
        .padding(.horizontal, 16).padding(.top, 16)
    }

    // MARK: balance

    private var balance: some View {
        let w = app.wallet
        let code = app.currencies.selected
        return VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text(t("home.yourBalance").uppercased()).font(LW.font(12)).tracking(1.2).foregroundStyle(LW.muted)
                if case .error(let msg) = w.status { RelayBadge(message: msg) { Task { await w.refreshBalance() } } }
            }
            ZStack {
                if w.hasWallet && w.balance == nil && w.status != .none {
                    if case .error = w.status {
                        Text(t("shared.balance.unavailable")).font(LW.font(16)).foregroundStyle(LW.destructiveText)
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(LW.card).frame(width: 160, height: 36).shimmer()
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(hidden ? "•••••" : app.currencies.format(w.balance ?? 0))
                            .font(LW.font(48, .semibold)).monospacedDigit()
                            .contentTransition(.numericText())
                            .opacity(w.balanceIsCached ? 0.7 : 1)
                            .animation(.spring, value: w.balance)
                            .lineLimit(1).minimumScaleFactor(0.5)
                            .accessibilityIdentifier("home.balance")
                        Text(app.currencies.unit()).font(LW.font(16)).foregroundStyle(LW.muted)
                    }
                }
            }
            .frame(minHeight: 56)
            .onTapGesture { app.currencies.cycle() }

            @Bindable var currencies = app.currencies
            CurrencyToggle(codes: currencies.active, selected: $currencies.selected)
            let _ = code
        }
        .padding(.horizontal, 16).padding(.top, 32).padding(.bottom, 16)
    }

    // MARK: actions

    private var actions: some View {
        HStack(spacing: 12) {
            Button(t("home.receive")) { app.flows.resetReceive(); app.navigate(.receive) }
                .buttonStyle(.lw(.secondary))
                .accessibilityIdentifier("home.receive")
            Button(t("home.send")) { app.flows.resetSend(); app.navigate(.send) }
                .buttonStyle(.lw(.theme))
                .disabled(!app.wallet.hasWallet)
                .accessibilityIdentifier("home.send")
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var addressCard: some View {
        if let address = app.me?.lightningAddress {
            Button { app.navigate(.receive) } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("home.address")).font(LW.font(12)).foregroundStyle(LW.muted)
                        Text(address).font(LW.font(16, .semibold)).foregroundStyle(LW.foreground).lineLimit(1).truncationMode(.middle)
                            .accessibilityIdentifier("home.address")
                    }
                    Spacer()
                    Icon("qr-code").foregroundStyle(LW.muted).frame(width: 40, height: 40).background(LW.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(LW.card).clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LW.border))
            }
            .padding(.horizontal, 16).padding(.top, 16)
        } else if app.me != nil {
            Button { app.navigate(.claimUsername(fromActivation: false, bonus: false)) } label: {
                HStack(spacing: 12) {
                    Icon("sparkles", size: 16).foregroundStyle(LW.nwcPurple)
                    Text(t("home.claimAddress")).font(LW.font(14)).foregroundStyle(LW.foreground)
                    Spacer()
                    Text("→").font(LW.font(12)).foregroundStyle(LW.muted)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(LW.nwcPurple.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LW.nwcPurple.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            .accessibilityIdentifier("home.claimAddress")
            .padding(.horizontal, 16).padding(.top, 16)
        }
        if app.me != nil && !app.wallet.hasWallet {
            let auto = app.settings?.lncurlAutoCreate == true
            VStack(alignment: .leading, spacing: 4) {
                Text(t(auto ? "home.autoCreateTitle" : "home.noWalletTitle")).font(LW.font(14, .medium)).foregroundStyle(LW.foreground)
                Text(t(auto ? "home.autoCreateBody" : "home.noWalletBody")).font(LW.font(12)).foregroundStyle(LW.muted)
                if !auto {
                    Button(t("home.connectWallet")) { app.navigate(.remoteWallets) }.buttonStyle(.lw(.secondary, height: 36, fullWidth: false)).padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(auto ? LW.nwcPurple.opacity(0.05) : LW.card.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(auto ? LW.nwcPurple.opacity(0.4) : LW.border,
                                                                   style: StrokeStyle(lineWidth: 1, dash: auto ? [4, 3] : [])))
            .padding(.horizontal, 16).padding(.top, 16)
            .accessibilityIdentifier("home.noWallet")
        }
    }

    // MARK: activity preview

    private var activity: some View {
        let w = app.wallet
        let items = (tab == 0 ? w.transactions : []).prefix(5)
        return VStack(spacing: 12) {
            HStack {
                HStack(spacing: 4) {
                    pill(t("home.tabActivity"), 0)
                    pill(t("home.tabTransfers"), 1)
                }
                .padding(4).background(LW.card).clipShape(Capsule())
                Spacer()
                Button(t("home.viewAll")) { app.navigate(.activity) }.font(LW.font(12, .medium)).foregroundStyle(LW.muted)
                    .accessibilityIdentifier("home.viewAll")
            }
            Group {
                if !w.hasWallet {
                    emptyBox(t("home.list.activity.connect"))
                } else if items.isEmpty && w.loadingTransactions {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text(t("common.loading")) }
                        .font(LW.font(14)).foregroundStyle(LW.muted).frame(maxWidth: .infinity).padding(.vertical, 32)
                        .background(LW.card.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 12))
                } else if items.isEmpty, let err = w.transactionsError, tab == 0 {
                    emptyBox(t("home.list.activity.error"), error: true).accessibilityHint(err)
                } else if items.isEmpty {
                    emptyBox(t(tab == 0 ? "home.list.activity.empty" : "home.list.transfers.empty"))
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, tx in
                            Button { app.navigate(.activityDetail(tx)) } label: { TransactionRowView(tx: tx) }
                            if i < items.count - 1 { Rectangle().fill(LW.border.opacity(0.4)).frame(height: 1) }
                        }
                    }
                    .background(LW.card.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 24)
    }

    private func pill(_ label: String, _ i: Int) -> some View {
        Button { tab = i } label: {
            Text(label).font(LW.font(12, .medium)).padding(.horizontal, 12).padding(.vertical, 5)
                .foregroundStyle(tab == i ? LW.foreground : LW.muted)
                .background(tab == i ? LW.background : .clear).clipShape(Capsule())
        }
    }

    private func emptyBox(_ text: String, error: Bool = false) -> some View {
        Text(text).font(LW.font(14)).foregroundStyle(error ? LW.destructiveText : LW.muted).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.vertical, 32)
            .background(LW.card.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LW.border))
    }
}

/// Live payment toast (home/payment-notice.tsx).
struct PaymentNotice: View {
    let tx: NWCTransaction
    var body: some View {
        let incoming = tx.type == .incoming
        HStack(spacing: 12) {
            Icon(incoming ? "arrow-down-left" : "arrow-up-right", size: 18).foregroundStyle(incoming ? LW.incoming : LW.outgoing)
                .frame(width: 36, height: 36).background((incoming ? LW.incoming : LW.outgoing).opacity(0.12)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(t(incoming ? "shared.tx.received" : "shared.tx.sent")).font(LW.font(13)).foregroundStyle(LW.muted)
                Text("\(incoming ? "+" : "−")\(tx.amountSats.formatted()) sats").font(LW.font(17, .semibold)).monospacedDigit()
            }
            Spacer()
        }
        .padding(12).background(LW.card).clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(LW.border))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
        .padding(.horizontal, 16).padding(.top, 8)
        .accessibilityIdentifier("payment.notice")
    }
}

/// Relay status chip next to the balance (shared/relay-error-badge.tsx).
struct RelayBadge: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        Button(action: retry) {
            HStack(spacing: 4) { Icon("wifi-off", size: 12); Text(t("shared.relay.offline")).font(LW.font(12, .medium)) }
                .foregroundStyle(LW.destructiveText).padding(.horizontal, 8).padding(.vertical, 3)
                .background(LW.destructive.opacity(0.15)).clipShape(Capsule())
                .overlay(Capsule().strokeBorder(LW.destructive.opacity(0.5)))
        }
        .accessibilityHint(message)
    }
}

/// Nostr avatar via `POST /api/nostr/profiles`, falling back to the community isotype.
struct Avatar: View {
    let pubkey: String?
    @Environment(AppModel.self) private var app
    @State private var picture: URL?
    var body: some View {
        ZStack {
            LW.card
            if let picture { RemoteImage(url: picture) } else { Image("isotypo").resizable().scaledToFit().padding(10) }
        }
        .clipShape(Circle())
        .task(id: pubkey) {
            guard let pubkey, let p = try? await app.api.profiles([pubkey]).first?.picture else { return }
            picture = URL(string: p)
        }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}

private struct Shimmer: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content.opacity(on ? 0.4 : 1).animation(.easeInOut(duration: 0.9).repeatForever(), value: on).onAppear { on = true }
    }
}
