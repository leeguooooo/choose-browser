import Foundation

enum RuleStoreDiagnosticEvent: Equatable {
    case storeCorrupted
    case storeRecovered
    case storeWriteFailed
}

enum RuleStoreError: Error, Equatable {
    case invalidHost
}

final class RuleStore: RuleStoring {
    private struct VersionProbe: Decodable {
        let version: Int
    }

    static var defaultStoreURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("ChooseBrowser", isDirectory: true)
            .appendingPathComponent("rules.json")
    }

    static var defaultBackupURL: URL {
        defaultStoreURL.deletingLastPathComponent()
            .appendingPathComponent("rules.backup.json")
    }

    private let lock = NSLock()
    private let storeURL: URL
    private let backupURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let diagnostics: (RuleStoreDiagnosticEvent) -> Void
    private let ruleEngineV2 = RuleEngineV2()

    private var rulesByHost: [String: RuleActionV1] = [:]
    private var ruleRecordsV2: [RuleRecordV2] = []

    init(
        storeURL: URL = RuleStore.defaultStoreURL,
        backupURL: URL = RuleStore.defaultBackupURL,
        fileManager: FileManager = .default,
        diagnostics: @escaping (RuleStoreDiagnosticEvent) -> Void = { _ in }
    ) {
        self.storeURL = storeURL
        self.backupURL = backupURL
        self.fileManager = fileManager
        self.diagnostics = diagnostics
        loadFromDisk()
    }

    func preferredTarget(forHost host: String) -> RoutingTarget? {
        guard let normalizedHost = normalizeHost(host) else {
            return nil
        }

        lock.lock()
        let action = rulesByHost[normalizedHost]
        lock.unlock()

        switch action {
        case let .alwaysOpenIn(bundleIdentifier):
            return RoutingTarget(bundleIdentifier: bundleIdentifier, displayName: bundleIdentifier)
        case .alwaysAsk:
            return nil
        case .none:
            return nil
        }
    }

    func evaluateV2Plan(for request: InboundRequestV2, context: RuleEvaluationContextV2) -> ExecutionPlanV2? {
        lock.lock()
        let snapshot = ruleRecordsV2
        lock.unlock()

        guard !snapshot.isEmpty else {
            return nil
        }

        return ruleEngineV2.evaluate(for: request, rules: snapshot, context: context)
    }

    func action(forHost host: String) -> RuleActionV1? {
        guard let normalizedHost = normalizeHost(host) else {
            return nil
        }

        lock.lock()
        let action = rulesByHost[normalizedHost]
        lock.unlock()

        return action
    }

    func setAlwaysOpenIn(bundleIdentifier: String, forHost host: String) throws {
        try set(action: .alwaysOpenIn(bundleIdentifier: bundleIdentifier), forHost: host)
    }

    func setAlwaysAsk(forHost host: String) throws {
        try set(action: .alwaysAsk, forHost: host)
    }

    private func set(action: RuleActionV1, forHost host: String) throws {
        guard let normalizedHost = normalizeHost(host) else {
            throw RuleStoreError.invalidHost
        }

        lock.lock()
        rulesByHost[normalizedHost] = action

        do {
            try persistLocked()
        } catch {
            diagnostics(.storeWriteFailed)
            lock.unlock()
            throw error
        }

        lock.unlock()
    }

    private func loadFromDisk() {
        lock.lock()
        defer { lock.unlock() }

        do {
            let decoded = try decodeStore(at: storeURL)
            rulesByHost = decoded.legacyRulesByHost
            ruleRecordsV2 = decoded.ruleRecordsV2
            return
        } catch let error as CocoaError {
            if error.code == .fileReadNoSuchFile {
                rulesByHost = [:]
                ruleRecordsV2 = []
                return
            }
        } catch {
            diagnostics(.storeCorrupted)
        }

        do {
            let decoded = try decodeStore(at: backupURL)
            rulesByHost = decoded.legacyRulesByHost
            ruleRecordsV2 = decoded.ruleRecordsV2
            diagnostics(.storeRecovered)
        } catch {
            rulesByHost = [:]
            ruleRecordsV2 = []
        }
    }

    private func decodeStore(at url: URL) throws -> DecodedRuleStoreState {
        let data = try Data(contentsOf: url)
        let schema = try RuleSchemaMigration.decode(data: data, decoder: decoder)

        var map: [String: RuleActionV1] = [:]

        for rule in schema.rules {
            guard let normalizedHost = normalizeHost(rule.host) else {
                continue
            }

            map[normalizedHost] = rule.action
        }

        let ruleRecordsV2 = try decodeRuleRecordsV2(data: data, legacySchema: schema)

        return DecodedRuleStoreState(legacyRulesByHost: map, ruleRecordsV2: ruleRecordsV2)
    }

    private func decodeRuleRecordsV2(data: Data, legacySchema: RuleSchemaV1) throws -> [RuleRecordV2] {
        let probe = try decoder.decode(VersionProbe.self, from: data)

        switch probe.version {
        case 2:
            return try decoder.decode(RuleSchemaV2.self, from: data).rules
        case 1:
            return legacySchema.rules.enumerated().map { index, rule in
                RuleRecordV2(
                    ruleId: rule.host,
                    priority: 100,
                    createdAt: index,
                    host: rule.host,
                    match: RuleMatchV2(
                        scheme: nil,
                        domain: rule.host,
                        path: nil,
                        query: nil,
                        source: nil,
                        modifierKeys: nil,
                        focusHint: nil,
                        context: nil,
                        mimeTypes: nil,
                        extensions: nil
                    ),
                    action: rule.action.toV2Action()
                )
            }
        default:
            throw RuleSchemaMigrationError.unsupportedVersion(probe.version)
        }
    }

    private func persistLocked() throws {
        try ensureParentDirectoryExists()

        let records = rulesByHost.keys.sorted().compactMap { host -> RuleRecordV1? in
            guard let action = rulesByHost[host] else {
                return nil
            }

            return RuleRecordV1(host: host, action: action)
        }

        let legacyRecords = records.map { record in
            RuleRecordV2(
                ruleId: record.host,
                priority: 100,
                createdAt: 0,
                host: record.host,
                match: RuleMatchV2(
                    scheme: nil,
                    domain: record.host,
                    path: nil,
                    query: nil,
                    source: nil,
                    modifierKeys: nil,
                    focusHint: nil,
                    context: nil,
                    mimeTypes: nil,
                    extensions: nil
                ),
                action: record.action.toV2Action()
            )
        }

        ruleRecordsV2 = legacyRecords

        let schema = RuleSchemaV2(rules: legacyRecords)
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

    private func normalizeHost(_ host: String) -> String? {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}

private struct DecodedRuleStoreState {
    let legacyRulesByHost: [String: RuleActionV1]
    let ruleRecordsV2: [RuleRecordV2]
}
