import Foundation

enum URLRewriteKindV2: String, Equatable {
    case regex
    case script
}

enum URLRewriteStatusV2: String, Equatable {
    case notConfigured = "not_configured"
    case applied
    case failed
}

enum URLRewriteReasonV2: String, Equatable {
    case noRewriteInstruction = "no_rewrite_instruction"
    case applied = "ok"
    case malformedInstruction = "malformed_instruction"
    case invalidRegex = "invalid_regex"
    case invalidOutputURL = "invalid_output_url"
    case scriptTooLong = "script_too_long"
    case unsafeScriptToken = "unsafe_script_token"
    case unsupportedScript = "unsupported_script"
}

enum URLRewriteInstructionV2: Equatable {
    case regex(pattern: String, replacement: String)
    case script(source: String)

    var kind: URLRewriteKindV2 {
        switch self {
        case .regex:
            return .regex
        case .script:
            return .script
        }
    }
}

struct URLRewriteResultV2: Equatable {
    let request: InboundRequestV2
    let status: URLRewriteStatusV2
    let reason: URLRewriteReasonV2
}

struct URLRewritePipelineV2 {
    private static let maxScriptLength = 256
    private static let maxOutputLength = 4096
    private static let unsafeScriptTokens = [
        "URLSession",
        "FileManager",
        "Process(",
        "import ",
        "while ",
        "for ",
        "repeat ",
        "DispatchQueue",
    ]

    func evaluate(request: InboundRequestV2, instruction: URLRewriteInstructionV2?) -> URLRewriteResultV2 {
        guard let instruction else {
            return URLRewriteResultV2(
                request: request,
                status: .notConfigured,
                reason: .noRewriteInstruction
            )
        }

        switch instruction {
        case let .regex(pattern, replacement):
            return applyRegexRewrite(pattern: pattern, replacement: replacement, request: request)
        case let .script(source):
            return applyScriptRewrite(source: source, request: request)
        }
    }

    private func applyRegexRewrite(
        pattern: String,
        replacement: String,
        request: InboundRequestV2
    ) -> URLRewriteResultV2 {
        guard !pattern.isEmpty else {
            return URLRewriteResultV2(
                request: request,
                status: .failed,
                reason: .malformedInstruction
            )
        }

        let input = request.url.absoluteString

        do {
            let regularExpression = try NSRegularExpression(pattern: pattern)
            let fullRange = NSRange(input.startIndex..<input.endIndex, in: input)
            let rewritten = regularExpression.stringByReplacingMatches(
                in: input,
                options: [],
                range: fullRange,
                withTemplate: replacement
            )

            return finalizeRewrite(originalRequest: request, rewritten: rewritten)
        } catch {
            return URLRewriteResultV2(
                request: request,
                status: .failed,
                reason: .invalidRegex
            )
        }
    }

    private func applyScriptRewrite(source: String, request: InboundRequestV2) -> URLRewriteResultV2 {
        if source.count > Self.maxScriptLength {
            return URLRewriteResultV2(
                request: request,
                status: .failed,
                reason: .scriptTooLong
            )
        }

        if Self.unsafeScriptTokens.contains(where: { source.contains($0) }) {
            return URLRewriteResultV2(
                request: request,
                status: .failed,
                reason: .unsafeScriptToken
            )
        }

        if let scheme = matchSingleArgument(source: source, command: "setScheme") {
            return rewriteBySettingScheme(scheme, request: request)
        }

        if let arguments = matchTwoArguments(source: source, command: "replacePrefix") {
            let rewritten = request.url.absoluteString.replacingOccurrences(
                of: arguments.first,
                with: arguments.second,
                options: [.anchored],
                range: nil
            )

            return finalizeRewrite(originalRequest: request, rewritten: rewritten)
        }

        if let arguments = matchTwoArguments(source: source, command: "replaceRegex") {
            return applyRegexRewrite(
                pattern: arguments.first,
                replacement: arguments.second,
                request: request
            )
        }

        return URLRewriteResultV2(
            request: request,
            status: .failed,
            reason: .unsupportedScript
        )
    }

    private func rewriteBySettingScheme(_ scheme: String, request: InboundRequestV2) -> URLRewriteResultV2 {
        guard let first = scheme.unicodeScalars.first,
              CharacterSet.letters.contains(first)
        else {
            return URLRewriteResultV2(
                request: request,
                status: .failed,
                reason: .unsupportedScript
            )
        }

        var components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
        components?.scheme = scheme

        guard let rewrittenURL = components?.url else {
            return URLRewriteResultV2(
                request: request,
                status: .failed,
                reason: .invalidOutputURL
            )
        }

        let rewrittenRequest = InboundRequestV2(
            objectType: request.objectType,
            url: rewrittenURL,
            sourceContext: request.sourceContext
        )

        return URLRewriteResultV2(
            request: rewrittenRequest,
            status: .applied,
            reason: .applied
        )
    }

    private func finalizeRewrite(
        originalRequest: InboundRequestV2,
        rewritten: String
    ) -> URLRewriteResultV2 {
        guard rewritten.count <= Self.maxOutputLength,
              let rewrittenURL = URL(string: rewritten),
              rewrittenURL.scheme != nil
        else {
            return URLRewriteResultV2(
                request: originalRequest,
                status: .failed,
                reason: .invalidOutputURL
            )
        }

        let rewrittenRequest = InboundRequestV2(
            objectType: originalRequest.objectType,
            url: rewrittenURL,
            sourceContext: originalRequest.sourceContext
        )

        return URLRewriteResultV2(
            request: rewrittenRequest,
            status: .applied,
            reason: .applied
        )
    }

    private func matchSingleArgument(source: String, command: String) -> String? {
        let pattern = "^\(command)\\('([^']+)'\\)$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, options: [], range: range),
              match.numberOfRanges == 2,
              let argumentRange = Range(match.range(at: 1), in: source)
        else {
            return nil
        }

        return String(source[argumentRange])
    }

    private func matchTwoArguments(source: String, command: String) -> (first: String, second: String)? {
        let pattern = "^\(command)\\('([^']*)','([^']*)'\\)$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, options: [], range: range),
              match.numberOfRanges == 3,
              let firstRange = Range(match.range(at: 1), in: source),
              let secondRange = Range(match.range(at: 2), in: source)
        else {
            return nil
        }

        return (String(source[firstRange]), String(source[secondRange]))
    }
}
