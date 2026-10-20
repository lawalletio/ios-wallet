import LaWalletKit
import SwiftUI

// MARK: recipient (send/recipient-input.tsx + shared/lightning-address-input.tsx)

struct SendRecipientScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var value = ""
    /// The value last picked from the list; while the field still holds it the list collapses.
    @State private var committed: String?
    @State private var error: String?
    @State private var loading = false
    @State private var contacts: [ContactsStore.Contact] = []
    /// Row picked with ↑/↓ on a hardware keyboard (web `highlightedOptionIndex`); Enter commits it.
    @State private var highlighted: Int?
    @FocusState private var focused: Bool

    private var query: String { value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: t("send.title"), close: true)
            VStack(alignment: .leading, spacing: 10) {
                Text(t("send.to")).font(LW.font(14, .semibold)).foregroundStyle(LW.muted).padding(.leading, 4)
                field
                if let error {
                    Text(error).font(LW.font(13)).foregroundStyle(LW.destructiveText).padding(.leading, 4).accessibilityIdentifier("error.text")
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 18)

            ZStack {
                if loading {
                    ProgressView().controlSize(.large).tint(LW.muted).accessibilityLabel(t("send.loadingNext"))
                } else {
                    options
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            BottomBar {
                Button { Task { await submit(value) } } label: {
                    BusyLabel(t("common.continue"), busy: loading, icon: "arrow-right")
                }
                .buttonStyle(.lw(.primary))
                .disabled(query.isEmpty || loading)
                .accessibilityIdentifier("send.continue")
            }
        }
        .onAppear {
            contacts = ContactsStore.shared.contacts
            focused = value.isEmpty
        }
    }

    // MARK: field

    private var settled: Bool { (!focused || committed == query) && Destination.isLightningAddress(query) }

    private var field: some View {
        HStack(spacing: 10) {
            if settled {
                PayAvatar(url: avatar(for: query), name: query, size: 30)
            }
            TextField("", text: $value, prompt: Text(verbatim: "satoshi@lawallet.ar, lnbc…, lnurl…").foregroundStyle(LW.muted.opacity(0.8)))
                .font(LW.font(16))
                .foregroundStyle(LW.foreground)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($focused)
                .disabled(loading)
                .onSubmit {
                    let rows = visible.all
                    if let i = highlighted, rows.indices.contains(i) { pick(rows[i]) } else { Task { await submit(value) } }
                }
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onChange(of: value) { _, next in
                    let lower = next.lowercased()
                    if lower != next { value = lower }
                    error = nil
                    // An exact match leaves one row: highlight it so Enter commits without an extra ↓.
                    highlighted = visible.exact && !visible.all.isEmpty ? 0 : nil
                }
                .accessibilityIdentifier("send.input")
            if settled {
                // A chip, not glass: it sits inside the glass field.
                Button { committed = nil; focused = true } label: {
                    Text(t("shared.addressInput.change")).font(LW.font(13, .semibold)).foregroundStyle(LW.foreground.opacity(0.85))
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(Color.white.opacity(0.10), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressScale())
            } else if value.isEmpty {
                // PasteButton reads the clipboard without the iOS "Allow Paste" prompt.
                PasteButton(payloadType: String.self) { strings in
                    guard let s = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return }
                    Task { @MainActor in
                        value = s.lowercased()
                        focused = false
                    }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .lwSystemGlass()
                .accessibilityIdentifier("send.paste")
            }
        }
        .padding(.leading, settled ? 12 : 16).padding(.trailing, 12).frame(minHeight: 54)
        .lwGlass(in: RoundedRectangle(cornerRadius: LW.Radius.control, style: .continuous))
        .overlay {
            if error != nil {
                RoundedRectangle(cornerRadius: LW.Radius.control, style: .continuous).strokeBorder(LW.destructiveText.opacity(0.7))
            }
        }
    }

    // MARK: options

    /// Rows currently listed, in display order (contacts first), as the web's `optionValues`.
    private var visible: (contacts: [ContactsStore.Contact], suggestions: [String], exact: Bool, all: [String]) {
        let q = query
        let suggestions = LightningSuggestions.build(value, currentDomain: LightningSuggestions.currentDomain(app.me?.lightningAddress))
        let exactContact = contacts.first { $0.address.lowercased() == q }
        let exactSuggestion = suggestions.first { $0 == q }
        let exact = exactContact != nil || exactSuggestion != nil
        let isCommitted = committed != nil && committed == q
        let recent = Array((q.isEmpty ? contacts : contacts.filter { LightningSuggestions.matches($0.address, q) }).prefix(10))
        let shownContacts = isCommitted ? [] : exact ? (exactContact.map { [$0] } ?? []) : recent
        let shownSuggestions = isCommitted ? [] : exact ? (exactContact == nil ? exactSuggestion.map { [$0] } ?? [] : []) : suggestions
        return (shownContacts, shownSuggestions, exact, shownContacts.map(\.address) + shownSuggestions)
    }

    /// ↓/↑ with wrap-around (`nextOptionIndex` in lightning-address-input.tsx).
    private func move(_ direction: Int) -> KeyPress.Result {
        let count = visible.all.count
        guard count > 0, !loading else { return .ignored }
        highlighted = Self.nextIndex(highlighted, count: count, direction: direction)
        return .handled
    }

    static func nextIndex(_ current: Int?, count: Int, direction: Int) -> Int? {
        guard count > 0 else { return nil }
        if direction > 0 { return current.map { $0 >= count - 1 ? 0 : $0 + 1 } ?? 0 }
        return current.map { $0 <= 0 || $0 >= count ? count - 1 : $0 - 1 } ?? count - 1
    }

    private func pick(_ address: String) {
        value = address
        committed = address.lowercased()
        highlighted = nil
        focused = false
        Task { await submit(address) }
    }

    @ViewBuilder private var options: some View {
        let rows = visible
        let shownContacts = rows.contacts, shownSuggestions = rows.suggestions
        if !shownContacts.isEmpty || !shownSuggestions.isEmpty {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !shownContacts.isEmpty {
                        group(t("shared.addressInput.saved")) {
                            ForEach(Array(shownContacts.enumerated()), id: \.element.address) { i, c in
                                option(c.address, avatar: c.avatar.flatMap(URL.init(string:)) ?? avatar(for: c.address), active: highlighted == i)
                            }
                        }
                    }
                    if !shownSuggestions.isEmpty {
                        group(t("shared.addressInput.suggestions")) {
                            ForEach(Array(shownSuggestions.enumerated()), id: \.element) { i, s in
                                option(s, avatar: avatar(for: s), active: highlighted == shownContacts.count + i)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .lwSoftScrollEdges()
            .scrollDismissesKeyboard(.interactively)
            .frame(maxHeight: .infinity, alignment: .top)
            .onChange(of: highlighted) { _, i in
                guard let i, rows.all.indices.contains(i) else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(rows.all[i]) }
            }
            }
        } else {
            Color.clear
        }
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(LW.font(14, .semibold)).foregroundStyle(LW.muted).padding(.leading, 4)
            VStack(spacing: 8) { content() }
        }
    }

    private func option(_ address: String, avatar: URL?, active: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Button {
            pick(address)
        } label: {
            HStack(spacing: 12) {
                PayAvatar(url: avatar, name: address, size: 34)
                Text(address).font(LW.font(15, .medium)).foregroundStyle(LW.foreground).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                Icon(active ? "arrow-right" : "chevron-right", size: 15).foregroundStyle(active ? theme.preset.primary : LW.muted.opacity(0.7))
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .contentShape(shape)
        }
        .buttonStyle(PressScale())
        // Keyboard highlight (↑/↓): brand-tinted glass plus a brand rim, so it reads at a glance.
        .lwGlass(in: shape, tint: active ? .color(theme.preset.primary.opacity(0.25)) : .none, interactive: true)
        .overlay { if active { shape.strokeBorder(theme.preset.primary.opacity(0.85), lineWidth: 1.5) } }
        .disabled(loading)
        .id(address)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier("send.option.\(address)")
    }

    private func avatar(for address: String) -> URL? {
        if let a = contacts.first(where: { $0.address.lowercased() == address.lowercased() })?.avatar { return URL(string: a) }
        return address.split(separator: "@").last.map(String.init).flatMap(AddressSuggestions.avatar)
    }

    // MARK: submit

    private func submit(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !loading else { return }
        value = text
        error = nil
        loading = true
        defer { loading = false }

        // bech32 LNURL / lnurlw:// / activation links resolve exactly like a scan.
        if LNURL.looksLike(text) || ActivationLink.parse(text) != nil {
            switch await ScanRouter.route(text, app: app) {
            case .handled: return
            case .unsupported(let msg): fail(msg)
            case .foreignActivation: fail(t("errors.destination.unsupported"))
            }
            return
        }

        let dest: Destination
        do { dest = try Destination.parse(text) } catch {
            fail(PayErrors.text(error, fallback: t("send.invalidRecipient")))
            return
        }
        let flows = app.flows
        flows.resetSend()
        flows.sendInput = text
        flows.destination = dest
        switch dest {
        case .invoice(_, let inv):
            if let amount = inv.amountSats, amount > 0 {
                flows.sendAmountSats = amount
                app.navigate(.sendPreview)
            } else {
                app.navigate(.sendAmount)
            }
        case .lnurlPay(let url, let address):
            flows.recipientLabel = address
            // Best effort: hydrate name / avatar / limits. A failed fetch still continues (the quote retries).
            if case .pay(let p)? = try? await LNURL.resolve(url: url) {
                flows.payParams = p
                flows.recipientAvatar = p.imageURL
            }
            app.navigate(.sendAmount)
        case .npub:
            flows.resetSend()
            fail(t("errors.payment.npubUnsupported"))
        }
    }

    private func fail(_ message: String) {
        error = message
        app.show(.error, message)
        Haptics.error()
    }
}

/// `lightning-address-suggestions.ts`: `username@domain` candidates, the user's own domain first.
enum LightningSuggestions {
    static let defaultDomain = "lawallet.io"

    static func currentDomain(_ address: String?) -> String {
        let d = address?.split(separator: "@").last.map { $0.lowercased() } ?? ""
        return d.wholeMatch(of: /[a-z0-9.-]+\.[a-z]{2,}/) != nil ? d : defaultDomain
    }

    static func matches(_ address: String, _ query: String) -> Bool {
        let a = address.lowercased(), q = query.lowercased()
        if q.isEmpty || a.hasPrefix(q) { return true }
        if q.contains("@") { return false }
        return a.split(separator: "@").first.map { $0.hasPrefix(q) } ?? false
    }

    static func build(_ input: String, currentDomain: String, limit: Int = 10) -> [String] {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty, text.wholeMatch(of: /(lnbc|lntb|lnbcrt|lnurl1|npub1).*/) == nil else { return [] }
        if text.hasPrefix("lightning:") { text.removeFirst(10) }
        let parts = text.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let username = parts[0]
        let domainQuery = parts.count > 1 ? parts[1] : ""
        guard username.wholeMatch(of: /[a-z0-9._-]{1,64}/) != nil else { return [] }
        var seen = Set<String>()
        return ([currentDomain] + AddressSuggestions.domains)
            .filter { seen.insert($0).inserted && (domainQuery.isEmpty || $0.hasPrefix(domainQuery)) }
            .prefix(limit)
            .map { "\(username)@\($0)" }
    }
}

// MARK: amount (send/amount-step.tsx)

struct SendAmountScreen: View {
    @Environment(AppModel.self) private var app
    @State private var value = "0"
    @State private var note = ""

    var body: some View {
        let flows = app.flows
        let sats = app.currencies.sats(fromInput: value)
        let params = flows.payParams
        let commentAllowed = params?.commentAllowed ?? 0
        let showNote: Bool = if case .lnurlPay? = flows.destination { commentAllowed > 0 } else { false }
        let outOfRange: String? = params.flatMap { p in
            guard let s = sats, p.maxSendableSats > 0, s < p.minSendableSats || s > p.maxSendableSats else { return nil }
            return t("ios.pay.amountRange", ["min": p.minSendableSats.formatted(), "max": p.maxSendableSats.formatted()])
        }

        VStack(spacing: 0) {
            ScreenHeader(title: t("send.amountTitle"))
            ScrollView {
                VStack(spacing: 16) {
                    if let info = flows.payRecipient { PayRecipientCard(info: info) }
                    PayAmountPad(value: $value)
                    if let p = params, p.maxSendableSats > 0, p.minSendableSats != p.maxSendableSats {
                        Text(t("ios.pay.range", ["min": p.minSendableSats.formatted(), "max": p.maxSendableSats.formatted()]))
                            .font(LW.font(13)).foregroundStyle(LW.muted)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 40)  // clears BottomBar's top fade
            }
            .scrollIndicators(.hidden)
            .lwSoftScrollEdges()
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)

            BottomBar {
                if showNote { noteField(max: commentAllowed) }
                ErrorText(message: outOfRange)
                Button { next(sats: sats, showNote: showNote, commentAllowed: commentAllowed) } label: {
                    BusyLabel(t("common.continue"), busy: false, icon: "arrow-right")
                }
                .buttonStyle(.lw(.primary))
                .disabled(sats == nil || outOfRange != nil)
                .accessibilityIdentifier("send.amount.continue")
            }
        }
        .onAppear { note = flows.sendComment }
        .task {
            // Scanned / typed addresses may arrive without LUD-06 params yet (`fetchPayRequest`).
            guard flows.payParams == nil, case .lnurlPay(let url, _)? = flows.destination,
                  case .pay(let p)? = try? await LNURL.resolve(url: url) else { return }
            flows.payParams = p
            if flows.recipientAvatar == nil { flows.recipientAvatar = p.imageURL }
        }
    }

    private func noteField(max: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: $note, prompt: Text(verbatim: t("send.amount.notePlaceholder")).foregroundStyle(LW.muted.opacity(0.8)))
                .font(LW.font(16))
                .foregroundStyle(LW.foreground)
                .textInputAutocapitalization(.sentences)
                .padding(.horizontal, 16).frame(minHeight: 54)
                .lwGlass(in: RoundedRectangle(cornerRadius: LW.Radius.control, style: .continuous))
                .onChange(of: note) { _, next in if next.count > max { note = String(next.prefix(max)) } }
                .accessibilityLabel(t("send.amount.noteAria"))
                .accessibilityIdentifier("send.amount.note")
            HStack {
                Text(t("send.amount.noteHint"))
                Spacer()
                Text(note.isEmpty ? t("send.amount.noteMax", ["n": "\(max)"]) : t("send.amount.noteLeft", ["n": "\(max - note.count)"]))
                    .monospacedDigit()
                    .foregroundStyle(note.count >= max ? LW.foreground : LW.muted)
            }
            .font(LW.font(12)).foregroundStyle(LW.muted).padding(.horizontal, 6)
        }
    }

    private func next(sats: Int?, showNote: Bool, commentAllowed: Int) {
        guard let sats else { return }
        app.flows.sendComment = showNote ? String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(commentAllowed)) : ""
        app.flows.sendAmountSats = sats
        app.navigate(.sendPreview)
    }
}

