import LaWalletKit
import XCTest
@testable import LaWallet

@MainActor final class StoreTests: XCTestCase {
    private static let keys = ["lawallet-active-currencies", "lawallet-contacts"]
    private var saved: [String: Any] = [:]

    override func setUp() async throws {
        saved = [:]
        for k in Self.keys {
            saved[k] = UserDefaults.standard.object(forKey: k)
            UserDefaults.standard.removeObject(forKey: k)
        }
        ContactsStore.shared.clear()
    }

    override func tearDown() async throws {
        ContactsStore.shared.clear()
        for k in Self.keys {
            if let v = saved[k] { UserDefaults.standard.set(v, forKey: k) } else { UserDefaults.standard.removeObject(forKey: k) }
        }
    }

    // MARK: CurrencyStore

    func testCycleWrapsThroughActive() {
        let store = CurrencyStore()
        XCTAssertEqual(store.active, ["SAT", "BTC"])
        XCTAssertEqual(store.selected, "SAT")
        store.cycle()
        XCTAssertEqual(store.selected, "BTC")
        store.cycle()
        XCTAssertEqual(store.selected, "SAT")
    }

    func testSetActiveNormalizesSyncsAndPersists() {
        let store = CurrencyStore()
        var synced: CurrencyPrefs?
        store.persist = { synced = $0 }
        store.setActive(["USD", "BTC", "USD", "XYZ"])
        XCTAssertEqual(store.active, ["SAT", "USD", "BTC"])
        XCTAssertEqual(synced, CurrencyPrefs(active: ["SAT", "USD", "BTC"], selected: "SAT"))
        XCTAssertEqual(CurrencyStore().active, ["SAT", "USD", "BTC"])
    }

    func testSetActiveDroppingSelectedFallsBackToSat() {
        let store = CurrencyStore()
        store.selected = "BTC"
        store.setActive(["USD"])
        XCTAssertEqual(store.active, ["SAT", "USD"])
        XCTAssertEqual(store.selected, "SAT")
        store.setActive([])
        XCTAssertEqual(store.active, ["SAT"])
        store.cycle()
        XCTAssertEqual(store.selected, "SAT")
        XCTAssertEqual(CurrencyStore().selected, "SAT")
    }

    // MARK: ContactsStore

    func testRememberDedupesCaseInsensitivelyNewestFirst() {
        let c = ContactsStore.shared
        c.remember("bob@x.io")
        c.remember("Alice@X.io", name: "A")
        c.remember("carol@x.io")
        c.remember("alice@x.io", name: "Alice", avatar: "https://x.io/a.png")
        XCTAssertEqual(c.contacts.map(\.address), ["alice@x.io", "carol@x.io", "bob@x.io"])
        XCTAssertEqual(c.contacts.first?.name, "Alice")
        XCTAssertEqual(c.contacts.first?.avatar, "https://x.io/a.png")
    }

    func testRememberKeepsTwentyMostRecent() {
        let c = ContactsStore.shared
        for i in 0..<25 { c.remember("u\(i)@x.io") }
        XCTAssertEqual(c.contacts.count, 20)
        XCTAssertEqual(c.contacts.first?.address, "u24@x.io")
        XCTAssertEqual(c.contacts.last?.address, "u5@x.io")
    }

    // MARK: FlowState.payRecipient

    private func lnurl(_ address: String?) -> Destination {
        .lnurlPay(url: URL(string: "https://example.com/.well-known/lnurlp/alice")!, address: address)
    }

    func testRecipientNilWithoutDestination() {
        XCTAssertNil(FlowState().payRecipient)
    }

    func testRecipientFromAddressLocalPart() throws {
        let f = FlowState()
        f.destination = lnurl("Alice@Example.com")
        let r = try XCTUnwrap(f.payRecipient)
        XCTAssertEqual(r.name, "alice")
        XCTAssertEqual(r.subtitle, "alice@example.com")
        XCTAssertEqual(r.address, "alice@example.com")
        XCTAssertEqual(r.avatar, AddressSuggestions.avatar("example.com"))
    }

    func testRecipientSavedContactWins() throws {
        ContactsStore.shared.remember("ALICE@example.com", name: " Alice A ", avatar: "https://x.io/a.png")
        let f = FlowState()
        f.destination = lnurl("alice@example.com")
        f.recipientLabel = "label"
        f.recipientAvatar = URL(string: "https://x.io/other.png")
        let r = try XCTUnwrap(f.payRecipient)
        XCTAssertEqual(r.name, "Alice A")
        XCTAssertEqual(r.avatar, URL(string: "https://x.io/a.png"))
    }

    func testRecipientBlankContactNameFallsThrough() throws {
        ContactsStore.shared.remember("alice@example.com", name: "   ")
        let f = FlowState()
        f.destination = lnurl("alice@example.com")
        f.recipientAvatar = URL(string: "https://x.io/other.png")
        let r = try XCTUnwrap(f.payRecipient)
        XCTAssertEqual(r.name, "alice")
        XCTAssertEqual(r.avatar, URL(string: "https://x.io/other.png"))
    }

    func testRecipientWithoutAddressUsesLabelThenInput() throws {
        let f = FlowState()
        f.destination = lnurl(nil)
        f.sendInput = "lnurl1dp68gurn"
        f.recipientLabel = "shop.example"
        var r = try XCTUnwrap(f.payRecipient)
        XCTAssertEqual(r.name, "shop.example")
        XCTAssertEqual(r.subtitle, t("send.kind.address"))
        XCTAssertNil(r.address)
        f.recipientLabel = nil
        r = try XCTUnwrap(f.payRecipient)
        XCTAssertEqual(r.name, "lnurl1dp68gurn")
    }

    func testRecipientKindSubtitles() throws {
        let f = FlowState()
        f.sendInput = "npub1abc"
        f.destination = .npub("npub1abc")
        XCTAssertEqual(try XCTUnwrap(f.payRecipient).subtitle, t("send.kind.nostrProfile"))
        let bolt11 = PaymentLogicTests.zeroAmountInvoice
        f.destination = .invoice(bolt11: bolt11, decoded: try XCTUnwrap(Bolt11.decode(bolt11)))
        XCTAssertEqual(try XCTUnwrap(f.payRecipient).subtitle, t("send.kind.invoice"))
    }
}
