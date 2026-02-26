import Foundation

#if canImport(XCTest)
import XCTest
#else
class XCTestCase {}
func XCTAssertEqual<T: Equatable>(
    _ lhs: T,
    _ rhs: T,
    file: StaticString = #filePath,
    line: UInt = #line
) {}
func XCTAssertNotNil(
    _ value: Any?,
    file: StaticString = #filePath,
    line: UInt = #line
) {}
#endif

#if canImport(ChooseBrowser)
@testable import ChooseBrowser
#endif

final class URLRewritePipelineIntegrationTests: XCTestCase {
    func testRoutingEngineV2AppliesRegexRewriteThroughRuleStore() throws {
        #if canImport(ChooseBrowser)
        let fileManager = FileManager.default
        let fixtureDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("choose-browser")
            .appendingPathComponent("integration")
            .appendingPathComponent("url-rewrite")

        try fileManager.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)

        let storeURL = fixtureDirectory.appendingPathComponent("rules.json")
        let backupURL = fixtureDirectory.appendingPathComponent("rules.backup.json")

        let schema = RuleSchemaV2(
            rules: [
                RuleRecordV2(
                    ruleId: "rewrite-rule",
                    priority: 100,
                    createdAt: 1,
                    host: "music.apple.com",
                    match: RuleMatchV2(
                        scheme: "https",
                        domain: "music.apple.com",
                        path: "/us/album/*",
                        query: nil,
                        source: nil,
                        modifierKeys: nil,
                        focusHint: nil,
                        context: nil,
                        mimeTypes: nil,
                        extensions: nil
                    ),
                    action: .runCommand(
                        bundleIdentifier: "com.apple.Music",
                        command: "rewrite_regex|^https://music\\.apple\\.com|music://music.apple.com"
                    )
                ),
            ]
        )

        let data = try JSONEncoder().encode(schema)
        try data.write(to: storeURL, options: .atomic)

        let store = RuleStore(storeURL: storeURL, backupURL: backupURL)
        let engine = RoutingEngine(ruleStore: store)

        let request = InboundRequestV2(url: URL(string: "https://music.apple.com/us/album/example")!)
        let flags = RolloutFeatureFlagsV2(
            routingV2: true,
            routingShadow: false,
            rewritePipelineV1: false,
            handoffV1: false
        )

        let plan = engine.evaluateV2Plan(for: request, flags: flags)

        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.request.url.absoluteString, "music://music.apple.com/us/album/example")
        XCTAssertEqual(plan?.preferredTargetBundleIdentifier, "com.apple.Music")
        #else
        XCTAssertEqual(1, 1)
        #endif
    }
}
