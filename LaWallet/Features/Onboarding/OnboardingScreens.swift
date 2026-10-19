import LaWalletKit
import SwiftUI

/// `/wallet/landing` — onboarding/landing-hero.tsx.
struct LandingScreen: View {
    @Binding var path: NavigationPath
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 32) {
                OnbIsotype()
                    .padding(24)
                    .frame(width: 160, height: 160)
                    .background(LW.card)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(LW.border))
                    .shadow(color: .black.opacity(0.5), radius: 25, y: 12)
                OnbHeading(title: app.onbCommunityName, subtitle: t("onboarding.landing.tagline"), centered: true)
            }
            Spacer()
            VStack(spacing: 12) {
                Button(t("onboarding.landing.createAccount")) { path.append(AuthRoute.signup) }
                    .buttonStyle(.lw(.theme))
                    .accessibilityIdentifier("landing.create")
                Button(t("onboarding.landing.login")) { path.append(AuthRoute.login) }
                    .buttonStyle(.lw(.secondary))
                    .accessibilityIdentifier("landing.login")
                Button { path.append(AuthRoute.instance) } label: {
                    OnbIconText(icon: "globe", text: app.instanceURL.host() ?? app.instanceURL.absoluteString)
                        .font(LW.font(13)).foregroundStyle(LW.muted).frame(minHeight: 36)
                }
                .accessibilityHint(t("ios.onb.changeInstance"))
                .accessibilityIdentifier("landing.instance")
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LW.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// `/wallet/signup` — onboarding/signup-choice.tsx.
struct SignupChoiceScreen: View {
    @Environment(\.authPath) private var path
    private let passkey = PasskeyService.isSupported

    var body: some View {
        OnbPage {
            VStack(spacing: 0) {
                OnbHeading(title: t("onboarding.signup.title"),
                           subtitle: t(passkey ? "onboarding.signup.subtitlePasskey" : "onboarding.signup.subtitleNostr"))
                    .padding(.top, 16)
                Spacer(minLength: 24)
                VStack(spacing: 12) {
                    if passkey {
                        Button { path.wrappedValue.append(AuthRoute.createPasskey) } label: {
                            OnbIconText(icon: "fingerprint", text: t("onboarding.signup.passkey"))
                        }
                        .buttonStyle(.lw(.theme))
                        .accessibilityIdentifier("signup.passkey")
                    }
                    Button(t("onboarding.signup.randomKey")) { path.wrappedValue.append(AuthRoute.createAccount) }
                        .buttonStyle(.lw(passkey ? .secondary : .theme))
                        .accessibilityIdentifier("signup.randomKey")
                    Button(t("onboarding.signup.haveKey")) { path.wrappedValue.append(AuthRoute.login) }
                        .buttonStyle(.lw(.secondary))
                        .accessibilityIdentifier("signup.haveKey")
                }
            }
        }
    }
}

/// `/wallet/create-account` — onboarding/create-account-flow.tsx. The key never leaves the device.
struct CreateAccountScreen: View {
    @Environment(AppModel.self) private var app
    @State private var keys = NostrKeys.generate()
    @State private var confirmed = false
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        OnbPage {
            ScrollView {
                VStack(spacing: 24) {
                    OnbHeading(title: t("onboarding.createAccount.title"), subtitle: t("onboarding.createAccount.subtitle"))
                    OnbSecretKeyReveal(nsec: keys.nsec, disabled: loading, confirmed: $confirmed,
                                       confirmLabel: t("onboarding.createAccount.confirmLabel"))
                    OnbError(message: error)
                }
                .padding(.top, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            Button(action: submit) {
                OnbIconText(icon: nil, text: loading ? t("onboarding.createAccount.creating") : t("common.continue"), busy: loading)
            }
            .buttonStyle(.lw(.primary))
            .disabled(!confirmed || loading)
            .padding(.top, 12)
            .accessibilityIdentifier("create.continue")
        }
    }

    private func submit() {
        error = nil
        loading = true
        // `postAuthPath('/wallet/welcome')`: a pending card activation wins over the welcome note.
        app.showWelcome = app.pendingActivation == nil
        Task {
            do {
                try await app.login(keys: keys, method: .nsec)
            } catch {
                app.showWelcome = false
                let message = error.localizedDescription.isEmpty ? t("onboarding.createAccount.failed") : error.localizedDescription
                self.error = message
                app.show(.error, message)
                loading = false
            }
        }
    }
}

/// `/wallet/create-passkey` — onboarding/passkey-create-flow.tsx. The Nostr key is derived from the passkey (PRF).
struct CreatePasskeyScreen: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        OnbPage {
            ScrollView {
                VStack(spacing: 24) {
                    OnbHeading(title: t("onboarding.passkey.title"),
                               subtitle: t("onboarding.passkey.subtitle", ["community": app.onbCommunityName]))
                    VStack(alignment: .leading, spacing: 16) {
                        benefit("fingerprint", t("onboarding.passkey.benefitBiometric"))
                        benefit("cloud", t("onboarding.passkey.benefitSync"))
                        benefit("key-round", t("onboarding.passkey.benefitKey"))
                    }
                }
                .padding(.top, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            OnbPasskeyButton(mode: .register, label: t("onboarding.passkey.submit"), surfaceCancel: true, id: "passkey.create",
                             onStart: { app.showWelcome = app.pendingActivation == nil },
                             onFailure: { app.showWelcome = false })
                .padding(.top, 12)
        }
    }

    private func benefit(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Icon(icon, size: 16).foregroundStyle(LW.foreground).frame(width: 32, height: 32).background(LW.card).clipShape(Circle())
            Text(text).font(LW.font(14)).foregroundStyle(LW.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
        }
    }
}

/// `/wallet/login` — onboarding/login-options.tsx: passkey or Nostr.
struct LoginScreen: View {
    @Environment(\.authPath) private var path

    var body: some View {
        OnbPage {
            ScrollView {
                VStack(spacing: 32) {
                    OnbLogotype().frame(width: 120, height: 28)
                    OnbHeading(title: t("onboarding.login.title"), subtitle: t("onboarding.login.subtitle"), centered: true)
                    VStack(spacing: 20) {
                        OnbPasskeyButton(mode: .authenticate, label: t("onboarding.login.passkey"), showCrossDeviceHint: true,
                                         surfaceCancel: true, id: "login.passkey")
                        ZStack {
                            Rectangle().fill(LW.border).frame(height: 1)
                            Text(t("onboarding.login.or")).font(LW.font(12)).foregroundStyle(LW.muted).padding(.horizontal, 8).background(LW.background)
                        }
                        Button { path.wrappedValue.append(AuthRoute.loginNostr) } label: {
                            OnbIconText(icon: "key-round", text: t("onboarding.login.continueWithNostr"))
                        }
                        .buttonStyle(.lw(.secondary))
                        .accessibilityIdentifier("login.nostr")
                    }
                }
                .padding(.top, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 12) {
                Text(t("onboarding.login.newHere")).font(LW.font(14)).foregroundStyle(LW.muted)
                Button(t("onboarding.login.createAccount")) { path.wrappedValue.append(AuthRoute.signup) }
                    .buttonStyle(.lw(.secondary, height: 44))
                    .accessibilityIdentifier("login.signup")
            }
            .padding(.top, 12)
        }
    }
}

/// `/wallet/welcome` — onboarding/community-note-card.tsx.
struct WelcomeScreen: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        OnbPage(back: false) {
            ScrollView {
                VStack(spacing: 32) {
                    Icon("sparkles", size: 40).foregroundStyle(LW.nwcPurple)
                        .frame(width: 80, height: 80)
                        .background(LW.nwcPurple.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    OnbHeading(title: t("onboarding.welcome.title").replacingOccurrences(of: "LaWallet", with: app.onbCommunityName),
                               subtitle: t("onboarding.welcome.body"), centered: true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(t("onboarding.welcome.thingsToKnow")).font(LW.font(14, .medium)).foregroundStyle(LW.foreground)
                        ForEach(["tipKey", "tipAddress", "tipSats"], id: \.self) { key in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•")
                                Text(t("onboarding.welcome.\(key)")).fixedSize(horizontal: false, vertical: true)
                            }
                            .font(LW.font(12)).foregroundStyle(LW.muted)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LW.card.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(LW.border))
                }
                .padding(.top, 64)
            }
            .scrollBounceBehavior(.basedOnSize)
            Button(t("onboarding.welcome.enter")) { app.showWelcome = false }
                .buttonStyle(.lw(.primary))
                .padding(.top, 12)
                .accessibilityIdentifier("welcome.enter")
        }
        .background(LW.background.ignoresSafeArea())
    }
}
