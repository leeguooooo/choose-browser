import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

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
    private let rewritePipeline = URLRewritePipelineV2()

    func evaluate(
        for request: InboundRequestV2,
        rules: [RuleRecordV2],
        context: RuleEvaluationContextV2 = RuleEvaluationContextV2()
    ) -> ExecutionPlanV2 {
        let enrichedContext = enrichContext(context, for: request)
        let normalizedRequest = normalize(request)
        let candidates = rules.compactMap { rule -> MatchingCandidate? in
            guard matches(rule, request: normalizedRequest, context: enrichedContext) else {
                return nil
            }

            let specificity = specificity(for: rule, request: normalizedRequest, context: enrichedContext)
            return MatchingCandidate(rule: rule, specificity: specificity)
        }

        let sorted = sort(candidates)
        guard let winner = sorted.first else {
            return ExecutionPlanV2(request: request)
        }

        return makePlan(for: request, winner: winner)
    }

    private func enrichContext(_ context: RuleEvaluationContextV2, for request: InboundRequestV2) -> RuleEvaluationContextV2 {
        let derivedPathExtension = derivePathExtension(for: request)
        let effectivePathExtension = context.pathExtension ?? derivedPathExtension

        let derivedMimeType = deriveMIMEType(for: request, pathExtension: effectivePathExtension)
        let effectiveMimeType = context.mimeType ?? derivedMimeType

        return RuleEvaluationContextV2(
            modifierKeys: context.modifierKeys,
            focusHint: context.focusHint,
            context: context.context,
            mimeType: effectiveMimeType,
            pathExtension: effectivePathExtension
        )
    }

    private func derivePathExtension(for request: InboundRequestV2) -> String? {
        let rawExtension = request.url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawExtension.isEmpty else {
            return nil
        }

        return rawExtension.lowercased()
    }

    private func deriveMIMEType(for request: InboundRequestV2, pathExtension: String?) -> String? {
        guard contextNeedsFileMetadata(for: request) else {
            return nil
        }

        guard let pathExtension else {
            return nil
        }

#if canImport(UniformTypeIdentifiers)
        if let type = UTType(filenameExtension: pathExtension),
           let mimeType = type.preferredMIMEType
        {
            return mimeType.lowercased()
        }
#endif

        return nil
    }

    private func contextNeedsFileMetadata(for request: InboundRequestV2) -> Bool {
        if request.objectType == .file {
            return true
        }

        return request.url.isFileURL
    }

    private func sort(_ candidates: [MatchingCandidate]) -> [MatchingCandidate] {
        candidates.sorted(by: hasHigherPrecedence)
    }

    private func hasHigherPrecedence(_ lhs: MatchingCandidate, _ rhs: MatchingCandidate) -> Bool {
        if lhs.rule.priority != rhs.rule.priority {
            return lhs.rule.priority > rhs.rule.priority
        }

        if lhs.specificity != rhs.specificity {
            return lhs.specificity > rhs.specificity
        }

        if lhs.rule.createdAt != rhs.rule.createdAt {
            return lhs.rule.createdAt < rhs.rule.createdAt
        }

        return lhs.rule.ruleId < rhs.rule.ruleId
    }

    private func makePlan(for request: InboundRequestV2, winner: MatchingCandidate) -> ExecutionPlanV2 {
        let rewriteInstruction = rewriteInstruction(for: winner.rule.action)
        let rewriteResult = rewritePipeline.evaluate(request: request, instruction: rewriteInstruction)
        let preferred = winner.rule.targetReference?.bundleIdentifier ?? winner.rule.action.preferredBundleIdentifier
        let steps = orderedSteps(
            for: winner,
            rewriteInstruction: rewriteInstruction,
            rewriteResult: rewriteResult
        )

        return ExecutionPlanV2(
            request: rewriteResult.request,
            preferredTargetBundleIdentifier: preferred,
            configuredFallbackBundleIdentifier: nil,
            targetReference: winner.rule.targetReference,
            dispatchMode: .singleTarget,
            steps: steps
        )
    }

    private func orderedSteps(
        for winner: MatchingCandidate,
        rewriteInstruction: URLRewriteInstructionV2?,
        rewriteResult: URLRewriteResultV2
    ) -> [ExecutionPlanStepV2] {
        return [
            ExecutionPlanStepV2(
                action: "rewrite",
                detail: rewriteDetail(
                    for: winner,
                    rewriteInstruction: rewriteInstruction,
                    rewriteResult: rewriteResult
                )
            ),
            ExecutionPlanStepV2(action: "cleanup", detail: "cleanup-tracking"),
            ExecutionPlanStepV2(action: "targetSelection", detail: targetSelectionDetail(for: winner)),
            ExecutionPlanStepV2(action: "launch", detail: launchDetail(for: winner)),
        ]
    }

    private func rewriteDetail(
        for winner: MatchingCandidate,
        rewriteInstruction: URLRewriteInstructionV2?,
        rewriteResult: URLRewriteResultV2
    ) -> String {
        guard let rewriteInstruction else {
            return legacyRewriteDetail(for: winner)
        }

        let effectiveURL = rewriteResult.request.url.absoluteString
        var metadata = [
            "rule-id=\(winner.rule.ruleId)",
            "kind=\(rewriteInstruction.kind.rawValue)",
            "status=\(rewriteResult.status.rawValue)",
            "reason=\(rewriteResult.reason.rawValue)",
            "effective_url=\(effectiveURL)",
        ]

        if rewriteResult.status == .failed {
            metadata.append("fallback_reason=\(rewriteResult.reason.rawValue)")
        }

        return metadata.joined(separator: ":")
    }

    private func legacyRewriteDetail(for winner: MatchingCandidate) -> String {
        switch winner.rule.action {
        case let .alwaysOpenIn(bundleIdentifier):
            return "rule-id=\(winner.rule.ruleId):alwaysOpenIn:\(bundleIdentifier)"
        case let .runCommand(bundleIdentifier, command):
            return "rule-id=\(winner.rule.ruleId):runCommand:\(bundleIdentifier):\(command)"
        case .alwaysAsk:
            return "rule-id=\(winner.rule.ruleId):alwaysAsk"
        }
    }

    private func rewriteInstruction(for action: RuleActionV2) -> URLRewriteInstructionV2? {
        guard case let .runCommand(_, command) = action else {
            return nil
        }

        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        let regexPrefix = "rewrite_regex|"
        if normalized.hasPrefix(regexPrefix) {
            let payload = String(normalized.dropFirst(regexPrefix.count))
            let parts = payload.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                return .regex(pattern: "", replacement: "")
            }

            return .regex(pattern: String(parts[0]), replacement: String(parts[1]))
        }

        let scriptPrefix = "rewrite_script|"
        if normalized.hasPrefix(scriptPrefix) {
            let payload = String(normalized.dropFirst(scriptPrefix.count))
            return .script(source: payload)
        }

        return nil
    }

    private func targetSelectionDetail(for winner: MatchingCandidate) -> String {
        if let targetReference = winner.rule.targetReference {
            let profileSegment = targetReference.profileID ?? "none"
            let workspaceSegment = targetReference.workspaceID ?? "none"
            return "\(targetReference.bundleIdentifier):profile=\(profileSegment):workspace=\(workspaceSegment)"
        }

        switch winner.rule.action {
        case .alwaysOpenIn, .runCommand:
            return winner.rule.action.preferredBundleIdentifier ?? "unknown"
        case .alwaysAsk:
            return "chooser"
        }
    }

    private func launchDetail(for winner: MatchingCandidate) -> String {
        guard let target = winner.rule.action.preferredBundleIdentifier else {
            return "chooser"
        }

        return target
    }

    private func normalize(_ request: InboundRequestV2) -> NormalizedInboundRequestV2 {
        let host = request.url.host?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let scheme = request.url.scheme?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return NormalizedInboundRequestV2(
            host: host,
            scheme: scheme,
            path: request.url.path.isEmpty ? "/" : request.url.path,
            query: request.url.query,
            sourceApplicationBundleIdentifier: request.sourceContext.sourceApplicationBundleIdentifier
        )
    }

    private func matches(_ rule: RuleRecordV2, request: NormalizedInboundRequestV2, context: RuleEvaluationContextV2) -> Bool {
        if let scheme = rule.match.scheme, !match(scheme: scheme, request.scheme) {
            return false
        }

        if let expectedDomain = expectedDomain(for: rule),
           !match(domain: expectedDomain, request.host) {
            return false
        }

        if let path = rule.match.path, !match(path: path, request.path) {
            return false
        }

        if let query = rule.match.query, !match(query: query, request.query) {
            return false
        }

        if let source = rule.match.source,
           !match(string: source, request.sourceApplicationBundleIdentifier) {
            return false
        }

        if let focusHint = rule.match.focusHint, !match(string: focusHint, context.focusHint) {
            return false
        }

        if let ruleContext = rule.match.context, !match(string: ruleContext, context.context) {
            return false
        }

        if let mimeTypes = rule.match.mimeTypes,
           !mimeTypes.isEmpty,
           !match(values: mimeTypes, context.mimeType) {
            return false
        }

        if let extensions = rule.match.extensions,
           !extensions.isEmpty,
           !match(values: extensions, context.pathExtension) {
            return false
        }

        if let modifierKeys = rule.match.modifierKeys, !modifierKeys.isEmpty {
            return match(allModifierKeys: modifierKeys, in: context.modifierKeys)
        }

        return true
    }

    private func expectedDomain(for rule: RuleRecordV2) -> String? {
        if let matchDomain = rule.match.domain?.trimmingCharacters(in: .whitespacesAndNewlines),
           !matchDomain.isEmpty {
            return matchDomain
        }

        if let ruleHost = rule.host?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ruleHost.isEmpty {
            return ruleHost
        }

        return nil
    }

    private func specificity(for rule: RuleRecordV2, request: NormalizedInboundRequestV2, context: RuleEvaluationContextV2) -> Int {
        var score = 0
        let ruleMatch = rule.match

        if let scheme = ruleMatch.scheme, match(scheme: scheme, request.scheme) {
            score += 1
        }

        if let domain = expectedDomain(for: rule),
           match(domain: domain, request.host) {
            score += 1
        }

        if let path = ruleMatch.path, match(path: path, request.path) {
            score += 1
        }

        if let query = ruleMatch.query, match(query: query, request.query) {
            score += 1
        }

        if let source = ruleMatch.source, match(string: source, request.sourceApplicationBundleIdentifier) {
            score += 1
        }

        if let focusHint = ruleMatch.focusHint, match(string: focusHint, context.focusHint) {
            score += 1
        }

        if let ruleContext = ruleMatch.context, match(string: ruleContext, context.context) {
            score += 1
        }

        if let modifierKeys = ruleMatch.modifierKeys, !modifierKeys.isEmpty,
           match(allModifierKeys: modifierKeys, in: context.modifierKeys) {
            score += 1
        }

        if let mimeTypes = ruleMatch.mimeTypes, !mimeTypes.isEmpty,
           match(values: mimeTypes, context.mimeType) {
            score += 1
        }

        if let extensions = ruleMatch.extensions, !extensions.isEmpty,
           match(values: extensions, context.pathExtension) {
            score += 1
        }

        return score
    }

    func match(scheme: String, _ requestScheme: String?) -> Bool {
        guard let requestScheme else {
            return false
        }

        return scheme
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == requestScheme
    }

    func match(domain: String, _ host: String?) -> Bool {
        let normalizedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedDomain.isEmpty,
              let host else {
            return false
        }

        if normalizedDomain.hasPrefix("*.") {
            let suffix = String(normalizedDomain.dropFirst(2))
            return host == suffix || host.hasSuffix(".\(suffix)")
        }

        return host == normalizedDomain
    }

    func match(path: String, _ requestPath: String) -> Bool {
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            return false
        }

        if normalizedPath.hasSuffix("*") {
            return requestPath.hasPrefix(String(normalizedPath.dropLast()))
        }

        return requestPath == normalizedPath
    }

    func match(query: String, _ requestQuery: String?) -> Bool {
        guard let requestQuery else {
            return false
        }

        return requestQuery == query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func match(string: String, _ requestValue: String?) -> Bool {
        guard let requestValue else {
            return false
        }

        return string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == requestValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    func match(values: [String], _ value: String?) -> Bool {
        guard let value else {
            return false
        }

        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return values
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
            .contains(normalizedValue)
    }

    func match(allModifierKeys expected: [String], in actual: [String]) -> Bool {
        let expectedSet = Set(
            expected
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )

        let actualSet = Set(
            actual
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )

        return expectedSet.isSubset(of: actualSet)
    }
}

private struct MatchingCandidate: Equatable {
    let rule: RuleRecordV2
    let specificity: Int
}

private struct NormalizedInboundRequestV2 {
    let host: String?
    let scheme: String?
    let path: String
    let query: String?
    let sourceApplicationBundleIdentifier: String?
}

private extension RuleActionV2 {
    var preferredBundleIdentifier: String? {
        switch self {
        case let .alwaysOpenIn(bundleIdentifier):
            return bundleIdentifier
        case .alwaysAsk:
            return nil
        case let .runCommand(bundleIdentifier, _):
            return bundleIdentifier
        }
    }
}
