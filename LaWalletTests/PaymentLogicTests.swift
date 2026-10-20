import LaWalletKit
import XCTest
@testable import LaWallet

@MainActor final class PaymentLogicTests: XCTestCase {
    private let usd: [String: Double] = ["USD": 100_000]
    /// BOLT 11 spec vector "donation of any amount" (no amount field).
    static let zeroAmountInvoice = "lnbc1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygspp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdpl2pkx2ctnv5sxxmmwwd5kgetjypeh2ursdae8g6twvus8g6rfwvs8qun0dfjkxaq9qrsgq357wnc5r2ueh7ck6q93dj32dlqnls087fxdwk8qakdyafkq3yap9us6v52vjjsrvywa6rt52cm9r9zqt8r2t7mlcwspyetp5h2tztugp9lfyql"

    // MARK: PayAmount

    func testSatsRejectsNonPositiveAndGarbage() {
        for raw in ["", "0", "0.0", "-5", "abc"] { XCTAssertNil(PayAmount.sats(raw, "SAT", nil), raw) }
    }

    func testSatsRoundsUpToWholePositiveSat() {
        XCTAssertEqual(PayAmount.sats("21", "SAT", nil), 21)
        XCTAssertEqual(PayAmount.sats("1.2", "SAT", nil), 2)
        XCTAssertEqual(PayAmount.sats("0.4", "SAT", nil), 1)
    }

    func testSatsFromBTC() {
        XCTAssertEqual(PayAmount.sats("1", "BTC", nil), 100_000_000)
        XCTAssertEqual(PayAmount.sats("0.00000001", "BTC", nil), 1)
        XCTAssertEqual(PayAmount.sats("0.1", "BTC", nil), 10_000_000)
        XCTAssertEqual(PayAmount.sats("0.000000015", "BTC", nil), 2)
    }

    func testSatsFromBTCIgnoresFloatNoiseAtLargeMagnitudes() {
        // 1.1 * 1e8 == 110000000.00000001 in Double; must not round up to 110,000,001.
        XCTAssertEqual(PayAmount.sats("1.1", "BTC", nil), 110_000_000)
        XCTAssertEqual(PayAmount.sats("20999999.12345678", "BTC", nil), 2_099_999_912_345_678)
    }

    func testSatsRejectsImpossibleAmountsInsteadOfTrapping() {
        XCTAssertNil(PayAmount.sats("99999999999", "BTC", nil))
        XCTAssertNil(PayAmount.sats("1e300", "SAT", nil))
        XCTAssertNil(PayAmount.sats("999999999999", "USD", ["USD": 0.000001]))
    }

    func testSatsFromFiat() {
        XCTAssertEqual(PayAmount.sats("1", "USD", usd), 1000)
        XCTAssertEqual(PayAmount.sats("0.01", "USD", usd), 10)
        XCTAssertEqual(PayAmount.sats("1", "USD", ["USD": 60_000]), 1667)
        XCTAssertEqual(PayAmount.sats("0.0001", "USD", usd), 1)
    }

    func testSatsWithoutRateIsNil() {
        XCTAssertNil(PayAmount.sats("1", "USD", nil))
        XCTAssertNil(PayAmount.sats("1", "USD", ["EUR": 90_000]))
        XCTAssertNil(PayAmount.sats("1", "USD", ["USD": 0]))
    }

    func testFormatFromSats() {
        XCTAssertEqual(PayAmount.format(nil, "SAT", nil), "0")
        XCTAssertEqual(PayAmount.format(0, "BTC", nil), "0")
        XCTAssertEqual(PayAmount.format(-5, "SAT", nil), "0")
        XCTAssertEqual(PayAmount.format(21, "SAT", nil), "21")
        XCTAssertEqual(PayAmount.format(1, "BTC", nil), "0.00000001")
        XCTAssertEqual(PayAmount.format(150_000_000, "BTC", nil), "1.5")
        XCTAssertEqual(PayAmount.format(100_000_000, "BTC", nil), "1")
    }

