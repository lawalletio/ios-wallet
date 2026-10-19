import LaWalletKit
import SwiftUI

/// Settlement proof for the receive summary.
/// ponytail: lives here because `FlowState` has no settledAt/preimage fields; move it there if another screen needs it.
@MainActor
enum ReceiveSettlement {
    static var settledAt: Date?
    static var preimage: String?
}

// MARK: address (receive/address-step.tsx)

struct ReceiveAddressScreen: View {
    @Environment(AppModel.self) private var app
    @State private var credit: NWCTransaction?

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: t("receive.title"), close: true)
            if app.me == nil {
                Spacer()
                HStack(spacing: 10) { ProgressView().tint(LW.muted); Text(t("common.loading")) }
                    .font(LW.font(14)).foregroundStyle(LW.muted)
                Spacer()
            } else if let address = app.me?.lightningAddress {
                VStack {
                    Spacer()
                    QRDisplay(value: address, caption: address)
                        .overlay(alignment: .top) {
                            if let credit {
                                // Covers QRDisplay's white code tile (232 + 2×16) inside its 10 pt glass bezel.
                                Text("+\(credit.amountSats.formatted())")
                                    .font(LW.font(44, .semibold)).tracking(-1.4).monospacedDigit().foregroundStyle(LW.incoming)
                                    .frame(width: 264, height: 264)
                                    .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    .padding(.top, 10)
                                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                                    .id(credit.id)
                                    .accessibilityIdentifier("receive.credit")
                            }
                        }
                    Spacer()
                }
                .padding(.horizontal, 20)
                BottomBar {
                    Button { app.navigate(.receiveAmount) } label: {
                        Label { Text(t("receive.requestAmount")) } icon: { Icon("plus", size: 16) }
                    }
                    .buttonStyle(.lw(.secondary))
                    .accessibilityIdentifier("receive.requestAmount")
                }
            } else {
                VStack(spacing: 18) {
                    Icon("qr-code", size: 26).foregroundStyle(LW.muted).frame(width: 64, height: 64).lwGlass(in: Circle())
                    Text(t("receive.noAddress")).font(LW.font(15)).foregroundStyle(LW.muted).multilineTextAlignment(.center)
                    Button(t("receive.claimUsername")) { app.navigate(.claimUsername(fromActivation: false, bonus: false)) }
                        .buttonStyle(.lw(.secondary, fullWidth: false))
                        .accessibilityIdentifier("receive.claimUsername")
                }
                .padding(.horizontal, 20)
                .frame(maxHeight: .infinity)
            }
        }
        .onChange(of: app.wallet.lastPayment) { _, tx in
            guard let tx, tx.type == .incoming else { return }
            withAnimation(.spring(duration: 0.4)) { credit = tx }
            Task {
                try? await Task.sleep(for: .seconds(1.8))
                withAnimation(.easeOut) { if credit == tx { credit = nil } }
            }
        }
    }
}

// MARK: amount (receive/amount-step.tsx)

struct ReceiveAmountScreen: View {
    @Environment(AppModel.self) private var app
    @State private var value = "0"
    @State private var note = ""
    @State private var loading = false

