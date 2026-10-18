import XCTest
@testable import LaWallet

final class L10nTests: XCTestCase {
    func testPlaceholder() { XCTAssertEqual(t("common.back"), "Back") }
}
