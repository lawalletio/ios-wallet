import Foundation

/// Parsed `nostr+walletconnect://<walletPubkey>?relay=…&secret=…&lud16=…`.
public struct NWCConnection: Sendable, Hashable {
    public let walletPubkey: String
    public let relays: [URL]
    public let secret: Data
    public let lud16: String?
    public let uri: String

    public init(uri: String) throws {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let schemeEnd = trimmed.range(of: "://"),
              ["nostr+walletconnect", "nostrwalletconnect"].contains(trimmed[..<schemeEnd.lowerBound].lowercased()),
              let comps = URLComponents(string: "https://" + trimmed[schemeEnd.upperBound...]),
              let host = comps.host, host.count == 64, Data(hex: host) != nil
        else { throw NWCError.invalidURI }
        let items = comps.queryItems ?? []
        let relays = items.filter { $0.name == "relay" }.compactMap { $0.value.flatMap(URL.init(string:)) }
        guard let secretHex = items.first(where: { $0.name == "secret" })?.value, let secret = Data(hex: secretHex),
              secret.count == 32, !relays.isEmpty
        else { throw NWCError.invalidURI }
        walletPubkey = host.lowercased()
        self.relays = relays
        self.secret = secret
        lud16 = items.first { $0.name == "lud16" }?.value
        self.uri = trimmed
    }

    /// Display name: `name` or `lud16` query param.
    public var displayName: String? {
        let items = URLComponents(string: uri.replacingOccurrences(of: "nostr+walletconnect://", with: "https://"))?.queryItems
        return items?.first { $0.name == "name" }?.value ?? lud16
    }
}

public enum NWCError: Error, Equatable, LocalizedError {
    case invalidURI
    case wallet(code: String, message: String)
    case timeout
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .invalidURI: "Invalid Nostr Wallet Connect URI"
        case .wallet(_, let message): message
        case .timeout: "The wallet did not respond in time"
        case .badResponse: "The wallet sent an invalid response"
        }
    }
}

public struct NWCInfo: Sendable, Equatable {
    public let alias: String?
    public let methods: [String]
    public let notifications: [String]
    public let encryptions: [String]
}

public struct NWCTransaction: Sendable, Hashable, Codable, Identifiable {
    public enum Kind: String, Sendable, Codable { case incoming, outgoing }
    public enum State: String, Sendable, Codable { case settled, pending, failed }

    public let type: Kind
    public let amountSats: Int
    public let feesPaidSats: Int
    public let description: String
    public let paymentHash: String
    public let preimage: String?
    public let invoice: String?
    public let settledAt: Date?
    public let createdAt: Date
    public let walletState: State?

    public var id: String { paymentHash + type.rawValue }
    public var state: State { walletState ?? (settledAt != nil ? .settled : .pending) }

    public init(type: Kind, amountSats: Int, feesPaidSats: Int = 0, description: String = "", paymentHash: String,
                preimage: String? = nil, invoice: String? = nil, settledAt: Date? = nil, createdAt: Date, walletState: State? = nil) {
        self.type = type
        self.amountSats = amountSats
        self.feesPaidSats = feesPaidSats
        self.description = description
        self.paymentHash = paymentHash
        self.preimage = preimage
        self.invoice = invoice
        self.settledAt = settledAt
        self.createdAt = createdAt
        self.walletState = walletState
    }

    /// Normalizes a raw NIP-47 transaction object (msats → sats, unix seconds → Date).
    public init?(raw: JSONValue) {
        guard let hash = raw["payment_hash"]?.string?.trimmingCharacters(in: .whitespaces), !hash.isEmpty else { return nil }
        type = raw["type"]?.string == "outgoing" ? .outgoing : .incoming
        amountSats = (raw["amount"]?.int ?? 0) / 1000
        feesPaidSats = (raw["fees_paid"]?.int ?? 0) / 1000
        description = raw["description"]?.string ?? ""
        paymentHash = hash
        preimage = raw["preimage"]?.string
        invoice = raw["invoice"]?.string
        settledAt = raw["settled_at"]?.double.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
        createdAt = Date(timeIntervalSince1970: raw["created_at"]?.double ?? 0)
        walletState = raw["state"]?.string.flatMap(State.init(rawValue:))
    }
}

