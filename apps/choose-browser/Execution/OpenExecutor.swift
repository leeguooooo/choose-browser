import AppKit
import Foundation

struct ExecutionTarget: Equatable {
    /// Stable, unique identity for selection. Equals `bundleIdentifier` for an
    /// ordinary browser; for a per-profile target it is the composite id minted
    /// by discovery so each profile resolves to the correct launch arguments.
    let id: String
    let bundleIdentifier: String
    let displayName: String
    let applicationURL: URL
    /// Extra process arguments at launch, e.g. `--profile-directory=Profile 1`.
    let launchArguments: [String]

    init(
        bundleIdentifier: String,
        displayName: String,
        applicationURL: URL,
        id: String? = nil,
        launchArguments: [String] = []
    ) {
        self.id = id ?? bundleIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.applicationURL = applicationURL
        self.launchArguments = launchArguments
    }
}

enum OpenExecutionFailureReason: Equatable {
    case loopPrevented
    case noTargets
    case openFailed
}

enum OpenFallbackReason: String, Equatable {
    case targetMissing = "target_missing"
}

enum OpenExecutionResult: Equatable {
    case success(usedBundleIdentifier: String)
    case failure(OpenExecutionFailureReason)
}

enum TargetDispatchStatus: String, Equatable {
    case success
    case openFailed
    case missingTarget
}

struct TargetDispatchTrace: Equatable {
    let bundleIdentifier: String
    let status: TargetDispatchStatus
}

enum MultiTargetExecutionOutcome: String, Equatable {
    case success
    case partialFailure = "partial_failure"
    case failure
}

struct MultiTargetExecutionResult: Equatable {
    let outcome: MultiTargetExecutionOutcome
    let traces: [TargetDispatchTrace]

    var succeededBundleIdentifiers: [String] {
        traces.compactMap { trace in
            trace.status == .success ? trace.bundleIdentifier : nil
        }
    }

    var failedBundleIdentifiers: [String] {
        traces.compactMap { trace in
            trace.status == .success ? nil : trace.bundleIdentifier
        }
    }
}

protocol WorkspaceOpening {
    func open(
        _ urls: [URL],
        withApplicationAt applicationURL: URL,
        configuration: NSWorkspace.OpenConfiguration,
        completionHandler: @escaping (NSRunningApplication?, Error?) -> Void
    )
}

struct LiveWorkspaceOpener: WorkspaceOpening {
    func open(
        _ urls: [URL],
        withApplicationAt applicationURL: URL,
        configuration: NSWorkspace.OpenConfiguration,
        completionHandler: @escaping (NSRunningApplication?, Error?) -> Void
    ) {
        NSWorkspace.shared.open(
            urls,
            withApplicationAt: applicationURL,
            configuration: configuration,
            completionHandler: completionHandler
        )
    }
}

/// Launches a browser with explicit process arguments (e.g.
/// `--profile-directory=…`).
///
/// This deliberately does NOT use `NSWorkspace.OpenConfiguration.arguments`:
/// those arguments are only delivered when LaunchServices spawns a brand-new
/// process. If the browser is already running, NSWorkspace just sends it an
/// "open URL" Apple event with NO arguments, so the URL lands in whatever
/// profile happens to be frontmost — the exact "clicked profile ≠ opened
/// profile" bug. Going through `/usr/bin/open -n --args` instead forces the
/// arguments onto the process command line, where Chromium's process singleton
/// honors `--profile-directory` even when the browser is already running, while
/// still detaching the launched app from us.
protocol ProfileBrowserLaunching {
    func launch(applicationURL: URL, arguments: [String], requestURL: URL) -> Bool
}

