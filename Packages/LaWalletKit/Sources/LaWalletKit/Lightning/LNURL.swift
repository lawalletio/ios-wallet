import Foundation

public struct LNURLError: Error, Equatable, LocalizedError {
    public enum Code: String, Sendable { case unreachable, httpStatus, invalidResponse, endpointError, unsupported, missingFields,
        noAmount, belowOneSat, invalidCallback, rejected, amountRange, notPayRequest }
    public let code: Code
    public let message: String
    public var errorDescription: String? { message }
    public init(_ code: Code, _ message: String) { self.code = code; self.message = message }
}

public struct LNURLPayParams: Sendable, Equatable {
    public let url: URL
    public let callback: URL
    public let minSendableSats: Int
    public let maxSendableSats: Int
    public let commentAllowed: Int
    public let metadata: String
    public let allowsNostr: Bool

    /// `text/plain` entry of the LUD-06 metadata array.
    public var text: String? { metadataEntry("text/plain") }
    public var identifier: String? { metadataEntry("text/identifier") ?? metadataEntry("text/email") }
    /// Avatar as raw image bytes (`image/png;base64` / `image/jpeg;base64`).
    public var image: Data? {
        (metadataEntry("image/png;base64") ?? metadataEntry("image/jpeg;base64")).flatMap { Data(base64Encoded: $0) }
    }

    private func metadataEntry(_ type: String) -> String? {
        guard let arr = try? JSONValue.parse(Data(metadata.utf8)).array else { return nil }
        return arr.first { $0.array?.first?.string == type }?.array?[1].string
    }
}

public struct LNURLWithdrawParams: Sendable, Equatable {
    public let callback: String
    public let k1: String
    public let defaultDescription: String
    public let minWithdrawableSats: Int
    public let maxWithdrawableSats: Int
    public let host: String
}

public enum LNURLResolved: Sendable, Equatable {
    case pay(LNURLPayParams)
    case withdraw(LNURLWithdrawParams)
}

public struct LUD21Verify: Sendable, Equatable, Decodable {
    public let settled: Bool
    public let preimage: String?
    public let pr: String?
}

public enum LNURL {
    public static func decodeBech32(_ s: String) -> URL? {
        guard let (hrp, data) = try? Bech32.decodeData(s, limit: 4096), hrp == "lnurl",
              let str = String(data: data, encoding: .utf8), let url = URL(string: str),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    public static func lud16URL(username: String, host: String) -> URL? {
        let user = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        return URL(string: "https://\(host.lowercased())/.well-known/lnurlp/\(user)")
    }

    /// Any LNURL form → http(s) endpoint; nil when the input isn't an LNURL.
    public static func toHTTPURL(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("lightning:") { text = String(text.dropFirst(10)).trimmingCharacters(in: .whitespaces) }
        let lower = text.lowercased()
        for scheme in ["lnurlw://", "lnurlp://", "lnurlc://", "keyauth://"] where lower.hasPrefix(scheme) {
            let rest = String(text.dropFirst(scheme.count))
            let host = rest.split(separator: "/").first.map(String.init) ?? ""
            let proto = host.split(separator: ":").first?.hasSuffix(".onion") == true ? "http://" : "https://"
            return URL(string: proto + rest)
        }
        if lower.hasPrefix("lnurl1") { return decodeBech32(text) }
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return URL(string: text) }
        return nil
    }

    /// IO-free precheck so the scanner doesn't fetch every website QR.
    public static func looksLike(_ input: String) -> Bool {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("lightning:") { text = String(text.dropFirst(10)) }
        let lower = text.lowercased()
        if lower.hasPrefix("lnurl1") { return true }
        if ["lnurlw://", "lnurlp://", "lnurlc://", "keyauth://"].contains(where: lower.hasPrefix) { return true }
        if lower.hasPrefix("http://") || lower.hasPrefix("https://"), let c = URLComponents(string: text) {
            let items = c.queryItems ?? []
            if let tag = items.first(where: { $0.name == "tag" })?.value, ["withdrawRequest", "payRequest"].contains(tag) { return true }
            return items.contains { $0.name == "k1" }
        }
        return false
    }

