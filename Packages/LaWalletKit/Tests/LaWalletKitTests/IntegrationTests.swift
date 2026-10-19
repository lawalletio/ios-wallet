import Foundation
import Testing
@testable import LaWalletKit

/// End-to-end against a live instance. Opt-in:
///   LAWALLET_E2E_URL=http://localhost:3774 swift test --filter Integration
///   LAWALLET_E2E_URL=https://beta.lawallet.io swift test --filter Integration
private let e2eURL = ProcessInfo.processInfo.environment["LAWALLET_E2E_URL"].flatMap(URL.init(string:))

@Suite(.enabled(if: e2eURL != nil), .serialized) struct IntegrationTests {
    @Test func newAccountGetsWalletAndAddress() async throws {
        let settings = try await LaWalletAPI.probe(e2eURL!)
        let base = settings.endpoint.flatMap(URL.init(string:)) ?? e2eURL!
        let signer = LocalSigner(keys: .generate())

        // NIP-98 → JWT, bound to the instance's public endpoint.
        let bootstrap = LaWalletAPI(http: HTTPClient(baseURL: base))
        let jwt = try await bootstrap.mintJWT(signer: signer)
        #expect(!jwt.token.isEmpty)
        let api = LaWalletAPI(http: HTTPClient(baseURL: base, bearer: { jwt.token }))
        #expect(try await api.jwtInfo().pubkey == signer.keys.publicKey)

        // First /me materializes the user and (with lncurl_auto_create) a courtesy NWC wallet.
        var me: CurrentUser?
        for attempt in 0..<4 {
            do { me = try await api.me(); break } catch let e as APIError where e.status == 503 && attempt < 3 {
                try await Task.sleep(for: .seconds(2))
            }
        }
        _ = try #require(me)

        // Claim a lightning address: the courtesy wallet minted at signup is routed through the primary address.
        let username = "ios" + Data.random(4).hex
        #expect(try await api.checkUsername(username))
        do {
            let address = try await api.createAddress(username)
            #expect(address.username == username)
        } catch let e as APIError where e.status == 402 {
            // Paid registration: the instance must hand out a LUD-21 invoice instead.
            let inv = try await api.registrationInvoice(username: username)
            #expect(inv.free == true || inv.bolt11.flatMap(Bolt11.decode) != nil)
            return
        }
        let user = try await api.me()
        #expect(user.lightningAddress?.hasPrefix(username + "@") == true)

        var nwcURI = user.nwc
        if nwcURI == nil {
            // Courtesy wallet unavailable (e.g. LNCurl down): attach one explicitly, like Settings → Remote wallets.
            if (try? await api.createLncurlWallet(isDefault: true)) == nil,
               let external = ProcessInfo.processInfo.environment["LAWALLET_E2E_NWC"] {
                _ = try await api.createNWCWallet(name: "e2e", connectionString: external, sendReceive: true, isDefault: true)
            }
            nwcURI = try await api.me().nwc
        }
        let uri = try #require(nwcURI, "no NWC wallet: LNCurl failed and LAWALLET_E2E_NWC is unset")
        let wallets = try await api.remoteWallets()
        #expect(wallets.contains { $0.isDefault && $0.isActive })

        // NWC round-trip over the wallet's relay.
        let nwc = try NWCClient(uri: uri)
        let info = try await nwc.getInfo()
        #expect(info.methods.contains("make_invoice"))
        let balance = try await nwc.getBalanceSats()
        #expect(balance >= 0)
        let invoice = try await nwc.makeInvoice(amountSats: 21, description: "ios e2e")
        #expect(Bolt11.decode(invoice.bolt11)?.amountSats == 21)
        _ = try await nwc.listTransactions(limit: 5)

        // LUD-16 on the new address resolves to a payable invoice.
        let lud16 = URL(string: base.absoluteString + "/.well-known/lnurlp/\(username)")!
        guard case .pay(let params) = try await LNURL.resolve(url: lud16) else { Issue.record("not a pay request"); return }
        let pr = try await LNURL.requestInvoice(params, amountSats: 5, comment: "hi")
        #expect(Bolt11.decode(pr.pr)?.amountSats == 5)

        // Real send when the wallet is funded (faucet-backed local LNCurl): pay our own address' invoice from a second wallet.
        if let payerURI = ProcessInfo.processInfo.environment["LAWALLET_E2E_PAYER_NWC"] {
            let payer = try NWCClient(uri: payerURI)
            let notifications = await nwc.notifications()
            let paid = try await payer.payInvoice(pr.pr)
            #expect(!paid.preimage.isEmpty)
            let got: NWCNotification? = try? await withTimeout(.seconds(30)) {
                for await n in notifications where n.type == "payment_received" { return n }
                return nil
            }
            #expect(got?.transaction.amountSats == 5)
            #expect(try await nwc.getBalanceSats() == balance + 5)
        }

        // Misc wallet surfaces a fresh account can read.
        #expect(try await api.cards().isEmpty)
        try await api.saveCurrencyPrefs(CurrencyPrefs(active: ["SAT", "USD"], selected: "USD"))
        #expect(try await api.me().currencyPrefs?.selected == "USD")

        // SSE accepts a NIP-98 query token signed over the bare events URL.
        let token = try await NIP98.token(url: base.absoluteString + "/api/events", signer: signer)
        var comps = URLComponents(string: base.absoluteString + "/api/events")!
        comps.queryItems = [URLQueryItem(name: "token", value: token)]
        let (bytes, resp) = try await URLSession.shared.bytes(from: comps.url!)
        #expect((resp as? HTTPURLResponse)?.statusCode == 200)
        var first: String?
        for try await line in bytes.lines { first = line; break }
        #expect(first == "event: connected")
    }
}
