import XCTest

final class MarketingScreenshots: XCTestCase {
    func testCapture() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-luxio.simulator.enabled", "NO"]
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8093/0"
        app.launchEnvironment["LUXIO_MARKETING_BLUETOOTH_NAME"] = "Studio"
        app.launch()
        XCTAssertTrue(app.buttons["Living Room"].waitForExistence(timeout: 15))
        for i in 1...4 {
            app.buttons["add-luxio"].tap()
            let field = app.textFields["add-luxio-address"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText("127.0.0.1:8093/\(i)")
            app.buttons["add-luxio-connect"].tap()
            XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 8))
            app.buttons["Back"].tap()
        }
        let home = XCTAttachment(screenshot: app.screenshot()); home.name = "Marketing-Home"; home.lifetime = .keepAlways; add(home)
        app.buttons["Living Room"].tap()
        app.segmentedControls.buttons["Gradient"].tap()
        let gradient = XCTAttachment(screenshot: app.screenshot()); gradient.name = "Marketing-Gradient"; gradient.lifetime = .keepAlways; add(gradient)
        app.segmentedControls.buttons["Animation"].tap()
        XCTAssertTrue(app.buttons["Play Cyberpunk"].waitForExistence(timeout: 5))
        for _ in 0..<3 where !app.buttons["Play Cyberpunk"].isHittable { app.swipeUp() }
        app.buttons["Play Cyberpunk"].tap()
        expectation(for: NSPredicate(format: "value == %@", "Playing"), evaluatedWith: app.buttons["Play Cyberpunk"])
        waitForExpectations(timeout: 5)
        let animation = XCTAttachment(screenshot: app.screenshot()); animation.name = "Marketing-Animation"; animation.lifetime = .keepAlways; add(animation)
        app.buttons["Luxio settings"].tap()
        Thread.sleep(forTimeInterval: 2)
        let settings = XCTAttachment(screenshot: app.screenshot()); settings.name = "Marketing-Settings"; settings.lifetime = .keepAlways; add(settings)
        let pairing = app.buttons["Show Pairing Code"]
        for _ in 0..<5 where !pairing.isHittable { app.swipeUp() }
        XCTAssertTrue(pairing.isHittable); pairing.tap()
        XCTAssertTrue(app.images["Matter Pairing QR Code"].waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.43)), withVelocity: .slow, thenHoldForDuration: 1)
        Thread.sleep(forTimeInterval: 2)
        let matter = XCTAttachment(screenshot: app.screenshot()); matter.name = "Marketing-Matter"; matter.lifetime = .keepAlways; add(matter)
    }
}
