import Foundation

// Shapes mirror the apps/web route handlers. Fields the server omits when undefined are optional.

public struct InstanceSettings: Codable, Sendable, Equatable {
    public var domain: String?
    public var endpoint: String?
    public var hasRoot: Bool?
    public var brand_theme: String?
    public var brand_rounding: String?
    public var community_name: String?
    public var logotype_url: String?
    public var isotypo_url: String?
    public var community_cover_url: String?
    public var maintenance_enabled: String?
    public var lncurl_enabled: String?
    public var lncurl_auto_create: String?
    public var social_website: String?
    public var social_nostr: String?

    public init() {}
    public var lncurlAutoCreate: Bool { lncurl_auto_create == "true" }
    public var lncurlEnabled: Bool { lncurl_enabled == "true" }
    public var maintenance: Bool { maintenance_enabled == "true" }
}

public struct CurrencyPrefs: Codable, Sendable, Equatable {
    public var active: [String]
    public var selected: String
    public init(active: [String], selected: String) { self.active = active; self.selected = selected }
}

public struct CurrentUser: Codable, Sendable, Equatable {
    public let userId: String
    public let lightningAddress: String?
    public let nwcString: String
    public let nwcUpdatedAt: String?
    public let effectiveNwcString: String?
    public let primaryAddressMode: String?
    public let primaryUsername: String?
    public let primaryRedirect: String?
    public let currencyPrefs: CurrencyPrefs?
    /// Nil on servers that predate card recovery (hide the Security toggle).
    public let cardRecoveryEnabled: Bool?
    /// Set when a card recovery moved this account to another key, until dismissed.
    public let accountTransfer: AccountTransfer?

    /// `effectiveNwcString || nwcString`, nil when the user has no wallet yet.
    public var nwc: String? {
        if let e = effectiveNwcString, !e.isEmpty { return e }
        return nwcString.isEmpty ? nil : nwcString
    }
}

/// `accountTransfer` on `/api/users/me`: what a card recovery took from this (old) account.
public struct AccountTransfer: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let transferredAt: String
    public let cardTitle: String?
    public let lightningAddresses: [String]
    public let cards: Int
    public let remoteWallets: Int
}

public struct JWTToken: Decodable, Sendable {
    public let token: String
    public let expiresIn: JSONValue
}

public struct JWTInfo: Decodable, Sendable {
    public let valid: Bool
    public let pubkey: String
    public let role: String
    public let permissions: [String]
    public let expiresAt: String
}

public struct CardDesign: Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let imageUrl: String
    public let description: String
}

public struct Card: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let design: CardDesign
    public let createdAt: String
    public let title: String?
    public let lastUsedAt: String?
    public let username: String?
    public let remoteWalletId: String?
    public let defaultRemoteWalletId: String?
    public let kind: String
    public let blocked: Bool?
    public let disabled: Bool?

    public var isActive: Bool { !(blocked ?? false) && !(disabled ?? false) }
}

public struct ActivationPreview: Codable, Sendable, Equatable {
    public struct PreviewCard: Codable, Sendable, Equatable {
        public let id: String
        public let title: String?
        public let kind: String
        public let design: CardDesign
    }
    public let tokenId: String
    public let qrKind: String
    /// `ACTIVATE` | `RECOVER`; missing on older servers (= activate). Never trust the URL's `?tag`.
    public let purpose: String?
    public let status: String
    public let card: PreviewCard
    public var isRecover: Bool { purpose == "RECOVER" }
}

/// `GET /api/activation-tokens/:id/recovery-check` — pre-flight before a RECOVER claim.
public struct RecoveryCheck: Decodable, Sendable, Equatable {
    public struct Side: Decodable, Sendable, Equatable {
        /// Full `user@domain`.
        public let lightningAddresses: [String]
        public let cards: Int
        public let remoteWallets: Int
    }
    public let sameAccount: Bool
    public let mergeRequired: Bool
    public let existing: Side
    public let incoming: Side
}

/// `POST /api/activation-tokens/:id/claim` on a RECOVER token.
public struct RecoveryClaim: Decodable, Sendable, Equatable {
    public let outcome: String
    public let recovery: RecoveredAccount?
    public let needsLightningAddress: Bool?

    /// What came over, or nil when the card was already the caller's (`same-account`: just open the wallet).
    public var recovered: RecoveredAccount? { outcome == "same-account" ? nil : recovery }
}

public struct RecoveredAccount: Decodable, Sendable, Equatable {
    public struct RecoveredCard: Decodable, Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String?
        public let designImageUrl: String?
    }
    public struct RecoveredWallet: Decodable, Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        public let isDefault: Bool
    }
    public let lightningAddresses: [String]
    public let primaryAddress: String?
    public let cards: [RecoveredCard]
    public let remoteWallets: [RecoveredWallet]
    public let vouchers: Int
    public let mergedIntoExisting: Bool

    /// Sum of the balances that loaded (nil = still loading or failed); nil when none did.
    public static func total(_ balances: [Int?]) -> Int? {
        let known = balances.compactMap { $0 }
        return known.isEmpty ? nil : known.reduce(0, +)
    }
}

