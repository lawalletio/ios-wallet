import LaWalletKit
import XCTest
@testable import LaWallet

@MainActor final class FormattingTests: XCTestCase {
    private var savedLocale = "en"

    override func setUp() async throws {
        savedLocale = L10n.shared.locale
        L10n.shared.load("en")
    }

    override func tearDown() async throws {
        L10n.shared.load(savedLocale)
    }

    // MARK: SettingsFormat

    func testNumberAcceptsCommaAndSpaces() {
        XCTAssertEqual(SettingsFormat.number("1,5"), 1.5)
        XCTAssertEqual(SettingsFormat.number(" 2 "), 2)
        XCTAssertEqual(SettingsFormat.number("0.25"), 0.25)
        XCTAssertNil(SettingsFormat.number(""))
        XCTAssertNil(SettingsFormat.number("abc"))
    }

    func testMsatsUsesAppLocale() {
        XCTAssertEqual(SettingsFormat.msats(1000), "1 sats")
        XCTAssertEqual(SettingsFormat.msats(1500), "1.5 sats")
        XCTAssertEqual(SettingsFormat.msats(1_234_567), "1,234.567 sats")
        XCTAssertEqual(SettingsFormat.msats(1234.5678), "1.235 sats")
        L10n.shared.load("es")
        XCTAssertEqual(SettingsFormat.msats(1500), "1,5 sats")
    }

    func testPercentFromBasisPoints() {
        XCTAssertEqual(SettingsFormat.percent(bps: 0), "0.00%")
        XCTAssertEqual(SettingsFormat.percent(bps: 25), "0.25%")
        XCTAssertEqual(SettingsFormat.percent(bps: 10_000), "100.00%")
    }

    func testStatusLocalizesKnownAndHumanizesUnknown() {
        XCTAssertEqual(SettingsFormat.status("PENDING"), t("shared.forwarding.statuses.PENDING"))
        XCTAssertEqual(SettingsFormat.status("awaiting_forwarding"), t("shared.forwarding.statuses.AWAITING_FORWARDING"))
        XCTAssertEqual(SettingsFormat.status("SOME_NEW_STATE"), "Some New State")
    }

    func testTone() {
        XCTAssertEqual(SettingsFormat.tone("completed"), .success)
        XCTAssertEqual(SettingsFormat.tone("RETAINED"), .success)
        XCTAssertEqual(SettingsFormat.tone("FAILED"), .destructive)
        XCTAssertEqual(SettingsFormat.tone("dead"), .destructive)
        XCTAssertEqual(SettingsFormat.tone("PENDING"), .warning)
        XCTAssertEqual(SettingsFormat.tone("UNKNOWN"), .warning)
        XCTAssertEqual(SettingsFormat.tone("RECEIVED"), .secondary)
    }

    func testDateParsesWithAndWithoutFraction() throws {
        XCTAssertEqual(SettingsFormat.date("2026-10-19T12:34:56Z"), Date(timeIntervalSince1970: 1_792_413_296))
        let frac = try XCTUnwrap(SettingsFormat.date("2026-10-19T12:34:56.789Z"))
        XCTAssertEqual(frac.timeIntervalSince1970, 1_792_413_296.789, accuracy: 0.001)
        XCTAssertNil(SettingsFormat.date(nil))
        XCTAssertNil(SettingsFormat.date("yesterday"))
    }

    func testDateStringsFallBackToDash() {
        for f in [SettingsFormat.relative, SettingsFormat.shortDate, SettingsFormat.dateTime] {
            XCTAssertEqual(f(nil), "—")
            XCTAssertEqual(f("garbage"), "—")
        }
        XCTAssertEqual(SettingsFormat.shortDate("2026-10-19T12:00:00Z"), "Oct 19")
    }

    // MARK: SecurityScreen

    func testTruncateNpub() {
        let hex = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        XCTAssertEqual(SecurityScreen.truncateNpub(hex), "npub180cvv07t...wsyjh6w6")
    }

    // MARK: RelativeTime (beyond LogicTests)

    func testRelativeTimeHoursDaysAndDate() {
        let now = Date()
        XCTAssertEqual(RelativeTime.format(now.addingTimeInterval(-2 * 3600), now: now), t("shared.tx.hoursAgo", ["n": "2"]))
        XCTAssertEqual(RelativeTime.format(now.addingTimeInterval(-3 * 86_400), now: now), t("shared.tx.daysAgo", ["n": "3"]))
        let old = now.addingTimeInterval(-10 * 86_400)
        XCTAssertEqual(RelativeTime.format(old, now: now), old.formatted(date: .numeric, time: .omitted))
    }

    func testRelativeTimeFutureIsJustNow() {
        let now = Date()
        XCTAssertEqual(RelativeTime.format(now.addingTimeInterval(120), now: now), t("shared.tx.justNow"))
    }
}
