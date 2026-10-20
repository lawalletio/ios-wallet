import XCTest

/// App Store screenshots. Run through `scripts/screenshots.sh` (6.9" simulator, clean status bar, en + es); each
/// capture is kept as an `XCTAttachment` and exported to `AppStore/screenshots/<lang>/`.
final class ScreenshotTests: LaWalletUITestCase {
    func testAppStoreScreenshots() throws {
        // Only when asked for: it repeats the signup flow the other tests already cover.
        guard let lang = ProcessInfo.processInfo.environment["SCREENSHOT_LANG"] else {
            throw XCTSkip("set TEST_RUNNER_SCREENSHOT_LANG=en|es (scripts/screenshots.sh)")
        }
        let app = launch(language: lang)
        createAccount(app)
        _ = claimAddress(app)
        wait(el(app, "home.balance"), timeout: 60, "label != '0' AND exists == true")
        sleep(2)  // let the balance count-up and ambient light settle
        snap(app, "1-home")

        tap(app, "home.receive")
        XCTAssertTrue(el(app, "qr.caption").waitForExistence(timeout: 15))
        snap(app, "2-receive")
        tap(app, "receive.requestAmount")
        for key in ["key.2", "key.1", "key.0", "key.0"] { tap(app, key) }
        snap(app, "3-amount")
        tap(app, "header.back")
        tap(app, "header.back")

        tap(app, "home.send", timeout: 20)
        tap(app, "send.input").typeText("satoshi")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'send.option.'"))
            .firstMatch.waitForExistence(timeout: 10))
        snap(app, "4-send")
        tap(app, "header.back")

        tap(app, "nav.settings", timeout: 20)
        snap(app, "5-settings")
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
