import CommonCrypto
import CryptoKit
import Foundation

/// NIP-04 (legacy): AES-256-CBC keyed by the raw ECDH X coordinate.
public enum NIP04 {
    public static func encrypt(_ plaintext: String, keys: NostrKeys, peer: String, iv: Data = .random(16)) throws -> String {
        let key = try keys.sharedX(with: peer)
        let ct = try aes(CCOperation(kCCEncrypt), key: key, iv: iv, data: Data(plaintext.utf8))
        return ct.base64EncodedString() + "?iv=" + iv.base64EncodedString()
    }

    public static func decrypt(_ payload: String, keys: NostrKeys, peer: String) throws -> String {
        let parts = payload.components(separatedBy: "?iv=")
        guard parts.count == 2, let ct = Data(base64Encoded: parts[0]), let iv = Data(base64Encoded: parts[1]), iv.count == 16
        else { throw NostrError.encryption("bad nip04 payload") }
        let key = try keys.sharedX(with: peer)
        let pt = try aes(CCOperation(kCCDecrypt), key: key, iv: iv, data: ct)
        guard let s = String(data: pt, encoding: .utf8) else { throw NostrError.encryption("bad utf8") }
        return s
    }

    private static func aes(_ op: CCOperation, key: Data, iv: Data, data: Data) throws -> Data {
        var out = Data(count: data.count + kCCBlockSizeAES128)
        var moved = 0
        let outCount = out.count
        let status = out.withUnsafeMutableBytes { o in
            data.withUnsafeBytes { d in
                key.withUnsafeBytes { k in
                    iv.withUnsafeBytes { i in
                        CCCrypt(op, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                k.baseAddress, key.count, i.baseAddress, d.baseAddress, data.count,
                                o.baseAddress, outCount, &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw NostrError.encryption("aes \(status)") }
        return out.prefix(moved)
    }
}

/// NIP-44 v2: HKDF + ChaCha20 + HMAC-SHA256 with power-of-two-ish padding.
public enum NIP44 {
    public static func conversationKey(keys: NostrKeys, peer: String) throws -> Data {
        let shared = try keys.sharedX(with: peer)
        let prk = HKDF<SHA256>.extract(inputKeyMaterial: SymmetricKey(data: shared), salt: Data("nip44-v2".utf8))
        return Data(prk)
    }

    public static func messageKeys(conversationKey: Data, nonce: Data) -> (chachaKey: Data, chachaNonce: Data, hmacKey: Data) {
        let okm = HKDF<SHA256>.expand(pseudoRandomKey: SymmetricKey(data: conversationKey), info: nonce, outputByteCount: 76)
        let bytes = okm.withUnsafeBytes { Data($0) }
        return (bytes[0..<32], bytes[32..<44], bytes[44..<76])
    }

    public static func paddedLength(_ len: Int) -> Int {
        if len <= 32 { return 32 }
        let nextPower = 1 << (Int.bitWidth - (len - 1).leadingZeroBitCount)
        let chunk = nextPower <= 256 ? 32 : nextPower / 8
        return chunk * ((len - 1) / chunk + 1)
    }

    public static func encrypt(_ plaintext: String, conversationKey: Data, nonce: Data = .random(32)) throws -> String {
        let pt = Data(plaintext.utf8)
        guard (1...65535).contains(pt.count) else { throw NostrError.encryption("invalid plaintext length") }
        var padded = Data([UInt8(pt.count >> 8), UInt8(pt.count & 0xff)]) + pt
        padded += Data(count: paddedLength(pt.count) - pt.count)
        let k = messageKeys(conversationKey: conversationKey, nonce: nonce)
        let ct = ChaCha20.xor(key: k.chachaKey, nonce: k.chachaNonce, data: padded)
        let mac = Data(HMAC<SHA256>.authenticationCode(for: nonce + ct, using: SymmetricKey(data: k.hmacKey)))
        return (Data([2]) + nonce + ct + mac).base64EncodedString()
    }

    public static func decrypt(_ payload: String, conversationKey: Data) throws -> String {
        guard !payload.isEmpty, payload.first != "#", (132...87472).contains(payload.count),
              let data = Data(base64Encoded: payload), (99...65603).contains(data.count), data.first == 2
        else { throw NostrError.encryption("invalid payload") }
        let nonce = data[1..<33], ct = data[33..<(data.count - 32)], mac = data.suffix(32)
        let k = messageKeys(conversationKey: conversationKey, nonce: Data(nonce))
        guard HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: Data(nonce) + ct, using: SymmetricKey(data: k.hmacKey))
        else { throw NostrError.encryption("invalid MAC") }
        let padded = ChaCha20.xor(key: k.chachaKey, nonce: k.chachaNonce, data: Data(ct))
        let len = Int(padded[0]) << 8 | Int(padded[1])
        guard len >= 1, padded.count == 2 + paddedLength(len), padded.count >= 2 + len,
              let s = String(data: padded[2..<(2 + len)], encoding: .utf8)
        else { throw NostrError.encryption("invalid padding") }
        return s
    }

    public static func encrypt(_ plaintext: String, keys: NostrKeys, peer: String) throws -> String {
        try encrypt(plaintext, conversationKey: conversationKey(keys: keys, peer: peer))
    }

    public static func decrypt(_ payload: String, keys: NostrKeys, peer: String) throws -> String {
        try decrypt(payload, conversationKey: conversationKey(keys: keys, peer: peer))
    }
}

/// RFC 8439 ChaCha20 stream (counter starts at 0). CryptoKit only exposes ChaChaPoly.
enum ChaCha20 {
    static func xor(key: Data, nonce: Data, data: Data) -> Data {
        func words(_ d: Data) -> [UInt32] {
            let b = [UInt8](d)
            return stride(from: 0, to: b.count, by: 4).map {
                UInt32(b[$0]) | UInt32(b[$0 + 1]) << 8 | UInt32(b[$0 + 2]) << 16 | UInt32(b[$0 + 3]) << 24
            }
        }
        let k = words(key), n = words(nonce)
        var out = [UInt8](data)
        var counter: UInt32 = 0
        var offset = 0
        while offset < out.count {
            let block = Self.block(key: k, counter: counter, nonce: n)
            for i in 0..<min(64, out.count - offset) { out[offset + i] ^= block[i] }
            offset += 64
            counter &+= 1
        }
        return Data(out)
    }

    private static func block(key: [UInt32], counter: UInt32, nonce: [UInt32]) -> [UInt8] {
        let initial: [UInt32] = [0x61707865, 0x3320646e, 0x79622d32, 0x6b206574] + key + [counter] + nonce
        var s = initial
        func qr(_ a: Int, _ b: Int, _ c: Int, _ d: Int) {
            s[a] &+= s[b]; s[d] ^= s[a]; s[d] = s[d] << 16 | s[d] >> 16
            s[c] &+= s[d]; s[b] ^= s[c]; s[b] = s[b] << 12 | s[b] >> 20
            s[a] &+= s[b]; s[d] ^= s[a]; s[d] = s[d] << 8 | s[d] >> 24
            s[c] &+= s[d]; s[b] ^= s[c]; s[b] = s[b] << 7 | s[b] >> 25
        }
        for _ in 0..<10 {
            qr(0, 4, 8, 12); qr(1, 5, 9, 13); qr(2, 6, 10, 14); qr(3, 7, 11, 15)
            qr(0, 5, 10, 15); qr(1, 6, 11, 12); qr(2, 7, 8, 13); qr(3, 4, 9, 14)
        }
        var out = [UInt8]()
        out.reserveCapacity(64)
        for i in 0..<16 {
            let v = s[i] &+ initial[i]
            out += [UInt8(v & 0xff), UInt8(v >> 8 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 24)]
        }
        return out
    }
}