    func testFormatFiatTwoDecimalsWithFloor() {
        XCTAssertEqual(PayAmount.format(1000, "USD", usd), "1.00")
        XCTAssertEqual(PayAmount.format(123_456, "USD", usd), "123.46")
        XCTAssertEqual(PayAmount.format(1, "USD", usd), "0.01")
        XCTAssertEqual(PayAmount.format(1000, "USD", nil), "0")
    }

    func testTrimmed() {
        XCTAssertEqual(PayAmount.trimmed(1.5, 8), "1.5")
        XCTAssertEqual(PayAmount.trimmed(2, 8), "2")
        XCTAssertEqual(PayAmount.trimmed(0, 8), "0")
        XCTAssertEqual(PayAmount.trimmed(0.123456789, 8), "0.12345679")
        XCTAssertEqual(PayAmount.trimmed(100, 0), "100")
    }

    func testDecimals() {
        XCTAssertEqual(PayAmount.decimals("SAT"), 0)
        XCTAssertEqual(PayAmount.decimals("BTC"), 8)
        XCTAssertEqual(PayAmount.decimals("USD"), 2)
        XCTAssertEqual(PayAmount.decimals("XYZ"), 2)
    }

    // MARK: PayErrors

    func testDestinationErrorsAreLocalized() {
        let cases: [(Destination.ParseError, String)] = [(.empty, "empty"), (.unsupported, "unsupported"), (.invalidInvoice, "invalidInvoice"),
                                                         (.invalidLnurl, "invalidLnurl"), (.invalidAddress, "invalidAddress")]
        for (e, name) in cases {
            let key = "errors.destination.\(name)"
            XCTAssertEqual(PayErrors.text(e), t(key))
            XCTAssertNotEqual(PayErrors.text(e), key, "missing translation")
        }
    }

    func testHelperLNURLErrorsAreLocalized() {
        let codes: [LNURLError.Code] = [.unreachable, .invalidResponse, .unsupported, .missingFields, .noAmount, .belowOneSat, .invalidCallback]
        for code in codes {
            XCTAssertEqual(PayErrors.text(LNURLError(code, "raw")), t("errors.lnurl.\(code.rawValue)"))
            XCTAssertNotEqual(PayErrors.text(LNURLError(code, "raw")), "errors.lnurl.\(code.rawValue)", "missing translation")
        }
    }

    func testServiceLNURLErrorsPassThrough() {
        XCTAssertEqual(PayErrors.text(LNURLError(.rejected, "Amount too low")), "Amount too low")
        XCTAssertEqual(PayErrors.text(LNURLError(.endpointError, "")), t("errors.nwc.generic"))
        XCTAssertEqual(PayErrors.text(LNURLError(.httpStatus, ""), fallback: "fb"), "fb")
    }

    func testRelayErrors() {
        XCTAssertEqual(PayErrors.text(RelayError.timeout), t("errors.nwc.timeout"))
        XCTAssertEqual(PayErrors.text(RelayError.notConnected), t("errors.nwc.relayOffline"))
        XCTAssertEqual(PayErrors.text(RelayError.rejected("blocked: spam")), "blocked: spam")
        XCTAssertEqual(PayErrors.text(RelayError.rejected("")), t("errors.nwc.generic"))
    }

    func testNWCAndOtherErrors() {
        struct Plain: Error {}
        XCTAssertEqual(PayErrors.text(NWCError.timeout), t("errors.nwc.timeout"))
        XCTAssertEqual(PayErrors.text(NWCError.wallet(code: "INSUFFICIENT_BALANCE", message: "Not enough funds")), "Not enough funds")
        XCTAssertEqual(PayErrors.text(PayError("boom")), "boom")
        XCTAssertEqual(PayErrors.text(Plain()), t("errors.nwc.generic"))
        XCTAssertEqual(PayErrors.text(Plain(), fallback: "fb"), "fb")
    }

    // MARK: PayAvatar / receipts

