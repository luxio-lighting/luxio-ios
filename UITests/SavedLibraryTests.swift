import XCTest

final class SavedLibraryTests: XCTestCase {
    func testDeviceHeaderNameRemainsVisible() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-luxio.simulator.enabled", "NO"]
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/settings"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15))
        app.buttons["Library test"].tap()
        let title = app.staticTexts["device-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Library test")
        XCTAssertTrue(title.isHittable)
        XCTAssertGreaterThan(title.frame.width, 60)
        XCTAssertLessThan(title.frame.minX, 100)
        let header = XCTAttachment(screenshot: app.screenshot()); header.name = "Device header"; header.lifetime = .keepAlways; add(header)
    }

    func testSK6812SimulatorSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-luxio.simulator.enabled", "NO"]
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8087/unreachable"
        app.launch()
        XCTAssertTrue(app.buttons["Try the Simulator"].waitForExistence(timeout: 15)); app.buttons["Try the Simulator"].tap()
        XCTAssertTrue(app.buttons["Luxio settings"].waitForExistence(timeout: 5)); app.buttons["Luxio settings"].tap()
        XCTAssertTrue(app.buttons["settings-strip"].waitForExistence(timeout: 5)); app.buttons["settings-strip"].tap()
        app.buttons["SK6812"].tap()
        app.navigationBars["Settings"].buttons["Save"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Color"].waitForExistence(timeout: 5)); app.segmentedControls.buttons["Color"].tap()
        XCTAssertTrue(app.buttons["White channel"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["White temperature wheel"].exists)
        app.buttons["White channel"].tap()
        app.buttons["Luxio settings"].tap()
        XCTAssertTrue(app.buttons["settings-strip"].label.contains("SK6812"))
    }

    func testRadioSettingsAndWifiConfirmation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-luxio.simulator.enabled", "NO"]
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8087/settings"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15)); app.buttons["Library test"].tap()
        app.buttons["Luxio settings"].tap()
        let wifi = app.switches["settings-wifi-enabled"]
        for _ in 0..<4 where !wifi.isHittable { app.swipeUp() }
        XCTAssertEqual(wifi.value as? String, "1"); XCTAssertTrue(wifi.isEnabled)
        wifi.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        app.navigationBars["Settings"].buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Disable Wi-Fi"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        app.navigationBars["Settings"].buttons["Save"].tap()
        app.buttons["Disable Wi-Fi"].tap()
        XCTAssertTrue(app.buttons["Luxio settings"].waitForExistence(timeout: 5)); app.buttons["Luxio settings"].tap()
        for _ in 0..<4 where !wifi.isHittable { app.swipeUp() }
        XCTAssertEqual(wifi.value as? String, "0")
        wifi.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let matter = app.switches["settings-matter-enabled"]
        for _ in 0..<4 where !matter.isHittable { app.swipeUp() }
        XCTAssertTrue(matter.isEnabled); XCTAssertEqual(matter.value as? String, "1")
        matter.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        app.navigationBars["Settings"].buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Luxio settings"].waitForExistence(timeout: 5)); app.buttons["Luxio settings"].tap()
        for _ in 0..<4 where !matter.isHittable { app.swipeUp() }
        XCTAssertEqual(matter.value as? String, "0")
        XCTAssertFalse(app.buttons["Show Pairing Code"].exists)
    }

    func testRelaySettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-luxio.simulator.enabled", "NO"]
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8083/relay"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15)); app.buttons["Library test"].tap()
        XCTAssertTrue(app.buttons["Luxio settings"].waitForExistence(timeout: 5)); app.buttons["Luxio settings"].tap()
        let enabled = app.switches["settings-relay-enabled"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 5)); XCTAssertEqual(enabled.value as? String, "0")
        XCTAssertTrue(enabled.isEnabled)
        enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(enabled.value as? String, "1")
        let pin = app.textFields["settings-relay-gpio"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        let save = app.navigationBars["Settings"].buttons["Save"].firstMatch
        for value in ["55", "16", "12"] {
            pin.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
            pin.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (pin.value as? String ?? "").count) + value)
            XCTAssertEqual(save.isEnabled, value == "12")
        }
        app.switches["settings-relay-inverted"].coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap(); save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 10))
        app.buttons["Luxio settings"].tap()
        XCTAssertTrue(pin.waitForExistence(timeout: 5)); XCTAssertEqual(pin.value as? String, "12")
        XCTAssertEqual(enabled.value as? String, "1")
        XCTAssertEqual(app.switches["settings-relay-inverted"].value as? String, "1")
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Relay settings"; screenshot.lifetime = .keepAlways; add(screenshot)
        enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap(); save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 10)); app.buttons["Luxio settings"].tap()
        XCTAssertTrue(enabled.waitForExistence(timeout: 5)); XCTAssertEqual(enabled.value as? String, "0")
        XCTAssertFalse(pin.exists)
    }

    func testWifiSetupAndMatterCode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-luxio.simulator.enabled", "NO"]
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/wifi"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15)); app.buttons["Library test"].tap()
        XCTAssertTrue(app.buttons["Luxio settings"].waitForExistence(timeout: 5)); app.buttons["Luxio settings"].tap()
        XCTAssertTrue(app.buttons["Configure Wi-Fi"].waitForExistence(timeout: 5)); app.buttons["Configure Wi-Fi"].tap()
        let network = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Test Network")).firstMatch
        XCTAssertTrue(network.waitForExistence(timeout: 10))
        let networks = XCTAttachment(screenshot: app.screenshot()); networks.name = "Wi-Fi networks"; networks.lifetime = .keepAlways; add(networks)
        XCTAssertFalse(app.secureTextFields["wifi-password"].exists)
        network.tap()
        XCTAssertFalse(app.buttons["wifi-connect"].isEnabled)
        let password = app.secureTextFields["wifi-password"]
        password.tap(); password.typeText("wrong-password")
        app.buttons["wifi-connect"].tap()
        XCTAssertTrue(app.staticTexts["Incorrect fixture credentials"].waitForExistence(timeout: 10))
        app.buttons["Show password"].tap()
        let visiblePassword = app.textFields["wifi-password"]
        XCTAssertEqual(visiblePassword.value as? String, "wrong-password")
        visiblePassword.tap(); visiblePassword.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 14) + "test-password")
        XCTAssertFalse(app.staticTexts["Incorrect fixture credentials"].exists)
        app.buttons["Hide password"].tap()
        let credentials = XCTAttachment(screenshot: app.screenshot()); credentials.name = "Wi-Fi password"; credentials.lifetime = .keepAlways; add(credentials)
        XCTAssertTrue(app.buttons["wifi-connect"].isEnabled); app.buttons["wifi-connect"].tap()
        let success = app.staticTexts["You're connected"]
        XCTAssertTrue(success.waitForExistence(timeout: 15))
        let setup = XCTAttachment(screenshot: app.screenshot()); setup.name = "Wi-Fi setup"; setup.lifetime = .keepAlways; add(setup)
        app.buttons["wifi-done"].tap()
        app.swipeUp()
        app.buttons["Show Pairing Code"].tap()
        XCTAssertTrue(app.staticTexts["pairing-code"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["Matter Pairing QR Code"].exists)
    }

    func testWifiManualEntryDuringScan() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-luxio.simulator.enabled", "NO"]
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/wifi-slow"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15)); app.buttons["Library test"].tap()
        app.buttons["Luxio settings"].tap(); app.buttons["Configure Wi-Fi"].tap()
        XCTAssertTrue(app.staticTexts["Finding nearby networks…"].waitForExistence(timeout: 5))
        let scanning = XCTAttachment(screenshot: app.screenshot()); scanning.name = "Wi-Fi scanning"; scanning.lifetime = .keepAlways; add(scanning)
        app.buttons["wifi-other"].tap()
        let name = app.textFields["wifi-ssid"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Hidden Network")
        let password = app.secureTextFields["wifi-password"]; password.tap(); password.typeText("test-password")
        XCTAssertTrue(app.buttons["wifi-connect"].isEnabled); app.buttons["wifi-connect"].tap()
        XCTAssertTrue(app.staticTexts["You're connected"].waitForExistence(timeout: 15))
    }

    func testWifiOpenNetwork() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-luxio.simulator.enabled", "NO"]
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/wifi"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15)); app.buttons["Library test"].tap()
        app.buttons["Luxio settings"].tap(); app.buttons["Configure Wi-Fi"].tap()
        XCTAssertTrue(app.buttons["Open Network"].waitForExistence(timeout: 10)); app.buttons["Open Network"].tap()
        XCTAssertFalse(app.secureTextFields["wifi-password"].exists)
        XCTAssertTrue(app.buttons["wifi-connect"].isEnabled); app.buttons["wifi-connect"].tap()
        XCTAssertTrue(app.staticTexts["You're connected"].waitForExistence(timeout: 15))
    }

    func testVirtualLuxio() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-luxio.simulator.enabled", "NO"]
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/unreachable"
        app.launch()
        XCTAssertTrue(app.buttons["Try the Simulator"].waitForExistence(timeout: 15))
        let empty = XCTAttachment(screenshot: app.screenshot())
        empty.name = "Try the Simulator"; empty.lifetime = .keepAlways; add(empty)
        app.buttons["Try the Simulator"].tap()
        XCTAssertTrue(app.segmentedControls["Light mode"].waitForExistence(timeout: 3))
        app.segmentedControls.buttons["Color"].tap()
        XCTAssertTrue(app.buttons["White temperature wheel"].waitForExistence(timeout: 5))
        app.buttons["White temperature wheel"].tap()
        XCTAssertTrue(app.buttons["White temperature wheel"].isSelected)
        app.segmentedControls.buttons["Gradient"].tap()
        let point = app.buttons["Add point"]
        for _ in 0..<6 {
            if point.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.85)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)))
        }
        point.tap()
        XCTAssertTrue(app.buttons["Select point 3"].waitForExistence(timeout: 3))
        app.segmentedControls.buttons["Animation"].tap()
        XCTAssertTrue(app.buttons["Play Rainbow"].waitForExistence(timeout: 5))
        app.buttons["Play Rainbow"].tap()
        XCTAssertTrue(app.buttons["Settings for Rainbow"].waitForExistence(timeout: 5))
        let animation = XCTAttachment(screenshot: app.screenshot())
        animation.name = "Virtual Luxio animation"; animation.lifetime = .keepAlways; add(animation)
        app.buttons["Luxio settings"].tap()
        XCTAssertTrue(app.buttons["settings-strip"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Check for Updates"].exists)
        XCTAssertFalse(app.buttons["Show Pairing Code"].exists)
        XCTAssertFalse(app.textFields["settings-gpio"].exists)
        let settings = XCTAttachment(screenshot: app.screenshot())
        settings.name = "Virtual Luxio settings"; settings.lifetime = .keepAlways; add(settings)
        app.buttons["Remove Simulator"].tap()
        XCTAssertTrue(app.buttons["Try the Simulator"].waitForExistence(timeout: 5))
    }

    func testHomeSkeletonsAndEmptyState() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lastDiscoveredLightCount", "3"]
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/unreachable"
        app.launch()
        XCTAssertTrue(app.otherElements["light-skeleton-0"].waitForExistence(timeout: 3))
        let skeletons = XCTAttachment(screenshot: app.screenshot())
        skeletons.name = "Remembered device skeletons"; skeletons.lifetime = .keepAlways; add(skeletons)
        XCTAssertEqual(app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'light-skeleton-'")).count, 3)
        XCTAssertTrue(app.staticTexts["No Luxio Devices Found"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons["Library test"].exists)
        XCTAssertFalse(app.otherElements["light-skeleton-0"].exists)
        XCTAssertTrue(app.buttons["Add Luxio"].exists)
        XCTAssertFalse(app.buttons["Connect Luxio"].exists)
        XCTAssertFalse(app.staticTexts["Pull down to search again."].exists)
        let empty = XCTAttachment(screenshot: app.screenshot())
        empty.name = "No reachable lights"; empty.lifetime = .keepAlways; add(empty)
    }

    func testCachedDeviceOpensWithoutWaiting() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lastDiscoveredLightCount", "1"]
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/cached"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15))
        app.buttons["Library test"].tap()
        // State requests take 2.5 seconds; opening must not await another request.
        XCTAssertTrue(app.segmentedControls["Light mode"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.segmentedControls.buttons["Gradient"].isSelected)
        XCTAssertEqual(app.otherElements["Brightness"].value as? String, "6 percent")
        XCTAssertTrue(app.navigationBars.firstMatch.exists)
    }

    func testRenameSavedItems() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/rename"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15))
        app.buttons["Library test"].tap()
        for mode in ["Color", "Gradient", "Animation"] {
            app.segmentedControls.buttons[mode].tap()
            let oldName = "Saved " + mode.lowercased()
            let prefix = mode == "Animation" ? "Play " : "Apply "
            let tile = app.buttons[prefix + oldName]
            for _ in 0..<15 {
                if tile.exists && tile.isHittable { break }
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.85)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.3)))
            }
            XCTAssertTrue(tile.isHittable)
            tile.press(forDuration: 1)
            XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Delete"].exists)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = mode + " context menu"; screenshot.lifetime = .keepAlways; add(screenshot)
            app.buttons["Rename"].tap()
            let alert = app.alerts["Rename"]
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            let field = alert.textFields.firstMatch
            XCTAssertEqual(field.value as? String, oldName)
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldName.count))
            XCTAssertFalse(alert.buttons["Save"].isEnabled)
            field.typeText("Renamed " + mode)
            alert.buttons["Save"].tap()
            XCTAssertTrue(app.buttons[prefix + "Renamed " + mode].waitForExistence(timeout: 10))
            XCTAssertFalse(tile.exists)
        }
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15))
        app.buttons["Library test"].tap()
        for mode in ["Color", "Gradient", "Animation"] {
            app.segmentedControls.buttons[mode].tap()
            let tile = app.buttons[(mode == "Animation" ? "Play " : "Apply ") + "Renamed " + mode]
            for _ in 0..<15 {
                if tile.exists && tile.isHittable { break }
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.85)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.3)))
            }
            XCTAssertTrue(tile.exists)
        }
    }

    func testNewGradientPointStaysSelected() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/point-selection"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15))
        app.buttons["Library test"].tap()
        app.segmentedControls.buttons["Gradient"].tap()
        let add = app.buttons["Add point"]
        for _ in 0..<6 {
            if add.exists && add.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.85)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)))
        }
        for number in [3, 4] {
            add.tap()
            let added = app.buttons["Select point \(number)"]
            XCTAssertTrue(added.waitForExistence(timeout: 5))
            XCTAssertTrue(added.isSelected)
            // Cover both the write response and the following periodic device refresh.
            Thread.sleep(forTimeInterval: 5)
            XCTAssertTrue(added.isSelected)
            XCTAssertFalse(app.buttons["Select point 1"].isSelected)
            XCTAssertTrue(app.buttons["Remove point \(number)"].exists)
        }
    }

    func testWhitePickerMovesHorizontallyWithoutChangingTemperature() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/white-drag"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15))
        app.buttons["Library test"].tap()
        let point = app.otherElements["Color point 1"]
        XCTAssertTrue(point.waitForExistence(timeout: 10))
        let temperature = point.value as? String
        XCTAssertTrue(temperature?.hasPrefix("White temperature") == true)
        for distance in [70.0, -140.0] {
            let before = point.frame
            let start = point.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: distance, dy: 0)))
            XCTAssertEqual(point.frame.midX, before.midX + distance, accuracy: 2)
            XCTAssertEqual(point.frame.midY, before.midY, accuracy: 2)
            XCTAssertEqual(point.value as? String, temperature)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Free white picker"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testSaveTilesAppendPresets() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/save-tiles"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15))
        app.buttons["Library test"].tap()
        for mode in ["Color", "Gradient"] {
            app.segmentedControls.buttons[mode].tap()
            let save = app.buttons["save-preset"]
            for _ in 0..<15 {
                if save.exists && save.isHittable { break }
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.85)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.3)))
            }
            XCTAssertTrue(save.isHittable)
            XCTAssertEqual(save.label, "Save")
            XCTAssertTrue(app.staticTexts["saved-empty-state"].exists)
            XCTAssertTrue(app.staticTexts["Presets"].exists)
            XCTAssertTrue(app.staticTexts["Saved"].exists)
            XCTAssertLessThan(app.staticTexts["Presets"].frame.minY, app.staticTexts["Saved"].frame.minY)
            XCTAssertLessThan(app.staticTexts["Saved"].frame.maxY, save.frame.minY)
            let position = save.frame
            save.tap()
            let alert = app.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            XCTAssertEqual(alert.label, "Save " + mode)
            XCTAssertTrue(alert.staticTexts["Save a copy on Library test."].exists)
            alert.textFields.firstMatch.tap(); alert.textFields.firstMatch.typeText("Custom " + mode)
            alert.buttons["Save"].tap()
            let saved = app.buttons["Apply Custom " + mode]
            XCTAssertTrue(saved.waitForExistence(timeout: 10))
            XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["saved-empty-state"].exists)
            XCTAssertFalse(app.staticTexts["studio-hint"].exists)
            Thread.sleep(forTimeInterval: 0.5)
            XCTAssertEqual(saved.frame.minX, position.minX, accuracy: 1)
            XCTAssertEqual(saved.frame.minY, position.minY, accuracy: 1)
            XCTAssertTrue(save.frame.minY > saved.frame.minY || save.frame.minX > saved.frame.minX)
            XCTAssertEqual(app.buttons.matching(identifier: "save-preset").count, 1)
            saved.tap()
            expectation(for: NSPredicate(format: "value == 'Selected'"), evaluatedWith: saved)
            waitForExpectations(timeout: 10)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = mode + " save tile"; screenshot.lifetime = .keepAlways; add(screenshot)
            save.tap()
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            alert.buttons["Cancel"].tap()
            XCTAssertTrue(saved.exists)
        }
    }

    func testEmptySavedAnimations() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/save-tiles"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15))
        app.buttons["Library test"].tap()
        app.segmentedControls.buttons["Animation"].tap()
        XCTAssertTrue(app.staticTexts["saved-empty-state"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["saved-empty-state"].label, "No saved animations yet. To create your own animations, try Luxio Studio.")
        XCTAssertFalse(app.staticTexts["studio-hint"].exists)
        for _ in 0..<3 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.35)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.85)))
        }
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[cd] 'cancelled'")).firstMatch.exists)
    }

    func testColorWheelSwitchKeepsLayoutStable() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/slow"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15))
        app.buttons["Library test"].tap()
        app.segmentedControls.buttons["Color"].tap()
        let heading = app.staticTexts["Presets"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        let originalY = heading.frame.minY
        for wheel in ["White temperature wheel", "Color wheel"] {
            app.buttons[wheel].tap()
            Thread.sleep(forTimeInterval: 1)
            XCTAssertFalse(app.activityIndicators["Applying colors"].exists)
            XCTAssertEqual(heading.frame.minY, originalY, accuracy: 1)
            Thread.sleep(forTimeInterval: 6)
            XCTAssertEqual(heading.frame.minY, originalY, accuracy: 1)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Hue sorted colors"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testAnimationsAreReplacedRatherThanStopped() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/animations"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15))
        app.buttons["Library test"].tap()
        app.segmentedControls.buttons["Animation"].tap()
        let rainbow = app.buttons["preset-Rainbow"]
        let saved = app.buttons["Play Saved animation"]
        for animation in [rainbow, saved] {
            for _ in 0..<6 {
                if animation.isHittable { break }
                app.swipeUp()
            }
            animation.tap()
            expectation(for: NSPredicate(format: "value == 'Playing'"), evaluatedWith: animation)
            waitForExpectations(timeout: 10)
            animation.tap()
            expectation(for: NSPredicate(format: "value == 'Playing'"), evaluatedWith: animation)
            waitForExpectations(timeout: 10)
            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Stop '")).firstMatch.exists)
        }
        XCTAssertNotEqual(rainbow.value as? String, "Playing")
        app.segmentedControls.buttons["Gradient"].tap()
        let sunset = app.buttons["preset-Sunset"]
        for _ in 0..<6 { if sunset.isHittable { break }; app.swipeUp() }
        sunset.tap()
        expectation(for: NSPredicate(format: "value == 'Selected'"), evaluatedWith: sunset)
        waitForExpectations(timeout: 10)
        app.segmentedControls.buttons["Animation"].tap()
        for _ in 0..<6 { if rainbow.isHittable { break }; app.swipeDown() }
        rainbow.tap()
        expectation(for: NSPredicate(format: "value == 'Playing'"), evaluatedWith: rainbow)
        waitForExpectations(timeout: 10)
        app.segmentedControls.buttons["Color"].tap()
        let relax = app.buttons["color-Relax"]
        for _ in 0..<6 { if relax.isHittable { break }; app.swipeUp() }
        relax.tap()
        expectation(for: NSPredicate(format: "value == 'Selected'"), evaluatedWith: relax)
        waitForExpectations(timeout: 10)
    }

    func testFirmwareUpdateSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-luxio.simulator.enabled", "NO"]
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/update-install"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15)); app.buttons["Library test"].tap()
        app.buttons["Luxio settings"].tap()
        let check = app.buttons["Check for Updates"]
        for _ in 0..<5 where !check.isHittable { app.swipeUp() }
        check.tap()
        XCTAssertTrue(app.buttons["update-install"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Update Available"].exists)
        let available = XCTAttachment(screenshot: app.screenshot()); available.name = "Update available sheet"; available.lifetime = .keepAlways; add(available)
        app.buttons["Cancel"].tap()
        app.buttons["Update Available"].tap()
        app.buttons["update-install"].tap()
        XCTAssertTrue(app.staticTexts["Installing Update"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["update-install"].exists)
        XCTAssertTrue(app.staticTexts["25% downloaded"].waitForExistence(timeout: 8))
        let progress = XCTAttachment(screenshot: app.screenshot()); progress.name = "Update progress sheet"; progress.lifetime = .keepAlways; add(progress)
        XCTAssertTrue(app.staticTexts["100% downloaded"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons["update-done"].exists, "Download completion must not claim installation succeeded before reconnection")
        XCTAssertTrue(app.buttons["update-done"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Luxio is now running build 35."].exists)
        app.buttons["update-done"].tap()
        XCTAssertFalse(app.buttons["Update Available"].exists)
    }

    func testFirmwareUpdateFailureInSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-luxio.simulator.enabled", "NO"]
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/update-error"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15)); app.buttons["Library test"].tap()
        app.buttons["Luxio settings"].tap()
        let check = app.buttons["Check for Updates"]
        for _ in 0..<5 where !check.isHittable { app.swipeUp() }
        check.tap()
        XCTAssertTrue(app.buttons["update-install"].waitForExistence(timeout: 10)); app.buttons["update-install"].tap()
        XCTAssertTrue(app.staticTexts["Firmware signature verification failed"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.links["Open Recovery"].exists)
        XCTAssertFalse(app.buttons["update-done"].exists)
        XCTAssertTrue(app.buttons["update-close"].exists)
        let failure = XCTAttachment(screenshot: app.screenshot()); failure.name = "Update failure sheet"; failure.lifetime = .keepAlways; add(failure)
        app.buttons["update-close"].tap()
    }

    func testFirmwareUpdateCheck() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-luxio.simulator.enabled", "NO"]
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/updates"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15)); app.buttons["Library test"].tap()
        XCTAssertTrue(app.buttons["Luxio settings"].waitForExistence(timeout: 5)); app.buttons["Luxio settings"].tap()
        let check = app.buttons["Check for Updates"]
        XCTAssertTrue(check.waitForExistence(timeout: 5)); check.tap()
        let checking = app.buttons["Checking..."]
        XCTAssertTrue(checking.waitForExistence(timeout: 3))
        XCTAssertFalse(checking.isEnabled)
        XCTAssertTrue(app.activityIndicators.firstMatch.exists)
        let progress = XCTAttachment(screenshot: app.screenshot()); progress.name = "Checking for Updates"; progress.lifetime = .keepAlways; add(progress)
        let alert = app.alerts["Up to Date"]
        XCTAssertTrue(alert.waitForExistence(timeout: 12))
        XCTAssertTrue(alert.staticTexts["Your Luxio is running the latest firmware."].exists)
        let result = XCTAttachment(screenshot: app.screenshot()); result.name = "Firmware up to date"; result.lifetime = .keepAlways; add(result)
        alert.buttons["OK"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 3))
        XCTAssertTrue(check.isEnabled)
        XCTAssertFalse(checking.exists)
    }

    func testWifiSettingsDetails() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-luxio.simulator.enabled", "NO"]
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/settings"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15)); app.buttons["Library test"].tap()
        let title = app.descendants(matching: .any)["device-title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Library test")
        XCTAssertTrue(title.isHittable)
        XCTAssertGreaterThan(title.frame.width, 60)
        let header = XCTAttachment(screenshot: app.screenshot()); header.name = "Device header"; header.lifetime = .keepAlways; add(header)
        XCTAssertTrue(app.buttons["Luxio settings"].waitForExistence(timeout: 5)); app.buttons["Luxio settings"].tap()
        let connection = app.descendants(matching: .any)["connection-type"].firstMatch
        XCTAssertTrue(connection.waitForExistence(timeout: 5))
        XCTAssertEqual(connection.value as? String, "Wi-Fi")
        for (label, value) in [("SSID", "Home Wi-Fi"), ("IP Address", "127.0.0.1"), ("Gateway", "192.0.2.1"), ("DNS", "192.0.2.1, 1.1.1.1")] {
            for _ in 0..<3 where !app.staticTexts[label].exists { app.swipeUp() }
            XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 5))
            XCTAssertTrue(app.debugDescription.contains(value), "Missing \(label): \(value)")
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Wi-Fi settings details"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.swipeUp()
        let pairing = app.buttons["Show Pairing Code"]
        XCTAssertTrue(pairing.waitForExistence(timeout: 5)); pairing.tap()
        XCTAssertTrue(app.staticTexts["pairing-code"].waitForExistence(timeout: 5))
        let matter = XCTAttachment(screenshot: app.screenshot()); matter.name = "Matter pairing button"; matter.lifetime = .keepAlways; add(matter)
        app.swipeDown()
        let configure = app.buttons["Configure Wi-Fi"]
        if !configure.isHittable { app.swipeUp() }
        configure.tap()
        XCTAssertTrue(app.staticTexts["Choose a network"].waitForExistence(timeout: 5))
    }

    func testSettingsLayout() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/settings"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15))
        app.buttons["Library test"].tap()
        XCTAssertTrue(app.buttons["Luxio settings"].waitForExistence(timeout: 10))
        app.buttons["Luxio settings"].tap()
        let count = app.textFields["settings-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        let save = app.navigationBars.buttons["Save"]
        // Invalid numeric values must never reach the device.
        for value in ["0", "1025", "61"] {
            count.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
            count.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (count.value as? String ?? "").count) + value)
            XCTAssertEqual(save.isEnabled, value == "61")
        }
        let pin = app.textFields["settings-gpio"]
        for value in ["55", "17"] {
            pin.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
            pin.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (pin.value as? String ?? "").count) + value)
            XCTAssertEqual(save.isEnabled, value == "17")
        }
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 10))
        app.buttons["Luxio settings"].tap()
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertEqual(count.value as? String, "61")
        XCTAssertEqual(pin.value as? String, "17")
        app.buttons["Show Pairing Code"].tap()
        let code = app.staticTexts["pairing-code"]
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        app.swipeUp()
        app.buttons["copy-pairing-code"].tap()
        XCTAssertEqual(app.buttons["copy-pairing-code"].label, "Pairing Code Copied")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Settings with pairing code"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testListPowerExpansion() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/settings"
        app.launchArguments += ["-luxio.simulator.enabled", "YES"]
        app.launch()
        let power = app.switches["Luxio Simulator power"]
        XCTAssertTrue(power.waitForExistence(timeout: 10))
        let lowerCard = app.buttons["Library test"]
        XCTAssertTrue(lowerCard.waitForExistence(timeout: 10))
        if power.value as? String == "1" { power.tap() }
        XCTAssertEqual(power.value as? String, "0")
        XCTAssertFalse(app.descendants(matching: .any)["Luxio Simulator brightness"].firstMatch.isHittable)
        let collapsedY = lowerCard.frame.minY
        power.tap()
        XCTAssertEqual(power.value as? String, "1")
        XCTAssertEqual(lowerCard.frame.minY - collapsedY, 43, accuracy: 1)
        XCTAssertTrue(app.descendants(matching: .any)["Luxio Simulator brightness"].firstMatch.isHittable)
        power.tap()
        XCTAssertEqual(power.value as? String, "0")
        XCTAssertEqual(lowerCard.frame.minY, collapsedY, accuracy: 1)
        XCTAssertFalse(app.descendants(matching: .any)["Luxio Simulator brightness"].firstMatch.isHittable)
    }

    func testLiveAnimationPreviews() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/live"
        app.launch()
        let light = app.buttons["Library test"]
        XCTAssertTrue(light.waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1)
        let home1 = XCTAttachment(screenshot: app.screenshot()); home1.name = "Live home frame 1"; home1.lifetime = .keepAlways; add(home1)
        Thread.sleep(forTimeInterval: 0.7)
        let home2 = XCTAttachment(screenshot: app.screenshot()); home2.name = "Live home frame 2"; home2.lifetime = .keepAlways; add(home2)
        light.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.buttons.element(boundBy: 0).waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1)
        let header1 = XCTAttachment(screenshot: app.screenshot()); header1.name = "Live header frame 1"; header1.lifetime = .keepAlways; add(header1)
        Thread.sleep(forTimeInterval: 0.7)
        let header2 = XCTAttachment(screenshot: app.screenshot()); header2.name = "Live header frame 2"; header2.lifetime = .keepAlways; add(header2)
        app.switches["Power"].tap()
        Thread.sleep(forTimeInterval: 1)
        let off = XCTAttachment(screenshot: app.screenshot()); off.name = "Live preview powered off"; off.lifetime = .keepAlways; add(off)
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(light.waitForExistence(timeout: 5))
    }

    func testLoadingStaysInsideSelectedCard() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/slow"
        app.launch()
        let light = app.buttons["Library test"]
        XCTAssertTrue(light.waitForExistence(timeout: 15)); light.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.buttons.element(boundBy: 0).waitForExistence(timeout: 10))
        for (mode, first, second) in [
            ("Color", "color-Relax", "color-Read"),
            ("Color", "Apply Saved color 1", "Apply Saved color 2"),
            ("Gradient", "preset-Sunset", "preset-Lagoon"),
            ("Gradient", "Apply Saved gradient 1", "Apply Saved gradient 2"),
            ("Animation", "preset-Ember", "preset-Tidal"),
            ("Animation", "Play Saved animation 1", "Play Saved animation 2")
        ] {
            app.segmentedControls.buttons[mode].tap()
            let card = app.buttons[first]
            for _ in 0..<8 {
                if card.isHittable { break }
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.85)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.35)))
            }
            XCTAssertTrue(card.waitForExistence(timeout: 10)); card.tap()
            XCTAssertEqual(card.value as? String, "Loading")
            XCTAssertFalse(card.isEnabled)
            XCTAssertTrue(app.buttons[second].isEnabled)
            XCTAssertTrue(app.navigationBars.firstMatch.buttons.element(boundBy: 0).isEnabled)
            XCTAssertTrue(app.segmentedControls.buttons["Color"].isEnabled)
            let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Loading \(first)"; screenshot.lifetime = .keepAlways; add(screenshot)
            expectation(for: NSPredicate(format: "exists == true AND value != 'Loading' AND enabled == true"), evaluatedWith: card)
            waitForExpectations(timeout: 15)
        }
        // Other selections stay available and complete in tap order.
        let rainbow = app.buttons["preset-Rainbow"]
        for _ in 0..<4 { if rainbow.isHittable { break }; app.swipeDown() }
        rainbow.tap()
        app.buttons["preset-Colorloop"].tap()
        XCTAssertEqual(app.buttons["preset-Colorloop"].value as? String, "Loading")
        expectation(for: NSPredicate(format: "value == 'Playing'"), evaluatedWith: app.buttons["preset-Colorloop"])
        waitForExpectations(timeout: 20)
        XCTAssertNotEqual(rainbow.value as? String, "Playing")
    }

    func testInteractiveSwipeBack() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082"
        app.launch()
        let light = app.buttons["Library test"]
        XCTAssertTrue(light.waitForExistence(timeout: 15)); light.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.buttons.element(boundBy: 0).waitForExistence(timeout: 10))
        let navigation = XCTAttachment(screenshot: app.screenshot())
        navigation.name = "Native glass navigation"; navigation.lifetime = .keepAlways; add(navigation)
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        // A short, slow drag must cancel and leave the detail screen usable.
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(app.navigationBars.firstMatch.buttons.element(boundBy: 0).waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Animation"].tap()
        XCTAssertTrue(app.buttons["Play Ember"].waitForExistence(timeout: 5))
        for _ in 0..<2 {
            edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.1)
            XCTAssertTrue(app.navigationBars.firstMatch.buttons.element(boundBy: 0).waitForNonExistence(timeout: 5))
            XCTAssertTrue(light.waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Connect Luxio"].exists)
            light.tap()
            XCTAssertTrue(app.navigationBars.firstMatch.buttons.element(boundBy: 0).waitForExistence(timeout: 5))
        }
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(light.waitForExistence(timeout: 5))
    }

    func testGradientAndAnimationPreviews() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082"
        app.launch()
        let light = app.buttons["Library test"]
        XCTAssertTrue(light.waitForExistence(timeout: 15))
        let home = XCTAttachment(screenshot: app.screenshot()); home.name = "Home gradient"; home.lifetime = .keepAlways; add(home)
        light.tap()
        app.segmentedControls.buttons["Gradient"].tap()
        let sunset = app.buttons["Apply Sunset"]
        for _ in 0..<5 {
            if sunset.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.85)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.4)))
        }
        XCTAssertTrue(sunset.waitForExistence(timeout: 10)); sunset.tap()
        XCTAssertTrue(sunset.waitForExistence(timeout: 5))
        let gradient = XCTAttachment(screenshot: app.screenshot()); gradient.name = "Sunset header"; gradient.lifetime = .keepAlways; add(gradient)
        app.segmentedControls.buttons["Animation"].tap()
        let ember = app.buttons["Play Ember"]
        XCTAssertTrue(ember.waitForExistence(timeout: 10)); ember.tap()
        expectation(for: NSPredicate(format: "value == 'Playing'"), evaluatedWith: ember)
        waitForExpectations(timeout: 10)
        let animation = XCTAttachment(screenshot: app.screenshot()); animation.name = "Ember preview"; animation.lifetime = .keepAlways; add(animation)
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(light.waitForExistence(timeout: 5))
        let card = XCTAttachment(screenshot: app.screenshot()); card.name = "Home animation preview"; card.lifetime = .keepAlways; add(card)
    }

    func testAnimationParameters() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/parameters"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15)); app.buttons["Library test"].tap()
        XCTAssertFalse(app.sliders["Speed"].exists)
        let settings = app.buttons["Settings for Parameterized"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        let toggle = app.switches["Flicker"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10)); XCTAssertEqual(toggle.value as? String, "1")
        toggle.tap()
        expectation(for: NSPredicate(format: "value == '0'"), evaluatedWith: toggle); waitForExpectations(timeout: 10)
        let speed = app.sliders["Speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 5)); speed.adjust(toNormalizedSliderPosition: 0.75)
        let spacing = app.textFields["Spacing"]
        XCTAssertTrue(spacing.waitForExistence(timeout: 5))
        spacing.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        spacing.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (spacing.value as? String ?? "").count) + "12")
        app.keyboards.buttons["Done"].tap()
        expectation(for: NSPredicate(format: "value == '12.0'"), evaluatedWith: spacing); waitForExpectations(timeout: 10)
        XCTAssertFalse(app.buttons["Save parameters"].exists)
        app.buttons["animation-settings-done"].tap()
        XCTAssertTrue(spacing.waitForNonExistence(timeout: 5))
        app.buttons["preset-Ember"].tap()
        XCTAssertTrue(app.buttons["Settings for Ember"].waitForExistence(timeout: 10))
        app.buttons["Play Parameterized"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        XCTAssertTrue(spacing.waitForExistence(timeout: 5)); XCTAssertEqual(spacing.value as? String, "12.0")
        XCTAssertEqual(toggle.value as? String, "0")
        app.buttons["Reset to Defaults"].tap()
        expectation(for: NSPredicate(format: "value == '8.0'"), evaluatedWith: spacing); waitForExpectations(timeout: 10)
        XCTAssertEqual(toggle.value as? String, "1")
    }

    func testAnimationOptionsExplainOldFirmware() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/old-animation"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15)); app.buttons["Library test"].tap()
        XCTAssertFalse(app.sliders["Speed"].exists)
        XCTAssertFalse(app.buttons["Settings for Ember"].exists)
        app.buttons["preset-Ember"].tap()
        XCTAssertTrue(app.staticTexts["These animation presets require firmware build 21 or newer."].waitForExistence(timeout: 10))
    }

    func testSelectingOldPresetLoadsItsNewOptions() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/stale-animation"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15)); app.buttons["Library test"].tap()
        XCTAssertFalse(app.buttons["Settings for Ember"].exists)
        app.buttons["preset-Ember"].tap()
        XCTAssertTrue(app.buttons["Settings for Ember"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.sliders["Speed"].exists)
        app.buttons["Settings for Ember"].tap()
        XCTAssertTrue(app.sliders["Speed"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["Spacing"].exists)
        XCTAssertTrue(app.switches["Pulse"].exists)
    }

    func testPresetSettingsPersistLocallyAndReset() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/options"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15)); app.buttons["Library test"].tap()
        app.segmentedControls.buttons["Animation"].tap()
        let rainbow = app.buttons["preset-Rainbow"]
        XCTAssertTrue(rainbow.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Settings for Rainbow"].exists)
        let collapsedWidth = rainbow.frame.width
        let colorloop = app.buttons["preset-Colorloop"], aurora = app.buttons["preset-Aurora"]
        let emberY = app.buttons["preset-Ember"].frame.minY
        rainbow.tap()
        let settings = app.buttons["Settings for Rainbow"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(settings.frame.maxX - rainbow.frame.minX, collapsedWidth)
        XCTAssertLessThanOrEqual(settings.frame.maxX - rainbow.frame.minX, collapsedWidth + 45)
        XCTAssertLessThan(colorloop.frame.width, collapsedWidth)
        XCTAssertLessThan(aurora.frame.width, collapsedWidth)
        XCTAssertEqual(colorloop.frame.minY, rainbow.frame.minY, accuracy: 1)
        XCTAssertEqual(aurora.frame.minY, rainbow.frame.minY, accuracy: 1)
        XCTAssertEqual(app.buttons["preset-Ember"].frame.minY, emberY, accuracy: 1)
        XCTAssertFalse(app.buttons["Settings for Colorloop"].exists)
        XCTAssertFalse(app.sliders["Speed"].exists)
        let card = XCTAttachment(screenshot: app.screenshot()); card.name = "Selected animation card"; card.lifetime = .keepAlways; add(card)
        settings.tap()
        let period = app.textFields["Period"]
        XCTAssertTrue(period.waitForExistence(timeout: 5))
        period.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        period.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (period.value as? String ?? "").count) + "12")
        app.keyboards.buttons["Done"].tap()
        expectation(for: NSPredicate(format: "value == '12.0'"), evaluatedWith: period); waitForExpectations(timeout: 10)
        let reverse = app.switches["Reverse"]; reverse.tap()
        expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: reverse); waitForExpectations(timeout: 10)
        let popup = XCTAttachment(screenshot: app.screenshot()); popup.name = "Animation settings popup"; popup.lifetime = .keepAlways; add(popup)
        app.buttons["animation-settings-done"].tap()
        XCTAssertTrue(period.waitForNonExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15)); app.buttons["Library test"].tap()
        app.buttons["preset-Colorloop"].tap()
        XCTAssertTrue(app.buttons["Settings for Colorloop"].waitForExistence(timeout: 10))
        XCTAssertFalse(settings.exists)
        XCTAssertLessThan(rainbow.frame.width, collapsedWidth)
        XCTAssertLessThan(aurora.frame.width, collapsedWidth)
        XCTAssertEqual(aurora.frame.minY, colorloop.frame.minY, accuracy: 1)
        rainbow.tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        XCTAssertTrue(period.waitForExistence(timeout: 5)); XCTAssertEqual(period.value as? String, "12.0")
        XCTAssertEqual(reverse.value as? String, "1")
        app.buttons["Reset to Defaults"].tap()
        expectation(for: NSPredicate(format: "value == '20.0'"), evaluatedWith: period); waitForExpectations(timeout: 10)
        XCTAssertEqual(reverse.value as? String, "0")
        app.buttons["animation-settings-done"].tap()
        app.buttons["preset-Colorloop"].tap()
        XCTAssertTrue(app.buttons["Settings for Colorloop"].waitForExistence(timeout: 10)); rainbow.tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        XCTAssertTrue(period.waitForExistence(timeout: 5)); XCTAssertEqual(period.value as? String, "20.0")
        XCTAssertEqual(reverse.value as? String, "0")
    }

    func testAutomaticAnimationPresets() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/options"
        app.launch()
        XCTAssertTrue(app.buttons["Library test"].waitForExistence(timeout: 15)); app.buttons["Library test"].tap()
        app.segmentedControls.buttons["Animation"].tap()
        app.buttons["preset-Rainbow"].tap()
        XCTAssertTrue(app.buttons["Settings for Rainbow"].waitForExistence(timeout: 10))
        for name in ["Christmas", "Knight Rider", "Fireplace", "Candle", "Cyberpunk"] {
            let card = app.buttons["preset-\(name)"]
            for _ in 0..<4 {
                if card.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(card.isHittable); card.tap()
            expectation(for: NSPredicate(format: "value == 'Playing'"), evaluatedWith: card); waitForExpectations(timeout: 10)
            XCTAssertFalse(app.buttons["Settings for Rainbow"].exists)
            XCTAssertFalse(app.buttons["Settings for \(name)"].exists)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "New animation presets"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testSaveApplyAndDeleteGradient() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082"
        app.launch()
        let light = app.buttons["Library test"]
        XCTAssertTrue(light.waitForExistence(timeout: 15)); light.tap()
        let gradient = app.segmentedControls.buttons["Gradient"]
        XCTAssertTrue(gradient.waitForExistence(timeout: 10)); gradient.tap()
        let save = app.buttons["save-preset"]
        let addPoint = app.buttons["Add point"]
        if !addPoint.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.85)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.6)))
        }
        XCTAssertTrue(addPoint.waitForExistence(timeout: 5)); addPoint.tap()
        XCTAssertTrue(app.buttons["Select point 3"].waitForExistence(timeout: 5))
        let controls = XCTAttachment(screenshot: app.screenshot()); controls.name = "Gradient controls"; controls.lifetime = .keepAlways; add(controls)
        for _ in 0..<50 {
            if save.exists && save.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(save.isHittable); save.tap()
        let alert = app.alerts["Save Gradient"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.tap(); alert.textFields.firstMatch.typeText("Evening sea")
        alert.buttons["Save"].tap()
        let search = app.textFields["Search saved items"]
        for _ in 0..<50 {
            if search.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("Evening sea\n")
        let apply = app.buttons["Apply Evening sea"]
        XCTAssertTrue(apply.waitForExistence(timeout: 10))
        if !apply.isHittable { app.swipeUp() }
        let saved = XCTAttachment(screenshot: app.screenshot()); saved.name = "Saved gradient library"; saved.lifetime = .keepAlways; add(saved)
        apply.tap()
        expectation(for: NSPredicate(format: "value == 'Selected'"), evaluatedWith: apply); waitForExpectations(timeout: 10)
        apply.tap()
        expectation(for: NSPredicate(format: "value == 'Selected'"), evaluatedWith: apply); waitForExpectations(timeout: 10)
        XCTAssertFalse(app.buttons["Stop Evening sea"].exists)
        apply.press(forDuration: 1)
        app.buttons["Delete"].tap()
        let deletion = app.alerts["Delete saved item?"]
        XCTAssertTrue(deletion.waitForExistence(timeout: 5)); deletion.buttons["Delete"].tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 10))
    }
    func testSaveApplyAndDeleteColor() throws {
        let app = XCUIApplication(); app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082"; app.launch()
        let light = app.buttons["Library test"]; XCTAssertTrue(light.waitForExistence(timeout: 15)); light.tap()
        let color = app.segmentedControls.buttons["Color"]; XCTAssertTrue(color.waitForExistence(timeout: 10)); color.tap()
        let save = app.buttons["save-preset"]
        for _ in 0..<15 { if save.exists && save.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(save.isHittable); save.tap()
        let alert = app.alerts["Save Color"]; XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.tap(); alert.textFields.firstMatch.typeText("Evening blue"); alert.buttons["Save"].tap()
        let apply = app.buttons["Apply Evening blue"]
        for _ in 0..<6 {
            if apply.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.85)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.3)))
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Saved color library"; screenshot.lifetime = .keepAlways; add(screenshot)
        XCTAssertTrue(apply.waitForExistence(timeout: 10)); apply.tap(); apply.press(forDuration: 1)
        let deletion = app.alerts["Delete saved item?"]
        for _ in 0..<3 {
            if deletion.exists { break }
            let remove = app.buttons["Delete"]; XCTAssertTrue(remove.waitForExistence(timeout: 5)); remove.tap()
            if deletion.waitForExistence(timeout: 2) { break }
        }
        XCTAssertTrue(deletion.exists); deletion.buttons["Delete"].tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 10))
    }

    func testStripCapabilities() throws {
        for (path, gradient, white, temperature) in [("rgb-single", false, false, false), ("rgbw-single", false, true, false), ("rgbcct-two", true, false, true)] {
            let app = XCUIApplication(); app.launchEnvironment["LUXIO_UI_TEST_ADDRESS"] = "127.0.0.1:8082/\(path)"; app.launch()
            let light = app.buttons["Library test"]; XCTAssertTrue(light.waitForExistence(timeout: 15)); light.tap()
            XCTAssertTrue(app.segmentedControls.buttons["Color"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.segmentedControls.buttons["Gradient"].exists, gradient)
            XCTAssertEqual(app.buttons["White channel"].exists, white)
            XCTAssertEqual(app.buttons["White temperature wheel"].exists, temperature)
            if white {
                app.buttons["White channel"].tap()
                XCTAssertEqual(app.otherElements["Color point 1"].value as? String, "White channel")
            }
            app.terminate()
        }
    }

}
