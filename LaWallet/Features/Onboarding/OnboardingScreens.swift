import LaWalletKit
import SwiftUI

/// `/wallet/landing` — onboarding/landing-hero.tsx.
struct LandingScreen: View {
    @Binding var path: NavigationPath
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 30) {
                // Glass tile over a soft mint bloom — the isotype's own light.
                OnbIsotype()
                    .padding(30)
                    .frame(width: 150, height: 150)
                    .background {
                        RoundedRectangle(cornerRadius: 48, style: .continuous).fill(LW.mint.opacity(0.35))
                            .blur(radius: 40).scaleEffect(1.15)
                    }
                    .lwGlass(in: RoundedRectangle(cornerRadius: LW.Radius.sheet, style: .continuous))
                    .shadow(color: LW.mint.opacity(0.25), radius: 40)
                VStack(spacing: 12) {
                    Text(app.onbCommunityName).font(LW.font(34, .bold)).tracking(-0.8).foregroundStyle(LW.foreground)
                        .accessibilityAddTraits(.isHeader)
                    Text(t("onboarding.landing.tagline")).font(LW.font(16)).foregroundStyle(LW.muted).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            }
            Spacer()
            VStack(spacing: 18) {
                GlassGroup(spacing: 12) {
                    VStack(spacing: 12) {
                        Button(t("onboarding.landing.createAccount")) { path.append(AuthRoute.signup) }
                            .buttonStyle(.lw(.theme))
                            .accessibilityIdentifier("landing.create")
                        Button(t("onboarding.landing.login")) { path.append(AuthRoute.login) }
                            .buttonStyle(.lw(.secondary))
                            .accessibilityIdentifier("landing.login")
                    }
                }
                Button { path.append(AuthRoute.instance) } label: {
                    OnbIconText(icon: "globe", text: app.instanceURL.host() ?? app.instanceURL.absoluteString)
                        .font(LW.font(13, .medium)).foregroundStyle(LW.muted).lineLimit(1)
                        .padding(.horizontal, 14).frame(minHeight: 36).contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .lwGlass(in: Capsule(), interactive: true)
                .accessibilityHint(t("ios.onb.changeInstance"))
                .accessibilityIdentifier("landing.instance")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    .padding(.horizontal, 20).padding(.top, 12)
                Spacer(minLength: 24)
            }
            BottomBar {
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
                    .buttonStyle(.lw(.outline))
                    .accessibilityIdentifier("signup.haveKey")
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
                VStack(spacing: 28) {
                    OnbHeading(title: t("onboarding.createAccount.title"), subtitle: t("onboarding.createAccount.subtitle"))
                    OnbSecretKeyReveal(nsec: keys.nsec, disabled: loading, confirmed: $confirmed,
                                       confirmLabel: t("onboarding.createAccount.confirmLabel"))
                    OnbError(message: error)
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .lwSoftScrollEdges()
            BottomBar {
                Button(action: submit) {
                    OnbIconText(icon: nil, text: loading ? t("onboarding.createAccount.creating") : t("common.continue"), busy: loading)
                }
                .buttonStyle(.lw(.primary))
                .disabled(!confirmed || loading)
                .accessibilityIdentifier("create.continue")
            }
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
                VStack(spacing: 28) {
                    OnbHeading(title: t("onboarding.passkey.title"),
                               subtitle: t("onboarding.passkey.subtitle", ["community": app.onbCommunityName]))
                    VStack(spacing: 0) {
                        benefit("fingerprint", t("onboarding.passkey.benefitBiometric"))
                        RowDivider().padding(.leading, 50)
                        benefit("cloud", t("onboarding.passkey.benefitSync"))
                        RowDivider().padding(.leading, 50)
                        benefit("key-round", t("onboarding.passkey.benefitKey"))
                    }
                    .padding(.vertical, 4)
                    .lwSurface(LW.Radius.surface - 4)
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .lwSoftScrollEdges()
            BottomBar {
                OnbPasskeyButton(mode: .register, label: t("onboarding.passkey.submit"), surfaceCancel: true, id: "passkey.create",
                                 onStart: { app.showWelcome = app.pendingActivation == nil },
                                 onFailure: { app.showWelcome = false })
            }
        }
    }

    private func benefit(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Icon(icon, size: 17).foregroundStyle(LW.mint)
                .frame(width: 36, height: 36).background(LW.mint.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(text).font(LW.font(15)).foregroundStyle(LW.foreground.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
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
                        HStack(spacing: 12) {
                            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.5)
                            Text(t("onboarding.login.or")).font(LW.font(13, .medium)).foregroundStyle(LW.muted)
                            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.5)
                        }
                        Button { path.wrappedValue.append(AuthRoute.loginNostr) } label: {
                            OnbIconText(icon: "key-round", text: t("onboarding.login.continueWithNostr"))
                        }
                        .buttonStyle(.lw(.secondary))
                        .accessibilityIdentifier("login.nostr")
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .lwSoftScrollEdges()
            BottomBar {
                Text(t("onboarding.login.newHere")).font(LW.font(14)).foregroundStyle(LW.muted)
                Button(t("onboarding.login.createAccount")) { path.wrappedValue.append(AuthRoute.signup) }
                    .buttonStyle(.lw(.outline, height: 46))
                    .accessibilityIdentifier("login.signup")
            }
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
                    Icon("sparkles", size: 38).foregroundStyle(LW.sun)
                        .frame(width: 84, height: 84)
                        .background {
                            RoundedRectangle(cornerRadius: 36, style: .continuous).fill(LW.sun.opacity(0.30))
                                .blur(radius: 30).scaleEffect(1.2)
                        }
                        .lwGlass(in: RoundedRectangle(cornerRadius: LW.Radius.surface, style: .continuous), tint: .color(LW.sun.opacity(0.14)))
                    OnbHeading(title: t("onboarding.welcome.title").replacingOccurrences(of: "LaWallet", with: app.onbCommunityName),
                               subtitle: t("onboarding.welcome.body"), centered: true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(t("onboarding.welcome.thingsToKnow")).font(LW.font(14, .semibold)).foregroundStyle(LW.muted).padding(.leading, 6)
                        VStack(spacing: 0) {
                            let tips = ["tipKey", "tipAddress", "tipSats"]
                            ForEach(tips.indices, id: \.self) { i in
                                if i > 0 { RowDivider() }
                                HStack(alignment: .top, spacing: 12) {
                                    Circle().fill(LW.mint).frame(width: 6, height: 6).padding(.top, 7)
                                    Text(t("onboarding.welcome.\(tips[i])")).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                                .font(LW.font(14)).foregroundStyle(LW.foreground.opacity(0.85))
                                .padding(.horizontal, 18).padding(.vertical, 14)
                            }
                        }
                        .lwSurface(LW.Radius.surface - 4)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 56).padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .lwSoftScrollEdges()
            BottomBar {
                Button(t("onboarding.welcome.enter")) { app.showWelcome = false }
                    .buttonStyle(.lw(.primary))
                    .accessibilityIdentifier("welcome.enter")
            }
        }
        // Welcome sits outside the routed stacks (RootView), so it brings its own ambient light.
        .lwScreenBackground(1)
    }
}