    var body: some View {
        let sats = app.currencies.sats(fromInput: value)
        let autoCreate = app.settings?.lncurlAutoCreate == true || app.settings?.lncurlEnabled == true
        VStack(spacing: 0) {
            ScreenHeader(title: t("receive.title"))
            ScrollView {
                PayAmountPad(value: $value, disabled: loading)
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .lwSoftScrollEdges()
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            BottomBar {
                TextField("", text: $note, prompt: Text(verbatim: t("receive.notePlaceholder")).foregroundStyle(LW.muted.opacity(0.8)))
                    .font(LW.font(16))
                    .foregroundStyle(LW.foreground)
                    .padding(.horizontal, 16).frame(minHeight: 54)
                    .lwGlass(in: RoundedRectangle(cornerRadius: LW.Radius.control, style: .continuous))
                    .accessibilityLabel(t("receive.notePlaceholder"))
                    .disabled(loading)
                    .accessibilityIdentifier("receive.amount.note")
                Button { Task { await create(sats) } } label: {
                    PayButtonLabel(busy: loading, title: t("common.continue"), busyTitle: t("receive.creatingInvoice"), icon: "arrow-right")
                }
                .buttonStyle(.lw(.primary))
                .disabled(sats == nil || loading || (!app.wallet.hasWallet && !autoCreate))
                .accessibilityIdentifier("receive.amount.continue")
            }
        }
        // Re-entering always starts a new request.
        .onAppear { app.flows.resetReceive() }
    }

    private func create(_ sats: Int?) async {
        guard let sats, !loading else { return }
        loading = true
        defer { loading = false }
        let flows = app.flows
        flows.receiveAmountSats = sats
        flows.receiveNote = note
        do {
            let nwc = try await app.ensureWallet()
            let client: NWCClient
            if let c = app.wallet.client, app.wallet.uri == nwc { client = c } else { client = try NWCClient(uri: nwc) }
            let invoice = try await client.makeInvoice(amountSats: sats, description: note.trimmingCharacters(in: .whitespacesAndNewlines))
            flows.invoice = invoice
            ReceiveSettlement.settledAt = nil
            ReceiveSettlement.preimage = nil
            app.navigate(.receiveInvoice)
        } catch {
            let message = PayErrors.text(error)
            app.show(.error, message)
            Haptics.error()
        }
    }
}

// MARK: invoice (receive/invoice-step.tsx + boltcard-nfc-status.tsx)

struct ReceiveInvoiceScreen: View {
    enum NFCPhase: Equatable { case idle, scanning, charging, accepted(Date), failed(String) }

    @Environment(AppModel.self) private var app
    @State private var nfc: NFCPhase = .idle
    @State private var settled = false
    @State private var copied = false

    var body: some View {
        if let inv = app.flows.invoice {
            content(inv)
        }
    }

    private var accepted: Bool { if case .accepted = nfc { true } else { false } }

