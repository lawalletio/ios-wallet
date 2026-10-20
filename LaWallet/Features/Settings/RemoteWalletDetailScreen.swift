import LaWalletKit
import SwiftUI

/// `/wallet/settings/remote-wallets/[id]` — header, receive protocols, forwarding, notifications, and the wallet's own NWC history.
struct RemoteWalletDetailScreen: View {
    let walletId: String
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var wallet: RemoteWallet?
    @State private var failed = false
    @State private var txs: [TxItem]?
    @State private var txError = false
    @State private var token = UUID()
    @State private var confirmDelete = false
    @State private var deleting = false

    var body: some View {
        SettingsPage(title: t("remoteWallets.detail.title"), refresh: { token = UUID(); await load() }) {
            if let wallet {
                VStack(alignment: .leading, spacing: 16) {
                    header(wallet)
                    RowDivider().padding(.leading, -18)
                    protocols(wallet)
                }
                .padding(18)
                .lwSurface()
                ForwardingPanel(walletId: wallet.id, token: token)
                NotificationsPanel(walletId: wallet.id, token: token)
                transactions(wallet)
                Button { confirmDelete = true } label: { Label { Text(t("ios.set.wallets.delete")) } icon: { Icon("trash-2", size: 16) } }
                    .buttonStyle(.lw(.destructive))
                    .disabled(deleting)
                    .accessibilityIdentifier("wallet.delete")
            } else if failed {
                Text(t("remoteWallets.detail.notFound")).font(LW.font(14)).foregroundStyle(LW.destructiveText)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    .lwGlass(in: RoundedRectangle(cornerRadius: LW.Radius.surface - 4, style: .continuous), tint: .color(LW.coral.opacity(0.12)))
            } else {
                ProgressView().tint(LW.muted).frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .task { await load() }
        .alert(t("ios.set.wallets.deleteTitle", ["name": wallet?.name ?? ""]), isPresented: $confirmDelete) {
            Button(t("common.cancel"), role: .cancel) {}
            Button(t("ios.set.wallets.delete"), role: .destructive) { Task { await delete() } }
        } message: { Text(t("ios.set.wallets.deleteBody")) }
    }

    private func load() async {
        do {
            let w = try await app.api.remoteWallet(walletId)
            wallet = w
            failed = false
            guard w.isActive else { txs = nil; return }
            do {
                let client = try NWCClient(uri: try await app.api.connectionString(w.id))
                txs = try await client.listTransactions(limit: 100).map { TxItem(tx: $0) }
                txError = false
            } catch { txError = true }
        } catch {
            if wallet == nil { failed = true }
        }
    }

    private func delete() async {
        guard let wallet else { return }
        deleting = true
        defer { deleting = false }
        do {
            try await app.api.deleteRemoteWallet(wallet.id)
            await app.refreshMe()
            app.show(.success, t("ios.set.wallets.deleted", ["name": wallet.name]))
            dismiss()
        } catch { app.show(.error, error.localizedDescription) }
    }

    // MARK: sections

    private func header(_ w: RemoteWallet) -> some View {
        HStack(spacing: 14) {
            SettingsIconTile(icon: "wallet", color: w.isDefault ? theme.preset.primary : LW.sun, size: 48)
            VStack(alignment: .leading, spacing: 6) {
                Text(w.name).font(LW.font(22, .bold)).tracking(-0.3).foregroundStyle(LW.foreground).lineLimit(1)
                HStack(spacing: 6) {
                    SettingsBadge(w.type, .outline)
                    SettingsBadge(w.status, w.isActive ? .success : ["BLOCKED", "DEAD"].contains(w.status.uppercased()) ? .destructive : .outline)
                    if w.isDefault { SettingsBadge(t("remoteWallets.list.primary"), .primary) }
                    if w.isLncurl { SettingsBadge("LNCurl", .info) }
                }
                Text(t("ios.set.wallets.created", ["date": SettingsFormat.dateTime(w.createdAt)])).font(LW.font(13)).foregroundStyle(LW.muted)
            }
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("wallet.header")
    }

    /// remote-wallet-receive-protocols.tsx — the dialog copy is inlined as captions.
    private func protocols(_ w: RemoteWallet) -> some View {
        let p = "remoteWallets.protocols"
        let caps = w.receiveCapabilities
        let zap = w.isActive && caps?.nip57 == true
        let zapDetail: String? = zap ? caps?.receiptPubkey.map { t("\(p).receiptsSignedBy", ["npub": NIP19.npub($0)]) }
            : (caps?.reason ?? t("\(p).zapRequirements"))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                chip("LUD-21", on: w.isActive)
                chip("NIP-57", on: zap)
            }
            if !w.isActive { caption("LUD-21", t("\(p).lud21Inactive")) }
            if let zapDetail { caption("NIP-57", zapDetail) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(t("\(p).label"))
    }

    private func chip(_ label: String, on: Bool) -> some View {
        HStack(spacing: 6) {
            Icon(on ? "check" : "minus", size: 10).frame(width: 18, height: 18)
                .background((on ? LW.incoming : LW.muted).opacity(0.2), in: Circle())
            Text(label).font(LW.font(12, .semibold))
        }
        .padding(.leading, 4).padding(.trailing, 10).padding(.vertical, 4)
        .foregroundStyle(on ? LW.incoming : LW.muted)
        .background((on ? LW.incoming : LW.muted).opacity(0.16), in: Capsule())
    }

    private func caption(_ label: String, _ text: String) -> some View {
        (Text(label + " · ").font(LW.font(13, .semibold)) + Text(text).font(LW.font(13))).foregroundStyle(LW.muted)
    }

    private func transactions(_ w: RemoteWallet) -> some View {
        let f = "remoteWallets.forwarding"
        return SettingsSection(t("home.tabActivity")) {
            Group {
                if !w.isActive {
                    emptyText(t("\(f).paymentsInactive"))
                } else if txError {
                    emptyText(t("\(f).paymentsError"), error: true)
                } else if let txs, txs.isEmpty {
                    emptyText(t("\(f).paymentsEmpty"))
                } else if let txs {
                    TransactionList(items: txs)
                } else {
                    ProgressView().tint(LW.muted).frame(maxWidth: .infinity, minHeight: 96).lwSurface()
                }
            }
            .accessibilityIdentifier("wallet.transactions")
        }
    }

    private func emptyText(_ text: String, error: Bool = false) -> some View {
        Text(text).font(LW.font(14)).foregroundStyle(error ? LW.destructiveText : LW.muted).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.vertical, 34)
            .lwSurface()
    }
}

/// Panel chrome shared by forwarding and notifications: one glass surface, hairline-divided sections inside.
private struct Panel<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .lwSurface()
    }
}

