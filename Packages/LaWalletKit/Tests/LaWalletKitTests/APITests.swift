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

    // MARK: card recovery

    private static let meJSON = #"{"userId":"u1","lightningAddress":null,"nwcString":"","nwcUpdatedAt":null,"effectiveNwcString":null,"primaryAddressMode":null,"primaryUsername":null,"primaryRedirect":null"#

    func testPreviewDecodesPurposeAndDefaultsToActivate() async throws {
        let card = #""card":{"id":"c1","title":null,"kind":"SIMPLE","design":{"id":"d","imageUrl":"/x.png","description":""}}"#
        let recover = try await api(body: #"{"tokenId":"t1","qrKind":"ONE_TIME","purpose":"RECOVER","status":"PENDING",\#(card)}"#).activationPreview("t1")
        XCTAssertTrue(recover.isRecover)
        let legacy = try await api(body: #"{"tokenId":"t1","qrKind":"ONE_TIME","status":"PENDING",\#(card)}"#).activationPreview("t1")
        XCTAssertNil(legacy.purpose)
        XCTAssertFalse(legacy.isRecover)
    }

    func testRecoveryCheckGetsAndDecodes() async throws {
        let check = try await api(body: #"{"sameAccount":false,"mergeRequired":true,"existing":{"lightningAddresses":["me@x.io"],"cards":1,"remoteWallets":2},"incoming":{"lightningAddresses":[],"cards":3,"remoteWallets":0}}"#)
            .recoveryCheck("t1")
        let req = try XCTUnwrap(StubProtocol.lastRequest)
        XCTAssertEqual(req.httpMethod, "GET")
        XCTAssertEqual(req.url?.absoluteString, "https://beta.lawallet.io/api/activation-tokens/t1/recovery-check")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-123")
        XCTAssertTrue(check.mergeRequired)
        XCTAssertEqual(check.existing.lightningAddresses, ["me@x.io"])
        XCTAssertEqual(check.incoming.cards, 3)
    }

    func testClaimRecoverySendsConfirmMergeAndDecodesRecovered() async throws {
        let body = #"{"qrKind":"ONE_TIME","purpose":"RECOVER","outcome":"recovered","needsLightningAddress":true,"recovery":{"lightningAddresses":["a@x.io"],"primaryAddress":"a@x.io","cards":[{"id":"c1","title":null,"designImageUrl":null}],"remoteWallets":[{"id":"w1","name":"Alby","isDefault":true}],"vouchers":2,"mergedIntoExisting":true}}"#
        let claim = try await api(body: body).claimRecovery("t1", confirmMerge: true)
        let req = try XCTUnwrap(StubProtocol.lastRequest)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.absoluteString, "https://beta.lawallet.io/api/activation-tokens/t1/claim")
        XCTAssertEqual(try JSONValue.parse(XCTUnwrap(StubProtocol.lastBody)), ["remoteWalletId": .null, "confirmMerge": true])
        let recovered = try XCTUnwrap(claim.recovered)
        XCTAssertEqual(claim.needsLightningAddress, true)
        XCTAssertEqual(recovered.remoteWallets.first?.name, "Alby")
        XCTAssertEqual(recovered.vouchers, 2)
        XCTAssertTrue(recovered.mergedIntoExisting)
    }

    func testClaimRecoverySameAccountHasNothingToShow() async throws {
        let claim = try await api(body: #"{"qrKind":"ONE_TIME","purpose":"RECOVER","outcome":"same-account"}"#).claimRecovery("t1", confirmMerge: false)
        XCTAssertEqual(try JSONValue.parse(XCTUnwrap(StubProtocol.lastBody)), ["remoteWalletId": .null, "confirmMerge": false])
        XCTAssertNil(claim.recovered)
    }

    func testMergeRequiredConflictKeepsDetailsReason() async {
        do {
            _ = try await api(status: 409, body: #"{"success":false,"error":{"message":"Merge needed","code":"CONFLICT","details":{"reason":"RECOVERY_MERGE_REQUIRED"}}}"#)
                .claimRecovery("t1", confirmMerge: false)
            XCTFail("expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 409)
            XCTAssertEqual(error.reason, "RECOVERY_MERGE_REQUIRED")
        } catch { XCTFail("unexpected \(error)") }
    }

    func testMeDecodesCardRecoveryFieldsAndStillDecodesWithout() async throws {
        let with = try await api(body: Self.meJSON + #","cardRecoveryEnabled":false,"accountTransfer":{"id":"tr1","transferredAt":"2026-10-01T12:00:00.000Z","cardTitle":null,"lightningAddresses":["old@x.io"],"cards":1,"remoteWallets":2}}"#).me()
        XCTAssertEqual(with.cardRecoveryEnabled, false)
        XCTAssertEqual(with.accountTransfer?.id, "tr1")
        XCTAssertEqual(with.accountTransfer?.remoteWallets, 2)
        let without = try await api(body: Self.meJSON + "}").me()
        XCTAssertNil(without.cardRecoveryEnabled)
        XCTAssertNil(without.accountTransfer)
        let cleared = try await api(body: Self.meJSON + #","cardRecoveryEnabled":true,"accountTransfer":null}"#).me()
        XCTAssertNil(cleared.accountTransfer)
    }

    func testSetCardRecoveryPutsEnabled() async throws {
        let enabled = try await api(body: #"{"cardRecoveryEnabled":false}"#).setCardRecovery(enabled: false)
        let req = try XCTUnwrap(StubProtocol.lastRequest)
        XCTAssertEqual(req.httpMethod, "PUT")
        XCTAssertEqual(req.url?.absoluteString, "https://beta.lawallet.io/api/users/me/card-recovery")
        XCTAssertEqual(try JSONValue.parse(XCTUnwrap(StubProtocol.lastBody)), ["enabled": false])
        XCTAssertFalse(enabled)
    }

    func testDismissAccountTransferPosts() async throws {
        try await api(body: #"{"dismissed":1}"#).dismissAccountTransfer()
        let req = try XCTUnwrap(StubProtocol.lastRequest)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.absoluteString, "https://beta.lawallet.io/api/users/me/account-transfer/dismiss")
    }

    func testRemoteWalletBalanceAndTotal() async throws {
        let sats = try await api(body: #"{"balanceSats":2100}"#).remoteWalletBalance("w1")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.absoluteString, "https://beta.lawallet.io/api/remote-wallets/w1/balance")
        XCTAssertEqual(sats, 2100)
        XCTAssertEqual(RecoveredAccount.total([sats, nil, 400]), 2500)
        XCTAssertNil(RecoveredAccount.total([nil, nil]))
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
