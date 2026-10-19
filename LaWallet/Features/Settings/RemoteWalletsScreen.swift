import LaWalletKit
import SwiftUI

/// `GET /api/remote-wallets` row plus `updatedAt`, which the shared model doesn't carry (the list shows "Updated {date}").
struct ListedWallet: Decodable, Identifiable, Hashable {
    let wallet: RemoteWallet
    let updatedAt: String?
    var id: String { wallet.id }

    private enum Keys: String, CodingKey { case updatedAt }
    init(from decoder: Decoder) throws {
        wallet = try RemoteWallet(from: decoder)
        updatedAt = try decoder.container(keyedBy: Keys.self).decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

extension LaWalletAPI {
    func listedRemoteWallets() async throws -> [ListedWallet] { try await http.get("/api/remote-wallets") }
}

/// `/wallet/settings/remote-wallets` — settings/remote-wallets-screen.tsx.
struct RemoteWalletsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var wallets: [ListedWallet]?
    @State private var failed = false
    @State private var pending: String?
    @State private var statusOverride: [String: Bool] = [:]
    @State private var showAdd = false
    @State private var showProxy = false
    @State private var prefill: String?
    @State private var deleting: RemoteWallet?
    private let l = "remoteWallets.list"

    private var sorted: [ListedWallet] {
        (wallets ?? []).sorted { a, b in
            if a.wallet.isDefault != b.wallet.isDefault { return a.wallet.isDefault }
            if a.wallet.status != b.wallet.status { return a.wallet.isActive }
            return a.wallet.name.localizedCompare(b.wallet.name) == .orderedAscending
        }
    }

    var body: some View {
        SettingsPage(title: t("settings.remoteWallets"), refresh: load) {
            if wallets == nil && !failed {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16).fill(LW.card).frame(height: 96).shimmer()
                }
                .accessibilityLabel(t("\(l).loading"))
            } else if failed {
                SettingsEmptyState(title: t("\(l).errorTitle"), message: t("\(l).tryAgain"), dashed: false) {
                    Button { Task { await load() } } label: { Label { Text(t("common.retry")) } icon: { Icon("refresh-cw", size: 16) } }
                        .buttonStyle(.lw(.outline, height: 40, fullWidth: false))
                }
            } else if sorted.isEmpty {
                SettingsEmptyState(icon: "wallet", title: t("\(l).emptyTitle"), message: t("\(l).emptyBody")) { addButton }
            } else {
                HStack(spacing: 8) {
                    Spacer()
                    Button { showProxy = true } label: { Label { Text(t("addresses.createProxy.title")) } icon: { Icon("git-branch", size: 16) } }
                        .buttonStyle(.lw(.outline, height: 40, fullWidth: false))
                        .accessibilityIdentifier("wallets.proxy")
                    addButton
                }
                VStack(spacing: 12) {
                    ForEach(sorted) { row($0) }
                }
            }
        }
        .task { await load() }
        .onAppear {
            // A scanned / deep-linked `nostr+walletconnect://` lands here; open the add sheet prefilled.
            let input = app.flows.sendInput
            if input.lowercased().hasPrefix("nostr+walletconnect://") || input.lowercased().hasPrefix("nostrwalletconnect://") {
                prefill = input
                app.flows.sendInput = ""
                showAdd = true
            }
        }
        .sheet(isPresented: $showAdd, onDismiss: { prefill = nil }) {
            AddWalletSheet(onlyWallet: wallets?.isEmpty == true, prefill: prefill) { await changed() }
                .presentationBackground(LW.background)
        }
        .sheet(isPresented: $showProxy) {
            ProxyWalletSheet(wallets: sorted.map(\.wallet)) { await changed() }
                .presentationBackground(LW.background)
        }
        .alert(t("ios.set.wallets.deleteTitle", ["name": deleting?.name ?? ""]),
               isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(t("common.cancel"), role: .cancel) {}
            Button(t("ios.set.wallets.delete"), role: .destructive) {
                if let w = deleting {
                    Task { await run(w, t("ios.set.wallets.deleted", ["name": w.name])) { try await app.api.deleteRemoteWallet(w.id) } }
                }
            }
        } message: { Text(t("ios.set.wallets.deleteBody")) }
    }

    private var addButton: some View {
        Button { showAdd = true } label: { Label { Text(t("ios.set.wallets.add")) } icon: { Icon("plus", size: 16) } }
            .buttonStyle(.lw(.primary, height: 40, fullWidth: false))
            .accessibilityIdentifier("wallets.add")
    }

    // MARK: rows

    private func row(_ item: ListedWallet) -> some View {
        let w = item.wallet
        let active = statusOverride[w.id] ?? w.isActive
        let updated = t("\(l).updated", ["type": w.type, "date": SettingsFormat.shortDate(item.updatedAt ?? w.createdAt)])
        let toggle = Toggle("", isOn: Binding(get: { active }, set: { on in Task { await setStatus(w, on) } }))
            .labelsHidden()
            .disabled(pending == w.id)
            .accessibilityLabel(t(active ? "\(l).disable" : "\(l).enable", ["name": w.name]))
            .accessibilityIdentifier("wallets.toggle.\(w.id)")
        let title = Button { app.navigate(.remoteWalletDetail(w.id)) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(w.name).font(LW.font(16, .semibold)).lineLimit(1)
                Text(updated).font(LW.font(12)).foregroundStyle(LW.muted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("wallets.row.\(w.id)")
        let icon = Icon("wallet").foregroundStyle(LW.muted).frame(width: w.isDefault ? 44 : 40, height: w.isDefault ? 44 : 40)
            .background(LW.background).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        return Group {
            if w.isDefault {
                HStack(alignment: .top, spacing: 12) {
                    icon
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 12) { title; toggle }
                        HStack(spacing: 8) {
                            SettingsBadge(t("\(l).primary"), .primary)
                            if w.isLncurl { SettingsBadge("LNCurl") }
                        }
                    }
                }
                .padding(16)
                .background(LW.card).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.preset.primary.opacity(0.5)))
                .shadow(color: theme.preset.primary.opacity(0.15), radius: 24, y: 12)
            } else {
                HStack(spacing: 12) {
                    icon
                    VStack(alignment: .leading, spacing: 4) {
                        title
                        if w.isLncurl { SettingsBadge("LNCurl") }
                    }
                    if !w.isDefault && active {
                        Button { Task { await run(w, t("\(l).nowPrimary", ["name": w.name])) { _ = try await app.api.updateRemoteWallet(w.id, makeDefault: true) } } } label: {
                            HStack(spacing: 4) {
                                if pending == w.id { ProgressView().controlSize(.mini) } else { Icon("star", size: 14) }
                                Text(t("\(l).setPrimary")).font(LW.font(13, .medium))
                            }
                        }
                        .buttonStyle(.lw(.secondary, height: 32, fullWidth: false))
                        .disabled(pending == w.id)
                        .accessibilityIdentifier("wallets.primary.\(w.id)")
                    }
                    toggle
                }
                .padding(12)
                .background(LW.card).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(LW.border.opacity(0.4)))
            }
        }
        .opacity(active ? 1 : 0.7)
        .contextMenu {
            Button(role: .destructive) { deleting = w } label: { Label(t("ios.set.wallets.delete"), image: "lucide-trash-2") }
        }
    }

    // MARK: actions

    private func load() async {
        do {
            wallets = try await app.api.listedRemoteWallets()
            failed = false
        } catch {
            if wallets == nil { failed = true } else { app.show(.error, error.localizedDescription) }
        }
    }

    /// After any change: reload, then `/me` so a new primary reconnects the home wallet.
    private func changed() async {
        await load()
        await app.refreshMe()
    }

    private func setStatus(_ w: RemoteWallet, _ on: Bool) async {
        statusOverride[w.id] = on
        await run(w, t(on ? "\(l).enabledToast" : "\(l).disabledToast", ["name": w.name])) {
            _ = try await app.api.updateRemoteWallet(w.id, status: on ? "ACTIVE" : "DISABLED")
        }
        statusOverride[w.id] = nil
    }

    private func run(_ w: RemoteWallet, _ success: String, _ work: () async throws -> Void) async {
        pending = w.id
        defer { pending = nil }
        do {
            try await work()
            app.show(.success, success)
            await changed()
        } catch {
            app.show(.error, error.localizedDescription.nonBlank ?? t("\(l).updateFailed"))
        }
    }
}

