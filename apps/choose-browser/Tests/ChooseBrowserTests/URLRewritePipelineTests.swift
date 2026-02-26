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
func XCTAssertTrue(
    _ expression: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) {}
#endif

#if canImport(ChooseBrowser)
@testable import ChooseBrowser
#else
enum InboundSourceTriggerV2: String, Equatable {
    case unknown
}

struct InboundSourceContextV2: Equatable {
    let sourceApplicationBundleIdentifier: String?
    let sourceTrigger: InboundSourceTriggerV2
    let isUserInitiated: Bool

    init(
        sourceApplicationBundleIdentifier: String? = nil,
        sourceTrigger: InboundSourceTriggerV2 = .unknown,
        isUserInitiated: Bool = true
    ) {
        self.sourceApplicationBundleIdentifier = sourceApplicationBundleIdentifier
        self.sourceTrigger = sourceTrigger
        self.isUserInitiated = isUserInitiated
    }
}

enum InboundObjectTypeV2: String, Equatable {
    case link
}

struct InboundRequestV2: Equatable {
    let objectType: InboundObjectTypeV2
    let url: URL
    let sourceContext: InboundSourceContextV2

    init(
        objectType: InboundObjectTypeV2 = .link,
        url: URL,
        sourceContext: InboundSourceContextV2 = InboundSourceContextV2()
    ) {
        self.objectType = objectType
        self.url = url
        self.sourceContext = sourceContext
    }
}

enum RuleActionV2: Equatable {
    case runCommand(bundleIdentifier: String, command: String)
}

struct RuleMatchV2: Equatable {
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

struct RuleRecordV2: Equatable {
    let ruleId: String
    let priority: Int
    let createdAt: Int
    let host: String?
    let match: RuleMatchV2
    let action: RuleActionV2
}

struct ExecutionPlanStepV2: Equatable {
    let action: String
    let detail: String
}

enum ExecutionPlanDispatchModeV2: Equatable {
    case singleTarget
}

struct ExecutionPlanV2: Equatable {
    let request: InboundRequestV2
    let preferredTargetBundleIdentifier: String?
    let configuredFallbackBundleIdentifier: String?
    let dispatchMode: ExecutionPlanDispatchModeV2
    let steps: [ExecutionPlanStepV2]
}

struct RuleEvaluationContextV2: Equatable {
    init() {}
}

struct RuleEngineV2 {
    func evaluate(
        for request: InboundRequestV2,
        rules _: [RuleRecordV2],
        context _: RuleEvaluationContextV2 = RuleEvaluationContextV2()
    ) -> ExecutionPlanV2 {
        ExecutionPlanV2(
            request: request,
            preferredTargetBundleIdentifier: nil,
            configuredFallbackBundleIdentifier: nil,
            dispatchMode: .singleTarget,
            steps: []
        )
    }
}
#endif

final class URLRewritePipelineTests: XCTestCase {
    private func makeRule(
        id: String,
        command: String,
        priority: Int = 100,
        createdAt: Int = 1
    ) -> RuleRecordV2 {
        RuleRecordV2(
            ruleId: id,
            priority: priority,
            createdAt: createdAt,
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
            action: .runCommand(bundleIdentifier: "com.apple.Music", command: command)
        )
    }

    private func evaluatePlan(command: String, urlString: String) -> ExecutionPlanV2 {
        let engine = RuleEngineV2()
        let request = InboundRequestV2(url: URL(string: urlString)!)
        let rule = makeRule(id: "rewrite-rule", command: command)
        return engine.evaluate(for: request, rules: [rule])
    }

    func testAppliesRegexRewriteBeforeTargetSelection() {
        let command = "rewrite_regex|^https://music\\.apple\\.com|music://music.apple.com"
        let plan = evaluatePlan(
            command: command,
            urlString: "https://music.apple.com/us/album/example"
        )

        XCTAssertEqual(plan.request.url.absoluteString, "music://music.apple.com/us/album/example")
        XCTAssertEqual(plan.preferredTargetBundleIdentifier, "com.apple.Music")
        XCTAssertEqual(plan.steps.map { $0.action }, ["rewrite", "cleanup", "targetSelection", "launch"])
        XCTAssertEqual(plan.steps[0].detail, "rule-id=rewrite-rule:kind=regex:status=applied:reason=ok:effective_url=music://music.apple.com/us/album/example")
        XCTAssertEqual(plan.steps[2].detail, "com.apple.Music")
    }

