import LaWalletKit
import SwiftUI

/// Signed-out page shell (`(auth)/layout.tsx`): optional glass back header, content capped at 480 pt.
/// Screens pad their own 20 pt gutters so scroll content can dissolve under the chrome; actions go in `BottomBar`.
struct OnbPage<Content: View>: View {
    var back = true
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            if back { ScreenHeader(title: nil) }
            VStack(spacing: 0) { content() }
                .frame(maxWidth: 480, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// `h1` + muted lead used at the top of every onboarding screen.
struct OnbHeading: View {
    let title: String
    var subtitle: String?
    var centered = false
    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 10) {
            Text(title).font(LW.font(30, .bold)).tracking(-0.6).foregroundStyle(LW.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).font(LW.font(15)).foregroundStyle(LW.muted).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(centered ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }
}

/// Icon + text button label (lucide icon at 16 pt).
struct OnbIconText: View {
    let icon: String?
    let text: String
    var busy = false
    var body: some View {
        HStack(spacing: 8) {
            if busy { ProgressView().controlSize(.small).tint(LW.muted) } else if let icon { Icon(icon, size: 16) }
            Text(text)
        }
    }
}

/// Small left-aligned destructive line (`text-xs text-destructive`).
struct OnbError: View {
    let message: String?
    var body: some View {
        if let message, !message.isEmpty {
            Text(message).font(LW.font(13, .medium)).foregroundStyle(LW.destructiveText).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("error.text")
        }
    }
}

/// Community isotype (`useBrandLogotypes().isotypo`), falling back to the bundled one.
struct OnbIsotype: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        if let url = app.onbImageURL(app.settings?.isotypo_url) {
            RemoteImage(url: url, contentMode: .fit)
        } else {
            Image("isotypo").resizable().scaledToFit()
        }
    }
}

struct OnbLogotype: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        if let url = app.onbImageURL(app.settings?.logotype_url) {
            RemoteImage(url: url, contentMode: .fit)
        } else {
            Image("logotype").resizable().scaledToFit()
        }
    }
}

extension AppModel {
    /// Settings image URLs may be root-relative; resolve them against the public endpoint.
    func onbImageURL(_ raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        return URL(string: raw, relativeTo: endpoint)?.absoluteURL
    }

    /// `community_name?.trim() || 'LaWallet'`.
    var onbCommunityName: String {
        let name = communityName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "LaWallet" : name
    }
}

/// shared/secret-key-reveal.tsx — blurred-by-default nsec with reveal, copy and an optional "I saved it" checkbox.
struct OnbSecretKeyReveal: View {
    let nsec: String
    var disabled = false
    var confirmed: Binding<Bool>?
    var confirmLabel: String?
    var idPrefix = "create"
    @Environment(AppModel.self) private var app
    @State private var revealed = false

    var body: some View {
        // One glass surface: the key sits in a recessed well, copy is a frosted chip, the backup confirm is a hairline row.
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    Text(nsec)
                        .font(.system(size: 13, design: .monospaced)).foregroundStyle(LW.foreground)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .blur(radius: revealed ? 0 : 5)
                        .accessibilityIdentifier("\(idPrefix).nsec")
                    Button { withAnimation(.snappy) { revealed.toggle() } } label: {
                        Icon(revealed ? "eye-off" : "eye", size: 16).foregroundStyle(LW.muted).frame(width: 32, height: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t(revealed ? "auth.hideKey" : "auth.revealKey"))
                    .accessibilityIdentifier("\(idPrefix).reveal")
                }
                .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 10)
                .lwInset()

