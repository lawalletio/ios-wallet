import Foundation

/// `{ error: { message, code, details } }` mapped onto the HTTP status. 402 = paid registration.
public struct APIError: Error, LocalizedError, Equatable {
    public let status: Int
    public let message: String
    public let code: String?
    public var errorDescription: String? { message }

    public init(status: Int, message: String, code: String? = nil) {
        self.status = status
        self.message = message
        self.code = code
    }
}

public enum APIAuth: Sendable {
    case none
    /// Session JWT from the client's token provider.
    case bearer
    /// Sign this request with NIP-98 (used for `/api/jwt` and passkey signup).
    case nip98(any NostrSigner)
}

/// Thin JSON-over-HTTP core. `baseURL` must be the instance's public `endpoint` — NIP-98 binds to it.
public final class HTTPClient: Sendable {
    public let baseURL: URL
    let session: URLSession
    let bearer: @Sendable () async throws -> String?
    let onUnauthorized: (@Sendable () -> Void)?

    public init(baseURL: URL, session: URLSession = .shared, bearer: @escaping @Sendable () async throws -> String? = { nil },
                onUnauthorized: (@Sendable () -> Void)? = nil) {
        self.baseURL = baseURL
        self.session = session
        self.bearer = bearer
        self.onUnauthorized = onUnauthorized
    }

    /// Absolute URL string for a path like `/api/users/me?x=1` (exactly what NIP-98 must sign).
    public func url(_ path: String) -> String {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        return base + path
    }

    public func raw(_ method: String, _ path: String, body: Data? = nil, auth: APIAuth = .bearer) async throws -> (Data, Int) {
        let urlString = url(path)
        guard let url = URL(string: urlString) else { throw APIError(status: 0, message: "Invalid URL") }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        switch auth {
        case .none: break
        case .bearer:
            if let token = try await bearer() { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        case .nip98(let signer):
            req.setValue(try await NIP98.header(url: urlString, method: method, body: body, signer: signer), forHTTPHeaderField: "Authorization")
        }
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) } catch {
            throw APIError(status: 0, message: (error as NSError).localizedDescription, code: "NETWORK")
        }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let env = try? JSONValue.parse(data)
            let message = env?["error"]?["message"]?.string ?? env?["error"]?.string ?? env?["message"]?.string ?? Self.defaultMessage(status)
            if status == 401 { onUnauthorized?() }
            throw APIError(status: status, message: message, code: env?["error"]?["code"]?.string)
        }
        return (data, status)
    }

    static func defaultMessage(_ status: Int) -> String {
        switch status {
        case 401: "Unauthorized"
        case 403: "Insufficient permissions"
        case 429: "Too many requests, try again in a minute"
        case 503: "Service unavailable, try again"
        default: "Request failed (\(status))"
        }
    }

    public func send<T: Decodable>(_ method: String, _ path: String, json: (any Encodable)? = nil, auth: APIAuth = .bearer,
                                   as: T.Type = T.self) async throws -> T {
        let body = try json.map { try Self.encoder.encode($0) }
        let (data, _) = try await raw(method, path, body: body, auth: auth)
        if T.self == Empty.self { return Empty() as! T }
        do { return try Self.decoder.decode(T.self, from: data.isEmpty ? Data("{}".utf8) : data) } catch {
            throw APIError(status: 0, message: "Unexpected response from \(path): \(error)", code: "DECODE")
        }
    }

    public func get<T: Decodable>(_ path: String, auth: APIAuth = .bearer, as t: T.Type = T.self) async throws -> T {
        try await send("GET", path, auth: auth, as: t)
    }

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()

    public static let decoder = JSONDecoder()
}

public struct Empty: Codable, Sendable, Equatable { public init() {} }

/// Server-Sent Events over `GET /api/events?token=…`. Events are payload-free invalidations: refetch on arrival.
public struct EventStream: Sendable {
    public struct Event: Sendable, Equatable {
        public let type: String
        public let data: String
    }

    let http: HTTPClient
    /// Fresh token per connect: a JWT, or a bare NIP-98 token signed over `<endpoint>/api/events`.
    let token: @Sendable () async throws -> String

    public init(http: HTTPClient, token: @escaping @Sendable () async throws -> String) {
        self.http = http
        self.token = token
    }

    /// Reconnects with backoff (1 s → 30 s) and immediately on `recycle`. Ends when the consumer stops.
    public func events() -> AsyncStream<Event> {
        AsyncStream { cont in
            let task = Task {
                var backoff = 1.0
                while !Task.isCancelled {
                    do {
                        let t = try await token()
                        var comps = URLComponents(string: http.url("/api/events"))!
                        comps.queryItems = [URLQueryItem(name: "token", value: t)]
                        var req = URLRequest(url: comps.url!, timeoutInterval: 120)
                        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        let (bytes, resp) = try await http.session.bytes(for: req)
                        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw APIError(status: 0, message: "SSE") }
                        var eventType: String?
                        for try await line in bytes.lines {
                            if line.hasPrefix("event:") {
                                eventType = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                            } else if line.hasPrefix("data:"), let type = eventType {
                                // `lines` drops blank separators, so dispatch on the data line.
                                eventType = nil
                                if type == "connected" { backoff = 1 }
                                if type == "recycle" { break }
                                if type != "heartbeat" { cont.yield(Event(type: type, data: String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))) }
                            }
                        }
                        continue
                    } catch {
                        if Task.isCancelled { break }
                    }
                    try? await Task.sleep(for: .seconds(backoff))
                    backoff = min(backoff * 2, 30)
                }
                cont.finish()
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}
