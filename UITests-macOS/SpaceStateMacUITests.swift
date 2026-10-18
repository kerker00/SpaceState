import XCTest

/// Runs the Debug Mac app with fixed sample data (see `UITestFixtures`). The app uses
/// its own settings suite in this mode, so an installed SpaceState keeps its preferences.
final class SpaceStateMacUITests: XCTestCase {
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
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", value, value)).firstMatch
    }

    @MainActor private func assertExists(_ element: XCUIElement, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), message, file: file, line: line)
    }

    @MainActor private func openMenuBarPanel() {
        let item = app.statusItems.firstMatch
        assertExists(item)
        item.click()
    }

    @MainActor func testFirstRunWindowSelectsASpace() {
        launch()
        assertExists(app.windows["Set up SpaceState"])
        assertExists(app.buttons["Chaosdorf"])
        app.buttons["Chaosdorf"].click()
        assertExists(app.buttons["Not now"])
        app.buttons["Not now"].click()
        assertExists(app.windows["SpaceState"])
        assertExists(text(containing: "Chaosdorf"))
    }

    @MainActor func testMenuBarPanelShowsStatusRoomsAndSensors() {
        launch("-UITestOnboarded")
        openMenuBarPanel()
        assertExists(text(containing: "Mainframe"))
        assertExists(text(containing: "Welcome to the hackerspace!"))
        assertExists(text(containing: "Radstelle"))
        assertExists(text(containing: "Members only"))
        assertExists(text(containing: "21.5 °C"))
    }

    @MainActor func testPanelOpensDetailsWindow() {
        launch("-UITestOnboarded")
        openMenuBarPanel()
        let details = app.buttons["Space details"]
        assertExists(details)
        details.click()
        assertExists(app.windows["Space details"])
        assertExists(text(containing: "Bahnhofsplatz 10"))
        assertExists(text(containing: "info@mainframe.example"))
    }

    @MainActor func testSettingsSwitchSpaceAndGeneralTabs() {
        launch("-UITestOnboarded")
        openMenuBarPanel()
        let settings = app.buttons["Settings"]
        assertExists(settings)
        settings.click()
        let search = app.textFields["Search spaces"].exists ? app.textFields["Search spaces"] : app.searchFields["Search spaces"]
        assertExists(search)
        search.click()
        search.typeText("Leine")
        assertExists(app.buttons["LeineLab"])
        app.buttons["LeineLab"].click()

        let general = app.radioButtons["General"].exists ? app.radioButtons["General"] : app.buttons["General"]
        assertExists(general)
        general.click()
        assertExists(app.checkBoxes["Show in Dock"])
        assertExists(app.checkBoxes["Notify me when the state changes"])
        app.checkBoxes["Notify me when the state changes"].click()
        assertExists(text(containing: "You will be notified about the selected space."))

        openMenuBarPanel()
        assertExists(text(containing: "LeineLab"))
    }
}
