import Foundation

#if canImport(XCTest)
import XCTest
#else
class XCTestCase {}
func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T) {}
func XCTAssertNil(_ value: Any?) {}
#endif

#if canImport(ChooseBrowser)
@testable import ChooseBrowser
#else
enum BrowserProfileLaunchSupportState: Equatable {
    case supported
    case unsupportedProfileLaunch
}

enum BrowserProfileLaunchUnsupportedReasonCode: Equatable {
    case browserDoesNotExposeProfileSelection
}

struct BrowserProfileLaunchSupport: Equatable {
    let state: BrowserProfileLaunchSupportState
    let reasonCode: BrowserProfileLaunchUnsupportedReasonCode?
}

enum BrowserWorkspaceSupportState: Equatable {
    case supported
    case unsupportedWorkspace
}

enum BrowserWorkspaceUnsupportedReasonCode: Equatable {
    case profileLaunchUnsupported
}

struct BrowserWorkspaceSupport: Equatable {
    let state: BrowserWorkspaceSupportState
    let reasonCode: BrowserWorkspaceUnsupportedReasonCode?
}

struct BrowserTargetCapabilities: Equatable {
    let supportedSchemes: [String]
    let supportedFileExtensions: [String]
    let supportedMIMETypes: [String]
    let profileLaunchSupport: BrowserProfileLaunchSupport
    let workspaceSupport: BrowserWorkspaceSupport
}

struct BrowserProfileV2: Equatable {
    let id: String
}

struct BrowserWorkspaceV2: Equatable {
    let id: String
}

struct RuleTargetReferenceV2: Equatable {
    let bundleIdentifier: String
    let profileID: String?
    let workspaceID: String?
}

enum RuleTargetFallbackReasonV2: Equatable {
    case unsupportedProfileLaunch
}

struct RuleTargetResolutionV2: Equatable {
    let resolvedReference: RuleTargetReferenceV2?
    let fallbackReason: RuleTargetFallbackReasonV2?
}

final class ProfileWorkspaceStore {
    init(
        storeURL _: URL,
        backupURL _: URL,
        fileManager _: FileManager = .default,
        nowTimestamp _: @escaping () -> Int = { Int(Date().timeIntervalSince1970) },
        diagnostics _: @escaping (Int) -> Void = { _ in }
    ) {}

    func upsertProfile(bundleIdentifier _: String, displayName _: String) throws -> BrowserProfileV2 {
        BrowserProfileV2(id: "")
    }

    func upsertWorkspace(bundleIdentifier _: String, displayName _: String, profileID _: String?) throws -> BrowserWorkspaceV2 {
        BrowserWorkspaceV2(id: "")
    }

    func selectProfile(id _: String?, for _: String) throws {}
    func selectWorkspace(id _: String?, for _: String) throws {}
    func selectedProfileID(for _: String) -> String? { nil }
    func selectedWorkspaceID(for _: String) -> String? { nil }
    func selectedTargetReference(for _: String) -> RuleTargetReferenceV2? { nil }
    func resolveTargetReference(_: RuleTargetReferenceV2?, capabilities _: BrowserTargetCapabilities) -> RuleTargetResolutionV2 {
        RuleTargetResolutionV2(resolvedReference: nil, fallbackReason: nil)
    }
}
#endif

final class ProfileWorkspaceStoreTests: XCTestCase {
    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("choose-browser-profile-workspace-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func removeDirectoryIfExists(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    func testPersistsSelectedProfileAndWorkspaceIDsAcrossReload() throws {
        let tempDirectory = try makeTempDirectory()
        defer { removeDirectoryIfExists(tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("profiles.json")
        let backupURL = tempDirectory.appendingPathComponent("profiles.backup.json")
        let bundleIdentifier = "com.browser.alpha"

        let store = ProfileWorkspaceStore(storeURL: storeURL, backupURL: backupURL)
        let profile = try store.upsertProfile(bundleIdentifier: bundleIdentifier, displayName: "Work")
        let workspace = try store.upsertWorkspace(
            bundleIdentifier: bundleIdentifier,
            displayName: "Team",
            profileID: profile.id
        )

        try store.selectProfile(id: profile.id, for: bundleIdentifier)
        try store.selectWorkspace(id: workspace.id, for: bundleIdentifier)

        let reloadedStore = ProfileWorkspaceStore(storeURL: storeURL, backupURL: backupURL)

        XCTAssertEqual(reloadedStore.selectedProfileID(for: bundleIdentifier), profile.id)
        XCTAssertEqual(reloadedStore.selectedWorkspaceID(for: bundleIdentifier), workspace.id)
        XCTAssertEqual(
            reloadedStore.selectedTargetReference(for: bundleIdentifier),
            RuleTargetReferenceV2(
                bundleIdentifier: bundleIdentifier,
                profileID: profile.id,
                workspaceID: workspace.id
            )
        )
    }

    func testUnsupportedProfileLaunchFallsBackToBundleTargetDeterministically() throws {
        let tempDirectory = try makeTempDirectory()
        defer { removeDirectoryIfExists(tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("profiles.json")
        let backupURL = tempDirectory.appendingPathComponent("profiles.backup.json")
        let bundleIdentifier = "company.thebrowser.arc"
        let store = ProfileWorkspaceStore(storeURL: storeURL, backupURL: backupURL)

        let profile = try store.upsertProfile(bundleIdentifier: bundleIdentifier, displayName: "Work")
        let requestedReference = RuleTargetReferenceV2(
            bundleIdentifier: bundleIdentifier,
            profileID: profile.id,
            workspaceID: nil
        )
        let capabilities = BrowserTargetCapabilities(
            supportedSchemes: ["https"],
            supportedFileExtensions: ["html"],
            supportedMIMETypes: ["text/html"],
            profileLaunchSupport: .unsupported(.browserDoesNotExposeProfileSelection),
            workspaceSupport: .unsupported(.profileLaunchUnsupported)
        )

        let firstResolution = store.resolveTargetReference(requestedReference, capabilities: capabilities)
        let secondResolution = store.resolveTargetReference(requestedReference, capabilities: capabilities)

        XCTAssertEqual(firstResolution, secondResolution)
        XCTAssertEqual(firstResolution.fallbackReason, .unsupportedProfileLaunch)
        XCTAssertEqual(
            firstResolution.resolvedReference,
            RuleTargetReferenceV2(bundleIdentifier: bundleIdentifier, profileID: nil, workspaceID: nil)
        )
        XCTAssertNil(firstResolution.resolvedReference?.profileID)
    }
}

