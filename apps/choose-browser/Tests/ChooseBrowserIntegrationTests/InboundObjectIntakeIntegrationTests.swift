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
#endif

#if canImport(ChooseBrowser)
@testable import ChooseBrowser
#else
struct RoutingRequest: Equatable {
    let url: URL
}

struct RoutingRequestEnvelope: Equatable {
    let request: RoutingRequest
    let receivedAt: TimeInterval
}

enum InboundSourceTriggerV2: Equatable {
    case browserExtensionToolbar
}

struct InboundSourceContextV2: Equatable {
    let sourceApplicationBundleIdentifier: String?
    let sourceTrigger: InboundSourceTriggerV2
    let isUserInitiated: Bool

    init(
        sourceApplicationBundleIdentifier: String? = nil,
        sourceTrigger: InboundSourceTriggerV2 = .browserExtensionToolbar,
        isUserInitiated: Bool = true
    ) {
        self.sourceApplicationBundleIdentifier = sourceApplicationBundleIdentifier
        self.sourceTrigger = sourceTrigger
        self.isUserInitiated = isUserInitiated
    }
}

enum InboundInputInvalidReasonV2: Equatable, Error {
    case invalidMailtoAddress
    case nonCanonicalFileURL
}

final class RequestQueue {
    func enqueue(_: RoutingRequest) {}
    func snapshot() -> [RoutingRequestEnvelope] { [] }
}

final class URLInboundPipeline {
    var onRejectedInbound: ((URL, InboundInputInvalidReasonV2) -> Void)?

    init(queue _: RequestQueue) {}

    func handleIncoming(urls _: [URL], sourceContext _: InboundSourceContextV2) {}
}
#endif

final class InboundObjectIntakeIntegrationTests: XCTestCase {
    func testMixedObjectIntakeEnqueuesHttpMailtoAndFileWithSourceContext() {
        let queue = RequestQueue()
        let pipeline = URLInboundPipeline(queue: queue)
        let sourceContext = InboundSourceContextV2(
            sourceApplicationBundleIdentifier: "com.choosebrowser.extension",
            sourceTrigger: .browserExtensionToolbar,
            isUserInitiated: true
        )

        let httpsURL = URL(string: "https://example.com/path?x=1#frag")!
        let mailtoURL = URL(string: "mailto:test@example.com")!
        let fileURL = URL(fileURLWithPath: "/tmp/report.pdf")

        pipeline.handleIncoming(urls: [httpsURL, mailtoURL, fileURL], sourceContext: sourceContext)

        let queuedURLs = queue.snapshot().map(\.request.url)
        XCTAssertEqual(queuedURLs, [httpsURL, mailtoURL, fileURL])
    }

    func testMalformedInputsAreRejectedWithExplicitReasonAndQueueUnchanged() {
        let queue = RequestQueue()
        let pipeline = URLInboundPipeline(queue: queue)
        var rejectedReasons: [InboundInputInvalidReasonV2] = []

        pipeline.onRejectedInbound = { _, reason in
            rejectedReasons.append(reason)
        }

        let invalidMailtoURL = URL(string: "mailto:")!
        let nonCanonicalFileURL = URL(string: "file://localhost/tmp/report.pdf")!
        let initialCount = queue.snapshot().count

        pipeline.handleIncoming(
            urls: [invalidMailtoURL, nonCanonicalFileURL],
            sourceContext: InboundSourceContextV2(sourceTrigger: .browserExtensionToolbar)
        )

        XCTAssertEqual(rejectedReasons, [.invalidMailtoAddress, .nonCanonicalFileURL])
        XCTAssertEqual(queue.snapshot().count, initialCount)
    }
}