    func testAvatarInitials() {
        XCTAssertEqual(PayAvatar.initials("satoshi@lawallet.io"), "SA")
        XCTAssertEqual(PayAvatar.initials("john.doe@x.com"), "JD")
        XCTAssertEqual(PayAvatar.initials("Mary Jane"), "MJ")
        XCTAssertEqual(PayAvatar.initials("x_y_z"), "XY")
        XCTAssertEqual(PayAvatar.initials("a"), "A")
        XCTAssertEqual(PayAvatar.initials(""), "?")
        XCTAssertEqual(PayAvatar.initials("__"), "?")
    }

    func testReceiptMinimal() {
        let l = "shared.receipt.text."
        let text = PayReceiptText.build(amount: "21 sats", date: nil, paymentHash: nil, preimage: nil)
        XCTAssertEqual(text.components(separatedBy: "\n"),
                       [t(l + "title"), "", "\(t(l + "status")): \(t("shared.receipt.settled"))", "\(t(l + "amount")): 21 sats"])
    }

    func testReceiptOptionalLines() {
        let l = "shared.receipt.text."
        let lines = PayReceiptText.build(amount: "21 sats", fee: "1 sat", recipient: " alice ", destination: "alice@x.io", comment: "gm",
                                         date: Date(), paymentHash: "abc", preimage: "def").components(separatedBy: "\n")
        XCTAssertTrue(lines.contains("\(t(l + "fee")): 1 sat"))
        XCTAssertTrue(lines.contains("\(t(l + "to")): alice"))
        XCTAssertTrue(lines.contains("\(t(l + "destination")): alice@x.io"))
        XCTAssertTrue(lines.contains("\(t(l + "note")): gm"))
        XCTAssertTrue(lines.contains { $0.hasPrefix("\(t(l + "time")): ") })
        XCTAssertEqual(Array(lines.suffix(6)), ["", "\(t(l + "paymentHash")):", "abc", "", "\(t(l + "preimage")):", "def"])
    }

    func testReceiptSkipsBlankAndDuplicateFields() {
        let l = "shared.receipt.text."
        let text = PayReceiptText.build(amount: "1", fee: "", recipient: "   ", destination: "", comment: "", date: nil, paymentHash: "", preimage: "")
        XCTAssertEqual(text.components(separatedBy: "\n").count, 4)
        let same = PayReceiptText.build(amount: "1", recipient: "bob@x.io", destination: "bob@x.io", date: nil, paymentHash: nil, preimage: nil)
        XCTAssertFalse(same.contains(t(l + "destination")))
    }

    // MARK: LightningSuggestions

    func testCurrentDomain() {
        XCTAssertEqual(LightningSuggestions.currentDomain(nil), "lawallet.io")
        XCTAssertEqual(LightningSuggestions.currentDomain("alice@LaCrypta.AR"), "lacrypta.ar")
        XCTAssertEqual(LightningSuggestions.currentDomain("alice@sub.domain.com"), "sub.domain.com")
        XCTAssertEqual(LightningSuggestions.currentDomain("alice@localhost"), "lawallet.io")
        XCTAssertEqual(LightningSuggestions.currentDomain(""), "lawallet.io")
    }

    func testSuggestionMatches() {
        let a = "alice@lawallet.io"
        XCTAssertTrue(LightningSuggestions.matches(a, ""))
        XCTAssertTrue(LightningSuggestions.matches(a, "ALI"))
        XCTAssertTrue(LightningSuggestions.matches(a, "alice@law"))
        XCTAssertFalse(LightningSuggestions.matches(a, "bob"))
        XCTAssertFalse(LightningSuggestions.matches(a, "lawallet"))
        XCTAssertFalse(LightningSuggestions.matches(a, "alice@x"))
    }

