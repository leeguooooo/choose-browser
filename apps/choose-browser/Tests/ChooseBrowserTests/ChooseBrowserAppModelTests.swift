import AppKit
import XCTest

@testable import ChooseBrowser

final class ChooseBrowserAppModelTests: XCTestCase {
    private final class TestDiscovery: BrowserDiscoveryConfiguring {
        private let targets: [BrowserTarget]

        init(targets: [BrowserTarget]) {
            self.targets = targets
        }

        func setHiddenBundleIdentifiers(_: Set<String>) {}

        func availableTargets() -> [BrowserTarget] {
            targets
        }
    }

    private final class TestDefaultHandlerInspector: DefaultHandlerInspecting {
        func currentDefaultHandlerBundleIdentifier(for _: String) -> String? {
            nil
        }

        func snapshot(appBundleIdentifier: String) -> DefaultHandlerSnapshot {
            DefaultHandlerSnapshot(
                appBundleIdentifier: appBundleIdentifier,
                httpHandlerBundleIdentifier: nil,
                httpsHandlerBundleIdentifier: nil
            )
        }

        func openSystemDefaultBrowserSettings() -> Bool {
            true
        }

        func setAsDefaultBrowser(bundleIdentifier _: String) -> Bool {
            true
        }
    }

    private final class TestWorkspaceOpener: WorkspaceOpening {
        func open(
            _: [URL],
            withApplicationAt _: URL,
            configuration _: NSWorkspace.OpenConfiguration,
            completionHandler: @escaping (NSRunningApplication?, Error?) -> Void
        ) {
            completionHandler(nil, nil)
        }
    }

    private final class TestSettingsStore: AppSettingsStoring {
        var fallbackBundleIdentifier: String?
        var hiddenBundleIdentifiers: Set<String> = []
        var chooserOrderBundleIdentifiers: [String] = []
        var ignoredUpdateVersion: String?

        func reset() {
            fallbackBundleIdentifier = nil
            hiddenBundleIdentifiers = []
            chooserOrderBundleIdentifiers = []
            ignoredUpdateVersion = nil
        }
    }

    func testWindowCloseClearsChooserSessionAndUnblocksNextRequest() {
        let queue = RequestQueue()
        let model = makeModel(inboundQueue: queue)
        let firstURL = URL(string: "https://example.com/first")!
        let secondURL = URL(string: "https://example.com/second")!

        queue.enqueue(RoutingRequest(url: firstURL))
        model.processNextRequestIfNeeded()

        XCTAssertEqual(model.chooserSession?.requestURLs.first, firstURL)

        model.handleChooserWindowClosed()

        XCTAssertNil(model.chooserSession)
        XCTAssertEqual(model.lastActionMessage, "cancelled:window-closed")

        queue.enqueue(RoutingRequest(url: secondURL))
        model.processNextRequestIfNeeded()

        XCTAssertEqual(model.chooserSession?.requestURLs.first, secondURL)
    }

    private func makeModel(inboundQueue: RequestQueue) -> ChooseBrowserAppDelegate.ChooseBrowserAppModel {
        let ruleStore = ChooseBrowserAppDelegate.InMemoryRuleStore()
        let routingEngine = RoutingEngine(ruleStore: ruleStore)
        let target = BrowserTarget(
            id: "com.test.browser",
            displayName: "Test Browser",
            applicationURL: URL(fileURLWithPath: "/Applications/Test Browser.app")
        )
        let discovery = TestDiscovery(targets: [target])
        let openExecutor = OpenExecutor(workspace: TestWorkspaceOpener())
        let settingsStore = TestSettingsStore()
        let diagnosticsLogger = DiagnosticsLogger(debugMode: true)

        return ChooseBrowserAppDelegate.ChooseBrowserAppModel(
            inboundQueue: inboundQueue,
            routingEngine: routingEngine,
            targetDiscovery: discovery,
            openExecutor: openExecutor,
            ruleStore: ruleStore,
            handlerInspector: TestDefaultHandlerInspector(),
            settingsStore: settingsStore,
            diagnosticsLogger: diagnosticsLogger,
            appBundleIdentifier: "com.choosebrowser.app",
            autoQuitOnSuccessfulDispatch: false
        )
    }
}