// MARK: add wallet (admin/create-remote-wallet-dialog.tsx)

struct AddWalletSheet: View {
    enum Method { case lncurl, nwc }
    enum Probe: Equatable { case idle, invalid, checking, success(NWCInfo), failed(String) }

    let onlyWallet: Bool
    var prefill: String?
    let onCreated: () async -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var method: Method = .nwc
    @State private var uri = ""
    @State private var name = ""
    @State private var isDefault = false
    @State private var probe: Probe = .idle
    @State private var creating = false
    @State private var error: String?
    private let w = "ios.set.wallets"

    private var trimmedURI: String { uri.trimmedValue }
    private var looksLikeNWC: Bool {
        let s = trimmedURI.lowercased()
        return s.hasPrefix("nostr+walletconnect://") || s.hasPrefix("nostrwalletconnect://")
    }
    private var info: NWCInfo? { if case .success(let i) = probe { i } else { nil } }
    private var canSend: Bool { info?.methods.contains("pay_invoice") ?? false }
    private var cannotReceive: Bool { method == .nwc && info.map { !$0.methods.contains("make_invoice") } == true }
    private var derivedName: String {
        if let alias = info?.alias?.nonBlank { return String(alias.prefix(120)) }
        let pubkey = trimmedURI.replacingOccurrences(of: "^(?:nostr\\+walletconnect|nostrwalletconnect)://", with: "", options: [.regularExpression, .caseInsensitive])
            .split(whereSeparator: { "/?#".contains($0) }).first.map(String.init) ?? ""
        let short = String(pubkey.filter { $0.isLetter || $0.isNumber }.prefix(8))
        return short.isEmpty ? "NWC wallet" : "NWC \(short)"
    }
    private var submitName: String { String((name.nonBlank ?? derivedName).prefix(120)) }
    private var canSubmit: Bool {
        guard !creating else { return false }
        if method == .lncurl { return true }
        switch probe {
        case .success, .failed: return looksLikeNWC && !submitName.isEmpty
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("\(w).addTitle")).font(LW.font(20, .semibold))
                        Text(t("\(w).addBody")).font(LW.font(14)).foregroundStyle(LW.muted)
                    }
                    if app.settings?.lncurlEnabled == true { methodPicker }
                    if method == .nwc { nwcForm } else { lncurlForm }
                    ErrorText(message: error).frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            HStack(spacing: 12) {
                Button(t("common.cancel")) { dismiss() }.buttonStyle(.lw(.outline)).disabled(creating)
                Button { Task { await submit() } } label: {
                    HStack(spacing: 8) {
                        if creating { ProgressView().tint(LW.foreground) }
                        Text(t(method == .lncurl ? "\(w).create" : "\(w).add"))
                    }
                }
                .buttonStyle(.lw(.theme))
                .disabled(!canSubmit)
                .accessibilityIdentifier("wallets.save")
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .onAppear {
            if let prefill { uri = prefill } else if app.settings?.lncurlEnabled == true { method = .lncurl }
        }
        .task(id: trimmedURI) { await runProbe() }
    }

