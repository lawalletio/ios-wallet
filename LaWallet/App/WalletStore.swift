import Foundation
import LaWalletKit
import Observation

/// Display model for a transaction row / receipt.
struct TxItem: Hashable, Identifiable, Sendable {
    let tx: NWCTransaction
    var id: String { tx.id }
    var incoming: Bool { tx.type == .incoming }
    var title: String { tx.description.isEmpty ? t(incoming ? "shared.tx.received" : "shared.tx.sent") : tx.description }
    var amountSats: Int { tx.amountSats }
    var date: Date { tx.settledAt ?? tx.createdAt }
    var pending: Bool { tx.state == .pending }
}

/// One shared NWC connection for the signed-in user: balance (30 s poll + on notification), activity, live NIP-47 notifications.
@Observable @MainActor
final class WalletStore {
    enum Status: Equatable { case none, connecting, connected, error(String) }

    private(set) var status: Status = .none
    /// Counts each payment once and drops stale `get_balance` reads (see `BalanceTracker`).
    private var tracker = BalanceTracker()
    var balance: Int? { tracker.value }
    private(set) var balanceIsCached = false
    private(set) var transactions: [TxItem] = []
    private(set) var loadingTransactions = false
    private(set) var transactionsError: String?
    private(set) var hasMore = true
    /// Latest live payment, for the home "payment notice" overlay and receive screens.
    private(set) var lastPayment: NWCTransaction?
    private(set) var client: NWCClient?
    private(set) var uri: String?

    var onPayment: ((NWCTransaction) -> Void)?
    private var tasks: [Task<Void, Never>] = []

    var hasWallet: Bool { uri != nil }

    func connect(_ nwc: String?) {
        guard nwc != uri else { return }
        disconnect()
        guard let nwc, let c = try? NWCClient(uri: nwc) else { status = .none; return }
        uri = nwc
        client = c
        Keychain.set(nwc, for: "nwc-uri")
        status = .connecting
        if let cached = UserDefaults.standard.object(forKey: cacheKey("balance")) as? Int {
            tracker = BalanceTracker(value: cached)
            balanceIsCached = true
        }
        if let data = UserDefaults.standard.data(forKey: cacheKey("tx")), let txs = try? JSONDecoder().decode([NWCTransaction].self, from: data) {
            transactions = txs.map(TxItem.init)
        }
        tasks.append(Task { [weak self] in
            await self?.refreshBalance()
            await self?.loadTransactions(reset: true)
        })
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await self?.refreshBalance()
            }
        })
        tasks.append(Task { [weak self] in
            let stream = await c.notifications()
            for await n in stream {
                guard let self else { return }
                self.receive(n.transaction)
            }
        })
    }

    func disconnect() {
        tasks.forEach { $0.cancel() }
        tasks = []
        client = nil
        uri = nil
        status = .none
        tracker = BalanceTracker()
        transactions = []
        hasMore = true
    }

    func clearCaches() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("lawallet-wallet-cache") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        Keychain.set(nil, for: "nwc-uri")
    }

    private func cacheKey(_ kind: String) -> String { "lawallet-wallet-cache-\(kind)-\((uri ?? "").sha256Hex.prefix(12))" }

    func refreshBalance() async {
        guard let client else { return }
        let ticket = tracker.beginRead()
        do {
            let sats = try await client.getBalanceSats()
            guard client === self.client else { return }
            status = .connected
            if tracker.applyRead(sats, ticket: ticket) {
                balanceIsCached = false
                UserDefaults.standard.set(sats, forKey: cacheKey("balance"))
            }
        } catch {
            if balance == nil || status != .connected { status = .error(Self.message(error)) }
        }
    }

    func loadTransactions(reset: Bool) async {
        guard let client, !loadingTransactions else { return }
        loadingTransactions = true
        defer { loadingTransactions = false }
        do {
            let until = reset ? nil : transactions.last.map { $0.tx.createdAt.addingTimeInterval(-1) }
            let page = try await client.listTransactions(limit: 20, until: until)
            guard client === self.client else { return }
            let items = page.map(TxItem.init)
            transactions = reset ? items : transactions + items.filter { i in !transactions.contains { $0.id == i.id } }
            hasMore = page.count == 20
            transactionsError = nil
            if reset, let data = try? JSONEncoder().encode(page) { UserDefaults.standard.set(data, forKey: cacheKey("tx")) }
        } catch {
            transactionsError = Self.message(error)
        }
    }

    /// One path for live notifications and our own optimistic copy. The row is always refreshed (the notification
    /// carries the wallet's fee/preimage), but the balance, notice and sound happen only the first time a payment is seen.
    func receive(_ tx: NWCTransaction) {
        let existing = transactions.firstIndex { $0.tx.paymentHash.lowercased() == tx.paymentHash.lowercased() && $0.tx.type == tx.type }
        if let existing { transactions[existing] = TxItem(tx: tx) } else { transactions.insert(TxItem(tx: tx), at: 0) }
        guard tracker.applyPayment(tx) else { return }
        lastPayment = tx
        onPayment?(tx)
        // Confirm against the wallet: soon, again, and once after the grace window so a fee difference settles.
        Task { [weak self] in
            for delay in [1.0, 4.0, 11.0] {
                try? await Task.sleep(for: .seconds(delay))
                await self?.refreshBalance()
            }
        }
    }

    /// Optimistic local update after our own payment (the wallet may deliver its notification late).
    func recordOutgoing(_ tx: NWCTransaction) { receive(tx) }

    static func message(_ error: Error) -> String {
        if let e = error as? RelayError {
            switch e {
            case .timeout: return t("shared.relay.timeout")
            case .notConnected: return t("shared.relay.unreachable")
            case .rejected(let m): return m.isEmpty ? t("shared.relay.generic") : m
            }
        }
        if case NWCError.timeout = error { return t("shared.relay.timeout") }
        return error.localizedDescription
    }
}
