import AppKit
import Foundation

#if canImport(XCTest)
import XCTest
@testable import ChooseBrowser

final class OpenExecutorProfileTests: XCTestCase {
    private final class ArgumentsSpy: WorkspaceOpening {
        var capturedArguments: [[String]] = []
        var capturedApplicationURLs: [URL] = []

        func open(
            _: [URL],
            withApplicationAt applicationURL: URL,
            configuration: NSWorkspace.OpenConfiguration,
            completionHandler: @escaping (NSRunningApplication?, Error?) -> Void
        ) {
            capturedArguments.append(configuration.arguments)
            capturedApplicationURLs.append(applicationURL)
            completionHandler(nil, nil)
        }
    }

    private func chromeProfileTarget(directory: String) -> ExecutionTarget {
        ExecutionTarget(
            bundleIdentifier: "com.google.chrome",
            displayName: "Google Chrome – \(directory)",
            applicationURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            id: "com.google.chrome::profile::\(directory)",
            launchArguments: ["--profile-directory=\(directory)"]
        )
    }

    func testResolvesProfileByCompositeIDAndForwardsProfileArgument() async {
        let workspace = ArgumentsSpy()
        let executor = OpenExecutor(workspace: workspace)
        let personal = chromeProfileTarget(directory: "Default")
        let work = chromeProfileTarget(directory: "Profile 1")

        let result = await executor.execute(
            requestURL: URL(string: "https://example.com")!,
            preferredTargetBundleIdentifier: work.id,
            discoveredTargets: [personal, work],
            configuredFallbackBundleIdentifier: nil
        )

        XCTAssertEqual(result, .success(usedBundleIdentifier: "com.google.chrome"))
        XCTAssertEqual(workspace.capturedArguments, [["--profile-directory=Profile 1"]])
    }

    func testOrdinaryTargetPassesNoArguments() async {
        let workspace = ArgumentsSpy()
        let executor = OpenExecutor(workspace: workspace)
        let safari = ExecutionTarget(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            applicationURL: URL(fileURLWithPath: "/Applications/Safari.app")
        )

        _ = await executor.execute(
            requestURL: URL(string: "https://example.com")!,
            preferredTargetBundleIdentifier: "com.apple.Safari",
            discoveredTargets: [safari],
            configuredFallbackBundleIdentifier: nil
        )

        XCTAssertEqual(workspace.capturedArguments, [[]])
    }
}
#endif
