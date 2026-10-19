import LaWalletKit
import SwiftUI

/// `/wallet/withdraw` — withdraw/withdraw-screen.tsx (LUD-03 claim). Params come from `app.flows.withdraw`.
struct WithdrawScreen: View {
    enum Phase { case confirm, claiming, success }

    @Environment(AppModel.self) private var app
    @State private var params: LNURLWithdrawParams?
    @State private var phase: Phase = .confirm
    @State private var value = ""
    @State private var error: String?
    @State private var snapshot: Int?
    @State private var result: (amountSats: Int, settled: Bool)?

    var body: some View {
        Group {
            if let p = params ?? app.flows.withdraw {
                if phase == .confirm {
                    confirm(p)
                } else {
                    ClaimCelebration(charging: phase == .claiming, amountSats: result?.amountSats ?? amount(p) ?? 0,
                                     settled: result?.settled ?? false, snapshot: snapshot, liveBalance: app.wallet.balance,
                                     onDone: done, onDismiss: { if !app.path.isEmpty { app.path.removeLast() } })
                }
            }
        }
        .onAppear {
            // Hold the voucher locally: the flow store may be reset while the celebration is still on screen.
            guard params == nil, let p = app.flows.withdraw else { return }
            params = p
            if value.isEmpty { value = String(p.maxWithdrawableSats) }
        }
    }

    private func fixed(_ p: LNURLWithdrawParams) -> Bool { p.minWithdrawableSats == p.maxWithdrawableSats }

    private func amount(_ p: LNURLWithdrawParams) -> Int? { fixed(p) ? p.maxWithdrawableSats : Int(value) }

    private func valid(_ p: LNURLWithdrawParams) -> Bool {
        guard let a = amount(p) else { return false }
        return a >= max(1, p.minWithdrawableSats) && a <= p.maxWithdrawableSats
    }

    // MARK: confirm

    private func confirm(_ p: LNURLWithdrawParams) -> some View {
        let canAutoCreate = app.settings?.lncurlAutoCreate == true || app.settings?.lncurlEnabled == true
        return VStack(spacing: 0) {
            ScreenHeader(title: t("withdraw.title"), close: true)
            VStack(spacing: 16) {
                voucher(p)
                if !app.wallet.hasWallet && !canAutoCreate {
                    noWallet
                } else {
                    VStack(spacing: 8) {
                        if fixed(p) {
                            AmountDisplay(value: String(p.maxWithdrawableSats), unit: "sats", subline: t("withdraw.fixedAmount"))
                        } else {
                            AmountDisplay(value: value, unit: "sats").padding(.vertical, -16)
                            Text(t("withdraw.range", ["min": p.minWithdrawableSats.formatted(), "max": p.maxWithdrawableSats.formatted()]))
                                .font(LW.font(12)).foregroundStyle(LW.muted)
                        }
                    }
                    Spacer(minLength: 0)
                    if !fixed(p) {
                        AmountKeypad(value: Binding(get: { value }, set: { value = $0; error = nil }), decimals: 0)
                    }
                    VStack(spacing: 8) {
                        ErrorText(message: error)
                        Button { Task { await claim(p) } } label: {
                            HStack(spacing: 8) {
                                Icon("arrow-down-to-line", size: 16)
                                Text(amount(p).map { t("withdraw.ctaAmount", ["amount": $0.formatted()]) } ?? t("withdraw.cta"))
                            }
                        }
                        .buttonStyle(.lw(.primary))
                        .disabled(!valid(p))
                        .accessibilityIdentifier("withdraw.claim")
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func voucher(_ p: LNURLWithdrawParams) -> some View {
        HStack(spacing: 12) {
            Icon("arrow-down-to-line").foregroundStyle(LW.muted).frame(width: 48, height: 48)
                .background(LW.background).clipShape(Circle()).overlay(Circle().strokeBorder(LW.border.opacity(0.7)))
            VStack(alignment: .leading, spacing: 2) {
                Text(t("withdraw.from").uppercased()).font(LW.font(12, .medium)).tracking(1.6).foregroundStyle(LW.muted)
                Text(p.host.isEmpty ? t("withdraw.voucher") : p.host).font(LW.font(16, .semibold)).lineLimit(1)
                if !p.defaultDescription.isEmpty {
                    Text(p.defaultDescription).font(LW.font(12)).foregroundStyle(LW.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(LW.card.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(LW.border.opacity(0.7)))
        .accessibilityIdentifier("withdraw.voucher")
    }

    private var noWallet: some View {
        VStack(spacing: 12) {
            Icon("wallet", size: 28).foregroundStyle(LW.muted).frame(width: 56, height: 56).background(LW.card).clipShape(Circle())
            Text(t("withdraw.noWallet")).font(LW.font(16, .semibold))
            Text(t("withdraw.noWalletBody")).font(LW.font(14)).foregroundStyle(LW.muted).multilineTextAlignment(.center)
            Button(t("withdraw.manageWallets")) { app.navigate(.remoteWallets) }
                .buttonStyle(.lw(.secondary, fullWidth: false))
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: claim

    private func claim(_ p: LNURLWithdrawParams) async {
        guard let amount = amount(p), valid(p), phase == .confirm else { return }
        error = nil
        snapshot = app.wallet.balance
        phase = .claiming
        Haptics.tap()
        do {
            let nwc = try await app.ensureWallet()
            let client: NWCClient
            if let c = app.wallet.client, app.wallet.uri == nwc { client = c } else { client = try NWCClient(uri: nwc) }
            let invoice = try await client.makeInvoice(amountSats: amount,
                                                       description: p.defaultDescription.isEmpty ? "LNURL withdraw" : p.defaultDescription)
            try await LNURL.submitWithdraw(p, invoice: invoice.bolt11)
            let settled = await waitForSettlement(client, invoice.paymentHash)
            result = (amount, settled)
            phase = .success
            Haptics.success()
        } catch {
            let message = PayErrors.text(error)
            self.error = message
            app.show(.error, message)
            Haptics.error()
            phase = .confirm
        }
    }

    /// LNURL-withdraw settles out-of-band: watch the invoice for up to 45 s (lookup every 3 s, or a live notification),
    /// then stop blocking and say it's on the way.
    private func waitForSettlement(_ client: NWCClient, _ hash: String) async -> Bool {
        let deadline = Date().addingTimeInterval(45)
        func notified() -> Bool { app.wallet.lastPayment.map { $0.type == .incoming && $0.paymentHash == hash } ?? false }
        while Date() < deadline {
            if notified() { return true }
            if let tx = try? await client.lookupInvoice(paymentHash: hash), tx.state == .settled || tx.settledAt != nil { return true }
            for _ in 0..<6 {
                try? await Task.sleep(for: .milliseconds(500))
                if notified() { return true }
            }
        }
        return false
    }

    private func done() {
        app.flows.withdraw = nil
        app.popToRoot()
    }
}
