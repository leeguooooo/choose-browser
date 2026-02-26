import Foundation

enum InboundObjectTypeV2: String, Codable, Equatable {
    case link
    case email
    case file
    case extensionHandoff
    case shareMenu
    case handoff
}

enum InboundSourceTriggerV2: String, Codable, Equatable {
    case coldStart
    case warmOpen
    case browserExtensionToolbar
    case browserExtensionContextMenu
    case shareMenu
    case handoff
    case unknown
}

struct InboundSourceContextV2: Codable, Equatable {
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

struct InboundRequestV2: Codable, Equatable {
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

enum InboundInputInvalidReasonV2: String, Codable, Equatable, Error {
    case unsupportedScheme
    case invalidMailtoAddress
    case nonCanonicalFileURL
}

enum ExecutionPlanDispatchModeV2: String, Codable, Equatable {
    case singleTarget
    case orderedFailover
    case fanout
}

struct ExecutionPlanStepV2: Codable, Equatable {
    let action: String
    let detail: String

    init(action: String, detail: String) {
        self.action = action
        self.detail = detail
    }
}

struct ExecutionPlanV2: Codable, Equatable {
    let request: InboundRequestV2
    let preferredTargetBundleIdentifier: String?
    let configuredFallbackBundleIdentifier: String?
    let targetReference: RuleTargetReferenceV2?
    let dispatchMode: ExecutionPlanDispatchModeV2
    let steps: [ExecutionPlanStepV2]

    init(
        request: InboundRequestV2,
        preferredTargetBundleIdentifier: String? = nil,
        configuredFallbackBundleIdentifier: String? = nil,
        targetReference: RuleTargetReferenceV2? = nil,
        dispatchMode: ExecutionPlanDispatchModeV2 = .singleTarget,
        steps: [ExecutionPlanStepV2] = []
    ) {
        self.request = request
        self.preferredTargetBundleIdentifier = preferredTargetBundleIdentifier
        self.configuredFallbackBundleIdentifier = configuredFallbackBundleIdentifier
        self.targetReference = targetReference
        self.dispatchMode = dispatchMode
        self.steps = steps
    }
}

struct RolloutFeatureFlagsV2: Codable, Equatable {
    let routingV2: Bool
    let routingShadow: Bool
    let rewritePipelineV1: Bool
    let handoffV1: Bool

    init(
        routingV2: Bool,
        routingShadow: Bool = false,
        rewritePipelineV1: Bool,
        handoffV1: Bool
    ) {
        self.routingV2 = routingV2
        self.routingShadow = routingShadow
        self.rewritePipelineV1 = rewritePipelineV1
        self.handoffV1 = handoffV1
    }

    static let disabled = RolloutFeatureFlagsV2(
        routingV2: false,
        routingShadow: false,
        rewritePipelineV1: false,
        handoffV1: false
    )
}