                // A fresh secret key: local-only, auto-expiring (never synced to other devices via Universal Clipboard).
                CopyButton(value: nsec, secret: true, onCopy: { app.show(.success, t("auth.keyCopied")) }) { copied in
                    OnbIconText(icon: copied ? "check" : "copy", text: copied ? t("common.copied") : t("auth.copyKey"))
                        .font(LW.font(15, .semibold)).foregroundStyle(LW.foreground)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressScale())
                .disabled(disabled)
                .opacity(disabled ? 0.42 : 1)
                .accessibilityIdentifier("\(idPrefix).copy")
            }
            .padding(14)

            if let confirmed {
                RowDivider()
                Button { confirmed.wrappedValue.toggle(); Haptics.tap() } label: {
                    HStack(alignment: .top, spacing: 12) {
                        OnbCheckbox(on: confirmed.wrappedValue).padding(.top, 1)
                        Text(confirmLabel ?? t("auth.savedKeyConfirm")).font(LW.font(15)).foregroundStyle(LW.foreground)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .accessibilityAddTraits(confirmed.wrappedValue ? .isSelected : [])
                .accessibilityIdentifier("\(idPrefix).backedUp")
            }
        }
        .lwSurface(LW.Radius.surface - 4)
    }
}

struct OnbCheckbox: View {
    let on: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(on ? LW.foreground : Color.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(on ? LW.foreground : LW.ring, lineWidth: 1))
            .overlay { if on { Icon("check", size: 13).foregroundStyle(LW.ink) } }
            .frame(width: 20, height: 20)
            .animation(.snappy(duration: 0.2), value: on)
    }
}

/// shared/passkey-login-button.tsx — the single passkey entry point (register or authenticate) with busy/error states.
struct OnbPasskeyButton: View {
    enum Mode { case register, authenticate }
    let mode: Mode
    var label: String?
    var kind: LWButtonKind = .theme
    var showCrossDeviceHint = false
    /// Show "prompt was closed" inline (never a toast) so a cancel has an obvious retry.
    var surfaceCancel = false
    var duplicateMessage: String?
    var id = "passkey.button"
    var onStart: () -> Void = {}
    var onFailure: () -> Void = {}
    @Environment(AppModel.self) private var app
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        if PasskeyService.isSupported(app) {
            VStack(spacing: 8) {
                Button(action: run) {
                    OnbIconText(icon: "fingerprint", text: busy ? t("auth.waitingForDevice") : buttonLabel, busy: busy)
                }
                .buttonStyle(.lw(kind))
                .disabled(busy)
                .accessibilityIdentifier(id)
                OnbError(message: error)
                if showCrossDeviceHint {
                    Text(t("auth.crossDeviceHint")).font(LW.font(13)).foregroundStyle(LW.muted).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var buttonLabel: String { label ?? t(mode == .register ? "auth.createWithPasskey" : "auth.continueWithPasskey") }

    private func run() {
        error = nil
        busy = true
        onStart()
        Task {
            do {
                switch mode {
                case .register: try await PasskeyService.shared.createAccount(app: app)
                case .authenticate: try await PasskeyService.shared.login(app: app)
                }
            } catch {
                onFailure()
                let e = PasskeyError.from(error)
                if e == .cancelled {
                    if surfaceCancel { self.error = e.localizedDescription }
                } else {
                    let message = (e.isDuplicate ? duplicateMessage : nil) ?? e.localizedDescription
                    self.error = message
                    app.show(.error, message)
                    Haptics.error()
                }
            }
            busy = false
        }
    }
}

/// Input with a trailing show/hide toggle (`nostr-connect-form.tsx` key + bunker fields).
struct OnbRevealField: View {
    let placeholder: String
    @Binding var text: String
    var invalid = false
    var id: String
    @State private var shown = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: LW.Radius.control, style: .continuous)
        let prompt = Text(verbatim: placeholder).foregroundStyle(LW.muted.opacity(0.8))
        HStack(spacing: 4) {
            Group {
                if shown { TextField("", text: $text, prompt: prompt) } else { SecureField("", text: $text, prompt: prompt) }
            }
            .font(.system(size: 15, design: .monospaced))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(.none)
            .accessibilityLabel(placeholder)
            .accessibilityIdentifier(id)
            Button { shown.toggle() } label: {
                Icon(shown ? "eye-off" : "eye", size: 16).foregroundStyle(LW.muted).frame(width: 36, height: 36).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("auth.toggleKeyVisibility"))
        }
        .padding(.leading, 16).padding(.trailing, 8).frame(minHeight: 54)
        .lwGlass(in: shape)
        .overlay { if invalid { shape.strokeBorder(LW.destructiveText.opacity(0.8), lineWidth: 1) } }
        .foregroundStyle(LW.foreground)
    }
}
