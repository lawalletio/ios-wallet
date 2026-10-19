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
    @State private var copied = false
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
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(t("claim.heading")).font(LW.font(24, .semibold))
                Text(t(fromActivation ? (bonus ? "claim.introActivateFree" : "claim.introActivate") : "claim.intro"))
                    .font(LW.font(14)).foregroundStyle(LW.muted).lineSpacing(3)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(t("claim.username")).font(LW.font(14, .medium))
                HStack(spacing: 0) {
                    TextField("satoshi", text: $username)
                        .font(LW.font(16))
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
                        .padding(.horizontal, 14)
                        .accessibilityIdentifier("claim.username")
                    Text("@\(domain)").font(LW.font(14)).foregroundStyle(LW.muted).lineLimit(1).padding(.trailing, 12)
                }
                .frame(height: 48)
                .background(LW.background)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(focused ? LW.ring : LW.border))
                hint.font(LW.font(12)).frame(minHeight: 16).accessibilityIdentifier("claim.hint")
            }
            Spacer(minLength: 0)
            Button { Task { await submit() } } label: {
                PayButtonLabel(busy: submitting, title: t("claim.claimAddress"), busyTitle: t("claim.claiming"))
            }
            .buttonStyle(.lw(.theme))
            .disabled(submitDisabled)
            .accessibilityIdentifier("claim.submit")
        }
        .padding(.horizontal, 24).padding(.top, fromActivation ? 32 : 8).padding(.bottom, 24)
        .onAppear { focused = true }
    }

    @ViewBuilder private var hint: some View {
        if let formatError {
            Text(formatError).foregroundStyle(LW.destructiveText)
        } else if checking {
            Text(t("claim.checkingAvailability")).foregroundStyle(LW.muted)
        } else if available == false {
            Text(t("claim.taken")).foregroundStyle(LW.destructiveText)
        } else if available == true {
            Text(t("claim.available")).foregroundStyle(LW.incoming)
        } else {
            Text(t("claim.usernameHint")).foregroundStyle(LW.muted)
        }
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
                VStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text(t("claim.payAmount", ["sats": (inv.amountSats ?? 0).formatted()])).font(LW.font(20, .semibold))
                            .accessibilityIdentifier("claim.payAmount")
                        (Text(t("claim.toClaim") + " ").foregroundStyle(LW.muted) + Text("\(username)@\(domain)").fontWeight(.medium))
                            .font(LW.font(14))
                    }
                    if status == .expired {
                        VStack(spacing: 12) {
                            Text(t("claim.invoiceExpired")).font(LW.font(14)).foregroundStyle(LW.muted).multilineTextAlignment(.center)
                            Button { Task { await mintInvoice() } } label: {
                                Label { Text(t("claim.newInvoice")) } icon: { Icon("refresh-cw", size: 14) }
                            }
                            .buttonStyle(.lw(.theme, fullWidth: false))
                        }
                    } else {
                        QRCodeImage(text: bolt11)
                            .frame(width: 224, height: 224).padding(16).background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("claim.qr")
                        VStack(spacing: 8) {
                            if app.wallet.hasWallet {
                                Button { Task { await payWithWallet() } } label: {
                                    PayButtonLabel(busy: payingWithWallet, title: t("claim.payWithWallet"), busyTitle: t("claim.confirmInWallet"), icon: "wallet")
                                }
                                .buttonStyle(.lw(.theme))
                                .disabled(payingWithWallet || status == .detected)
                                .accessibilityIdentifier("claim.payWithWallet")
                            }
                            Button {
                                UIPasteboard.general.string = bolt11
                                copied = true
                                Task { try? await Task.sleep(for: .seconds(2)); copied = false }
                            } label: {
                                Label { Text(t(copied ? "claim.copied" : "claim.copyInvoice")) } icon: { Icon("copy", size: 16) }
                            }
                            .buttonStyle(.lw(.outline))
                            .accessibilityIdentifier("claim.copy")
                        }
                        VStack(spacing: 8) {
                            switch status {
                            case .waiting:
                                HStack(spacing: 8) { ProgressView().controlSize(.mini).tint(LW.muted); Text(t("claim.waitingPayment")) }
                                    .font(LW.font(12)).foregroundStyle(LW.muted)
                                Button { Task { await manualCheck() } } label: {
                                    PayButtonLabel(busy: manualChecking, title: t("claim.checkNow"), busyTitle: t("claim.checking"), icon: "refresh-cw")
                                }
                                .buttonStyle(.lw(.ghost, height: 36, fullWidth: false))
                                .disabled(manualChecking)
                                .accessibilityIdentifier("claim.checkNow")
                            case .detected:
                                HStack(spacing: 6) { Icon("check", size: 14); Text(t("claim.detected")) }
                                    .font(LW.font(12)).foregroundStyle(LW.incoming)
                            case .expired:
                                EmptyView()
                            }
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 24)
            }
        } else {
            VStack(spacing: 16) {
                if let mintError {
                    VStack(spacing: 4) {
                        Text(t("claim.paymentFailedTitle")).font(LW.font(20, .semibold))
                        Text(t("claim.paymentFailedBody", ["address": "\(username)@\(domain)"])).font(LW.font(14)).foregroundStyle(LW.muted)
                    }
                    .multilineTextAlignment(.center)
                    Text(mintError).font(LW.font(14)).foregroundStyle(LW.muted).multilineTextAlignment(.center)
                        .accessibilityIdentifier("claim.mintError")
                    Button { Task { await mintInvoice() } } label: {
                        Label { Text(t("claim.tryAgain")) } icon: { Icon("refresh-cw", size: 14) }
                    }
                    .buttonStyle(.lw(.theme))
                } else {
                    HStack(spacing: 8) { ProgressView().controlSize(.small).tint(LW.muted); Text(t("claim.generatingInvoice")) }
                        .font(LW.font(14)).foregroundStyle(LW.muted)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
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
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text(t("claim.claimedTitle")).font(LW.font(24, .semibold))
                Text(t("claim.claimedBody")).font(LW.font(14)).foregroundStyle(LW.muted).multilineTextAlignment(.center)
            }
            .padding(.top, 40)
            if let claimedAddress { SuccessHero(address: claimedAddress) }
            Spacer(minLength: 0)
            Button(t("claim.goToWallet")) { app.popToRoot() }
                .buttonStyle(.lw(.theme))
                .accessibilityIdentifier("claim.done")
        }
        .padding(.horizontal, 24).padding(.bottom, 24)
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
            .font(LW.font(18, .medium)).lineLimit(1).minimumScaleFactor(0.6)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(LW.background).clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(LW.border))
            .shadow(color: .black.opacity(0.4), radius: 25, y: 25)
            .offset(y: shown ? 0 : 12).opacity(shown ? 1 : 0)
            .accessibilityIdentifier("claim.address")
        }
        .frame(maxWidth: .infinity).aspectRatio(16 / 9, contentMode: .fit)
        .background(LW.card).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(LW.border))
        .onAppear { withAnimation(.easeOut(duration: 0.6).delay(0.15)) { shown = true } }
    }
}
