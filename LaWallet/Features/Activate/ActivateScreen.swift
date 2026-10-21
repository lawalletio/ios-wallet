import LaWalletKit
import SwiftUI

/// Arms the claim to fire as soon as the signed-in activate screen is ready after an inline signup
/// (web `autoActivate`). The signed-out tree is torn down on login, so this outlives it.
@MainActor enum ActivationAutoClaim { static var tokenId: String? }

/// `/wallet/activate/[id]` — components/activate/activate-client.tsx. Used signed out (inline auth) and signed in (claim).
/// A RECOVER token (`preview.purpose`, never the URL's `?tag`) moves the card's whole account instead of linking the card.
struct ActivateScreen: View {
    let tokenId: String
    @Environment(AppModel.self) private var app
    @Environment(\.authPath) private var authPath
    @Environment(\.theme) private var theme

    private enum PreviewError { case invalidLink, loadFailed }
    private enum ClaimState { case idle, claiming, success, error }
    private enum Phase { case loading, error, unavailable, unsupported, ready }

    @State private var preview: ActivationPreview?
    @State private var previewError: PreviewError?
    @State private var claimState = ClaimState.idle
    @State private var claimError: String?
    @State private var claim: ActivationClaim?
    @State private var mergeCheck: RecoveryCheck?
    @State private var recovered: (account: RecoveredAccount, needsAddress: Bool)?

    private var isRecover: Bool { preview?.isRecover == true }

    private var phase: Phase {
        if previewError != nil { return .error }
        guard let preview else { return .loading }
        if preview.status != "PENDING" { return .unavailable }
        if preview.qrKind != "ONE_TIME" { return .unsupported }
        return .ready
    }

    private var design: CardDesign? { claim?.card.design ?? preview?.card.design }
    private var title: String? { (claim?.card.title ?? preview?.card.title).flatMap { $0.isEmpty ? nil : $0 } }
    private var imageURL: URL? { app.onbImageURL(design?.imageUrl) }

    var body: some View {
        // The route's ambient light (brand glow included) sits behind; the card floats over it.
        VStack(spacing: 0) {
            if claimState != .success { ScreenHeader(title: nil, close: true) }
            content.padding(.horizontal, 20).frame(maxWidth: 480, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await loadPreview() }
        .onChange(of: phase, initial: true) { _, p in sync(p) }
        .sheet(isPresented: Binding(get: { mergeCheck != nil }, set: { if !$0 { mergeCheck = nil } })) {
            if let check = mergeCheck {
                RecoverMergeSheet(check: check, onConfirm: {
                    mergeCheck = nil
                    runRecover(confirmMerge: true)
                }, onCancel: { mergeCheck = nil })
                .presentationDetents([.large])
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            VStack(spacing: 24) {
                Color.clear.frame(width: 300, height: 189).lwSurface(16).shimmer()
                ProgressView().tint(LW.muted)
            }
            .frame(maxHeight: .infinity)
        case .error:
            ActivationStatusView(icon: "alert-circle", tint: LW.destructiveText, heading: t("activate.error.title"),
                                 message: t(previewError == .invalidLink ? "activate.error.invalidLink" : "activate.error.loadFailed")) {
                Button(t("activate.error.tryAgain")) { Task { await loadPreview() } }
                    .buttonStyle(.lw(.secondary, height: 46, fullWidth: false))
            }
        case .unavailable:
            unavailable
        case .unsupported:
            ActivationStatusView(icon: "shield-x", tint: LW.muted, heading: t("activate.unsupported.title"), message: t("activate.unsupported.body")) {
                EmptyView()
            }
        case .ready:
            if claimState == .success, let recovered {
                RecoveredView(recovery: recovered.account, claimAddress: recovered.needsAddress, onContinue: finish)
            } else if claimState == .success, let claim {
                ActivationSuccessView(imageURL: imageURL, title: title, claimAddress: claim.needsLightningAddress,
                                      bonusSats: claim.bonuses.sats.granted ? claim.bonuses.sats.amountSats.flatMap { $0 > 0 ? $0 : nil } : nil,
                                      onContinue: finish)
            } else {
                ready
            }
        }
    }

    private var ready: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 6) {
                        Text(t(isRecover ? "activate.recover.eyebrow" : "activate.eyebrow")).font(LW.font(15, .semibold)).foregroundStyle(LW.muted)
                        if let title {
                            Text(title).font(LW.font(28, .bold)).tracking(-0.6).foregroundStyle(LW.foreground).multilineTextAlignment(.center)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                    .padding(.top, 8).padding(.bottom, 8)
                    ActivationCard(imageURL: imageURL, title: title)
                        .frame(maxHeight: .infinity)
                        .frame(minHeight: 280)
                    actionBar.padding(.top, 16).padding(.bottom, 12)
                }
                .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .lwSoftScrollEdges()
        }
    }

