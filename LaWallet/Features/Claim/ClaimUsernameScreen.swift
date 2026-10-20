import LaWalletKit
import SwiftUI

/// `/wallet/claim-username` — claim/claim-address-screen.tsx + claim/use-new-address-flow.ts.
/// username → (402: paid registration invoice, LUD-21 verify → claim with preimage) → success.
struct ClaimUsernameScreen: View {
    let fromActivation: Bool
    let bonus: Bool

    enum Step { case username, payment, success }
    enum PaymentStatus { case waiting, detected, expired }

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var step: Step = .username
    @State private var username = ""
    @State private var available: Bool?
    @State private var checking = false
    @State private var submitting = false
    @State private var invoice: RegistrationInvoice?
    @State private var mintError: String?
    @State private var status: PaymentStatus = .waiting
    @State private var payingWithWallet = false
    @State private var manualChecking = false
    @State private var claiming = false
    @State private var claimedAddress: String?
    @State private var pollID = UUID()
    @FocusState private var focused: Bool

    private var domain: String { app.settings?.domain ?? t("claim.yourDomain") }

    private var formatError: String? {
        if username.isEmpty { return nil }
        if username.count > 16 { return t("claim.errors.maxLength") }
        return username.wholeMatch(of: /[a-z0-9]+/) == nil ? t("claim.errors.charset") : nil
    }

    private var submitDisabled: Bool { submitting || checking || formatError != nil || username.isEmpty || available == false }

    var body: some View {
        VStack(spacing: 0) {
            if step != .success && !(fromActivation && step == .username) {
                ScreenHeader(title: t(step == .payment ? "claim.paymentTitle" : "claim.headerTitle"), close: step == .username, onBack: back)
            }
            switch step {
            case .username: usernameStep
            case .payment: paymentStep
            case .success: successStep
            }
        }
        .animation(.easeInOut(duration: 0.2), value: step)
        .task(id: username) { await checkAvailability() }
        .task(id: pollID) { await pollVerify() }
    }

    private func back() {
        if step == .payment { return backFromPayment() }
        // After card activation an address is required — no dismiss.
        if fromActivation { return }
        app.popToRoot()
    }

    // MARK: username

