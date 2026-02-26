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
func XCTAssertNil(
    _ value: Any?,
    file: StaticString = #filePath,
    line: UInt = #line
) {}
#endif

#if canImport(ChooseBrowser)
@testable import ChooseBrowser
#else
enum InboundSourceTriggerV2: String, Equatable {
    case coldStart
    case warmStart
    case browserExtensionToolbar
    case browserExtensionContextMenu
    case shareMenu
    case handoff
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

struct InboundRequestV2: Equatable {
    let objectType: String
    let url: URL
    let sourceContext: InboundSourceContextV2

    init(
        objectType: String = "link",
        url: URL,
        sourceContext: InboundSourceContextV2 = InboundSourceContextV2()
    ) {
        self.objectType = objectType
        self.url = url
        self.sourceContext = sourceContext
    }
}

enum RuleActionV2: Equatable {
    case alwaysOpenIn(bundleIdentifier: String)
    case alwaysAsk
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

    init(
        scheme: String? = nil,
        domain: String? = nil,
        path: String? = nil,
        query: String? = nil,
        source: String? = nil,
        modifierKeys: [String]? = nil,
        focusHint: String? = nil,
        context: String? = nil,
        mimeTypes: [String]? = nil,
        extensions: [String]? = nil
    ) {
        self.scheme = scheme
        self.domain = domain
        self.path = path
        self.query = query
        self.source = source
        self.modifierKeys = modifierKeys
        self.focusHint = focusHint
        self.context = context
        self.mimeTypes = mimeTypes
        self.extensions = extensions
    }
}

struct RuleRecordV2: Equatable {
    let ruleId: String
    let priority: Int
    let createdAt: Int
    let host: String?
    let match: RuleMatchV2
    let action: RuleActionV2

    init(
        ruleId: String,
        priority: Int,
        createdAt: Int,
        host: String? = nil,
        match: RuleMatchV2,
        action: RuleActionV2
    ) {
        self.ruleId = ruleId
        self.priority = priority
        self.createdAt = createdAt
        self.host = host
        self.match = match
        self.action = action
    }
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

    init(
        request: InboundRequestV2,
        preferredTargetBundleIdentifier: String? = nil,
        configuredFallbackBundleIdentifier: String? = nil,
        dispatchMode: ExecutionPlanDispatchModeV2 = .singleTarget,
        steps: [ExecutionPlanStepV2] = []
    ) {
        self.request = request
        self.preferredTargetBundleIdentifier = preferredTargetBundleIdentifier
        self.configuredFallbackBundleIdentifier = configuredFallbackBundleIdentifier
        self.dispatchMode = dispatchMode
        self.steps = steps
    }
}

struct RuleEvaluationContextV2: Equatable {
    let modifierKeys: [String]
    let focusHint: String?
    let context: String?
    let mimeType: String?
    let pathExtension: String?

    init(
        modifierKeys: [String] = [],
        focusHint: String? = nil,
        context: String? = nil,
        mimeType: String? = nil,
        pathExtension: String? = nil
    ) {
        self.modifierKeys = modifierKeys
        self.focusHint = focusHint
        self.context = context
        self.mimeType = mimeType
        self.pathExtension = pathExtension
    }
}

struct RuleEngineV2 {
    func evaluate(
        for _: InboundRequestV2,
        rules _: [RuleRecordV2],
        context _: RuleEvaluationContextV2 = RuleEvaluationContextV2()
    ) -> ExecutionPlanV2 {
        fatalError("ChooseBrowser module unavailable")
    }
}
#endif

final class RuleEngineV2DeterminismTests: XCTestCase {
    private func makeRequest(urlString: String = "https://example.com/path?source=test") -> InboundRequestV2 {
        InboundRequestV2(
            url: URL(string: urlString)!,
            sourceContext: InboundSourceContextV2(
                sourceApplicationBundleIdentifier: "com.example.SourceApp",
                sourceTrigger: .coldStart,
                isUserInitiated: true
            )
        )
    }

