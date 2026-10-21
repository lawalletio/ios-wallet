import Foundation

/// Typed REST client for one LaWallet instance. Mirrors `@lawallet/sdk`'s client surface.
public struct LaWalletAPI: Sendable {
    public let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    private func path(_ base: String, _ segments: String...) -> String {
        ([base] + segments.map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? $0 })
            .joined(separator: "/")
    }

    // MARK: instance discovery (no auth)

    public static func probe(_ origin: URL, session: URLSession = .shared) async throws -> InstanceSettings {
        let http = HTTPClient(baseURL: origin, session: session)
        let marker = try? await http.get("/.well-known/lawallet.json", auth: .none, as: JSONValue.self)
        guard marker?["service"]?.string == "lawallet" else {
            throw APIError(status: 404, message: "That server isn't a LaWallet instance", code: "NOT_LAWALLET")
        }
        return try await http.get("/api/settings", auth: .none)
    }

    public func settings() async throws -> InstanceSettings { try await http.get("/api/settings", auth: .none) }

    // MARK: auth

    public func mintJWT(signer: any NostrSigner, expiresIn: String = "24h") async throws -> JWTToken {
        try await http.send("POST", "/api/jwt", json: ["expiresIn": expiresIn], auth: .nip98(signer))
    }

    public func jwtInfo() async throws -> JWTInfo { try await http.get("/api/jwt") }

    // MARK: user

    /// Creates the account on first call (and mints a courtesy LNCurl wallet when the instance auto-creates).
    public func me() async throws -> CurrentUser { try await http.get("/api/users/me") }

    public func me(signer: any NostrSigner) async throws -> CurrentUser { try await http.get("/api/users/me", auth: .nip98(signer)) }

    /// Permanently deletes the caller's account (addresses, cards, remote wallets). App Store guideline 5.1.1(v).
    /// Instances that predate the endpoint answer 404/405.
    public func deleteAccount() async throws {
        _ = try await http.send("DELETE", "/api/account", json: ["confirm": "DELETE"], as: JSONValue.self)
    }

    public func saveCurrencyPrefs(_ prefs: CurrencyPrefs) async throws {
        struct Body: Encodable { let currencyPrefs: CurrencyPrefs }
        _ = try await http.send("PUT", "/api/users/me/currency-prefs", json: Body(currencyPrefs: prefs), as: JSONValue.self)
    }

    public func setCardRecovery(enabled: Bool) async throws -> Bool {
        struct R: Decodable { let cardRecoveryEnabled: Bool }
        return try await http.send("PUT", "/api/users/me/card-recovery", json: ["enabled": enabled], as: R.self).cardRecoveryEnabled
    }

    /// Idempotent ack of `me.accountTransfer`.
    public func dismissAccountTransfer() async throws {
        _ = try await http.send("POST", "/api/users/me/account-transfer/dismiss", as: JSONValue.self)
    }

    public func profiles(_ pubkeys: [String]) async throws -> [NostrProfile] {
        struct R: Decodable { let profiles: [NostrProfile] }
        return try await http.send("POST", "/api/nostr/profiles", json: ["pubkeys": pubkeys], as: R.self).profiles
    }

    // MARK: lightning addresses

    public func checkUsername(_ username: String) async throws -> Bool {
        let q = username.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? username
        return try await http.get("/api/lightning-addresses/check?username=\(q)", auth: .none, as: UsernameAvailability.self).available
    }

    public func addresses() async throws -> [WalletAddress] { try await http.get("/api/wallet/addresses") }

    /// Throws `APIError` 402 when the instance charges for addresses → use `registrationInvoice`.
    public func createAddress(_ username: String) async throws -> WalletAddress {
        try await http.send("POST", "/api/wallet/addresses", json: ["username": username])
    }

    public func setPrimaryAddress(_ username: String) async throws {
        _ = try await http.send("POST", path("/api/wallet/addresses", username, "primary"), as: JSONValue.self)
    }

    public func deleteAddress(_ username: String) async throws {
        _ = try await http.send("DELETE", path("/api/wallet/addresses", username), as: JSONValue.self)
    }

    public func registrationInvoice(username: String) async throws -> RegistrationInvoice {
        try await http.send("POST", "/api/invoices", json: ["purpose": JSONValue.string("wallet-address"), "metadata": ["username": .string(username)]])
    }

    public func claimInvoice(id: String, preimage: String) async throws -> InvoiceClaim {
        try await http.send("POST", path("/api/invoices", id, "claim"), json: ["preimage": preimage])
    }

    // MARK: cards

    public func cards() async throws -> [Card] { try await http.get("/api/wallet/cards") }

    public func setCardEnabled(_ id: String, _ enabled: Bool) async throws -> Card {
        try await http.send("PATCH", path("/api/wallet/cards", id), json: ["enabled": enabled])
    }

    public func setCardWallet(_ id: String, remoteWalletId: String?) async throws -> Card {
        try await http.send("PATCH", path("/api/wallet/cards", id), json: ["remoteWalletId": remoteWalletId.map(JSONValue.string) ?? .null])
    }

    public func activationPreview(_ tokenId: String) async throws -> ActivationPreview {
        try await http.get(path("/api/activation-tokens", tokenId), auth: .none)
    }

    public func claimActivation(_ tokenId: String) async throws -> ActivationClaim {
        try await http.send("POST", path("/api/activation-tokens", tokenId, "claim"), json: ["remoteWalletId": JSONValue.null])
    }

    public func recoveryCheck(_ tokenId: String) async throws -> RecoveryCheck {
        try await http.get(path("/api/activation-tokens", tokenId, "recovery-check"))
    }

    /// RECOVER claim. Throws 409 with `reason == "RECOVERY_MERGE_REQUIRED"` when the caller has data and didn't confirm.
    public func claimRecovery(_ tokenId: String, confirmMerge: Bool) async throws -> RecoveryClaim {
        try await http.send("POST", path("/api/activation-tokens", tokenId, "claim"),
                            json: ["remoteWalletId": JSONValue.null, "confirmMerge": .bool(confirmMerge)])
    }

    // MARK: remote wallets

    public func remoteWallets() async throws -> [RemoteWallet] { try await http.get("/api/remote-wallets") }
    public func remoteWallet(_ id: String) async throws -> RemoteWallet { try await http.get(path("/api/remote-wallets", id)) }

    public func remoteWalletBalance(_ id: String) async throws -> Int {
        struct R: Decodable { let balanceSats: Double }
        return Int(try await http.get(path("/api/remote-wallets", id, "balance"), as: R.self).balanceSats)
    }

    public func createNWCWallet(name: String, connectionString: String, sendReceive: Bool, isDefault: Bool) async throws -> RemoteWallet {
        let body: JSONValue = ["name": .string(name), "type": "NWC", "isDefault": .bool(isDefault),
                               "config": ["connectionString": .string(connectionString), "mode": sendReceive ? "SEND_RECEIVE" : "RECEIVE"]]
        return try await http.send("POST", "/api/remote-wallets", json: body)
    }

    public func createLncurlWallet(name: String? = nil, isDefault: Bool) async throws -> RemoteWallet {
        var body: [String: JSONValue] = ["isDefault": .bool(isDefault)]
        if let name { body["name"] = .string(name) }
        return try await http.send("POST", "/api/remote-wallets/lncurl", json: JSONValue.object(body))
    }

    public func updateRemoteWallet(_ id: String, name: String? = nil, makeDefault: Bool = false, status: String? = nil) async throws -> RemoteWallet {
        var body: [String: JSONValue] = [:]
        if let name { body["name"] = .string(name) }
        if makeDefault { body["isDefault"] = true }
        if let status { body["status"] = .string(status) }
        return try await http.send("PATCH", path("/api/remote-wallets", id), json: JSONValue.object(body))
    }

    public func deleteRemoteWallet(_ id: String) async throws {
        _ = try await http.send("DELETE", path("/api/remote-wallets", id), as: Empty.self)
    }

    public func connectionString(_ id: String) async throws -> String {
        try await http.get(path("/api/remote-wallets", id, "connection-string"), as: JSONValue.self)["connectionString"]?.string ?? ""
    }

    public func receiveAction(_ id: String) async throws -> ReceiveAction { try await http.get(path("/api/remote-wallets", id, "receive-action")) }

    public func saveReceiveAction(_ id: String, feeBps: Int, baseFeeSats: Int, enabled: Bool, destinations: [ForwardingDestination]) async throws -> ReceiveAction {
        struct Body: Encodable { let feeBps: Int; let baseFeeSats: Int; let enabled: Bool; let destinations: [ForwardingDestination] }
        return try await http.send("PUT", path("/api/remote-wallets", id, "receive-action"),
                                   json: Body(feeBps: feeBps, baseFeeSats: baseFeeSats, enabled: enabled, destinations: destinations))
    }

    public func setForwarding(_ id: String, enabled: Bool) async throws -> ReceiveAction {
        try await http.send("PATCH", path("/api/remote-wallets", id, "receive-action"), json: ["enabled": enabled])
    }

    public func forceForwarding(_ id: String) async throws {
        _ = try await http.send("POST", path("/api/remote-wallets", id, "receive-action", "force"), as: JSONValue.self)
    }

    public func forwardingReceipts(_ id: String, cursor: String? = nil) async throws -> ReceiptPage {
        try await http.get(path("/api/remote-wallets", id, "forwarding-receipts") + "?limit=30" + (cursor.map { "&cursor=\($0)" } ?? ""))
    }

    public func retryReceipt(_ id: String, receiptId: String) async throws {
        _ = try await http.send("POST", path("/api/remote-wallets", id, "forwarding-receipts", receiptId, "retry"), json: [String: String](), as: JSONValue.self)
    }

    public func notifications(_ id: String) async throws -> [WalletNotification] {
        try await http.get(path("/api/remote-wallets", id, "notifications"), as: NotificationList.self).notifications
    }

    public func createWebhookNotification(_ id: String, name: String, action: String, url: String) async throws -> [WalletNotification] {
        try await http.send("POST", path("/api/remote-wallets", id, "notifications"),
                            json: ["name": name, "channel": "WEBHOOK", "action": action, "webhookUrl": url], as: NotificationList.self).notifications
    }

    public func createNostrNotification(_ id: String, name: String, action: String, kind: Int, pTag: String, relays: [String], nip44: Bool) async throws -> [WalletNotification] {
        let body: JSONValue = ["name": .string(name), "channel": "NOSTR", "action": .string(action), "kind": .number(Double(kind)),
                               "pTag": .string(pTag), "relays": .array(relays.map(JSONValue.string)), "nip44": .bool(nip44)]
        return try await http.send("POST", path("/api/remote-wallets", id, "notifications"), json: body, as: NotificationList.self).notifications
    }

    public func setNotification(_ id: String, notificationId: String, enabled: Bool) async throws -> [WalletNotification] {
        try await http.send("PATCH", path("/api/remote-wallets", id, "notifications", notificationId), json: ["enabled": enabled],
                            as: NotificationList.self).notifications
    }

    public func retryDelivery(_ id: String, deliveryId: String) async throws {
        _ = try await http.send("POST", path("/api/remote-wallets", id, "notification-deliveries", deliveryId, "retry"), as: JSONValue.self)
    }

    // MARK: passkeys & connected apps

    public func passkeyRegistrationOptions(authenticated: Bool) async throws -> JSONValue {
        try await http.send("POST", "/api/auth/passkey/registration/options", json: [String: String](), auth: authenticated ? .bearer : .none,
                            as: JSONValue.self)["options"] ?? .null
    }

    public func verifyPasskeyRegistration(_ body: JSONValue, authenticated: Bool) async throws {
        _ = try await http.send("POST", "/api/auth/passkey/registration/verify", json: body, auth: authenticated ? .bearer : .none, as: JSONValue.self)
    }

    public func passkeys() async throws -> [PasskeyCredential] {
        try await http.get("/api/auth/passkey/credentials", as: PasskeyCredentialList.self).credentials
    }

    public func renamePasskey(_ id: String, label: String) async throws {
        _ = try await http.send("PATCH", path("/api/auth/passkey/credentials", id), json: ["label": label], as: JSONValue.self)
    }

    public func deletePasskey(_ id: String) async throws {
        _ = try await http.send("DELETE", path("/api/auth/passkey/credentials", id), as: JSONValue.self)
    }

    public func oauthGrants() async throws -> [OAuthGrant] {
        struct R: Decodable { let grants: [OAuthGrant] }
        return try await http.get("/api/oauth/grants", as: R.self).grants
    }

    public func revokeGrant(_ id: String) async throws {
        _ = try await http.send("DELETE", path("/api/oauth/grants", id), as: JSONValue.self)
    }
}
