#if canImport(XCTest)
import XCTest

final class ProfileWorkspaceChooserTests: ChooseBrowserUITestCase {
    private func displayedText(_ element: XCUIElement) -> String {
        if !element.label.isEmpty {
            return element.label
        }

        if let value = element.value as? String {
            return value
        }

        return ""
    }

    func testSelectsProfileAndWorkspaceThroughChooserControls() {
        let app = launchApp(arguments: ["--uitest-onboarding-configured"])

        let profileButton = app.buttons["profileWorkspace.profileOption.work"]
        let workspaceButton = app.buttons["profileWorkspace.workspaceOption.focus"]
        XCTAssertTrue(profileButton.waitForExistence(timeout: 5))
        XCTAssertTrue(workspaceButton.waitForExistence(timeout: 5))

        profileButton.click()
        workspaceButton.click()

        let selectedProfileLabel = app.staticTexts["profileWorkspace.selectedProfileLabel"]
        XCTAssertTrue(selectedProfileLabel.waitForExistence(timeout: 2))
        XCTAssertEqual(displayedText(selectedProfileLabel), "Profile: Work")

        let selectedWorkspaceLabel = app.staticTexts["profileWorkspace.selectedWorkspaceLabel"]
        XCTAssertTrue(selectedWorkspaceLabel.waitForExistence(timeout: 2))
        XCTAssertEqual(displayedText(selectedWorkspaceLabel), "Workspace: Focus")
    }
}
#else
class ProfileWorkspaceChooserTests {}
#endif
