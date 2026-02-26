import Foundation

#if canImport(XCTest)
import XCTest
#else
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
struct RoutingTarget: Equatable {
    let bundleIdentifier: String
    let displayName: String
}

enum RouteFallbackReason: Equatable {
    case timeout
    case invalidURL
}

enum RouteDecision: Equatable {
    case showChooser
    case route(RoutingTarget)
    case fallback(RouteFallbackReason)
}

protocol RuleStoring {
    func preferredTarget(forHost host: String) -> RoutingTarget?
}

struct RoutingEngine {
    init(ruleStore: RuleStoring, decisionTimeout: TimeInterval = 1.5, now: @escaping () -> TimeInterval = { 0 }) {}

    func normalize(_ url: URL) -> (originalURL: URL, normalizedHost: String)? { nil }

    func decide(for url: URL) -> RouteDecision { .showChooser }
}
#endif

final class RoutingEngineTests: XCTestCase {
    private final class RuleStoreStub: RuleStoring {
        private let lookup: (String) -> RoutingTarget?

        init(lookup: @escaping (String) -> RoutingTarget?) {
            self.lookup = lookup
        }

        func preferredTarget(forHost host: String) -> RoutingTarget? {
            lookup(host)
        }
    }

    private func sampleTarget() -> RoutingTarget {
        RoutingTarget(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
    }

    func testNormalizesUppercaseHostToLowercase() {
        let engine = RoutingEngine(ruleStore: RuleStoreStub(lookup: { _ in nil }))
        let url = URL(string: "https://EXAMPLE.com/path")!

        let normalized = engine.normalize(url)

        XCTAssertEqual(normalized?.normalizedHost, "example.com")
    }

    func testNormalizesHostWhenPortIsPresent() {
        let engine = RoutingEngine(ruleStore: RuleStoreStub(lookup: { _ in nil }))
        let url = URL(string: "https://example.com:443/path")!

        let normalized = engine.normalize(url)

        XCTAssertEqual(normalized?.normalizedHost, "example.com")
    }

    func testNormalizesLocalhost() {
        let engine = RoutingEngine(ruleStore: RuleStoreStub(lookup: { _ in nil }))
        let url = URL(string: "http://localhost:3000/path")!

        let normalized = engine.normalize(url)

        XCTAssertEqual(normalized?.normalizedHost, "localhost")
    }

    func testNormalizesIPv4Host() {
        let engine = RoutingEngine(ruleStore: RuleStoreStub(lookup: { _ in nil }))
        let url = URL(string: "http://127.0.0.1:8080/path")!

        let normalized = engine.normalize(url)

        XCTAssertEqual(normalized?.normalizedHost, "127.0.0.1")
    }

    func testKeepsPunycodeHostUntouched() {
        let engine = RoutingEngine(ruleStore: RuleStoreStub(lookup: { _ in nil }))
        let url = URL(string: "https://xn--bcher-kva.example/path")!

        let normalized = engine.normalize(url)

        XCTAssertEqual(normalized?.normalizedHost, "xn--bcher-kva.example")
    }

    func testRoutesUsingExactNormalizedHostRule() {
        let target = sampleTarget()
        let store = RuleStoreStub(lookup: { host in
            host == "example.com" ? target : nil
        })
        let engine = RoutingEngine(ruleStore: store)
        let url = URL(string: "https://EXAMPLE.com/path?x=1#y")!

        let decision = engine.decide(for: url)

        XCTAssertEqual(decision, .route(target))
        XCTAssertEqual(url.absoluteString, "https://EXAMPLE.com/path?x=1#y")
    }

    func testShowsChooserWhenNoExactHostRuleMatches() {
        let engine = RoutingEngine(ruleStore: RuleStoreStub(lookup: { _ in nil }))
        let url = URL(string: "https://example.com")!

        let decision = engine.decide(for: url)

        XCTAssertEqual(decision, .showChooser)
    }

    func testFallbackWhenRuleLookupExceedsBudget() {
        var currentTime: TimeInterval = 100
        let store = RuleStoreStub(lookup: { host in
            currentTime += 1.6
            return host == "example.com" ? RoutingTarget(bundleIdentifier: "com.apple.Safari", displayName: "Safari") : nil
        })
        let engine = RoutingEngine(
            ruleStore: store,
            decisionTimeout: 1.5,
            now: { currentTime }
        )
        let url = URL(string: "https://example.com")!

        let decision = engine.decide(for: url)

        XCTAssertEqual(decision, .fallback(.timeout))
    }
}
