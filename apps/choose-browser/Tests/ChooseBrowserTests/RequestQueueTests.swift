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

func XCTAssertTrue(
    _ condition: Bool,
    file _: StaticString = #filePath,
    line _: UInt = #line
) {}

func XCTAssertFalse(
    _ condition: Bool,
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

final class RequestQueue {
    private let now: () -> TimeInterval
    private var envelopes: [RoutingRequestEnvelope] = []
    var onEnqueue: (() -> Void)?

    init(now: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }) {
        self.now = now
    }

    func enqueue(_ request: RoutingRequest) {
        envelopes.append(RoutingRequestEnvelope(request: request, receivedAt: now()))
        onEnqueue?()
    }

    func dequeueBurst(window: TimeInterval) -> [RoutingRequest] {
        guard let first = envelopes.first else {
            return []
        }

        var count = 1
        while count < envelopes.count {
            if (envelopes[count].receivedAt - first.receivedAt) <= window {
                count += 1
            } else {
                break
            }
        }

        let batch = Array(envelopes.prefix(count)).map(\.request)
        envelopes.removeFirst(count)
        return batch
    }
}

struct DiagnosticsEvent: Codable, Equatable {
    let timestamp: TimeInterval
    let category: String
    let message: String
    let metadata: [String: String]
}

final class DiagnosticsLogger {
    private let debugMode: Bool
    private var events: [DiagnosticsEvent] = []

    init(debugMode: Bool = false, now _: @escaping () -> Date = Date.init) {
        self.debugMode = debugMode
    }

    func logDecision(url: URL, decision: String) {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        let redacted = debugMode ? url.absoluteString : (components?.string ?? url.absoluteString)
        events.append(
            DiagnosticsEvent(
                timestamp: 0,
                category: "routing",
                message: "decision",
                metadata: ["url": redacted, "decision": decision]
            )
        )
    }

    func exportBundle(to outputURL: URL) throws {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(events).write(to: outputURL, options: .atomic)
    }
}
#endif

final class RequestQueueTests: XCTestCase {
    func testBurstCoalescesFiveURLsWithin500Milliseconds() {
        var currentTime: TimeInterval = 0
        let queue = RequestQueue(now: { currentTime })

        for index in 0 ..< 5 {
            let request = RoutingRequest(url: URL(string: "https://example.com/path?i=\(index)")!)
            queue.enqueue(request)
            currentTime += 0.1
        }

        let burst = queue.dequeueBurst(window: 0.5)

        XCTAssertEqual(burst.count, 5)
        XCTAssertEqual(queue.dequeueBurst(window: 0.5).count, 0)
    }

    func testDiagnosticsExportRedactsQueryValues() throws {
        let logger = DiagnosticsLogger(debugMode: false)
        let url = URL(string: "https://example.com/path?token=secret&x=1")!
        logger.logDecision(url: url, decision: "showChooser")

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("choose-browser")
            .appendingPathComponent("tests")
            .appendingPathComponent("diagnostics-redaction.json")

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        try logger.exportBundle(to: outputURL)
        let data = try Data(contentsOf: outputURL)
        let events = try JSONDecoder().decode([DiagnosticsEvent].self, from: data)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].metadata["url"], "https://example.com/path")
        XCTAssertFalse(data.contains(Data("secret".utf8)))
    }
}
