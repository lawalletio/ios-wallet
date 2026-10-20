import LaWalletKit
import XCTest
@testable import LaWallet

@MainActor final class LogicTests: XCTestCase {
    func testKeypadIntegerSats() {
        var v = ""
        for k in ["0", "1", "2", "⌫", "5"] { v = AmountKeypad.apply(k, to: v, decimals: 0, maxLength: 12) }
        XCTAssertEqual(v, "15")
        XCTAssertEqual(AmountKeypad.apply(".", to: "15", decimals: 0, maxLength: 12), "15")
    }

    func testKeypadFiatDecimals() {
        var v = ""
        for k in [".", "5", "0", "9"] { v = AmountKeypad.apply(k, to: v, decimals: 2, maxLength: 12) }
        XCTAssertEqual(v, "0.50")
        XCTAssertEqual(AmountKeypad.apply(".", to: "0.50", decimals: 2, maxLength: 12), "0.50")
    }

    func testAmountDisplayGrouping() {
        XCTAssertEqual(AmountDisplay.format("1234567"), "1,234,567")
        XCTAssertEqual(AmountDisplay.format("1234."), "1,234.")
        XCTAssertEqual(AmountDisplay.format(""), "0")
    }

    func testJWTClaims() {
        // header.payload.sig with payload {"exp":2000000000,"role":"USER"}
        let payload = Data(#"{"exp":2000000000,"role":"USER"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        let token = "e30.\(payload).sig"
        XCTAssertEqual(AppModel.jwtExpiry(token), Date(timeIntervalSince1970: 2_000_000_000))
        XCTAssertEqual(AppModel.jwtClaims(token)?["role"]?.string, "USER")
        XCTAssertNil(AppModel.jwtExpiry("garbage"))
    }

    func testThemePresetFromSettings() {
        XCTAssertEqual(ThemePreset.from(brandTheme: "#3b82f6").name, "Blue")
        XCTAssertEqual(ThemePreset.from(brandTheme: "violet").name, "Violet")
        XCTAssertEqual(ThemePreset.from(brandTheme: nil).name, "Green")
        XCTAssertEqual(Theme.from(("#ec4899", "full")).radius, 24)
    }

    func testRelativeTime() {
        let now = Date()
        XCTAssertEqual(RelativeTime.format(now.addingTimeInterval(-10), now: now), t("shared.tx.justNow"))
        XCTAssertEqual(RelativeTime.format(now.addingTimeInterval(-300), now: now), t("shared.tx.minutesAgo", ["n": "5"]))
    }

    @MainActor func testScanRouterInvoiceGoesToPreview() async {
        let app = AppModel()
        let invoice = "lnbc2500u1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygspp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdq5xysxxatsyp3k7enxv4jsxqzpu9qrsgquk0rl77nj30yxdy8j9vdx85fkpmdla2087ne0xh8nhedh8w27kyke0lp53ut353s06fv3qfegext0eh0ymjpf39tuven09sam30g4vgpfna3rh"
        let outcome = await ScanRouter.route("lightning:" + invoice, app: app)
        XCTAssertEqual(outcome, .handled)
        XCTAssertEqual(app.path.count, 1)
        XCTAssertEqual(app.flows.sendAmountSats, 250_000)
    }

    @MainActor func testScanRouterRejectsPlainText() async {
        let app = AppModel()
        if case .unsupported = await ScanRouter.route("hello world", app: app) {} else { XCTFail("expected unsupported") }
        XCTAssertEqual(app.path.count, 0)
    }

    @MainActor func testScanRouterForeignActivation() async {
        let app = AppModel()
        let outcome = await ScanRouter.route("https://other.example.com/wallet/activate/abc123", app: app)
        XCTAssertEqual(outcome, .foreignActivation(URL(string: "https://other.example.com/wallet/activate/abc123")!))
    }

    func testSuggestionArrowNavigationWraps() {
        XCTAssertEqual(SendRecipientScreen.nextIndex(nil, count: 3, direction: 1), 0)
        XCTAssertEqual(SendRecipientScreen.nextIndex(2, count: 3, direction: 1), 0)
        XCTAssertEqual(SendRecipientScreen.nextIndex(nil, count: 3, direction: -1), 2)
        XCTAssertEqual(SendRecipientScreen.nextIndex(0, count: 3, direction: -1), 2)
        XCTAssertEqual(SendRecipientScreen.nextIndex(1, count: 3, direction: -1), 0)
        XCTAssertNil(SendRecipientScreen.nextIndex(1, count: 0, direction: 1))
    }

    func testQRImageDecoderRoundTrip() throws {
        let text = "lightning:satoshi@lawallet.io"
        let png = try XCTUnwrap(QRCodeImage.make(text)?.pngData())
        XCTAssertEqual(QRImageDecoder.decode(png), text)
        XCTAssertNil(QRImageDecoder.decode(Data("not an image".utf8)))
    }

    @MainActor func testChimeIsValidWAV() {
        let wav = SoundPlayer.chime()
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertGreaterThan(wav.count, 10_000)
    }

    func testTabBarShowsOnHomeAndSettingsOnly() {
        XCTAssertEqual(NavTabbar.Tab.visible(for: []), .home)
        XCTAssertEqual(NavTabbar.Tab.visible(for: [.settings]), .settings)
        XCTAssertEqual(NavTabbar.Tab.visible(for: [.settings, .remoteWallets, .remoteWalletDetail("w1")]), .settings)
        XCTAssertNil(NavTabbar.Tab.visible(for: [.send]))
        XCTAssertNil(NavTabbar.Tab.visible(for: [.settings, .scan]))
        XCTAssertNil(NavTabbar.Tab.visible(for: [.activity]))
    }

    func testAmbientRedrawsOnlyWhenSeen() {
        typealias A = AmbientBackground
        XCTAssertEqual(A.frameRate(onScreen: true, active: true, flaring: false, reduceMotion: false, lowPower: false), .drift)
        XCTAssertEqual(A.frameRate(onScreen: true, active: true, flaring: true, reduceMotion: false, lowPower: false), .display)
        // The payment bloom still plays with Reduce Motion / Low Power; the idle drift doesn't.
        XCTAssertEqual(A.frameRate(onScreen: true, active: true, flaring: true, reduceMotion: true, lowPower: true), .display)
        XCTAssertEqual(A.frameRate(onScreen: true, active: true, flaring: false, reduceMotion: true, lowPower: false), .paused)
        XCTAssertEqual(A.frameRate(onScreen: true, active: true, flaring: false, reduceMotion: false, lowPower: true), .paused)
        XCTAssertEqual(A.frameRate(onScreen: false, active: true, flaring: true, reduceMotion: false, lowPower: false), .paused)
        XCTAssertEqual(A.frameRate(onScreen: true, active: false, flaring: false, reduceMotion: false, lowPower: false), .paused)
    }

    func testUITestHooksAreDebugOnly() {
        // Tests run the Debug build without `-uitest-reset`; Release compiles the check to `false`.
        XCTAssertFalse(AppModel.isUITest)
    }

    /// Passkey buttons are only offered where iOS will run the ceremony: keep the list equal to the entitlements.
    func testPasskeyDomainsMatchEntitlements() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "LaWallet/LaWallet.entitlements")
        let plist = try XCTUnwrap(NSDictionary(contentsOf: file) as? [String: Any])
        let domains = (plist["com.apple.developer.associated-domains"] as? [String] ?? [])
            .filter { $0.hasPrefix("webcredentials:") }.map { String($0.dropFirst("webcredentials:".count)) }
        XCTAssertEqual(Set(domains), PasskeyService.associatedDomains)
    }
}
