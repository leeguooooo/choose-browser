import Foundation

struct RoutingTarget: Equatable {
    let bundleIdentifier: String
    let displayName: String
}

enum RouteFallbackReason: Equatable {
    case timeout
    case invalidURL
}

enum RouteDecision: Equatable {
    case showChooser
    case route(RoutingTarget)
    case fallback(RouteFallbackReason)
}

enum RoutingShadowComparisonOutcome: Equatable {
    case matched
    case mismatched
    case skipped
}

enum RoutingShadowComparisonReason: String, Equatable {
    case matchedRoute = "matched_route"
    case matchedChooser = "matched_chooser"
    case v2Disabled = "v2_disabled"
    case v1Fallback = "v1_fallback"
    case v2MissingPlanForV1Route = "v2_missing_plan_for_v1_route"
    case v2TargetMismatch = "v2_target_mismatch"
    case v1ChooserButV2Target = "v1_chooser_but_v2_target"
    case v1RouteButV2Chooser = "v1_route_but_v2_chooser"
}

struct RoutingShadowComparisonResult: Equatable {
    let outcome: RoutingShadowComparisonOutcome
    let reason: RoutingShadowComparisonReason
    let v1DecisionSummary: String
    let v2DecisionSummary: String

    var counters: (total: Int, matched: Int, mismatched: Int, skipped: Int) {
        switch outcome {
        case .matched:
            return (1, 1, 0, 0)
        case .mismatched:
            return (1, 0, 1, 0)
        case .skipped:
            return (1, 0, 0, 1)
        }
    }
}
