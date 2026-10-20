import LaWalletKit
import SwiftUI

/// `/wallet` — components/wallet/home-screen.tsx, in Liquid Glass over the isotype light.
struct HomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @AppStorage("lawallet-balance-hidden") private var hidden = false
    @State private var tab = 0
    @State private var notice: NWCTransaction?
    @State private var flare: AmbientFlare?
    @State private var flareAt: Date?

    var body: some View {
        // Bottom padding clears the root's fixed `NavTabbar`.
        ScrollView {
            VStack(spacing: 0) {
                header
                balance
                actions
                addressCard
                activity
            }
            .padding(.bottom, 150)
        }
        .scrollIndicators(.hidden)
        .lwSoftScrollEdges()
        .refreshable {
            await app.refreshMe()
            await app.wallet.refreshBalance()
            await app.wallet.loadTransactions(reset: true)
        }
        .background(AmbientBackground(intensity: 1, flare: flare, flareAt: flareAt))
        .onChange(of: app.wallet.lastPayment) { _, tx in
            guard let tx else { return }
            flare = tx.type == .incoming ? .incoming : .outgoing
            flareAt = Date()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { notice = tx }
            Task {
                try? await Task.sleep(for: .seconds(3.8))
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { if notice == tx { notice = nil } }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: header

    private var header: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                Menu {
                    if let pk = app.pubkey { Text(t("home.accountWithKey", ["short": String(NIP19.npub(pk).prefix(12)) + "…"])) }
                    Button(role: .destructive) { app.logout() } label: { Label(t("home.logOut"), image: "lucide-log-out") }
                } label: {
                    Avatar(pubkey: app.pubkey).frame(width: 46, height: 46)
                }
                .lwGlass(in: Circle(), interactive: true)
                .accessibilityLabel(t("home.account"))
                .accessibilityIdentifier("home.avatar")

                // The logo pill doubles as the live payment notice: it morphs to "Received +N sats" and back.
                ZStack {
                    if let notice {
                        PaymentNotice(tx: notice).transition(.blurReplace.combined(with: .scale(0.92)))
                    } else if let logo = app.settings?.logotype_url.flatMap({ URL(string: $0, relativeTo: app.endpoint) }) {
                        RemoteImage(url: logo, contentMode: .fit).frame(height: 20).transition(.blurReplace)
                    } else {
                        Image("logotype").resizable().scaledToFit().frame(height: 20).transition(.blurReplace)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 46)
                .lwGlass(in: Capsule(), tint: notice.map { .color(($0.type == .incoming ? LW.incoming : LW.coral).opacity(0.28)) } ?? .none)
                .accessibilityLabel(notice == nil ? app.communityName : "")

                GlassIconButton(icon: hidden ? "eye-off" : "eye", size: 46, label: t(hidden ? "home.showBalance" : "home.hideBalance")) {
                    withAnimation(.snappy) { hidden.toggle() }
                }
                .accessibilityIdentifier("home.toggleBalance")
            }
        }
        .padding(.horizontal, 20).padding(.top, 10)
    }

    // MARK: balance — the hero; light blooms behind it on payments

    private var balance: some View {
        let w = app.wallet
        return VStack(spacing: 14) {
            HStack(spacing: 8) {
                Text(t("home.yourBalance")).font(LW.font(15, .medium)).foregroundStyle(LW.muted)
                if case .error(let msg) = w.status { RelayBadge(message: msg) { Task { await w.refreshBalance() } } }
            }
            ZStack {
                if w.hasWallet && w.balance == nil && w.status != .none {
                    if case .error = w.status {
                        Text(t("shared.balance.unavailable")).font(LW.font(17, .medium)).foregroundStyle(LW.destructiveText)
                    } else {
                        Capsule().fill(Color.white.opacity(0.08)).frame(width: 190, height: 52).shimmer()
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(hidden ? "•••••" : app.currencies.format(w.balance ?? 0))
                            .font(LW.font(68, .semibold)).tracking(-2.4).monospacedDigit()
                            .foregroundStyle(LW.foreground)
                            .contentTransition(.numericText(countsDown: false))
                            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: w.balance)
                            .opacity(w.balanceIsCached ? 0.72 : 1)
                            .lineLimit(1).minimumScaleFactor(0.4)
                            .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
                            .accessibilityIdentifier("home.balance")
                        Text(app.currencies.unit()).font(LW.font(20, .medium)).foregroundStyle(LW.muted)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .frame(minHeight: 82)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.snappy) { app.currencies.cycle() } }

            @Bindable var currencies = app.currencies
            CurrencyToggle(codes: currencies.active, selected: $currencies.selected)

            if let bonus = ActivationBonusNote.amount {
                Text(t("home.bonusNote", ["sats": bonus.formatted()])).font(LW.font(13)).foregroundStyle(LW.muted)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
            }
        }
        .padding(.top, 44).padding(.bottom, 30)
    }

    // MARK: actions — one glass group so the pair reads as a single control

    private var actions: some View {
        GlassGroup(spacing: 12) {
            HStack(spacing: 12) {
                Button { app.flows.resetReceive(); app.navigate(.receive) } label: {
                    Label { Text(t("home.receive")) } icon: { Icon("arrow-down-left", size: 18) }
                }
                .buttonStyle(.lw(.secondary, height: 56))
                .accessibilityIdentifier("home.receive")
                Button { app.flows.resetSend(); app.navigate(.send) } label: {
                    Label { Text(t("home.send")) } icon: { Icon("arrow-up-right", size: 18) }
                }
                .buttonStyle(.lw(.theme, height: 56))
                .disabled(!app.wallet.hasWallet)
                .accessibilityIdentifier("home.send")
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder private var addressCard: some View {
        if let address = app.me?.lightningAddress {
            Button { app.navigate(.receive) } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t("home.address")).font(LW.font(13, .medium)).foregroundStyle(LW.muted)
                        Text(address).font(LW.font(17, .semibold)).foregroundStyle(LW.foreground).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Icon("qr-code", size: 20).foregroundStyle(LW.foreground)
                        .frame(width: 44, height: 44).background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScale())
            .lwSurface(LW.Radius.surface - 2)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.address")
            .padding(.horizontal, 20).padding(.top, 16)
        } else if app.me != nil {
            Button { app.navigate(.claimUsername(fromActivation: false, bonus: false)) } label: {
                HStack(spacing: 12) {
                    Icon("sparkles", size: 18).foregroundStyle(LW.sun)
                        .frame(width: 36, height: 36).background(LW.sun.opacity(0.14), in: Circle())
                    Text(t("home.claimAddress")).font(LW.font(15, .semibold)).foregroundStyle(LW.foreground).multilineTextAlignment(.leading)
                    Spacer()
                    Icon("chevron-right", size: 16).foregroundStyle(LW.muted)
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScale())
            .lwGlass(in: RoundedRectangle(cornerRadius: LW.Radius.surface - 2, style: .continuous), tint: .color(LW.sun.opacity(0.10)), interactive: true)
            .accessibilityIdentifier("home.claimAddress")
            .padding(.horizontal, 20).padding(.top, 16)
        }
        if app.me != nil && !app.wallet.hasWallet {
            let auto = app.settings?.lncurlAutoCreate == true
            HStack(alignment: .top, spacing: 12) {
                Icon(auto ? "zap" : "wallet", size: 18).foregroundStyle(auto ? LW.mint : LW.muted)
                    .frame(width: 36, height: 36).background((auto ? LW.mint : Color.white).opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(t(auto ? "home.autoCreateTitle" : "home.noWalletTitle")).font(LW.font(15, .semibold)).foregroundStyle(LW.foreground)
                    Text(t(auto ? "home.autoCreateBody" : "home.noWalletBody")).font(LW.font(13)).foregroundStyle(LW.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if !auto {
                        Button(t("home.connectWallet")) { app.navigate(.remoteWallets) }
                            .buttonStyle(.lw(.secondary, height: 40, fullWidth: false)).padding(.top, 8)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .lwSurface(LW.Radius.surface - 2)
            .padding(.horizontal, 20).padding(.top, 16)
            .accessibilityIdentifier("home.noWallet")
        }
    }

    // MARK: activity preview

    private var activity: some View {
        let w = app.wallet
        let items = (tab == 0 ? w.transactions : []).prefix(5)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                GlassSegmented(items: [(0, t("home.tabActivity")), (1, t("home.tabTransfers"))], selection: $tab, idPrefix: "home.tab")
                Spacer()
                Button(t("home.viewAll")) { app.navigate(.activity) }
                    .font(LW.font(14, .semibold)).foregroundStyle(LW.foreground.opacity(0.85))
                    .padding(.horizontal, 14).frame(height: 36)
                    .lwGlass(in: Capsule(), interactive: true)
                    .accessibilityIdentifier("home.viewAll")
            }
            Group {
                if !w.hasWallet {
                    emptyState("wallet", t("home.list.activity.connect"))
                } else if items.isEmpty && w.loadingTransactions {
                    HStack(spacing: 10) { ProgressView().tint(LW.muted); Text(t("common.loading")) }
                        .font(LW.font(14)).foregroundStyle(LW.muted).frame(maxWidth: .infinity).padding(.vertical, 36)
                        .lwSurface()
                } else if items.isEmpty, let err = w.transactionsError, tab == 0 {
                    emptyState("wifi-off", t("home.list.activity.error"), error: true).accessibilityHint(err)
                } else if items.isEmpty {
                    emptyState(tab == 0 ? "activity" : "git-branch", t(tab == 0 ? "home.list.activity.empty" : "home.list.transfers.empty"))
                } else {
                    TransactionList(items: Array(items), rowID: "home.tx")
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 30)
    }

    private func emptyState(_ icon: String, _ text: String, error: Bool = false) -> some View {
        VStack(spacing: 10) {
            Icon(icon, size: 22).foregroundStyle(error ? LW.destructiveText : LW.muted)
            Text(text).font(LW.font(14)).foregroundStyle(error ? LW.destructiveText : LW.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.vertical, 34)
        .lwSurface()
    }
}

/// "Includes N sats from activating your card" (set by the activation flow, dismissed after 24 h).
enum ActivationBonusNote {
    static var amount: Int? {
        let d = UserDefaults.standard
        guard let at = d.object(forKey: "lawallet-activation-bonus-at") as? Date, Date().timeIntervalSince(at) < 86_400 else { return nil }
        let sats = d.integer(forKey: "lawallet-activation-bonus-sats")
        return sats > 0 ? sats : nil
    }
}

/// Live payment notice content (shown inside the header pill).
struct PaymentNotice: View {
    let tx: NWCTransaction
    var body: some View {
        let incoming = tx.type == .incoming
        HStack(spacing: 8) {
            Icon(incoming ? "arrow-down-left" : "arrow-up-right", size: 15).foregroundStyle(.white)
            Text(t(incoming ? "shared.tx.received" : "shared.tx.sent")).font(LW.font(14, .medium)).foregroundStyle(LW.foreground.opacity(0.85))
            Text("\(incoming ? "+" : "−")\(tx.amountSats.formatted()) sats").font(LW.font(15, .bold)).monospacedDigit()
        }
        .lineLimit(1).minimumScaleFactor(0.7)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("payment.notice")
    }
}

/// Relay status chip next to the balance.
struct RelayBadge: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        Button(action: retry) {
            HStack(spacing: 5) { Icon("wifi-off", size: 12); Text(t("shared.relay.offline")).font(LW.font(12, .semibold)) }
                .foregroundStyle(LW.destructiveText).padding(.horizontal, 10).padding(.vertical, 5).contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .lwGlass(in: Capsule(), tint: .color(LW.coral.opacity(0.18)), interactive: true)
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
            if let picture { RemoteImage(url: picture) } else { Image("isotypo").resizable().scaledToFit().padding(11) }
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

    /// iOS 26 soft scroll edges so content dissolves under floating glass chrome.
    @ViewBuilder func lwSoftScrollEdges() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }
}

private struct Shimmer: ViewModifier {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.opacity(on ? 0.45 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(), value: on)
            .onAppear { on = true }
    }
}
