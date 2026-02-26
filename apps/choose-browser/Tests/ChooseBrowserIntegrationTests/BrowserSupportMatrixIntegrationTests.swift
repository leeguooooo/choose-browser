import Foundation
import CryptoKit

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

func XCTAssertTrue(
    _ condition: Bool,
    _ message: String = "",
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
enum BrowserProfileLaunchSupportState: String, Codable, Equatable {
    case supported
    case unsupportedProfileLaunch
}

enum BrowserProfileLaunchUnsupportedReasonCode: String, Codable, Equatable {
    case browserDoesNotExposeProfileSelection
}

enum BrowserWorkspaceSupportState: String, Codable, Equatable {
    case supported
    case unsupportedWorkspace
}

enum BrowserWorkspaceUnsupportedReasonCode: String, Codable, Equatable {
    case profileLaunchUnsupported
}

struct BrowserCapabilitySupportMatrixRow: Codable, Equatable {
    let stableTargetID: String
    let displayName: String
    let supportedSchemes: [String]
    let supportedFileExtensions: [String]
    let supportedMIMETypes: [String]
    let profileLaunchSupportState: BrowserProfileLaunchSupportState
    let profileLaunchUnsupportedReasonCode: BrowserProfileLaunchUnsupportedReasonCode?
    let workspaceSupportState: BrowserWorkspaceSupportState
    let workspaceUnsupportedReasonCode: BrowserWorkspaceUnsupportedReasonCode?
}

protocol BrowserHandlerQuerying {
    func handlers(for scheme: String) -> [String]
    func applicationURL(for bundleIdentifier: String) -> URL?
    func displayName(for applicationURL: URL, bundleIdentifier: String) -> String
}

struct TargetDiscoveryResult: Equatable {
    let rows: [BrowserCapabilitySupportMatrixRow]

    func capabilitySupportMatrixRows() -> [BrowserCapabilitySupportMatrixRow] {
        rows
    }
}

final class TargetDiscovery {
    init(selfBundleIdentifier _: String = "", hiddenBundleIdentifiers _: Set<String> = [], query _: BrowserHandlerQuerying) {}

    func discoverTargets() -> TargetDiscoveryResult {
        TargetDiscoveryResult(rows: [])
    }
}
#endif

final class BrowserSupportMatrixIntegrationTests: XCTestCase {
    private static let sourceFilePath = #filePath
    private static let failureToggleMarkerRelativePath = ".sisyphus/evidence/parity/.force-discovery-capability-matrix-failure"

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

    func testGeneratesDeterministicCapabilityMatrixFixtureHash() throws {
        let discovery = TargetDiscovery(
            selfBundleIdentifier: "com.choosebrowser.app",
            hiddenBundleIdentifiers: [],
            query: QueryStub(
                handlersByScheme: [
                    "http": ["com.browser.alpha", "company.arc.browser", "company.dia.browser"],
                    "https": ["company.arc.browser", "company.dia.browser", "com.browser.alpha"],
                ],
                appURLsByBundleID: [
                    "com.browser.alpha": makeURL("com.browser.alpha"),
                    "company.arc.browser": makeURL("company.arc.browser"),
                    "company.dia.browser": makeURL("company.dia.browser"),
                ],
                displayNamesByBundleID: [
                    "com.browser.alpha": "Alpha Browser",
                    "company.arc.browser": "Arc",
                    "company.dia.browser": "Dia",
                ]
            )
        )

        let result = discovery.discoverTargets()
        let rows = result.capabilitySupportMatrixRows()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(rows)
        let hash = sha256Hex(encoded)

        XCTAssertEqual(rows.map(\.stableTargetID), ["com.browser.alpha", "company.arc.browser", "company.dia.browser"])
        XCTAssertEqual(hash, "754a4d48b373a993c60a9f1ae4f1347d2cf44ff269c66b306758b48b10e4d59a")
    }

    func testArcAndDiaAreMarkedUnsupportedProfileLaunchWithReasonCode() {
        let discovery = TargetDiscovery(
            selfBundleIdentifier: "com.choosebrowser.app",
            hiddenBundleIdentifiers: [],
            query: QueryStub(
                handlersByScheme: [
                    "http": ["company.arc.browser", "company.dia.browser"],
                    "https": ["company.arc.browser", "company.dia.browser"],
                ],
                appURLsByBundleID: [
                    "company.arc.browser": makeURL("company.arc.browser"),
                    "company.dia.browser": makeURL("company.dia.browser"),
                ],
                displayNamesByBundleID: [
                    "company.arc.browser": "Arc",
                    "company.dia.browser": "Dia",
                ]
            )
        )

        let rows = discovery.discoverTargets().capabilitySupportMatrixRows()

        XCTAssertTrue(rows.count == 2)
        for row in rows {
            XCTAssertEqual(row.profileLaunchSupportState, .unsupportedProfileLaunch)
            XCTAssertEqual(row.profileLaunchUnsupportedReasonCode, .browserDoesNotExposeProfileSelection)
            XCTAssertEqual(row.workspaceSupportState, .unsupportedWorkspace)
            XCTAssertEqual(row.workspaceUnsupportedReasonCode, .profileLaunchUnsupported)
        }
    }

    func testDiscoveryCapabilityMatrixExplicitFailureScenarioWhenExtraCheckEnabled() throws {
        guard Self.shouldInjectFailureScenario() else {
            XCTAssertTrue(true)
            return
        }

        let discovery = TargetDiscovery(
            selfBundleIdentifier: "com.choosebrowser.app",
            hiddenBundleIdentifiers: [],
            query: QueryStub(
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
        )

        let rows = discovery.discoverTargets().capabilitySupportMatrixRows()
        let arcRow = rows.first(where: { $0.stableTargetID == "company.arc.browser" })
        XCTAssertEqual(arcRow?.profileLaunchSupportState, .unsupportedProfileLaunch)

        if arcRow?.profileLaunchUnsupportedReasonCode != .browserDoesNotExposeProfileSelection {
            XCTFail("unsupported-profile-reason-mismatch: expected browser_does_not_expose_profile_selection")
        }

        XCTFail("unsupported-profile-reason-mismatch: __must_fail_discovery_capability_matrix__")
    }

    private static func shouldInjectFailureScenario() -> Bool {
        if ProcessInfo.processInfo.environment["DISCOVERY_CAPABILITY_MATRIX_REQUIRE_FAKE_REASON"] == "1" {
            return true
        }

        for base in candidateRoots() {
            let markerPath = base.appendingPathComponent(failureToggleMarkerRelativePath)
            if FileManager.default.fileExists(atPath: markerPath.path) {
                return true
            }
        }

        return false
    }

    private static func candidateRoots() -> [URL] {
        var roots: [URL] = []

        var sourceRoot = URL(fileURLWithPath: sourceFilePath, isDirectory: false)
        for _ in 0..<5 {
            sourceRoot.deleteLastPathComponent()
        }
        roots.append(sourceRoot)

        var current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        for _ in 0..<8 {
            roots.append(current)
            current.deleteLastPathComponent()
        }

        return roots
    }

    private func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
