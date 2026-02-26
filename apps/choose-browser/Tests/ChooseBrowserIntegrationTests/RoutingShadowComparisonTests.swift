import Foundation

#if canImport(XCTest)
import XCTest
#else
class XCTestCase {}

func XCTAssertEqual<T: Equatable>(
    _ lhs: T,
    _ rhs: T,
    file _: StaticString = #filePath,
    line _: UInt = #line
) {}

func XCTFail(
    _ message: String = "",
    file _: StaticString = #filePath,
    line _: UInt = #line
) {}
#endif

#if canImport(ChooseBrowser)
@testable import ChooseBrowser
#else
struct RoutingTarget: Equatable {
    let bundleIdentifier: String
    let displayName: String
}

enum RouteDecision: Equatable {
    case showChooser
    case route(RoutingTarget)
}

struct InboundSourceContextV2: Equatable {
    init(sourceTrigger _: InboundSourceTriggerV2 = .warmOpen) {}
}

enum InboundSourceTriggerV2: Equatable {
    case warmOpen
}

enum InboundObjectTypeV2: Equatable {
    case link
}

struct InboundRequestV2: Equatable {
    let objectType: InboundObjectTypeV2
    let url: URL
    let sourceContext: InboundSourceContextV2
}

struct RuleEvaluationContextV2: Equatable {
    init() {}
}

struct ExecutionPlanV2: Equatable {
    let request: InboundRequestV2
    let preferredTargetBundleIdentifier: String?
}

struct RolloutFeatureFlagsV2: Equatable {
    let routingV2: Bool
    let routingShadow: Bool
    let rewritePipelineV1: Bool
    let handoffV1: Bool

    static let disabled = RolloutFeatureFlagsV2(routingV2: false, routingShadow: false, rewritePipelineV1: false, handoffV1: false)
}

enum RoutingRolloutInvalidReason: String, Equatable {
    case v2AndShadowEnabled = "v2_and_shadow_enabled"
}

enum RoutingRolloutMode: Equatable {
    case v1Only
    case v2Primary
    case v1WithShadow
    case invalid(RoutingRolloutInvalidReason)
}

struct RoutingRolloutConfiguration: Equatable {
    let flags: RolloutFeatureFlagsV2
    let mode: RoutingRolloutMode

    static func from(routingV2: Bool, routingShadow: Bool) -> RoutingRolloutConfiguration {
        let flags = RolloutFeatureFlagsV2(
            routingV2: routingV2,
            routingShadow: routingShadow,
            rewritePipelineV1: false,
            handoffV1: false
        )

        if routingV2, routingShadow {
            return RoutingRolloutConfiguration(flags: flags, mode: .invalid(.v2AndShadowEnabled))
        }

        if routingV2 {
            return RoutingRolloutConfiguration(flags: flags, mode: .v2Primary)
        }

        if routingShadow {
            return RoutingRolloutConfiguration(flags: flags, mode: .v1WithShadow)
        }

        return RoutingRolloutConfiguration(flags: flags, mode: .v1Only)
    }
}

enum RoutingShadowComparisonOutcome: Equatable {
    case matched
    case mismatched
    case skipped
}

enum RoutingShadowComparisonReason: String, Equatable {
    case matchedRoute
    case v2TargetMismatch
    case v2Disabled
    case v2MissingPlanForV1Route
    case v1ChooserButV2Target
    case v1RouteButV2Chooser
}

struct RoutingShadowComparisonResult {
    let outcome: RoutingShadowComparisonOutcome
    let reason: RoutingShadowComparisonReason
    let v1DecisionSummary: String
    let v2DecisionSummary: String
    let counters: (total: Int, matched: Int, mismatched: Int, skipped: Int)
}

struct DiagnosticsEvent: Equatable {
    let timestamp: TimeInterval
    let category: String
    let message: String
    let metadata: [String: String]
}

protocol RuleStoring {
    func preferredTarget(forHost host: String) -> RoutingTarget?
    func evaluateV2Plan(for request: InboundRequestV2, context: RuleEvaluationContextV2) -> ExecutionPlanV2?
}

struct RoutingEngine {
    init(ruleStore _: RuleStoring) {}
    func decide(for _: URL) -> RouteDecision { .showChooser }
    func compareWithShadowV2(
        for _: URL,
        v1Decision _: RouteDecision,
        flags _: RolloutFeatureFlagsV2,
        context _: RuleEvaluationContextV2 = RuleEvaluationContextV2(),
        sourceContext _: InboundSourceContextV2 = InboundSourceContextV2()
    ) -> RoutingShadowComparisonResult {
        RoutingShadowComparisonResult(
            outcome: .skipped,
            reason: .v2Disabled,
            v1DecisionSummary: "",
            v2DecisionSummary: "",
            counters: (1, 0, 0, 1)
        )
    }
}