    func testBuildSuggestionsForUsername() {
        let out = LightningSuggestions.build("alice", currentDomain: "lawallet.io")
        XCTAssertEqual(out.count, 10)
        XCTAssertEqual(Set(out).count, out.count)
        XCTAssertEqual(out.first, "alice@lawallet.io")
        XCTAssertEqual(LightningSuggestions.build("alice@", currentDomain: "lawallet.io"), out)
        XCTAssertEqual(LightningSuggestions.build("  Lightning:ALICE ", currentDomain: "lawallet.io"), out)
    }

    func testBuildSuggestionsPutsCurrentDomainFirst() {
        let out = LightningSuggestions.build("bob", currentDomain: "custom.org")
        XCTAssertEqual(Array(out.prefix(2)), ["bob@custom.org", "bob@lawallet.io"])
        XCTAssertEqual(LightningSuggestions.build("bob", currentDomain: "blink.sv").filter { $0 == "bob@blink.sv" }.count, 1)
        XCTAssertEqual(LightningSuggestions.build("bob", currentDomain: "lawallet.io", limit: 3).count, 3)
    }

    func testBuildSuggestionsFiltersByDomainQuery() {
        XCTAssertEqual(LightningSuggestions.build("alice@st", currentDomain: "lawallet.io"), ["alice@strike.me"])
        XCTAssertEqual(LightningSuggestions.build("Alice@BL", currentDomain: "lawallet.io"), ["alice@blink.sv"])
        XCTAssertEqual(LightningSuggestions.build("alice@zzz", currentDomain: "lawallet.io"), [])
    }

    func testBuildSuggestionsSkipsNonUsernames() {
        for input in ["", "   ", "lnbc1abc", "LNURL1DP68", "npub1abc", "al ice", "al!ce", String(repeating: "a", count: 65)] {
            XCTAssertEqual(LightningSuggestions.build(input, currentDomain: "lawallet.io"), [], input)
        }
    }

    // MARK: NFC

    func testBoltcardURLPrefersWithdrawLinks() {
        XCTAssertEqual(NFCReader.firstBoltcardURL(["https://a.io/x", "lnurlw://card.io/w?p=1"]), "lnurlw://card.io/w?p=1")
        XCTAssertEqual(NFCReader.firstBoltcardURL(["https://a.io/x", "LNURL1DP68GURN"]), "LNURL1DP68GURN")
        XCTAssertEqual(NFCReader.firstBoltcardURL(["lnurlp://x.io/p", "https://y.io"]), "lnurlp://x.io/p")
        XCTAssertEqual(NFCReader.firstBoltcardURL(["en", "https://a.io/x"]), "https://a.io/x")
    }

    func testBoltcardURLCleansAndRejects() {
        XCTAssertEqual(NFCReader.firstBoltcardURL(["\u{0}lnurlw://card.io/w\n"]), "lnurlw://card.io/w")
        XCTAssertNil(NFCReader.firstBoltcardURL([]))
        XCTAssertNil(NFCReader.firstBoltcardURL(["hello", "ftp://x.io", "mailto:a@b.c"]))
    }

    // MARK: send preview / receive / claim

    func testPreviewEquivalent() {
        XCTAssertEqual(SendPreviewScreen.equivalent(21, "SAT", nil), "21")
        XCTAssertEqual(SendPreviewScreen.equivalent(150_000_000, "BTC", nil), "1.5")
        XCTAssertEqual(SendPreviewScreen.equivalent(1, "BTC", nil), "0.00000001")
        XCTAssertEqual(SendPreviewScreen.equivalent(1000, "USD", usd), "1")
        XCTAssertEqual(SendPreviewScreen.equivalent(1234, "USD", usd), 1.23.formatted())
        XCTAssertEqual(SendPreviewScreen.equivalent(150_678, "USD", usd), "151")
        XCTAssertEqual(SendPreviewScreen.equivalent(1000, "USD", nil), "...")
    }

    func testInvoiceClock() {
        XCTAssertEqual(ReceiveInvoiceScreen.clock(0), "0:00")
        XCTAssertEqual(ReceiveInvoiceScreen.clock(59), "0:59")
        XCTAssertEqual(ReceiveInvoiceScreen.clock(61), "1:01")
        XCTAssertEqual(ReceiveInvoiceScreen.clock(3600), "1:00:00")
        XCTAssertEqual(ReceiveInvoiceScreen.clock(86_399), "23:59:59")
    }

