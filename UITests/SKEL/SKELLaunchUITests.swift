import XCTest

// OWNER: SKEL. A launch smoke test on the phone (never the gesture gate, SPEC §16): the Bench appears with its title,
// the image window and the seven rail chips. Runs with `device-session "test --area SKEL"` under the simulator hold.
final class SKEL_LaunchSmokeUITests: XCTestCase {
    @MainActor func testBenchLaunches() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-B2Scenario", "bench"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Blur2ool"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.otherElements["Image window"].waitForExistence(timeout: 10) || app.images["Image window"].exists
                      || app.descendants(matching: .any)["Image window"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Floor '")).count >= 7)
    }
}
