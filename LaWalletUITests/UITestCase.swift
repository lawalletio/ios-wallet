import XCTest

/// Shared driver for UI tests against a live LaWallet instance (default: local `pnpm start:dev-server` on :3774 whose
/// `lncurl_server_url` points at the Alby NWC faucet, so every signup gets a funded test wallet).
/// Override with `LAWALLET_UITEST_INSTANCE` (e.g. https://beta.lawallet.io).
class LaWalletUITestCase: XCTestCase {
    var instance: String { ProcessInfo.processInfo.environment["LAWALLET_UITEST_INSTANCE"] ?? "http://localhost:3774" }

    override func setUp() { continueAfterFailure = false }

    func launch(language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        let locale = language == "es" ? "es_AR" : "en_US"
        app.launchArguments = ["-uitest-reset", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launchEnvironment["LAWALLET_INSTANCE"] = instance
        app.launch()
        return app
    }

    func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    @discardableResult
    func tap(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 15) -> XCUIElement {
        let e = el(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "missing \(id)")
        e.tap()
        return e
    }

    func wait(_ e: XCUIElement, timeout: TimeInterval = 30, _ predicate: String = "exists == true") {
        let exp = expectation(for: NSPredicate(format: predicate), evaluatedWith: e)
        wait(for: [exp], timeout: timeout)
    }

    /// Landing → random key → backup → welcome → home.
    func createAccount(_ app: XCUIApplication) {
        tap(app, "landing.create", timeout: 30)
        tap(app, "signup.randomKey")
        tap(app, "create.backedUp")
        tap(app, "create.continue")
        allowSystemAlert()
        tap(app, "welcome.enter", timeout: 40)
        XCTAssertTrue(el(app, "home.receive").waitForExistence(timeout: 20))
    }

    /// Dismisses the notification permission prompt raised after signup.
    func allowSystemAlert() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
    }

    /// Taps the non-cancel button of the visible alert.
    func confirmAlert(_ app: XCUIApplication) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let buttons = alert.buttons.allElementsBoundByIndex.filter { $0.label != "Cancel" }
        XCTAssertFalse(buttons.isEmpty)
        buttons.last!.tap()
    }

    func claimAddress(_ app: XCUIApplication) -> String {
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
}