    private var usernameStep: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(t("claim.heading")).font(LW.font(30, .bold)).tracking(-0.6)
                    Text(t(fromActivation ? (bonus ? "claim.introActivateFree" : "claim.introActivate") : "claim.intro"))
                        .font(LW.font(15)).foregroundStyle(LW.muted).lineSpacing(3)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(t("claim.username")).font(LW.font(14, .semibold)).foregroundStyle(LW.muted).padding(.leading, 4)
                    usernameField
                    hint.frame(minHeight: 18).padding(.leading, 4).accessibilityIdentifier("claim.hint")
                }
            }
            .padding(.horizontal, 20).padding(.top, fromActivation ? 32 : 8)
            .frame(maxHeight: .infinity, alignment: .top)
            BottomBar {
                Button { Task { await submit() } } label: {
                    BusyLabel(t("claim.claimAddress"), busy: submitting, busyTitle: t("claim.claiming"))
                }
                .buttonStyle(.lw(.theme))
                .disabled(submitDisabled)
                .accessibilityIdentifier("claim.submit")
            }
        }
        .onAppear { focused = true }
    }

    /// Glass field with the community domain living inside it, after the caret.
    private var usernameField: some View {
        let shape = RoundedRectangle(cornerRadius: LW.Radius.control, style: .continuous)
        return HStack(spacing: 6) {
            TextField("", text: $username, prompt: Text(verbatim: "satoshi").foregroundStyle(LW.muted.opacity(0.8)))
                .font(LW.font(17, .medium))
                .foregroundStyle(LW.foreground)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($focused)
                .onSubmit { Task { await submit() } }
                .onChange(of: username) { _, next in
                    let lower = String(next.lowercased().prefix(16))
                    if lower != next { username = lower }
                }
                .accessibilityIdentifier("claim.username")
            Text("@\(domain)").font(LW.font(15, .medium)).foregroundStyle(LW.muted).lineLimit(1)
        }
        .padding(.horizontal, 16).frame(minHeight: 54)
        .lwGlass(in: shape)
        .overlay(shape.strokeBorder(Color.white.opacity(focused ? 0.22 : 0), lineWidth: 1))
    }

    /// Availability as a small colored dot + text (sun while checking, green free, coral taken/invalid).
    private var hint: some View {
        let state: (text: String, dot: Color?, color: Color) = if let formatError {
            (formatError, LW.coral, LW.destructiveText)
        } else if checking {
            (t("claim.checkingAvailability"), LW.sun, LW.muted)
        } else if available == false {
            (t("claim.taken"), LW.coral, LW.destructiveText)
        } else if available == true {
            (t("claim.available"), LW.incoming, LW.incoming)
        } else {
            (t("claim.usernameHint"), nil, LW.muted)
        }
        return HStack(spacing: 7) {
            if let dot = state.dot { Circle().fill(dot).frame(width: 7, height: 7) }
            Text(state.text).foregroundStyle(state.color)
        }
        .font(LW.font(13, .medium))
    }

    /// Debounced (300 ms) public availability check; a failed check means "unknown", not "taken".
    private func checkAvailability() async {
        available = nil
        guard step == .username, !username.isEmpty, formatError == nil else { checking = false; return }
        checking = true
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let result = try? await app.api.checkUsername(username)
        guard !Task.isCancelled else { return }
        available = result
        checking = false
    }

    private func submit() async {
        guard !submitDisabled else { return }
        submitting = true
        defer { submitting = false }
        do {
            _ = try await app.api.createAddress(username)
            await succeed("\(username)@\(domain)")
        } catch let e as APIError where e.status == 402 {
            await mintInvoice()
        } catch {
            fail(createErrorText(error))
        }
    }

    private func createErrorText(_ error: Error) -> String {
        guard let e = error as? APIError else { return PayErrors.text(error, fallback: t("claim.errors.createFailed")) }
        switch e.status {
        case 409: return t("claim.taken")
        case 403: return t("ios.pay.claimDisabled")
        default: return e.message.isEmpty ? t("claim.errors.createFailed") : e.message
        }
    }

    // MARK: payment

    private func mintInvoice() async {
        mintError = nil
        invoice = nil
        status = .waiting
        step = .payment
        do {
            let inv = try await app.api.registrationInvoice(username: username)
            if inv.free == true {
                // Paid mode reports free: try the direct create once, else the operator's config is incomplete.
                if (try? await app.api.createAddress(username)) != nil { return await succeed("\(username)@\(domain)") }
                mintError = t("claim.errors.paidIncomplete")
                return
            }
            guard inv.bolt11 != nil, inv.id != nil else {
                mintError = t("claim.errors.providerUnreachable")
                return
            }
            invoice = inv
            pollID = UUID()
        } catch {
            mintError = (error as? APIError)?.message ?? t("claim.errors.providerUnreachable")
        }
    }

    private var expiry: Date? {
        invoice?.expiresAt.flatMap { (try? Date($0, strategy: .iso8601)) ?? (try? Date($0, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))) }
            ?? invoice?.bolt11.flatMap { Bolt11.decode($0)?.expiresAt }
    }

    /// LUD-21 verify for the invoice's whole lifetime (a short cutoff dropped late settlements).
    private func pollVerify() async {
        guard step == .payment, let inv = invoice, let id = inv.id, let verify = inv.verify.flatMap(URL.init(string:)) else { return }
        let remaining = max(1, (expiry ?? Date().addingTimeInterval(600)).timeIntervalSinceNow)
        do {
            let r = try await LNURL.pollVerify(verify, timeout: .seconds(remaining))
            if let preimage = r.preimage { await claimWithPreimage(id: id, preimage: preimage) }
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled && step == .payment && status != .detected { status = .expired }
        }
    }

    private func claimWithPreimage(id: String, preimage: String) async {
        guard !claiming else { return }
        claiming = true
        defer { claiming = false }
        status = .detected
        do {
            let r = try await app.api.claimInvoice(id: id, preimage: preimage)
            if r.success { await succeed(r.lightningAddress ?? "\(username)@\(domain)") }
        } catch {
            let message = (error as? APIError)?.message ?? t("claim.errors.claimFailed")
            // A lost response to an earlier successful claim: the address is ours.
            if message.lowercased().contains("already been claimed") { return await succeed("\(username)@\(domain)") }
            fail(message)
            if message.lowercased().contains("taken") || (error as? APIError)?.status == 409 { backFromPayment() } else { status = .waiting }
        }
    }

    private func payWithWallet() async {
        guard let inv = invoice, let bolt11 = inv.bolt11, let id = inv.id else { return }
        payingWithWallet = true
        defer { payingWithWallet = false }
        guard let nwc = await app.freshNWC() else { return fail(t("send.preview.noWallet")) }
        do {
            let client: NWCClient
            if let c = app.wallet.client, app.wallet.uri == nwc { client = c } else { client = try NWCClient(uri: nwc) }
            let r = try await client.payInvoice(bolt11)
            if !r.preimage.isEmpty { await claimWithPreimage(id: id, preimage: r.preimage) }
        } catch {
            fail(PayErrors.text(error, fallback: t("claim.errors.walletPaymentFailed")))
        }
    }

    private func manualCheck() async {
        guard let inv = invoice, let id = inv.id, let verify = inv.verify.flatMap(URL.init(string:)) else {
            return fail(t("claim.errors.cantRecheck"))
        }
        manualChecking = true
        defer { manualChecking = false }
        do {
            let r = try await LNURL.verify(verify)
            if r.settled, let preimage = r.preimage { await claimWithPreimage(id: id, preimage: preimage) }
            else { app.show(.info, t("claim.errors.noPaymentYet")) }
        } catch {
            fail(t("claim.errors.verifierUnreachable"))
        }
    }

    private func backFromPayment() {
        step = .username
        invoice = nil
        mintError = nil
        status = .waiting
        manualChecking = false
        pollID = UUID()
    }

    @ViewBuilder private var paymentStep: some View {
        if let inv = invoice, let bolt11 = inv.bolt11 {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 6) {
                        Text(t("claim.payAmount", ["sats": (inv.amountSats ?? 0).formatted()])).font(LW.font(26, .bold)).tracking(-0.4)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("claim.payAmount")
                        (Text(t("claim.toClaim") + " ").foregroundStyle(LW.muted) + Text("\(username)@\(domain)").fontWeight(.semibold))
                            .font(LW.font(15)).multilineTextAlignment(.center)
                    }
                    if status == .expired {
                        VStack(spacing: 14) {
                            Icon("clock", size: 24).foregroundStyle(LW.muted).frame(width: 60, height: 60).lwGlass(in: Circle())
                            Text(t("claim.invoiceExpired")).font(LW.font(15)).foregroundStyle(LW.muted).multilineTextAlignment(.center)
                            Button { Task { await mintInvoice() } } label: {
                                Label { Text(t("claim.newInvoice")) } icon: { Icon("refresh-cw", size: 14) }
                            }
                            .buttonStyle(.lw(.theme, fullWidth: false))
                        }
                        .padding(.top, 16)
                    } else {
                        // QRDisplay-style: opaque white tile for scanners, set in a glass bezel.
                        QRCodeImage(text: bolt11)
                            .frame(width: 224, height: 224).padding(16)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .accessibilityIdentifier("claim.qr")
                            .padding(10)
                            .lwSurface(LW.Radius.sheet)
                        GlassGroup(spacing: 10) {
                            VStack(spacing: 10) {
                                if app.wallet.hasWallet {
                                    Button { Task { await payWithWallet() } } label: {
                                        BusyLabel(t("claim.payWithWallet"), busy: payingWithWallet, busyTitle: t("claim.confirmInWallet"), icon: "wallet")
                                    }
                                    .buttonStyle(.lw(.theme))
                                    .disabled(payingWithWallet || status == .detected)
                                    .accessibilityIdentifier("claim.payWithWallet")
                                }
                                CopyButton(value: bolt11) {
                                    CopyLabel(copied: $0, title: t("claim.copyInvoice"), copiedTitle: t("claim.copied"))
                                }
                                .buttonStyle(.lw(.outline))
                                .accessibilityIdentifier("claim.copy")
                            }
                        }
                        VStack(spacing: 6) {
                            switch status {
                            case .waiting:
                                StatusPill { PulseDot(); Text(t("claim.waitingPayment")) }
                                    .foregroundStyle(LW.foreground.opacity(0.9))
                                Button { Task { await manualCheck() } } label: {
                                    BusyLabel(t("claim.checkNow"), busy: manualChecking, busyTitle: t("claim.checking"), icon: "refresh-cw")
                                }
                                .buttonStyle(.lw(.ghost, height: 40, fullWidth: false))
                                .disabled(manualChecking)
                                .accessibilityIdentifier("claim.checkNow")
                            case .detected:
                                StatusPill(tint: LW.incoming) { Icon("check", size: 14); Text(t("claim.detected")).fontWeight(.semibold) }
                                    .foregroundStyle(LW.incoming)
                            case .expired:
                                EmptyView()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .lwSoftScrollEdges()
        } else {
            VStack(spacing: 16) {
                if let mintError {
                    Icon("alert-triangle", size: 24).foregroundStyle(LW.destructiveText).frame(width: 60, height: 60).lwGlass(in: Circle())
                    VStack(spacing: 6) {
                        Text(t("claim.paymentFailedTitle")).font(LW.font(22, .semibold))
                        Text(t("claim.paymentFailedBody", ["address": "\(username)@\(domain)"])).font(LW.font(15)).foregroundStyle(LW.muted)
                    }
                    .multilineTextAlignment(.center)
                    Text(mintError).font(LW.font(14)).foregroundStyle(LW.muted).multilineTextAlignment(.center)
                        .accessibilityIdentifier("claim.mintError")
                    Button { Task { await mintInvoice() } } label: {
                        Label { Text(t("claim.tryAgain")) } icon: { Icon("refresh-cw", size: 14) }
                    }
                    .buttonStyle(.lw(.theme))
                    .padding(.top, 4)
                } else {
                    HStack(spacing: 10) { ProgressView().controlSize(.small).tint(LW.muted); Text(t("claim.generatingInvoice")) }
                        .font(LW.font(15)).foregroundStyle(LW.muted)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: success

    private func succeed(_ address: String) async {
        invoice = nil
        claimedAddress = address
        step = .success
        Haptics.success()
        await app.refreshMe()
    }

    private var successStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 28) {
                VStack(spacing: 10) {
                    Text(t("claim.claimedTitle")).font(LW.font(30, .bold)).tracking(-0.6).multilineTextAlignment(.center)
                    Text(t("claim.claimedBody")).font(LW.font(15)).foregroundStyle(LW.muted).multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                if let claimedAddress { SuccessHero(address: claimedAddress) }
            }
            .padding(.horizontal, 20)
            .frame(maxHeight: .infinity, alignment: .top)
            BottomBar {
                Button(t("claim.goToWallet")) { app.popToRoot() }
                    .buttonStyle(.lw(.theme))
                    .accessibilityIdentifier("claim.done")
            }
        }
    }

    private func fail(_ message: String) {
        app.show(.error, message)
        Haptics.error()
    }
}

/// `SuccessHeroCard`: glow + lightning frame behind the address pill, landing last.
private struct SuccessHero: View {
    let address: String
    @State private var shown = false
    @Environment(\.theme) private var theme

    var body: some View {
        let parts = address.split(separator: "@", maxSplits: 1).map(String.init)
        ZStack {
            Ellipse().fill(theme.preset.primary.opacity(0.35)).frame(width: 240, height: 120).blur(radius: 40).offset(y: -60)
                .opacity(shown ? 0.8 : 0)
            Icon("zap", size: 140).foregroundStyle(theme.preset.primary.opacity(0.12)).scaleEffect(shown ? 1 : 0.9).opacity(shown ? 1 : 0)
            HStack(spacing: 0) {
                Text(parts.first ?? address).foregroundStyle(LW.muted)
                if parts.count > 1 { Text("@" + parts[1]).foregroundStyle(LW.foreground) }
            }
            .font(LW.font(19, .semibold)).lineLimit(1).minimumScaleFactor(0.6)
            .padding(.horizontal, 18).padding(.vertical, 10)
            // A chip inside the glass card, not glass of its own.
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 14)
            .padding(.horizontal, 16)
            .offset(y: shown ? 0 : 12).opacity(shown ? 1 : 0)
            .accessibilityIdentifier("claim.address")
        }
        .frame(maxWidth: .infinity).aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: LW.Radius.surface, style: .continuous))
        .lwSurface()
        .onAppear { withAnimation(.easeOut(duration: 0.6).delay(0.15)) { shown = true } }
    }
}
