import Foundation

protocol RuleStoring {
    func preferredTarget(forHost host: String) -> RoutingTarget?
    func evaluateV2Plan(for request: InboundRequestV2, context: RuleEvaluationContextV2) -> ExecutionPlanV2?
}

extension RuleStoring {
    func evaluateV2Plan(for request: InboundRequestV2, context: RuleEvaluationContextV2) -> ExecutionPlanV2? {
        nil
    }
}

struct NormalizedRoutingURL: Equatable {
    let originalURL: URL
    let normalizedHost: String
}

struct RoutingEngine {
    static let defaultDecisionTimeout: TimeInterval = 1.5

    private let ruleStore: RuleStoring
    private let decisionTimeout: TimeInterval
    private let now: () -> TimeInterval

    init(
        ruleStore: RuleStoring,
        decisionTimeout: TimeInterval = RoutingEngine.defaultDecisionTimeout,
        now: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }
    ) {
        self.ruleStore = ruleStore
        self.decisionTimeout = decisionTimeout
        self.now = now
    }

    func decide(for url: URL) -> RouteDecision {
        let startTime = now()

        guard let normalizedRequest = normalize(url) else {
            return .fallback(.invalidURL)
        }

        if elapsedSince(startTime) > decisionTimeout {
            return .fallback(.timeout)
        }

        if let target = ruleStore.preferredTarget(forHost: normalizedRequest.normalizedHost) {
            if elapsedSince(startTime) > decisionTimeout {
                return .fallback(.timeout)
            }

            return .route(target)
        }

        if elapsedSince(startTime) > decisionTimeout {
            return .fallback(.timeout)
        }

        return .showChooser
    }

    func evaluateV2Plan(
        for request: InboundRequestV2,
        context: RuleEvaluationContextV2 = RuleEvaluationContextV2(),
        flags: RolloutFeatureFlagsV2 = .disabled
    ) -> ExecutionPlanV2? {
        guard flags.routingV2 || flags.routingShadow else {
            return nil
        }

        return ruleStore.evaluateV2Plan(for: request, context: context)
    }

    func decideUsingV2(
        for url: URL,
        context: RuleEvaluationContextV2 = RuleEvaluationContextV2(),
        sourceContext: InboundSourceContextV2 = InboundSourceContextV2(sourceTrigger: .warmOpen)
    ) -> RouteDecision {
        let v1Decision = decide(for: url)

        guard shouldCompare(v1Decision: v1Decision) else {
            return v1Decision
        }

        let request = InboundRequestV2(objectType: .link, url: url, sourceContext: sourceContext)
        let v2Plan = ruleStore.evaluateV2Plan(for: request, context: context)
        return routeDecision(from: v2Plan)
    }

    func compareWithShadowV2(
        for url: URL,
        v1Decision: RouteDecision,
        flags: RolloutFeatureFlagsV2 = .disabled,
        context: RuleEvaluationContextV2 = RuleEvaluationContextV2(),
        sourceContext: InboundSourceContextV2 = InboundSourceContextV2(sourceTrigger: .warmOpen)
    ) -> RoutingShadowComparisonResult {
        let v1Summary = summarize(v1Decision: v1Decision)

        guard flags.routingShadow else {
            return RoutingShadowComparisonResult(
                outcome: .skipped,
                reason: .v2Disabled,
                v1DecisionSummary: v1Summary,
                v2DecisionSummary: "disabled"
            )
        }

        guard shouldCompare(v1Decision: v1Decision) else {
            return RoutingShadowComparisonResult(
                outcome: .skipped,
                reason: .v1Fallback,
                v1DecisionSummary: v1Summary,
                v2DecisionSummary: "not-evaluated"
            )
        }

        let request = InboundRequestV2(objectType: .link, url: url, sourceContext: sourceContext)
        let v2Plan = ruleStore.evaluateV2Plan(for: request, context: context)
        return compare(v1Decision: v1Decision, v2Plan: v2Plan, v1Summary: v1Summary)
    }

    func normalize(_ url: URL) -> NormalizedRoutingURL? {
        guard URLComponents(url: url, resolvingAgainstBaseURL: false) != nil else {
            return nil
        }

        guard let host = extractNormalizedHost(from: url), !host.isEmpty else {
            return nil
        }

        return NormalizedRoutingURL(originalURL: url, normalizedHost: host)
    }

    private func extractNormalizedHost(from url: URL) -> String? {
        let raw = url.absoluteString

        guard let schemeBoundary = raw.range(of: "://") else {
            return nil
        }

        var authoritySlice = raw[schemeBoundary.upperBound...]

        if let slash = authoritySlice.firstIndex(of: "/") {
            authoritySlice = authoritySlice[..<slash]
        }

        if let questionMark = authoritySlice.firstIndex(of: "?") {
            authoritySlice = authoritySlice[..<questionMark]
        }

        if let hash = authoritySlice.firstIndex(of: "#") {
            authoritySlice = authoritySlice[..<hash]
        }

        if let at = authoritySlice.lastIndex(of: "@") {
            authoritySlice = authoritySlice[authoritySlice.index(after: at)...]
        }

        let authority = String(authoritySlice)

        if authority.hasPrefix("[") {
            guard let close = authority.firstIndex(of: "]") else {
                return nil
            }

            return String(authority[authority.startIndex...close]).lowercased()
        }

        let host = authority.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true).first

        return host.map { String($0).lowercased() }
    }

    private func elapsedSince(_ startTime: TimeInterval) -> TimeInterval {
        now() - startTime
    }

    private func shouldCompare(v1Decision: RouteDecision) -> Bool {
        switch v1Decision {
        case .showChooser, .route:
            return true
        case .fallback:
            return false
        }
    }

    private func summarize(v1Decision: RouteDecision) -> String {
        switch v1Decision {
        case let .route(target):
            return "route:\(target.bundleIdentifier)"
        case .showChooser:
            return "showChooser"
        case let .fallback(reason):
            return "fallback:\(reason)"
        }
    }

    private func summarize(v2Plan: ExecutionPlanV2?) -> String {
        guard let v2Plan else {
            return "showChooser"
        }

        guard let preferredTargetBundleIdentifier = v2Plan.preferredTargetBundleIdentifier,
              !preferredTargetBundleIdentifier.isEmpty
        else {
            return "showChooser"
        }

        return "route:\(preferredTargetBundleIdentifier)"
    }

    private func compare(
        v1Decision: RouteDecision,
        v2Plan: ExecutionPlanV2?,
        v1Summary: String
    ) -> RoutingShadowComparisonResult {
        let v2Summary = summarize(v2Plan: v2Plan)
        let v2Target = v2Plan?.preferredTargetBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedV2Target = (v2Target?.isEmpty == false) ? v2Target : nil

        switch v1Decision {
        case let .route(target):
            guard let normalizedV2Target else {
                return RoutingShadowComparisonResult(
                    outcome: .mismatched,
                    reason: v2Plan == nil ? .v2MissingPlanForV1Route : .v1RouteButV2Chooser,
                    v1DecisionSummary: v1Summary,
                    v2DecisionSummary: v2Summary
                )
            }

            if normalizedV2Target == target.bundleIdentifier {
                return RoutingShadowComparisonResult(
                    outcome: .matched,
                    reason: .matchedRoute,
                    v1DecisionSummary: v1Summary,
                    v2DecisionSummary: v2Summary
                )
            }

            return RoutingShadowComparisonResult(
                outcome: .mismatched,
                reason: .v2TargetMismatch,
                v1DecisionSummary: v1Summary,
                v2DecisionSummary: v2Summary
            )
        case .showChooser:
            if normalizedV2Target == nil {
                return RoutingShadowComparisonResult(
                    outcome: .matched,
                    reason: .matchedChooser,
                    v1DecisionSummary: v1Summary,
                    v2DecisionSummary: v2Summary
                )
            }

            return RoutingShadowComparisonResult(
                outcome: .mismatched,
                reason: .v1ChooserButV2Target,
                v1DecisionSummary: v1Summary,
                v2DecisionSummary: v2Summary
            )
        case .fallback:
            return RoutingShadowComparisonResult(
                outcome: .skipped,
                reason: .v1Fallback,
                v1DecisionSummary: v1Summary,
                v2DecisionSummary: "not-evaluated"
            )
        }
    }

    private func routeDecision(from plan: ExecutionPlanV2?) -> RouteDecision {
        guard let preferredTargetBundleIdentifier = plan?.preferredTargetBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !preferredTargetBundleIdentifier.isEmpty
        else {
            return .showChooser
        }

        return .route(
            RoutingTarget(
                bundleIdentifier: preferredTargetBundleIdentifier,
                displayName: preferredTargetBundleIdentifier
            )
        )
    }
}
