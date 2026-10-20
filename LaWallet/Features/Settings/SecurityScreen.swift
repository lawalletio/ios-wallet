import AuthenticationServices
import LaWalletKit
import SwiftUI
import UniformTypeIdentifiers

/// `/wallet/settings/security` — settings/security-screen.tsx (+ passkeys-section, oauth/connected-apps, shared/secret-key-reveal).
struct SecurityScreen: View {
    @Environment(AppModel.self) private var app
    @State private var nsec: String?
    @State private var confirmReveal = false
    @State private var confirmRemove = false
    @State private var confirmDelete = false
    @State private var deleting = false
    private var s: String { "settings.securityScreen" }

    var body: some View {
        SettingsPage(title: t("settings.security")) {
            GroupBox(label: t("settings.account")) {
                if let pk = app.pubkey {
                    Button { copyNpub(pk) } label: { info(t("\(s).publicKey"), Self.truncateNpub(pk), icon: "user", tint: LW.mint, copy: true) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(t("\(s).copyLabel", ["label": t("\(s).publicKey")]))
                        .accessibilityIdentifier("security.npub")
                } else {
                    info(t("\(s).publicKey"), t("\(s).notSignedIn"), icon: "user", tint: LW.mint)
                }
                SettingsRowDivider()
                info(t("\(s).role"), roleLabel, icon: "shield", tint: LW.sun)
                SettingsRowDivider()
                info(t("\(s).loginMethod"), app.loginMethod.map { t("\(s).methods.\($0.rawValue)") } ?? t("\(s).unknown"), icon: "key-round")
            }

            SettingsSection(t("\(s).passkeys")) { PasskeysSection() }
            SettingsSection(t("\(s).connectedApps")) { ConnectedAppsSection() }

            if app.loginMethod == .nsec || app.loginMethod == .passkey {
                SettingsSection(t("\(s).secretKey")) {
                    if let nsec {
                        SecretKeyReveal(nsec: nsec)
                    } else {
                        Button { confirmReveal = true } label: { Label { Text(t("\(s).revealSecret")) } icon: { Icon("key-round", size: 16) } }
                            .buttonStyle(.lw(.secondary))
                            .accessibilityIdentifier("security.reveal")
                    }
                    Text(t(app.loginMethod == .passkey ? "\(s).passkeyKeyHint" : "\(s).nsecKeyHint"))
                        .font(LW.font(13)).foregroundStyle(LW.muted).padding(.horizontal, 6)
                }
            }

            SettingsSection(t("\(s).device")) {
                Button { confirmRemove = true } label: { Label { Text(t("\(s).removeDevice")) } icon: { Icon("log-out", size: 16) } }
                    .buttonStyle(.lw(.destructive))
                    .accessibilityIdentifier("security.removeDevice")
            }

            SettingsSection(t("ios.security.deleteTitle")) {
                Button { confirmDelete = true } label: {
                    Label { Text(t(deleting ? "ios.security.deleting" : "ios.security.deleteAccount")) } icon: { Icon("trash-2", size: 16) }
                }
                .buttonStyle(.lw(.outline))
                .disabled(deleting)
                .accessibilityIdentifier("security.deleteAccount")
                Text(t("ios.security.deleteHint")).font(LW.font(13)).foregroundStyle(LW.muted).padding(.horizontal, 6)
            }
        }
        .alert(t("\(s).revealSecret"), isPresented: $confirmReveal) {
            Button(t("common.cancel"), role: .cancel) {}
            Button(t("\(s).revealSecret")) { reveal() }
        } message: { Text(t("ios.security.revealHint")) }
        .alert(t("\(s).removeDevice"), isPresented: $confirmRemove) {
            Button(t("common.cancel"), role: .cancel) {}
            Button(t("\(s).removeDevice"), role: .destructive) { app.logout() }
        } message: { Text(t("\(s).removeConfirm")) }
        .alert(t("ios.security.deleteTitle"), isPresented: $confirmDelete) {
            Button(t("common.cancel"), role: .cancel) {}
            Button(t("ios.security.deleteAccount"), role: .destructive) { Task { await deleteAccount() } }
        } message: { Text(t("ios.security.deleteConfirm", ["host": host])) }
    }

    private var host: String { app.instanceURL.host() ?? app.instanceURL.absoluteString }

    private func deleteAccount() async {
        deleting = true
        defer { deleting = false }
        do {
            try await app.api.deleteAccount()
            app.logout()
            app.show(.success, t("ios.security.deleted"))
        } catch let error as APIError where error.status == 404 || error.status == 405 {
            app.show(.error, t("ios.security.deleteUnsupported", ["host": host]))
        } catch {
            app.show(.error, t("ios.security.deleteFailed", ["error": error.localizedDescription]))
        }
    }

    private var roleLabel: String {
        let key = "\(s).roles.\(app.role)"
        return L10n.shared.has(key) ? t(key) : app.role.lowercased().capitalized
    }

    private func info(_ label: String, _ value: String, icon: String, tint: Color = LW.foreground, copy: Bool = false) -> some View {
        HStack(spacing: 14) {
            SettingsIconTile(icon: icon, color: tint)
            Text(label).font(LW.font(16, .medium)).foregroundStyle(LW.foreground)
            Spacer(minLength: 8)
            Text(value).font(copy ? .system(size: 13, design: .monospaced) : LW.font(14)).foregroundStyle(LW.muted)
                .lineLimit(1).truncationMode(.middle)
            if copy { Icon("copy", size: 15).foregroundStyle(LW.muted.opacity(0.8)) }
        }
        .padding(.horizontal, 18).frame(minHeight: 58).contentShape(Rectangle())
    }

    private func copyNpub(_ pk: String) {
        Clipboard.copy(NIP19.npub(pk))
        app.show(.success, t("\(s).npubCopied"))
    }

    /// Read at tap time so the secret never sits in view state before the user asks (`handleRevealSecret`).
    private func reveal() {
        guard let stored = Keychain.get("signer-secret") else { app.show(.error, t("\(s).noSecret")); return }
        if stored.count == 64, let data = Data(hex: stored) { nsec = NIP19.nsec(data) } else { nsec = stored }
    }

    /// `truncateNpub`: `npub1` + 8 … last 8.
    static func truncateNpub(_ pk: String) -> String {
        let npub = NIP19.npub(pk)
        return npub.count <= 19 ? npub : "\(npub.prefix(13))...\(npub.suffix(8))"
    }
}

/// Blur-by-default key with show/hide + copy (shared/secret-key-reveal.tsx).
struct SecretKeyReveal: View {
    let nsec: String
    @Environment(AppModel.self) private var app
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text(nsec).font(.system(size: 13, design: .monospaced)).foregroundStyle(LW.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .blur(radius: revealed ? 0 : 5)
                    .animation(.easeOut(duration: 0.2), value: revealed)
                    .accessibilityIdentifier("security.nsec")
                Button { revealed.toggle() } label: {
                    Icon(revealed ? "eye-off" : "eye", size: 16).foregroundStyle(LW.muted).frame(width: 36, height: 36).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t(revealed ? "auth.hideKey" : "auth.revealKey"))
                .accessibilityIdentifier("security.toggleNsec")
            }
            .padding(.leading, 14).padding(.trailing, 4).padding(.vertical, 8)
            .lwInset()

