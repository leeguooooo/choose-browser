import AppKit
import CoreServices
import Foundation

enum BrowserProfileLaunchSupportState: String, Codable, Equatable {
    case supported
    case unsupportedProfileLaunch
}

enum BrowserProfileLaunchUnsupportedReasonCode: String, Codable, Equatable {
    case browserDoesNotExposeProfileSelection = "browser_does_not_expose_profile_selection"
}

struct BrowserProfileLaunchSupport: Codable, Equatable {
    let state: BrowserProfileLaunchSupportState
    let reasonCode: BrowserProfileLaunchUnsupportedReasonCode?

    static let supported = BrowserProfileLaunchSupport(
        state: .supported,
        reasonCode: nil
    )

    static func unsupported(_ reasonCode: BrowserProfileLaunchUnsupportedReasonCode) -> BrowserProfileLaunchSupport {
        BrowserProfileLaunchSupport(
            state: .unsupportedProfileLaunch,
            reasonCode: reasonCode
        )
    }
}

enum BrowserWorkspaceSupportState: String, Codable, Equatable {
    case supported
    case unsupportedWorkspace
}

enum BrowserWorkspaceUnsupportedReasonCode: String, Codable, Equatable {
    case profileLaunchUnsupported = "profile_launch_unsupported"
}

struct BrowserWorkspaceSupport: Codable, Equatable {
    let state: BrowserWorkspaceSupportState
    let reasonCode: BrowserWorkspaceUnsupportedReasonCode?

    static let supported = BrowserWorkspaceSupport(
        state: .supported,
        reasonCode: nil
    )

    static func unsupported(_ reasonCode: BrowserWorkspaceUnsupportedReasonCode) -> BrowserWorkspaceSupport {
        BrowserWorkspaceSupport(
            state: .unsupportedWorkspace,
            reasonCode: reasonCode
        )
    }
}

struct BrowserTargetCapabilities: Codable, Equatable {
    let supportedSchemes: [String]
    let supportedFileExtensions: [String]
    let supportedMIMETypes: [String]
    let profileLaunchSupport: BrowserProfileLaunchSupport
    let workspaceSupport: BrowserWorkspaceSupport

    init(
        supportedSchemes: [String] = [],
        supportedFileExtensions: [String] = [],
        supportedMIMETypes: [String] = [],
        profileLaunchSupport: BrowserProfileLaunchSupport = .supported,
        workspaceSupport: BrowserWorkspaceSupport = .supported
    ) {
        self.supportedSchemes = Self.normalizedValues(supportedSchemes)
        self.supportedFileExtensions = Self.normalizedValues(supportedFileExtensions)
        self.supportedMIMETypes = Self.normalizedValues(supportedMIMETypes)
        self.profileLaunchSupport = profileLaunchSupport
        self.workspaceSupport = workspaceSupport
    }

    static let `default` = BrowserTargetCapabilities()

    private static func normalizedValues(_ values: [String]) -> [String] {
        Set(
            values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        .sorted()
    }
}

struct BrowserTarget: Equatable, Identifiable {
    let id: String
    let displayName: String
    let applicationURL: URL
    let capabilities: BrowserTargetCapabilities

    init(
        id: String,
        displayName: String,
        applicationURL: URL,
        capabilities: BrowserTargetCapabilities = .default
    ) {
        self.id = id
        self.displayName = displayName
        self.applicationURL = applicationURL
        self.capabilities = capabilities
    }
}

protocol BrowserDiscovering {
    func availableTargets() -> [BrowserTarget]
}

protocol BrowserDiscoveryConfiguring: BrowserDiscovering {
    func setHiddenBundleIdentifiers(_ hiddenBundleIdentifiers: Set<String>)
}

protocol BrowserCapabilityResolving {
    func capabilities(for bundleIdentifier: String, supportedSchemes: Set<String>) -> BrowserTargetCapabilities
}

struct LiveBrowserCapabilityResolver: BrowserCapabilityResolving {
    private static let defaultSupportedFileExtensions = [
        "html",
        "htm",
        "xhtml",
        "pdf",
    ]

    private static let defaultSupportedMIMETypes = [
        "text/html",
        "application/xhtml+xml",
        "application/pdf",
    ]

    func capabilities(for bundleIdentifier: String, supportedSchemes: Set<String>) -> BrowserTargetCapabilities {
        let profileLaunchSupport = profileLaunchSupport(for: bundleIdentifier)
        let workspaceSupport = workspaceSupport(for: profileLaunchSupport)

        return BrowserTargetCapabilities(
            supportedSchemes: Array(supportedSchemes),
            supportedFileExtensions: Self.defaultSupportedFileExtensions,
            supportedMIMETypes: Self.defaultSupportedMIMETypes,
            profileLaunchSupport: profileLaunchSupport,
            workspaceSupport: workspaceSupport
        )
    }

    private func profileLaunchSupport(for bundleIdentifier: String) -> BrowserProfileLaunchSupport {
        let normalizedBundleIdentifier = bundleIdentifier.lowercased()

        if normalizedBundleIdentifier.contains("arc") || normalizedBundleIdentifier.contains("dia") {
            return .unsupported(.browserDoesNotExposeProfileSelection)
        }

        return .supported
    }