    private func matchRuleMatch(
        scheme: String? = nil,
        domain: String? = nil,
        path: String? = nil,
        query: String? = nil,
        source: String? = nil,
        modifierKeys: [String]? = nil,
        focusHint: String? = nil,
        context: String? = nil,
        mimeTypes: [String]? = nil,
        extensions: [String]? = nil
    ) -> RuleMatchV2 {
        RuleMatchV2(
            scheme: scheme,
            domain: domain,
            path: path,
            query: query,
            source: source,
            modifierKeys: modifierKeys,
            focusHint: focusHint,
            context: context,
            mimeTypes: mimeTypes,
            extensions: extensions
        )
    }

    private func matchRule(
        id: String,
        priority: Int,
        createdAt: Int,
        host: String? = nil,
        match: RuleMatchV2,
        action: RuleActionV2 = .alwaysOpenIn(bundleIdentifier: "com.example.Browser")
    ) -> RuleRecordV2 {
        RuleRecordV2(
            ruleId: id,
            priority: priority,
            createdAt: createdAt,
            host: host,
            match: match,
            action: action
        )
    }

    func testSelectsHighestPriorityFirst() {
        let engine = RuleEngineV2()
        let request = makeRequest()

        let lowerPriorityRule = matchRule(
            id: "lower",
            priority: 1,
            createdAt: 10,
            host: "example.com",
            match: matchRuleMatch(scheme: "https", domain: "example.com", path: "/path")
        )
        let higherPriorityRule = matchRule(
            id: "higher",
            priority: 100,
            createdAt: 1,
            host: "example.com",
            match: matchRuleMatch(scheme: "https")
        )

        let plan = engine.evaluate(for: request, rules: [lowerPriorityRule, higherPriorityRule])
        XCTAssertEqual(plan.preferredTargetBundleIdentifier, "com.example.Browser")
        XCTAssertEqual(plan.request, request)
    }

    func testSortPrefersHigherSpecificityWhenPriorityMatches() {
        let engine = RuleEngineV2()
        let request = makeRequest()

        let lessSpecificRule = matchRule(
            id: "less",
            priority: 10,
            createdAt: 20,
            host: "example.com",
            match: matchRuleMatch(scheme: "https")
        )
        let moreSpecificRule = matchRule(
            id: "more",
            priority: 10,
            createdAt: 30,
            host: "example.com",
            match: matchRuleMatch(scheme: "https", domain: "example.com", path: "/path")
        )

        let plan = engine.evaluate(for: request, rules: [lessSpecificRule, moreSpecificRule])
        XCTAssertEqual(plan.preferredTargetBundleIdentifier, "com.example.Browser")
        XCTAssertEqual(plan.steps.first?.action, "rewrite")
        XCTAssertEqual(plan.steps[1].action, "cleanup")
        XCTAssertEqual(plan.steps[2].action, "targetSelection")
        XCTAssertEqual(plan.steps[3].action, "launch")
    }

    func testSortUsesOldestCreatedAtWhenPriorityAndSpecificityMatch() {
        let engine = RuleEngineV2()
        let request = makeRequest()

        let newerRule = matchRule(
            id: "newer",
            priority: 10,
            createdAt: 200,
            host: "example.com",
            match: matchRuleMatch(scheme: "https", domain: "example.com", path: "/path")
        )
        let olderRule = matchRule(
            id: "older",
            priority: 10,
            createdAt: 100,
            host: "example.com",
            match: matchRuleMatch(scheme: "https", domain: "example.com", path: "/path")
        )

        let plan = engine.evaluate(for: request, rules: [newerRule, olderRule])
        XCTAssertEqual(plan.preferredTargetBundleIdentifier, "com.example.Browser")
        XCTAssertEqual(plan.steps.map { $0.action }, ["rewrite", "cleanup", "targetSelection", "launch"])
        XCTAssertEqual(plan.steps[0].detail.contains("older"), true)
    }