    static func getJSON(_ url: URL, session: URLSession) async throws -> JSONValue {
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) } catch {
            throw LNURLError(.unreachable, "Could not reach the LNURL endpoint")
        }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONValue.parse(data)
        guard (200..<300).contains(status) else {
            if let reason = json?["reason"]?.string ?? json?["error"]?["message"]?.string, !reason.isEmpty {
                throw LNURLError(.endpointError, reason)
            }
            throw LNURLError(.httpStatus, "LNURL endpoint returned \(status)")
        }
        guard let json else { throw LNURLError(.invalidResponse, "LNURL endpoint returned an invalid response") }
        if json["status"]?.string == "ERROR" {
            throw LNURLError(.endpointError, json["reason"]?.string ?? "LNURL endpoint returned an error")
        }
        return json
    }

    /// Fetches the endpoint and branches on its `tag`. Nil when `input` isn't an LNURL.
    public static func resolve(_ input: String, session: URLSession = .shared) async throws -> LNURLResolved? {
        guard let url = toHTTPURL(input) else { return nil }
        return try await resolve(url: url, session: session)
    }

    public static func resolve(url: URL, session: URLSession = .shared) async throws -> LNURLResolved {
        let json = try await getJSON(url, session: session)
        switch json["tag"]?.string {
        case "withdrawRequest": return .withdraw(try withdrawParams(json, url: url))
        case "payRequest": return .pay(try payParams(json, url: url))
        default: throw LNURLError(.unsupported, "Unsupported LNURL type")
        }
    }

    static func payParams(_ json: JSONValue, url: URL) throws -> LNURLPayParams {
        guard let cb = json["callback"]?.string, let callback = URL(string: cb) else {
            throw LNURLError(.missingFields, "Pay request is missing its callback")
        }
        return LNURLPayParams(url: url, callback: callback,
                              minSendableSats: Int(((json["minSendable"]?.double ?? 1000) / 1000).rounded(.up)),
                              maxSendableSats: Int((json["maxSendable"]?.double ?? 0) / 1000),
                              commentAllowed: json["commentAllowed"]?.int ?? 0,
                              metadata: json["metadata"]?.string ?? "[]",
                              allowsNostr: json["allowsNostr"]?.bool ?? false)
    }

    static func withdrawParams(_ json: JSONValue, url: URL) throws -> LNURLWithdrawParams {
        guard let callback = json["callback"]?.string, !callback.isEmpty, let k1 = json["k1"]?.string, !k1.isEmpty else {
            throw LNURLError(.missingFields, "Withdraw voucher is missing required fields")
        }
        let minMsat = max(0, json["minWithdrawable"]?.double ?? 0)
        let maxMsat = json["maxWithdrawable"]?.double ?? 0
        guard maxMsat > 0 else { throw LNURLError(.noAmount, "Withdraw voucher has no withdrawable amount") }
        let maxSats = Int((maxMsat / 1000).rounded(.down))
        guard maxSats >= 1 else { throw LNURLError(.belowOneSat, "Withdrawable amount is below 1 sat") }
        let minSats = Int((minMsat / 1000).rounded(.up))
        return LNURLWithdrawParams(callback: callback, k1: k1, defaultDescription: json["defaultDescription"]?.string ?? "",
                                   minWithdrawableSats: min(minSats, maxSats), maxWithdrawableSats: maxSats,
                                   host: url.host.map { h in url.port.map { "\(h):\($0)" } ?? h } ?? "")
    }

    /// LUD-03: hand our invoice to the withdraw callback. Settlement is async — watch the invoice.
    public static func submitWithdraw(_ params: LNURLWithdrawParams, invoice: String, session: URLSession = .shared) async throws {
        guard var comps = URLComponents(string: params.callback) else {
            throw LNURLError(.invalidCallback, "Withdraw voucher has an invalid callback URL")
        }
        var items = comps.queryItems ?? []
        items.removeAll { $0.name == "k1" || $0.name == "pr" }
        items += [URLQueryItem(name: "k1", value: params.k1), URLQueryItem(name: "pr", value: invoice)]
        comps.queryItems = items
        guard let url = comps.url else { throw LNURLError(.invalidCallback, "Withdraw voucher has an invalid callback URL") }
        do { _ = try await getJSON(url, session: session) } catch let e as LNURLError where e.code == .endpointError {
            throw LNURLError(.rejected, e.message)
        }
    }

    /// LUD-06/12: mint an invoice. Drops the comment and retries if the recipient refuses it.
    public static func requestInvoice(_ params: LNURLPayParams, amountSats: Int, comment: String? = nil,
                                      session: URLSession = .shared) async throws -> (pr: String, verify: URL?, comment: String?) {
        guard amountSats > 0 else { throw LNURLError(.amountRange, "Enter an amount") }
        guard amountSats >= params.minSendableSats, amountSats <= params.maxSendableSats else {
            throw LNURLError(.amountRange, "Amount must be between \(params.minSendableSats) and \(params.maxSendableSats) sats")
        }
        let trimmed = comment?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sent: String? = params.commentAllowed > 0 && !trimmed.isEmpty ? String(trimmed.prefix(params.commentAllowed)) : nil

        func call(_ c: String?) async throws -> (String, URL?) {
            var comps = URLComponents(url: params.callback, resolvingAgainstBaseURL: false)!
            var items = (comps.queryItems ?? []).filter { $0.name != "amount" && $0.name != "comment" }
            items.append(URLQueryItem(name: "amount", value: String(amountSats * 1000)))
            if let c { items.append(URLQueryItem(name: "comment", value: c)) }
            comps.queryItems = items
            let json = try await getJSON(comps.url!, session: session)
            guard let pr = json["pr"]?.string else { throw LNURLError(.invalidResponse, "Recipient refused the invoice request") }
            return (pr, json["verify"]?.string.flatMap(URL.init(string:)))
        }
        do {
            let (pr, verify) = try await call(sent)
            return (pr, verify, sent)
        } catch where sent != nil {
            let (pr, verify) = try await call(nil)
            return (pr, verify, nil)
        }
    }

    /// LUD-21 single check.
    public static func verify(_ url: URL, session: URLSession = .shared) async throws -> LUD21Verify {
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(LUD21Verify.self, from: data)
    }

    /// Polls a LUD-21 verify URL until settled (or the task is cancelled / times out).
    public static func pollVerify(_ url: URL, interval: Duration = .seconds(3), timeout: Duration = .seconds(300),
                                  session: URLSession = .shared) async throws -> LUD21Verify {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if let r = try? await verify(url, session: session), r.settled { return r }
            try await Task.sleep(for: interval)
        }
        throw NWCError.timeout
    }
}
