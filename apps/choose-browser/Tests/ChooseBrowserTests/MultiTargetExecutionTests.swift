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
#endif

#if canImport(ChooseBrowser)
@testable import ChooseBrowser
#else
struct ExecutionTarget: Equatable {
    let bundleIdentifier: String
    let displayName: String
    let applicationURL: URL
}

enum ExecutionPlanDispatchModeV2 {
    case singleTarget
    case orderedFailover
    case fanout
}

enum MultiTargetExecutionOutcome: Equatable {
    case success
    case partialFailure
    case failure
}

enum TargetDispatchStatus: Equatable {
    case success
    case openFailed
    case missingTarget
}

struct TargetDispatchTrace: Equatable {
    let bundleIdentifier: String
    let status: TargetDispatchStatus
}

struct MultiTargetExecutionResult: Equatable {
    let outcome: MultiTargetExecutionOutcome
    let traces: [TargetDispatchTrace]

    var succeededBundleIdentifiers: [String] { [] }
    var failedBundleIdentifiers: [String] { [] }
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

    func executeMultiTarget(
        requestURL: URL,
        preferredTargetBundleIdentifiers: [String],
        discoveredTargets: [ExecutionTarget],
        dispatchMode: ExecutionPlanDispatchModeV2
    ) async -> MultiTargetExecutionResult {
        MultiTargetExecutionResult(outcome: .failure, traces: [])
    }
}
#endif

final class MultiTargetExecutionTests: XCTestCase {
    private struct SyntheticOpenError: Error {}

    private final class WorkspaceSpy: WorkspaceOpening {
        var openCallCount = 0
        var openedBundleIdentifiers: [String] = []
        var failingBundleIdentifiers: Set<String> = []

        func open(
            _: [URL],
            withApplicationAt applicationURL: URL,
            configuration _: NSWorkspace.OpenConfiguration,
            completionHandler: @escaping (NSRunningApplication?, Error?) -> Void
        ) {
            openCallCount += 1

            let bundleIdentifier = applicationURL
                .deletingPathExtension()
                .lastPathComponent
                .trimmingCharacters(in: .whitespacesAndNewlines)
            openedBundleIdentifiers.append(bundleIdentifier)

            if failingBundleIdentifiers.contains(bundleIdentifier) {
                completionHandler(nil, SyntheticOpenError())
                return
            }

            completionHandler(nil, nil)
        }
    }

    private func target(_ bundleIdentifier: String) -> ExecutionTarget {
        ExecutionTarget(
            bundleIdentifier: bundleIdentifier,
            displayName: bundleIdentifier,
            applicationURL: URL(fileURLWithPath: "/Applications/\(bundleIdentifier).app")
        )
    }

    func testOrderedFailoverStopsAtFirstSuccessfulTargetInDeterministicOrder() async {
        let workspace = WorkspaceSpy()
        workspace.failingBundleIdentifiers = ["com.browser.alpha"]
        let executor = OpenExecutor(workspace: workspace)
        let requestURL = URL(string: "https://example.com/report")!

        let result = await executor.executeMultiTarget(
            requestURL: requestURL,
            preferredTargetBundleIdentifiers: ["com.browser.alpha", "com.browser.beta", "com.browser.gamma"],
            discoveredTargets: [
                target("com.browser.alpha"),
                target("com.browser.beta"),
                target("com.browser.gamma"),
            ],
            dispatchMode: .orderedFailover
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.succeededBundleIdentifiers, ["com.browser.beta"])
        XCTAssertEqual(result.failedBundleIdentifiers, ["com.browser.alpha"])
        XCTAssertEqual(
            result.traces,
            [
                TargetDispatchTrace(bundleIdentifier: "com.browser.alpha", status: .openFailed),
                TargetDispatchTrace(bundleIdentifier: "com.browser.beta", status: .success),
            ]
        )
        XCTAssertEqual(workspace.openCallCount, 2)
        XCTAssertEqual(workspace.openedBundleIdentifiers, ["com.browser.alpha", "com.browser.beta"])
    }

    func testFanoutRecordsPartialFailureDeterministically() async {
        let workspace = WorkspaceSpy()
        workspace.failingBundleIdentifiers = ["com.browser.beta"]
        let executor = OpenExecutor(workspace: workspace)
        let requestURL = URL(string: "https://example.com/report")!

        let result = await executor.executeMultiTarget(
            requestURL: requestURL,
            preferredTargetBundleIdentifiers: ["com.browser.alpha", "com.browser.beta", "com.browser.gamma"],
            discoveredTargets: [
                target("com.browser.alpha"),
                target("com.browser.beta"),
                target("com.browser.gamma"),
            ],
            dispatchMode: .fanout
        )

        XCTAssertEqual(result.outcome, .partialFailure)
        XCTAssertEqual(result.succeededBundleIdentifiers, ["com.browser.alpha", "com.browser.gamma"])
        XCTAssertEqual(result.failedBundleIdentifiers, ["com.browser.beta"])
        XCTAssertEqual(
            result.traces,
            [
                TargetDispatchTrace(bundleIdentifier: "com.browser.alpha", status: .success),
                TargetDispatchTrace(bundleIdentifier: "com.browser.beta", status: .openFailed),
                TargetDispatchTrace(bundleIdentifier: "com.browser.gamma", status: .success),
            ]
        )
        XCTAssertEqual(workspace.openCallCount, 3)
        XCTAssertEqual(
            workspace.openedBundleIdentifiers,
            ["com.browser.alpha", "com.browser.beta", "com.browser.gamma"]
        )
    }
}
