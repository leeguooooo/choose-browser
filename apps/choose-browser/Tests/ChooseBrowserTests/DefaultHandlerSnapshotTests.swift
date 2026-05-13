import XCTest

@testable import ChooseBrowser

final class DefaultHandlerSnapshotTests: XCTestCase {
    func testConfiguredRequiresURLSchemesAndHTMLDocumentTypes() {
        let appBundleIdentifier = "com.choosebrowser.app"
        let snapshot = DefaultHandlerSnapshot(
            appBundleIdentifier: appBundleIdentifier,
            httpHandlerBundleIdentifier: appBundleIdentifier,
            httpsHandlerBundleIdentifier: appBundleIdentifier,
            htmlDocumentHandlerBundleIdentifier: appBundleIdentifier,
            xhtmlDocumentHandlerBundleIdentifier: appBundleIdentifier
        )

        XCTAssertEqual(snapshot.status, .configured)
    }

    func testMissingHTMLDocumentHandlerIsPartial() {
        let appBundleIdentifier = "com.choosebrowser.app"
        let snapshot = DefaultHandlerSnapshot(
            appBundleIdentifier: appBundleIdentifier,
            httpHandlerBundleIdentifier: appBundleIdentifier,
            httpsHandlerBundleIdentifier: appBundleIdentifier,
            htmlDocumentHandlerBundleIdentifier: "com.apple.Safari",
            xhtmlDocumentHandlerBundleIdentifier: appBundleIdentifier
        )

        XCTAssertEqual(snapshot.status, .partial)
    }
}
