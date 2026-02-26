import Foundation

enum HandoffEnvelopeSourceV1: String, Equatable {
    case toolbar
    case contextmenu
    case link
    case share
    case handoff
}

struct HandoffEnvelopeV1: Equatable {
    let version: Int
    let url: String
    let source: HandoffEnvelopeSourceV1
    let sourceApplicationBundleIdentifier: String?
    let isUserInitiated: Bool

    init(
        version: Int = 1,
        url: String,
        source: HandoffEnvelopeSourceV1,
        sourceApplicationBundleIdentifier: String? = nil,
        isUserInitiated: Bool = true
    ) {
        self.version = version
        self.url = url
        self.source = source
        self.sourceApplicationBundleIdentifier = sourceApplicationBundleIdentifier
        self.isUserInitiated = isUserInitiated
    }
}

enum HandoffEnvelopeRejectReason: String, Equatable, Error {
    case malformedEnvelope = "malformed_envelope"
    case unsupportedVersion = "unsupported_version"
    case missingURL = "missing_url"
    case invalidURL = "invalid_url"
    case invalidSource = "invalid_source"
    case unsupportedScheme = "unsupported_scheme"
    case nonCanonicalFileURL = "non_canonical_file_url"
}

enum HandoffBrokerResult: Equatable {
    case inboundRequest(InboundRequestV2)
    case fallbackToDirectOpen(url: URL, reason: HandoffEnvelopeRejectReason)
    case rejected(HandoffEnvelopeRejectReason)
}

final class HandoffBroker {
    private static let supportedSchemes: Set<String> = ["http", "https", "mailto", "file"]

    func processEnvelopeData(_ data: Data, fallbackURL: URL? = nil) -> HandoffBrokerResult {
        switch parseEnvelope(data) {
        case let .success(envelope):
            return validateAndMap(envelope: envelope, fallbackURL: fallbackURL)
        case let .failure(reason):
            return fallbackOrReject(reason: reason, fallbackURL: fallbackURL)
        }
    }

    private func parseEnvelope(_ data: Data) -> Result<HandoffEnvelopeV1, HandoffEnvelopeRejectReason> {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any]
        else {
            return .failure(.malformedEnvelope)
        }

        guard let version = payload["version"] as? Int else {
            return .failure(.malformedEnvelope)
        }

        guard version == 1 else {
            return .failure(.unsupportedVersion)
        }

        guard let rawURL = payload["url"] as? String else {
            return .failure(.missingURL)
        }

        guard let rawSource = payload["source"] as? String,
              let source = HandoffEnvelopeSourceV1(rawValue: rawSource)
        else {
            return .failure(.invalidSource)
        }

        let sourceApplicationBundleIdentifier = payload["sourceApplicationBundleIdentifier"] as? String
        let isUserInitiated = payload["isUserInitiated"] as? Bool ?? true

        return .success(
            HandoffEnvelopeV1(
                version: version,
                url: rawURL,
                source: source,
                sourceApplicationBundleIdentifier: sourceApplicationBundleIdentifier,
                isUserInitiated: isUserInitiated
            )
        )
    }

    private func validateAndMap(
        envelope: HandoffEnvelopeV1,
        fallbackURL: URL?
    ) -> HandoffBrokerResult {
        guard let parsedURL = URL(string: envelope.url),
              let scheme = parsedURL.scheme?.lowercased()
        else {
            return fallbackOrReject(reason: .invalidURL, fallbackURL: fallbackURL)
        }

        guard Self.supportedSchemes.contains(scheme) else {
            return fallbackOrReject(reason: .unsupportedScheme, fallbackURL: fallbackURL)
        }

        if scheme == "file", !Self.isCanonicalFileURL(parsedURL) {
            return fallbackOrReject(reason: .nonCanonicalFileURL, fallbackURL: fallbackURL)
        }

        let mappedObjectType: InboundObjectTypeV2
        let mappedTrigger: InboundSourceTriggerV2

        switch envelope.source {
        case .toolbar:
            mappedObjectType = .extensionHandoff
            mappedTrigger = .browserExtensionToolbar
        case .contextmenu:
            mappedObjectType = .extensionHandoff
            mappedTrigger = .browserExtensionContextMenu
        case .link:
            mappedObjectType = .link
            mappedTrigger = .browserExtensionContextMenu
        case .share:
            mappedObjectType = .shareMenu
            mappedTrigger = .shareMenu
        case .handoff:
            mappedObjectType = .handoff
            mappedTrigger = .handoff
        }

        let request = InboundRequestV2(
            objectType: mappedObjectType,
            url: parsedURL,
            sourceContext: InboundSourceContextV2(
                sourceApplicationBundleIdentifier: envelope.sourceApplicationBundleIdentifier,
                sourceTrigger: mappedTrigger,
                isUserInitiated: envelope.isUserInitiated
            )
        )
        return .inboundRequest(request)
    }

    private func fallbackOrReject(
        reason: HandoffEnvelopeRejectReason,
        fallbackURL: URL?
    ) -> HandoffBrokerResult {
        guard let fallbackURL, isValidDirectOpenFallbackURL(fallbackURL) else {
            return .rejected(reason)
        }

        return .fallbackToDirectOpen(url: fallbackURL, reason: reason)
    }

    private func isValidDirectOpenFallbackURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              Self.supportedSchemes.contains(scheme)
        else {
            return false
        }

        if scheme == "file" {
            return Self.isCanonicalFileURL(url)
        }

        return true
    }

    private static func isCanonicalFileURL(_ url: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }

        let host = url.host ?? ""
        guard host.isEmpty else {
            return false
        }

        let normalized = url.absoluteURL
        return normalized.absoluteString.hasPrefix("file:///") && normalized.path.hasPrefix("/")
    }
}
