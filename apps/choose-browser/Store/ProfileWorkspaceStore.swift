import Foundation

enum ProfileWorkspaceStoreDiagnosticEvent: Equatable {
    case storeCorrupted
    case storeRecovered
    case storeWriteFailed
}

enum ProfileWorkspaceStoreError: Error, Equatable {
    case invalidBundleIdentifier
    case invalidDisplayName
    case profileNotFound
    case workspaceNotFound
    case bundleIdentifierMismatch
    case workspaceProfileMismatch
}

final class ProfileWorkspaceStore {
    private struct ProfileWorkspaceSchemaV1: Codable {
        let version: Int
        let profiles: [BrowserProfileV2]
        let workspaces: [BrowserWorkspaceV2]
        let selectedProfileIDByBundleIdentifier: [String: String]
        let selectedWorkspaceIDByBundleIdentifier: [String: String]
    }

    private struct VersionProbe: Decodable {
        let version: Int
    }

    static var defaultStoreURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("ChooseBrowser", isDirectory: true)
            .appendingPathComponent("profiles.json")
    }

    static var defaultBackupURL: URL {
        defaultStoreURL.deletingLastPathComponent()
            .appendingPathComponent("profiles.backup.json")
    }

    private let lock = NSLock()
    private let storeURL: URL
    private let backupURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let nowTimestamp: () -> Int
    private let diagnostics: (ProfileWorkspaceStoreDiagnosticEvent) -> Void

    private var profilesByID: [String: BrowserProfileV2] = [:]
    private var workspacesByID: [String: BrowserWorkspaceV2] = [:]
    private var selectedProfileIDByBundleIdentifier: [String: String] = [:]
    private var selectedWorkspaceIDByBundleIdentifier: [String: String] = [:]

    init(
        storeURL: URL = ProfileWorkspaceStore.defaultStoreURL,
        backupURL: URL = ProfileWorkspaceStore.defaultBackupURL,
        fileManager: FileManager = .default,
        nowTimestamp: @escaping () -> Int = { Int(Date().timeIntervalSince1970) },
        diagnostics: @escaping (ProfileWorkspaceStoreDiagnosticEvent) -> Void = { _ in }
    ) {
        self.storeURL = storeURL
        self.backupURL = backupURL
        self.fileManager = fileManager
        self.nowTimestamp = nowTimestamp
        self.diagnostics = diagnostics
        loadFromDisk()
    }

    func upsertProfile(bundleIdentifier: String, displayName: String) throws -> BrowserProfileV2 {
        let normalizedBundleIdentifier = try normalizeBundleIdentifier(bundleIdentifier)
        let normalizedDisplayName = try normalizeDisplayName(displayName)
        let stableID = BrowserProfileV2.stableID(
            bundleIdentifier: normalizedBundleIdentifier,
            displayName: normalizedDisplayName
        )

        lock.lock()
        let existing = profilesByID[stableID]
        let profile = BrowserProfileV2(
            id: stableID,
            bundleIdentifier: normalizedBundleIdentifier,
            displayName: normalizedDisplayName,
            createdAt: existing?.createdAt ?? nowTimestamp()
        )
        profilesByID[stableID] = profile
        do {
            try persistLocked()
        } catch {
            diagnostics(.storeWriteFailed)
            lock.unlock()
            throw error
        }
        lock.unlock()

        return profile
    }

    func upsertWorkspace(
        bundleIdentifier: String,
        displayName: String,
        profileID: String?
    ) throws -> BrowserWorkspaceV2 {
        let normalizedBundleIdentifier = try normalizeBundleIdentifier(bundleIdentifier)
        let normalizedDisplayName = try normalizeDisplayName(displayName)
        let normalizedProfileID = profileID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stableID = BrowserWorkspaceV2.stableID(
            bundleIdentifier: normalizedBundleIdentifier,
            displayName: normalizedDisplayName
        )

        lock.lock()
        if let normalizedProfileID,
           let profile = profilesByID[normalizedProfileID],
           profile.bundleIdentifier != normalizedBundleIdentifier
        {
            lock.unlock()
            throw ProfileWorkspaceStoreError.bundleIdentifierMismatch
        }

        let existing = workspacesByID[stableID]
        let workspace = BrowserWorkspaceV2(
            id: stableID,
            bundleIdentifier: normalizedBundleIdentifier,
            displayName: normalizedDisplayName,
            profileID: normalizedProfileID,
            createdAt: existing?.createdAt ?? nowTimestamp()
        )
        workspacesByID[stableID] = workspace

        do {
            try persistLocked()
        } catch {
            diagnostics(.storeWriteFailed)
            lock.unlock()
            throw error
        }
        lock.unlock()

        return workspace
    }

    func profiles(for bundleIdentifier: String) -> [BrowserProfileV2] {
        let normalizedBundleIdentifier = bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        lock.lock()
        let profiles = profilesByID.values
            .filter { $0.bundleIdentifier == normalizedBundleIdentifier }
            .sorted(by: sortProfiles)
        lock.unlock()

        return profiles
    }

    func workspaces(for bundleIdentifier: String) -> [BrowserWorkspaceV2] {
        let normalizedBundleIdentifier = bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        lock.lock()
        let workspaces = workspacesByID.values
            .filter { $0.bundleIdentifier == normalizedBundleIdentifier }
            .sorted(by: sortWorkspaces)
        lock.unlock()

        return workspaces
    }

    func selectedProfileID(for bundleIdentifier: String) -> String? {
        let normalizedBundleIdentifier = bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        lock.lock()
        let selected = selectedProfileIDByBundleIdentifier[normalizedBundleIdentifier]
        lock.unlock()

        return selected
    }

    func selectedWorkspaceID(for bundleIdentifier: String) -> String? {
        let normalizedBundleIdentifier = bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        lock.lock()
        let selected = selectedWorkspaceIDByBundleIdentifier[normalizedBundleIdentifier]
        lock.unlock()

        return selected
    }

    func selectProfile(id: String?, for bundleIdentifier: String) throws {
        let normalizedBundleIdentifier = try normalizeBundleIdentifier(bundleIdentifier)
        let normalizedID = id?.trimmingCharacters(in: .whitespacesAndNewlines)

        lock.lock()
        if let normalizedID {
            guard let profile = profilesByID[normalizedID] else {
                lock.unlock()
                throw ProfileWorkspaceStoreError.profileNotFound
            }

            guard profile.bundleIdentifier == normalizedBundleIdentifier else {
                lock.unlock()
                throw ProfileWorkspaceStoreError.bundleIdentifierMismatch
            }

            selectedProfileIDByBundleIdentifier[normalizedBundleIdentifier] = normalizedID

            if let selectedWorkspaceID = selectedWorkspaceIDByBundleIdentifier[normalizedBundleIdentifier],
               let selectedWorkspace = workspacesByID[selectedWorkspaceID],
               let workspaceProfileID = selectedWorkspace.profileID,
               workspaceProfileID != normalizedID
            {
                selectedWorkspaceIDByBundleIdentifier.removeValue(forKey: normalizedBundleIdentifier)
            }
        } else {
            selectedProfileIDByBundleIdentifier.removeValue(forKey: normalizedBundleIdentifier)
        }

        do {
            try persistLocked()
        } catch {
            diagnostics(.storeWriteFailed)
            lock.unlock()
            throw error
        }
        lock.unlock()
    }

    func selectWorkspace(id: String?, for bundleIdentifier: String) throws {
        let normalizedBundleIdentifier = try normalizeBundleIdentifier(bundleIdentifier)
        let normalizedID = id?.trimmingCharacters(in: .whitespacesAndNewlines)

        lock.lock()
        if let normalizedID {
            guard let workspace = workspacesByID[normalizedID] else {
                lock.unlock()
                throw ProfileWorkspaceStoreError.workspaceNotFound
            }

            guard workspace.bundleIdentifier == normalizedBundleIdentifier else {
                lock.unlock()
                throw ProfileWorkspaceStoreError.bundleIdentifierMismatch
            }

            if let workspaceProfileID = workspace.profileID {
                guard let profile = profilesByID[workspaceProfileID] else {
                    lock.unlock()
                    throw ProfileWorkspaceStoreError.profileNotFound
                }

                guard profile.bundleIdentifier == normalizedBundleIdentifier else {
                    lock.unlock()
                    throw ProfileWorkspaceStoreError.bundleIdentifierMismatch
                }

                selectedProfileIDByBundleIdentifier[normalizedBundleIdentifier] = workspaceProfileID
            }

            selectedWorkspaceIDByBundleIdentifier[normalizedBundleIdentifier] = normalizedID
        } else {
            selectedWorkspaceIDByBundleIdentifier.removeValue(forKey: normalizedBundleIdentifier)
        }

        do {
            try persistLocked()
        } catch {
            diagnostics(.storeWriteFailed)
            lock.unlock()
            throw error
        }
        lock.unlock()
    }

    func selectedTargetReference(for bundleIdentifier: String) -> RuleTargetReferenceV2? {
        let normalizedBundleIdentifier = bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        lock.lock()
        let profileID = selectedProfileIDByBundleIdentifier[normalizedBundleIdentifier]
        let workspaceID = selectedWorkspaceIDByBundleIdentifier[normalizedBundleIdentifier]
        lock.unlock()

        if profileID == nil, workspaceID == nil {
            return nil
        }

        return RuleTargetReferenceV2(
            bundleIdentifier: normalizedBundleIdentifier,
            profileID: profileID,
            workspaceID: workspaceID
        )
    }

    func resolveTargetReference(
        _ reference: RuleTargetReferenceV2?,
        capabilities: BrowserTargetCapabilities
    ) -> RuleTargetResolutionV2 {
        guard let reference else {
            return .resolved(nil)
        }

        let normalizedBundleIdentifier = reference.bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let profileID = reference.profileID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspaceID = reference.workspaceID?.trimmingCharacters(in: .whitespacesAndNewlines)

        lock.lock()
        defer { lock.unlock() }

        if profileID != nil, capabilities.profileLaunchSupport.state != .supported {
            return .fallback(
                bundleIdentifier: normalizedBundleIdentifier,
                reason: .unsupportedProfileLaunch
            )
        }

        if workspaceID != nil, capabilities.workspaceSupport.state != .supported {
            return .fallback(
                bundleIdentifier: normalizedBundleIdentifier,
                reason: .unsupportedWorkspace
            )
        }

        if let profileID {
            guard let profile = profilesByID[profileID] else {
                return .fallback(bundleIdentifier: normalizedBundleIdentifier, reason: .missingProfile)
            }

            guard profile.bundleIdentifier == normalizedBundleIdentifier else {
                return .fallback(bundleIdentifier: normalizedBundleIdentifier, reason: .bundleIdentifierMismatch)
            }
        }

        var resolvedProfileID = profileID
        if let workspaceID {
            guard let workspace = workspacesByID[workspaceID] else {
                return .fallback(bundleIdentifier: normalizedBundleIdentifier, reason: .missingWorkspace)
            }

            guard workspace.bundleIdentifier == normalizedBundleIdentifier else {
                return .fallback(bundleIdentifier: normalizedBundleIdentifier, reason: .bundleIdentifierMismatch)
            }

            if let workspaceProfileID = workspace.profileID {
                if let resolvedProfileID, resolvedProfileID != workspaceProfileID {
                    return .fallback(bundleIdentifier: normalizedBundleIdentifier, reason: .workspaceProfileMismatch)
                }

                resolvedProfileID = workspaceProfileID
            }
        }

        return .resolved(
            RuleTargetReferenceV2(
                bundleIdentifier: normalizedBundleIdentifier,
                profileID: resolvedProfileID,
                workspaceID: workspaceID
            )
        )
    }

    private func loadFromDisk() {
        lock.lock()
        defer { lock.unlock() }

        do {
            try loadLocked(from: storeURL)
            return
        } catch let error as CocoaError {
            if error.code == .fileReadNoSuchFile {
                clearStateLocked()
                return
            }
        } catch {
            diagnostics(.storeCorrupted)
        }

        do {
            try loadLocked(from: backupURL)
            diagnostics(.storeRecovered)
        } catch {
            clearStateLocked()
        }
    }

    private func loadLocked(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let probe = try decoder.decode(VersionProbe.self, from: data)

        guard probe.version == 1 else {
            throw NSError(
                domain: "ProfileWorkspaceStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "unsupported version \(probe.version)"]
            )
        }

        let schema = try decoder.decode(ProfileWorkspaceSchemaV1.self, from: data)
        profilesByID = Dictionary(uniqueKeysWithValues: schema.profiles.map { ($0.id, $0) })
        workspacesByID = Dictionary(uniqueKeysWithValues: schema.workspaces.map { ($0.id, $0) })
        selectedProfileIDByBundleIdentifier = schema.selectedProfileIDByBundleIdentifier
        selectedWorkspaceIDByBundleIdentifier = schema.selectedWorkspaceIDByBundleIdentifier
    }

    private func clearStateLocked() {
        profilesByID = [:]
        workspacesByID = [:]
        selectedProfileIDByBundleIdentifier = [:]
        selectedWorkspaceIDByBundleIdentifier = [:]
    }

    private func persistLocked() throws {
        try ensureParentDirectoryExists()

        let profiles = profilesByID.values.sorted(by: sortProfiles)
        let workspaces = workspacesByID.values.sorted(by: sortWorkspaces)
        let schema = ProfileWorkspaceSchemaV1(
            version: 1,
            profiles: profiles,
            workspaces: workspaces,
            selectedProfileIDByBundleIdentifier: selectedProfileIDByBundleIdentifier,
            selectedWorkspaceIDByBundleIdentifier: selectedWorkspaceIDByBundleIdentifier
        )
        let data = try encoder.encode(schema)
        let directoryURL = storeURL.deletingLastPathComponent()
        let tempURL = directoryURL.appendingPathComponent("\(storeURL.lastPathComponent).tmp")

        if fileManager.fileExists(atPath: tempURL.path) {
            try fileManager.removeItem(at: tempURL)
        }

        fileManager.createFile(atPath: tempURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tempURL)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()

        if fileManager.fileExists(atPath: storeURL.path) {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }

            try fileManager.copyItem(at: storeURL, to: backupURL)
            _ = try fileManager.replaceItemAt(storeURL, withItemAt: tempURL)
        } else {
            try fileManager.moveItem(at: tempURL, to: storeURL)
        }
    }

    private func ensureParentDirectoryExists() throws {
        let directoryURL = storeURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: directoryURL.path) {
            return
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func normalizeBundleIdentifier(_ bundleIdentifier: String) throws -> String {
        let normalized = bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized.isEmpty {
            throw ProfileWorkspaceStoreError.invalidBundleIdentifier
        }

        return normalized
    }

    private func normalizeDisplayName(_ displayName: String) throws -> String {
        let normalized = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            throw ProfileWorkspaceStoreError.invalidDisplayName
        }

        return normalized
    }

    private func sortProfiles(lhs: BrowserProfileV2, rhs: BrowserProfileV2) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }

        return lhs.id < rhs.id
    }

    private func sortWorkspaces(lhs: BrowserWorkspaceV2, rhs: BrowserWorkspaceV2) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }

        return lhs.id < rhs.id
    }
}