public struct ActivationClaim: Decodable, Sendable, Equatable {
    public struct Bonuses: Decodable, Sendable, Equatable {
        public struct Sats: Decodable, Sendable, Equatable { public let granted: Bool; public let amountSats: Int? }
        public let freeLightningAddress: Bool
        public let sats: Sats
    }
    public struct ClaimedCard: Decodable, Sendable, Equatable {
        public let id: String
        public let design: CardDesign
        public let title: String?
    }
    public let card: ClaimedCard
    public let bonuses: Bonuses
    public let needsLightningAddress: Bool
}

public struct WalletAddress: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let username: String
    public let mode: String
    public let redirect: String?
    public let remoteWalletId: String?
    public let remoteWalletName: String?
    public let isPrimary: Bool
    public let nwcMode: String
    public var id: String { username }
}

public struct UsernameAvailability: Decodable, Sendable { public let available: Bool; public let username: String }

/// `POST /api/invoices` → `{free:true}` or a payable invoice.
public struct RegistrationInvoice: Decodable, Sendable, Equatable {
    public let free: Bool?
    public let id: String?
    public let bolt11: String?
    public let paymentHash: String?
    public let amountSats: Int?
    public let verify: String?
    public let expiresAt: String?
}

public struct InvoiceClaim: Decodable, Sendable { public let success: Bool; public let lightningAddress: String? }

public struct RemoteWallet: Codable, Sendable, Equatable, Identifiable, Hashable {
    public struct ReceiveCapabilities: Codable, Sendable, Equatable, Hashable {
        public let lud21: Bool
        public let nip57: Bool
        public let receiptPubkey: String?
        public let reason: String?
    }
    public let id: String
    public let name: String
    public let type: String
    public let status: String
    public let isDefault: Bool
    public let createdAt: String
    public let diedAt: String?
    public let diedReason: String?
    public let provider: String?
    public let receiveCapabilities: ReceiveCapabilities?
    public var isLncurl: Bool { provider == "lncurl" }
    public var isActive: Bool { status == "ACTIVE" }
}

public struct ForwardingDestination: Codable, Sendable, Equatable, Hashable {
    public var address: String
    public var allocationBps: Int
    public init(address: String, allocationBps: Int) { self.address = address; self.allocationBps = allocationBps }
}

public struct ReceiveAction: Decodable, Sendable, Equatable {
    public struct Revision: Decodable, Sendable, Equatable {
        public let number: Int
        public let feeBps: Int
        public let baseFeeSats: Double
        public let destinations: [ForwardingDestination]
    }
    public let walletId: String
    public let eligible: Bool
    public let reason: String?
    public let attemptInProgress: Bool
    public let configured: Bool
    public let enabled: Bool
    public let pausedAt: String?
    public let pendingReceipts: Int
    public let pendingAmountMsats: Double
    public let revision: Revision?
}

public struct ForwardingReceipt: Decodable, Sendable, Equatable, Identifiable {
    public struct Leg: Decodable, Sendable, Equatable, Identifiable {
        public let id: String
        public let destination: String
        public let requestedAmountMsats: Double
        public let forwardedAmountMsats: Double?
        public let status: String
        public let lastError: String?
    }
    public let id: String
    public let sourcePaymentHash: String
    public let comment: String?
    public let grossAmountMsats: Double
    public let retainedFeeMsats: Double
    public let forwardedAmountMsats: Double
    public let status: String
    public let lastError: String?
    public let sourceSettledAt: String
    public let createdAt: String
    public let legs: [Leg]
}

public struct ReceiptPage: Decodable, Sendable { public let receipts: [ForwardingReceipt]; public let nextCursor: String? }

public struct WalletNotification: Decodable, Sendable, Equatable, Identifiable {
    public struct Delivery: Decodable, Sendable, Equatable, Identifiable {
        public let id: String
        public let action: String
        public let status: String
        public let attemptCount: Int
        public let lastError: String?
        public let createdAt: String
    }
    public let id: String
    public let name: String
    public let channel: String
    public let action: String
    public let enabled: Bool
    public let pausedAt: String?
    public let webhookUrl: String?
    public let nostrKind: Int?
    public let nostrRecipient: String?
    public let nostrRelays: [String]
    public let nip44: Bool
    public let deliveries: [Delivery]
}

public struct NotificationList: Decodable, Sendable { public let notifications: [WalletNotification] }

public struct PasskeyCredential: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String?
    public let deviceType: String
    public let backedUp: Bool
    public let rpId: String
    public let createdAt: String
    public let lastUsedAt: String?
}

public struct PasskeyCredentialList: Decodable, Sendable {
    public let credentials: [PasskeyCredential]
}

public struct OAuthGrant: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let clientName: String
    public let scopes: [String]
    public let spendLimitSats: Int?
    public let createdAt: String
    public let lastUsedAt: String?
}

public struct NostrProfile: Decodable, Sendable, Equatable {
    public let pubkey: String
    public let npub: String
    public let name: String?
    public let displayName: String?
    public let picture: String?
    public let nip05: String?
    public let lud16: String?
}