/// Full-width hairline between panel sections.
private struct PanelDivider: View {
    var body: some View { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5) }
}

@MainActor private func panelHeader(icon: String, tint: Color, title: String, badge: SettingsBadge?, subtitle: String) -> some View {
    HStack(alignment: .top, spacing: 14) {
        SettingsIconTile(icon: icon, color: tint, size: 44)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title).font(LW.font(17, .semibold)).foregroundStyle(LW.foreground)
                if let badge { badge }
            }
            Text(subtitle).font(LW.font(14)).foregroundStyle(LW.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: forwarding (remote-wallet-forwarding-panel.tsx)

private struct ForwardingPanel: View {
    let walletId: String
    let token: UUID
    @Environment(AppModel.self) private var app
    @State private var action: ReceiveAction?
    @State private var failed = false
    @State private var receipts: [ForwardingReceipt]?
    @State private var tab = 0
    @State private var busy = false
    @State private var forcing = false
    @State private var configOpen = false
    private let f = "remoteWallets.forwarding"

    var body: some View {
        Group {
            if let action { panel(action) } else if failed {
                Text(t("\(f).unavailable")).font(LW.font(14)).foregroundStyle(LW.destructiveText)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    .lwGlass(in: RoundedRectangle(cornerRadius: LW.Radius.surface, style: .continuous), tint: .color(LW.coral.opacity(0.12)))
            } else {
                ProgressView().tint(LW.muted).frame(maxWidth: .infinity, minHeight: 120).lwSurface()
            }
        }
        .task(id: token) { await load() }
        .sheet(isPresented: $configOpen) {
            if let action {
                ForwardingConfigSheet(action: action) { feeBps, baseFee, destinations in
                    let next = try await app.api.saveReceiveAction(walletId, feeBps: feeBps, baseFeeSats: baseFee, enabled: true, destinations: destinations)
                    self.action = next
                    await loadReceipts()
                }
            }
        }
    }

    private func panel(_ a: ReceiveAction) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 16) {
                panelHeader(icon: "git-branch", tint: LW.sun, title: t("\(f).title"), badge: stateBadge(a), subtitle: t("\(f).subtitle"))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { buttons(a) }
                    VStack(alignment: .leading, spacing: 8) { buttons(a) }
                }
            }
            .padding(20)

            if !a.eligible, let reason = a.reason {
                HStack(alignment: .top, spacing: 12) {
                    Icon("alert-triangle", size: 16)
                    Text(reason).font(LW.font(14))
                }
                .foregroundStyle(LW.sun).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(LW.sun.opacity(0.10), in: RoundedRectangle(cornerRadius: LW.Radius.inset, style: .continuous))
                .padding(.horizontal, 20).padding(.bottom, 16)
            }

            PanelDivider()
            GlassSegmented(items: [(0, t("\(f).tabOverview")), (1, t("\(f).tabActivity"))], selection: $tab, idPrefix: "forwarding.tab")
                .padding(.horizontal, 20).padding(.top, 16)

            Group {
                if tab == 0 { overview(a) } else { receiptList }
            }
            .padding(20)
        }
        .accessibilityIdentifier("wallet.forwarding")
    }

    @ViewBuilder private func buttons(_ a: ReceiveAction) -> some View {
        if a.configured && a.pendingReceipts > 0 {
            let running = forcing || a.attemptInProgress
            Button { Task { await force(a) } } label: {
                HStack(spacing: 6) {
                    if running { ProgressView().controlSize(.mini) } else { Icon("chevrons-right", size: 14) }
                    Text(t(running ? "\(f).forwardingBusy" : "\(f).forceForward"))
                }
            }
            .buttonStyle(.lw(.secondary, height: 36, fullWidth: false))
            .disabled(!a.enabled || running)
            .accessibilityHint(t(!a.enabled ? "\(f).resumeFirst" : running ? "\(f).attemptRunning" : "\(f).forwardNow"))
            .accessibilityIdentifier("forwarding.force")
        }
        if a.configured {
            Button(t(a.enabled ? "remoteWallets.pause" : "remoteWallets.resume")) { Task { await toggle(a) } }
                .buttonStyle(.lw(.outline, height: 36, fullWidth: false))
                .disabled(busy)
                .accessibilityIdentifier("forwarding.toggle")
        }
        Button { configOpen = true } label: {
            HStack(spacing: 6) { Icon("settings", size: 14); Text(t(a.configured ? "\(f).editPlan" : "\(f).configure")) }
        }
        .buttonStyle(.lw(.theme, height: 36, fullWidth: false))
        .disabled(!a.eligible)
        .accessibilityIdentifier("forwarding.configure")
    }

    private func stateBadge(_ a: ReceiveAction) -> SettingsBadge {
        if !a.configured { return SettingsBadge(t("\(f).notConfigured"), .outline) }
        return a.enabled ? SettingsBadge(t("remoteWallets.live"), .success) : SettingsBadge(t("remoteWallets.paused"))
    }

    @ViewBuilder private func overview(_ a: ReceiveAction) -> some View {
        if let r = a.revision {
            VStack(alignment: .leading, spacing: 20) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    metric(t("\(f).pendingBalance"), SettingsFormat.msats(a.pendingAmountMsats), accent: true)
                    metric(t("\(f).openReceipts"), "\(a.pendingReceipts)")
                    metric(t("\(f).entryFee"), "\(SettingsFormat.percent(bps: r.feeBps)) + \(Int(r.baseFeeSats)) sat")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(t("\(f).destinations")).font(LW.font(14, .semibold)).foregroundStyle(LW.muted).padding(.leading, 4)
                    VStack(spacing: 0) {
                        ForEach(Array(r.destinations.enumerated()), id: \.element.address) { i, d in
                            if i > 0 { RowDivider().padding(.leading, -4) }
                            HStack {
                                Text(d.address).font(.system(size: 13, design: .monospaced)).foregroundStyle(LW.foreground.opacity(0.9))
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer()
                                SettingsBadge(SettingsFormat.percent(bps: d.allocationBps))
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                        }
                    }
                    .lwInset()
                }
            }
        } else {
            VStack(spacing: 8) {
                Icon("git-branch", size: 28).foregroundStyle(LW.muted)
                    .frame(width: 52, height: 52).background(Color.white.opacity(0.08), in: Circle())
                Text(t("\(f).noPlan")).font(LW.font(16, .semibold)).foregroundStyle(LW.foreground)
                Text(t("\(f).noPlanBody")).font(LW.font(14)).foregroundStyle(LW.muted).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 24)
        }
    }

    private func metric(_ label: String, _ value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(LW.font(13)).foregroundStyle(LW.muted)
            Text(value).font(LW.font(17, .semibold)).monospacedDigit().foregroundStyle(accent ? LW.sun : LW.foreground)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .lwInset()
    }

    @ViewBuilder private var receiptList: some View {
        if let receipts, receipts.isEmpty {
            Text(t("\(f).activityEmpty")).font(LW.font(14)).foregroundStyle(LW.muted).frame(maxWidth: .infinity).padding(.vertical, 24)
        } else if let receipts {
            VStack(spacing: 10) { ForEach(receipts) { receiptRow($0) } }
        } else {
            ProgressView().tint(LW.muted).frame(maxWidth: .infinity, minHeight: 80)
        }
    }

    private func receiptRow(_ r: ForwardingReceipt) -> some View {
        let retryable = r.legs.contains { ["READY", "REJECTED", "EXPIRED"].contains($0.status.uppercased()) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SettingsFormat.msats(r.grossAmountMsats)).font(LW.font(16, .semibold)).monospacedDigit().foregroundStyle(LW.foreground)
                    Text(SettingsFormat.dateTime(r.sourceSettledAt)).font(LW.font(13)).foregroundStyle(LW.muted)
                }
                Spacer()
                SettingsBadge(SettingsFormat.status(r.status), SettingsFormat.tone(r.status))
            }
            HStack(spacing: 12) {
                Text(t("\(f).forwarded") + " " + SettingsFormat.msats(r.forwardedAmountMsats))
                Text(t("\(f).feeRetained") + " " + SettingsFormat.msats(r.retainedFeeMsats))
            }
            .font(LW.font(13)).foregroundStyle(LW.muted)
            ForEach(r.legs) { leg in
                HStack(spacing: 8) {
                    Text(leg.destination).font(.system(size: 12, design: .monospaced)).foregroundStyle(LW.foreground.opacity(0.85))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    SettingsBadge(SettingsFormat.status(leg.status), SettingsFormat.tone(leg.status))
                }
                if let err = leg.lastError { Text(err).font(LW.font(12)).foregroundStyle(LW.destructiveText) }
            }
            if let err = r.lastError { Text(err).font(LW.font(12)).foregroundStyle(LW.destructiveText) }
            if retryable {
                Button { Task { await retry(r) } } label: {
                    HStack(spacing: 6) { Icon("rotate-ccw", size: 14); Text(t("\(f).retryFailedLegs")) }
                }
                .buttonStyle(.lw(.outline, height: 34, fullWidth: false))
                .disabled(busy)
                .accessibilityIdentifier("forwarding.retry.\(r.id)")
            }
        }
        .padding(14)
        .lwInset(14)
    }

    // MARK: actions

    private func load() async {
        do {
            action = try await app.api.receiveAction(walletId)
            failed = false
        } catch {
            if action == nil { failed = true }
        }
        await loadReceipts()
    }

    private func loadReceipts() async {
        if let page = try? await app.api.forwardingReceipts(walletId) { receipts = page.receipts } else if receipts == nil { receipts = [] }
    }

    private func toggle(_ a: ReceiveAction) async {
        busy = true
        defer { busy = false }
        do {
            action = try await app.api.setForwarding(walletId, enabled: !a.enabled)
            app.show(.success, t(a.enabled ? "\(f).pausedToast" : "\(f).resumedToast"))
            await loadReceipts()
        } catch { app.show(.error, error.localizedDescription.nonBlank ?? t("\(f).updateFailed")) }
    }

    private func force(_ a: ReceiveAction) async {
        forcing = true
        tab = 1
        defer { forcing = false }
        do {
            try await app.api.forceForwarding(walletId)
            app.show(.success, t("\(f).startedToast", ["n": "\(a.pendingReceipts)"]))
            await load()
        } catch { app.show(.error, error.localizedDescription.nonBlank ?? t("\(f).startFailed")) }
    }

    private func retry(_ r: ForwardingReceipt) async {
        busy = true
        defer { busy = false }
        do {
            try await app.api.retryReceipt(walletId, receiptId: r.id)
            app.show(.success, t("\(f).retryQueued"))
            await loadReceipts()
        } catch { app.show(.error, error.localizedDescription.nonBlank ?? t("\(f).retryFailed")) }
    }
}

