import Foundation
import XCTest
@testable import LaWalletKit

/// REST client against a stubbed URLSession: request shape (method, path, auth, body) and the error envelope.
final class APITests: XCTestCase {
    private func api(status: Int = 200, body: String = "{}", onUnauthorized: (@Sendable () -> Void)? = nil) -> LaWalletAPI {
        StubProtocol.respond(status: status, body: body)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let http = HTTPClient(baseURL: URL(string: "https://beta.lawallet.io/")!, session: URLSession(configuration: config),
                              bearer: { "jwt-123" }, onUnauthorized: onUnauthorized)
        return LaWalletAPI(http: http)
    }

    func testDeleteAccountSendsConfirmedDeleteWithBearer() async throws {
        try await api(body: #"{"deleted":true}"#).deleteAccount()
        let req = try XCTUnwrap(StubProtocol.lastRequest)
        XCTAssertEqual(req.httpMethod, "DELETE")
        XCTAssertEqual(req.url?.absoluteString, "https://beta.lawallet.io/api/account")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-123")
        let body = try XCTUnwrap(StubProtocol.lastBody)
        XCTAssertEqual(try JSONValue.parse(body)["confirm"]?.string, "DELETE")
    }

    func testErrorEnvelopeMapsToAPIError() async {
        do {
            try await api(status: 404, body: #"{"error":{"message":"Account not found","code":"NOT_FOUND"}}"#).deleteAccount()
            XCTFail("expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 404)
            XCTAssertEqual(error.message, "Account not found")
            XCTAssertEqual(error.code, "NOT_FOUND")
        } catch { XCTFail("unexpected \(error)") }
    }

    func testEmptyErrorBodyFallsBackToStatusMessage() async {
        do {
            _ = try await api(status: 503, body: "").me()
            XCTFail("expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 503)
            XCTAssertEqual(error.message, "Service unavailable, try again")
        } catch { XCTFail("unexpected \(error)") }
    }

    func testUnauthorizedNotifiesSession() async {
        let flag = Flag()
        _ = try? await api(status: 401, body: #"{"error":"expired"}"#, onUnauthorized: { flag.set() }).me()
        XCTAssertTrue(flag.isSet)
    }

    func testPathSegmentsArePercentEncoded() async throws {
        try await api(body: "{}").deleteAddress("a b/c")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.absoluteString, "https://beta.lawallet.io/api/wallet/addresses/a%20b%2Fc")
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}

/// Answers every request with one canned response and records it. Tests in this class run serially.
private final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response: (Int, Data) = (200, Data())
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    static func respond(status: Int, body: String) {
        response = (status, Data(body.utf8))
        lastRequest = nil
        lastBody = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        // URLSession moves bodies into a stream before protocols see them.
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open()
            defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            return data
        }
        let (status, body) = Self.response
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class RelayResumeTests: XCTestCase {
    func testReconnectResumesFromNewestSeenEvent() {
        let filters: [JSONValue] = [["kinds": [23196], "since": 100], ["kinds": [1]]]
        let resumed = Relay.resumed(filters, after: 250)
        XCTAssertEqual(resumed[0]["since"]?.double, 250)
        XCTAssertEqual(resumed[1]["since"]?.double, 250)
        XCTAssertEqual(resumed[0]["kinds"], filters[0]["kinds"])
    }

    func testNothingSeenKeepsOriginalFilters() {
        let filters: [JSONValue] = [["kinds": [23196], "since": 100]]
        XCTAssertEqual(Relay.resumed(filters, after: nil), filters)
        // Never moves `since` backwards.
        XCTAssertEqual(Relay.resumed(filters, after: 50)[0]["since"]?.double, 100)
    }
}
