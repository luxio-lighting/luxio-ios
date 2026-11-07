import XCTest

final class StoreScreenshots: XCTestCase {
    func testStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-luxio.simulator.enabled", "NO", "-luxio.simulator.snapshot", ""]
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:1"
        app.launch()
        XCTAssertTrue(app.buttons["Try the Simulator"].waitForExistence(timeout: 20))
        app.buttons["Try the Simulator"].tap()
        XCTAssertTrue(app.segmentedControls["Light mode"].waitForExistence(timeout: 5))
        for mode in ["Color", "Gradient", "Animation"] {
            app.segmentedControls.buttons[mode].tap()
            if mode == "Animation" {
                XCTAssertTrue(app.buttons["Play Rainbow"].waitForExistence(timeout: 5))
                app.buttons["Play Rainbow"].tap()
                XCTAssertTrue(app.buttons["Settings for Rainbow"].waitForExistence(timeout: 5))
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Store-" + mode
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }
}