/// `ForwardingConfigDialog`: fee, base fee and a destination split that must total 100 %.
private struct ForwardingConfigSheet: View {
    struct Row: Identifiable { let id = UUID(); var address: String; var percent: String }

    let action: ReceiveAction
    let onSave: (Int, Int, [ForwardingDestination]) async throws -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var fee: String
    @State private var baseFee: String
    @State private var rows: [Row]
    @State private var saving = false
    @State private var error: String?
    private let f = "remoteWallets.forwarding"

    init(action: ReceiveAction, onSave: @escaping (Int, Int, [ForwardingDestination]) async throws -> Void) {
        self.action = action
        self.onSave = onSave
        let r = action.revision
        _fee = State(initialValue: String(format: "%.2f", Double(r?.feeBps ?? 50) / 100))
        _baseFee = State(initialValue: String(Int(r?.baseFeeSats ?? 1)))
        _rows = State(initialValue: r?.destinations.map { Row(address: $0.address, percent: Self.trim(Double($0.allocationBps) / 100)) }
            ?? [Row(address: "", percent: "100")])
    }

    private static func trim(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "en_US"))) }

    private var total: Double { rows.reduce(0) { $0 + (SettingsFormat.number($1.percent) ?? 0) } }
    private var valid: Bool {
        let addresses = rows.map { $0.address.trimmedValue.lowercased() }
        return abs(total - 100) < 0.001 && Set(addresses).count == addresses.count
            && rows.allSatisfy { !$0.address.trimmedValue.isEmpty && (SettingsFormat.number($0.percent) ?? 0) > 0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SheetTitle(title: t("\(f).configTitle"), message: t("\(f).configBody"))
                    HStack(spacing: 12) {
                        field(t("\(f).percentageFee"), $fee, suffix: "%", keyboard: .decimalPad)
                        field(t("\(f).baseFee"), $baseFee, suffix: "sats", keyboard: .numberPad)
                    }
                    HStack {
                        Text(t("\(f).destinations")).font(LW.font(14, .semibold)).foregroundStyle(LW.muted).padding(.leading, 6)
                        Spacer()
                        SettingsBadge(String(format: "%.2f%%", total), valid ? .secondary : .destructive)
                    }
                    ForEach($rows) { $row in
                        let n = (rows.firstIndex { $0.id == row.id } ?? 0) + 1
                        HStack(spacing: 8) {
                            LWTextField(placeholder: "name@example.com", text: $row.address).keyboardType(.emailAddress)
                                .accessibilityLabel(t("\(f).destinationN", ["n": "\(n)"]))
                                .accessibilityIdentifier("forwarding.destination.\(n)")
                            LWTextField(placeholder: "%", text: $row.percent).keyboardType(.decimalPad).frame(width: 84)
                                .accessibilityLabel(t("\(f).allocationN", ["n": "\(n)"]))
                            GlassIconButton(icon: "trash-2", size: 44, label: t("\(f).removeDestination")) { rows.removeAll { $0.id == row.id } }
                                .disabled(rows.count == 1)
                                .opacity(rows.count == 1 ? 0.4 : 1)
                        }
                    }
                    Button { rows.append(Row(address: "", percent: "0")) } label: {
                        HStack(spacing: 6) { Icon("plus", size: 14); Text(t("\(f).addDestination")) }
                    }
                    .buttonStyle(.lw(.secondary, height: 40, fullWidth: false))
                    ErrorText(message: error).frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .lwSoftScrollEdges()
            BottomBar {
                HStack(spacing: 12) {
                    Button(t("common.cancel")) { dismiss() }.buttonStyle(.lw(.secondary))
                    Button { Task { await save() } } label: {
                        BusyLabel(t(action.enabled ? "\(f).saveChanges" : "\(f).saveAndEnable"), busy: saving)
                    }
                    .buttonStyle(.lw(.theme))
                    .disabled(!valid || saving)
                    .accessibilityIdentifier("forwarding.save")
                }
            }
        }
    }

    private func field(_ label: String, _ text: Binding<String>, suffix: String, keyboard: UIKeyboardType) -> some View {
        SheetField(label: label) {
            LWTextField(placeholder: "0", text: text).keyboardType(keyboard)
                .overlay(alignment: .trailing) { Text(suffix).font(LW.font(13)).foregroundStyle(LW.muted).padding(.trailing, 16) }
        }
    }

    private func save() async {
        guard valid else { return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            try await onSave(Int(((SettingsFormat.number(fee) ?? 0) * 100).rounded()), Int(SettingsFormat.number(baseFee) ?? 0),
                             rows.map { ForwardingDestination(address: $0.address.trimmedValue, allocationBps: Int(((SettingsFormat.number($0.percent) ?? 0) * 100).rounded())) })
            dismiss()
            app.show(.success, t("\(f).planSaved"))
        } catch {
            self.error = error.localizedDescription.nonBlank ?? t("\(f).saveFailed")
        }
    }
}