    func testMalformedRegexKeepsOriginalURLAndProvidesFailureReason() {
        let command = "rewrite_regex|([|music://music.apple.com"
        let inputURL = "https://music.apple.com/us/album/example"
        let plan = evaluatePlan(command: command, urlString: inputURL)

        XCTAssertEqual(plan.request.url.absoluteString, inputURL)
        XCTAssertEqual(plan.steps[0].detail, "rule-id=rewrite-rule:kind=regex:status=failed:reason=invalid_regex:effective_url=https://music.apple.com/us/album/example:fallback_reason=invalid_regex")
    }

    func testUnsafeScriptIsRejectedAndOriginalURLIsPreserved() {
        let command = "rewrite_script|URLSession.shared.dataTask(with: URL(string:'https://example.com')!)"
        let inputURL = "https://music.apple.com/us/album/example"
        let plan = evaluatePlan(command: command, urlString: inputURL)

        XCTAssertEqual(plan.request.url.absoluteString, inputURL)
        XCTAssertEqual(plan.steps[0].detail, "rule-id=rewrite-rule:kind=script:status=failed:reason=unsafe_script_token:effective_url=https://music.apple.com/us/album/example:fallback_reason=unsafe_script_token")
    }

    func testSupportedScriptCanSetCustomSchemeDeterministically() {
        let command = "rewrite_script|setScheme('music')"
        let plan = evaluatePlan(
            command: command,
            urlString: "https://music.apple.com/us/album/example"
        )

        XCTAssertEqual(plan.request.url.absoluteString, "music://music.apple.com/us/album/example")
        XCTAssertEqual(plan.steps[0].detail, "rule-id=rewrite-rule:kind=script:status=applied:reason=ok:effective_url=music://music.apple.com/us/album/example")
    }

    func testUnsupportedScriptFailsClosedWithExplicitMetadata() {
        let command = "rewrite_script|mapURL('music')"
        let inputURL = "https://music.apple.com/us/album/example"
        let plan = evaluatePlan(command: command, urlString: inputURL)

        XCTAssertEqual(plan.request.url.absoluteString, inputURL)
        XCTAssertEqual(plan.steps[0].detail, "rule-id=rewrite-rule:kind=script:status=failed:reason=unsupported_script:effective_url=https://music.apple.com/us/album/example:fallback_reason=unsupported_script")
    }

    func testMalformedScriptFailsClosedWithFallbackToUnsupportedReason() {
        let command = "rewrite_script|setScheme('music'"
        let inputURL = "https://music.apple.com/us/album/example"
        let plan = evaluatePlan(command: command, urlString: inputURL)

        XCTAssertEqual(plan.request.url.absoluteString, inputURL)
        XCTAssertEqual(plan.steps[0].detail, "rule-id=rewrite-rule:kind=script:status=failed:reason=unsupported_script:effective_url=https://music.apple.com/us/album/example:fallback_reason=unsupported_script")
    }

    func testScriptPathImportCommandIsRejectedAsUnsupported() {
        let command = "rewrite_script|load('/tmp/rewrite.js')"
        let inputURL = "https://music.apple.com/us/album/example"
        let plan = evaluatePlan(command: command, urlString: inputURL)

        XCTAssertEqual(plan.request.url.absoluteString, inputURL)
        XCTAssertEqual(plan.steps[0].detail, "rule-id=rewrite-rule:kind=script:status=failed:reason=unsupported_script:effective_url=https://music.apple.com/us/album/example:fallback_reason=unsupported_script")
    }

    func testMalformedRegexInstructionFallsBackToOriginalURL() {
        let command = "rewrite_regex|^https://music\\.apple\\.com"
        let inputURL = "https://music.apple.com/us/album/example"
        let plan = evaluatePlan(command: command, urlString: inputURL)

        XCTAssertEqual(plan.request.url.absoluteString, inputURL)
        XCTAssertEqual(plan.steps[0].detail, "rule-id=rewrite-rule:kind=regex:status=failed:reason=malformed_instruction:effective_url=https://music.apple.com/us/album/example:fallback_reason=malformed_instruction")
    }
}
