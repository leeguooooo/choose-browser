import AppKit
import SwiftUI

final class URLInboundPipeline {
    private let queue: RoutingRequestQueueing
    var onRejectedInbound: ((URL, InboundInputInvalidReasonV2) -> Void)?

    init(queue: RoutingRequestQueueing) {
        self.queue = queue
    }

    func handleIncoming(urls: [URL]) {
        for url in urls {
            handleIncoming(url: url, sourceContext: InboundSourceContextV2(sourceTrigger: .warmOpen))
        }
    }

    func handleIncoming(url: URL) {
        handleIncoming(url: url, sourceContext: InboundSourceContextV2(sourceTrigger: .warmOpen))
    }

    func handleIncoming(urls: [URL], sourceContext: InboundSourceContextV2) {
        for url in urls {
            handleIncoming(url: url, sourceContext: sourceContext)
        }
    }

    func handleIncoming(url: URL, sourceContext: InboundSourceContextV2) {
        switch makeInboundRequestV2(from: url, sourceContext: sourceContext) {
        case let .success(inboundRequest):
            queue.enqueue(RoutingRequest(url: inboundRequest.url))
        case let .failure(reason):
            onRejectedInbound?(url, reason)
        }
    }

    func makeInboundRequestV2(
        from url: URL,
        sourceContext: InboundSourceContextV2 = InboundSourceContextV2(sourceTrigger: .warmOpen)
    ) -> Result<InboundRequestV2, InboundInputInvalidReasonV2> {
        guard let scheme = url.scheme?.lowercased() else {
            return .failure(.unsupportedScheme)
        }

        switch scheme {
        case "http", "https":
            return .success(InboundRequestV2(objectType: .link, url: url, sourceContext: sourceContext))
        case "mailto":
            guard Self.isValidMailtoURL(url) else {
                return .failure(.invalidMailtoAddress)
            }

            return .success(InboundRequestV2(objectType: .email, url: url, sourceContext: sourceContext))
        case "file":
            guard Self.isCanonicalFileURL(url) else {
                return .failure(.nonCanonicalFileURL)
            }

            return .success(InboundRequestV2(objectType: .file, url: url, sourceContext: sourceContext))
        default:
            return .failure(.unsupportedScheme)
        }
    }

    func makeRoutingRequest(from url: URL) -> RoutingRequest? {
        guard case let .success(inboundRequest) = makeInboundRequestV2(from: url) else {
            return nil
        }

        return RoutingRequest(url: inboundRequest.url)
    }

    private static func isValidMailtoURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "mailto"
        else {
            return false
        }

        func hasValidAddress(_ candidate: String) -> Bool {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.contains("@") && !trimmed.hasPrefix("@") && !trimmed.hasSuffix("@")
        }

        let directRecipients = components.path
            .split(separator: ",")
            .map { String($0).removingPercentEncoding ?? String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if !directRecipients.isEmpty {
            return directRecipients.allSatisfy(hasValidAddress)
        }

        let queryRecipients = (components.queryItems ?? [])
            .filter { $0.name.caseInsensitiveCompare("to") == .orderedSame }
            .compactMap(\.value)
            .flatMap { value in
                value
                    .split(separator: ",")
                    .map { String($0).removingPercentEncoding ?? String($0) }
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !queryRecipients.isEmpty else {
            return false
        }

        return queryRecipients.allSatisfy(hasValidAddress)
    }

    private static func isCanonicalFileURL(_ url: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }

        let host = url.host ?? ""
        guard host.isEmpty else {
            return false
        }

        let normalized = url.absoluteURL
        return normalized.absoluteString.hasPrefix("file:///") && normalized.path.hasPrefix("/")
    }
}

