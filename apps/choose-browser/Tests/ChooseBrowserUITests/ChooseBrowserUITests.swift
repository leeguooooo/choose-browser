#if canImport(XCTest)
import XCTest
#else
class XCTestCase {}

class XCUIApplication {
    var launchArguments: [String] = []
    func launch() {}
}
#endif

class ChooseBrowserUITestCase: XCTestCase {
    #if canImport(XCTest)
    func launchApp(arguments: [String]) -> XCUIApplication {
        terminateIfRunning(bundleIdentifier: "com.choosebrowser.app")

        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), "app should launch in foreground")
        return app
    }

    func elementText(_ element: XCUIElement) -> String {
        if !element.label.isEmpty {
            return element.label
        }

        if let value = element.value as? String {
            return value
        }

        return ""
    }

    @discardableResult
    func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func terminateIfRunning(bundleIdentifier: String) {
        let runningApp = XCUIApplication(bundleIdentifier: bundleIdentifier)
        guard runningApp.state != .notRunning else {
            return
        }

        runningApp.terminate()
        _ = runningApp.wait(for: .notRunning, timeout: 5)
    }
    #endif
}
