import LaWalletKit
import SwiftUI

/// Signed-in navigation (mirrors `app/wallet/(app)/*`).
enum Route: Hashable {
    case activity
    case activityDetail(TxItem)
    case send, sendAmount, sendPreview, sendSummary
    case receive, receiveAmount, receiveInvoice, receiveSummary
    case scan
    case withdraw
    case claimUsername(fromActivation: Bool, bonus: Bool)
    case activate(String)
    case settings, cards, security, currencies, language, paymentSound, instance
    case remoteWallets
    case remoteWalletDetail(String)
}

/// Signed-out navigation (mirrors `app/wallet/(auth)/*`).
enum AuthRoute: Hashable {
    case signup, createAccount, createPasskey, login, loginNostr, instance
    case activate(String)
}

extension Route {
    @MainActor @ViewBuilder var view: some View {
        switch self {
        case .activity: ActivityScreen()
        case .activityDetail(let tx): ActivityDetailScreen(item: tx)
        case .send: SendRecipientScreen()
        case .sendAmount: SendAmountScreen()
        case .sendPreview: SendPreviewScreen()
        case .sendSummary: SendSummaryScreen()
        case .receive: ReceiveAddressScreen()
        case .receiveAmount: ReceiveAmountScreen()
        case .receiveInvoice: ReceiveInvoiceScreen()
        case .receiveSummary: ReceiveSummaryScreen()
        case .scan: ScanScreen()
        case .withdraw: WithdrawScreen()
        case .claimUsername(let fromActivation, let bonus): ClaimUsernameScreen(fromActivation: fromActivation, bonus: bonus)
        case .activate(let id): ActivateScreen(tokenId: id)
        case .settings: SettingsScreen()
        case .cards: CardsScreen()
        case .security: SecurityScreen()
        case .currencies: CurrenciesScreen()
        case .language: LanguageScreen()
        case .paymentSound: PaymentSoundScreen()
        case .instance: InstanceScreen()
        case .remoteWallets: RemoteWalletsScreen()
        case .remoteWalletDetail(let id): RemoteWalletDetailScreen(walletId: id)
        }
    }
}

extension Route {
    /// Ambient light strength behind the screen: flows that need focus (amount entry, scanning) stay quieter.
    var ambientIntensity: Double {
        switch self {
        case .scan: 0.5  // the camera feed covers it when available
        case .sendAmount, .receiveAmount, .sendPreview, .withdraw: 0.6
        default: 0.8
        }
    }
}

extension AuthRoute {
    var ambientIntensity: Double { 0.9 }

    @MainActor @ViewBuilder var view: some View {
        switch self {
        case .signup: SignupChoiceScreen()
        case .createAccount: CreateAccountScreen()
        case .createPasskey: CreatePasskeyScreen()
        case .login: LoginScreen()
        case .loginNostr: NostrLoginScreen()
        case .instance: InstanceScreen()
        case .activate(let id): ActivateScreen(tokenId: id)
        }
    }
}

/// Routes any scanned / deep-linked / pasted string the same way the web scanner does
/// (`scan-screen.tsx`): activation URL → LNURL (withdraw / pay) → destination (invoice / address).
@MainActor
enum ScanRouter {
    enum Outcome: Equatable { case handled, foreignActivation(URL), unsupported(String) }

    static func route(_ raw: String, app: AppModel, replacingScan: Bool = false) async -> Outcome {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        func go(_ r: Route) {
            if replacingScan, !app.path.isEmpty { app.path.removeLast() }
            app.navigate(r)
        }
        if let link = ActivationLink.parse(text) {
            let own = [app.endpoint.host(), app.instanceURL.host()].compactMap { $0?.lowercased() }
            let host = link.host.split(separator: ":").first.map { String($0).lowercased() } ?? link.host
            if own.contains(host) || own.contains(link.host.lowercased()) { go(.activate(link.tokenId)); return .handled }
            return .foreignActivation(URL(string: text)!)
        }
        if text.lowercased().hasPrefix("nostr+walletconnect://") {
            app.flows.sendInput = text  // RemoteWalletsScreen opens "Add wallet" prefilled with it
            go(.remoteWallets)
            return .handled
        }
        if LNURL.looksLike(text) {
            do {
                switch try await LNURL.resolve(text) {
                case .withdraw(let p):
                    app.flows.withdraw = p
                    go(.withdraw)
                    return .handled
                case .pay(let p):
                    app.flows.resetSend()
                    app.flows.sendInput = text
                    app.flows.payParams = p
                    app.flows.destination = .lnurlPay(url: p.url, address: p.identifier)
                    app.flows.recipientLabel = p.identifier ?? p.url.host()
                    go(.sendAmount)
                    return .handled
                case nil: break
                }
            } catch {
                return .unsupported(error.localizedDescription)
            }
        }
        if let dest = try? Destination.parse(text) {
            app.flows.resetSend()
            app.flows.sendInput = text
            app.flows.destination = dest
            switch dest {
            case .invoice(_, let inv):
                app.flows.sendAmountSats = inv.amountSats ?? 0
                go(inv.amountSats != nil ? .sendPreview : .sendAmount)
            case .lnurlPay(_, let address):
                app.flows.recipientLabel = address
                go(.sendAmount)
            case .npub:
                return .unsupported(t("errors.payment.npubUnsupported"))
            }
            return .handled
        }
        return .unsupported(t("scan.unsupported"))
    }
}