final class ChooseBrowserAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private struct UITestTargets {
        static let standard: [ExecutionTarget] = [
            ExecutionTarget(
                bundleIdentifier: "com.browser.alpha",
                displayName: "Alpha Browser",
                applicationURL: URL(fileURLWithPath: "/Applications/Alpha Browser.app")
            ),
            ExecutionTarget(
                bundleIdentifier: "com.browser.beta",
                displayName: "Beta Browser",
                applicationURL: URL(fileURLWithPath: "/Applications/Beta Browser.app")
            ),
            ExecutionTarget(
                bundleIdentifier: "com.browser.gamma",
                displayName: "Gamma Browser",
                applicationURL: URL(fileURLWithPath: "/Applications/Gamma Browser.app")
            ),
        ]
    }

    private struct NoopWorkspaceOpener: WorkspaceOpening {
        func open(
            _ urls: [URL],
            withApplicationAt applicationURL: URL,
            configuration: NSWorkspace.OpenConfiguration,
            completionHandler: @escaping (NSRunningApplication?, Error?) -> Void
        ) {
            completionHandler(nil, nil)
        }
    }

    private struct StaticDefaultHandlerInspector: DefaultHandlerInspecting {
        let httpHandlerBundleIdentifier: String?
        let httpsHandlerBundleIdentifier: String?

        func currentDefaultHandlerBundleIdentifier(for scheme: String) -> String? {
            if scheme == "http" {
                return httpHandlerBundleIdentifier
            }

            if scheme == "https" {
                return httpsHandlerBundleIdentifier
            }

            return nil
        }

        func snapshot(appBundleIdentifier: String) -> DefaultHandlerSnapshot {
            DefaultHandlerSnapshot(
                appBundleIdentifier: appBundleIdentifier,
                httpHandlerBundleIdentifier: httpHandlerBundleIdentifier,
                httpsHandlerBundleIdentifier: httpsHandlerBundleIdentifier
            )
        }

        func openSystemDefaultBrowserSettings() -> Bool {
            true
        }

        func setAsDefaultBrowser(bundleIdentifier: String) -> Bool {
            true
        }
    }

    final class InMemoryRuleStore: RuleStoring {
        private var rules: [String: RoutingTarget] = [:]

        func preferredTarget(forHost host: String) -> RoutingTarget? {
            rules[host]
        }

        func setPreferredTarget(_ target: RoutingTarget, forHost host: String) {
            rules[host] = target
        }
    }

    final class ChooseBrowserAppModel: ObservableObject {
        struct ChooserSession {
            let requestURLs: [URL]
            let discoveredTargets: [ExecutionTarget]
            let viewModel: ChooserViewModel
        }

        struct UpdatePromptState: Identifiable, Equatable {
            let version: String
            let releaseURL: URL

            var id: String {
                version
            }
        }

        private struct LatestReleasePayload: Decodable {
            let tagName: String
            let htmlURL: URL
            let draft: Bool
            let prerelease: Bool

            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case htmlURL = "html_url"
                case draft
                case prerelease
            }
        }

        @Published var chooserSession: ChooserSession?
        @Published var lastActionMessage: String = "idle"
        @Published var defaultHandlerSnapshot: DefaultHandlerSnapshot
        @Published var fallbackBundleIdentifier: String?
        @Published var hiddenBundleIdentifiers: Set<String>
        @Published var updatePrompt: UpdatePromptState?
        @Published var updateStatusMessage: String?
        @Published var settingsCandidates: [ExecutionTarget] = []
        @Published var advancedRuleDomain: String = ""
        @Published var advancedRulePath: String = ""
        @Published var advancedRuleDispatchMode: ExecutionPlanDispatchModeV2 = .orderedFailover
        @Published var advancedRuleValidationMessage: String?
        @Published var advancedRuleSummaries: [String] = []
        @Published var availableProfiles: [String] = ["Default", "Work", "Personal"]
        @Published var availableWorkspaces: [String] = ["General", "Focus", "Research"]
        @Published var selectedProfile: String?
        @Published var selectedWorkspace: String?
        let showAdvancedPanel: Bool

        private let inboundQueue: RequestQueue
        private let routingEngine: RoutingEngine
        private let targetDiscovery: BrowserDiscoveryConfiguring
        private let openExecutor: OpenExecutor
        private let ruleStore: InMemoryRuleStore
        private let handlerInspector: DefaultHandlerInspecting
        private let settingsStore: AppSettingsStoring
        private let diagnosticsLogger: DiagnosticsLogger
        private let routingRolloutConfiguration: RoutingRolloutConfiguration
        private let appBundleIdentifier: String
        private let uiTestTargets: [ExecutionTarget]?
        private let autoQuitOnSuccessfulDispatch: Bool
        private let releaseFeedURL = URL(string: "https://api.github.com/repos/leeguooooo/choose-browser/releases/latest")!
        private var chooserOrderBundleIdentifiers: [String]
        private var isProcessingRequest = false
        private var isCheckingForUpdates = false
        private let burstWindow: TimeInterval = 0.5
        var onChooserPresentationChanged: ((Bool) -> Void)?
        var onSuccessfulDispatch: (() -> Void)?

        init(
            inboundQueue: RequestQueue,
            routingEngine: RoutingEngine,
            targetDiscovery: BrowserDiscoveryConfiguring,
            openExecutor: OpenExecutor,
            ruleStore: InMemoryRuleStore,
            handlerInspector: DefaultHandlerInspecting,
            settingsStore: AppSettingsStoring,
            diagnosticsLogger: DiagnosticsLogger,
            routingRolloutConfiguration: RoutingRolloutConfiguration = .disabled,
            appBundleIdentifier: String,
            uiTestTargets: [ExecutionTarget]? = nil,
            showAdvancedPanel: Bool = false,
            autoQuitOnSuccessfulDispatch: Bool = true
        ) {
            self.inboundQueue = inboundQueue
            self.routingEngine = routingEngine
            self.targetDiscovery = targetDiscovery
            self.openExecutor = openExecutor
            self.ruleStore = ruleStore
            self.handlerInspector = handlerInspector
            self.settingsStore = settingsStore
            self.diagnosticsLogger = diagnosticsLogger
            self.routingRolloutConfiguration = routingRolloutConfiguration
            self.appBundleIdentifier = appBundleIdentifier
            self.uiTestTargets = uiTestTargets
            self.showAdvancedPanel = showAdvancedPanel
            self.autoQuitOnSuccessfulDispatch = autoQuitOnSuccessfulDispatch
            self.fallbackBundleIdentifier = settingsStore.fallbackBundleIdentifier
            self.hiddenBundleIdentifiers = settingsStore.hiddenBundleIdentifiers
            self.chooserOrderBundleIdentifiers = settingsStore.chooserOrderBundleIdentifiers
            self.defaultHandlerSnapshot = handlerInspector.snapshot(appBundleIdentifier: appBundleIdentifier)

            applySettingsToDiscovery()
            refreshSettingsCandidates()
        }

        func processNextRequestIfNeeded() {
            guard !isProcessingRequest else {
                return
            }

            guard chooserSession == nil else {
                return
            }

            let requests = inboundQueue.dequeueBurst(window: burstWindow)
            guard !requests.isEmpty else {
                return
            }

            isProcessingRequest = true
            diagnosticsLogger.logRoutingBatch(requests: requests)
            handle(requestURLs: requests.map(\.url))
        }

        func showUITestChooser(empty: Bool) {
            let requestURL = URL(string: "https://example.com/path?x=1#frag")!
            let targets = empty ? [] : UITestTargets.standard
            presentChooser(requestURLs: [requestURL], discoveredTargets: targets)
        }

        func startFromOnboarding() {
            let requestURL = URL(string: "https://example.com/path?x=1#frag")!
            let discoveredTargets = resolveDiscoveredTargets()

            presentChooser(requestURLs: [requestURL], discoveredTargets: discoveredTargets)
        }

        func openSystemDefaultBrowserSettings() {
            let opened = handlerInspector.openSystemDefaultBrowserSettings()
            lastActionMessage = opened ? "opened-system-settings" : "failed-open-system-settings"
            refreshDefaultHandlerSnapshot()
        }

        func setAsDefaultBrowser() {
            guard defaultHandlerSnapshot.status != .configured else {
                lastActionMessage = "set-as-default:already-configured"
                return
            }

            let isDefault = handlerInspector.setAsDefaultBrowser(bundleIdentifier: appBundleIdentifier)
            refreshDefaultHandlerSnapshot()

            if isDefault || defaultHandlerSnapshot.status == .configured {
                lastActionMessage = "set-as-default:success"
                return
            }

            let openedSettings = handlerInspector.openSystemDefaultBrowserSettings()
            lastActionMessage = openedSettings ? "set-as-default:needs-user-confirmation" : "set-as-default:failure"
        }

        func selectFallbackBundleIdentifier(_ bundleIdentifier: String?) {
            fallbackBundleIdentifier = bundleIdentifier
            settingsStore.fallbackBundleIdentifier = bundleIdentifier
            lastActionMessage = "fallback-set:\(bundleIdentifier ?? "none")"
        }

        func setHidden(bundleIdentifier: String, isHidden: Bool) {
            var updated = hiddenBundleIdentifiers

            if isHidden {
                updated.insert(bundleIdentifier)
            } else {
                updated.remove(bundleIdentifier)
            }

            hiddenBundleIdentifiers = updated
            settingsStore.hiddenBundleIdentifiers = updated

            if isHidden, fallbackBundleIdentifier == bundleIdentifier {
                selectFallbackBundleIdentifier(nil)
            }

            applySettingsToDiscovery()
            refreshSettingsCandidates()
        }

        func runFallbackProbe() {
            let probeURL = URL(string: "https://probe.example/path")!
            let discoveredTargets = resolveDiscoveredTargets()

            guard !discoveredTargets.isEmpty else {
                lastActionMessage = "error:no-targets-for-probe"
                return
            }

            executeOpen(
                requestURLs: [probeURL],
                preferredBundleIdentifier: "com.browser.missing",
                discoveredTargets: discoveredTargets,
                rememberTargetForHost: nil
            )
        }

        func selectAdvancedRuleDispatchMode(_ mode: ExecutionPlanDispatchModeV2) {
            advancedRuleDispatchMode = mode
        }

        func saveAdvancedRuleDraft() {
            let normalizedDomain = advancedRuleDomain.trimmingCharacters(in: .whitespacesAndNewlines)
            var normalizedPath = advancedRulePath.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !normalizedDomain.isEmpty, !normalizedPath.isEmpty else {
                advancedRuleValidationMessage = "validation-error:domain-and-path-required"
                lastActionMessage = "rule-save:blocked"
                return
            }

            if !normalizedPath.hasPrefix("/") {
                normalizedPath = "/" + normalizedPath
            }

            let summary = "\(normalizedDomain)\(normalizedPath)|\(advancedRuleDispatchMode.rawValue)"
            advancedRuleSummaries.append(summary)
            advancedRuleSummaries.sort()
            advancedRuleValidationMessage = nil
            lastActionMessage = "rule-save:ok"
        }

        func selectProfile(_ name: String) {
            selectedProfile = name
            lastActionMessage = "profile-selected:\(name)"
        }

        func selectWorkspace(_ name: String) {
            selectedWorkspace = name
            lastActionMessage = "workspace-selected:\(name)"
        }

        func refreshDefaultHandlerSnapshot() {
            defaultHandlerSnapshot = handlerInspector.snapshot(appBundleIdentifier: appBundleIdentifier)
        }

        func checkForUpdates(manual: Bool = false) {
            if isCheckingForUpdates {
                return
            }

            isCheckingForUpdates = true

            if manual {
                updateStatusMessage = "Checking for updates..."
            }

            Task { [weak self] in
                guard let self else {
                    return
                }

                let result = await Self.fetchLatestRelease(from: releaseFeedURL)

                await MainActor.run {
                    self.isCheckingForUpdates = false

                    switch result {
                    case let .success(release):
                        self.handleLatestRelease(release, manual: manual)
                    case .failure:
                        if manual {
                            self.updateStatusMessage = "Failed to check updates."
                        }
                    }
                }
            }
        }

        func dismissUpdatePrompt() {
            updatePrompt = nil
        }

        func handleChooserWindowClosed() {
            guard chooserSession != nil else {
                return
            }

            lastActionMessage = "cancelled:window-closed"
            chooserSession = nil
            onChooserPresentationChanged?(false)
            isProcessingRequest = false
            processNextRequestIfNeeded()
        }

        func openCurrentUpdateRelease() {
            guard let updatePrompt else {
                return
            }

            NSWorkspace.shared.open(updatePrompt.releaseURL)
            lastActionMessage = "update-opened:\(updatePrompt.version)"
            self.updatePrompt = nil
        }

        func ignoreCurrentUpdateVersion() {
            guard let updatePrompt else {
                return
            }

            settingsStore.ignoredUpdateVersion = updatePrompt.version
            updateStatusMessage = "Ignored v\(updatePrompt.version)."
            lastActionMessage = "update-ignored:\(updatePrompt.version)"
            self.updatePrompt = nil
        }

        private func handle(requestURLs: [URL]) {
            guard let primaryURL = requestURLs.first else {
                isProcessingRequest = false
                processNextRequestIfNeeded()
                return
            }

            let v1Decision = routingEngine.decide(for: primaryURL)
            let decision = resolveEffectiveDecision(url: primaryURL, v1Decision: v1Decision)
            diagnosticsLogger.logDecision(url: primaryURL, decision: String(describing: decision))

            if case .v1WithShadow = routingRolloutConfiguration.mode {
                let shadowComparison = routingEngine.compareWithShadowV2(
                    for: primaryURL,
                    v1Decision: v1Decision,
                    flags: routingRolloutConfiguration.flags
                )
                diagnosticsLogger.logRoutingShadowComparison(url: primaryURL, comparison: shadowComparison)
            }

            switch decision {
            case let .route(target):
                let resolvedTarget = resolveRoutedExecutionTarget(for: target)
                executeOpen(
                    requestURLs: requestURLs,
                    preferredBundleIdentifier: resolvedTarget.bundleIdentifier,
                    discoveredTargets: [resolvedTarget],
                    rememberTargetForHost: nil
                )
            case .showChooser:
                let discoveredTargets = resolveDiscoveredTargets()
                presentChooser(requestURLs: requestURLs, discoveredTargets: discoveredTargets)
            case let .fallback(reason):
                lastActionMessage = "fallback:\(reason)"
                isProcessingRequest = false
                processNextRequestIfNeeded()
            }
        }

        private func handleLatestRelease(_ release: LatestReleasePayload, manual: Bool) {
            guard !release.draft, !release.prerelease else {
                if manual {
                    updateStatusMessage = "No stable update found."
                }
                return
            }

            let latestVersion = Self.normalizedVersion(release.tagName)
            guard !latestVersion.isEmpty else {
                if manual {
                    updateStatusMessage = "Invalid version from update feed."
                }
                return
            }

            let currentVersion = Self.currentVersionString()
            let compareResult = Self.compareVersions(latestVersion, currentVersion)

            if compareResult <= 0 {
                if manual {
                    updateStatusMessage = "You're up to date (v\(currentVersion))."
                }
                return
            }

            updateStatusMessage = "New version available: v\(latestVersion)."

            if !manual, settingsStore.ignoredUpdateVersion == latestVersion {
                return
            }

            updatePrompt = UpdatePromptState(version: latestVersion, releaseURL: release.htmlURL)
        }

        private static func currentVersionString() -> String {
            let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            return normalizedVersion(raw)
        }

        private static func normalizedVersion(_ raw: String) -> String {
            raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"^[vV]"#, with: "", options: .regularExpression)
        }

        private static func compareVersions(_ lhs: String, _ rhs: String) -> Int {
            let lhsComponents = numericComponents(from: lhs)
            let rhsComponents = numericComponents(from: rhs)
            let maxCount = max(lhsComponents.count, rhsComponents.count)

            for index in 0 ..< maxCount {
                let left = index < lhsComponents.count ? lhsComponents[index] : 0
                let right = index < rhsComponents.count ? rhsComponents[index] : 0

                if left < right {
                    return -1
                }

                if left > right {
                    return 1
                }
            }

            return 0
        }

        private static func numericComponents(from version: String) -> [Int] {
            version
                .split(separator: ".")
                .map { component -> Int in
                    let digits = component.prefix { $0.isNumber }
                    return Int(digits) ?? 0
                }
        }

        private static func fetchLatestRelease(from url: URL) async -> Result<LatestReleasePayload, Error> {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("ChooseBrowser", forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
                    throw URLError(.badServerResponse)
                }

                let payload = try JSONDecoder().decode(LatestReleasePayload.self, from: data)
                return .success(payload)
            } catch {
                return .failure(error)
            }
        }

        private func resolveEffectiveDecision(url: URL, v1Decision: RouteDecision) -> RouteDecision {
            switch routingRolloutConfiguration.mode {
            case .v1Only, .v1WithShadow:
                return v1Decision
            case .v2Primary:
                return routingEngine.decideUsingV2(for: url)
            case let .invalid(reason):
                diagnosticsLogger.logRoutingRolloutInvalidConfiguration(
                    reason: reason,
                    flags: routingRolloutConfiguration.flags
                )
                return v1Decision
            }
        }

        private func resolveDiscoveredTargets() -> [ExecutionTarget] {
            if let uiTestTargets {
                return uiTestTargets
            }

            return targetDiscovery.availableTargets().map {
                ExecutionTarget(
                    bundleIdentifier: $0.id,
                    displayName: $0.displayName,
                    applicationURL: $0.applicationURL
                )
            }
        }

        private func resolveRoutedExecutionTarget(for target: RoutingTarget) -> ExecutionTarget {
            let discoveredTargets = resolveDiscoveredTargets()

            if let discoveredTarget = discoveredTargets.first(where: { $0.bundleIdentifier == target.bundleIdentifier }) {
                return discoveredTarget
            }

            return ExecutionTarget(
                bundleIdentifier: target.bundleIdentifier,
                displayName: target.displayName,
                applicationURL: URL(fileURLWithPath: "/Applications/\(target.displayName).app")
            )
        }

        private func applySettingsToDiscovery() {
            targetDiscovery.setHiddenBundleIdentifiers(hiddenBundleIdentifiers)
        }

        private func refreshSettingsCandidates() {
            settingsCandidates = resolveDiscoveredTargets()
        }

        private func presentChooser(requestURLs: [URL], discoveredTargets: [ExecutionTarget]) {
            guard !requestURLs.isEmpty else {
                isProcessingRequest = false
                processNextRequestIfNeeded()
                return
            }

            let orderedDiscoveredTargets = applyChooserOrder(to: discoveredTargets)
            let chooserTargets = orderedDiscoveredTargets.map {
                ChooserTarget(
                    id: $0.bundleIdentifier,
                    displayName: $0.displayName,
                    applicationURL: $0.applicationURL
                )
            }

            let viewModel = ChooserViewModel(
                targets: chooserTargets,
                onOpenOnce: { [weak self] target in
                    let latestDiscoveredTargets = self?.applyChooserOrder(to: orderedDiscoveredTargets) ?? orderedDiscoveredTargets
                    self?.executeOpen(
                        requestURLs: requestURLs,
                        preferredBundleIdentifier: target.id,
                        discoveredTargets: latestDiscoveredTargets,
                        rememberTargetForHost: nil,
                        shouldTerminateOnSuccess: true
                    )
                },
                onRememberForHost: { [weak self] target in
                    let latestDiscoveredTargets = self?.applyChooserOrder(to: orderedDiscoveredTargets) ?? orderedDiscoveredTargets
                    self?.executeOpen(
                        requestURLs: requestURLs,
                        preferredBundleIdentifier: target.id,
                        discoveredTargets: latestDiscoveredTargets,
                        rememberTargetForHost: target.id,
                        shouldTerminateOnSuccess: true
                    )
                },
                onCancel: { [weak self] in
                    self?.lastActionMessage = "cancelled"
                    self?.chooserSession = nil
                    self?.onChooserPresentationChanged?(false)
                    self?.isProcessingRequest = false
                    self?.processNextRequestIfNeeded()
                },
                onOpenFallback: { [weak self] in
                    let latestDiscoveredTargets = self?.applyChooserOrder(to: orderedDiscoveredTargets) ?? orderedDiscoveredTargets
                    self?.executeOpen(
                        requestURLs: requestURLs,
                        preferredBundleIdentifier: nil,
                        discoveredTargets: latestDiscoveredTargets,
                        rememberTargetForHost: nil,
                        shouldTerminateOnSuccess: true
                    )
                },
                onOrderChanged: { [weak self] updatedTargets in
                    self?.persistChooserOrder(from: updatedTargets)
                }
            )

            chooserSession = ChooserSession(
                requestURLs: requestURLs,
                discoveredTargets: orderedDiscoveredTargets,
                viewModel: viewModel
            )
            onChooserPresentationChanged?(true)

            if requestURLs.count > 1 {
                lastActionMessage = "batch-size:\(requestURLs.count)"
            }
        }

        private func applyChooserOrder(to discoveredTargets: [ExecutionTarget]) -> [ExecutionTarget] {
            guard !chooserOrderBundleIdentifiers.isEmpty else {
                return discoveredTargets
            }

            var remainingByBundleIdentifier: [String: ExecutionTarget] = [:]
            discoveredTargets.forEach { remainingByBundleIdentifier[$0.bundleIdentifier] = $0 }
            var orderedTargets: [ExecutionTarget] = []

            for bundleIdentifier in chooserOrderBundleIdentifiers {
                guard let target = remainingByBundleIdentifier.removeValue(forKey: bundleIdentifier) else {
                    continue
                }

                orderedTargets.append(target)
            }

            for target in discoveredTargets where remainingByBundleIdentifier[target.bundleIdentifier] != nil {
                orderedTargets.append(target)
            }

            return orderedTargets
        }

        private func persistChooserOrder(from targets: [ChooserTarget]) {
            chooserOrderBundleIdentifiers = targets.map(\.id)
            settingsStore.chooserOrderBundleIdentifiers = chooserOrderBundleIdentifiers
        }

        private func executeBatchOpen(
            requestURLs: [URL],
            preferredBundleIdentifier: String?,
            discoveredTargets: [ExecutionTarget]
        ) async -> OpenExecutionResult {
            var result: OpenExecutionResult = .failure(.noTargets)

            for requestURL in requestURLs {
                result = await openExecutor.execute(
                    requestURL: requestURL,
                    preferredTargetBundleIdentifier: preferredBundleIdentifier,
                    discoveredTargets: discoveredTargets,
                    configuredFallbackBundleIdentifier: fallbackBundleIdentifier
                )

                if case .failure = result {
                    break
                }
            }

            return result
        }

        private func executeOpen(
            requestURLs: [URL],
            preferredBundleIdentifier: String?,
            discoveredTargets: [ExecutionTarget],
            rememberTargetForHost: String?,
            shouldTerminateOnSuccess: Bool = false
        ) {
            guard let primaryURL = requestURLs.first else {
                chooserSession = nil
                onChooserPresentationChanged?(false)
                isProcessingRequest = false
                processNextRequestIfNeeded()
                return
            }

            Task {
                let finalResult = await executeBatchOpen(
                    requestURLs: requestURLs,
                    preferredBundleIdentifier: preferredBundleIdentifier,
                    discoveredTargets: discoveredTargets
                )

                await MainActor.run {
                    if let rememberTargetForHost,
                       let normalized = routingEngine.normalize(primaryURL),
                       let target = discoveredTargets.first(where: { $0.bundleIdentifier == rememberTargetForHost })
                    {
                        ruleStore.setPreferredTarget(
                            RoutingTarget(
                                bundleIdentifier: target.bundleIdentifier,
                                displayName: target.displayName
                            ),
                            forHost: normalized.normalizedHost
                        )
                    }

                    switch finalResult {
                    case let .success(usedBundleIdentifier):
                        lastActionMessage = "opened:\(usedBundleIdentifier)"
                        chooserSession = nil
                        onChooserPresentationChanged?(false)
                        isProcessingRequest = false
                        if shouldTerminateOnSuccess, autoQuitOnSuccessfulDispatch {
                            onSuccessfulDispatch?()
                            return
                        }
                    case let .failure(reason):
                        lastActionMessage = "error:\(reason)"
                        chooserSession = nil
                        onChooserPresentationChanged?(false)
                        isProcessingRequest = false
                    }
                    processNextRequestIfNeeded()
                }
            }
        }
    }

    private var window: NSWindow?
    private var appModel: ChooseBrowserAppModel?
    private let routingQueue: RequestQueue
    private let ruleStore: InMemoryRuleStore
    private let inboundPipeline: URLInboundPipeline

    private func positionWindowNearMouse(_ window: NSWindow) {
        let cursor = NSEvent.mouseLocation
        let currentFrame = window.frame
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) ?? NSScreen.main
        let visibleFrame = targetScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? currentFrame

        var originX = cursor.x + 12
        var originY = cursor.y - currentFrame.height - 12

        originX = min(max(originX, visibleFrame.minX), visibleFrame.maxX - currentFrame.width)
        originY = min(max(originY, visibleFrame.minY), visibleFrame.maxY - currentFrame.height)

        window.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func refreshWindowPresentation(isChooserPresented: Bool) {
        guard let window else {
            return
        }

        if isChooserPresented {
            window.level = .statusBar
            
            // Resize window to fit ChooserView
            let chooserWidth: CGFloat = 420
            let chooserHeight: CGFloat = 480 // Approximate height for URL + Search + List + Footer
            var frame = window.frame
            frame.size = NSSize(width: chooserWidth, height: chooserHeight)
            window.setFrame(frame, display: true)
            
            positionWindowNearMouse(window)
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            return
        }

        window.level = .normal
    }

    private func terminateAfterSuccessfulDispatch() {
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    private static func argumentValue(flag: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }

        let nextIndex = arguments.index(after: index)
        guard nextIndex < arguments.endIndex else {
            return nil
        }

        return arguments[nextIndex]
    }

    override init() {
        let queue = RequestQueue()
        self.routingQueue = queue
        self.ruleStore = InMemoryRuleStore()
        self.inboundPipeline = URLInboundPipeline(queue: queue)
        super.init()
    }

    init(inboundPipeline: URLInboundPipeline) {
        self.routingQueue = RequestQueue()
        self.ruleStore = InMemoryRuleStore()
        self.inboundPipeline = inboundPipeline
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        let isUITestMode = arguments.contains { $0.hasPrefix("--uitest-") }
        let diagnosticsDebugMode = arguments.contains("--diagnostics-debug")
        let appBundleIdentifier = Bundle.main.bundleIdentifier ?? "com.choosebrowser.app"

        let discovery = TargetDiscovery()
        let executor = isUITestMode ? OpenExecutor(workspace: NoopWorkspaceOpener()) : OpenExecutor()
        let routingEngine = RoutingEngine(ruleStore: ruleStore)

        let settingsStore: AppSettingsStoring = {
            if let suiteName = Self.argumentValue(flag: "--uitest-settings-suite", arguments: arguments),
               let userDefaults = UserDefaults(suiteName: suiteName)
            {
                return UserDefaultsAppSettingsStore(userDefaults: userDefaults)
            }

            return UserDefaultsAppSettingsStore()
        }()

        if arguments.contains("--uitest-reset-settings") {
            settingsStore.reset()
        }

        let diagnosticsLogger = DiagnosticsLogger(debugMode: diagnosticsDebugMode)
        let routingRolloutConfiguration = RoutingRolloutConfiguration.from(arguments: arguments)
        let showAdvancedPanel = arguments.contains("--show-advanced-panel") ||
            arguments.contains("--uitest-show-advanced-panel")

        let uiTestTargets: [ExecutionTarget]? = {
            if arguments.contains("--uitest-empty-chooser") {
                return []
            }

            if arguments.contains("--uitest-show-chooser") ||
                arguments.contains("--uitest-onboarding-configured") ||
                arguments.contains("--uitest-onboarding-partial") ||
                arguments.contains("--uitest-onboarding-not-configured")
            {
                return UITestTargets.standard
            }

            return nil
        }()

        let handlerInspector: DefaultHandlerInspecting = {
            if arguments.contains("--uitest-onboarding-configured") {
                return StaticDefaultHandlerInspector(
                    httpHandlerBundleIdentifier: appBundleIdentifier,
                    httpsHandlerBundleIdentifier: appBundleIdentifier
                )
            }

            if arguments.contains("--uitest-onboarding-partial") {
                return StaticDefaultHandlerInspector(
                    httpHandlerBundleIdentifier: "com.other.browser",
                    httpsHandlerBundleIdentifier: appBundleIdentifier
                )
            }

            if arguments.contains("--uitest-onboarding-not-configured") {
                return StaticDefaultHandlerInspector(
                    httpHandlerBundleIdentifier: "com.other.browser",
                    httpsHandlerBundleIdentifier: "com.other.browser"
                )
            }

            return DefaultHandlerInspector()
        }()

        let model = ChooseBrowserAppModel(
            inboundQueue: routingQueue,
            routingEngine: routingEngine,
            targetDiscovery: discovery,
            openExecutor: executor,
            ruleStore: ruleStore,
            handlerInspector: handlerInspector,
            settingsStore: settingsStore,
            diagnosticsLogger: diagnosticsLogger,
            routingRolloutConfiguration: routingRolloutConfiguration,
            appBundleIdentifier: appBundleIdentifier,
            uiTestTargets: uiTestTargets,
            showAdvancedPanel: showAdvancedPanel,
            autoQuitOnSuccessfulDispatch: !isUITestMode
        )
        model.onChooserPresentationChanged = { [weak self] isPresented in
            self?.refreshWindowPresentation(isChooserPresented: isPresented)
        }
        model.onSuccessfulDispatch = { [weak self] in
            self?.terminateAfterSuccessfulDispatch()
        }

        routingQueue.onEnqueue = { [weak model] in
            Task { @MainActor in
                model?.processNextRequestIfNeeded()
            }
        }

        self.appModel = model

        let hostingView = NSHostingView(rootView: RootView(appModel: model))
        let initialWindowWidth: CGFloat = showAdvancedPanel ? 860 : 480
        let initialWindowHeight: CGFloat = showAdvancedPanel ? 780 : 260
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: initialWindowWidth, height: initialWindowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "ChooseBrowser"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.delegate = self
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        self.window = window

        if arguments.contains("--uitest-show-chooser") {
            model.showUITestChooser(empty: false)
        } else if arguments.contains("--uitest-empty-chooser") {
            model.showUITestChooser(empty: true)
        }

        if let diagnosticsPath = Self.argumentValue(flag: "--export-diagnostics", arguments: arguments) {
            let outputURL = URL(fileURLWithPath: diagnosticsPath)
            do {
                try diagnosticsLogger.exportBundle(to: outputURL)
            } catch {
                diagnosticsLogger.log(
                    category: "diagnostics",
                    message: "export_failed",
                    metadata: ["path": outputURL.path, "error": String(describing: error)]
                )
            }
        }

        if !isUITestMode {
            model.checkForUpdates(manual: false)
        }

        model.processNextRequestIfNeeded()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        inboundPipeline.handleIncoming(urls: urls)
    }

    func application(_ application: NSApplication, open url: URL) {
        inboundPipeline.handleIncoming(url: url)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow, closingWindow === window else {
            return
        }

        appModel?.handleChooserWindowClosed()
    }
}

let app = NSApplication.shared
let delegate = ChooseBrowserAppDelegate()
app.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
