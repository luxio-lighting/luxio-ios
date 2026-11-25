import XCTest

final class IPadMarketingScreenshots: XCTestCase {
    @MainActor func testCapture() async throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8093/0"
        app.launchEnvironment["LUXIO_MARKETING_DEVICES"] = "1"
        app.launchEnvironment["LUXIO_MARKETING_BLUETOOTH_NAME"] = "Studio"
        app.launch()
        XCTAssertTrue(app.buttons["Hallway"].waitForExistence(timeout: 20))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        XCTAssertTrue(app.buttons["Living Room"].isHittable)
        XCTAssertTrue(app.buttons["Hallway"].isHittable)
        XCTAssertEqual(app.switches["Hallway power"].value as? String, "0")
        for screen in ["home", "gradient", "animation", "settings", "matter"] {
            if screen == "home" { app.segmentedControls.buttons["Color"].tap() }
            if screen == "gradient" {
                app.segmentedControls.buttons["Gradient"].tap()
                XCTAssertTrue(app.buttons["Select point 2"].waitForExistence(timeout: 5))
            }
            if screen == "animation" {
                app.segmentedControls.buttons["Animation"].tap()
                app.buttons["Play Cyberpunk"].tap()
                let playing = expectation(for: NSPredicate(format: "value == %@", "Playing"), evaluatedWith: app.buttons["Play Cyberpunk"])
                await fulfillment(of: [playing], timeout: 10)
            }
            if screen == "settings" {
                app.buttons["Luxio settings"].tap()
                XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
            }
            if screen == "matter" {
                let pairing = app.buttons["Show Pairing Code"]
                for _ in 0..<8 where !pairing.isHittable { app.swipeUp(velocity: .slow) }
                XCTAssertTrue(pairing.isHittable); pairing.tap()
                XCTAssertTrue(app.images["Matter Pairing QR Code"].waitForExistence(timeout: 5))
                app.swipeUp(velocity: .slow)
            }
            try await Task.sleep(for: .seconds(2))
            let (_, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:8093/capture/" + screen)!)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        }
    }
}