    private func workspaceSupport(for profileLaunchSupport: BrowserProfileLaunchSupport) -> BrowserWorkspaceSupport {
        if profileLaunchSupport.state == .supported {
            return .supported
        }

        return .unsupported(.profileLaunchUnsupported)
    }
}

enum TargetDiscoveryFailureReason: Equatable {
    case noTargets
}

struct TargetDiscoveryResult: Equatable {
    let candidates: [BrowserTarget]
    let failureReason: TargetDiscoveryFailureReason?

    func capabilitySupportMatrixRows() -> [BrowserCapabilitySupportMatrixRow] {
        candidates
            .map { candidate in
                BrowserCapabilitySupportMatrixRow(
                    stableTargetID: candidate.id,
                    displayName: candidate.displayName,
                    supportedSchemes: candidate.capabilities.supportedSchemes,
                    supportedFileExtensions: candidate.capabilities.supportedFileExtensions,
                    supportedMIMETypes: candidate.capabilities.supportedMIMETypes,
                    profileLaunchSupportState: candidate.capabilities.profileLaunchSupport.state,
                    profileLaunchUnsupportedReasonCode: candidate.capabilities.profileLaunchSupport.reasonCode,
                    workspaceSupportState: candidate.capabilities.workspaceSupport.state,
                    workspaceUnsupportedReasonCode: candidate.capabilities.workspaceSupport.reasonCode
                )
            }
            .sorted { lhs, rhs in
                lhs.stableTargetID < rhs.stableTargetID
            }
    }
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

struct LiveBrowserHandlerQuery: BrowserHandlerQuerying {
    func handlers(for scheme: String) -> [String] {
        guard let handlers = LSCopyAllHandlersForURLScheme(scheme as CFString)?.takeRetainedValue() as? [String] else {
            return []
        }

        return handlers
    }

    func applicationURL(for bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func displayName(for applicationURL: URL, bundleIdentifier: String) -> String {
        let fileManager = FileManager.default
        let displayName = fileManager.displayName(atPath: applicationURL.path)

        if displayName.isEmpty {
            return bundleIdentifier
        }

        return displayName.replacingOccurrences(of: ".app", with: "")
    }
}

final class TargetDiscovery: BrowserDiscoveryConfiguring {
    private let selfBundleIdentifier: String
    private let query: BrowserHandlerQuerying
    private let capabilityResolver: BrowserCapabilityResolving
    private var hiddenBundleIdentifiers: Set<String>

    init(
        selfBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "",
        hiddenBundleIdentifiers: Set<String> = [],
        query: BrowserHandlerQuerying = LiveBrowserHandlerQuery(),
        capabilityResolver: BrowserCapabilityResolving = LiveBrowserCapabilityResolver()
    ) {
        self.selfBundleIdentifier = selfBundleIdentifier
        self.hiddenBundleIdentifiers = hiddenBundleIdentifiers
        self.query = query
        self.capabilityResolver = capabilityResolver
    }

    func setHiddenBundleIdentifiers(_ hiddenBundleIdentifiers: Set<String>) {
        self.hiddenBundleIdentifiers = hiddenBundleIdentifiers
    }

    func discoverTargets() -> TargetDiscoveryResult {
        let (orderedBundleIdentifiers, schemesByBundleIdentifier) = gatherOrderedBundleIdentifiers(for: ["http", "https"])

        var candidates: [BrowserTarget] = []

        for bundleIdentifier in orderedBundleIdentifiers {
            guard shouldInclude(bundleIdentifier: bundleIdentifier) else {
                continue
            }

            guard let applicationURL = query.applicationURL(for: bundleIdentifier) else {
                continue
            }

            let displayName = query.displayName(for: applicationURL, bundleIdentifier: bundleIdentifier)
            let capabilities = capabilityResolver.capabilities(
                for: bundleIdentifier,
                supportedSchemes: schemesByBundleIdentifier[bundleIdentifier, default: []]
            )
            let target = BrowserTarget(
                id: bundleIdentifier,
                displayName: displayName,
                applicationURL: applicationURL,
                capabilities: capabilities
            )
            candidates.append(target)
        }

        let sorted = candidates.sorted(by: sortComparator)

        if sorted.isEmpty {
            return TargetDiscoveryResult(candidates: [], failureReason: .noTargets)
        }

        return TargetDiscoveryResult(candidates: sorted, failureReason: nil)
    }

    func availableTargets() -> [BrowserTarget] {
        discoverTargets().candidates
    }

    private func gatherOrderedBundleIdentifiers(for schemes: [String]) -> ([String], [String: Set<String>]) {
        var seen: Set<String> = []
        var ordered: [String] = []
        var supportedSchemesByBundleIdentifier: [String: Set<String>] = [:]

        for scheme in schemes {
            let normalizedScheme = scheme.lowercased()

            for bundleIdentifier in query.handlers(for: scheme) {
                if seen.insert(bundleIdentifier).inserted {
                    ordered.append(bundleIdentifier)
                }

                supportedSchemesByBundleIdentifier[bundleIdentifier, default: []].insert(normalizedScheme)
            }
        }

        return (ordered, supportedSchemesByBundleIdentifier)
    }

    private func shouldInclude(bundleIdentifier: String) -> Bool {
        if bundleIdentifier == selfBundleIdentifier {
            return false
        }

        if hiddenBundleIdentifiers.contains(bundleIdentifier) {
            return false
        }

        return true
    }

    private func sortComparator(lhs: BrowserTarget, rhs: BrowserTarget) -> Bool {
        let primary = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)

        if primary == .orderedSame {
            return lhs.id < rhs.id
        }

        return primary == .orderedAscending
    }
}
