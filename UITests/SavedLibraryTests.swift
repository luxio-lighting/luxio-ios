import XCTest

final class SavedLibraryTests: XCTestCase {
    func testSavePlayAndDeleteGradient() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082"
        app.launch()
        let light = app.buttons["Library test"]
        XCTAssertTrue(light.waitForExistence(timeout: 15)); light.tap()
        let save = app.buttons["Save gradient"]
        XCTAssertTrue(save.waitForExistence(timeout: 10)); save.tap()
        let alert = app.alerts["Save gradient"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.tap(); alert.textFields.firstMatch.typeText("Evening sea")
        alert.buttons["Save"].tap()
        let search = app.textFields["Search saved items"]
        for _ in 0..<6 { if search.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("Evening sea")
        let play = app.buttons["Play Evening sea"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        if !play.isHittable { app.swipeUp() }
        let saved = XCTAttachment(screenshot: app.screenshot()); saved.name = "Saved gradient library"; saved.lifetime = .keepAlways; add(saved)
        play.tap()
        let stop = app.buttons["Stop Evening sea"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        stop.press(forDuration: 1)
        app.buttons["Delete"].tap()
        let deletion = app.alerts["Delete saved item?"]
        XCTAssertTrue(deletion.waitForExistence(timeout: 5)); deletion.buttons["Delete"].tap()
        XCTAssertTrue(play.waitForNonExistence(timeout: 10))
        XCTAssertTrue(stop.waitForNonExistence(timeout: 10))
    }
}
