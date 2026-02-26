import AppKit

#if canImport(XCTest)
import XCTest
#else
import Foundation

class XCTestCase {}

func XCTAssertEqual<T: Equatable>(
    _ lhs: T,
    _ rhs: T,
    file: StaticString = #filePath,
    line: UInt = #line
) {}
#endif

#if canImport(ChooseBrowser)
@testable import ChooseBrowser
#else
struct RoutingRequest: Equatable {
    let url: URL
}

protocol RoutingRequestQueueing: AnyObject {
    func enqueue(_ request: RoutingRequest)
}

final class URLInboundPipeline {
    init(queue: RoutingRequestQueueing) {}
}

final class ChooseBrowserAppDelegate {
    init(inboundPipeline: URLInboundPipeline) {}

    func application(_ application: NSApplication, open url: URL) {}

    func application(_ application: NSApplication, open urls: [URL]) {}
}
#endif

final class URLInboundPipelineTests: XCTestCase {
    private final class SpyQueue: RoutingRequestQueueing {
        var requests: [RoutingRequest] = []

        func enqueue(_ request: RoutingRequest) {
            requests.append(request)
        }
    }

    func testEnqueuesIdenticalRoutingRequestURLForColdStartAndWarmStateEvents() {
        let queue = SpyQueue()
        let pipeline = URLInboundPipeline(queue: queue)
        let delegate = ChooseBrowserAppDelegate(inboundPipeline: pipeline)
        let inboundURL = URL(string: "https://example.com/path?x=1#frag")!

        delegate.application(NSApplication.shared, open: inboundURL)
        delegate.application(NSApplication.shared, open: [inboundURL])

        XCTAssertEqual(queue.requests.count, 2)
        XCTAssertEqual(queue.requests[0].url, inboundURL)
        XCTAssertEqual(queue.requests[1].url, inboundURL)
    }

    func testRejectsOnlyUnsupportedSchemes() {
        let queue = SpyQueue()
        let pipeline = URLInboundPipeline(queue: queue)
        let delegate = ChooseBrowserAppDelegate(inboundPipeline: pipeline)
        let mailtoURL = URL(string: "mailto:test@example.com")!
        let fileURL = URL(fileURLWithPath: "/tmp/test.txt")
        let supportedURL = URL(string: "https://example.com")!

        delegate.application(
            NSApplication.shared,
            open: [
                mailtoURL,
                fileURL,
                supportedURL,
                URL(string: "tel:+1234567")!,
            ]
        )

        XCTAssertEqual(queue.requests.count, 3)
        XCTAssertEqual(queue.requests[0].url, mailtoURL)
        XCTAssertEqual(queue.requests[1].url, fileURL)
        XCTAssertEqual(queue.requests[2].url, supportedURL)
    }
}
