import Foundation
import Testing
@testable import LaWalletKit

@Suite struct BalanceTrackerTests {
    private func tx(_ type: NWCTransaction.Kind, _ sats: Int, hash: String = "ab", fee: Int = 0, at: Date = Date()) -> NWCTransaction {
        NWCTransaction(type: type, amountSats: sats, feesPaidSats: fee, paymentHash: hash, settledAt: at, createdAt: at)
    }

    /// Regression: a notification that lands after a read which already includes the payment must not add it twice.
    @Test func notificationAlreadyInLastReadIsNotAddedAgain() {
        let t0 = Date()
        var b = BalanceTracker(value: 0)
        let read = b.beginRead(now: t0.addingTimeInterval(5))
        _ = b.applyRead(100, ticket: read)                                    // balance already includes the payment…
        let announce = b.applyPayment(tx(.incoming, 100, at: t0), now: t0.addingTimeInterval(6))  // …whose notification arrives late
        #expect(announce && b.value == 100)
        let newer = b.applyPayment(tx(.incoming, 1, hash: "cd", at: t0.addingTimeInterval(20)), now: t0.addingTimeInterval(20))
        #expect(newer && b.value == 101)
    }

    /// Regression: paying 1 sat subtracted twice (optimistic copy + `payment_sent` notification), then bounced back.
    @Test func sameOutgoingPaymentCountsOnce() {
        var b = BalanceTracker(value: 100)
        let first = b.applyPayment(tx(.outgoing, 1, hash: "AB"))
        let again = b.applyPayment(tx(.outgoing, 1, hash: "ab"))
        #expect(first && !again)
        #expect(b.value == 99)
    }

    @Test func readStartedBeforePaymentIsDropped() {
        var b = BalanceTracker(value: 100)
        let inFlight = b.beginRead()  // e.g. the 30 s poll
        _ = b.applyPayment(tx(.incoming, 1))
        let stale = b.applyRead(100, ticket: inFlight)
        #expect(!stale && b.value == 101)
        let fresh = b.applyRead(101, ticket: b.beginRead())
        #expect(fresh)
    }

    @Test func outOfOrderReadsAreDropped() {
        var b = BalanceTracker(value: 0)
        let older = b.beginRead(), newer = b.beginRead()
        let appliedNewer = b.applyRead(50, ticket: newer)
        let appliedOlder = b.applyRead(40, ticket: older)
        #expect(appliedNewer && !appliedOlder)
        #expect(b.value == 50)
    }

    @Test func laggingWalletIsIgnoredOnlyDuringGrace() {
        let t0 = Date()
        var b = BalanceTracker(value: 100, grace: 10)
        _ = b.applyPayment(tx(.incoming, 5), now: t0)
        let lagging = b.applyRead(100, ticket: b.beginRead(), now: t0.addingTimeInterval(1))
        #expect(!lagging && b.value == 105)
        let afterGrace = b.applyRead(104, ticket: b.beginRead(), now: t0.addingTimeInterval(11))
        #expect(afterGrace && b.value == 104)
    }

    @Test func matchingReadClearsExpectation() {
        var b = BalanceTracker(value: 10)
        _ = b.applyPayment(tx(.outgoing, 3, fee: 1))
        #expect(b.value == 6)
        let confirmed = b.applyRead(6, ticket: b.beginRead())
        let laterChange = b.applyRead(20, ticket: b.beginRead())  // accepted immediately once confirmed
        #expect(confirmed && laterChange && b.value == 20)
    }

    @Test func paymentBeforeFirstReadDoesNotInventABalance() {
        var b = BalanceTracker()
        let counted = b.applyPayment(tx(.incoming, 5))
        #expect(counted && b.value == nil)
        let firstRead = b.applyRead(5, ticket: b.beginRead())
        #expect(firstRead && b.value == 5)
    }
}