struct LiveProfileBrowserLauncher: ProfileBrowserLaunching {
    func launch(applicationURL: URL, arguments: [String], requestURL: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", "-a", applicationURL.path, "--args"]
            + arguments
            + [requestURL.absoluteString]

        do {
            try process.run()
            process.waitUntilExit() // `open` returns promptly once the app is launched.
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

final class OpenExecutor {
    private static let safariBundleIdentifier = "com.apple.Safari"

    private let workspace: WorkspaceOpening
    private let profileLauncher: ProfileBrowserLaunching
    private let now: () -> TimeInterval
    private let onFallbackDecision: ((OpenFallbackReason) -> Void)?
    private let loopGuardTTL: TimeInterval
    private var recentDispatches: [String: TimeInterval] = [:]

    init(
        workspace: WorkspaceOpening = LiveWorkspaceOpener(),
        profileLauncher: ProfileBrowserLaunching = LiveProfileBrowserLauncher(),
        loopGuardTTL: TimeInterval = 2,
        now: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate },
        onFallbackDecision: ((OpenFallbackReason) -> Void)? = nil
    ) {
        self.workspace = workspace
        self.profileLauncher = profileLauncher
        self.loopGuardTTL = loopGuardTTL
        self.now = now
        self.onFallbackDecision = onFallbackDecision
    }

    func execute(
        requestURL: URL,
        preferredTargetBundleIdentifier: String?,
        discoveredTargets: [ExecutionTarget],
        configuredFallbackBundleIdentifier: String?
    ) async -> OpenExecutionResult {
        let dispatchKey = normalizedLoopKey(for: requestURL)
        evictExpiredLoopEntries(referenceTime: now())

        if isReentrant(dispatchKey: dispatchKey, referenceTime: now()) {
            return .failure(.loopPrevented)
        }

        guard let resolution = resolveTarget(
            preferredTargetBundleIdentifier: preferredTargetBundleIdentifier,
            discoveredTargets: discoveredTargets,
            configuredFallbackBundleIdentifier: configuredFallbackBundleIdentifier
        ) else {
            return .failure(.noTargets)
        }

        if let fallbackReason = resolution.fallbackReason {
            onFallbackDecision?(fallbackReason)
        }

        let target = resolution.target

        recentDispatches[dispatchKey] = now()

        let didOpen = await openExplicitly(requestURL: requestURL, target: target)

        if didOpen {
            return .success(usedBundleIdentifier: target.bundleIdentifier)
        }

        return .failure(.openFailed)
    }

    func executeMultiTarget(
        requestURL: URL,
        preferredTargetBundleIdentifiers: [String],
        discoveredTargets: [ExecutionTarget],
        dispatchMode: ExecutionPlanDispatchModeV2
    ) async -> MultiTargetExecutionResult {
        let dispatchKey = normalizedLoopKey(for: requestURL)
        evictExpiredLoopEntries(referenceTime: now())

        if isReentrant(dispatchKey: dispatchKey, referenceTime: now()) {
            return MultiTargetExecutionResult(outcome: .failure, traces: [])
        }

        let dispatchEntries = resolveDispatchEntries(
            preferredTargetBundleIdentifiers: preferredTargetBundleIdentifiers,
            discoveredTargets: discoveredTargets
        )
        guard !dispatchEntries.isEmpty else {
            return MultiTargetExecutionResult(outcome: .failure, traces: [])
        }

        recentDispatches[dispatchKey] = now()
        var traces: [TargetDispatchTrace] = []

        switch dispatchMode {
        case .singleTarget:
            for entry in dispatchEntries {
                switch entry {
                case let .missing(bundleIdentifier):
                    traces.append(TargetDispatchTrace(bundleIdentifier: bundleIdentifier, status: .missingTarget))
                    return MultiTargetExecutionResult(outcome: .failure, traces: traces)
                case let .target(target):
                    let didOpen = await openExplicitly(requestURL: requestURL, target: target)
                    traces.append(
                        TargetDispatchTrace(
                            bundleIdentifier: target.bundleIdentifier,
                            status: didOpen ? .success : .openFailed
                        )
                    )

                    return MultiTargetExecutionResult(
                        outcome: didOpen ? .success : .failure,
                        traces: traces
                    )
                }
            }

            return MultiTargetExecutionResult(outcome: .failure, traces: traces)

        case .orderedFailover:
            for entry in dispatchEntries {
                switch entry {
                case let .missing(bundleIdentifier):
                    traces.append(TargetDispatchTrace(bundleIdentifier: bundleIdentifier, status: .missingTarget))
                case let .target(target):
                    let didOpen = await openExplicitly(requestURL: requestURL, target: target)
                    traces.append(
                        TargetDispatchTrace(
                            bundleIdentifier: target.bundleIdentifier,
                            status: didOpen ? .success : .openFailed
                        )
                    )

                    if didOpen {
                        return MultiTargetExecutionResult(outcome: .success, traces: traces)
                    }
                }
            }

            return MultiTargetExecutionResult(outcome: .failure, traces: traces)

        case .fanout:
            for entry in dispatchEntries {
                switch entry {
                case let .missing(bundleIdentifier):
                    traces.append(TargetDispatchTrace(bundleIdentifier: bundleIdentifier, status: .missingTarget))
                case let .target(target):
                    let didOpen = await openExplicitly(requestURL: requestURL, target: target)
                    traces.append(
                        TargetDispatchTrace(
                            bundleIdentifier: target.bundleIdentifier,
                            status: didOpen ? .success : .openFailed
                        )
                    )
                }
            }

            let successCount = traces.filter { $0.status == .success }.count
            let outcome: MultiTargetExecutionOutcome

            if successCount == traces.count {
                outcome = .success
            } else if successCount == 0 {
                outcome = .failure
            } else {
                outcome = .partialFailure
            }

            return MultiTargetExecutionResult(outcome: outcome, traces: traces)
        }
    }

    private enum DispatchEntry {
        case target(ExecutionTarget)
        case missing(bundleIdentifier: String)
    }

    private func resolveDispatchEntries(
        preferredTargetBundleIdentifiers: [String],
        discoveredTargets: [ExecutionTarget]
    ) -> [DispatchEntry] {
        let requestedBundleIdentifiers = normalizedRequestedBundleIdentifiers(
            preferredTargetBundleIdentifiers,
            discoveredTargets: discoveredTargets
        )

        return requestedBundleIdentifiers.map { bundleIdentifier in
            if let target = discoveredTargets.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
                return .target(target)
            }

            return .missing(bundleIdentifier: bundleIdentifier)
        }
    }

    private func normalizedRequestedBundleIdentifiers(
        _ preferredTargetBundleIdentifiers: [String],
        discoveredTargets: [ExecutionTarget]
    ) -> [String] {
        var unique: [String] = []
        var seen = Set<String>()

        for rawValue in preferredTargetBundleIdentifiers {
            let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                continue
            }

            if seen.insert(normalized).inserted {
                unique.append(normalized)
            }
        }

        if !unique.isEmpty {
            return unique
        }

        if let first = discoveredTargets.first {
            return [first.bundleIdentifier]
        }

        return []
    }

