import LaWalletKit
import SwiftUI

/// Arms the claim to fire as soon as the signed-in activate screen is ready after an inline signup
/// (web `autoActivate`). The signed-out tree is torn down on login, so this outlives it.
@MainActor enum ActivationAutoClaim { static var tokenId: String? }

/// `/wallet/activate/[id]` — components/activate/activate-client.tsx. Used signed out (inline auth) and signed in (claim).
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
        ZStack {
            AmbientBackdrop(color: theme.preset.primary)
            VStack(spacing: 0) {
                if claimState != .success { ScreenHeader(title: nil, close: true) }
                content.padding(.horizontal, 20).frame(maxWidth: 480, maxHeight: .infinity)
            }
        }
        .task { await loadPreview() }
        .onChange(of: phase, initial: true) { _, p in sync(p) }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            VStack(spacing: 24) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LW.card)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(LW.border))
                    .frame(width: 300, height: 189).shimmer()
                ProgressView().tint(LW.muted)
            }
            .frame(maxHeight: .infinity)
        case .error:
            ActivationStatusView(icon: "alert-circle", tint: LW.destructiveText, heading: t("activate.error.title"),
                                 message: t(previewError == .invalidLink ? "activate.error.invalidLink" : "activate.error.loadFailed")) {
                Button(t("activate.error.tryAgain")) { Task { await loadPreview() } }
                    .buttonStyle(.lw(.secondary, height: 40, fullWidth: false))
            }
        case .unavailable:
            unavailable
        case .unsupported:
            ActivationStatusView(icon: "shield-x", tint: LW.muted, heading: t("activate.unsupported.title"), message: t("activate.unsupported.body")) {
                EmptyView()
            }
        case .ready:
            if claimState == .success, let claim {
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
                    VStack(spacing: 4) {
                        Text(t("activate.eyebrow").uppercased()).font(LW.font(12, .medium)).tracking(2.4).foregroundStyle(LW.muted)
                        if let title { Text(title).font(LW.font(20, .semibold)).foregroundStyle(LW.foreground).multilineTextAlignment(.center) }
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
        }
    }

    @ViewBuilder private var actionBar: some View {
        if claimState == .claiming {
            VStack(spacing: 8) {
                ProgressView().tint(LW.muted)
                Text(t("activate.activating")).font(LW.font(14)).foregroundStyle(LW.muted)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
        } else if app.isAuthenticated {
            VStack(spacing: 12) {
                Button(action: runClaim) {
                    HStack(spacing: 8) { Icon("zap", size: 20); Text(t("activate.activate")).font(LW.font(16, .semibold)) }
                }
                .buttonStyle(.lw(.theme, height: 56))
                .accessibilityIdentifier("activate.claim")
                if claimState == .error {
                    let message = claimError ?? t("activate.failed")
                    VStack(spacing: 8) {
                        Text(message).font(LW.font(14)).foregroundStyle(LW.destructiveText).multilineTextAlignment(.center)
                            .accessibilityIdentifier("activate.error")
                        if message.range(of: "claim", options: .caseInsensitive) != nil {
                            Button(t("activate.openWallet"), action: openWallet).buttonStyle(.lw(.secondary))
                        }
                    }
                }
            }
        } else {
            InlineActivationAuth(tokenId: tokenId)
        }
    }

    private var unavailable: some View {
        let status = preview?.status ?? ""
        let (icon, tint, key): (String, Color, String) = switch status {
        case "CLAIMED": ("check-circle-2", theme.preset.primary, "claimed")
        case "EXPIRED": ("clock", LW.gold, "expired")
        default: ("shield-x", LW.destructiveText, "revoked")
        }
        return ActivationStatusView(icon: icon, tint: tint, heading: t("activate.\(key).title"), message: t("activate.\(key).body")) {
            if status == "CLAIMED" {
                Button(t("activate.openWallet"), action: openWallet).buttonStyle(.lw(.secondary, height: 40, fullWidth: false))
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
        claimState = .claiming
        claimError = nil
        Task {
            do {
                let result = try await app.api.claimActivation(tokenId)
                app.pendingActivation = nil
                claim = result
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

    private func finish() {
        guard let claim else { return }
        app.popToRoot()
        if claim.needsLightningAddress {
            app.navigate(.claimUsername(fromActivation: true, bonus: claim.bonuses.freeLightningAddress))
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
        VStack(spacing: 12) {
            Text(t(PasskeyService.isSupported ? "activate.inlineAuth.intro" : "activate.inlineAuth.introNoPasskey"))
                .font(LW.font(14)).foregroundStyle(LW.muted).multilineTextAlignment(.center)
            OnbPasskeyButton(mode: .register, label: t("activate.inlineAuth.passkey"), surfaceCancel: true,
                             duplicateMessage: t("activate.inlineAuth.duplicate"), id: "activate.passkey",
                             onStart: arm, onFailure: disarm)
            Button { creating = true } label: { OnbIconText(icon: "key-round", text: t("activate.inlineAuth.nostr")) }
                .buttonStyle(.lw(.secondary))
                .accessibilityIdentifier("activate.nostr")
            Button(t("activate.inlineAuth.haveAccount")) { authPath.wrappedValue.append(AuthRoute.login) }
                .buttonStyle(.lw(.ghost, height: 40))
                .accessibilityIdentifier("activate.haveAccount")
        }
    }

    private var createKey: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { creating = false } label: {
                HStack(spacing: 4) { Icon("arrow-left", size: 14); Text(t("common.back")) }.font(LW.font(12)).foregroundStyle(LW.muted)
            }
            .disabled(loading)
            VStack(alignment: .leading, spacing: 4) {
                Text(t("activate.inlineAuth.newKeyTitle")).font(LW.font(16, .semibold)).foregroundStyle(LW.foreground)
                Text(t("activate.inlineAuth.newKeyBody")).font(LW.font(12)).foregroundStyle(LW.muted)
            }
            OnbSecretKeyReveal(nsec: keys.nsec, disabled: loading, confirmed: $confirmed,
                               confirmLabel: t("activate.inlineAuth.confirmLabel"), idPrefix: "activate")
            OnbError(message: error)
            Button(action: createAndActivate) {
                OnbIconText(icon: nil, text: loading ? t("activate.inlineAuth.activating") : t("activate.inlineAuth.createAndActivate"), busy: loading)
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
            do { try await app.login(keys: keys, method: .nsec) } catch {
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
        VStack(spacing: 12) {
            Icon(icon, size: 28).foregroundStyle(tint).frame(width: 56, height: 56).background(LW.card).clipShape(Circle())
            Text(heading).font(LW.font(20, .semibold)).foregroundStyle(LW.foreground)
            Text(message).font(LW.font(14)).foregroundStyle(LW.muted).frame(maxWidth: 320)
            action().padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("activate.status")
    }
}

/// Two soft themed blobs behind the activate flow (follows the community's brand color).
private struct AmbientBackdrop: View {
    let color: Color
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [color.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: 144))
                .frame(width: 288, height: 288).blur(radius: 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).offset(x: -96, y: -96)
            Circle().fill(RadialGradient(colors: [color.opacity(0.12), .clear], center: .center, startRadius: 0, endRadius: 144))
                .frame(width: 288, height: 288).blur(radius: 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).offset(x: 64, y: 96)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
