import Foundation

/// Minimal BOLT11 decoder: amount, timestamp, expiry, payment hash, description. No signature check (the wallet pays, not us).
public struct Bolt11: Sendable, Equatable {
    public let network: String
    public let amountMsats: Int?
    public let timestamp: Date
    public let expirySeconds: Int
    public let paymentHash: String?
    public let description: String?
    public let descriptionHash: String?

    public var amountSats: Int? { amountMsats.map { $0 / 1000 } }
    public var expiresAt: Date { timestamp.addingTimeInterval(TimeInterval(expirySeconds)) }

    public static func decode(_ invoice: String) -> Bolt11? {
        var text = invoice.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("lightning:") { text = String(text.dropFirst(10)) }
        guard let (hrp, words) = try? Bech32.decode(text, limit: 7089), hrp.hasPrefix("ln"), words.count > 7 + 104 else { return nil }

        var rest = Substring(hrp.dropFirst(2))
        guard let network = ["bcrt", "bc", "tbs", "tb", "sb"].first(where: { rest.hasPrefix($0) }) else { return nil }
        rest = rest.dropFirst(network.count)
        var amount: Int?
        if !rest.isEmpty {
            let digits = rest.prefix { $0.isNumber }
            guard let n = Int(digits) else { return nil }
            let mult = rest.dropFirst(digits.count)
            switch mult {
            case "": amount = n * 100_000_000_000
            case "m": amount = n * 100_000_000
            case "u": amount = n * 100_000
            case "n": amount = n * 100
            case "p":
                guard n % 10 == 0 else { return nil }
                amount = n / 10
            default: return nil
            }
        }

        func int(_ w: ArraySlice<UInt8>) -> Int { w.reduce(0) { $0 << 5 | Int($1) } }
        let data = words.dropLast(104)
        let timestamp = int(data.prefix(7))
        var i = data.startIndex + 7
        var hash: String?, desc: String?, descHash: String?, expiry = 3600
        while i + 3 <= data.endIndex {
            let type = data[i]
            let len = int(data[(i + 1)..<(i + 3)])
            let start = i + 3, end = start + len
            guard end <= data.endIndex else { break }
            let field = Array(data[start..<end])
            let bytes = (try? Bech32.convertBits(field, from: 5, to: 8, pad: false)).map { Data($0) }
                ?? (try? Bech32.convertBits(field, from: 5, to: 8, pad: true)).map { Data($0.dropLast()) }
            switch type {
            case 1 where len == 52: hash = bytes?.hex
            case 13: desc = bytes.flatMap { String(data: $0, encoding: .utf8) }
            case 23 where len == 52: descHash = bytes?.hex
            case 6: expiry = int(data[start..<end])
            default: break
            }
            i = end
        }
        return Bolt11(network: network, amountMsats: amount, timestamp: Date(timeIntervalSince1970: TimeInterval(timestamp)),
                      expirySeconds: expiry, paymentHash: hash, description: desc, descriptionHash: descHash)
    }
}