    func testSortUsesLexicographicRuleIdWhenPrioritySpecificityAndCreatedAtMatch() {
        let engine = RuleEngineV2()
        let request = makeRequest()

        let zRule = matchRule(
            id: "z-rule",
            priority: 10,
            createdAt: 100,
            host: "example.com",
            match: matchRuleMatch(scheme: "https", domain: "example.com")
        )
        let aRule = matchRule(
            id: "a-rule",
            priority: 10,
            createdAt: 100,
            host: "example.com",
            match: matchRuleMatch(scheme: "https", domain: "example.com")
        )

        let plan = engine.evaluate(for: request, rules: [zRule, aRule])
        XCTAssertEqual(plan.steps[0].detail, "rule-id=a-rule:alwaysOpenIn:com.example.Browser")
        XCTAssertEqual(plan.steps[2].detail, "com.example.Browser")
    }

    func testSortKeepsComparatorOrderingWithDifferentActionsWhenKeysTie() {
        let engine = RuleEngineV2()
        let request = makeRequest()

        let askRule = matchRule(
            id: "z-ask",
            priority: 10,
            createdAt: 100,
            host: "example.com",
            match: matchRuleMatch(scheme: "https", domain: "example.com"),
            action: .alwaysAsk
        )

        let commandRule = matchRule(
            id: "a-run",
            priority: 10,
            createdAt: 100,
            host: "example.com",
            match: matchRuleMatch(scheme: "https", domain: "example.com"),
            action: .runCommand(bundleIdentifier: "com.example.Commander", command: "open -a /Applications/Browser.app")
        )

        let plan = engine.evaluate(for: request, rules: [askRule, commandRule])

        XCTAssertEqual(plan.preferredTargetBundleIdentifier, "com.example.Commander")
        XCTAssertEqual(plan.steps[0].detail, "rule-id=a-run:runCommand:com.example.Commander:open -a /Applications/Browser.app")
        XCTAssertEqual(plan.steps.map { $0.action }, ["rewrite", "cleanup", "targetSelection", "launch"])
    }

    func testSortAppliesAllComparatorTiersInOneComparison() {
        let engine = RuleEngineV2()
        let request = makeRequest()

        let lowSpecificPriorityRule = matchRule(
            id: "low-specific",
            priority: 20,
            createdAt: 100,
            host: "example.com",
            match: matchRuleMatch(scheme: "https")
        )

        let higherSpecificityButNewerRule = matchRule(
            id: "z-newer",
            priority: 20,
            createdAt: 300,
            host: "example.com",
            match: matchRuleMatch(scheme: "https", domain: "example.com", path: "/path")
        )

        let higherSpecificityOlderRule = matchRule(
            id: "z-older",
            priority: 20,
            createdAt: 120,
            host: "example.com",
            match: matchRuleMatch(scheme: "https", domain: "example.com", path: "/path")
        )

        let highestPriorityRule = matchRule(
            id: "a-best",
            priority: 20,
            createdAt: 120,
            host: "example.com",
            match: matchRuleMatch(scheme: "https", domain: "example.com", path: "/path")
        )

        let plan = engine.evaluate(for: request, rules: [
            lowSpecificPriorityRule,
            higherSpecificityButNewerRule,
            higherSpecificityOlderRule,
            highestPriorityRule
        ])

        XCTAssertEqual(plan.preferredTargetBundleIdentifier, "com.example.Browser")
        XCTAssertEqual(plan.steps[0].detail, "rule-id=a-best:alwaysOpenIn:com.example.Browser")
        XCTAssertEqual(plan.steps.map { $0.action }, ["rewrite", "cleanup", "targetSelection", "launch"])
    }

    func testPlanStructureUsesStableStepOrder() {
        let engine = RuleEngineV2()
        let request = makeRequest()

        let alwaysAskRule = matchRule(
            id: "ask",
            priority: 10,
            createdAt: 100,
            host: "example.com",
            match: matchRuleMatch(scheme: "https", domain: "example.com"),
            action: .alwaysAsk
        )

        let plan = engine.evaluate(
            for: request,
            rules: [alwaysAskRule],
            context: RuleEvaluationContextV2()
        )

        XCTAssertEqual(plan.steps.map { $0.action }, ["rewrite", "cleanup", "targetSelection", "launch"])
        XCTAssertEqual(plan.steps[2].detail, "chooser")
        XCTAssertEqual(plan.preferredTargetBundleIdentifier, nil)
    }

