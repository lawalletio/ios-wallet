import Foundation
import Testing
@testable import LaWalletKit

@Suite struct LightningTests {
    // BOLT11 spec example ("1 cup coffee", 2500u, expiry 60s).
    let coffee = "lnbc2500u1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygspp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdq5xysxxatsyp3k7enxv4jsxqzpu9qrsgquk0rl77nj30yxdy8j9vdx85fkpmdla2087ne0xh8nhedh8w27kyke0lp53ut353s06fv3qfegext0eh0ymjpf39tuven09sam30g4vgpfna3rh"

    @Test func bolt11Decode() throws {
        let inv = try #require(Bolt11.decode(coffee))
        #expect(inv.network == "bc")
        #expect(inv.amountSats == 250_000)
        #expect(inv.description == "1 cup coffee")
        #expect(inv.paymentHash == "0001020304050607080900010203040506070809000102030405060708090102")
        #expect(inv.expirySeconds == 60)
        #expect(inv.timestamp == Date(timeIntervalSince1970: 1_496_314_658))
        #expect(Bolt11.decode("lightning:" + coffee.uppercased())?.amountSats == 250_000)
        #expect(Bolt11.decode("lnbc1notaninvoice") == nil)
    }

    @Test func destinationPriority() throws {
        guard case .invoice(_, let d) = try Destination.parse("lightning:" + coffee) else { Issue.record("not invoice"); return }
        #expect(d.amountSats == 250_000)

        guard case .lnurlPay(let url, let address) = try Destination.parse("  Satoshi@LaWallet.io ") else { Issue.record(); return }
        #expect(url.absoluteString == "https://lawallet.io/.well-known/lnurlp/Satoshi")
        #expect(address == "Satoshi@LaWallet.io")

        #expect(try Destination.parse("npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg")
            == .npub("npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg"))
        #expect(throws: Destination.ParseError.empty) { try Destination.parse("  ") }
        #expect(throws: Destination.ParseError.unsupported) { try Destination.parse("hello") }
        #expect(throws: Destination.ParseError.invalidInvoice) { try Destination.parse("lnbc1qqqq") }
    }

    @Test func lnurlDecoding() {
        // LUD-01 example.
        let lnurl = "LNURL1DP68GURN8GHJ7UM9WFMXJCM99E3K7MF0V9CXJ0M385EKVCENXC6R2C35XVUKXEFCV5MKVV34X5EKZD3EV56NYD3HXQURZEPEXEJXXEPNXSCRVWFNV9NXZCN9XQ6XYEFHVGCXXCMYXYMNSERXFQ5FNS"
        #expect(LNURL.toHTTPURL(lnurl)?.absoluteString
            == "https://service.com/api?q=3fc3645b439ce8e7f2553a69e5267081d96dcd340693afabe04be7b0ccd178df")
        #expect(LNURL.toHTTPURL("lnurlw://beta.lawallet.io/api/cards/x/scan?p=1&c=2")?.absoluteString
            == "https://beta.lawallet.io/api/cards/x/scan?p=1&c=2")
        #expect(LNURL.toHTTPURL("lnurlp://abc.onion/x")?.scheme == "http")
        #expect(LNURL.looksLike(lnurl))
        #expect(LNURL.looksLike("lightning:lnurlw://host/x"))
        #expect(LNURL.looksLike("https://h.com/w?tag=withdrawRequest&k1=1"))
        #expect(!LNURL.looksLike("https://example.com"))
        #expect(!LNURL.looksLike("satoshi@lawallet.io"))
    }

    @Test func withdrawParamsClampToWholeSats() throws {
        let json: JSONValue = ["tag": "withdrawRequest", "callback": "https://h/cb", "k1": "abc", "minWithdrawable": 1500,
                               "maxWithdrawable": 10_999, "defaultDescription": "gift"]
        let p = try LNURL.withdrawParams(json, url: URL(string: "https://h.io:8443/w")!)
        #expect(p.minWithdrawableSats == 2 && p.maxWithdrawableSats == 10 && p.host == "h.io:8443")
        #expect(throws: LNURLError.self) {
            try LNURL.withdrawParams(["tag": "withdrawRequest", "callback": "x", "k1": "y", "maxWithdrawable": 500], url: URL(string: "https://h")!)
        }
    }

    @Test func payMetadata() throws {
        let meta = #"[["text/plain","Pay to satoshi"],["text/identifier","satoshi@lawallet.io"]]"#
        let p = try LNURL.payParams(["callback": "https://h/cb", "minSendable": 1000, "maxSendable": 100_000_000,
                                      "metadata": .string(meta), "commentAllowed": 140], url: URL(string: "https://h")!)
        #expect(p.text == "Pay to satoshi" && p.identifier == "satoshi@lawallet.io")
        #expect(p.minSendableSats == 1 && p.maxSendableSats == 100_000 && p.commentAllowed == 140)
    }

    @Test func activationLinks() {
        #expect(ActivationLink.parse("https://beta.lawallet.io/wallet/activate/abc123/")
            == ActivationLink(tokenId: "abc123", host: "beta.lawallet.io"))
        #expect(ActivationLink.parse("http://localhost:3227/wallet/activate/x_y-z")?.host == "localhost:3227")
        #expect(ActivationLink.parse("https://h/wallet/activate") == nil)
        #expect(ActivationLink.parse("lnurlw://h/wallet/activate/x") == nil)
    }

    @Test func nwcURI() throws {
        let pk = String(repeating: "a", count: 64), secret = String(repeating: "1", count: 64)
        let c = try NWCConnection(uri: "nostr+walletconnect://\(pk)?relay=wss%3A%2F%2Frelay.getalby.com%2Fv1&secret=\(secret)&lud16=me%40lncurl.lol")
        #expect(c.walletPubkey == pk && c.relays == [URL(string: "wss://relay.getalby.com/v1")!] && c.lud16 == "me@lncurl.lol")
        #expect(throws: NWCError.invalidURI) { try NWCConnection(uri: "nostr+walletconnect://\(pk)?secret=\(secret)") }
    }

    @Test func nwcTransactionNormalizes() {
        let tx = NWCTransaction(raw: ["type": "outgoing", "amount": 21_000, "fees_paid": 2000, "payment_hash": "ff",
                                      "created_at": 1_700_000_000, "settled_at": 1_700_000_001])
        #expect(tx?.amountSats == 21 && tx?.feesPaidSats == 2 && tx?.state == .settled && tx?.type == .outgoing)
        #expect(NWCTransaction(raw: ["type": "incoming", "amount": 1000, "payment_hash": "ee", "created_at": 1])?.state == .pending)
        #expect(NWCTransaction(raw: ["amount": 1000]) == nil)
    }
}

