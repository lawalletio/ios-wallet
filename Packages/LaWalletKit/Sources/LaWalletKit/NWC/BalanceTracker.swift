import Foundation

/// Reconciles optimistic payment updates with `get_balance` reads so the shown balance moves once per payment and never
/// steps back:
/// - a payment is counted once, even when it arrives twice (our own optimistic copy + the wallet's NIP-47 notification);
/// - a read that started before a local payment, or is older than one already applied, is dropped;
/// - for `grace` after a payment, a read that disagrees with the optimistic value is treated as the wallet lagging;
/// - a payment that settled before the last applied read started is already in that read, so it is not added again.
public struct BalanceTracker: Sendable {
    public struct Ticket: Sendable { let seq: Int; let mutation: Int; let startedAt: Date }

    public private(set) var value: Int?
    private var counted = Set<String>()  // ponytail: grows per session; prune if sessions run for days
    private var mutation = 0
    private var readSeq = 0
    private var lastApplied = 0
    private var lastAppliedStart: Date?
    private var expected: (value: Int, until: Date)?
    let grace: TimeInterval

    public init(value: Int? = nil, grace: TimeInterval = 10) {
        self.value = value
        self.grace = grace
    }

    /// Counts a payment. Returns false when it was already counted (caller should not re-announce it).
    public mutating func applyPayment(_ tx: NWCTransaction, now: Date = Date()) -> Bool {
        guard counted.insert(tx.type.rawValue + ":" + tx.paymentHash.lowercased()).inserted else { return false }
        // 1 s of slack for wallet-vs-device clock skew; erring this way only delays the update to the next read.
        if let readStart = lastAppliedStart, (tx.settledAt ?? tx.createdAt) <= readStart.addingTimeInterval(1) { return true }
        mutation += 1
        if let v = value {
            let next = tx.type == .incoming ? v + tx.amountSats : max(0, v - tx.amountSats - tx.feesPaidSats)
            value = next
            expected = (next, now.addingTimeInterval(grace))
        }
        return true
    }

    /// Call right before sending `get_balance`; hand the ticket back to `applyRead`.
    public mutating func beginRead(now: Date = Date()) -> Ticket {
        readSeq += 1
        return Ticket(seq: readSeq, mutation: mutation, startedAt: now)
    }

    /// Applies a read unless it is stale. Returns whether `value` was updated from it.
    @discardableResult
    public mutating func applyRead(_ sats: Int, ticket: Ticket, now: Date = Date()) -> Bool {
        guard ticket.seq > lastApplied, ticket.mutation == mutation else { return false }
        if let e = expected {
            if sats != e.value, now < e.until { return false }
            expected = nil
        }
        lastApplied = ticket.seq
        lastAppliedStart = ticket.startedAt
        value = sats
        return true
    }
}
