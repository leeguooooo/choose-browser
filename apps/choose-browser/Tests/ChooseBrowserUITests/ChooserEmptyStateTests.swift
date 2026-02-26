#if canImport(XCTest)
import XCTest

final class ChooserEmptyStateTests: ChooseBrowserUITestCase {
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
        app.launchArguments = ["--uitest-empty-chooser"]
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

    func testShowsEmptyStateAndFallbackPrimaryAction() {
        let app = launchChooser()

        let chooserWindow = app.windows["ChooseBrowser"]
        XCTAssertTrue(chooserWindow.waitForExistence(timeout: 8), "chooser window should exist")

        app.activate()
        chooserWindow.click()

        let emptyStateByIdentifier = app.staticTexts["chooser.emptyStateText"]
        let emptyStateByText = app.staticTexts["No available browsers installed."]
        let emptyState = emptyStateByIdentifier.waitForExistence(timeout: 2) ? emptyStateByIdentifier : emptyStateByText
        XCTAssertTrue(
            emptyState.waitForExistence(timeout: 8),
            "empty state should be visible"
        )
        XCTAssertTrue(
            waitForElementText("No available browsers installed.", in: emptyState, timeout: 2),
            "empty state text should match"
        )
        XCTAssertFalse(app.buttons["chooser.appRow.0"].exists, "no browser options should be visible")
    }
}
#else
class ChooserEmptyStateTests {}
#endif