// MARK: notifications (remote-wallet-notifications-panel.tsx)

private struct NotificationsPanel: View {
    let walletId: String
    let token: UUID
    @Environment(AppModel.self) private var app
    @State private var items: [WalletNotification]?
    @State private var failed = false
    @State private var busy = false
    @State private var createOpen = false
    private let n = "remoteWallets.notifications"
    private static let sky = Color(hex: "0ea5e9")
    private static let violet = Color(hex: "a78bfa")

    /// Delivery journal: every rule's recent deliveries, newest first.
    private var deliveries: [(WalletNotification.Delivery, WalletNotification)] {
        (items ?? []).flatMap { rule in rule.deliveries.map { ($0, rule) } }.sorted { $0.0.createdAt > $1.0.createdAt }
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 16) {
                panelHeader(icon: "bell", tint: Self.sky, title: t("\(n).title"),
                            badge: SettingsBadge(t("\(n).channels", ["n": "\(items?.count ?? 0)"]), .outline), subtitle: t("\(n).subtitle"))
                Button { createOpen = true } label: { HStack(spacing: 6) { Icon("plus", size: 14); Text(t("\(n).add")) } }
                    .buttonStyle(.lw(.theme, height: 36, fullWidth: false))
                    .accessibilityIdentifier("notifications.add")
            }
            .padding(20)
            PanelDivider()

