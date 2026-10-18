import Foundation

/// BIP-173 bech32 (not bech32m) — used by NIP-19, LNURL and BOLT11.
public enum Bech32 {
    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let rev: [Character: UInt8] = Dictionary(
        uniqueKeysWithValues: charset.enumerated().map { ($1, UInt8($0)) }
    )

    public enum Error: Swift.Error { case invalid }

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        let gen: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var chk: UInt32 = 1
        for v in values {
            let top = chk >> 25
            chk = (chk & 0x1ffffff) << 5 ^ UInt32(v)
            for i in 0..<5 where (top >> i) & 1 == 1 { chk ^= gen[i] }
        }
        return chk
    }

    private static func expand(_ hrp: String) -> [UInt8] {
        let b = Array(hrp.utf8)
        return b.map { $0 >> 5 } + [0] + b.map { $0 & 31 }
    }

    /// Decodes to (hrp, 5-bit words). `limit` defaults high enough for invoices/LNURLs.
    public static func decode(_ string: String, limit: Int = 4096) throws -> (hrp: String, words: [UInt8]) {
        guard string.count >= 8, string.count <= limit else { throw Error.invalid }
        let lower = string.lowercased()
        guard lower == string || string.uppercased() == string else { throw Error.invalid }
        guard let sep = lower.lastIndex(of: "1") else { throw Error.invalid }
        let hrp = String(lower[..<sep])
        guard !hrp.isEmpty else { throw Error.invalid }
        var words: [UInt8] = []
        for c in lower[lower.index(after: sep)...] {
            guard let v = rev[c] else { throw Error.invalid }
            words.append(v)
        }
        guard words.count >= 6, polymod(expand(hrp) + words) == 1 else { throw Error.invalid }
        return (hrp, Array(words.dropLast(6)))
    }

    public static func encode(hrp: String, words: [UInt8]) -> String {
        let values = expand(hrp) + words + [0, 0, 0, 0, 0, 0]
        let mod = polymod(values) ^ 1
        let checksum = (0..<6).map { UInt8((mod >> (5 * (5 - $0))) & 31) }
        return hrp + "1" + String((words + checksum).map { charset[Int($0)] })
    }

    public static func convertBits(_ data: [UInt8], from: Int, to: Int, pad: Bool) throws -> [UInt8] {
        var acc = 0, bits = 0
        var out: [UInt8] = []
        let maxv = (1 << to) - 1
        for value in data {
            guard Int(value) >> from == 0 else { throw Error.invalid }
            acc = (acc << from) | Int(value)
            bits += from
            while bits >= to {
                bits -= to
                out.append(UInt8((acc >> bits) & maxv))
            }
        }
        if pad {
            if bits > 0 { out.append(UInt8((acc << (to - bits)) & maxv)) }
        } else if bits >= from || ((acc << (to - bits)) & maxv) != 0 {
            throw Error.invalid
        }
        return out
    }

    public static func encode(hrp: String, data: Data) -> String {
        encode(hrp: hrp, words: (try? convertBits(Array(data), from: 8, to: 5, pad: true)) ?? [])
    }

    public static func decodeData(_ string: String, limit: Int = 4096) throws -> (hrp: String, data: Data) {
        let (hrp, words) = try decode(string, limit: limit)
        return (hrp, Data(try convertBits(words, from: 5, to: 8, pad: false)))
    }
}

/// NIP-19 bare keys.
public enum NIP19 {
    public static func npub(_ pubkeyHex: String) -> String {
        Bech32.encode(hrp: "npub", data: Data(hex: pubkeyHex) ?? Data())
    }

    public static func nsec(_ secret: Data) -> String { Bech32.encode(hrp: "nsec", data: secret) }

    /// Accepts `npub1…` or 64-char hex; returns hex.
    public static func pubkeyHex(_ input: String) -> String? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count == 64, Data(hex: s) != nil { return s.lowercased() }
        guard let (hrp, data) = try? Bech32.decodeData(s), hrp == "npub", data.count == 32 else { return nil }
        return data.hex
    }

    /// Accepts `nsec1…` or 64-char hex; returns 32 bytes.
    public static func secret(_ input: String) -> Data? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count == 64, let d = Data(hex: s) { return d }
        guard let (hrp, data) = try? Bech32.decodeData(s), hrp == "nsec", data.count == 32 else { return nil }
        return data
    }
}
