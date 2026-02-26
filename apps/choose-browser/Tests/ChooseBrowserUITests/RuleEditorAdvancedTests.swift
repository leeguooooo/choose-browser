#if canImport(XCTest)
import XCTest

final class RuleEditorAdvancedTests: ChooseBrowserUITestCase {
    private func displayedText(_ element: XCUIElement) -> String {
        if !element.label.isEmpty {
            return element.label
        }

        if let value = element.value as? String {
            return value
        }

        return ""
    }

    func testCreatesAdvancedRuleWithFanoutDispatchMode() {
        let app = launchApp(arguments: ["--uitest-onboarding-configured", "--uitest-show-advanced-panel"])

        let domainField = app.textFields["ruleEditor.domainField"]
        let pathField = app.textFields["ruleEditor.pathField"]
        XCTAssertTrue(domainField.waitForExistence(timeout: 5))
        XCTAssertTrue(pathField.waitForExistence(timeout: 5))

        domainField.click()
        domainField.typeText("example.com")

        pathField.click()
        pathField.typeText("/docs")

        let fanoutButton = app.buttons["ruleEditor.dispatch.fanout"]
        XCTAssertTrue(fanoutButton.waitForExistence(timeout: 2))
        fanoutButton.click()

        let saveButton = app.buttons["ruleEditor.saveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2))
        saveButton.click()

        let dispatchLabel = app.staticTexts["ruleEditor.dispatchModeLabel"]
        XCTAssertTrue(dispatchLabel.waitForExistence(timeout: 2))
        XCTAssertEqual(displayedText(dispatchLabel), "Dispatch mode: fanout")

        let countLabel = app.staticTexts["ruleEditor.savedRulesCountLabel"]
        XCTAssertTrue(countLabel.waitForExistence(timeout: 2))
        XCTAssertEqual(displayedText(countLabel), "Saved rules: 1")

        let firstSavedRule = app.staticTexts["ruleEditor.savedRule.0"]
        XCTAssertTrue(firstSavedRule.waitForExistence(timeout: 2))
        XCTAssertEqual(displayedText(firstSavedRule), "example.com/docs|fanout")
    }

    func testBlocksSaveWhenRequiredFieldsAreMissing() {
        let app = launchApp(arguments: ["--uitest-onboarding-configured", "--uitest-show-advanced-panel"])

        let saveButton = app.buttons["ruleEditor.saveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.click()

        let validationLabel = app.staticTexts["ruleEditor.validationLabel"]
        XCTAssertTrue(validationLabel.waitForExistence(timeout: 2))
        XCTAssertEqual(displayedText(validationLabel), "validation-error:domain-and-path-required")

        let countLabel = app.staticTexts["ruleEditor.savedRulesCountLabel"]
        XCTAssertTrue(countLabel.waitForExistence(timeout: 2))
        XCTAssertEqual(displayedText(countLabel), "Saved rules: 0")
    }
}
#else
class RuleEditorAdvancedTests {}
#endif
