#if canImport(XCTest)
import XCTest

final class ChooserKeyboardTests: ChooseBrowserUITestCase {
    private let appBundleIdentifier = "com.choosebrowser.app"
    private var appUnderTest: XCUIApplication?

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        terminateIfRunning()
    }

    override func tearDownWithError() throws {
        defer {
            appUnderTest = nil
            try? super.tearDownWithError()
        }

        guard let appUnderTest, appUnderTest.state != .notRunning else {
            return
        }

        appUnderTest.terminate()
        _ = appUnderTest.wait(for: .notRunning, timeout: 5)
    }

    private func terminateIfRunning() {
        let runningApp = XCUIApplication(bundleIdentifier: appBundleIdentifier)
        guard runningApp.state != .notRunning else {
            return
        }

        runningApp.terminate()
        _ = runningApp.wait(for: .notRunning, timeout: 5)
    }

    @discardableResult
    private func launchChooser() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-show-chooser"]
        app.launch()
        app.activate()
        appUnderTest = app
        return app
    }

    private func waitForElementText(_ expected: String, in element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate { [weak self] _, _ in
            self?.elementText(element) == expected
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    func testArrowDownSelectsNextRowAndEnterOpensSelection() {
        let app = launchChooser()

        let chooserWindow = app.windows["ChooseBrowser"]
        XCTAssertTrue(chooserWindow.waitForExistence(timeout: 8), "chooser window should exist")

        app.activate()
        chooserWindow.click()
        chooserWindow.typeKey(.downArrow, modifierFlags: [])
        chooserWindow.click()
        chooserWindow.typeKey(.return, modifierFlags: [])

        let lastActionLabel = app.staticTexts["chooser.lastActionLabel"]
        XCTAssertTrue(lastActionLabel.waitForExistence(timeout: 2), "last action label should exist")
        XCTAssertTrue(
            waitForElementText("Last action: opened:com.browser.beta", in: lastActionLabel, timeout: 12),
            "open action should be visible"
        )
        XCTAssertTrue(waitForNonExistence(app.buttons["chooser.appRow.0"], timeout: 12), "chooser should close after enter")
    }

    func testEscapeCancelsChooserWithoutDispatching() {
        let app = launchChooser()

        let chooserWindow = app.windows["ChooseBrowser"]
        XCTAssertTrue(chooserWindow.waitForExistence(timeout: 8), "chooser window should exist")

        app.activate()
        chooserWindow.typeKey(.escape, modifierFlags: [])

        let lastActionLabel = app.staticTexts["chooser.lastActionLabel"]
        XCTAssertTrue(lastActionLabel.waitForExistence(timeout: 2), "last action label should exist")
        XCTAssertTrue(
            waitForElementText("Last action: cancelled", in: lastActionLabel, timeout: 2),
            "cancel action should be visible"
        )
        XCTAssertTrue(waitForNonExistence(app.buttons["chooser.appRow.0"], timeout: 3), "chooser should close after escape")
    }
}
#else
class ChooserKeyboardTests {}
#endif
