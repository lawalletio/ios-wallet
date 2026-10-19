import LaWalletKit
import XCTest
@testable import LaWallet

/// Live regression for "the balance goes back and forth": drives the real `WalletStore` against Alby NWC faucet wallets
/// and samples the shown balance every 100 ms around a receive and a send.
/// Opt-in: `TEST_RUNNER_LAWALLET_E2E=1 xcodebuild test … -only-testing:LaWalletTests/WalletStoreLiveTests`
@MainActor
final class WalletStoreLiveTests: XCTestCase {
    override func setUp() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LAWALLET_E2E"] != nil, "live test (set LAWALLET_E2E)")
    }

    private func faucet(_ sats: Int) async throws -> String {
        var req = URLRequest(url: URL(string: "https://faucet.nwc.dev?balance=\(sats)")!)
        req.httpMethod = "POST"
        let (data, _) = try await URLSession.shared.data(for: req)
        return String(decoding: data, as: UTF8.self)
    }

    /// Distinct values the balance showed, in order, while `body` runs and for `settle` seconds after.
    private func samples(_ store: WalletStore, settle: Double, _ body: () async throws -> Void) async throws -> [Int] {
        var seen: [Int] = []
        let sampler = Task { @MainActor in
            while !Task.isCancelled {
                if let b = store.balance, b != seen.last { seen.append(b) }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        try await body()
        try await Task.sleep(for: .seconds(settle))
        sampler.cancel()
        if let b = store.balance, b != seen.last { seen.append(b) }
        return seen
    }

    private func waitForBalance(_ store: WalletStore) async throws {
        for _ in 0..<100 where store.balance == nil || store.balanceIsCached { try await Task.sleep(for: .milliseconds(200)) }
        XCTAssertNotNil(store.balance)
    }

    func testReceiveMovesBalanceOnceAndNoticesOnce() async throws {
        let store = WalletStore()
        var announced = 0
        store.onPayment = { _ in announced += 1 }
        store.connect(try await faucet(100))
        try await waitForBalance(store)
        try await Task.sleep(for: .seconds(3))
        // The faucet funds the wallet just after handing it out, so its notification lands after the first read:
        // it may be announced, but must not be counted twice.
        XCTAssertEqual(store.balance, 100, "funding payment counted twice")
        announced = 0
        let start = try XCTUnwrap(store.balance)
        let payer = try NWCClient(uri: try await faucet(100))
        let invoice = try await XCTUnwrap(store.client).makeInvoice(amountSats: 1, description: "ios regression")

        let seen = try await samples(store, settle: 13) { _ = try await payer.payInvoice(invoice.bolt11) }
        XCTAssertEqual(seen.first, start)
        XCTAssertEqual(seen.last, start + 1)
        XCTAssertEqual(seen, [start, start + 1], "balance must move once, never back: \(seen)")
        XCTAssertEqual(announced, 1, "payment announced \(announced) times")
    }

    func testSendMovesBalanceOnceAndNoticesOnce() async throws {
        let store = WalletStore()
        var notices = 0
        store.onPayment = { _ in notices += 1 }
        store.connect(try await faucet(100))
        try await waitForBalance(store)
        try await Task.sleep(for: .seconds(3))
        // The faucet funds the wallet just after handing it out, so its notification lands after the first read:
        // it may be announced, but must not be counted twice.
        XCTAssertEqual(store.balance, 100, "funding payment counted twice")
        notices = 0
        let start = try XCTUnwrap(store.balance)
        let recipient = try NWCClient(uri: try await faucet(10))
        let invoice = try await recipient.makeInvoice(amountSats: 1, description: "ios regression")

        // Same as SendPreviewScreen: pay, then record the optimistic copy; the wallet's payment_sent arrives after.
        let seen = try await samples(store, settle: 13) {
            let client = try XCTUnwrap(store.client)
            let r = try await client.payInvoice(invoice.bolt11)
            store.recordOutgoing(NWCTransaction(type: .outgoing, amountSats: 1, feesPaidSats: r.feesPaidSats,
                                                paymentHash: invoice.paymentHash, preimage: r.preimage, settledAt: Date(),
                                                createdAt: Date(), walletState: .settled))
        }
        XCTAssertEqual(seen, [start, start - 1], "balance must move once, never back: \(seen)")
        XCTAssertEqual(notices, 1, "payment announced \(notices) times")
        XCTAssertEqual(store.transactions.filter { $0.tx.paymentHash == invoice.paymentHash }.count, 1)
    }
}