    private func content(_ inv: NWCMadeInvoice) -> some View {
        VStack(spacing: 0) {
            ScreenHeader(title: t("receive.invoiceTitle"))
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(inv.amountSats.formatted()).font(LW.font(56, .semibold)).tracking(-2).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.4)
                                .contentTransition(.numericText())
                            Text("sats").font(LW.font(20, .medium)).foregroundStyle(LW.muted)
                        }
                        .accessibilityIdentifier("receive.invoice.amount")
                        if !inv.description.isEmpty {
                            Text(inv.description).font(LW.font(15)).foregroundStyle(LW.muted).multilineTextAlignment(.center)
                        }
                    }
                    if accepted {
                        BoltcardAccepted(amountSats: inv.amountSats)
                    } else {
                        invoiceQR(inv)
                        status(inv)
                        nfcStatus(inv)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .lwSoftScrollEdges()
        }
        .onChange(of: app.wallet.lastPayment) { _, tx in
            if let tx, tx.type == .incoming, tx.paymentHash == inv.paymentHash { settle(tx) }
        }
        .task(id: inv.paymentHash) { await poll(inv) }
    }

    // MARK: QR

    private func invoiceQR(_ inv: NWCMadeInvoice) -> some View {
        let preview = "\(inv.bolt11.prefix(12))…\(inv.bolt11.suffix(8))"
        // Same white tile + glass bezel as `QRDisplay` (kept local for the invoice's own copy/a11y identifiers).
        return VStack(spacing: 18) {
            // Upper-cased for a denser (bolt11-safe) QR, like `uppercasePayload`.
            QRCodeImage(text: inv.bolt11.uppercased())
                .frame(width: 232, height: 232)
                .padding(16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityElement()
                .accessibilityLabel(t("receive.invoiceTitle"))
                .accessibilityIdentifier("receive.invoice.qr")
                .padding(10)
                .lwSurface(LW.Radius.sheet)
            Text(preview).font(LW.font(15, .medium)).foregroundStyle(LW.foreground.opacity(0.85))
            GlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = inv.bolt11
                        copied = true
                        Haptics.tap()
                        app.show(.success, t("common.copied"))
                        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                    } label: {
                        Label { Text(copied ? t("common.copied") : t("common.copy")) } icon: { Icon(copied ? "check" : "copy", size: 16) }
                    }
                    .buttonStyle(.lw(.secondary, height: 46))
                    .accessibilityIdentifier("receive.invoice.copy")
                    ShareLink(item: inv.bolt11) {
                        Icon("share-2", size: 17).foregroundStyle(LW.foreground).frame(width: 46, height: 46).contentShape(Circle())
                    }
                    .lwGlass(in: Circle(), interactive: true)
                    .accessibilityLabel(t("common.share"))
                }
            }
            .frame(width: 272)
        }
    }

    /// "Waiting for payment · expires in m:ss" as one small glass capsule; the expired state swaps in a retry.
    @ViewBuilder private func status(_ inv: NWCMadeInvoice) -> some View {
        let waiting = nfc != .charging
        if let expiresAt = inv.expiresAt ?? Bolt11.decode(inv.bolt11)?.expiresAt {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let left = Int(expiresAt.timeIntervalSince(ctx.date))
                if left > 0 {
                    statusPill(waiting: waiting, expiry: t("ios.pay.expiresIn", ["time": Self.clock(left)]))
                } else {
                    VStack(spacing: 10) {
                        Text(t("ios.pay.expired")).font(LW.font(14, .medium)).foregroundStyle(LW.destructiveText)
                        Button(t("ios.pay.newInvoice")) { app.path.removeLast() }
                            .buttonStyle(.lw(.secondary, height: 44, fullWidth: false))
                    }
                }
            }
            .accessibilityIdentifier("receive.invoice.expiry")
        } else if waiting {
            statusPill(waiting: true, expiry: nil)
        }
    }

    private func statusPill(waiting: Bool, expiry: String?) -> some View {
        HStack(spacing: 8) {
            PulseDot()
            if waiting { Text(t("receive.waitingPayment")).foregroundStyle(LW.foreground.opacity(0.9)) }
            if waiting && expiry != nil { Text(verbatim: "·") }
            if let expiry { Text(expiry).monospacedDigit() }
        }
        .font(LW.font(13, .medium)).foregroundStyle(LW.muted)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .lwGlass(in: Capsule())
        .accessibilityElement(children: .combine)
    }

    static func clock(_ seconds: Int) -> String {
        let h = seconds / 3600, m = seconds % 3600 / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: NFC (use-boltcard-nfc.ts)

    @ViewBuilder private func nfcStatus(_ inv: NWCMadeInvoice) -> some View {
        switch nfc {
        case .idle:
            if NFCReader.isAvailable {
                Button { Task { await tapCard(inv) } } label: {
                    Label { Text(t("ios.nfc.tapCard")) } icon: { Icon("nfc", size: 16) }
                }
                .buttonStyle(.lw(.outline, height: 44, fullWidth: false))
                .accessibilityIdentifier("receive.nfc")
            } else {
                HStack(spacing: 6) { Icon("nfc", size: 14); Text(t("receive.nfc.unsupported")) }
                    .font(LW.font(13)).foregroundStyle(LW.muted).multilineTextAlignment(.center)
            }
        case .scanning:
            VStack(spacing: 10) {
                NFCPulse()
                Text(t("receive.nfc.scanning")).font(LW.font(13)).foregroundStyle(LW.muted).multilineTextAlignment(.center)
            }
        case .charging:
            HStack(spacing: 8) { ProgressView().controlSize(.small).tint(LW.muted); Text(t("receive.nfc.charging")) }
                .font(LW.font(14, .medium))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .lwGlass(in: Capsule())
        case .failed(let message):
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 6) { Icon("alert-triangle", size: 14); Text(message) }
                    .font(LW.font(13)).foregroundStyle(LW.destructiveText).multilineTextAlignment(.center)
                    .accessibilityIdentifier("receive.nfc.error")
                Button(t("receive.nfc.tryAgain")) { Task { await tapCard(inv) } }
                    .buttonStyle(.lw(.outline, height: 44, fullWidth: false))
            }
        case .accepted:
            EmptyView()
        }
    }

    private func tapCard(_ inv: NWCMadeInvoice) async {
        nfc = .scanning
        do {
            let url = try await NFCReader.readURL(prompt: t("ios.nfc.prompt"))
            nfc = .charging
            try await BoltcardPay.payInvoice(cardURL: url, bolt11: inv.bolt11, amountSats: inv.amountSats)
            Haptics.success()
            withAnimation(.spring) { nfc = .accepted(Date()) }
        } catch is CancellationError {
            nfc = .idle
        } catch {
            Haptics.error()
            nfc = .failed(PayErrors.text(error, fallback: t("receive.nfc.failed")))
        }
    }

    // MARK: settlement

    /// Ask the wallet directly as well as listening for NIP-47 notifications — some wallets never send one.
    /// Faster cadence once a card tap is accepted (`TAP_SETTLE_POLL_MS`).
    private func poll(_ inv: NWCMadeInvoice) async {
        while !Task.isCancelled && !settled {
            try? await Task.sleep(for: .seconds(accepted ? 1 : 3))
            guard !Task.isCancelled, !settled, let client = app.wallet.client,
                  let tx = try? await client.lookupInvoice(paymentHash: inv.paymentHash) else { continue }
            if tx.state == .settled || tx.settledAt != nil { settle(tx) }
        }
    }

    private func settle(_ tx: NWCTransaction) {
        guard !settled, let inv = app.flows.invoice, tx.paymentHash == inv.paymentHash else { return }
        settled = true
        ReceiveSettlement.settledAt = tx.settledAt ?? Date()
        ReceiveSettlement.preimage = tx.preimage
        app.flows.receivedSats = inv.amountSats
        // Hold a card tap's success animation briefly (`BOLTCARD_SUCCESS_HOLD_MS`).
        var wait = 0.0
        if case .accepted(let at) = nfc { wait = max(0, 1.1 - Date().timeIntervalSince(at)) }
        Task {
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            app.path = [.receiveSummary]
        }
    }
}

