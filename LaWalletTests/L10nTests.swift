import LaWalletKit
import XCTest
@testable import LaWallet

final class L10nTests: XCTestCase {
    private func table(_ locale: String) throws -> [String: String] {
        var out: [String: String] = [:]
        for name in ["wallet", "ios", "ios-onboarding", "ios-payments", "ios-settings"] {
            guard let url = Bundle(for: AppModel.self).url(forResource: name, withExtension: "json", subdirectory: nil, localization: locale)
            else { continue }
            out.merge(try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))) { $1 }
        }
        return out
    }

    func testLocalesHaveSameKeys() throws {
        let en = try table("en"), es = try table("es")
        XCTAssertGreaterThan(en.count, 900)
        XCTAssertEqual(Set(en.keys).subtracting(es.keys), [], "missing in es")
        XCTAssertEqual(Set(es.keys).subtracting(en.keys), [], "missing in en")
    }

    /// Every literal `t("…")` key used in the app source exists in both locales.
    func testEveryUsedKeyExists() throws {
        let en = try table("en"), es = try table("es")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("LaWallet")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        let regex = try NSRegularExpression(pattern: #"\bt\("([A-Za-z0-9_.\-]+)"[,)]"#)
        var missing: [String] = []
        for file in files {
            let src = try String(contentsOf: file, encoding: .utf8)
            for m in regex.matches(in: src, range: NSRange(src.startIndex..., in: src)) {
                let key = String(src[Range(m.range(at: 1), in: src)!])
                if en[key] == nil || es[key] == nil { missing.append("\(file.lastPathComponent): \(key)") }
            }
        }
        XCTAssertEqual(missing, [], "Unknown i18n keys")
    }

    func testInterpolation() {
        XCTAssertEqual(L10n.shared.string("common.sats", ["n": "21"]), L10n.shared.string("common.sats").replacingOccurrences(of: "{n}", with: "21"))
        XCTAssertEqual(t("does.not.exist"), "does.not.exist")
    }
}

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
}
