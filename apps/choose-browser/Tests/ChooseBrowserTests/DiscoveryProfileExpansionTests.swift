import Foundation

#if canImport(XCTest)
import XCTest
@testable import ChooseBrowser

final class DiscoveryProfileExpansionTests: XCTestCase {
    private final class QueryStub: BrowserHandlerQuerying {
        let bundleIDs: [String]
        init(bundleIDs: [String]) { self.bundleIDs = bundleIDs }

        func handlers(for scheme: String) -> [String] { bundleIDs }
        func applicationURL(for bundleIdentifier: String) -> URL? {
            URL(fileURLWithPath: "/Applications/\(bundleIdentifier).app")
        }

        func displayName(for applicationURL: URL, bundleIdentifier: String) -> String {
            bundleIdentifier == "com.google.chrome" ? "Google Chrome" : bundleIdentifier
        }
    }

    private struct ProfileReaderStub: ChromiumProfileReading {
        let profilesByBundleID: [String: [ChromiumProfile]]
        func profiles(forBundleIdentifier bundleIdentifier: String) -> [ChromiumProfile] {
            profilesByBundleID[bundleIdentifier] ?? []
        }
    }

    func testExpandsChromeIntoOneRowPerProfile() {
        let discovery = TargetDiscovery(
            query: QueryStub(bundleIDs: ["com.google.chrome"]),
            profileReader: ProfileReaderStub(profilesByBundleID: [
                "com.google.chrome": [
                    ChromiumProfile(directoryName: "Default", displayName: "Personal"),
                    ChromiumProfile(directoryName: "Profile 1", displayName: "Work"),
                ],
            ])
        )

        let targets = discovery.availableTargets()

        XCTAssertEqual(targets.count, 2)
        XCTAssertEqual(targets.map(\.displayName).sorted(), ["Google Chrome – Personal", "Google Chrome – Work"])
        // Every profile row keeps the real bundle id but a unique composite id.
        XCTAssertEqual(Set(targets.map(\.bundleIdentifier)), ["com.google.chrome"])
        XCTAssertEqual(Set(targets.map(\.id)).count, 2)
        let workTarget = targets.first { $0.displayName == "Google Chrome – Work" }
        XCTAssertEqual(workTarget?.launchArguments, ["--profile-directory=Profile 1"])
    }

    func testSingleProfileBrowserIsNotExpanded() {
        let discovery = TargetDiscovery(
            query: QueryStub(bundleIDs: ["com.google.chrome"]),
            profileReader: ProfileReaderStub(profilesByBundleID: [
                "com.google.chrome": [ChromiumProfile(directoryName: "Default", displayName: "Personal")],
            ])
        )

        let targets = discovery.availableTargets()

        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets.first?.id, "com.google.chrome")
        XCTAssertEqual(targets.first?.launchArguments, [])
    }
}
#endif
