import AppKit
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

func XCTAssertTrue(
    _ condition: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) {}
#endif

#if canImport(ChooseBrowser)
@testable import ChooseBrowser
#else
struct ExecutionTarget: Equatable {
    let bundleIdentifier: String
    let displayName: String
    let applicationURL: URL
}

enum OpenExecutionFailureReason: Equatable {
    case loopPrevented
    case noTargets
    case openFailed
}

enum OpenExecutionResult: Equatable {
    case success(usedBundleIdentifier: String)
    case failure(OpenExecutionFailureReason)
}

protocol WorkspaceOpening {
    func open(
        _ urls: [URL],
        withApplicationAt applicationURL: URL,
        configuration: NSWorkspace.OpenConfiguration,
        completionHandler: @escaping (NSRunningApplication?, Error?) -> Void
    )
}

final class OpenExecutor {
    init(
        workspace: WorkspaceOpening,
        loopGuardTTL: TimeInterval = 2,
        now: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }
    ) {}

    func execute(
        requestURL: URL,
        preferredTargetBundleIdentifier: String?,
        discoveredTargets: [ExecutionTarget],
        configuredFallbackBundleIdentifier: String?
    ) async -> OpenExecutionResult {
        .failure(.openFailed)
    }
}
#endif

final class OpenExecutorTests: XCTestCase {
    private final class WorkspaceSpy: WorkspaceOpening {
        var openCallCount = 0
        var openedURLs: [[URL]] = []
        var openedApplicationURLs: [URL] = []
        var nextError: Error?

        func open(
            _ urls: [URL],
            withApplicationAt applicationURL: URL,
            configuration _: NSWorkspace.OpenConfiguration,
            completionHandler: @escaping (NSRunningApplication?, Error?) -> Void
        ) {
            openCallCount += 1
            openedURLs.append(urls)
            openedApplicationURLs.append(applicationURL)
            completionHandler(nil, nextError)
        }
    }

    private func target(_ bundleIdentifier: String) -> ExecutionTarget {
        ExecutionTarget(
            bundleIdentifier: bundleIdentifier,
            displayName: bundleIdentifier,
            applicationURL: URL(fileURLWithPath: "/Applications/\(bundleIdentifier).app")
        )
    }

    func testOpensWithExplicitApplicationURL() async {
        let workspace = WorkspaceSpy()
        let executor = OpenExecutor(workspace: workspace)
        let requestURL = URL(string: "https://example.com/path")!
        let safari = target("com.apple.Safari")

        let result = await executor.execute(
            requestURL: requestURL,
            preferredTargetBundleIdentifier: safari.bundleIdentifier,
            discoveredTargets: [safari],
            configuredFallbackBundleIdentifier: nil
        )

        XCTAssertEqual(result, .success(usedBundleIdentifier: "com.apple.Safari"))
        XCTAssertEqual(workspace.openCallCount, 1)
        XCTAssertEqual(workspace.openedURLs.first, [requestURL])
        XCTAssertEqual(workspace.openedApplicationURLs.first, safari.applicationURL)
    }

    func testBlocksReentrantDispatchWithinTTL() async {
        var currentTime: TimeInterval = 100
        let workspace = WorkspaceSpy()
        let executor = OpenExecutor(
            workspace: workspace,
            loopGuardTTL: 2,
            now: { currentTime }
        )

        let requestURL = URL(string: "https://example.com/path?x=1")!
        let safari = target("com.apple.Safari")

        let first = await executor.execute(
            requestURL: requestURL,
            preferredTargetBundleIdentifier: safari.bundleIdentifier,
            discoveredTargets: [safari],
            configuredFallbackBundleIdentifier: nil
        )

        currentTime += 1

        let second = await executor.execute(
            requestURL: requestURL,
            preferredTargetBundleIdentifier: safari.bundleIdentifier,
            discoveredTargets: [safari],
            configuredFallbackBundleIdentifier: nil
        )

        XCTAssertEqual(first, .success(usedBundleIdentifier: "com.apple.Safari"))
        XCTAssertEqual(second, .failure(.loopPrevented))
        XCTAssertEqual(workspace.openCallCount, 1)
    }

    func testUsesConfiguredFallbackWhenPreferredTargetMissing() async {
        let workspace = WorkspaceSpy()
        let executor = OpenExecutor(workspace: workspace)
        let requestURL = URL(string: "https://example.com")!
        let fallback = target("com.browser.fallback")
        let safari = target("com.apple.Safari")

        let result = await executor.execute(
            requestURL: requestURL,
            preferredTargetBundleIdentifier: "com.browser.missing",
            discoveredTargets: [safari, fallback],
            configuredFallbackBundleIdentifier: fallback.bundleIdentifier
        )

        XCTAssertEqual(result, .success(usedBundleIdentifier: fallback.bundleIdentifier))
        XCTAssertEqual(workspace.openCallCount, 1)
        XCTAssertEqual(workspace.openedApplicationURLs.first, fallback.applicationURL)
    }
}
