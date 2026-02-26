import Foundation

enum RuleActionV2: Equatable, Codable {
    case alwaysOpenIn(bundleIdentifier: String)
    case alwaysAsk
    case runCommand(bundleIdentifier: String, command: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case bundleIdentifier
        case command
    }

    private enum ActionType: String, Codable {
        case alwaysOpenIn = "always_open_in"
        case alwaysAsk = "always_ask"
        case runCommand = "run_command"
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
        case .runCommand:
            let bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
            let command = try container.decode(String.self, forKey: .command)
            self = .runCommand(bundleIdentifier: bundleIdentifier, command: command)
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
        case let .runCommand(bundleIdentifier, command):
            try container.encode(ActionType.runCommand, forKey: .type)
            try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
            try container.encode(command, forKey: .command)
        }
    }
}

struct RuleMatchV2: Equatable, Codable {
    let scheme: String?
    let domain: String?
    let path: String?
    let query: String?
    let source: String?
    let modifierKeys: [String]?
    let focusHint: String?
    let context: String?
    let mimeTypes: [String]?
    let extensions: [String]?
}

struct RuleRecordV2: Equatable, Codable {
    let ruleId: String
    let priority: Int
    let createdAt: Int
    let host: String?
    let match: RuleMatchV2
    let action: RuleActionV2
    let targetReference: RuleTargetReferenceV2?

    init(
        ruleId: String,
        priority: Int,
        createdAt: Int,
        host: String? = nil,
        match: RuleMatchV2,
        action: RuleActionV2,
        targetReference: RuleTargetReferenceV2? = nil
    ) {
        self.ruleId = ruleId
        self.priority = priority
        self.createdAt = createdAt
        self.host = host
        self.match = match
        self.action = action
        self.targetReference = targetReference
    }
}

extension RuleRecordV2 {
    var specificityScore: Int {
        var score = 0

        if let scheme = match.scheme?.trimmingCharacters(in: .whitespacesAndNewlines), !scheme.isEmpty {
            score += 1
        }

        if let domain = match.domain?.trimmingCharacters(in: .whitespacesAndNewlines), !domain.isEmpty {
            score += 1
        }

        if let path = match.path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            score += 1
        }

        if let query = match.query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            score += 1
        }

        if let source = match.source?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty {
            score += 1
        }

        if let focusHint = match.focusHint?.trimmingCharacters(in: .whitespacesAndNewlines), !focusHint.isEmpty {
            score += 1
        }

        if let context = match.context?.trimmingCharacters(in: .whitespacesAndNewlines), !context.isEmpty {
            score += 1
        }

        if let modifierKeys = match.modifierKeys, !modifierKeys.isEmpty {
            score += 1
        }

        if let mimeTypes = match.mimeTypes, !mimeTypes.isEmpty {
            score += 1
        }

        if let extensions = match.extensions, !extensions.isEmpty {
            score += 1
        }

        if let host = host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty {
            score += 1
        }

        return score
    }
}

struct RuleSchemaV2: Equatable, Codable {
    let version: Int
    let rules: [RuleRecordV2]

    init(rules: [RuleRecordV2]) {
        self.version = 2
        self.rules = rules
    }
}
