import Foundation

#if canImport(XCTest)
import XCTest
#else
class XCTestCase {}

func XCTAssertEqual<T: Equatable>(
    _ lhs: T,
    _ rhs: T,
    file _: StaticString = #filePath,
    line _: UInt = #line
) {}

func XCTAssertNil(
    _ value: Any?,
    file _: StaticString = #filePath,
    line _: UInt = #line
) {}

func XCTFail(
    _ message: String = "",
    file _: StaticString = #filePath,
    line _: UInt = #line
) {}
#endif

#if canImport(ChooseBrowser)
@testable import ChooseBrowser
#else
enum BrowserProfileLaunchSupportState: Equatable {
    case supported
    case unsupportedProfileLaunch
}

enum BrowserProfileLaunchUnsupportedReasonCode: Equatable {
    case browserDoesNotExposeProfileSelection
}

struct BrowserProfileLaunchSupport: Equatable {
    let state: BrowserProfileLaunchSupportState
    let reasonCode: BrowserProfileLaunchUnsupportedReasonCode?
}

enum BrowserWorkspaceSupportState: Equatable {
    case supported
    case unsupportedWorkspace
}

enum BrowserWorkspaceUnsupportedReasonCode: Equatable {
    case profileLaunchUnsupported
}

struct BrowserWorkspaceSupport: Equatable {
    let state: BrowserWorkspaceSupportState
    let reasonCode: BrowserWorkspaceUnsupportedReasonCode?
}

struct BrowserTargetCapabilities: Equatable {
    let supportedSchemes: [String]
    let supportedFileExtensions: [String]
    let supportedMIMETypes: [String]
    let profileLaunchSupport: BrowserProfileLaunchSupport
    let workspaceSupport: BrowserWorkspaceSupport
}

struct BrowserTarget: Equatable {
    let id: String
    let displayName: String
    let applicationURL: URL
    let capabilities: BrowserTargetCapabilities
}

enum TargetDiscoveryFailureReason: Equatable {
    case noTargets
}

struct TargetDiscoveryResult: Equatable {
    let candidates: [BrowserTarget]
    let failureReason: TargetDiscoveryFailureReason?
}

protocol BrowserHandlerQuerying {
    func handlers(for scheme: String) -> [String]
    func applicationURL(for bundleIdentifier: String) -> URL?
    func displayName(for applicationURL: URL, bundleIdentifier: String) -> String
}

final class TargetDiscovery {
    init(selfBundleIdentifier: String = "", hiddenBundleIdentifiers: Set<String> = [], query: BrowserHandlerQuerying) {}
    func discoverTargets() -> TargetDiscoveryResult { TargetDiscoveryResult(candidates: [], failureReason: .noTargets) }
}
#endif

final class TargetDiscoveryCapabilityTests: XCTestCase {
    private final class QueryStub: BrowserHandlerQuerying {
        private let handlersByScheme: [String: [String]]
        private let appURLsByBundleID: [String: URL]
        private let displayNamesByBundleID: [String: String]

        init(
            handlersByScheme: [String: [String]],
            appURLsByBundleID: [String: URL],
            displayNamesByBundleID: [String: String]
        ) {
            self.handlersByScheme = handlersByScheme
            self.appURLsByBundleID = appURLsByBundleID
            self.displayNamesByBundleID = displayNamesByBundleID
        }

        func handlers(for scheme: String) -> [String] {
            handlersByScheme[scheme, default: []]
        }

        func applicationURL(for bundleIdentifier: String) -> URL? {
            appURLsByBundleID[bundleIdentifier]
        }

        func displayName(for applicationURL: URL, bundleIdentifier: String) -> String {
            displayNamesByBundleID[bundleIdentifier, default: bundleIdentifier]
        }
    }

    private func makeURL(_ bundleIdentifier: String) -> URL {
        URL(fileURLWithPath: "/Applications/\(bundleIdentifier).app")
    }

    func testDiscoversCapabilitiesForSchemesMimeExtensionsAndWorkspaceSupport() {
        let query = QueryStub(
            handlersByScheme: [
                "http": ["com.browser.alpha"],
                "https": ["com.browser.alpha"],
            ],
            appURLsByBundleID: [
                "com.browser.alpha": makeURL("com.browser.alpha"),
            ],
            displayNamesByBundleID: [
                "com.browser.alpha": "Alpha Browser",
            ]
        )
        let discovery = TargetDiscovery(
            selfBundleIdentifier: "com.choosebrowser.app",
            hiddenBundleIdentifiers: [],
            query: query
        )

        let result = discovery.discoverTargets()
        guard let target = result.candidates.first(where: { $0.id == "com.browser.alpha" }) else {
            XCTFail("Expected discovered target com.browser.alpha")
            return
        }

        XCTAssertEqual(target.id, "com.browser.alpha")
        XCTAssertEqual(target.capabilities.supportedSchemes, ["http", "https"])
        XCTAssertEqual(target.capabilities.supportedFileExtensions, ["htm", "html", "pdf", "xhtml"])
        XCTAssertEqual(target.capabilities.supportedMIMETypes, ["application/pdf", "application/xhtml+xml", "text/html"])
        XCTAssertEqual(target.capabilities.profileLaunchSupport.state, .supported)
        XCTAssertNil(target.capabilities.profileLaunchSupport.reasonCode)
        XCTAssertEqual(target.capabilities.workspaceSupport.state, .supported)
        XCTAssertNil(target.capabilities.workspaceSupport.reasonCode)
    }

    func testMarksArcLikeBrowsersAsUnsupportedForProfileLaunchWithReasonCode() {
        let query = QueryStub(
            handlersByScheme: [
                "http": ["company.arc.browser"],
                "https": ["company.arc.browser"],
            ],
            appURLsByBundleID: [
                "company.arc.browser": makeURL("company.arc.browser"),
            ],
            displayNamesByBundleID: [
                "company.arc.browser": "Arc",
            ]
        )
        let discovery = TargetDiscovery(
            selfBundleIdentifier: "com.choosebrowser.app",
            hiddenBundleIdentifiers: [],
            query: query
        )

        let result = discovery.discoverTargets()
        guard let target = result.candidates.first else {
            XCTFail("Expected discovered target for profile support assertion")
            return
        }

        XCTAssertEqual(target.capabilities.profileLaunchSupport.state, .unsupportedProfileLaunch)
        XCTAssertEqual(
            target.capabilities.profileLaunchSupport.reasonCode,
            .browserDoesNotExposeProfileSelection
        )
        XCTAssertEqual(target.capabilities.workspaceSupport.state, .unsupportedWorkspace)
        XCTAssertEqual(target.capabilities.workspaceSupport.reasonCode, .profileLaunchUnsupported)
    }
}
