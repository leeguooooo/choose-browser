#if canImport(XCTest)
import XCTest

final class OnboardingStatusTests: ChooseBrowserUITestCase {
    private func displayedText(_ element: XCUIElement) -> String {
        if !element.label.isEmpty {
            return element.label
        }

        if let value = element.value as? String {
            return value
        }

        return ""
    }

    func testShowsConfiguredStatusWhenHTTPAndHTTPSMatchApp() {
        let app = launchApp(arguments: ["--uitest-onboarding-configured"])

        let statusBadge = app.staticTexts["onboarding.statusBadge"]
        XCTAssertTrue(statusBadge.waitForExistence(timeout: 5))
        XCTAssertEqual(displayedText(statusBadge), "configured")
    }

    func testShowsPartialWhenOnlyHTTPSMatches() {
        let app = launchApp(arguments: ["--uitest-onboarding-partial"])

        let statusBadge = app.staticTexts["onboarding.statusBadge"]
        XCTAssertTrue(statusBadge.waitForExistence(timeout: 5))
        XCTAssertEqual(displayedText(statusBadge), "partial")

        XCTAssertTrue(app.buttons["onboarding.openSettingsButton"].waitForExistence(timeout: 2))
    }

    func testShowsNotConfiguredStatus() {
        let app = launchApp(arguments: ["--uitest-onboarding-not-configured"])

        let statusBadge = app.staticTexts["onboarding.statusBadge"]
        XCTAssertTrue(statusBadge.waitForExistence(timeout: 5))
        XCTAssertEqual(displayedText(statusBadge), "not configured")
    }

    func testFallbackSelectionPersistsAndIsUsedByProbe() {
        let suiteName = "uitest.settings.\(UUID().uuidString)"

        let firstLaunch = launchApp(arguments: [
            "--uitest-onboarding-configured",
            "--uitest-reset-settings",
            "--uitest-settings-suite",
            suiteName,
        ])

        let betaButton = firstLaunch.buttons["settings.fallbackOption.com.browser.beta"]
        XCTAssertTrue(betaButton.waitForExistence(timeout: 5))
        betaButton.click()

        let fallbackLabel = firstLaunch.staticTexts["settings.selectedFallbackLabel"]
        XCTAssertTrue(fallbackLabel.waitForExistence(timeout: 2))
        XCTAssertEqual(displayedText(fallbackLabel), "Fallback: Beta Browser")

        firstLaunch.buttons["settings.runFallbackProbeButton"].click()

        let lastActionLabel = firstLaunch.staticTexts["chooser.lastActionLabel"]
        XCTAssertTrue(lastActionLabel.waitForExistence(timeout: 2))
        XCTAssertEqual(displayedText(lastActionLabel), "Last action: opened:com.browser.beta")

        firstLaunch.terminate()

        let secondLaunch = launchApp(arguments: [
            "--uitest-onboarding-configured",
            "--uitest-settings-suite",
            suiteName,
        ])

        let persistedLabel = secondLaunch.staticTexts["settings.selectedFallbackLabel"]
        XCTAssertTrue(persistedLabel.waitForExistence(timeout: 5))
        XCTAssertEqual(displayedText(persistedLabel), "Fallback: Beta Browser")
    }
}
#else
class OnboardingStatusTests {}
#endif
