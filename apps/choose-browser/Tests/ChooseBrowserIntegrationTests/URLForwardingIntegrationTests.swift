import AppKit
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
#endif

#if canImport(ChooseBrowser)
@testable import ChooseBrowser
#else
struct ExecutionTarget: Equatable {
    let bundleIdentifier: String
    let displayName: String
    let applicationURL: URL
}

enum OpenFallbackReason: Equatable {
    case targetMissing
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
        workspace _: WorkspaceOpening,
        loopGuardTTL _: TimeInterval = 2,
        now _: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate },
        onFallbackDecision _: ((OpenFallbackReason) -> Void)? = nil
    ) {}

    func execute(
        requestURL _: URL,
        preferredTargetBundleIdentifier _: String?,
        discoveredTargets _: [ExecutionTarget],
        configuredFallbackBundleIdentifier _: String?
    ) async -> OpenExecutionResult {
        .failure(.openFailed)
    }
}
#endif

final class URLForwardingIntegrationTests: XCTestCase {
    private struct SinkPayload: Decodable, Equatable {
        let requestURL: String
        let targetBundleIdentifier: String
    }

    private final class LinkSinkWorkspaceOpener: WorkspaceOpening {
        private let sinkOutputURL: URL

        init(sinkOutputURL: URL) {
            self.sinkOutputURL = sinkOutputURL
        }

        func open(
            _ urls: [URL],
            withApplicationAt applicationURL: URL,
            configuration _: NSWorkspace.OpenConfiguration,
            completionHandler: @escaping (NSRunningApplication?, Error?) -> Void
        ) {
            do {
                let executableURL = applicationURL
                    .appendingPathComponent("Contents")
                    .appendingPathComponent("MacOS")
                    .appendingPathComponent("LinkSink")

                let process = Process()
                process.executableURL = executableURL
                process.arguments = urls.map(\.absoluteString)

                var environment = ProcessInfo.processInfo.environment
                environment["LINKSINK_OUTPUT_PATH"] = sinkOutputURL.path
                process.environment = environment

                try process.run()
                if !waitForTermination(process, timeout: 5) {
                    process.terminate()
                    completionHandler(nil, NSError(domain: "LinkSink", code: 408))
                    return
                }

                if process.terminationStatus == 0 {
                    completionHandler(nil, nil)
                    return
                }

                completionHandler(nil, NSError(domain: "LinkSink", code: Int(process.terminationStatus)))
            } catch {
                completionHandler(nil, error)
            }
        }

        private func waitForTermination(_ process: Process, timeout: TimeInterval) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning {
                if Date() >= deadline {
                    return false
                }

                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }

            return true
        }
    }

    private let linkSinkBundleIdentifier = "com.choosebrowser.linksink"

    func testForwardsExactURLToLinkSinkLog() async throws {
        let sinkOutputURL = deterministicSinkURL(name: "task-9-forwarding")
        try removeSinkFileIfPresent(at: sinkOutputURL)

        let workspace = LinkSinkWorkspaceOpener(sinkOutputURL: sinkOutputURL)
        let executor = OpenExecutor(workspace: workspace)
        let requestURL = URL(string: "https://example.com/path?x=1#frag")!
        let linkSink = try linkSinkTarget()

        let result = await executor.execute(
            requestURL: requestURL,
            preferredTargetBundleIdentifier: linkSink.bundleIdentifier,
            discoveredTargets: [linkSink],
            configuredFallbackBundleIdentifier: nil
        )

        XCTAssertEqual(result, .success(usedBundleIdentifier: linkSink.bundleIdentifier))

        let payload = try decodeSinkPayload(at: sinkOutputURL)
        XCTAssertEqual(payload.requestURL, requestURL.absoluteString)
        XCTAssertEqual(payload.targetBundleIdentifier, linkSinkBundleIdentifier)
    }

    func testFallsBackWhenPrimaryTargetUnavailable() async throws {
        let sinkOutputURL = deterministicSinkURL(name: "task-9-fallback")
        try removeSinkFileIfPresent(at: sinkOutputURL)

        let workspace = LinkSinkWorkspaceOpener(sinkOutputURL: sinkOutputURL)
        var fallbackReasons: [OpenFallbackReason] = []
        let executor = OpenExecutor(
            workspace: workspace,
            onFallbackDecision: { reason in
                fallbackReasons.append(reason)
            }
        )

        let requestURL = URL(string: "https://example.com/path?x=1#frag")!
        let linkSink = try linkSinkTarget()

        let result = await executor.execute(
            requestURL: requestURL,
            preferredTargetBundleIdentifier: "com.browser.missing",
            discoveredTargets: [linkSink],
            configuredFallbackBundleIdentifier: linkSink.bundleIdentifier
        )

        XCTAssertEqual(result, .success(usedBundleIdentifier: linkSink.bundleIdentifier))
        XCTAssertEqual(fallbackReasons, [.targetMissing])

        let payload = try decodeSinkPayload(at: sinkOutputURL)
        XCTAssertEqual(payload.requestURL, requestURL.absoluteString)
        XCTAssertEqual(payload.targetBundleIdentifier, linkSinkBundleIdentifier)
    }

    private func linkSinkTarget() throws -> ExecutionTarget {
        let appURL = try linkSinkApplicationURL()
        return ExecutionTarget(
            bundleIdentifier: linkSinkBundleIdentifier,
            displayName: "LinkSink",
            applicationURL: appURL
        )
    }

    private func linkSinkApplicationURL() throws -> URL {
        if let builtProductsDir = ProcessInfo.processInfo.environment["BUILT_PRODUCTS_DIR"] {
            let appURL = URL(fileURLWithPath: builtProductsDir).appendingPathComponent("LinkSink.app")
            if FileManager.default.fileExists(atPath: appURL.path) {
                return appURL
            }
        }

        var cursor = Bundle(for: Self.self).bundleURL
        for _ in 0 ..< 10 {
            let candidate = cursor.appendingPathComponent("LinkSink.app")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }

            cursor = cursor.deletingLastPathComponent()
        }

        throw NSError(domain: "LinkSink", code: 404)
    }

    private func deterministicSinkURL(name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("choose-browser")
            .appendingPathComponent("integration")
            .appendingPathComponent("\(name).json")
    }

    private func removeSinkFileIfPresent(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func decodeSinkPayload(at url: URL) throws -> SinkPayload {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SinkPayload.self, from: data)
    }
}
