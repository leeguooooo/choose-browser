import Foundation

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

    static let disabled = RoutingRolloutConfiguration(flags: .disabled, mode: .v1Only)

    static func from(arguments: [String]) -> RoutingRolloutConfiguration {
        let routingV2 = arguments.contains("--routing-v2")
        let routingShadow = arguments.contains("--routing-v2-shadow") || arguments.contains("--routing-shadow")
        return from(routingV2: routingV2, routingShadow: routingShadow)
    }

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
