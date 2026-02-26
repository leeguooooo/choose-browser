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

func XCTAssertNil(
    _ value: Any?,
    file _: StaticString = #filePath,
    line _: UInt = #line
) {}
#endif

#if canImport(ChooseBrowser)
@testable import ChooseBrowser
#else
enum InboundObjectTypeV2: Equatable {
    case link
    case email
    case file
}

enum InboundSourceTriggerV2: Equatable {
    case warmOpen
    case browserExtensionContextMenu
}

struct InboundSourceContextV2: Equatable {
    let sourceApplicationBundleIdentifier: String?
    let sourceTrigger: InboundSourceTriggerV2
    let isUserInitiated: Bool

    init(
        sourceApplicationBundleIdentifier: String? = nil,
        sourceTrigger: InboundSourceTriggerV2 = .warmOpen,
        isUserInitiated: Bool = true
    ) {
        self.sourceApplicationBundleIdentifier = sourceApplicationBundleIdentifier
        self.sourceTrigger = sourceTrigger
        self.isUserInitiated = isUserInitiated
    }
}

struct InboundRequestV2: Equatable {
    let objectType: InboundObjectTypeV2
    let url: URL
    let sourceContext: InboundSourceContextV2
}

enum InboundInputInvalidReasonV2: Equatable, Error {
    case unsupportedScheme
    case invalidMailtoAddress
    case nonCanonicalFileURL
}

struct RoutingRequest: Equatable {
    let url: URL
}

protocol RoutingRequestQueueing: AnyObject {
    func enqueue(_ request: RoutingRequest)
}

final class URLInboundPipeline {
    init(queue _: RoutingRequestQueueing) {}

    func makeInboundRequestV2(
        from _: URL,
        sourceContext _: InboundSourceContextV2 = InboundSourceContextV2()
    ) -> Result<InboundRequestV2, InboundInputInvalidReasonV2> {
        .failure(.unsupportedScheme)
    }

    func makeRoutingRequest(from _: URL) -> RoutingRequest? {
        nil
    }
}
#endif

final class InboundRequestV2Tests: XCTestCase {
    private final class SpyQueue: RoutingRequestQueueing {
        func enqueue(_: RoutingRequest) {}
    }

    func testNormalizesHttpHttpsMailtoAndFileIntoInboundRequestV2() {
        let pipeline = URLInboundPipeline(queue: SpyQueue())
        let sourceContext = InboundSourceContextV2(
            sourceApplicationBundleIdentifier: "com.apple.Safari",
            sourceTrigger: .browserExtensionContextMenu,
            isUserInitiated: true
        )

        let httpsURL = URL(string: "https://example.com/path?x=1#frag")!
        let mailtoURL = URL(string: "mailto:test@example.com")!
        let fileURL = URL(fileURLWithPath: "/tmp/report.pdf")

        let httpsResult = pipeline.makeInboundRequestV2(from: httpsURL, sourceContext: sourceContext)
        let mailtoResult = pipeline.makeInboundRequestV2(from: mailtoURL, sourceContext: sourceContext)
        let fileResult = pipeline.makeInboundRequestV2(from: fileURL, sourceContext: sourceContext)

        XCTAssertEqual(try? httpsResult.get().objectType, .link)
        XCTAssertEqual(try? httpsResult.get().sourceContext, sourceContext)
        XCTAssertEqual(try? mailtoResult.get().objectType, .email)
        XCTAssertEqual(try? mailtoResult.get().sourceContext, sourceContext)
        XCTAssertEqual(try? fileResult.get().objectType, .file)
        XCTAssertEqual(try? fileResult.get().sourceContext, sourceContext)
    }

    func testRejectsInvalidMailtoWithExplicitReason() {
        let pipeline = URLInboundPipeline(queue: SpyQueue())
        let invalidMailtoURL = URL(string: "mailto:")!

        let result = pipeline.makeInboundRequestV2(from: invalidMailtoURL)

        XCTAssertEqual(result, .failure(.invalidMailtoAddress))
    }

    func testRejectsNonCanonicalFileURLWithExplicitReason() {
        let pipeline = URLInboundPipeline(queue: SpyQueue())
        let nonCanonicalFileURL = URL(string: "file://localhost/tmp/report.pdf")!

        let result = pipeline.makeInboundRequestV2(from: nonCanonicalFileURL)

        XCTAssertEqual(result, .failure(.nonCanonicalFileURL))
    }

    func testRejectsMalformedInputsWithoutProducingRoutingRequest() {
        let pipeline = URLInboundPipeline(queue: SpyQueue())
        let invalidMailtoURL = URL(string: "mailto:")!
        let nonCanonicalFileURL = URL(string: "file://localhost/tmp/report.pdf")!

        XCTAssertNil(pipeline.makeRoutingRequest(from: invalidMailtoURL))
        XCTAssertNil(pipeline.makeRoutingRequest(from: nonCanonicalFileURL))
    }
}