    private func resolveTarget(
        preferredTargetBundleIdentifier: String?,
        discoveredTargets: [ExecutionTarget],
        configuredFallbackBundleIdentifier: String?
    ) -> (target: ExecutionTarget, fallbackReason: OpenFallbackReason?)? {
        let preferredTargetMissing = preferredTargetBundleIdentifier != nil

        if let preferredTargetBundleIdentifier,
           let preferred = discoveredTargets.first(where: { $0.id == preferredTargetBundleIdentifier })
               ?? discoveredTargets.first(where: { $0.bundleIdentifier == preferredTargetBundleIdentifier })
        {
            return (preferred, nil)
        }

        if let configuredFallbackBundleIdentifier,
           let configuredFallback = discoveredTargets.first(where: { $0.bundleIdentifier == configuredFallbackBundleIdentifier })
        {
            return (
                configuredFallback,
                preferredTargetMissing ? .targetMissing : nil
            )
        }

        if let safari = discoveredTargets.first(where: { $0.bundleIdentifier == Self.safariBundleIdentifier }) {
            return (
                safari,
                preferredTargetMissing ? .targetMissing : nil
            )
        }

        guard let firstTarget = discoveredTargets.first else {
            return nil
        }

        return (
            firstTarget,
            preferredTargetMissing ? .targetMissing : nil
        )
    }

    private func openExplicitly(requestURL: URL, target: ExecutionTarget) async -> Bool {
        // Targets that carry launch arguments (e.g. a specific Chrome profile)
        // must bypass NSWorkspace so the arguments reach an already-running
        // browser. See `ProfileBrowserLaunching` for why.
        if !target.launchArguments.isEmpty {
            return profileLauncher.launch(
                applicationURL: target.applicationURL,
                arguments: target.launchArguments,
                requestURL: requestURL
            )
        }

        return await withCheckedContinuation { continuation in
            let configuration = NSWorkspace.OpenConfiguration()

            workspace.open(
                [requestURL],
                withApplicationAt: target.applicationURL,
                configuration: configuration
            ) { _, error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    private func normalizedLoopKey(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased()
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()

        return components.string?.lowercased() ?? url.absoluteString.lowercased()
    }

    private func isReentrant(dispatchKey: String, referenceTime: TimeInterval) -> Bool {
        guard let previousDispatchTime = recentDispatches[dispatchKey] else {
            return false
        }

        return (referenceTime - previousDispatchTime) <= loopGuardTTL
    }

    private func evictExpiredLoopEntries(referenceTime: TimeInterval) {
        recentDispatches = recentDispatches.filter { (_, timestamp) in
            (referenceTime - timestamp) <= loopGuardTTL
        }
    }
}