            CopyButton(value: nsec, secret: true, onCopy: { app.show(.success, t("auth.keyCopied")) }) {
                CopyLabel(copied: $0, title: t("auth.copyKey"))
            }
                .buttonStyle(.lw(.secondary, height: 46))
                .accessibilityIdentifier("security.copyNsec")
        }
        .padding(12)
        .lwSurface(LW.Radius.surface - 4)
    }
}

// MARK: passkeys (settings/passkeys-section.tsx)

struct PasskeysSection: View {
    @Environment(AppModel.self) private var app
    @State private var credentials: [PasskeyCredential]?
    @State private var adding = false
    @State private var selected: PasskeyCredential?
    private let p = "settings.passkeysScreen"

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                if credentials == nil {
                    ProgressView().tint(LW.muted).frame(maxWidth: .infinity, minHeight: 58)
                } else if let credentials, credentials.isEmpty {
                    Text(t("\(p).empty")).font(LW.font(14)).foregroundStyle(LW.muted).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.vertical, 18)
                } else {
                    ForEach(Array((credentials ?? []).enumerated()), id: \.element.id) { i, c in
                        if i > 0 { SettingsRowDivider() }
                        Button { selected = c } label: { row(c) }.buttonStyle(.plain)
                    }
                }
            }
            .lwSurface(LW.Radius.surface - 4)

            if PasskeyService.isSupported(app) {
                Button { Task { await add() } } label: {
                    HStack(spacing: 8) {
                        if adding { ProgressView().controlSize(.small) } else { Icon("plus", size: 16) }
                        Text(t(adding ? "\(p).waiting" : "\(p).add"))
                    }
                }
                .buttonStyle(.lw(.secondary))
                .disabled(adding)
                .accessibilityIdentifier("security.addPasskey")
            }
        }
        .task { await load() }
        .sheet(item: $selected) { c in
            PasskeySheet(credential: c, name: name(c), isLast: credentials?.count == 1) { message in
                selected = nil
                app.show(.success, message)
                Task { await load() }
            }
            .presentationDetents([.medium])
        }
    }

    private func name(_ c: PasskeyCredential) -> String {
        c.label?.nonBlank ?? t("\(p).untitled", ["date": SettingsFormat.date(c.createdAt)?.formatted(date: .numeric, time: .omitted) ?? ""])
    }

    private func row(_ c: PasskeyCredential) -> some View {
        HStack(spacing: 14) {
            SettingsIconTile(icon: "fingerprint", color: LW.mint)
            VStack(alignment: .leading, spacing: 2) {
                Text(name(c)).font(LW.font(16, .medium)).foregroundStyle(LW.foreground).lineLimit(1)
                Text(c.lastUsedAt != nil ? t("\(p).lastUsed", ["when": SettingsFormat.relative(c.lastUsedAt)])
                    : t("\(p).addedAgo", ["when": SettingsFormat.relative(c.createdAt)]))
                    .font(LW.font(13)).foregroundStyle(LW.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            if c.deviceType == "multiDevice" && c.backedUp { SettingsBadge(t("\(p).synced"), .info) }
            Icon("chevron-right", size: 15).foregroundStyle(LW.muted.opacity(0.8))
        }
        .padding(.horizontal, 18).frame(minHeight: 58).contentShape(Rectangle())
    }

    private func load() async {
        do { credentials = try await app.api.passkeys() } catch {
            if credentials == nil { credentials = [] }
        }
    }

    private func add() async {
        adding = true
        defer { adding = false }
        do {
            try await PasskeyService.shared.addToCurrentAccount(app: app, label: nil)
            app.show(.success, t("\(p).added"))
            await load()
        } catch let e as ASAuthorizationError where e.code == .canceled {
            // closed the prompt — not an error
        } catch {
            app.show(.error, error.localizedDescription.nonBlank ?? t("\(p).addFailed"))
        }
    }
}

/// Rename / delete dialog for one credential.
private struct PasskeySheet: View {
    let credential: PasskeyCredential
    let name: String
    let isLast: Bool
    let onDone: (String) -> Void
    @Environment(AppModel.self) private var app
    @State private var label: String
    @State private var busy = false
    @State private var error: String?
    @State private var confirmDelete = false
    private let p = "settings.passkeysScreen"

    init(credential: PasskeyCredential, name: String, isLast: Bool, onDone: @escaping (String) -> Void) {
        self.credential = credential
        self.name = name
        self.isLast = isLast
        self.onDone = onDone
        _label = State(initialValue: credential.label ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(t("\(p).manage")).font(LW.font(22, .bold)).foregroundStyle(LW.foreground)
                Text(name).font(LW.font(14)).foregroundStyle(LW.muted)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(t("\(p).name")).font(LW.font(14, .semibold)).foregroundStyle(LW.muted).padding(.leading, 6)
                LWTextField(placeholder: t("\(p).namePlaceholder"), text: $label)
                    .onChange(of: label) { _, v in if v.count > 64 { label = String(v.prefix(64)) } }
            }
            ErrorText(message: error)
            Button(t("\(p).saveName")) { Task { await rename() } }
                .buttonStyle(.lw(.primary))
                .disabled(busy || label.trimmedValue.isEmpty)
            Button { confirmDelete = true } label: { Label { Text(t("\(p).delete")) } icon: { Icon("trash-2", size: 16) } }
                .buttonStyle(.lw(.destructive))
                .disabled(busy)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 28)
        .alert(t(isLast ? "\(p).deleteOnlyTitle" : "\(p).deleteTitle"), isPresented: $confirmDelete) {
            Button(t("common.cancel"), role: .cancel) {}
            Button(t("\(p).deleteConfirm"), role: .destructive) { Task { await delete() } }
        } message: { Text(t(isLast ? "\(p).deleteOnlyBody" : "\(p).deleteBody")) }
    }

    private func rename() async {
        busy = true
        defer { busy = false }
        do {
            try await app.api.renamePasskey(credential.id, label: label.trimmedValue)
            onDone(t("\(p).renamed"))
        } catch { self.error = error.localizedDescription.nonBlank ?? t("\(p).renameFailed") }
    }

    private func delete() async {
        busy = true
        defer { busy = false }
        do {
            try await app.api.deletePasskey(credential.id)
            onDone(t("\(p).deleted"))
        } catch { self.error = error.localizedDescription.nonBlank ?? t("\(p).deleteFailed") }
    }
}

