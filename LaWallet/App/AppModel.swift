import Foundation
import LaWalletKit
import Observation
import SwiftUI

enum LoginMethod: String, Codable, Sendable { case nsec, passkey, bunker }

/// App-wide state: which instance we talk to, who is signed in, and the signed-in user's server record.
@Observable @MainActor
final class AppModel {
    static let defaultInstance = URL(string: "https://beta.lawallet.io")!
    static let instanceKey = "lawallet-instance-url"
    static let settingsCacheKey = "lawallet-instance-settings"

    // Instance
    private(set) var instanceURL: URL
    private(set) var settings: InstanceSettings?
    private(set) var theme = Theme()
    private(set) var api: LaWalletAPI

    /// NIP-98 binds to the public `endpoint` setting; fall back to what the user typed.
    var endpoint: URL { settings?.endpoint.flatMap { URL(string: $0) } ?? instanceURL }
    var communityName: String { settings?.community_name ?? "LaWallet" }
    var addressDomain: String { settings?.domain ?? endpoint.host() ?? "" }

    // Session
    private(set) var signer: (any NostrSigner)?
    private(set) var pubkey: String?
    private(set) var loginMethod: LoginMethod?
    private(set) var role = "USER"
    var isAuthenticated: Bool { signer != nil }
    private var jwt: String?
    private var jwtExpiry: Date?
    private var minting: Task<String, Error>?

    // User
    private(set) var me: CurrentUser?
    private(set) var meError: String?
    private(set) var bootstrapped = false

