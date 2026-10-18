import CryptoKit
import Foundation

public protocol NostrSigner: Sendable {
    func publicKey() async throws -> String
    func sign(_ event: UnsignedEvent) async throws -> NostrEvent
}

public struct LocalSigner: NostrSigner {
    public let keys: NostrKeys
    public init(keys: NostrKeys) { self.keys = keys }
    public func publicKey() async throws -> String { keys.publicKey }
    public func sign(_ event: UnsignedEvent) async throws -> NostrEvent { try NostrEvent.sign(event, with: keys) }
}

/// NIP-98 HTTP auth (kind 27235). `u` must be the instance's public `endpoint` + path + query,
/// and `payload` the sha256 of the exact body bytes sent.
public enum NIP98 {
    public static func template(url: String, method: String, body: Data?) -> UnsignedEvent {
        var tags = [["u", url], ["method", method.uppercased()]]
        if let body, !body.isEmpty { tags.append(["payload", body.sha256.hex]) }
        return UnsignedEvent(kind: 27235, tags: tags)
    }

    public static func header(url: String, method: String, body: Data?, signer: NostrSigner) async throws -> String {
        "Nostr " + (try await token(url: url, method: method, body: body, signer: signer))
    }

    /// Bare base64 event, used for the SSE `?token=` param (URL without its query, GET, no payload).
    public static func token(url: String, method: String = "GET", body: Data? = nil, signer: NostrSigner) async throws -> String {
        let ev = try await signer.sign(template(url: url, method: method, body: body))
        return Data(ev.json.utf8).base64EncodedString()
    }
}

/// Kind-22242 proof of key control (passkey registration, identity linking).
public enum KeyProof {
    public static func sign(challenge: String, signer: NostrSigner) async throws -> NostrEvent {
        try await signer.sign(UnsignedEvent(kind: 22242, tags: [["challenge", challenge]]))
    }
}

/// Passkey → Nostr identity. ⚠️ Consensus-critical: must match `apps/web/lib/client/passkey-prf.ts` forever.
public enum PasskeyPRF {
    /// sha256("lawallet-nsec-prf-v1")
    public static let saltHex = "8ee22949c1045c627e14236f1d06cf730b46b4cf309cbf4ede25a446cf33ad8d"
    public static var salt: Data { Data(hex: saltHex)! }
    static let info = Data("lawallet-nsec-v1".utf8)

    public static func deriveSecret(prfOutput: Data) -> Data {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: prfOutput), salt: salt, info: info, outputByteCount: 32)
            .withUnsafeBytes { Data($0) }
    }
}
