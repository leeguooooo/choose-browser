import Foundation

struct DiagnosticsEvent: Codable, Equatable {
    let timestamp: TimeInterval
    let category: String
    let message: String
    let metadata: [String: String]
}

final class DiagnosticsLogger {
    private let lock = NSLock()
    private let now: () -> Date
    private let debugMode: Bool
    private var events: [DiagnosticsEvent] = []

    init(
        debugMode: Bool = false,
        now: @escaping () -> Date = Date.init
    ) {
        self.debugMode = debugMode
        self.now = now
    }

    func log(
        category: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        let event = DiagnosticsEvent(
            timestamp: now().timeIntervalSince1970,
            category: category,
            message: message,
            metadata: metadata
        )

        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func logRoutingBatch(requests: [RoutingRequest]) {
        guard let firstURL = requests.first?.url else {
            return
        }

        log(
            category: "routing",
            message: "burst_batch_received",
            metadata: [
                "batch_size": String(requests.count),
                "url": redact(url: firstURL),
            ]
        )
    }

    func logDecision(url: URL, decision: String) {
        log(
            category: "routing",
            message: "decision",
            metadata: [
                "url": redact(url: url),
                "decision": decision,
            ]
        )
    }

    func logRoutingShadowComparison(url: URL, comparison: RoutingShadowComparisonResult) {
        let counters = comparison.counters

        log(
            category: "routing_shadow",
            message: "shadow_comparison",
            metadata: [
                "url": redact(url: url),
                "outcome": describe(outcome: comparison.outcome),
                "reason": comparison.reason.rawValue,
                "v1_decision": comparison.v1DecisionSummary,
                "v2_decision": comparison.v2DecisionSummary,
                "shadow_total_count": String(counters.total),
                "shadow_matched_count": String(counters.matched),
                "shadow_mismatched_count": String(counters.mismatched),
                "shadow_skipped_count": String(counters.skipped),
            ]
        )
    }

    func logRoutingRolloutInvalidConfiguration(
        reason: RoutingRolloutInvalidReason,
        flags: RolloutFeatureFlagsV2
    ) {
        log(
            category: "routing_shadow",
            message: "rollout_invalid_flag_configuration",
            metadata: [
                "reason": reason.rawValue,
                "routing_v2": String(flags.routingV2),
                "routing_shadow": String(flags.routingShadow),
            ]
        )
    }

    func exportBundle(to outputURL: URL) throws {
        let snapshot = self.snapshot()
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: outputURL, options: .atomic)
    }

    func snapshot() -> [DiagnosticsEvent] {
        lock.lock()
        let copy = events
        lock.unlock()
        return copy
    }

    private func redact(url: URL) -> String {
        if debugMode {
            return url.absoluteString
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "<redacted-url>"
        }

        components.query = nil
        components.fragment = nil

        var redacted = ""
        if let scheme = components.scheme {
            redacted += "\(scheme)://"
        }

        redacted += components.host ?? ""
        redacted += components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        return redacted
    }

    private func describe(outcome: RoutingShadowComparisonOutcome) -> String {
        switch outcome {
        case .matched:
            return "matched"
        case .mismatched:
            return "mismatched"
        case .skipped:
            return "skipped"
        }
    }
}
