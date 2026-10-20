import Foundation
import LaWalletKit
import Observation

/// Display currencies (`currencies-store.ts`): local copy + server sync via `PUT /api/users/me/currency-prefs`.
@Observable @MainActor
final class CurrencyStore {
    private static let key = "lawallet-active-currencies"
    private(set) var active: [String]
    var selected: String { didSet { if oldValue != selected { save() } } }
    private(set) var rates: [String: Double]?
    var persist: ((CurrencyPrefs) -> Void)?

    init() {
        let stored = UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(CurrencyPrefs.self, from: $0) }
        let n = Currencies.normalize(active: stored?.active ?? Currencies.defaultActive, selected: stored?.selected ?? "SAT")
        active = n.active
        selected = n.selected
        rates = UserDefaults.standard.dictionary(forKey: "lawallet-yadio-rates") as? [String: Double]
    }

    func hydrate(_ prefs: CurrencyPrefs) {
        let n = Currencies.normalize(active: prefs.active, selected: prefs.selected)
        active = n.active
        selected = n.selected
        writeLocal()
    }

    func setActive(_ codes: [String]) {
        let n = Currencies.normalize(active: codes, selected: selected)
        active = n.active
        if selected != n.selected { selected = n.selected } else { save() }
    }

    /// Home balance chip tap: cycle through active currencies.
    func cycle() {
        guard let i = active.firstIndex(of: selected) else { return }
        selected = active[(i + 1) % active.count]
    }

    private func save() {
        writeLocal()
        persist?(CurrencyPrefs(active: active, selected: selected))
    }

    private func writeLocal() {
        if let data = try? JSONEncoder().encode(CurrencyPrefs(active: active, selected: selected)) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    func refreshRates() async {
        if let r = await RatesService.shared.refresh() {
            rates = r
            UserDefaults.standard.set(r, forKey: "lawallet-yadio-rates")
        }
    }

    func format(_ sats: Int, _ code: String? = nil) -> String { Currencies.format(sats: sats, code: code ?? selected, rates: rates) }
    func unit(_ code: String? = nil) -> String { (code ?? selected) == "SAT" ? "sats" : (code ?? selected) }
}

/// In-memory send / receive / withdraw state shared across a flow's screens (`wallet-flow-store.ts`).
@Observable @MainActor
final class FlowState {
    // send
    var sendInput = ""
    var destination: Destination?
    var payParams: LNURLPayParams?
    var recipientLabel: String?
    var recipientAvatar: URL?
    var sendAmountSats = 0
    var sendComment = ""
    var sendResult: SendResult?
    // receive
    var receiveAmountSats = 0
    var receiveNote = ""
    var invoice: NWCMadeInvoice?
    var receivedSats: Int?
    // withdraw
    var withdraw: LNURLWithdrawParams?

    struct SendResult: Equatable {
        let amountSats: Int
        let feeSats: Int
        let preimage: String
        let paymentHash: String?
        let recipient: String
        let comment: String?
        let date: Date
    }

    func resetSend() {
        sendInput = ""; destination = nil; payParams = nil; recipientLabel = nil; recipientAvatar = nil
        sendAmountSats = 0; sendComment = ""; sendResult = nil
    }

    func resetReceive() { receiveAmountSats = 0; receiveNote = ""; invoice = nil; receivedSats = nil }

    func reset() { resetSend(); resetReceive(); withdraw = nil }
}

/// Recently paid recipients (`contacts-store.ts`, `lawallet-contacts`).
final class ContactsStore: @unchecked Sendable {
    static let shared = ContactsStore()
    private let key = "lawallet-contacts"
    struct Contact: Codable, Hashable { let address: String; var name: String?; var avatar: String?; var lastUsed: Date }

    private let lock = NSLock()
    private var cached: [Contact]?

    /// Decoded once; read on every keypad tap and preview render.
    var contacts: [Contact] {
        lock.withLock {
            if let cached { return cached }
            let list = (UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([Contact].self, from: $0) } ?? [])
                .sorted { $0.lastUsed > $1.lastUsed }
            cached = list
            return list
        }
    }

    func remember(_ address: String, name: String? = nil, avatar: String? = nil) {
        var list = contacts.filter { $0.address.lowercased() != address.lowercased() }
        list.insert(Contact(address: address, name: name, avatar: avatar, lastUsed: Date()), at: 0)
        list = Array(list.prefix(20))
        lock.withLock { cached = list }
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }

    func clear() {
        lock.withLock { cached = nil }
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Fixed suggestion domains (`lightning-address-suggestions.ts`).
enum AddressSuggestions {
    static let domains = ["lawallet.io", "lacrypta.ar", "walletofsatoshi.com", "blink.sv", "strike.me", "getalby.com", "primal.net",
                          "coinos.io", "zeuspay.com", "minibits.cash", "npub.cash", "rizful.com"]
    static func avatar(_ domain: String) -> URL? {
        URL(string: "https://raw.githubusercontent.com/lawalletio/static/main/public/img/domains/\(domain).png")
    }
}