// MARK: preview (send/preview-step.tsx)

struct SendQuote: Equatable {
    let bolt11: String
    let amountSats: Int
    /// Only for zero-amount invoices.
    let payAmountSats: Int?
    let comment: String?
}

struct SendPreviewScreen: View {
    enum QuoteState: Equatable { case loading, ready(SendQuote), failed(String) }

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var quote: QuoteState = .loading
    @State private var paying = false
    @State private var error: String?

    var body: some View {
        let flows = app.flows
        VStack(spacing: 0) {
            ScreenHeader(title: t("send.previewTitle"))
            ScrollView {
                VStack(spacing: 16) {
                    summaryCard(flows)
                    quotePanel(flows)
                    equivalents(flows)
                    if let error { Text(error).font(LW.font(14)).foregroundStyle(LW.destructiveText).multilineTextAlignment(.center)
                        .accessibilityIdentifier("send.preview.error") }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .lwSoftScrollEdges()
            BottomBar {
                SwipeButton(label: quote == .loading ? t("send.preview.quotingPayment") : t("send.preview.swipeToPay"), loading: paying) {
                    Task { await pay() }
                }
                .disabled(!canPay)
            }
        }
        .task(id: quoteKey) { await makeQuote() }
    }

    private var canPay: Bool {
        if case .ready = quote { return app.wallet.hasWallet || app.me?.nwc != nil }
        return false
    }

    private var quoteKey: String {
        let f = app.flows
        return [f.sendInput, "\(f.sendAmountSats)", f.sendComment].joined(separator: "|")
    }

    // MARK: cards

    private func summaryCard(_ flows: FlowState) -> some View {
        let info = flows.payRecipient
        let acceptedNote: String? = if case .ready(let q) = quote { q.comment } else { flows.sendComment.isEmpty ? nil : flows.sendComment }
        let noteOmitted: Bool = if case .ready(let q) = quote { !flows.sendComment.isEmpty && q.comment == nil } else { false }
        let shownSats: Int = if case .ready(let q) = quote { q.amountSats } else { flows.sendAmountSats }
        return VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text(t("send.preview.sending")).font(LW.font(15, .semibold)).foregroundStyle(LW.muted)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(shownSats.formatted()).font(LW.font(60, .semibold)).tracking(-2).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.4)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: shownSats)
                    Text("sats").font(LW.font(20, .medium)).foregroundStyle(LW.muted)
                }
                .accessibilityIdentifier("send.preview.amount")
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 26)

            if let info {
                RowDivider()
                HStack(spacing: 14) {
                    PayAvatar(url: info.avatar, name: info.name, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("send.to")).font(LW.font(13, .semibold)).foregroundStyle(LW.muted)
                        Text(info.name).font(LW.font(18, .semibold)).lineLimit(1)
                        Text(info.subtitle).font(LW.font(14)).foregroundStyle(LW.muted).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18).padding(.vertical, 16)
                RowDivider()
                detailRow(t("send.preview.type"), kindLabel(flows.destination))
                if let acceptedNote {
                    RowDivider()
                    detailRow(t("send.note"), acceptedNote)
                } else if noteOmitted {
                    RowDivider()
                    Text(t("send.preview.noteOmitted")).font(LW.font(13)).foregroundStyle(LW.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.vertical, 14)
                }
            }
        }
        .lwSurface()
    }

    private func quotePanel(_ flows: FlowState) -> some View {
        let amount: Int = if case .ready(let q) = quote { q.amountSats } else { flows.sendAmountSats }
        let feeText: String = switch quote {
        case .loading: t("send.preview.feeQuoting")
        case .failed: t("send.preview.feeUnavailable")
        case .ready: t("send.preview.feeNotQuoted")
        }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("send.preview.quote")).font(LW.font(13, .semibold)).foregroundStyle(LW.muted)
                    Text(t("send.preview.beforeSending")).font(LW.font(16, .semibold))
                }
                Spacer()
                statusChip
            }
            VStack(spacing: 0) {
                quoteLine(t("send.preview.amount"), t("common.sats", ["n": amount.formatted()]))
                RowDivider().padding(.leading, -4)
                quoteLine(t("send.networkFee"), feeText, muted: true)
                RowDivider().padding(.leading, -4)
                quoteLine(t("send.preview.total"), t("send.preview.plusFee", ["amount": amount.formatted()]), strong: true)
            }
            .lwInset(LW.Radius.control - 4)

            switch quote {
            case .ready: Text(t("send.preview.feeQuoteUnavailable")).font(LW.font(13)).foregroundStyle(LW.muted)
            case .failed(let m): Text(m).font(LW.font(13)).foregroundStyle(LW.destructiveText).accessibilityIdentifier("send.preview.quoteError")
            case .loading: EmptyView()
            }
        }
        .padding(18)
        .lwSurface()
    }

    /// One small glass chip per active currency, outside the quote surface (no glass on glass).
    private func equivalents(_ flows: FlowState) -> some View {
        let amount: Int = if case .ready(let q) = quote { q.amountSats } else { flows.sendAmountSats }
        return VStack(alignment: .leading, spacing: 10) {
            Text(t("send.preview.equivalents")).font(LW.font(14, .semibold)).foregroundStyle(LW.muted).padding(.leading, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(app.currencies.active, id: \.self) { code in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(code == "SAT" ? "sats" : code).font(LW.font(12, .semibold)).foregroundStyle(LW.muted)
                        Text(Self.equivalent(amount, code, app.currencies.rates)).font(LW.font(15, .semibold)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .contentTransition(.numericText())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .lwGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder private var statusChip: some View {
        switch quote {
        case .loading:
            HStack(spacing: 6) { ProgressView().controlSize(.mini).tint(LW.muted); Text(t("send.preview.statusQuoting")) }
                .font(LW.font(12, .semibold)).foregroundStyle(LW.muted)
                .padding(.horizontal, 12).padding(.vertical, 6).background(Color.white.opacity(0.08), in: Capsule())
        case .failed:
            HStack(spacing: 6) { Circle().fill(LW.coral).frame(width: 6, height: 6); Text(t("send.preview.statusFailed")) }
                .font(LW.font(12, .semibold)).foregroundStyle(LW.destructiveText)
                .padding(.horizontal, 12).padding(.vertical, 6).background(LW.coral.opacity(0.16), in: Capsule())
        case .ready:
            HStack(spacing: 6) { Circle().fill(theme.preset.primary).frame(width: 6, height: 6); Text(t("send.preview.statusReady")) }
                .font(LW.font(12, .semibold)).foregroundStyle(LW.foreground)
                .padding(.horizontal, 12).padding(.vertical, 6).background(theme.preset.primary.opacity(0.18), in: Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("send.preview.ready")
        }
    }

    private func quoteLine(_ label: String, _ value: String, muted: Bool = false, strong: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(LW.muted)
            Spacer(minLength: 12)
            Text(value).fontWeight(strong ? .semibold : .medium).foregroundStyle(muted ? LW.muted : LW.foreground).lineLimit(1)
        }
        .font(LW.font(15))
        .padding(.horizontal, 14).padding(.vertical, 13)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(LW.muted)
            Spacer(minLength: 12)
            Text(value).fontWeight(.medium).multilineTextAlignment(.trailing)
        }
        .font(LW.font(15))
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private func kindLabel(_ d: Destination?) -> String {
        switch d {
        case .invoice?: t("send.kind.invoice")
        case .lnurlPay?: t("send.kind.address")
        case .npub?: t("send.kind.nostrZap")
        case nil: ""
        }
    }

    static func equivalent(_ sats: Int, _ code: String, _ rates: [String: Double]?) -> String {
        guard let v = Currencies.convert(sats: sats, to: code, rates: rates) else { return "..." }
        if code == "SAT" { return sats.formatted() }
        if code == "BTC" { return PayAmount.trimmed(v, 8) }
        return v.formatted(.number.precision(.fractionLength(0...(abs(v) >= 100 ? 0 : 2))))
    }

    // MARK: quote + pay (lib/client/nwc/pay.ts)

    private func makeQuote() async {
        let f = app.flows
        quote = .loading
        do {
            switch f.destination {
            case .invoice(let bolt11, let inv)?:
                let amount = inv.amountSats ?? f.sendAmountSats
                guard amount > 0 else { throw PayError(t("errors.payment.zeroAmountInvoice")) }
                quote = .ready(SendQuote(bolt11: bolt11, amountSats: amount, payAmountSats: inv.amountSats == nil ? amount : nil, comment: nil))
            case .lnurlPay(let url, _)?:
                var params = f.payParams
                if params == nil, case .pay(let p) = try await LNURL.resolve(url: url) {
                    params = p
                    f.payParams = p
                }
                guard let params else { throw LNURLError(.unsupported, t("errors.lnurl.unsupported")) }
                guard f.sendAmountSats > 0 else { throw PayError(t("errors.payment.amountRequired")) }
                let r = try await LNURL.requestInvoice(params, amountSats: f.sendAmountSats, comment: f.sendComment.isEmpty ? nil : f.sendComment)
                try Task.checkCancellation()
                quote = .ready(SendQuote(bolt11: r.pr, amountSats: Bolt11.decode(r.pr)?.amountSats ?? f.sendAmountSats,
                                         payAmountSats: nil, comment: r.comment))
            case .npub?:
                throw PayError(t("errors.payment.npubUnsupported"))
            case nil:
                app.popToRoot()
            }
        } catch is CancellationError {
        } catch {
            quote = .failed(PayErrors.text(error, fallback: t("send.preview.quoteFailed")))
        }
    }

    private func pay() async {
        guard case .ready(let q) = quote, !paying else {
            if case .failed(let m) = quote { app.show(.error, m) } else { app.show(.info, t("send.preview.preparingQuote")) }
            return
        }
        paying = true
        error = nil
        let flows = app.flows
        let info = flows.payRecipient
        guard let nwc = await app.freshNWC() else { return fail(t("send.preview.noWallet")) }
        do {
            let client: NWCClient
            if let c = app.wallet.client, app.wallet.uri == nwc { client = c } else { client = try NWCClient(uri: nwc) }
            let r = try await client.payInvoice(q.bolt11, amountSats: q.payAmountSats)
            let decoded = Bolt11.decode(q.bolt11)
            let now = Date()
            app.wallet.recordOutgoing(NWCTransaction(type: .outgoing, amountSats: q.amountSats, feesPaidSats: r.feesPaidSats,
                                                     description: q.comment ?? decoded?.description ?? "",
                                                     paymentHash: decoded?.paymentHash ?? q.bolt11, preimage: r.preimage,
                                                     invoice: q.bolt11, settledAt: now, createdAt: now, walletState: .settled))
            if let address = info?.address {
                ContactsStore.shared.remember(address, name: info?.name, avatar: flows.recipientAvatar?.absoluteString)
            }
            flows.sendResult = FlowState.SendResult(amountSats: q.amountSats, feeSats: r.feesPaidSats, preimage: r.preimage,
                                                    paymentHash: decoded?.paymentHash, recipient: info?.name ?? flows.sendInput,
                                                    comment: q.comment, date: now)
            paying = false
            app.path = [.sendSummary]
        } catch {
            fail(PayErrors.text(error, fallback: t("send.preview.paymentFailed")))
        }
    }

    private func fail(_ message: String) {
        error = message
        paying = false
        app.show(.error, message)
        Haptics.error()
    }
}

// MARK: summary (send/summary-step.tsx)

struct SendSummaryScreen: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let r = app.flows.sendResult {
            let code = app.currencies.selected
            let fee = "\(app.currencies.format(r.feeSats, code)) \(app.currencies.unit(code))"
            let destination = destinationLabel
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        PaymentReceipt(
                            status: .settled,
                            title: t("send.summary.title"),
                            amountSats: r.amountSats,
                            details: [(t("send.to"), r.recipient.isEmpty ? nil : r.recipient), (t("send.networkFee"), fee)]
                                + (destination != nil && destination != r.recipient ? [(t("send.summary.destination"), destination)] : [])
                                + (r.comment.map { [(t("send.note"), $0)] } ?? [])
                                + [(t("send.summary.time"), PayReceiptText.time(r.date))],
                            proofs: [(t("send.summary.paymentHash"), r.paymentHash), (t("send.summary.preimage"), r.preimage.isEmpty ? nil : r.preimage)]
                        )
                    }
                    .padding(.horizontal, 20).padding(.top, 32).padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
                .lwSoftScrollEdges()
                PayReceiptActions(shareText: PayReceiptText.build(amount: "\(app.currencies.format(r.amountSats, code)) \(app.currencies.unit(code))",
                                                            fee: fee, recipient: r.recipient, destination: destination, comment: r.comment,
                                                            date: r.date, paymentHash: r.paymentHash, preimage: r.preimage)) {
                    app.popToRoot()
                    app.flows.resetSend()
                }
            }
        }
    }

    /// `destinationForReceipt`: the address (or raw LNURL), or the invoice's own description.
    private var destinationLabel: String? {
        switch app.flows.destination {
        case .lnurlPay(_, let address)?: address ?? app.flows.sendInput
        case .invoice(_, let inv)?: inv.description
        default: app.flows.sendInput.isEmpty ? nil : app.flows.sendInput
        }
    }
}
