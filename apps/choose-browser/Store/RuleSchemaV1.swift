import Foundation

enum RuleActionV1: Equatable, Codable {
    case alwaysOpenIn(bundleIdentifier: String)
    case alwaysAsk

    private enum CodingKeys: String, CodingKey {
        case type
        case bundleIdentifier
    }

    private enum ActionType: String, Codable {
        case alwaysOpenIn = "always_open_in"
        case alwaysAsk = "always_ask"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ActionType.self, forKey: .type)

        switch type {
        case .alwaysOpenIn:
            let bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
            self = .alwaysOpenIn(bundleIdentifier: bundleIdentifier)
        case .alwaysAsk:
            self = .alwaysAsk
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .alwaysOpenIn(bundleIdentifier):
            try container.encode(ActionType.alwaysOpenIn, forKey: .type)
            try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        case .alwaysAsk:
            try container.encode(ActionType.alwaysAsk, forKey: .type)
        }
    }
}

extension RuleActionV1 {
    func toV2Action() -> RuleActionV2 {
        switch self {
        case let .alwaysOpenIn(bundleIdentifier):
            return .alwaysOpenIn(bundleIdentifier: bundleIdentifier)
        case .alwaysAsk:
            return .alwaysAsk
        }
    }
}

struct RuleRecordV1: Equatable, Codable {
    let host: String
    let action: RuleActionV1
}

struct RuleSchemaV1: Equatable, Codable {
    let version: Int
    let rules: [RuleRecordV1]

    init(rules: [RuleRecordV1]) {
        self.version = 1
        self.rules = rules
    }
}

enum RuleSchemaMigrationError: Error, Equatable {
    case missingVersion
    case unsupportedVersion(Int)
}

private struct RuleVersionProbe: Decodable {
    let version: Int
}

enum RuleSchemaMigration {
    static func decode(data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> RuleSchemaV1 {
        guard let probe = try? decoder.decode(RuleVersionProbe.self, from: data) else {
            throw RuleSchemaMigrationError.missingVersion
        }

        switch probe.version {
        case 1:
            return try decoder.decode(RuleSchemaV1.self, from: data)
        case 2:
            let schema = try decoder.decode(RuleSchemaV2.self, from: data)
            return try schema.toLegacySchema()
        default:
            throw RuleSchemaMigrationError.unsupportedVersion(probe.version)
        }
    }
}

extension RuleSchemaV2 {
    func toLegacySchema() throws -> RuleSchemaV1 {
        var legacyRecords: [RuleRecordV1] = []

        let sortedByPriority = rules.sorted {
            if $0.priority != $1.priority {
                return $0.priority > $1.priority
            }

            if $0.specificityScore != $1.specificityScore {
                return $0.specificityScore > $1.specificityScore
            }

            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }

            return $0.ruleId < $1.ruleId
        }

        for record in sortedByPriority {
            guard let legacyAction = record.action.toLegacyAction() else {
                continue
            }

            let host = record.host ?? record.match.domain

            guard let normalizedHost = host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !normalizedHost.isEmpty else {
                continue
            }

            let alreadyHasMatch = legacyRecords.contains { $0.host == normalizedHost }
            if alreadyHasMatch {
                continue
            }

            legacyRecords.append(RuleRecordV1(host: normalizedHost, action: legacyAction))
        }

        return RuleSchemaV1(rules: legacyRecords)
    }
}

private extension RuleActionV2 {
    func toLegacyAction() -> RuleActionV1? {
        switch self {
        case let .alwaysOpenIn(bundleIdentifier):
            return .alwaysOpenIn(bundleIdentifier: bundleIdentifier)
        case .alwaysAsk:
            return .alwaysAsk
        case .runCommand:
            return nil
        }
    }
}
