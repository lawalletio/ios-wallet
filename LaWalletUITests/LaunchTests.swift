import XCTest

final class LaunchTests: XCTestCase {
    func testLaunches() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"]
        app.launch()
    }
}