    func testClaimBalancesFromSnapshot() {
        var b = ClaimCelebration.balances(snapshot: 500, live: 9999, amount: 100, settled: true)
        XCTAssertEqual(b.before, 500); XCTAssertEqual(b.after, 600)
        b = ClaimCelebration.balances(snapshot: 500, live: nil, amount: 100, settled: false)
        XCTAssertEqual(b.before, 500); XCTAssertEqual(b.after, 500)
        b = ClaimCelebration.balances(snapshot: -5, live: nil, amount: 100, settled: true)
        XCTAssertEqual(b.before, 0); XCTAssertEqual(b.after, 100)
    }

    func testClaimBalancesFromLiveBalance() {
        var b = ClaimCelebration.balances(snapshot: nil, live: 600, amount: 100, settled: true)
        XCTAssertEqual(b.before, 500); XCTAssertEqual(b.after, 600)
        b = ClaimCelebration.balances(snapshot: nil, live: 50, amount: 100, settled: true)
        XCTAssertEqual(b.before, 50); XCTAssertEqual(b.after, 150)
        b = ClaimCelebration.balances(snapshot: nil, live: 600, amount: 100, settled: false)
        XCTAssertEqual(b.before, 600); XCTAssertEqual(b.after, 600)
        b = ClaimCelebration.balances(snapshot: nil, live: nil, amount: 100, settled: true)
        XCTAssertNil(b.before); XCTAssertNil(b.after)
    }

    func testClaimPourShare() {
        XCTAssertEqual(ClaimCelebration.pourShare(100, 0), 0)
        XCTAssertEqual(ClaimCelebration.pourShare(0, 100), 1)
        XCTAssertEqual(ClaimCelebration.pourShare(100, 100), 0.5)
        XCTAssertEqual(ClaimCelebration.pourShare(1000, 1), 0.26)
        XCTAssertEqual(ClaimCelebration.pourShare(1, 1000), 0.78)
    }

    // MARK: ScanRouter (branches beyond LogicTests)

    func testScanRouterOwnHostWithPortActivates() async throws {
        let app = AppModel()
        let host = try XCTUnwrap(app.instanceURL.host())
        let outcome = await ScanRouter.route("https://\(host):8443/wallet/activate/tok_1", app: app)
        XCTAssertEqual(outcome, .handled)
        XCTAssertEqual(app.path, [.activate("tok_1")])
    }

    func testScanRouterWalletConnectOpensRemoteWallets() async {
        let app = AppModel()
        app.path = [.scan]
        let uri = "nostr+walletconnect://b889ff5b1513b641e2a139f661a661364979c5beee91842f8f0ef42ab558e9d4?relay=wss%3A%2F%2Frelay.damus.io&secret=71a8c14c1407c113601079c4302dab36460f0ccd0ad506f1f2dc73b5100e4f3c"
        let outcome = await ScanRouter.route("  \(uri)\n", app: app, replacingScan: true)
        XCTAssertEqual(outcome, .handled)
        XCTAssertEqual(app.path, [.remoteWallets])
        XCTAssertEqual(app.flows.sendInput, uri)
    }

    func testScanRouterZeroAmountInvoiceAsksForAmount() async {
        let app = AppModel()
        let outcome = await ScanRouter.route("lightning:" + Self.zeroAmountInvoice, app: app)
        XCTAssertEqual(outcome, .handled)
        XCTAssertEqual(app.path, [.sendAmount])
        XCTAssertEqual(app.flows.sendAmountSats, 0)
    }

    func testScanRouterNpubIsUnsupported() async {
        let app = AppModel()
        let outcome = await ScanRouter.route("npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6", app: app)
        XCTAssertEqual(outcome, .unsupported(t("errors.payment.npubUnsupported")))
        XCTAssertEqual(app.path, [])
    }
}
