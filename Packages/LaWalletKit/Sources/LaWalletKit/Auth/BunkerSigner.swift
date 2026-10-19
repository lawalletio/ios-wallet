import Foundation

/// Persistable NIP-46 session: our local client key + the remote signer it is paired with.
public struct BunkerSession: Codable, Sendable, Equatable {
    public let clientSecretHex: String
    public let remotePubkey: String
    public let relays: [URL]
    public let userPubkey: String
}

public enum BunkerError: Error, Equatable, LocalizedError {
    case invalidURI, rejected(String), authRequired(URL)
    public var errorDescription: String? {
        switch self {
        case .invalidURI: "Invalid bunker URI"
        case .rejected(let m): m.isEmpty ? "The remote signer rejected the request" : m
        case .authRequired(let url): "Approve the request in your signer: \(url.absoluteString)"
        }
    }
}

/// NIP-46 remote signer (kind 24133, NIP-44 with NIP-04 fallback on decrypt).
public actor BunkerSigner: NostrSigner {
    public nonisolated let session: BunkerSession
    private let clientKeys: NostrKeys
    /// Called with the signer's `auth_url` challenge (open it in a browser); the request keeps waiting.
    public var onAuthURL: (@Sendable (URL) -> Void)?

    public init(session: BunkerSession) throws {
        self.session = session
        clientKeys = try NostrKeys(secret: Data(hex: session.clientSecretHex) ?? Data())
    }

    public func setAuthHandler(_ h: (@Sendable (URL) -> Void)?) { onAuthURL = h }

    public nonisolated func publicKey() async throws -> String { session.userPubkey }

    public func sign(_ event: UnsignedEvent) async throws -> NostrEvent {
        let template = try String(decoding: JSONEncoder().encode(event), as: UTF8.self)
        let result = try await Self.rpc(method: "sign_event", params: [template], clientKeys: clientKeys,
                                        remote: session.remotePubkey, relays: session.relays, onAuth: onAuthURL)
        let ev = try JSONDecoder().decode(NostrEvent.self, from: Data(result.utf8))
        guard ev.isValid, ev.pubkey == session.userPubkey else { throw BunkerError.rejected("Signer returned an invalid event") }
        return ev
    }

    // MARK: pairing

    /// `bunker://<remote-pubkey>?relay=…&secret=…`
    public static func connect(bunkerURI: String, onAuth: (@Sendable (URL) -> Void)? = nil) async throws -> BunkerSigner {
        guard let comps = URLComponents(string: bunkerURI.trimmingCharacters(in: .whitespacesAndNewlines)),
              comps.scheme == "bunker", let remote = comps.host, remote.count == 64 else { throw BunkerError.invalidURI }
        let relays = (comps.queryItems ?? []).filter { $0.name == "relay" }.compactMap { $0.value.flatMap(URL.init(string:)) }
        guard !relays.isEmpty else { throw BunkerError.invalidURI }
        let secret = comps.queryItems?.first { $0.name == "secret" }?.value ?? ""
        let client = NostrKeys.generate()
        _ = try await rpc(method: "connect", params: [remote, secret], clientKeys: client, remote: remote, relays: relays, onAuth: onAuth)
        let user = try await rpc(method: "get_public_key", params: [], clientKeys: client, remote: remote, relays: relays, onAuth: onAuth)
        return try BunkerSigner(session: BunkerSession(clientSecretHex: client.secret.hex, remotePubkey: remote, relays: relays, userPubkey: user))
    }

    /// Builds a `nostrconnect://` URI for the signer app to scan.
    public static func nostrConnectURI(clientKeys: NostrKeys, relays: [URL], secret: String, appName: String) -> String {
        var comps = URLComponents()
        comps.scheme = "nostrconnect"
        comps.host = clientKeys.publicKey
        comps.queryItems = relays.map { URLQueryItem(name: "relay", value: $0.absoluteString) }
            + [URLQueryItem(name: "secret", value: secret), URLQueryItem(name: "name", value: appName),
               URLQueryItem(name: "perms", value: "sign_event:27235,sign_event:22242,get_public_key")]
        return comps.string ?? ""
    }

    /// Waits for a signer to answer a `nostrconnect://` QR, then fetches the user pubkey.
    public static func awaitNostrConnect(clientKeys: NostrKeys, relays: [URL], secret: String,
                                         timeout: Duration = .seconds(300)) async throws -> BunkerSigner {
        let relay = await Relay.shared(relays[0])
        let stream = await relay.subscribe([["kinds": [24133], "#p": [.string(clientKeys.publicKey)],
                                             "since": .number((Date().timeIntervalSince1970 - 10).rounded(.down))]])
        let remote: String = try await withTimeout(timeout) {
            for await ev in stream {
                guard let plain = decrypt(ev.content, keys: clientKeys, peer: ev.pubkey),
                      let json = try? JSONValue.parse(Data(plain.utf8)), json["result"]?.string == secret || json["result"]?.string == "ack"
                else { continue }
                return ev.pubkey
            }
            throw RelayError.timeout
        }
        let user = try await rpc(method: "get_public_key", params: [], clientKeys: clientKeys, remote: remote, relays: relays, onAuth: nil)
        return try BunkerSigner(session: BunkerSession(clientSecretHex: clientKeys.secret.hex, remotePubkey: remote, relays: relays, userPubkey: user))
    }

    // MARK: transport

    private static func decrypt(_ content: String, keys: NostrKeys, peer: String) -> String? {
        content.contains("?iv=") ? try? NIP04.decrypt(content, keys: keys, peer: peer) : try? NIP44.decrypt(content, keys: keys, peer: peer)
    }

    static func rpc(method: String, params: [String], clientKeys: NostrKeys, remote: String, relays: [URL],
                    onAuth: (@Sendable (URL) -> Void)?, timeout: Duration = .seconds(120)) async throws -> String {
        let id = Data.random(8).hex
        let body = try JSONValue.object(["id": .string(id), "method": .string(method), "params": .array(params.map(JSONValue.string))]).data()
        let content = try NIP44.encrypt(String(decoding: body, as: UTF8.self), keys: clientKeys, peer: remote)
        let ev = try NostrEvent.sign(UnsignedEvent(kind: 24133, tags: [["p", remote]], content: content), with: clientKeys)
        let relay = await Relay.shared(relays[0])
        let stream = await relay.subscribe([["kinds": [24133], "authors": [.string(remote)], "#p": [.string(clientKeys.publicKey)],
                                             "since": .number(Double(ev.created_at - 5))]])
        try await relay.publish(ev)
        return try await withTimeout(timeout) {
            for await r in stream {
                guard let plain = decrypt(r.content, keys: clientKeys, peer: remote),
                      let json = try? JSONValue.parse(Data(plain.utf8)), json["id"]?.string == id else { continue }
                if json["result"]?.string == "auth_url", let u = json["error"]?.string.flatMap(URL.init(string:)) {
                    onAuth?(u)
                    continue
                }
                if let err = json["error"]?.string, !err.isEmpty { throw BunkerError.rejected(err) }
                return json["result"]?.string ?? ""
            }
            throw RelayError.timeout
        }
    }
}
