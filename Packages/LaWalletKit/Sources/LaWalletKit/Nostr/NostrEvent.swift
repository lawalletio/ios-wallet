import Foundation
import P256K

public enum NostrError: Error, Equatable {
    case invalidKey, invalidSignature, encryption(String)
}

/// A secp256k1 key pair. `secret` is the 32-byte scalar (nsec).
public struct NostrKeys: Sendable, Equatable {
    public let secret: Data
    public let publicKey: String

    public init(secret: Data) throws {
        guard secret.count == 32,
              let key = try? P256K.Schnorr.PrivateKey(dataRepresentation: secret) else { throw NostrError.invalidKey }
        self.secret = secret
        self.publicKey = Data(key.xonly.bytes).hex
    }

    public init(nsecOrHex: String) throws {
        guard let secret = NIP19.secret(nsecOrHex) else { throw NostrError.invalidKey }
        try self.init(secret: secret)
    }

    public static func generate() -> NostrKeys {
        while true { if let k = try? NostrKeys(secret: .random(32)) { return k } }
    }

    public var nsec: String { NIP19.nsec(secret) }
    public var npub: String { NIP19.npub(publicKey) }

    func schnorrSign(_ message32: Data) throws -> Data {
        let key = try P256K.Schnorr.PrivateKey(dataRepresentation: secret)
        var msg = Array(message32)
        var aux = Array(Data.random(32))
        return try key.signature(message: &msg, auxiliaryRand: &aux, strict: true).dataRepresentation
    }

    /// ECDH shared X coordinate with an x-only peer pubkey (NIP-04 / NIP-44 input).
    public func sharedX(with pubkeyHex: String) throws -> Data {
        guard let x = Data(hex: pubkeyHex), x.count == 32 else { throw NostrError.invalidKey }
        let priv = try P256K.KeyAgreement.PrivateKey(dataRepresentation: secret)
        guard let pub = try? P256K.KeyAgreement.PublicKey(dataRepresentation: Data([0x02]) + x, format: .compressed)
        else { throw NostrError.invalidKey }
        let shared = priv.sharedSecretFromKeyAgreement(with: pub, format: .compressed)
        return shared.withUnsafeBytes { Data($0) }.dropFirst()
    }
}

/// An unsigned event template (what a signer receives).
public struct UnsignedEvent: Codable, Sendable, Equatable {
    public var kind: Int
    public var created_at: Int
    public var tags: [[String]]
    public var content: String

    public init(kind: Int, tags: [[String]] = [], content: String = "", createdAt: Int = Int(Date().timeIntervalSince1970)) {
        self.kind = kind
        self.created_at = createdAt
        self.tags = tags
        self.content = content
    }
}

public struct NostrEvent: Codable, Sendable, Equatable {
    public let id: String
    public let pubkey: String
    public let created_at: Int
    public let kind: Int
    public let tags: [[String]]
    public let content: String
    public let sig: String

    public init(id: String, pubkey: String, created_at: Int, kind: Int, tags: [[String]], content: String, sig: String) {
        self.id = id
        self.pubkey = pubkey
        self.created_at = created_at
        self.kind = kind
        self.tags = tags
        self.content = content
        self.sig = sig
    }

    /// NIP-01 canonical serialization (escapes exactly `" \ \n \r \t \b \f`, other C0 as \u00XX).
    public static func serialize(pubkey: String, createdAt: Int, kind: Int, tags: [[String]], content: String) -> String {
        let tagsJSON = "[" + tags.map { "[" + $0.map(jsonString).joined(separator: ",") + "]" }.joined(separator: ",") + "]"
        return "[0,\"\(pubkey)\",\(createdAt),\(kind),\(tagsJSON),\(jsonString(content))]"
    }

    public static func computeId(pubkey: String, createdAt: Int, kind: Int, tags: [[String]], content: String) -> String {
        Data(serialize(pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content).utf8).sha256.hex
    }

    public static func sign(_ t: UnsignedEvent, with keys: NostrKeys) throws -> NostrEvent {
        let id = computeId(pubkey: keys.publicKey, createdAt: t.created_at, kind: t.kind, tags: t.tags, content: t.content)
        let sig = try keys.schnorrSign(Data(hex: id)!)
        return NostrEvent(id: id, pubkey: keys.publicKey, created_at: t.created_at, kind: t.kind, tags: t.tags, content: t.content, sig: sig.hex)
    }

    public var isValid: Bool {
        guard id == Self.computeId(pubkey: pubkey, createdAt: created_at, kind: kind, tags: tags, content: content),
              let pub = Data(hex: pubkey), pub.count == 32,
              let sigData = Data(hex: sig), let signature = try? P256K.Schnorr.SchnorrSignature(dataRepresentation: sigData)
        else { return false }
        var msg = Array(Data(hex: id)!)
        return P256K.Schnorr.XonlyKey(dataRepresentation: pub).isValid(signature, for: &msg)
    }

    public func tag(_ name: String) -> String? { tags.first { $0.first == name && $0.count > 1 }?[1] }

    /// Compact JSON for the wire (`["EVENT", …]`, NIP-98 header, NIP-46 params).
    public var json: String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.withoutEscapingSlashes]
        return String(data: try! enc.encode(self), encoding: .utf8)!
    }
}

func jsonString(_ s: String) -> String {
    var out = "\""
    for scalar in s.unicodeScalars {
        switch scalar {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        case "\u{08}": out += "\\b"
        case "\u{0C}": out += "\\f"
        default:
            if scalar.value < 0x20 { out += String(format: "\\u%04x", scalar.value) } else { out.unicodeScalars.append(scalar) }
        }
    }
    return out + "\""
}
