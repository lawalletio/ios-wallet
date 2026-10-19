import XCTest

/// End-to-end UI flows against a live LaWallet instance (default: local `pnpm start:dev-server` on :3774 whose
/// `lncurl_server_url` points at the Alby NWC faucet, so every signup gets a funded test wallet).
/// Override with `LAWALLET_UITEST_INSTANCE` (e.g. https://beta.lawallet.io).
final class WalletFlowTests: XCTestCase {
    private var instance: String { ProcessInfo.processInfo.environment["LAWALLET_UITEST_INSTANCE"] ?? "http://localhost:3774" }

    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["LAWALLET_INSTANCE"] = instance
        app.launch()
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    @discardableResult
    private func tap(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 15) -> XCUIElement {
        let e = el(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "missing \(id)")
        e.tap()
        return e
    }

    private func wait(_ e: XCUIElement, timeout: TimeInterval = 30, _ predicate: String = "exists == true") {
        let exp = expectation(for: NSPredicate(format: predicate), evaluatedWith: e)
        wait(for: [exp], timeout: timeout)
    }

    /// Landing → random key → backup → welcome → home.
    private func createAccount(_ app: XCUIApplication) {
        tap(app, "landing.create", timeout: 30)
        tap(app, "signup.randomKey")
        tap(app, "create.backedUp")
        tap(app, "create.continue")
        allowSystemAlert()
        tap(app, "welcome.enter", timeout: 40)
        XCTAssertTrue(el(app, "home.receive").waitForExistence(timeout: 20))
    }

    /// Dismisses the notification permission prompt raised after signup.
    private func allowSystemAlert() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
    }

    /// Taps the non-cancel button of the visible alert.
    private func confirmAlert(_ app: XCUIApplication) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let buttons = alert.buttons.allElementsBoundByIndex.filter { $0.label != "Cancel" }
        XCTAssertFalse(buttons.isEmpty)
        buttons.last!.tap()
    }

    private func claimAddress(_ app: XCUIApplication) -> String {
        let name = "ui" + String(UUID().uuidString.lowercased().filter(\.isHexDigit).prefix(10))
        tap(app, "home.claimAddress", timeout: 30)
        let field = tap(app, "claim.username")
        field.typeText(name)
        tap(app, "claim.submit", timeout: 20)
        tap(app, "claim.done", timeout: 40)
        let address = el(app, "home.address")
        XCTAssertTrue(address.waitForExistence(timeout: 40))
        XCTAssertTrue(address.label.contains(name + "@"), "address was \(address.label)")
        return name
    }

    func testCreateAccountClaimAddressAndReceive() throws {
        let app = launch()
        createAccount(app)
        let name = claimAddress(app)

        // Balance appears once the courtesy NWC wallet answers over its relay.
        let balance = el(app, "home.balance")
        wait(balance, timeout: 60, "label != '0' AND exists == true")

        tap(app, "home.receive")
        let caption = el(app, "qr.caption")
        XCTAssertTrue(caption.waitForExistence(timeout: 15))
        XCTAssertTrue(caption.label.contains(name + "@"), "caption was \(caption.label)")
        tap(app, "receive.requestAmount")
        tap(app, "key.2")
        tap(app, "key.1")
        tap(app, "receive.amount.continue")
        XCTAssertTrue(el(app, "receive.invoice.qr").waitForExistence(timeout: 60), "invoice was not created over NWC")
    }

    func testSendToLightningAddress() throws {
        // A second faucet wallet is the recipient (its lud16 is a real Lightning address).
        let recipient = try faucetLud16()
        let app = launch()
        createAccount(app)
        _ = claimAddress(app)
        let balance = el(app, "home.balance")
        wait(balance, timeout: 60, "label != '0' AND exists == true")
        let before = balance.label

        tap(app, "home.send")
        let input = tap(app, "send.input")
        input.typeText(recipient)
        tap(app, "send.continue")
        tap(app, "key.1", timeout: 30)
        tap(app, "key.0")
        tap(app, "send.amount.continue")
        let swipe = el(app, "swipe.confirm")
        XCTAssertTrue(swipe.waitForExistence(timeout: 40))
        let start = swipe.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: swipe.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)))
        tap(app, "summary.done", timeout: 90)
        wait(el(app, "home.balance"), timeout: 60, "label != '\(before)'")
    }

    func testSettingsInstanceLanguageBackupAndLogout() throws {
        let app = launch()
        createAccount(app)

        tap(app, "nav.settings")
        tap(app, "settings.instance")
        XCTAssertTrue(el(app, "instance.current").waitForExistence(timeout: 10))
        tap(app, "header.back")

        tap(app, "settings.security")
        tap(app, "security.reveal")
        confirmAlert(app)
        let nsec = el(app, "security.nsec")
        XCTAssertTrue(nsec.waitForExistence(timeout: 10))
        XCTAssertTrue(nsec.label.contains("nsec1") || (nsec.value as? String)?.contains("nsec1") == true, "nsec label: \(nsec.label)")
        tap(app, "header.back")

        tap(app, "settings.language")
        tap(app, "language.es")
        tap(app, "header.back")
        XCTAssertTrue(app.staticTexts["Ajustes"].waitForExistence(timeout: 10))
        tap(app, "settings.language")
        tap(app, "language.en")
        tap(app, "header.back")

        tap(app, "settings.currencies")
        tap(app, "header.back")

        app.swipeUp()
        tap(app, "settings.removeWallet")
        confirmAlert(app)
        XCTAssertTrue(el(app, "landing.create").waitForExistence(timeout: 15))
    }

    func testNsecLogin() throws {
        let app = launch()
        tap(app, "landing.login", timeout: 30)
        tap(app, "login.nostr")
        tap(app, "nostr.tab.nsec")
        let field = tap(app, "nostr.nsecField")
        field.typeText("nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5")
        tap(app, "nostr.nsecSubmit")
        XCTAssertTrue(el(app, "home.receive").waitForExistence(timeout: 40))
    }

    private func faucetLud16() throws -> String {
        var req = URLRequest(url: URL(string: "https://faucet.nwc.dev?balance=100")!)
        req.httpMethod = "POST"
        let done = expectation(description: "faucet")
        var uri = ""
        URLSession.shared.dataTask(with: req) { data, _, _ in
            uri = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 30)
        let lud16 = URLComponents(string: uri.replacingOccurrences(of: "nostr+walletconnect://", with: "https://"))?
            .queryItems?.first { $0.name == "lud16" }?.value
        return try XCTUnwrap(lud16, "faucet returned no lud16: \(uri)")
    }
}
