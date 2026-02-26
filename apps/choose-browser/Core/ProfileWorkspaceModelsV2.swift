import Foundation

struct BrowserProfileV2: Codable, Equatable, Identifiable {
    let id: String
    let bundleIdentifier: String
    let displayName: String
    let createdAt: Int

    init(
        id: String,
        bundleIdentifier: String,
        displayName: String,
        createdAt: Int
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.createdAt = createdAt
    }

    static func stableID(bundleIdentifier: String, displayName: String) -> String {
        let normalizedBundleIdentifier = bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedDisplayName = displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")

        return "profile:\(normalizedBundleIdentifier):\(normalizedDisplayName)"
    }
}

struct BrowserWorkspaceV2: Codable, Equatable, Identifiable {
    let id: String
    let bundleIdentifier: String
    let displayName: String
    let profileID: String?
    let createdAt: Int

    init(
        id: String,
        bundleIdentifier: String,
        displayName: String,
        profileID: String?,
        createdAt: Int
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.profileID = profileID
        self.createdAt = createdAt
    }

    static func stableID(bundleIdentifier: String, displayName: String) -> String {
        let normalizedBundleIdentifier = bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedDisplayName = displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")

        return "workspace:\(normalizedBundleIdentifier):\(normalizedDisplayName)"
    }
}

struct RuleTargetReferenceV2: Codable, Equatable {
    let bundleIdentifier: String
    let profileID: String?
    let workspaceID: String?

    init(bundleIdentifier: String, profileID: String? = nil, workspaceID: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.profileID = profileID
        self.workspaceID = workspaceID
    }
}

enum RuleTargetFallbackReasonV2: String, Codable, Equatable {
    case unsupportedProfileLaunch = "unsupported_profile_launch"
    case unsupportedWorkspace = "unsupported_workspace"
    case missingProfile = "missing_profile"
    case missingWorkspace = "missing_workspace"
    case workspaceProfileMismatch = "workspace_profile_mismatch"
    case bundleIdentifierMismatch = "bundle_identifier_mismatch"
}

struct RuleTargetResolutionV2: Codable, Equatable {
    let resolvedReference: RuleTargetReferenceV2?
    let fallbackReason: RuleTargetFallbackReasonV2?

    static func resolved(_ reference: RuleTargetReferenceV2?) -> RuleTargetResolutionV2 {
        RuleTargetResolutionV2(resolvedReference: reference, fallbackReason: nil)
    }

    static func fallback(
        bundleIdentifier: String,
        reason: RuleTargetFallbackReasonV2
    ) -> RuleTargetResolutionV2 {
        RuleTargetResolutionV2(
            resolvedReference: RuleTargetReferenceV2(bundleIdentifier: bundleIdentifier),
            fallbackReason: reason
        )
    }
}

