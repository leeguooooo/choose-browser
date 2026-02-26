import Foundation

enum ExtensionTransportResult: Equatable {
    case inboundRequest(InboundRequestV2)
    case fallbackToDirectOpen(url: URL, reasonCode: String)
    case rejected(reasonCode: String)
}

protocol HandoffBrokering {
    func processEnvelopeData(_ data: Data, fallbackURL: URL?) -> HandoffBrokerResult
}

extension HandoffBroker: HandoffBrokering {}

protocol NativeMessagingHostAvailabilityChecking {
    func isHostAvailable() -> Bool
}

struct NativeMessagingHostAvailabilityChecker: NativeMessagingHostAvailabilityChecking {
    func isHostAvailable() -> Bool {
        true
    }
}

final class SafariExtensionTransportAdapter {
    private let broker: HandoffBrokering

    init(broker: HandoffBrokering = HandoffBroker()) {
        self.broker = broker
    }

    func receive(payload: Data, fallbackURL: URL? = nil) -> ExtensionTransportResult {
        mapBrokerResult(broker.processEnvelopeData(payload, fallbackURL: fallbackURL))
    }

    fileprivate func mapBrokerResult(_ result: HandoffBrokerResult) -> ExtensionTransportResult {
        switch result {
        case let .inboundRequest(request):
            return .inboundRequest(request)
        case let .fallbackToDirectOpen(url, reason):
            return .fallbackToDirectOpen(url: url, reasonCode: reason.rawValue)
        case let .rejected(reason):
            return .rejected(reasonCode: reason.rawValue)
        }
    }
}

final class NativeMessagingTransportAdapter {
    private static let hostUnavailableReasonCode = "host_unavailable"

    private let broker: HandoffBrokering
    private let hostAvailabilityChecker: NativeMessagingHostAvailabilityChecking

    init(
        broker: HandoffBrokering = HandoffBroker(),
        hostAvailabilityChecker: NativeMessagingHostAvailabilityChecking = NativeMessagingHostAvailabilityChecker()
    ) {
        self.broker = broker
        self.hostAvailabilityChecker = hostAvailabilityChecker
    }

    func receive(payload: Data, fallbackURL: URL? = nil) -> ExtensionTransportResult {
        if !hostAvailabilityChecker.isHostAvailable() {
            if let fallbackURL {
                return .fallbackToDirectOpen(
                    url: fallbackURL,
                    reasonCode: Self.hostUnavailableReasonCode
                )
            }

            return .rejected(reasonCode: Self.hostUnavailableReasonCode)
        }

        let safariAdapter = SafariExtensionTransportAdapter(broker: broker)
        return safariAdapter.receive(payload: payload, fallbackURL: fallbackURL)
    }
}