    func testEvaluationIsDeterministicAcrossRepeatedRuns() {
        let engine = RuleEngineV2()
        let request = makeRequest()

        let ruleA = matchRule(
            id: "a-rule",
            priority: 5,
            createdAt: 100,
            host: "example.com",
            match: matchRuleMatch(scheme: "https", domain: "example.com", path: "/path")
        )
        let ruleB = matchRule(
            id: "b-rule",
            priority: 10,
            createdAt: 50,
            host: "example.com",
            match: matchRuleMatch(scheme: "https", domain: "example.com")
        )

        let plan1 = engine.evaluate(for: request, rules: [ruleA, ruleB])
        let plan2 = engine.evaluate(for: request, rules: [ruleA, ruleB])

        XCTAssertEqual(plan1, plan2)
    }

    func testComparatorOrderRemainsStableAcrossRuleInputPermutations() {
        let engine = RuleEngineV2()
        let request = makeRequest()

        let lowerSpecificity = matchRule(
            id: "mismatch-specificity",
            priority: 50,
            createdAt: 1,
            host: "example.com",
            match: matchRuleMatch(scheme: "https")
        )

        let newerMoreSpecific = matchRule(
            id: "newer-specific",
            priority: 50,
            createdAt: 100,
            host: "example.com",
            match: matchRuleMatch(scheme: "https", domain: "example.com", path: "/path")
        )

        let olderMoreSpecific = matchRule(
            id: "older-specific",
            priority: 50,
            createdAt: 10,
            host: "example.com",
            match: matchRuleMatch(scheme: "https", domain: "example.com", path: "/path")
        )

        let sameSpecificityOlderButLowerRuleId = matchRule(
            id: "a-top",
            priority: 50,
            createdAt: 10,
            host: "example.com",
            match: matchRuleMatch(scheme: "https", domain: "example.com", path: "/path")
        )

        let variants = [
            [lowerSpecificity, newerMoreSpecific, olderMoreSpecific, sameSpecificityOlderButLowerRuleId],
            [sameSpecificityOlderButLowerRuleId, lowerSpecificity, olderMoreSpecific, newerMoreSpecific],
            [newerMoreSpecific, sameSpecificityOlderButLowerRuleId, lowerSpecificity, olderMoreSpecific],
            [olderMoreSpecific, newerMoreSpecific, lowerSpecificity, sameSpecificityOlderButLowerRuleId],
        ]

        for rules in variants {
            let plan = engine.evaluate(for: request, rules: rules)
            XCTAssertEqual(plan.steps.first?.detail, "rule-id=a-top:alwaysOpenIn:com.example.Browser")
        }
    }

    func testExecutionPlanActionSequenceIsStableAcrossRepeatedEvaluations() {
        let engine = RuleEngineV2()
        let request = makeRequest()
        let rule = matchRule(
            id: "stable-sequence",
            priority: 20,
            createdAt: 1,
            host: "example.com",
            match: matchRuleMatch(scheme: "https", domain: "example.com", path: "/path"),
            action: .runCommand(bundleIdentifier: "com.example.Commander", command: "open -a /Applications/Browser.app")
        )

        for _ in 0..<25 {
            let plan = engine.evaluate(for: request, rules: [rule])
            XCTAssertEqual(plan.steps.map { $0.action }, ["rewrite", "cleanup", "targetSelection", "launch"])
            XCTAssertEqual(plan.steps[0].detail, "rule-id=stable-sequence:runCommand:com.example.Commander:open -a /Applications/Browser.app")
            XCTAssertEqual(plan.steps[2].detail, "com.example.Commander")
            XCTAssertEqual(plan.steps[3].detail, "com.example.Commander")
        }
    }
}
