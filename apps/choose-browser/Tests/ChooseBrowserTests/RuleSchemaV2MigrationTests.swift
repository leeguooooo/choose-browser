import Foundation

#if canImport(XCTest)
import XCTest
#else
class XCTestCase {}

func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T) {}
func XCTAssertNil(_ value: Any?) {}
func XCTAssertNotNil(_ value: Any?) {}
func XCTAssertTrue(_ value: Bool) {}
func XCTFail(_ message: String = "") {}
#endif

#if canImport(ChooseBrowser)
@testable import ChooseBrowser
#else
enum RuleStoreDiagnosticEvent {
    case storeCorrupted
    case storeRecovered
    case storeWriteFailed
}

struct RoutingTarget: Equatable {
    let bundleIdentifier: String
    let displayName: String
}

final class RuleStore {
    init(storeURL _: URL, backupURL _: URL, fileManager _: FileManager = .default, diagnostics _: @escaping (RuleStoreDiagnosticEvent) -> Void = { _ in }) {}
    func preferredTarget(forHost _: String) -> RoutingTarget? { nil }
    func setAlwaysOpenIn(bundleIdentifier _: String, forHost _: String) throws {}
    func setAlwaysAsk(forHost _: String) throws {}
}
#endif

final class RuleSchemaV2MigrationTests: XCTestCase {
    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("choose-browser-rule-schema-v2-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func removeDirectoryIfExists(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writeJSON(_ value: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted])
        try data.write(to: url)
    }

    private func loadJSONObject(from url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw NSError(domain: "RuleSchemaV2MigrationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "invalid top-level schema object"])
        }
        return dictionary
    }

    private func writeV1Fixture(to url: URL) throws {
        let schema: [String: Any] = [
            "version": 1,
            "rules": [
                [
                    "host": "  Example.COM  ",
                    "action": [
                        "type": "always_open_in",
                        "bundleIdentifier": "com.apple.Safari",
                    ],
                ],
                [
                    "host": "example.org",
                    "action": [
                        "type": "always_ask",
                    ],
                ],
                [
                    "host": "  ",
                    "action": [
                        "type": "always_open_in",
                        "bundleIdentifier": "com.example.ShouldIgnore",
                    ],
                ],
            ],
        ]
        try writeJSON(schema, to: url)
    }

    private func writeV2Fixture(to url: URL) throws {
        let schema: [String: Any] = [
            "version": 2,
            "rules": [
                [
                    "ruleId": "duplicate-highest",
                    "priority": 1,
                    "createdAt": 200,
                    "host": "duplicate.test",
                    "match": [
                        "scheme": "https",
                        "domain": "duplicate.com",
                    ],
                    "action": [
                        "type": "always_open_in",
                        "bundleIdentifier": "com.legacy.should-not-win",
                    ],
                ],
                [
                    "ruleId": "duplicate-ask",
                    "priority": 10,
                    "createdAt": 100,
                    "host": "duplicate.test",
                    "match": [
                        "scheme": "https",
                        "domain": "duplicate.com",
                    ],
                    "action": [
                        "type": "always_ask",
                    ],
                ],
                [
                    "ruleId": "normalized-highest",
                    "priority": 5,
                    "createdAt": 50,
                    "host": "  NORMALIZED.test  ",
                    "match": [
                        "scheme": "https",
                        "domain": "normalized.test",
                    ],
                    "action": [
                        "type": "always_open_in",
                        "bundleIdentifier": "com.example.normalized",
                    ],
                ],
                [
                    "ruleId": "run-command-only",
                    "priority": 99,
                    "createdAt": 10,
                    "host": "command-only.test",
                    "match": [
                        "scheme": "https",
                        "domain": "command-only.test",
                    ],
                    "action": [
                        "type": "run_command",
                        "bundleIdentifier": "com.example.command",
                        "command": "/usr/bin/echo", 
                    ],
                ],
            ],
        ]
        try writeJSON(schema, to: url)
    }

