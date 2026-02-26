import Foundation

#if canImport(XCTest)
import XCTest
#else
class XCTestCase {}

func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T) {}
func XCTAssertNil(_ value: Any?) {}
func XCTAssertTrue(_ value: Bool) {}
#endif

#if canImport(ChooseBrowser)
@testable import ChooseBrowser
#else
enum RuleStoreDiagnosticEvent: Equatable {
    case storeCorrupted
    case storeRecovered
    case storeWriteFailed
}

struct RoutingTarget: Equatable {
    let bundleIdentifier: String
    let displayName: String
}

final class RuleStore {
    init(
        storeURL _: URL,
        backupURL _: URL,
        fileManager _: FileManager = .default,
        diagnostics _: @escaping (RuleStoreDiagnosticEvent) -> Void = { _ in }
    ) {}

    func preferredTarget(forHost _: String) -> RoutingTarget? { nil }
    func setAlwaysOpenIn(bundleIdentifier _: String, forHost _: String) throws {}
}
#endif

final class RuleStoreTests: XCTestCase {
    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("choose-browser-rule-store-tests-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return directory
    }

    private func removeDirectoryIfExists(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    func testExactHostLookupDoesNotMatchSubdomain() throws {
        let tempDirectory = try makeTempDirectory()
        defer { removeDirectoryIfExists(tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("rules.json")
        let backupURL = tempDirectory.appendingPathComponent("rules.backup.json")

        let store = RuleStore(storeURL: storeURL, backupURL: backupURL)
        try store.setAlwaysOpenIn(bundleIdentifier: "com.apple.Safari", forHost: "example.com")

        let reloadedStore = RuleStore(storeURL: storeURL, backupURL: backupURL)

        XCTAssertEqual(
            reloadedStore.preferredTarget(forHost: "example.com")?.bundleIdentifier,
            "com.apple.Safari"
        )
        XCTAssertNil(reloadedStore.preferredTarget(forHost: "a.example.com"))
    }

    func testRecoversFromCorruptFileUsingBackup() throws {
        let tempDirectory = try makeTempDirectory()
        defer { removeDirectoryIfExists(tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("rules.json")
        let backupURL = tempDirectory.appendingPathComponent("rules.backup.json")

        var diagnosticsEvents: [RuleStoreDiagnosticEvent] = []
        let initialStore = RuleStore(
            storeURL: storeURL,
            backupURL: backupURL,
            diagnostics: { diagnosticsEvents.append($0) }
        )

        try initialStore.setAlwaysOpenIn(bundleIdentifier: "com.apple.Safari", forHost: "example.com")
        try initialStore.setAlwaysOpenIn(bundleIdentifier: "com.browser.Updated", forHost: "example.com")

        try Data("{ not valid json".utf8).write(to: storeURL)

        let recoveredStore = RuleStore(
            storeURL: storeURL,
            backupURL: backupURL,
            diagnostics: { diagnosticsEvents.append($0) }
        )

        XCTAssertEqual(
            recoveredStore.preferredTarget(forHost: "example.com")?.bundleIdentifier,
            "com.apple.Safari"
        )
        XCTAssertTrue(diagnosticsEvents.contains(.storeCorrupted))
        XCTAssertTrue(diagnosticsEvents.contains(.storeRecovered))
    }
}
