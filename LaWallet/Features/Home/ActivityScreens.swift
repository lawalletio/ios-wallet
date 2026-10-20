import LaWalletKit
import SwiftUI

/// `/wallet/activity` — full NWC history grouped by day, infinite scroll.
struct ActivityScreen: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let w = app.wallet
        let items = w.transactions
        let groups = Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.date) }.sorted { $0.key > $1.key }
        VStack(spacing: 0) {
            ScreenHeader(title: t("activity.title"))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if items.isEmpty {
                        Group {
                            if w.loadingTransactions { ProgressView().tint(LW.muted) }
                            else if !w.hasWallet { Text(t("activity.connectWallet")).foregroundStyle(LW.muted) }
                            else if w.transactionsError != nil { Text(t("activity.loadFailed")).foregroundStyle(LW.destructiveText) }
                            else { Text(t("activity.empty")).foregroundStyle(LW.muted) }
                        }
                        .font(LW.font(14)).frame(maxWidth: .infinity).padding(.vertical, 48)
                    }
                    ForEach(groups, id: \.key) { day, txs in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(dayLabel(day)).font(LW.font(15, .semibold)).foregroundStyle(LW.muted).padding(.leading, 6)
                            TransactionList(items: txs, rowID: "activity.row")
                        }
                    }
                    if w.hasMore && !items.isEmpty {
                        ProgressView().tint(LW.muted).frame(maxWidth: .infinity).padding()
                            .onAppear { Task { await w.loadTransactions(reset: false) } }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 32).padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .lwSoftScrollEdges()
            .refreshable { await w.loadTransactions(reset: true) }
        }
        .task { if w.transactions.isEmpty { await w.loadTransactions(reset: true) } }
    }

    private func dayLabel(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return t("activity.today") }
        if Calendar.current.isDateInYesterday(d) { return t("activity.yesterday") }
        return d.formatted(date: .abbreviated, time: .omitted)
    }
}

/// `/wallet/activity/[paymentHash]` — receipt for one transaction.
struct ActivityDetailScreen: View {
    let item: TxItem
    @Environment(AppModel.self) private var app

    var body: some View {
        let tx = item.tx
        VStack(spacing: 0) {
            ScreenHeader(title: t("activity.title"))
            ScrollView {
                PaymentReceipt(
                    status: tx.state == .settled ? .settled : tx.state == .failed ? .failed : .pending,
                    title: t(tx.state == .pending ? "activity.detail.pending" : tx.state == .failed ? "activity.detail.failed"
                        : item.incoming ? "activity.detail.received" : "activity.detail.sent"),
                    subtitle: tx.description.isEmpty ? nil : tx.description,
                    amountSats: tx.amountSats,
                    details: [
                        (t("activity.detail.note"), tx.description.isEmpty ? nil : tx.description),
                        (t("activity.detail.time"), (tx.settledAt ?? tx.createdAt).formatted(date: .abbreviated, time: .shortened)),
                        (t("activity.detail.networkFee"), item.incoming ? nil : "\(tx.feesPaidSats) sats")
                    ],
                    proofs: [(t("activity.detail.paymentHash"), tx.paymentHash), (t("activity.detail.preimage"), tx.preimage)]
                )
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .lwSoftScrollEdges()
        }
    }
}