@Suite struct AuthAndCurrencyTests {
    @Test func prfDerivationFrozenVector() {
        // Same frozen vector as apps/web/tests/unit/lib/client/passkey-prf.test.ts.
        #expect(PasskeyPRF.deriveSecret(prfOutput: Data(repeating: 7, count: 32)).hex
            == "a1e1ac8dd866cabdf743a4cdedbf53c680444094a25c0ffc4e558ec5a78831c1")
        #expect("lawallet-nsec-prf-v1".sha256Hex == PasskeyPRF.saltHex)
    }

    @Test func nip98Token() async throws {
        let signer = LocalSigner(keys: .generate())
        let body = Data(#"{"expiresIn":"24h"}"#.utf8)
        let header = try await NIP98.header(url: "https://beta.lawallet.io/api/jwt", method: "post", body: body, signer: signer)
        #expect(header.hasPrefix("Nostr "))
        let ev = try JSONDecoder().decode(NostrEvent.self, from: Data(base64Encoded: String(header.dropFirst(6)))!)
        #expect(ev.isValid && ev.kind == 27235)
        #expect(ev.tag("u") == "https://beta.lawallet.io/api/jwt" && ev.tag("method") == "POST")
        #expect(ev.tag("payload") == body.sha256.hex)
        let get = try await NIP98.token(url: "https://h/api/events", signer: signer)
        let ev2 = try JSONDecoder().decode(NostrEvent.self, from: Data(base64Encoded: get)!)
        #expect(ev2.tag("payload") == nil && ev2.tag("method") == "GET")
    }

    @Test func currencyMath() {
        let rates = ["USD": 100_000.0, "ARS": 100_000_000.0]
        #expect(Currencies.convert(sats: 50_000, to: "USD", rates: rates) == 50)
        #expect(Currencies.convert(sats: 1, to: "BTC", rates: nil) == 0.00000001)
        #expect(Currencies.convert(sats: 1, to: "USD", rates: nil) == nil)
        #expect(Currencies.toSats(1, from: "USD", rates: rates) == 1000)
        let en = Locale(identifier: "en_US")
        #expect(Currencies.format(sats: 1_234_567, code: "SAT", rates: nil, locale: en) == "1,234,567")
        #expect(Currencies.format(sats: 1, code: "BTC", rates: nil, locale: en) == "0.00000001")
        #expect(Currencies.format(sats: 1, code: "USD", rates: rates, locale: en) == "< 0.01")
        #expect(Currencies.format(sats: 1, code: "EUR", rates: rates, locale: en) == "—")
        let n = Currencies.normalize(active: ["USD", "SAT", "XXX", "USD"], selected: "EUR")
        #expect(n.active == ["SAT", "USD"] && n.selected == "SAT")
    }
}
