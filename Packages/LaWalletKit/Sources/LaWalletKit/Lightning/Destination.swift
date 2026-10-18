import Foundation

/// A parsed send recipient. Mirrors `apps/web/lib/client/nwc/parse-destination.ts`.
public enum Destination: Sendable, Equatable {
    case invoice(bolt11: String, decoded: Bolt11)
    /// LUD-16 address (`address` set) or bech32 LNURL (`address` nil).
    case lnurlPay(url: URL, address: String?)
    case npub(String)

    public enum ParseError: Error, Equatable { case empty, unsupported, invalidInvoice, invalidLnurl, invalidAddress }

    private static var addressRegex: Regex<(Substring, Substring, Substring)> { /^([a-z0-9._-]+)@([a-z0-9.-]+\.[a-z]{2,})$/.ignoresCase() }

    public static func parse(_ raw: String) throws -> Destination {
        var input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.lowercased().hasPrefix("lightning:") { input = String(input.dropFirst(10)) }
        guard !input.isEmpty else { throw ParseError.empty }
        let lower = input.lowercased()
        if lower.hasPrefix("lnbc") || lower.hasPrefix("lntb") || lower.hasPrefix("lnbcrt") {
            guard let decoded = Bolt11.decode(input) else { throw ParseError.invalidInvoice }
            return .invoice(bolt11: input, decoded: decoded)
        }
        if lower.hasPrefix("lnurl1") {
            guard let url = LNURL.decodeBech32(input) else { throw ParseError.invalidLnurl }
            return .lnurlPay(url: url, address: nil)
        }
        if let m = input.wholeMatch(of: addressRegex) {
            guard let url = LNURL.lud16URL(username: String(m.1), host: String(m.2)) else { throw ParseError.invalidAddress }
            return .lnurlPay(url: url, address: input)
        }
        if lower.hasPrefix("npub1") { return .npub(input) }
        throw ParseError.unsupported
    }

    public static func isLightningAddress(_ s: String) -> Bool { s.wholeMatch(of: addressRegex) != nil }
}

/// Card activation link: `<host>/wallet/activate/<tokenId>` (optional trailing slash).
public struct ActivationLink: Sendable, Equatable {
    public let tokenId: String
    public let host: String

    public static func parse(_ text: String) -> ActivationLink? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host
        else { return nil }
        let segments = url.path.split(separator: "/").map(String.init)
        guard segments.count == 3, segments[0] == "wallet", segments[1] == "activate",
              segments[2].wholeMatch(of: /[A-Za-z0-9_-]+/) != nil else { return nil }
        return ActivationLink(tokenId: segments[2], host: url.port.map { "\(host):\($0)" } ?? host)
    }
}
