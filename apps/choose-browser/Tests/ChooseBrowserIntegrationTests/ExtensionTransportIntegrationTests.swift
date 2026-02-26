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
    case extensionHandoff
}

enum InboundSourceTriggerV2: Equatable {
    case browserExtensionToolbar
    case browserExtensionContextMenu
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

enum ExtensionTransportResult: Equatable {
    case inboundRequest(InboundRequestV2)
    case fallbackToDirectOpen(url: URL, reasonCode: String)
    case rejected(reasonCode: String)
}

protocol NativeMessagingHostAvailabilityChecking {
    func isHostAvailable() -> Bool
}

final class SafariExtensionTransportAdapter {
    func receive(payload _: Data, fallbackURL _: URL? = nil) -> ExtensionTransportResult {
        .rejected(reasonCode: "stub")
    }
}

final class NativeMessagingTransportAdapter {
    init(hostAvailabilityChecker _: NativeMessagingHostAvailabilityChecking) {}

    func receive(payload _: Data, fallbackURL _: URL? = nil) -> ExtensionTransportResult {
        .rejected(reasonCode: "stub")
    }
}
#endif

final class ExtensionTransportIntegrationTests: XCTestCase {
    private struct HostUnavailableChecker: NativeMessagingHostAvailabilityChecking {
        func isHostAvailable() -> Bool {
            false
        }
    }

    private func makePayloadData(_ payload: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    func testTransportAdapterRoutesToolbarAndContextMenuPayloadsToHandoffBroker() throws {
        let adapter = SafariExtensionTransportAdapter()
        let cases: [(source: String, expectedTrigger: InboundSourceTriggerV2)] = [
            ("toolbar", .browserExtensionToolbar),
            ("contextmenu", .browserExtensionContextMenu),
        ]

        for caseInfo in cases {
            let payload: [String: Any] = [
                "version": 1,
                "url": "https://example.com/\(caseInfo.source)",
                "source": caseInfo.source,
                "sourceApplicationBundleIdentifier": "com.apple.Safari",
                "isUserInitiated": true,
            ]
            let data = try makePayloadData(payload)
            let result = adapter.receive(payload: data)

            switch result {
            case let .inboundRequest(request):
                XCTAssertEqual(request.objectType, .extensionHandoff)
                XCTAssertEqual(request.sourceContext.sourceTrigger, caseInfo.expectedTrigger)
                XCTAssertEqual(request.sourceContext.sourceApplicationBundleIdentifier, "com.apple.Safari")
                XCTAssertEqual(request.sourceContext.isUserInitiated, true)
            default:
                XCTFail("expected inbound request for \(caseInfo.source)")
            }
        }
    }

    func testNativeMessagingUnavailableFallsBackToDirectLaunchPath() throws {
        let adapter = NativeMessagingTransportAdapter(hostAvailabilityChecker: HostUnavailableChecker())
        let fallbackURL = URL(string: "https://fallback.example/native-host")!
        let payload: [String: Any] = [
            "version": 1,
            "url": "https://example.com/native-host",
            "source": "toolbar",
        ]
        let data = try makePayloadData(payload)

        let result = adapter.receive(payload: data, fallbackURL: fallbackURL)

        XCTAssertEqual(
            result,
            .fallbackToDirectOpen(url: fallbackURL, reasonCode: "host_unavailable")
        )
    }
}