    // Stores & UI state
    let wallet = WalletStore()
    let currencies = CurrencyStore()
    let flows = FlowState()
    var path = NavigationPath()
    var toast: Toast?
    var showWelcome = false
    /// Card activation started while signed out (1 h TTL, like `lawallet:pending-activation`).
    var pendingActivation: (id: String, at: Date)?
    var paymentSound: String = UserDefaults.standard.string(forKey: "lawallet-payment-sound") ?? "off" {
        didSet { UserDefaults.standard.set(paymentSound, forKey: "lawallet-payment-sound") }
    }
    var language: String = L10n.shared.locale {
        didSet { L10n.shared.load(language); localeVersion += 1 }
    }
    /// Bumped when the language changes so views re-render.
    private(set) var localeVersion = 0

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.instanceKey).flatMap(URL.init(string:)) ?? Self.defaultInstance
        instanceURL = saved
        let cached = UserDefaults.standard.data(forKey: Self.settingsCacheKey).flatMap { try? JSONDecoder().decode(InstanceSettings.self, from: $0) }
        settings = cached
        theme = Theme.from((cached?.brand_theme, cached?.brand_rounding))
        api = LaWalletAPI(http: HTTPClient(baseURL: cached?.endpoint.flatMap(URL.init(string:)) ?? saved))
        rebuildAPI()
        wallet.onPayment = { [weak self] tx in self?.handlePayment(tx) }
        currencies.persist = { [weak self] prefs in
            guard let self, self.isAuthenticated else { return }
            Task { try? await self.api.saveCurrencyPrefs(prefs) }
        }
    }

    private func rebuildAPI() {
        api = LaWalletAPI(http: HTTPClient(baseURL: endpoint, bearer: { @MainActor [weak self] in try await self?.validJWT() },
                                           onUnauthorized: { Task { @MainActor [weak self] in self?.jwt = nil } }))
    }

    // MARK: bootstrap

    func bootstrap() async {
        restoreSession()
        await loadSettings()
        if isAuthenticated { await refreshMe() }
        bootstrapped = true
        Task { await currencies.refreshRates() }
    }

    func loadSettings() async {
        guard let s = try? await api.settings() else { return }
        apply(settings: s)
    }

    private func apply(settings s: InstanceSettings) {
        let endpointChanged = s.endpoint != settings?.endpoint
        settings = s
        theme = Theme.from((s.brand_theme, s.brand_rounding))
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: Self.settingsCacheKey) }
        if endpointChanged { rebuildAPI(); jwt = nil }
    }

    /// Settings → Instance. Probes `/.well-known/lawallet.json` + `/api/settings` before switching.
    func switchInstance(to raw: String) async throws {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), url.host() != nil else {
            throw APIError(status: 0, message: t("ios.instance.invalid"))
        }
        let s = try await LaWalletAPI.probe(url)
        instanceURL = url
        UserDefaults.standard.set(url.absoluteString, forKey: Self.instanceKey)
        settings = nil
        apply(settings: s)
        rebuildAPI()
        jwt = nil
        jwtExpiry = nil
        Keychain.set(nil, for: "jwt")
        me = nil
        wallet.disconnect()
        if isAuthenticated { await refreshMe() }
    }

    // MARK: session

    private func restoreSession() {
        guard let method = Keychain.get("login-method").flatMap(LoginMethod.init(rawValue:)) else { return }
        switch method {
        case .nsec, .passkey:
            guard let secret = Keychain.get("signer-secret"), let keys = try? NostrKeys(nsecOrHex: secret) else { return }
            signer = LocalSigner(keys: keys)
            pubkey = keys.publicKey
        case .bunker:
            guard let json = Keychain.get("bunker-session"), let session = try? JSONDecoder().decode(BunkerSession.self, from: Data(json.utf8)),
                  let bunker = try? BunkerSigner(session: session) else { return }
            signer = bunker
            pubkey = session.userPubkey
        }
        loginMethod = method
        if let saved = Keychain.get("jwt"), let exp = Self.jwtExpiry(saved), exp > Date() { jwt = saved; jwtExpiry = exp }
    }

    /// Signs in with a local key (`nsec` or passkey-derived). Creates the account on first `/me`.
    func login(keys: NostrKeys, method: LoginMethod) async throws {
        try await login(signer: LocalSigner(keys: keys), pubkey: keys.publicKey, method: method) {
            Keychain.set(keys.secret.hex, for: "signer-secret")
        }
    }

    func login(bunker: BunkerSigner) async throws {
        let session = bunker.session
        try await login(signer: bunker, pubkey: session.userPubkey, method: .bunker) {
            Keychain.set(String(decoding: try! JSONEncoder().encode(session), as: UTF8.self), for: "bunker-session")
        }
    }

    private func login(signer s: any NostrSigner, pubkey pk: String, method: LoginMethod, persist: () -> Void) async throws {
        // Mint first: flipping `signer` swaps RootView to the signed-in tree, so only do it once auth succeeded.
        let token = try await LaWalletAPI(http: HTTPClient(baseURL: endpoint)).mintJWT(signer: s).token
        signer = s
        pubkey = pk
        loginMethod = method
        jwt = token
        jwtExpiry = Self.jwtExpiry(token) ?? Date().addingTimeInterval(3600)
        Keychain.set(token, for: "jwt")
        if let r = Self.jwtClaims(token)?["role"]?.string { role = r }
        persist()
        Keychain.set(method.rawValue, for: "login-method")
        await refreshMe()
        if !ProcessInfo.processInfo.arguments.contains("-uitest-reset") { Notifier.requestAuthorization() }
    }

    func logout() {
        Keychain.wipe()
        signer = nil
        pubkey = nil
        loginMethod = nil
        jwt = nil
        jwtExpiry = nil
        me = nil
        role = "USER"
        wallet.disconnect()
        wallet.clearCaches()
        flows.reset()
        path = NavigationPath()
        ContactsStore.shared.clear()
    }

    /// Bearer JWT, re-minted over NIP-98 five minutes before expiry (mirrors `jwt-expiry.ts`).
    func validJWT() async throws -> String? {
        guard let signer else { return nil }
        if let jwt, let jwtExpiry, jwtExpiry.timeIntervalSinceNow > 300 { return jwt }
        if let minting { return try await minting.value }
        let bootstrap = LaWalletAPI(http: HTTPClient(baseURL: endpoint))
        let task = Task { try await bootstrap.mintJWT(signer: signer).token }
        minting = task
        defer { minting = nil }
        let token = try await task.value
        jwt = token
        jwtExpiry = Self.jwtExpiry(token) ?? Date().addingTimeInterval(3600)
        Keychain.set(token, for: "jwt")
        if let claims = Self.jwtClaims(token), let r = claims["role"]?.string { role = r }
        return token
    }

    nonisolated static func jwtClaims(_ token: String) -> JSONValue? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        return Data(base64Encoded: b64).flatMap { try? JSONValue.parse($0) }
    }

    nonisolated static func jwtExpiry(_ token: String) -> Date? { jwtClaims(token)?["exp"]?.double.map(Date.init(timeIntervalSince1970:)) }

    // MARK: user

    func refreshMe() async {
        do {
            let user = try await api.me()
            me = user
            meError = nil
            if let prefs = user.currencyPrefs { currencies.hydrate(prefs) }
            wallet.connect(user.nwc)
            if let r = Self.jwtClaims(jwt ?? "")?["role"]?.string { role = r }
        } catch {
            meError = error.localizedDescription
        }
    }

    /// Re-reads `/me` right before moving money so a revived courtesy wallet is used (`resolveFreshUserNwc`).
    func freshNWC() async -> String? {
        await refreshMe()
        return me?.nwc
    }

    /// Receive-side: auto-create an LNCurl wallet when the user has none and the instance allows it.
    func ensureWallet() async throws -> String {
        if let nwc = await freshNWC() { return nwc }
        guard settings?.lncurlAutoCreate == true || settings?.lncurlEnabled == true else {
            throw APIError(status: 0, message: t("home.noWalletBody"))
        }
        _ = try await api.createLncurlWallet(isDefault: true)
        guard let nwc = await freshNWC() else { throw APIError(status: 0, message: t("home.noWalletBody")) }
        return nwc
    }

    // MARK: events

    private func handlePayment(_ tx: NWCTransaction) {
        guard tx.type == .incoming else { return }
        SoundPlayer.play(paymentSound)
        Notifier.notifyIncoming(sats: tx.amountSats, description: tx.description)
        Haptics.success()
    }

    func show(_ kind: Toast.Kind, _ message: String) {
        let next = Toast(kind: kind, message: message)
        toast = next
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            if toast?.id == next.id { toast = nil }
        }
    }

    func navigate(_ route: Route) { path.append(route) }
    func popToRoot() { path = NavigationPath() }
}