    private var methodPicker: some View {
        HStack(spacing: 4) {
            segment(t("\(w).methodLncurl"), .lncurl).accessibilityIdentifier("wallets.lncurl")
            segment(t("\(w).methodNwc"), .nwc).accessibilityIdentifier("wallets.nwc")
        }
        .padding(4)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(LW.border))
    }

    private func segment(_ label: String, _ m: Method) -> some View {
        Button { method = m; error = nil } label: {
            Text(label).font(LW.font(13, .medium)).lineLimit(2).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 36).padding(.horizontal, 6)
                .foregroundStyle(method == m ? Color(hex: "0a0a0a") : LW.muted)
                .background(method == m ? theme.preset.primary : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .disabled(creating)
    }

    @ViewBuilder private var nwcForm: some View {
        field(t("\(w).connection")) {
            HStack(spacing: 8) {
                // Masked like the web `type="password"` input — the URI carries a shared secret.
                LWTextField(placeholder: "nostr+walletconnect://...", text: $uri, secure: true, mono: true)
                    .accessibilityIdentifier("wallets.nwcField")
                PasteButton(payloadType: String.self) { items in
                    if let s = items.first { uri = s.trimmedValue }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .accessibilityLabel(t("ios.scan.paste"))
            }
            hint(t("\(w).connectionHint"))
        }
        if probe != .idle {
            field(t("\(w).capabilities")) {
                capabilities
                hint(t("\(w).capabilitiesHint"))
            }
        }
        field(t("\(w).nameOptional")) {
            LWTextField(placeholder: derivedName, text: $name)
                .onChange(of: name) { _, v in if v.count > 120 { name = String(v.prefix(120)) } }
                .accessibilityIdentifier("wallets.name")
        }
        if !onlyWallet {
            primaryToggle(hint: cannotReceive ? t("\(w).cannotReceive") : t("\(w).primaryHint"), allowed: !cannotReceive)
        }
    }

    @ViewBuilder private var lncurlForm: some View {
        HStack(alignment: .top, spacing: 8) {
            Icon("alert-triangle", size: 16)
            Text((try? AttributedString(markdown: t("\(w).lncurlWarning"))) ?? AttributedString(t("\(w).lncurlWarning"))).font(LW.font(14))
        }
        .foregroundStyle(LW.gold)
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(LW.gold.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(LW.gold.opacity(0.4)))
        hint(t("\(w).lncurlHint"))
        field(t("\(w).nameOptional")) {
            LWTextField(placeholder: t("\(w).lncurlPlaceholder"), text: $name).accessibilityIdentifier("wallets.name")
        }
        if !onlyWallet { primaryToggle(hint: t("\(w).primaryHint"), allowed: true) }
    }

    @ViewBuilder private var capabilities: some View {
        switch probe {
        case .checking:
            capabilityBox(LW.border) {
                ProgressView().controlSize(.small)
                Text(t("\(w).detecting")).foregroundStyle(LW.muted)
            }
        case .invalid:
            capabilityBox(LW.destructive) { Text(t("\(w).invalid")).foregroundStyle(LW.destructiveText) }
        case .failed(let message):
            capabilityBox(LW.gold.opacity(0.4)) {
                Icon("alert-triangle", size: 16)
                Text(t("\(w).probeFailed", ["error": message])).lineLimit(2)
            }
            .foregroundStyle(LW.gold)
        case .success(let i):
            let receive = i.methods.contains("make_invoice")
            let alias = i.alias?.nonBlank.map { " · \($0)" } ?? ""
            if !receive {
                capabilityBox(LW.gold.opacity(0.4)) {
                    Icon("alert-triangle", size: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t(canSend ? "\(w).sendOnly" : "\(w).viewOnly") + alias).font(LW.font(14, .medium))
                        Text(t("\(w).cannotReceive")).font(LW.font(12))
                    }
                }
                .foregroundStyle(LW.gold)
            } else {
                capabilityBox(LW.incoming.opacity(0.4)) {
                    Icon(canSend ? "arrow-up-right" : "arrow-down-to-line", size: 16).foregroundStyle(LW.incoming)
                    Text(t(canSend ? "\(w).sendReceive" : "\(w).receiveOnly")).font(LW.font(14, .medium))
                    Text(alias).foregroundStyle(LW.muted).lineLimit(1)
                    Spacer()
                    Icon("check", size: 16).foregroundStyle(LW.incoming)
                }
                .accessibilityIdentifier("wallets.capabilities")
            }
        case .idle: EmptyView()
        }
    }

    private func capabilityBox<C: View>(_ stroke: Color, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) { content() }
            .font(LW.font(14))
            .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(stroke))
    }

    private func primaryToggle(hint text: String, allowed: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(t("\(w).primary")).font(LW.font(14, .medium))
                Text(text).font(LW.font(12)).foregroundStyle(LW.muted)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { isDefault && allowed }, set: { isDefault = $0 })).labelsHidden().disabled(creating || !allowed)
                .accessibilityIdentifier("wallets.makePrimary")
        }
        .padding(12).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(LW.border))
        .opacity(allowed ? 1 : 0.7)
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(LW.font(14, .medium))
            content()
        }
    }

    private func hint(_ text: String) -> some View { Text(text).font(LW.font(12)).foregroundStyle(LW.muted) }

    /// Debounced NIP-47 `get_info` probe: decides SEND_RECEIVE vs RECEIVE and the default name.
    private func runProbe() async {
        guard looksLikeNWC else { probe = .idle; return }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        guard let client = try? NWCClient(uri: trimmedURI) else { probe = .invalid; return }
        probe = .checking
        do {
            let i = try await client.getInfo()
            if !Task.isCancelled { probe = .success(i) }
        } catch {
            if !Task.isCancelled { probe = .failed(error.localizedDescription) }
        }
    }

    private func submit() async {
        guard canSubmit else { return }
        creating = true
        error = nil
        defer { creating = false }
        let primary = !cannotReceive && (onlyWallet || isDefault)
        do {
            let message: String
            if method == .lncurl {
                _ = try await app.api.createLncurlWallet(name: name.nonBlank, isDefault: primary)
                message = t("\(w).lncurlCreated")
            } else {
                _ = try await app.api.createNWCWallet(name: submitName, connectionString: trimmedURI, sendReceive: canSend, isDefault: primary)
                message = t("\(w).added")
            }
            await onCreated()
            dismiss()
            app.show(.success, message)
        } catch let e as APIError where e.status == 409 {
            if method == .nwc && name.isEmpty { name = derivedName }
            error = t("\(w).nameTaken")
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: proxy wallet (wallet/create-proxy-wallet-dialog.tsx)

struct ProxyWalletSheet: View {
    let wallets: [RemoteWallet]
    let onDone: () async -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var walletId = ""
    @State private var destination = ""
    @State private var fee = "0.50"
    @State private var baseFee = "1"
    @State private var busy = false
    @State private var error: String?
    private let p = "addresses.createProxy"

    private var selectable: [RemoteWallet] { wallets.filter { $0.type == "NWC" && $0.isActive } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("\(p).title")).font(LW.font(20, .semibold))
                        Text(t("\(p).description")).font(LW.font(14)).foregroundStyle(LW.muted)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(t("\(p).sourceWallet")).font(LW.font(14, .medium))
                        Menu {
                            ForEach(selectable) { w in Button(w.name) { walletId = w.id } }
                        } label: {
                            HStack {
                                Text(selectable.first { $0.id == walletId }?.name ?? t("\(p).selectWallet"))
                                    .foregroundStyle(walletId.isEmpty ? LW.muted : LW.foreground)
                                Spacer()
                                Icon("chevron-down", size: 16).foregroundStyle(LW.muted)
                            }
                            .font(LW.font(16)).padding(.horizontal, 14).frame(minHeight: 52)
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LW.border))
                        }
                        .accessibilityIdentifier("proxy.source")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(t("addresses.destination")).font(LW.font(14, .medium))
                        LWTextField(placeholder: "name@example.com", text: $destination).keyboardType(.emailAddress)
                            .accessibilityIdentifier("proxy.destination")
                    }
                    HStack(spacing: 12) {
                        numberField(t("\(p).entryFee"), $fee, decimal: true)
                        numberField(t("\(p).baseFee"), $baseFee, decimal: false)
                    }
                    ErrorText(message: error).frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            HStack(spacing: 12) {
                Button(t("common.cancel")) { dismiss() }.buttonStyle(.lw(.outline))
                Button { Task { await configure() } } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView().tint(LW.foreground) }
                        Text(t("\(p).enable"))
                    }
                }
                .buttonStyle(.lw(.theme))
                .disabled(walletId.isEmpty || destination.trimmedValue.isEmpty || busy)
                .accessibilityIdentifier("proxy.save")
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
    }

    private func numberField(_ label: String, _ text: Binding<String>, decimal: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(LW.font(14, .medium))
            LWTextField(placeholder: "0", text: text).keyboardType(decimal ? .decimalPad : .numberPad)
        }
    }

    private func configure() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            _ = try await app.api.saveReceiveAction(walletId, feeBps: Int(((SettingsFormat.number(fee) ?? 0) * 100).rounded()),
                                                    baseFeeSats: Int(SettingsFormat.number(baseFee) ?? 0), enabled: true,
                                                    destinations: [ForwardingDestination(address: destination.trimmedValue, allocationBps: 10_000)])
            await onDone()
            dismiss()
            app.show(.success, t("\(p).created"))
        } catch {
            self.error = error.localizedDescription.nonBlank ?? t("\(p).enableFailed")
        }
    }
}
