import AppKit
import Foundation

#if canImport(XCTest)
import XCTest
@testable import ChooseBrowser

final class OpenExecutorProfileTests: XCTestCase {
    private final class WorkspaceSpy: WorkspaceOpening {
        var openCount = 0
        func open(
            _: [URL],
            withApplicationAt _: URL,
            configuration _: NSWorkspace.OpenConfiguration,
            completionHandler: @escaping (NSRunningApplication?, Error?) -> Void
        ) {
            openCount += 1
            completionHandler(nil, nil)
        }
    }

    private final class ProfileLauncherSpy: ProfileBrowserLaunching {
        var launches: [(application: URL, arguments: [String], requestURL: URL)] = []
        func launch(applicationURL: URL, arguments: [String], requestURL: URL) -> Bool {
            launches.append((applicationURL, arguments, requestURL))
            return true
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

    func testResolvesProfileByCompositeIDAndLaunchesWithProfileArgument() async {
        let workspace = WorkspaceSpy()
        let launcher = ProfileLauncherSpy()
        let executor = OpenExecutor(workspace: workspace, profileLauncher: launcher)
        let personal = chromeProfileTarget(directory: "Default")
        let work = chromeProfileTarget(directory: "Profile 1")
        let requestURL = URL(string: "https://example.com")!

        let result = await executor.execute(
            requestURL: requestURL,
            preferredTargetBundleIdentifier: work.id,
            discoveredTargets: [personal, work],
            configuredFallbackBundleIdentifier: nil
        )

        XCTAssertEqual(result, .success(usedBundleIdentifier: "com.google.chrome"))
        // The chosen profile is launched directly (not via NSWorkspace), with
        // its own --profile-directory argument and the request URL.
        XCTAssertEqual(workspace.openCount, 0)
        XCTAssertEqual(launcher.launches.count, 1)
        XCTAssertEqual(launcher.launches.first?.arguments, ["--profile-directory=Profile 1"])
        XCTAssertEqual(launcher.launches.first?.requestURL, requestURL)
        XCTAssertEqual(launcher.launches.first?.application, work.applicationURL)
    }

    func testOrdinaryTargetGoesThroughWorkspaceWithoutLauncher() async {
        let workspace = WorkspaceSpy()
        let launcher = ProfileLauncherSpy()
        let executor = OpenExecutor(workspace: workspace, profileLauncher: launcher)
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

        XCTAssertEqual(workspace.openCount, 1)
        XCTAssertEqual(launcher.launches.count, 0)
    }
}
#endif