    func testV1SchemaLoadsAndPersistsAsV2WhenStoreWrites() throws {
        let tempDirectory = try makeTempDirectory()
        defer { removeDirectoryIfExists(tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("rules.json")
        let backupURL = tempDirectory.appendingPathComponent("rules.backup.json")

        try writeV1Fixture(to: storeURL)

        let store = RuleStore(storeURL: storeURL, backupURL: backupURL)
        XCTAssertEqual(store.preferredTarget(forHost: "example.com")?.bundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(store.preferredTarget(forHost: "example.org")?.bundleIdentifier, nil)

        try store.setAlwaysOpenIn(bundleIdentifier: "com.apple.Safari", forHost: "example.com")

        let object = try loadJSONObject(from: storeURL)
        XCTAssertEqual(object["version"] as? Int, 2)

        guard let rules = object["rules"] as? [[String: Any]] else {
            XCTFail("rules missing")
            return
        }
        XCTAssertEqual(rules.count, 2)

        let exampleRule = rules.first { ($0["host"] as? String) == "example.com" }
        XCTAssertNotNil(exampleRule)
        XCTAssertEqual(exampleRule?["host"] as? String, "example.com")

        let action = exampleRule?["action"] as? [String: Any]
        XCTAssertEqual(action?["type"] as? String, "always_open_in")
        XCTAssertEqual(action?["bundleIdentifier"] as? String, "com.apple.Safari")

        let ruleHostRule = rules.first { ($0["match"] as? [String: Any])?["domain"] as? String == "example.org" }
        XCTAssertNotNil(ruleHostRule)
    }

    func testV2SchemaConvertsToLegacyByPriorityAndSkipsRunCommandAction() throws {
        let tempDirectory = try makeTempDirectory()
        defer { removeDirectoryIfExists(tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("rules.json")
        let backupURL = tempDirectory.appendingPathComponent("rules.backup.json")

        try writeV2Fixture(to: storeURL)

        let store = RuleStore(storeURL: storeURL, backupURL: backupURL)

        XCTAssertEqual(store.preferredTarget(forHost: "duplicate.com")?.bundleIdentifier, nil)
        XCTAssertEqual(store.preferredTarget(forHost: "normalized.test")?.bundleIdentifier, "com.example.normalized")
        XCTAssertNil(store.preferredTarget(forHost: "command-only.test")?.bundleIdentifier)

        let object = try loadJSONObject(from: storeURL)
        XCTAssertEqual(object["version"] as? Int, 2)
    }

    func testIdempotentMigrationAcrossConsecutiveLoadCycles() throws {
        let tempDirectory = try makeTempDirectory()
        defer { removeDirectoryIfExists(tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("rules.json")
        let backupURL = tempDirectory.appendingPathComponent("rules.backup.json")

        try writeV2Fixture(to: storeURL)
        let firstObject = try loadJSONObject(from: storeURL)

        for _ in 0..<2 {
            let store = RuleStore(storeURL: storeURL, backupURL: backupURL)
            XCTAssertEqual(store.preferredTarget(forHost: "normalized.test")?.bundleIdentifier, "com.example.normalized")
            XCTAssertNil(store.preferredTarget(forHost: "duplicate.com")?.bundleIdentifier)
        }

        let secondObject = try loadJSONObject(from: storeURL)
        let first = try JSONSerialization.data(withJSONObject: firstObject, options: [.sortedKeys])
        let second = try JSONSerialization.data(withJSONObject: secondObject, options: [.sortedKeys])
        XCTAssertEqual(String(data: first, encoding: .utf8), String(data: second, encoding: .utf8))
    }

    func testRecoversFromCorruptStoreUsingBackupAndEmitsDiagnostics() throws {
        let tempDirectory = try makeTempDirectory()
        defer { removeDirectoryIfExists(tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("rules.json")
        let backupURL = tempDirectory.appendingPathComponent("rules.backup.json")

        var diagnostics: [RuleStoreDiagnosticEvent] = []
        let initialStore = RuleStore(
            storeURL: storeURL,
            backupURL: backupURL,
            diagnostics: { diagnostics.append($0) }
        )
        try initialStore.setAlwaysOpenIn(bundleIdentifier: "com.apple.Safari", forHost: "recover.test")
        try initialStore.setAlwaysAsk(forHost: "other.test")

        try Data("{ corrupted".utf8).write(to: storeURL)

        let restoredStore = RuleStore(
            storeURL: storeURL,
            backupURL: backupURL,
            diagnostics: { diagnostics.append($0) }
        )

        XCTAssertEqual(restoredStore.preferredTarget(forHost: "recover.test")?.bundleIdentifier, "com.apple.Safari")
        XCTAssertTrue(diagnostics.contains(.storeCorrupted))
        XCTAssertTrue(diagnostics.contains(.storeRecovered))
    }
}