    @ViewBuilder private var actionBar: some View {
        if claimState == .claiming {
            HStack(spacing: 10) {
                ProgressView().tint(theme.preset.primary)
                Text(t(isRecover ? "activate.recover.recovering" : "activate.activating")).font(LW.font(15, .medium)).foregroundStyle(LW.foreground.opacity(0.85))
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .lwGlass(in: Capsule())
        } else if app.isAuthenticated {
            VStack(spacing: 12) {
                if claimState == .error {
                    let message = claimError ?? failedCopy
                    HStack(alignment: .top, spacing: 12) {
                        Icon("alert-circle", size: 17).foregroundStyle(LW.coral)
                            .frame(width: 34, height: 34).background(LW.coral.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text(message).font(LW.font(14, .medium)).foregroundStyle(LW.destructiveText).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true).padding(.top, 7)
                            .accessibilityIdentifier("activate.error")
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .lwGlass(in: RoundedRectangle(cornerRadius: LW.Radius.surface - 4, style: .continuous), tint: .color(LW.coral.opacity(0.10)))
                }
                GlassGroup(spacing: 12) {
                    VStack(spacing: 12) {
                        Button(action: runClaim) {
                            HStack(spacing: 8) {
                                Icon(isRecover ? "life-buoy" : "zap", size: 20)
                                Text(t(isRecover ? "activate.recover.action" : "activate.activate")).font(LW.font(16, .semibold))
                            }
                        }
                        .buttonStyle(.lw(.theme, height: 56))
                        .accessibilityIdentifier("activate.claim")
                        if claimState == .error, (claimError ?? failedCopy).range(of: "claim", options: .caseInsensitive) != nil {
                            Button(t("activate.openWallet"), action: openWallet).buttonStyle(.lw(.secondary))
                        }
                    }
                }
            }
        } else {
            InlineActivationAuth(tokenId: tokenId, recover: isRecover)
        }
    }

    private var failedCopy: String { t(isRecover ? "activate.recover.failed" : "activate.failed") }

    private var unavailable: some View {
        let status = preview?.status ?? ""
        let (icon, tint, key): (String, Color, String) = switch status {
        case "CLAIMED": ("check-circle-2", theme.preset.primary, "claimed")
        case "EXPIRED": ("clock", LW.gold, "expired")
        default: ("shield-x", LW.destructiveText, "revoked")
        }
        return ActivationStatusView(icon: icon, tint: tint, heading: t("activate.\(key).title"), message: t("activate.\(key).body")) {
            if status == "CLAIMED" {
                Button(t("activate.openWallet"), action: openWallet).buttonStyle(.lw(.secondary, height: 46, fullWidth: false))
            }
        }
    }

    // MARK: actions

    private func loadPreview() async {
        previewError = nil
        do {
            preview = try await app.api.activationPreview(tokenId)
        } catch {
            previewError = (error as? APIError)?.status == 404 ? .invalidLink : .loadFailed
        }
    }

    /// `rememberPendingActivation` while claimable and signed out; forget it once it can't be claimed. Fires an armed auto-claim.
    private func sync(_ p: Phase) {
        switch p {
        case .ready where claimState != .success:
            if !app.isAuthenticated { app.pendingActivation = (tokenId, Date()) }
            if app.isAuthenticated, claimState == .idle, ActivationAutoClaim.tokenId == tokenId {
                ActivationAutoClaim.tokenId = nil
                runClaim()
            }
        case .unavailable, .unsupported:
            app.pendingActivation = nil
            ActivationAutoClaim.tokenId = nil
        default: break
        }
    }

    private func runClaim() {
        if isRecover { return runRecover() }
        claimState = .claiming
        claimError = nil
        Task {
            do {
                let result = try await app.api.claimActivation(tokenId)
                app.pendingActivation = nil
                claim = result
                // Home's `ActivationBonusNote` explains the bump in balance for the next 24 h.
                if result.bonuses.sats.granted, let sats = result.bonuses.sats.amountSats, sats > 0 {
                    UserDefaults.standard.set(Date(), forKey: "lawallet-activation-bonus-at")
                    UserDefaults.standard.set(sats, forKey: "lawallet-activation-bonus-sats")
                }
                withAnimation(.easeOut(duration: 0.3)) { claimState = .success }
                Haptics.success()
                Task {
                    await app.refreshMe()
                    await app.wallet.refreshBalance()
                }
            } catch {
                let message = (error as? APIError)?.message ?? error.localizedDescription
                claimError = message.isEmpty ? nil : message
                claimState = .error
                Haptics.error()
            }
        }
    }

    /// RECOVER: pre-flight first so an account that already has data is asked before anything merges. No activation
    /// bonus or wallet binding here — the cards keep their wallets. The card's own owner just lands in the wallet.
    private func runRecover(confirmMerge: Bool = false) {
        claimState = .claiming
        claimError = nil
        Task {
            do {
                if !confirmMerge {
                    let check = try await app.api.recoveryCheck(tokenId)
                    if check.mergeRequired { return askMerge(check) }
                }
                let result = try await app.api.claimRecovery(tokenId, confirmMerge: confirmMerge)
                app.pendingActivation = nil
                // First `/me` only now for a fresh key, so the recovered wallets don't get a courtesy LNCurl one beside them.
                Task {
                    await app.refreshMe()
                    await app.wallet.refreshBalance()
                }
                guard let account = result.recovered else { return app.popToRoot() }
                recovered = (account, result.needsLightningAddress ?? false)
                withAnimation(.easeOut(duration: 0.3)) { claimState = .success }
                Haptics.success()
            } catch {
                // A merge became necessary between the pre-flight and the claim.
                if (error as? APIError)?.reason == "RECOVERY_MERGE_REQUIRED", let check = try? await app.api.recoveryCheck(tokenId) {
                    return askMerge(check)
                }
                let message = (error as? APIError)?.message ?? error.localizedDescription
                claimError = message.isEmpty ? nil : message
                claimState = .error
                Haptics.error()
            }
        }
    }

    private func askMerge(_ check: RecoveryCheck) {
        claimState = .idle
        mergeCheck = check
    }

    private func finish() {
        let needsAddress = recovered?.needsAddress ?? claim?.needsLightningAddress ?? false
        app.popToRoot()
        if needsAddress {
            app.navigate(.claimUsername(fromActivation: true, bonus: claim?.bonuses.freeLightningAddress ?? false))
        }
    }

    private func openWallet() {
        if app.isAuthenticated { app.popToRoot() } else { authPath.wrappedValue = NavigationPath() }
    }
}

// MARK: inline auth (components/activate/inline-auth.tsx)

/// Signed-out panel: new passkey, new Nostr key, or "I already have an account" (the card stays pending, so login returns here).
private struct InlineActivationAuth: View {
    let tokenId: String
    let recover: Bool
    @Environment(AppModel.self) private var app
    @Environment(\.authPath) private var authPath
    @State private var creating = false
    @State private var keys = NostrKeys.generate()
    @State private var confirmed = false
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        if creating { createKey } else { choose }
    }

    private var choose: some View {
        VStack(spacing: 14) {
            Text(t(PasskeyService.isSupported(app) ? (recover ? "activate.recover.intro" : "activate.inlineAuth.intro")
                   : (recover ? "activate.recover.introNoPasskey" : "activate.inlineAuth.introNoPasskey")))
                .font(LW.font(15)).foregroundStyle(LW.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 8)
            GlassGroup(spacing: 12) {
                VStack(spacing: 12) {
                    OnbPasskeyButton(mode: .register, label: t("activate.inlineAuth.passkey"), surfaceCancel: true,
                                     duplicateMessage: t("activate.inlineAuth.duplicate"), id: "activate.passkey",
                                     onStart: arm, onFailure: disarm)
                    Button { creating = true } label: { OnbIconText(icon: "key-round", text: t("activate.inlineAuth.nostr")) }
                        .buttonStyle(.lw(.secondary))
                        .accessibilityIdentifier("activate.nostr")
                }
            }
            Button(t("activate.inlineAuth.haveAccount")) { authPath.wrappedValue.append(AuthRoute.login) }
                .buttonStyle(.lw(.ghost, height: 44))
                .accessibilityIdentifier("activate.haveAccount")
        }
    }

    private var createKey: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button { creating = false } label: {
                HStack(spacing: 4) { Icon("chevron-left", size: 16); Text(t("common.back")).font(LW.font(14, .medium)) }
                    .foregroundStyle(LW.foreground)
                    .padding(.leading, 8).padding(.trailing, 12).frame(height: 36).contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .lwGlass(in: Capsule(), interactive: true)
            .disabled(loading)
            VStack(alignment: .leading, spacing: 6) {
                Text(t("activate.inlineAuth.newKeyTitle")).font(LW.font(22, .bold)).tracking(-0.4).foregroundStyle(LW.foreground)
                Text(t("activate.inlineAuth.newKeyBody")).font(LW.font(14)).foregroundStyle(LW.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            OnbSecretKeyReveal(nsec: keys.nsec, disabled: loading, confirmed: $confirmed,
                               confirmLabel: t("activate.inlineAuth.confirmLabel"), idPrefix: "activate")
            OnbError(message: error)
            Button(action: createAndActivate) {
                OnbIconText(icon: nil, text: loading ? t(recover ? "activate.recover.working" : "activate.inlineAuth.activating")
                            : t(recover ? "activate.recover.createAndRecover" : "activate.inlineAuth.createAndActivate"), busy: loading)
            }
            .buttonStyle(.lw(.primary))
            .disabled(!confirmed || loading)
            .accessibilityIdentifier("activate.createAndActivate")
        }
    }

    private func arm() {
        app.pendingActivation = (tokenId, Date())
        ActivationAutoClaim.tokenId = tokenId
    }

    private func disarm() { ActivationAutoClaim.tokenId = nil }

    private func createAndActivate() {
        error = nil
        loading = true
        arm()
        Task {
            // RECOVER: no `/me` before the claim — it would mint a courtesy wallet the recovered account doesn't want.
            do { try await app.login(keys: keys, method: .nsec, loadMe: !recover) } catch {
                disarm()
                let message = error.localizedDescription.isEmpty ? t("activate.inlineAuth.connectFailed") : error.localizedDescription
                self.error = message
                app.show(.error, message)
                loading = false
            }
        }
    }
}

// MARK: status

private struct ActivationStatusView<Action: View>: View {
    let icon: String
    let tint: Color
    let heading: String
    let message: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 14) {
                Icon(icon, size: 28).foregroundStyle(tint)
                    .frame(width: 64, height: 64).background(tint.opacity(0.16), in: Circle())
                    .padding(.bottom, 4)
                Text(heading).font(LW.font(24, .bold)).tracking(-0.4).foregroundStyle(LW.foreground)
                Text(message).font(LW.font(15)).foregroundStyle(LW.muted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24).padding(.vertical, 30)
            .frame(maxWidth: 360)
            .lwSurface(LW.Radius.sheet)
            action()
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("activate.status")
    }
}