public struct NWCNotification: Sendable, Equatable {
    public let type: String
    public let transaction: NWCTransaction
}

public struct NWCMadeInvoice: Sendable, Equatable {
    public let bolt11: String
    public let paymentHash: String
    public let amountSats: Int
    public let description: String
    public let expiresAt: Date?
}

/// NIP-47 client. One per connection string; requests go to the first relay.
/// ponytail: single relay — every NWC wallet we target (LNCurl, Alby Hub) advertises one; fan out if that changes.
public actor NWCClient {
    public let connection: NWCConnection
    private let keys: NostrKeys
    private var info: NWCInfo?

    public init(connection: NWCConnection) throws {
        self.connection = connection
        keys = try NostrKeys(secret: connection.secret)
    }

    public init(uri: String) throws { try self.init(connection: NWCConnection(uri: uri)) }

    private var relayURL: URL { connection.relays[0] }
    public var clientPubkey: String { keys.publicKey }

    public func getInfo() async throws -> NWCInfo {
        if let info, info.alias != nil { return info }
        let base = await infoEvent()
        guard let r = try? await request("get_info", [:], timeout: .seconds(15)) else { return base }
        let m = r["methods"]?.array?.compactMap(\.string) ?? []
        let n = r["notifications"]?.array?.compactMap(\.string) ?? []
        let resolved = NWCInfo(alias: r["alias"]?.string ?? "", methods: m.isEmpty ? base.methods : m,
                               notifications: n.isEmpty ? base.notifications : n, encryptions: base.encryptions)
        info = resolved
        return resolved
    }

    /// The wallet's kind-13194 info event (methods + supported encryptions), fetched once.
    private func infoEvent() async -> NWCInfo {
        if let info { return info }
        let relay = await Relay.shared(relayURL)
        let events = await relay.query([["kinds": [13194], "authors": [.string(connection.walletPubkey)], "limit": 1]], timeout: .seconds(6))
        let ev = events.max { $0.created_at < $1.created_at }
        let resolved = NWCInfo(alias: nil,
                               methods: ev?.content.split(whereSeparator: \.isWhitespace).map(String.init) ?? [],
                               notifications: ev?.tag("notifications")?.split(separator: " ").map(String.init) ?? [],
                               encryptions: ev?.tag("encryption")?.split(separator: " ").map(String.init) ?? ["nip04"])
        info = resolved
        return resolved
    }

    private func encrypt(_ s: String, nip44: Bool) throws -> String {
        nip44 ? try NIP44.encrypt(s, keys: keys, peer: connection.walletPubkey) : try NIP04.encrypt(s, keys: keys, peer: connection.walletPubkey)
    }

    private func decrypt(_ s: String) throws -> String {
        s.contains("?iv=") ? try NIP04.decrypt(s, keys: keys, peer: connection.walletPubkey)
            : try NIP44.decrypt(s, keys: keys, peer: connection.walletPubkey)
    }

    /// Raw NIP-47 request → `result` object. Throws `NWCError.wallet` on an `error` response.
    /// Reads may be re-sent once if the socket turns out dead; payments and invoices never are (a request that reached
    /// the wallet before the drop must not run twice).
    private static let idempotent: Set<String> = ["get_info", "get_balance", "lookup_invoice", "list_transactions"]

    public func request(_ method: String, _ params: JSONValue, timeout: Duration = .seconds(45)) async throws -> JSONValue {
        let nip44 = await infoEvent().encryptions.contains("nip44_v2")
        let body = try JSONValue.object(["method": .string(method), "params": params]).data()
        var tags = [["p", connection.walletPubkey]]
        if nip44 { tags.append(["encryption", "nip44_v2"]) }
        let ev = try NostrEvent.sign(UnsignedEvent(kind: 23194, tags: tags, content: encrypt(String(decoding: body, as: UTF8.self), nip44: nip44)), with: keys)
        let relay = await Relay.shared(relayURL)
        let stream = await relay.subscribe([["kinds": [23195], "authors": [.string(connection.walletPubkey)], "#e": [.string(ev.id)]]])
        do { try await relay.publish(ev) } catch RelayError.notConnected where Self.idempotent.contains(method) {
            try await relay.publish(ev)
        }
        let wallet = connection.walletPubkey
        let response: NostrEvent = try await withTimeout(timeout) {
            for await r in stream where r.pubkey == wallet && r.tag("e") == ev.id { return r }
            throw NWCError.timeout
        }
        guard let json = try? JSONValue.parse(Data(decrypt(response.content).utf8)) else { throw NWCError.badResponse }
        if let err = json["error"], !err.isNull {
            throw NWCError.wallet(code: err["code"]?.string ?? "INTERNAL", message: err["message"]?.string ?? "Wallet error")
        }
        return json["result"] ?? .null
    }

    // MARK: typed methods

    public func getBalanceSats() async throws -> Int {
        (try await request("get_balance", [:], timeout: .seconds(20))["balance"]?.int ?? 0) / 1000
    }

    /// `amountSats` only for zero-amount invoices.
    public func payInvoice(_ invoice: String, amountSats: Int? = nil) async throws -> (preimage: String, feesPaidSats: Int) {
        var params: [String: JSONValue] = ["invoice": .string(invoice)]
        if let amountSats { params["amount"] = .number(Double(amountSats * 1000)) }
        let r = try await request("pay_invoice", .object(params), timeout: .seconds(90))
        return (r["preimage"]?.string ?? "", (r["fees_paid"]?.int ?? 0) / 1000)
    }

    public func makeInvoice(amountSats: Int, description: String = "") async throws -> NWCMadeInvoice {
        let r = try await request("make_invoice", ["amount": .number(Double(amountSats * 1000)), "description": .string(description)])
        guard let bolt11 = r["invoice"]?.string else { throw NWCError.badResponse }
        return NWCMadeInvoice(bolt11: bolt11, paymentHash: r["payment_hash"]?.string ?? Bolt11.decode(bolt11)?.paymentHash ?? "",
                              amountSats: (r["amount"]?.int ?? amountSats * 1000) / 1000,
                              description: r["description"]?.string ?? description,
                              expiresAt: r["expires_at"]?.double.map(Date.init(timeIntervalSince1970:)))
    }

    public func lookupInvoice(paymentHash: String) async throws -> NWCTransaction? {
        NWCTransaction(raw: try await request("lookup_invoice", ["payment_hash": .string(paymentHash)], timeout: .seconds(20)))
    }

    public func listTransactions(limit: Int = 20, until: Date? = nil, from: Date? = nil, type: NWCTransaction.Kind? = nil) async throws -> [NWCTransaction] {
        var p: [String: JSONValue] = ["limit": .number(Double(limit))]
        if let until { p["until"] = .number(until.timeIntervalSince1970.rounded(.down)) }
        if let from { p["from"] = .number(from.timeIntervalSince1970.rounded(.down)) }
        if let type { p["type"] = .string(type.rawValue) }
        let r = try await request("list_transactions", .object(p), timeout: .seconds(30))
        return r["transactions"]?.array?.compactMap(NWCTransaction.init(raw:)) ?? []
    }

    /// NIP-47 notifications (`payment_received` / `payment_sent`), deduped across the nip04 and nip44 kinds.
    public func notifications() async -> AsyncStream<NWCNotification> {
        let relay = await Relay.shared(relayURL)
        // Only events published from now on: a look-back window makes the relay replay recent notifications, which the
        // app would re-announce (and briefly re-add to the balance) right after launch or a reconnect.
        let since = Int(Date().timeIntervalSince1970)
        let events = await relay.subscribe([["kinds": [23196, 23197], "authors": [.string(connection.walletPubkey)],
                                              "#p": [.string(keys.publicKey)], "since": .number(Double(since))]])
        let keys = keys, wallet = connection.walletPubkey
        return AsyncStream { cont in
            let task = Task {
                var seen = Set<String>()
                for await ev in events {
                    let plain = ev.kind == 23197 ? try? NIP44.decrypt(ev.content, keys: keys, peer: wallet)
                        : try? NIP04.decrypt(ev.content, keys: keys, peer: wallet)
                    guard let plain, let json = try? JSONValue.parse(Data(plain.utf8)), let type = json["notification_type"]?.string,
                          let raw = json["notification"], let tx = NWCTransaction(raw: raw) else { continue }
                    guard seen.insert(type + tx.paymentHash).inserted else { continue }
                    cont.yield(NWCNotification(type: type, transaction: tx))
                }
                cont.finish()
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}