            Group {
                if let items, items.isEmpty {
                    VStack(spacing: 8) {
                        Icon("bell", size: 26).foregroundStyle(LW.muted)
                            .frame(width: 52, height: 52).background(Color.white.opacity(0.08), in: Circle())
                        Text(t("\(n).emptyTitle")).font(LW.font(16, .semibold)).foregroundStyle(LW.foreground)
                        Text(t("\(n).emptyBody")).font(LW.font(14)).foregroundStyle(LW.muted).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
                } else if let items {
                    VStack(spacing: 10) { ForEach(items) { card($0) } }
                } else if failed {
                    Text(t("\(n).unavailable")).font(LW.font(14)).foregroundStyle(LW.destructiveText)
                } else {
                    ProgressView().tint(LW.muted).frame(maxWidth: .infinity, minHeight: 80)
                }
            }
            .padding(20)

            PanelDivider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("\(n).journal")).font(LW.font(15, .semibold)).foregroundStyle(LW.foreground)
                    Text(t("\(n).journalBody")).font(LW.font(13)).foregroundStyle(LW.muted)
                }
                Spacer()
                HStack(spacing: 6) { Icon("radio", size: 14).foregroundStyle(LW.incoming); Text(t("remoteWallets.live")) }
                    .font(LW.font(12, .semibold)).foregroundStyle(LW.incoming)
                    .padding(.horizontal, 9).padding(.vertical, 4).background(LW.incoming.opacity(0.16), in: Capsule())
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            if deliveries.isEmpty {
                Text(t("\(n).journalEmpty")).font(LW.font(14)).foregroundStyle(LW.muted).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.bottom, 28).padding(.top, 8)
            } else {
                ForEach(Array(deliveries.enumerated()), id: \.element.0.id) { i, pair in
                    if i > 0 { RowDivider().padding(.leading, 50) }
                    deliveryRow(pair.0, pair.1)
                }
            }
        }
        .accessibilityIdentifier("wallet.notifications")
        .task(id: token) { await load() }
        .sheet(isPresented: $createOpen) {
            CreateNotificationSheet(walletId: walletId) { items = $0 }
        }
    }

    private func card(_ rule: WalletNotification) -> some View {
        let webhook = rule.channel == "WEBHOOK"
        let tint = webhook ? Self.sky : Self.violet
        let latest = rule.deliveries.first
        let triggerKey = "\(n).trigger.\(rule.action)"
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                SettingsIconTile(icon: webhook ? "webhook" : "send", color: tint, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(rule.name).font(LW.font(15, .semibold)).foregroundStyle(LW.foreground).lineLimit(1)
                        SettingsBadge(t(rule.enabled ? "remoteWallets.live" : "remoteWallets.paused"), rule.enabled ? .success : .secondary)
                    }
                    Text(webhook ? rule.webhookUrl ?? "" : t("\(n).kind", ["n": rule.nostrKind.map(String.init) ?? ""]))
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(LW.muted).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Button(t(rule.enabled ? "remoteWallets.pause" : "remoteWallets.resume")) { Task { await toggle(rule) } }
                    .buttonStyle(.lw(.outline, height: 34, fullWidth: false))
                    .disabled(busy)
                    .accessibilityIdentifier("notifications.toggle.\(rule.id)")
            }
            RowDivider().padding(.leading, -18)
            HStack(spacing: 6) {
                SettingsBadge(L10n.shared.has(triggerKey) ? t(triggerKey) : "On \(rule.action.lowercased())", .outline)
                if rule.nip44 { SettingsBadge("NIP-44", .outline, icon: "lock") }
                Spacer()
                Text(latest.map { t("\(n).last", ["status": $0.status.lowercased()]) } ?? t("\(n).waitingFirst"))
                    .font(LW.font(12)).foregroundStyle(LW.muted)
            }
        }
        .padding(14)
        .lwInset(16)
        .opacity(rule.enabled ? 1 : 0.7)
    }

    private func deliveryRow(_ d: WalletNotification.Delivery, _ rule: WalletNotification) -> some View {
        let s = d.status.uppercased()
        let retryable = s == "REJECTED" || s == "EXPIRED" || (s == "UNKNOWN" && rule.channel == "NOSTR")
        let tint: Color = s == "SUCCEEDED" ? LW.incoming : s == "UNKNOWN" ? LW.sun : (s == "REJECTED" || s == "EXPIRED") ? LW.coral : LW.muted
        return HStack(alignment: .top, spacing: 12) {
            Icon(s == "SUCCEEDED" ? "check-circle-2" : "clock", size: 16).foregroundStyle(tint).frame(width: 36, height: 36)
                .background(tint.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(rule.name).font(LW.font(14, .medium)).foregroundStyle(LW.foreground).lineLimit(1)
                    SettingsBadge(SettingsFormat.status(d.status), SettingsFormat.tone(d.status))
                    SettingsBadge(d.action, .outline)
                }
                Text([SettingsFormat.dateTime(d.createdAt), t("\(n).attemptCount", ["n": "\(d.attemptCount)"]), d.lastError].compactMap { $0 }.joined(separator: " · "))
                    .font(LW.font(12)).foregroundStyle(LW.muted).lineLimit(2)
                if retryable {
                    Button { Task { await retry(d) } } label: { HStack(spacing: 6) { Icon("rotate-ccw", size: 14); Text(t("common.retry")) } }
                        .buttonStyle(.lw(.outline, height: 34, fullWidth: false))
                        .disabled(busy)
                        .accessibilityIdentifier("notifications.retry.\(d.id)")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private func load() async {
        do {
            items = try await app.api.notifications(walletId)
            failed = false
        } catch {
            if items == nil { failed = true }
        }
    }

    private func toggle(_ rule: WalletNotification) async {
        busy = true
        defer { busy = false }
        do {
            items = try await app.api.setNotification(walletId, notificationId: rule.id, enabled: !rule.enabled)
            app.show(.success, t(rule.enabled ? "\(n).pausedToast" : "\(n).resumedToast"))
        } catch { app.show(.error, error.localizedDescription) }
    }

    private func retry(_ d: WalletNotification.Delivery) async {
        busy = true
        defer { busy = false }
        do {
            try await app.api.retryDelivery(walletId, deliveryId: d.id)
            app.show(.success, t("\(n).retryQueued"))
            await load()
        } catch { app.show(.error, error.localizedDescription) }
    }
}

private struct CreateNotificationSheet: View {
    let walletId: String
    let onCreated: ([WalletNotification]) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var webhook = true
    @State private var name = ""
    @State private var action = "RECEIVED"
    @State private var url = ""
    @State private var kind = "1"
    @State private var pTag = ""
    @State private var relays = "wss://relay.damus.io\nwss://nos.lol"
    @State private var nip44 = false
    @State private var saving = false
    @State private var error: String?
    private let n = "remoteWallets.notifications"

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SheetTitle(title: t("\(n).addTitle"), message: t("\(n).addBody"))
                    GlassSegmented(items: [(true, "Webhook"), (false, "Nostr")], selection: $webhook, idPrefix: "notifications.channel", compact: false)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(t("\(n).channelLabel"))
                    field(t("\(n).name")) {
                        LWTextField(placeholder: t("\(n).namePlaceholder"), text: $name).accessibilityIdentifier("notifications.name")
                    }
                    field(t("\(n).action")) {
                        GlassSegmented(items: [("RECEIVED", t("\(n).actionReceived")), ("FORWARDED", t("\(n).actionForwarded"))],
                                       selection: $action, idPrefix: "notifications.action")
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel(t("\(n).action"))
                    }
                    if webhook {
                        field(t("\(n).endpoint")) {
                            LWTextField(placeholder: "https://example.com/hooks/wallet", text: $url).keyboardType(.URL)
                                .accessibilityIdentifier("notifications.url")
                            Text("\(t("\(n).webhookHint.before")) `Idempotency-Key` \(t("\(n).webhookHint.and")) `X-LaWallet-Event`\(t("\(n).webhookHint.after"))")
                                .font(LW.font(13)).foregroundStyle(LW.muted).padding(.horizontal, 6)
                        }
                    } else {
                        HStack(alignment: .top, spacing: 12) {
                            field(t("\(n).eventKind")) { LWTextField(placeholder: "1", text: $kind).keyboardType(.numberPad) }.frame(width: 110)
                            field(t("\(n).pTag")) { LWTextField(placeholder: "npub1…", text: $pTag) }
                        }
                        field(t("\(n).relays")) {
                            TextEditor(text: $relays).font(.system(size: 14, design: .monospaced)).foregroundStyle(LW.foreground)
                                .scrollContentBackground(.hidden)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .frame(minHeight: 96).padding(.horizontal, 12).padding(.vertical, 8)
                                .lwGlass(in: RoundedRectangle(cornerRadius: LW.Radius.control, style: .continuous))
                        }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("\(n).encrypt")).font(LW.font(15, .medium)).foregroundStyle(LW.foreground)
                                Text(t("\(n).encryptHint")).font(LW.font(13)).foregroundStyle(LW.muted)
                            }
                            Spacer()
                            Toggle("", isOn: $nip44).labelsHidden().tint(theme.preset.primary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .lwSurface(LW.Radius.control)
                    }
                    ErrorText(message: error).frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .lwSoftScrollEdges()
            BottomBar {
                HStack(spacing: 12) {
                    Button(t("common.cancel")) { dismiss() }.buttonStyle(.lw(.secondary))
                    Button { Task { await create() } } label: {
                        BusyLabel(t("\(n).create"), busy: saving)
                    }
                    .buttonStyle(.lw(.theme))
                    .disabled(saving)
                    .accessibilityIdentifier("notifications.create")
                }
            }
        }
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: @escaping () -> C) -> some View {
        SheetField(label: label, content: content)
    }

    private func create() async {
        guard let trimmedName = name.nonBlank else { error = t("\(n).nameRequired"); return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            let list = webhook
                ? try await app.api.createWebhookNotification(walletId, name: trimmedName, action: action, url: url.trimmedValue)
                : try await app.api.createNostrNotification(walletId, name: trimmedName, action: action, kind: Int(kind) ?? 1, pTag: pTag.trimmedValue,
                                                            relays: relays.split(whereSeparator: \.isWhitespace).map(String.init), nip44: nip44)
            onCreated(list)
            dismiss()
            app.show(.success, t("\(n).liveToast"))
        } catch {
            self.error = error.localizedDescription
        }
    }
}