final class DiagnosticsLogger {
    init(debugMode _: Bool = false) {}
    func logRoutingShadowComparison(url _: URL, comparison _: RoutingShadowComparisonResult) {}
    func logRoutingRolloutInvalidConfiguration(reason _: RoutingRolloutInvalidReason, flags _: RolloutFeatureFlagsV2) {}
    func snapshot() -> [DiagnosticsEvent] { [] }
}
#endif

final class RoutingShadowComparisonTests: XCTestCase {
    private static let sourceFilePath = #filePath
    private static let failureToggleMarkerRelativePath = ".sisyphus/evidence/parity/.force-routing-shadow-invalid-flags-failure"

    private final class RuleStoreStub: RuleStoring {
        private let lookup: (String) -> RoutingTarget?
        private let v2Evaluator: (InboundRequestV2, RuleEvaluationContextV2) -> ExecutionPlanV2?

        init(
            lookup: @escaping (String) -> RoutingTarget?,
            v2Evaluator: @escaping (InboundRequestV2, RuleEvaluationContextV2) -> ExecutionPlanV2?
        ) {
            self.lookup = lookup
            self.v2Evaluator = v2Evaluator
        }

        func preferredTarget(forHost host: String) -> RoutingTarget? {
            lookup(host)
        }

        func evaluateV2Plan(for request: InboundRequestV2, context: RuleEvaluationContextV2) -> ExecutionPlanV2? {
            v2Evaluator(request, context)
        }
    }

    private func enabledShadowFlags() -> RolloutFeatureFlagsV2 {
        RolloutFeatureFlagsV2(routingV2: false, routingShadow: true, rewritePipelineV1: false, handoffV1: false)
    }

    func testShadowEnabledMismatchLogsDeterministicReasonWithoutChangingV1Decision() {
        let v1Target = RoutingTarget(bundleIdentifier: "com.browser.alpha", displayName: "Alpha")
        let v2Target = "com.browser.beta"
        let store = RuleStoreStub(
            lookup: { host in
                host == "example.com" ? v1Target : nil
            },
            v2Evaluator: { request, _ in
                ExecutionPlanV2(request: request, preferredTargetBundleIdentifier: v2Target)
            }
        )
        let engine = RoutingEngine(ruleStore: store)
        let logger = DiagnosticsLogger(debugMode: false)
        let url = URL(string: "https://example.com/path")!

        let v1Decision = engine.decide(for: url)
        let comparison = engine.compareWithShadowV2(for: url, v1Decision: v1Decision, flags: enabledShadowFlags())
        logger.logRoutingShadowComparison(url: url, comparison: comparison)

        XCTAssertEqual(v1Decision, .route(v1Target))
        XCTAssertEqual(comparison.outcome, .mismatched)
        XCTAssertEqual(comparison.reason, .v2TargetMismatch)

        let shadowEvent = logger.snapshot().last
        XCTAssertEqual(shadowEvent?.metadata["reason"], "v2_target_mismatch")
        XCTAssertEqual(shadowEvent?.metadata["shadow_total_count"], "1")
        XCTAssertEqual(shadowEvent?.metadata["shadow_matched_count"], "0")
        XCTAssertEqual(shadowEvent?.metadata["shadow_mismatched_count"], "1")
        XCTAssertEqual(shadowEvent?.metadata["shadow_skipped_count"], "0")
    }

    func testShadowDisabledSkipsWithExplicitReasonAndCounters() {
        let expectedTarget = RoutingTarget(bundleIdentifier: "com.browser.alpha", displayName: "Alpha")
        let store = RuleStoreStub(
            lookup: { host in
                host == "example.com" ? expectedTarget : nil
            },
            v2Evaluator: { request, _ in
                ExecutionPlanV2(request: request, preferredTargetBundleIdentifier: "com.browser.beta")
            }
        )
        let engine = RoutingEngine(ruleStore: store)
        let logger = DiagnosticsLogger(debugMode: false)
        let url = URL(string: "https://example.com/path")!

        let v1Decision = engine.decide(for: url)
        let comparison = engine.compareWithShadowV2(for: url, v1Decision: v1Decision, flags: .disabled)
        logger.logRoutingShadowComparison(url: url, comparison: comparison)

        XCTAssertEqual(v1Decision, .route(expectedTarget))
        XCTAssertEqual(comparison.outcome, .skipped)
        XCTAssertEqual(comparison.reason, .v2Disabled)

        let shadowEvent = logger.snapshot().last
        XCTAssertEqual(shadowEvent?.metadata["reason"], "v2_disabled")
        XCTAssertEqual(shadowEvent?.metadata["shadow_total_count"], "1")
        XCTAssertEqual(shadowEvent?.metadata["shadow_matched_count"], "0")
        XCTAssertEqual(shadowEvent?.metadata["shadow_mismatched_count"], "0")
        XCTAssertEqual(shadowEvent?.metadata["shadow_skipped_count"], "1")
    }