/// `lib/client/boltcard-pay.ts`: charge the invoice on screen from a BoltCard's LNURL-withdraw link.
enum BoltcardPay {
    static func payInvoice(cardURL: String, bolt11: String, amountSats: Int) async throws {
        guard !bolt11.isEmpty, amountSats > 0 else { throw PayError(t("errors.boltcard.noInvoice")) }
        let resolved: LNURLResolved?
        do { resolved = try await LNURL.resolve(cardURL) } catch let e as LNURLError {
            if e.code == .noAmount || e.code == .belowOneSat { throw PayError(t("errors.boltcard.cannotPay")) }
            throw e
        } catch {
            throw PayError(t("errors.boltcard.unreachable"))
        }
        guard case .withdraw(let p)? = resolved else { throw PayError(t("errors.boltcard.notBoltcard")) }
        if amountSats > p.maxWithdrawableSats {
            throw PayError(t("errors.boltcard.aboveMax", ["limit": p.maxWithdrawableSats.formatted(), "amount": amountSats.formatted()]))
        }
        if amountSats < p.minWithdrawableSats {
            throw PayError(t("errors.boltcard.belowMin", ["limit": p.minWithdrawableSats.formatted(), "amount": amountSats.formatted()]))
        }
        do { try await LNURL.submitWithdraw(p, invoice: bolt11) } catch let e as LNURLError { throw e } catch {
            throw PayError(t("errors.boltcard.rejected"))
        }
    }
}

private struct NFCPulse: View {
    @State private var on = false
    @Environment(\.theme) private var theme
    var body: some View {
        ZStack {
            Circle().fill(theme.preset.primary.opacity(0.15)).scaleEffect(on ? 1.25 : 0.8).opacity(on ? 0 : 1)
            Circle().fill(theme.preset.primary.opacity(0.1)).padding(8)
            Icon("nfc", size: 24).foregroundStyle(theme.preset.primary)
        }
        .frame(width: 56, height: 56)
        .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: on)
        .onAppear { on = true }
    }
}

