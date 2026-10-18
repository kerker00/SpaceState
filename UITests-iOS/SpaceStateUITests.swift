import XCTest

/// Runs the Debug app with fixed sample data (see `UITestFixtures`): no network,
/// no SpacePush, no APNs and a settings suite that starts empty on every launch.
final class SpaceStateUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @discardableResult
    @MainActor private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFixtures", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + arguments
        app.launch()
        self.app = app
        addTeardownBlock { @MainActor in app.terminate() }
        return app
    }

    @MainActor private func text(containing value: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }

    @MainActor private func assertExists(_ element: XCUIElement, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), message, file: file, line: line)
    }

    // MARK: First run

    @MainActor func testFirstRunListsSpacesAndSearchesNamesAndAddresses() {
        launch()
        assertExists(app.staticTexts["Choose your space"])
        for name in ["Mainframe", "Chaosdorf", "LeineLab", "/dev/tal"] {
            assertExists(app.buttons[name], name)
        }
        let search = app.textFields["Search spaces"]
        search.tap()
        search.typeText("Hannover")
        assertExists(app.buttons["LeineLab"])
        XCTAssertFalse(app.buttons["Chaosdorf"].exists)

        search.typeText("xyz")
        assertExists(text(containing: "No Results"))
    }

    @MainActor func testFirstRunCanSkipNotifications() {
        launch()
        assertExists(app.buttons["LeineLab"])
        app.buttons["LeineLab"].tap()
        assertExists(app.staticTexts["Stay up to date"])
        assertExists(app.staticTexts["LeineLab"])
        app.buttons["Not now"].tap()
        assertExists(app.navigationBars["LeineLab"])
        assertExists(app.staticTexts["Closed"])
        assertExists(text(containing: "next meetup"))
    }

    @MainActor func testFirstRunCanEnableNotifications() {
        launch()
        assertExists(app.buttons["Mainframe"])
        app.buttons["Mainframe"].tap()
        app.buttons["Enable notifications"].tap()
        assertExists(app.navigationBars["Mainframe"])
        app.buttons["Settings"].tap()
        let toggle = app.switches["Notify me when the state changes"]
        assertExists(toggle)
        XCTAssertEqual(toggle.value as? String, "1")
        assertExists(text(containing: "You will be notified about the selected space."))
    }

    // MARK: Status

    @MainActor func testStatusShowsMessageRoomsAndSensors() {
        launch("-UITestOnboarded")
        assertExists(app.navigationBars["Mainframe"])
        assertExists(app.staticTexts["Open"])
        assertExists(text(containing: "Welcome to the hackerspace!"))
        for room in ["Space", "Radstelle", "3D Lab"] { assertExists(app.staticTexts[room], room) }
        assertExists(app.staticTexts["Open+"])
        assertExists(app.staticTexts["Members only"])
        assertExists(text(containing: "Visitors"))
        assertExists(text(containing: "21.5 °C"))
        assertExists(text(containing: "620 ppm"))
    }

    @MainActor func testDarkModeShowsTheSameStatus() {
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = .light }
        launch("-UITestOnboarded")
        assertExists(app.navigationBars["Mainframe"])
        assertExists(app.staticTexts["Open"])
    }

    @MainActor func testDetailsShowAddressContactsAndFeeds() {
        launch("-UITestOnboarded")
        assertExists(app.buttons["Space details"])
        app.buttons["Space details"].tap()
        assertExists(app.staticTexts["Address"])
        assertExists(text(containing: "Bahnhofsplatz 10"))
        app.swipeUp()
        assertExists(app.staticTexts["Contacts"])
        assertExists(text(containing: "info@mainframe.example"))
        app.swipeUp()
        assertExists(app.staticTexts["Feeds"])
        assertExists(app.staticTexts["Projects"])
    }

    // MARK: Settings

    @MainActor func testSettingsChangeTheSelectedSpace() {
        launch("-UITestOnboarded")
        assertExists(app.buttons["Settings"])
        app.buttons["Settings"].tap()
        assertExists(app.navigationBars["Settings"])
        // The settings row names the selected space; the status behind it has a room called "Space".
        let spaceRow = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Mainframe'")).firstMatch
        assertExists(spaceRow)
        spaceRow.tap()
        let search = app.searchFields["Search spaces"]
        assertExists(search)
        search.tap()
        search.typeText("Chaos")
        assertExists(app.buttons["Chaosdorf"])
        app.buttons["Chaosdorf"].tap()
        // Choosing a space returns to the settings by itself.
        assertExists(app.navigationBars["Settings"])
        assertExists(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Chaosdorf'")).firstMatch)
        app.buttons["Done"].tap()
        assertExists(app.navigationBars["Chaosdorf"])
    }

    @MainActor func testRefusedNotificationsPointToSystemSettings() {
        launch("-UITestOnboarded", "-UITestPushEnabled", "-UITestPushDenied")
        assertExists(app.buttons["Settings"])
        app.buttons["Settings"].tap()
        assertExists(text(containing: "Notifications are turned off in System Settings."))
        assertExists(app.buttons["Open notification settings"])
    }

    @MainActor func testTurningNotificationsOnAndOff() {
        launch("-UITestOnboarded")
        app.buttons["Settings"].tap()
        let toggle = app.switches["Notify me when the state changes"]
        assertExists(toggle)
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.switches.firstMatch.tap()
        assertExists(text(containing: "You will be notified about the selected space."))
        toggle.switches.firstMatch.tap()
        let off = NSPredicate(format: "value == '0'")
        expectation(for: off, evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
    }

    // MARK: Links

    @MainActor func testStatusLinkOpensATemporarySpace() throws {
        launch("-UITestOnboarded")
        assertExists(app.navigationBars["Mainframe"])
        var components = URLComponents()
        components.scheme = "spacestate"
        components.host = "status"
        components.queryItems = [URLQueryItem(name: "endpoint", value: "https://chaosdorf.example/spaceapi.json")]
        app.open(try XCTUnwrap(components.url))
        assertExists(app.navigationBars["Chaosdorf"])
        assertExists(text(containing: "Your selected space stays unchanged."))
        app.buttons["Done"].tap()
        assertExists(app.navigationBars["Mainframe"])
    }
}
