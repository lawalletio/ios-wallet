import LaWalletKit
import SwiftUI

/// `/wallet/login/nostr` — onboarding/nostr-login-methods.tsx + shared/nostr-connect-form.tsx.
/// Private key and bunker (NIP-46) tabs; no NIP-07 extension on iOS.
struct NostrLoginScreen: View {
    private enum Tab { case nsec, bunker }
    @State private var tab = Tab.nsec

    var body: some View {
        OnbPage {
            ScrollView {
                VStack(spacing: 28) {
                    OnbHeading(title: t("onboarding.nostr.title"), subtitle: t("onboarding.nostr.subtitle"))
                    VStack(spacing: 20) {
                        // ids resolve to `nostr.tab.nsec` / `nostr.tab.bunker`.
                        GlassSegmented(items: [(Tab.nsec, t("auth.privateKeyTab")), (.bunker, "Bunker")], selection: $tab,
                                       idPrefix: "nostr.tab", compact: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        switch tab {
                        case .nsec: NsecLoginForm()
                        case .bunker: BunkerLoginForm()
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .lwSoftScrollEdges()
        }
    }
}

/// Opens a NIP-46 `auth_url` challenge in the browser; the signer request keeps waiting.
private let openAuthURL: @Sendable (URL) -> Void = { url in
    Task { @MainActor in _ = await UIApplication.shared.open(url) }
}

// MARK: private key

private struct NsecLoginForm: View {
    @Environment(AppModel.self) private var app
    @State private var nsec = ""
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                OnbRevealField(placeholder: t("auth.nsecPlaceholder"), text: $nsec, invalid: error != nil, id: "nostr.nsecField")
                    .onChange(of: nsec) { error = nil }
                    .onSubmit(submit)
                OnbError(message: error).padding(.horizontal, 6)
            }
            Button(action: submit) {
                OnbIconText(icon: nil, text: loading ? t("onboarding.nostr.loading") : t("onboarding.nostr.submit"), busy: loading)
            }
            .buttonStyle(.lw(.primary))
            .disabled(nsec.trimmingCharacters(in: .whitespaces).isEmpty || loading)
            .accessibilityIdentifier("nostr.nsecSubmit")
        }
    }

    private func submit() {
        guard !loading else { return }
        error = nil
        guard let keys = try? NostrKeys(nsecOrHex: nsec) else {
            fail(t("ios.onb.invalidKey"))
            return
        }
        loading = true
        Task {
            do { try await app.login(keys: keys, method: .nsec) } catch {
                fail(error.localizedDescription.isEmpty ? t("auth.loginFailed") : error.localizedDescription)
            }
            loading = false
        }
    }

    private func fail(_ message: String) {
        error = message
        app.show(.error, message)
        Haptics.error()
    }
}

// MARK: bunker

private struct BunkerLoginForm: View {
    private enum Mode { case qr, paste }
    @State private var mode = Mode.qr

    var body: some View {
        VStack(spacing: 20) {
            // ids resolve to `nostr.bunker.qr` / `nostr.bunker.paste`.
            GlassSegmented(items: [(Mode.qr, t("auth.showQr")), (.paste, t("auth.pasteUrl"))], selection: $mode, idPrefix: "nostr.bunker")
            switch mode {
            case .qr: BunkerQRMode()
            case .paste: BunkerPasteMode()
            }
        }
    }
}

/// `nostrconnect://` QR: the signer app scans it and answers on our relays.
private struct BunkerQRMode: View {
    private enum Status { case generating, waiting, connecting, error }
    static let relays = [URL(string: "wss://relay.nsec.app")!, URL(string: "wss://relay.damus.io")!]

    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var status = Status.generating
    @State private var uri: String?
    @State private var error: String?
    @State private var copied = false
    @State private var attempt = 0

    var body: some View {
        Group {
            switch status {
            case .generating: progress(t("auth.generatingConnection"))
            case .connecting: progress(t("auth.signerConnected"))
            case .error:
                VStack(spacing: 14) {
                    Icon("wifi-off", size: 18).foregroundStyle(LW.coral)
                        .frame(width: 36, height: 36).background(LW.coral.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text(error ?? t("auth.connectFailed")).font(LW.font(14)).foregroundStyle(LW.destructiveText).multilineTextAlignment(.center)
                    Button { attempt += 1 } label: { OnbIconText(icon: "refresh-cw", text: t("auth.tryAgain")) }
                        .buttonStyle(.lw(.outline, height: 40, fullWidth: false))
                        .accessibilityIdentifier("nostr.bunker.retry")
                }
                .padding(.horizontal, 20).padding(.vertical, 26)
                .frame(maxWidth: .infinity)
                .lwSurface()
            case .waiting: waiting
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: attempt) { await connect() }
    }

    private var waiting: some View {
        VStack(spacing: 16) {
            if let uri {
                // White tile stays opaque for scanners, set in a glass bezel (same as `QRDisplay`).
                QRCodeImage(text: uri)
                    .frame(width: 200, height: 200).padding(14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(10)
                    .lwSurface(LW.Radius.sheet)
                    .accessibilityIdentifier("nostr.bunker.qrCode")
                // Open-signer capsule + round copy lens, like `QRDisplay`'s copy/share pair.
                GlassGroup(spacing: 10) {
                    HStack(spacing: 10) {
                        if let url = URL(string: uri) {
                            Button { openURL(url) } label: { OnbIconText(icon: "external-link", text: t("ios.onb.openSigner")) }
                                .buttonStyle(.lw(.secondary, height: 46))
                                .accessibilityIdentifier("nostr.bunker.open")
                        }
                        Button {
                            UIPasteboard.general.string = uri
                            copied = true
                            Haptics.tap()
                            Task { try? await Task.sleep(for: .seconds(2)); copied = false }
                        } label: {
                            Icon(copied ? "check" : "copy", size: 17).foregroundStyle(LW.foreground).frame(width: 46, height: 46).contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .lwGlass(in: Circle(), interactive: true)
                        .accessibilityLabel(copied ? t("auth.copiedBang") : t("auth.copyUri"))
                        .accessibilityIdentifier("nostr.bunker.copy")
                    }
                }
                .frame(maxWidth: 300)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini).tint(LW.sun)
                    Text(t("auth.waitingForSigner"))
                }
                .font(LW.font(13, .medium)).foregroundStyle(LW.muted)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.white.opacity(0.08), in: Capsule())
                Text(scanHint).font(LW.font(13)).foregroundStyle(LW.muted).multilineTextAlignment(.center).tint(LW.muted)
                    .padding(.horizontal, 12)
            }
        }
    }

    private var scanHint: AttributedString {
        var link = AttributedString("nsec.app")
        link.link = URL(string: "https://nsec.app")
        link.underlineStyle = .single
        return AttributedString(t("auth.scanWithSignerPrefix")) + link + AttributedString(t("auth.scanWithSignerSuffix"))
    }

    private func progress(_ label: String) -> some View {
        VStack(spacing: 12) {
            ProgressView().tint(LW.muted)
            Text(label).font(LW.font(14)).foregroundStyle(LW.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
        .lwSurface()
    }

    private func connect() async {
        status = .generating
        error = nil
        copied = false
        let keys = NostrKeys.generate()
        let secret = Data.random(16).hex
        uri = BunkerSigner.nostrConnectURI(clientKeys: keys, relays: Self.relays, secret: secret, appName: app.onbCommunityName)
        status = .waiting
        do {
            let signer = try await BunkerSigner.awaitNostrConnect(clientKeys: keys, relays: Self.relays, secret: secret)
            try Task.checkCancellation()
            await signer.setAuthHandler(openAuthURL)
            status = .connecting
            // Unstructured so the root swapping to the signed-in tree (which cancels this `.task`) can't abort the login.
            let app = app
            try await Task { try await app.login(bunker: signer) }.value
        } catch {
            if Task.isCancelled { return }
            self.error = (error as? RelayError) == .timeout ? t("auth.connectTimedOut")
                : (error as? LocalizedError)?.errorDescription ?? t("auth.connectFailed")
            status = .error
        }
    }
}

/// `bunker://<remote-pubkey>?relay=…&secret=…` paste.
private struct BunkerPasteMode: View {
    @Environment(AppModel.self) private var app
    @State private var url = ""
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                OnbRevealField(placeholder: "bunker://...", text: $url, invalid: error != nil, id: "nostr.bunkerField")
                    .disabled(loading)
                    .onChange(of: url) { error = nil }
                    .onSubmit(submit)
                OnbError(message: error).padding(.horizontal, 6)
            }
            Button(action: submit) {
                OnbIconText(icon: nil, text: loading ? t("onboarding.nostr.loading") : t("onboarding.nostr.submit"), busy: loading)
            }
            .buttonStyle(.lw(.primary))
            .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty || loading)
            .accessibilityIdentifier("nostr.bunkerSubmit")
        }
    }

    /// `isValidBunkerUrl` from the web form.
    static func validate(_ raw: String) -> String? {
        let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard url.hasPrefix("bunker://") else { return t("auth.bunkerMustStart") }
        let rest = url.dropFirst("bunker://".count)
        let parts = rest.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        guard let pubkey = parts.first, pubkey.wholeMatch(of: /[0-9a-f]{64}/) != nil else { return t("auth.bunkerBadPubkey") }
        guard parts.count > 1, let comps = URLComponents(string: "x://h?" + parts[1]) else { return t("auth.bunkerNoRelay") }
        guard comps.queryItems?.contains(where: { $0.name == "relay" && !($0.value ?? "").isEmpty }) == true else { return t("auth.bunkerNoRelay") }
        return nil
    }

    private func submit() {
        guard !loading else { return }
        error = nil
        if let invalid = Self.validate(url) {
            error = invalid
            return
        }
        loading = true
        let uri = url.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let signer = try await BunkerSigner.connect(bunkerURI: uri, onAuth: openAuthURL)
                await signer.setAuthHandler(openAuthURL)
                try await app.login(bunker: signer)
            } catch {
                let message = (error as? RelayError) == .timeout ? t("auth.connectTimedOut")
                    : (error as? LocalizedError)?.errorDescription ?? t("auth.bunkerConnectFailed")
                self.error = message
                app.show(.error, message)
                Haptics.error()
            }
            loading = false
        }
    }
}
