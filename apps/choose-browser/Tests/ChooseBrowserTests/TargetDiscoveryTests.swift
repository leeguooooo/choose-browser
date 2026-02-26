import Foundation

#if canImport(XCTest)
import XCTest
#else
class XCTestCase {}

func XCTAssertEqual<T: Equatable>(
    _ lhs: T,
    _ rhs: T,
    file: StaticString = #filePath,
    line: UInt = #line
) {}

func XCTAssertNil<T>(
    _ value: T?,
    file: StaticString = #filePath,
    line: UInt = #line
) {}
#endif

#if canImport(ChooseBrowser)
@testable import ChooseBrowser
#else
struct BrowserTarget: Equatable {
    let id: String
    let displayName: String
    let applicationURL: URL
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
    func setHiddenBundleIdentifiers(_ hiddenBundleIdentifiers: Set<String>) {}
    func discoverTargets() -> TargetDiscoveryResult { TargetDiscoveryResult(candidates: [], failureReason: .noTargets) }
    func availableTargets() -> [BrowserTarget] { [] }
}
#endif

final class TargetDiscoveryTests: XCTestCase {
    private final class QueryStub: BrowserHandlerQuerying {
        let handlersByScheme: [String: [String]]
        let appURLsByBundleID: [String: URL]
        let displayNamesByBundleID: [String: String]

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

    func testExcludesSelfAppAndSortsByDisplayNameStably() {
        let query = QueryStub(
            handlersByScheme: [
                "http": [
                    "com.choosebrowser.app",
                    "com.browser.beta",
                    "com.browser.alpha",
                    "com.browser.charlie",
                ],
                "https": [
                    "com.browser.beta",
                    "com.browser.alpha",
                ],
            ],
            appURLsByBundleID: [
                "com.browser.alpha": makeURL("com.browser.alpha"),
                "com.browser.beta": makeURL("com.browser.beta"),
                "com.browser.charlie": makeURL("com.browser.charlie"),
            ],
            displayNamesByBundleID: [
                "com.browser.alpha": "A Browser",
                "com.browser.beta": "A Browser",
                "com.browser.charlie": "C Browser",
            ]
        )

        let discovery = TargetDiscovery(
            selfBundleIdentifier: "com.choosebrowser.app",
            hiddenBundleIdentifiers: [],
            query: query
        )

        let result = discovery.discoverTargets()

        XCTAssertEqual(result.candidates.map(\.id), [
            "com.browser.alpha",
            "com.browser.beta",
            "com.browser.charlie",
        ])
        XCTAssertNil(result.failureReason)
    }

    func testHiddenBundleIdentifiersAreExcluded() {
        let query = QueryStub(
            handlersByScheme: [
                "http": [
                    "com.browser.alpha",
                    "com.browser.beta",
                ],
                "https": [
                    "com.browser.alpha",
                    "com.browser.beta",
                ],
            ],
            appURLsByBundleID: [
                "com.browser.alpha": makeURL("com.browser.alpha"),
                "com.browser.beta": makeURL("com.browser.beta"),
            ],
            displayNamesByBundleID: [
                "com.browser.alpha": "Alpha",
                "com.browser.beta": "Beta",
            ]
        )

        let discovery = TargetDiscovery(
            selfBundleIdentifier: "com.choosebrowser.app",
            hiddenBundleIdentifiers: ["com.browser.beta"],
            query: query
        )

        XCTAssertEqual(discovery.availableTargets().map(\.id), ["com.browser.alpha"])
    }

    func testReturnsEmptyWhenAllCandidatesHiddenOrInvalid() {
        let query = QueryStub(
            handlersByScheme: [
                "http": ["com.browser.alpha", "com.browser.beta"],
                "https": ["com.browser.alpha", "com.browser.beta"],
            ],
            appURLsByBundleID: [
                "com.browser.alpha": makeURL("com.browser.alpha"),
            ],
            displayNamesByBundleID: [
                "com.browser.alpha": "Alpha",
                "com.browser.beta": "Beta",
            ]
        )

        let discovery = TargetDiscovery(
            selfBundleIdentifier: "com.choosebrowser.app",
            hiddenBundleIdentifiers: ["com.browser.alpha"],
            query: query
        )

        let result = discovery.discoverTargets()

        XCTAssertEqual(result.candidates, [])
        XCTAssertEqual(result.failureReason, .noTargets)
    }
}