// MARK: connected apps (oauth/connected-apps.tsx)

struct ConnectedAppsSection: View {
    @Environment(AppModel.self) private var app
    @State private var grants: [OAuthGrant]?
    @State private var error: String?
    @State private var target: OAuthGrant?
    @State private var revoking = false
    private let a = "ios.set.apps"

    var body: some View {
        let mcpURL = app.api.http.url("/api/mcp")
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(t("\(a).mcpUrl")).font(LW.font(15, .semibold)).foregroundStyle(LW.foreground)
                    Spacer()
                    Link(destination: URL(string: "https://docs.lawallet.io/docs/guides/mcp")!) {
                        HStack(spacing: 4) { Text(t("\(a).setupGuide")).font(LW.font(13, .medium)); Icon("external-link", size: 12) }
                    }
                    .foregroundStyle(LW.mint)
                }
                HStack(spacing: 8) {
                    Text(mcpURL).font(.system(size: 13, design: .monospaced)).foregroundStyle(LW.foreground.opacity(0.9))
                        .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                    CopyButton(value: mcpURL) { copied in
                        Icon(copied ? "check" : "copy", size: 15).foregroundStyle(copied ? LW.incoming : LW.muted)
                            .frame(width: 36, height: 36).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t("common.copy"))
                }
                .padding(.leading, 14).padding(.trailing, 4).padding(.vertical, 4)
                .lwInset()
                Text(t("\(a).mcpHint")).font(LW.font(13)).foregroundStyle(LW.muted)
            }
            .padding(18).lwSurface(LW.Radius.surface - 4)

            VStack(spacing: 0) {
                if let error {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(t("\(a).loadFailed", ["error": error])).font(LW.font(14)).foregroundStyle(LW.destructiveText)
                        Button { Task { await load() } } label: { Label { Text(t("common.retry")) } icon: { Icon("refresh-cw", size: 14) } }
                            .buttonStyle(.lw(.outline, height: 32, fullWidth: false))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                } else if let grants, grants.isEmpty {
                    Text(t("\(a).empty")).font(LW.font(14)).foregroundStyle(LW.muted).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.vertical, 18)
                } else if let grants {
                    ForEach(Array(grants.enumerated()), id: \.element.id) { i, g in
                        if i > 0 { SettingsRowDivider() }
                        row(g)
                    }
                } else {
                    ProgressView().tint(LW.muted).frame(maxWidth: .infinity, minHeight: 58)
                }
            }
            .lwSurface(LW.Radius.surface - 4)
        }
        .task { await load() }
        .alert(t("\(a).revokeTitle"), isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } })) {
            Button(t("common.cancel"), role: .cancel) {}
            Button(t("\(a).revoke"), role: .destructive) { if let g = target { Task { await revoke(g) } } }
        } message: { Text(t("\(a).revokeBody", ["name": target?.clientName ?? ""])) }
    }

    private func row(_ g: OAuthGrant) -> some View {
        HStack(alignment: .top, spacing: 14) {
            SettingsIconTile(icon: "bot", color: LW.foreground)
            VStack(alignment: .leading, spacing: 6) {
                Text(g.clientName).font(LW.font(16, .medium)).foregroundStyle(LW.foreground)
                HStack(spacing: 4) {
                    ForEach(g.scopes, id: \.self) { scope in
                        if scope == "spend" {
                            SettingsBadge(t("\(a).spend") + (g.spendLimitSats.map { " · " + t("\(a).spendLimit", ["n": $0.formatted()]) } ?? ""), .destructive)
                        } else {
                            SettingsBadge(scope.capitalized)
                        }
                    }
                }
                Text(t("\(a).connected", ["when": SettingsFormat.relative(g.createdAt)]) + " · "
                    + (g.lastUsedAt != nil ? t("\(a).lastUsed", ["when": SettingsFormat.relative(g.lastUsedAt)]) : t("\(a).notUsed")))
                    .font(LW.font(13)).foregroundStyle(LW.muted)
            }
            Spacer(minLength: 0)
            Button(t("\(a).revoke")) { target = g }
                .font(LW.font(13, .semibold)).foregroundStyle(LW.destructiveText)
                .padding(.horizontal, 12).frame(height: 32)
                .background(LW.coral.opacity(0.14), in: Capsule())
                .buttonStyle(.plain)
                .disabled(revoking)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private func load() async {
        do {
            grants = try await app.api.oauthGrants()
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func revoke(_ g: OAuthGrant) async {
        revoking = true
        defer { revoking = false }
        do {
            try await app.api.revokeGrant(g.id)
            app.show(.success, t("\(a).revoked", ["name": g.clientName]))
            await load()
        } catch { app.show(.error, error.localizedDescription.nonBlank ?? t("\(a).revokeFailed")) }
    }
}