/// Celebration once the card's server accepts the invoice (`BoltcardAccepted`).
private struct BoltcardAccepted: View {
    let amountSats: Int
    @State private var popped = false
    @State private var slow = false
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().strokeBorder(theme.preset.primary, lineWidth: 2).scaleEffect(popped ? 1.6 : 1).opacity(popped ? 0 : 0.8)
                Circle().fill(Color.clear).lwGlass(in: Circle(), tint: .color(theme.preset.primary.opacity(0.75))).padding(8)
                    .shadow(color: theme.preset.primary.opacity(0.45), radius: 24, y: 8)
                Icon("check", size: 40).foregroundStyle(.white).scaleEffect(popped ? 1 : 0.3).opacity(popped ? 1 : 0)
            }
            .frame(width: 96, height: 96)
            .scaleEffect(popped ? 1 : 0.6)
            .padding(.bottom, 12)
            Text(t("receive.nfc.cardAccepted")).font(LW.font(20, .semibold))
            Text(t("common.sats", ["n": amountSats.formatted()])).font(LW.font(15)).monospacedDigit().foregroundStyle(LW.muted)
            Text(t(slow ? "receive.nfc.slowConfirm" : "receive.nfc.confirming")).font(LW.font(13)).foregroundStyle(LW.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background { PayConfetti() }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("receive.nfc.accepted")
        .onAppear { withAnimation(.spring(duration: 0.6, bounce: 0.45)) { popped = true } }
        .task {
            try? await Task.sleep(for: .seconds(20))
            slow = true
        }
    }
}

/// Falling confetti pieces (deterministic spray, like the web's seeded `Math.sin` jitter).
struct PayConfetti: View {
    var count = 28
    var colors: [Color] = [.green, LW.gold, Color(hex: "E53935"), Color(hex: "A78BFA"), .white]
    @State private var fall = false

    var body: some View {
        GeometryReader { geo in
            ForEach(0..<count, id: \.self) { i in
                let r = { (n: Double) in (sin(Double(i) * 9301 + n * 49297) + 1) / 2 }
                let size = 6 + r(6) * 6
                RoundedRectangle(cornerRadius: r(7) > 0.55 ? size / 2 : 2)
                    .fill(colors[i % colors.count])
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(fall ? 360 + r(5) * 720 : 0))
                    .position(x: geo.size.width * r(1) + (fall ? (r(4) - 0.5) * 160 : 0), y: fall ? geo.size.height + 20 : -10)
                    .opacity(fall ? 0 : 1)
                    .animation(.linear(duration: 1.6 + r(3) * 1.1).delay(r(2) * 0.45), value: fall)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { fall = true }
    }
}

// MARK: summary (receive/summary-step.tsx)

struct ReceiveSummaryScreen: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let inv = app.flows.invoice {
            let code = app.currencies.selected
            let note = inv.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let settledAt = ReceiveSettlement.settledAt
            let preimage = ReceiveSettlement.preimage.flatMap { $0.isEmpty || $0 == inv.paymentHash ? nil : $0 }
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        PaymentReceipt(
                            status: .settled,
                            title: t("receive.summary.title"),
                            amountSats: inv.amountSats,
                            details: (note.isEmpty ? [] : [(t("receive.summary.note"), note)])
                                + (settledAt.map { [(t("receive.summary.time"), PayReceiptText.time($0))] } ?? []),
                            proofs: [(t("receive.summary.paymentHash"), inv.paymentHash)] + (preimage.map { [(t("receive.summary.preimage"), $0)] } ?? [])
                        )
                    }
                    .padding(.horizontal, 20).padding(.top, 32).padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
                .lwSoftScrollEdges()
                PayReceiptActions(shareText: PayReceiptText.build(amount: "\(app.currencies.format(inv.amountSats, code)) \(app.currencies.unit(code))",
                                                            comment: note.isEmpty ? nil : note, date: settledAt,
                                                            paymentHash: inv.paymentHash, preimage: preimage)) {
                    app.popToRoot()
                    app.flows.resetReceive()
                }
            }
        }
    }
}