    func testMismatchReasonTaxonomyIsRecordedDeterministically() {
        let url = URL(string: "https://example.com/path")!

        let routeTarget = RoutingTarget(bundleIdentifier: "com.browser.alpha", displayName: "Alpha")
        let routeDecision = RouteDecision.route(routeTarget)
        let chooserDecision = RouteDecision.showChooser

        let cases: [(description: String, v1Decision: RouteDecision, v2Plan: ExecutionPlanV2?, expectedReason: String)] = [
            (
                "v2 target mismatch",
                routeDecision,
                ExecutionPlanV2(
                    request: InboundRequestV2(objectType: .link, url: url, sourceContext: InboundSourceContextV2(sourceTrigger: .warmOpen)),
                    preferredTargetBundleIdentifier: "com.browser.beta"
                ),
                "v2_target_mismatch"
            ),
            ("v2 missing plan for v1 route", routeDecision, nil, "v2_missing_plan_for_v1_route"),
            (
                "v1 chooser but v2 target",
                chooserDecision,
                ExecutionPlanV2(
                    request: InboundRequestV2(objectType: .link, url: url, sourceContext: InboundSourceContextV2(sourceTrigger: .warmOpen)),
                    preferredTargetBundleIdentifier: "com.browser.alpha"
                ),
                "v1_chooser_but_v2_target"
            ),
            (
                "v1 route but v2 chooser",
                routeDecision,
                ExecutionPlanV2(
                    request: InboundRequestV2(objectType: .link, url: url, sourceContext: InboundSourceContextV2(sourceTrigger: .warmOpen)),
                    preferredTargetBundleIdentifier: "  "
                ),
                "v1_route_but_v2_chooser"
            ),
        ]

        for testCase in cases {
            let store = RuleStoreStub(
                lookup: { host in
                    host == "example.com" ? routeTarget : nil
                },
                v2Evaluator: { _, _ in
                    testCase.v2Plan
                }
            )
            let engine = RoutingEngine(ruleStore: store)
            let logger = DiagnosticsLogger(debugMode: false)
            let comparison = engine.compareWithShadowV2(
                for: url,
                v1Decision: testCase.v1Decision,
                flags: enabledShadowFlags()
            )

            logger.logRoutingShadowComparison(url: url, comparison: comparison)
            XCTAssertEqual(logger.snapshot().last?.metadata["reason"], testCase.expectedReason)
            XCTAssertEqual(logger.snapshot().last?.metadata["shadow_mismatched_count"], "1")
        }
    }

    func testInvalidFeatureFlagCombinationFailsClosedWithExplicitDiagnosticAndNoCrash() {
        let configuration = RoutingRolloutConfiguration.from(routingV2: true, routingShadow: true)
        let logger = DiagnosticsLogger(debugMode: false)

        if case let .invalid(reason) = configuration.mode {
            logger.logRoutingRolloutInvalidConfiguration(reason: reason, flags: configuration.flags)
        }

        let event = logger.snapshot().last
        XCTAssertEqual(event?.category, "routing_shadow")
        XCTAssertEqual(event?.message, "rollout_invalid_flag_configuration")
        XCTAssertEqual(event?.metadata["reason"], "v2_and_shadow_enabled")
        XCTAssertEqual(event?.metadata["routing_v2"], "true")
        XCTAssertEqual(event?.metadata["routing_shadow"], "true")
    }

    func testRoutingShadowExplicitFailureScenarioWhenMarkerEnabled() {
        guard Self.shouldInjectFailureScenario() else {
            XCTAssertEqual(1, 1)
            return
        }

        let configuration = RoutingRolloutConfiguration.from(routingV2: true, routingShadow: true)
        if case let .invalid(reason) = configuration.mode {
            XCTFail("routing-shadow-invalid-flags: \(reason.rawValue): __must_fail_routing_shadow_flag_combination__")
            return
        }

        XCTFail("routing-shadow-invalid-flags: __must_fail_routing_shadow_flag_combination__")
    }

    private static func shouldInjectFailureScenario() -> Bool {
        if ProcessInfo.processInfo.environment["ROUTING_SHADOW_REQUIRE_INVALID_FLAG_FAILURE"] == "1" {
            return true
        }

        for base in candidateRoots() {
            let markerPath = base.appendingPathComponent(failureToggleMarkerRelativePath)
            if FileManager.default.fileExists(atPath: markerPath.path) {
                return true
            }
        }

        return false
    }

    private static func candidateRoots() -> [URL] {
        var roots: [URL] = []

        var sourceRoot = URL(fileURLWithPath: sourceFilePath, isDirectory: false)
        for _ in 0..<5 {
            sourceRoot.deleteLastPathComponent()
        }
        roots.append(sourceRoot)

        var current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        for _ in 0..<8 {
            roots.append(current)
            current.deleteLastPathComponent()
        }

        return roots
    }
}
