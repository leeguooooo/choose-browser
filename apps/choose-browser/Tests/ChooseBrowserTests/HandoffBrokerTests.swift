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
enum InboundObjectTypeV2: Equatable {
    case link
    case extensionHandoff
    case shareMenu
    case handoff
}

enum InboundSourceTriggerV2: Equatable {
    case browserExtensionToolbar
    case browserExtensionContextMenu
    case shareMenu
    case handoff
}

struct InboundSourceContextV2: Equatable {
    let sourceApplicationBundleIdentifier: String?
    let sourceTrigger: InboundSourceTriggerV2
    let isUserInitiated: Bool
}

struct InboundRequestV2: Equatable {
    let objectType: InboundObjectTypeV2
    let url: URL
    let sourceContext: InboundSourceContextV2
}

enum HandoffEnvelopeRejectReason: Equatable {
    case malformedEnvelope
    case invalidSource
}

enum HandoffBrokerResult: Equatable {
    case inboundRequest(InboundRequestV2)
    case fallbackToDirectOpen(url: URL, reason: HandoffEnvelopeRejectReason)
    case rejected(HandoffEnvelopeRejectReason)
}

final class HandoffBroker {
    func processEnvelopeData(_: Data, fallbackURL _: URL? = nil) -> HandoffBrokerResult {
        .rejected(.malformedEnvelope)
    }
}
#endif

final class HandoffBrokerTests: XCTestCase {
    private func makeEnvelopeData(_ payload: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    func testParsesValidToolbarEnvelopeIntoInboundRequest() throws {
        let broker = HandoffBroker()
        let requestURL = "https://example.com/path?x=1"
        let payload: [String: Any] = [
            "version": 1,
            "url": requestURL,
            "source": "toolbar",
            "sourceApplicationBundleIdentifier": "com.apple.Safari",
            "isUserInitiated": true,
        ]
        let data = try makeEnvelopeData(payload)

        let result = broker.processEnvelopeData(data)

        switch result {
        case let .inboundRequest(request):
            XCTAssertEqual(request.objectType, .extensionHandoff)
            XCTAssertEqual(request.url.absoluteString, requestURL)
            XCTAssertEqual(request.sourceContext.sourceApplicationBundleIdentifier, "com.apple.Safari")
            XCTAssertEqual(request.sourceContext.sourceTrigger, .browserExtensionToolbar)
            XCTAssertEqual(request.sourceContext.isUserInitiated, true)
        default:
            XCTFail("expected inbound request")
        }
    }

    func testMapsHandoffSourceIntoHandoffInboundRequest() throws {
        let broker = HandoffBroker()
        let payload: [String: Any] = [
            "version": 1,
            "url": "https://handoff.example/open",
            "source": "handoff",
            "isUserInitiated": false,
        ]
        let data = try makeEnvelopeData(payload)

        let result = broker.processEnvelopeData(data)

        switch result {
        case let .inboundRequest(request):
            XCTAssertEqual(request.objectType, .handoff)
            XCTAssertEqual(request.sourceContext.sourceTrigger, .handoff)
            XCTAssertEqual(request.sourceContext.isUserInitiated, false)
        default:
            XCTFail("expected handoff inbound request")
        }
    }

    func testInvalidSourceRoutesToDeterministicDirectOpenFallback() throws {
        let broker = HandoffBroker()
        let fallbackURL = URL(string: "https://fallback.example/direct-open")!
        let payload: [String: Any] = [
            "version": 1,
            "url": "https://example.com/open",
            "source": "invalid_source",
        ]
        let data = try makeEnvelopeData(payload)

        let result = broker.processEnvelopeData(data, fallbackURL: fallbackURL)

        XCTAssertEqual(
            result,
            .fallbackToDirectOpen(url: fallbackURL, reason: .invalidSource)
        )
    }

    func testMalformedEnvelopeWithoutFallbackFailsClosed() {
        let broker = HandoffBroker()
        let malformedData = Data("not-json".utf8)

        let result = broker.processEnvelopeData(malformedData)

        XCTAssertEqual(result, .rejected(.malformedEnvelope))
    }
}
