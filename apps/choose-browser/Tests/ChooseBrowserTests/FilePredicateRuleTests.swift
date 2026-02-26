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
func XCTAssertNil(
    _ value: Any?,
    file: StaticString = #filePath,
    line: UInt = #line
) {}
#endif

#if canImport(ChooseBrowser)
@testable import ChooseBrowser
#else
struct InboundSourceContextV2: Equatable {
    let sourceApplicationBundleIdentifier: String?
    let sourceTrigger: String
    let isUserInitiated: Bool

    init(
        sourceApplicationBundleIdentifier: String? = nil,
        sourceTrigger: String = "unknown",
        isUserInitiated: Bool = true
    ) {
        self.sourceApplicationBundleIdentifier = sourceApplicationBundleIdentifier
        self.sourceTrigger = sourceTrigger
        self.isUserInitiated = isUserInitiated
    }
}

struct InboundRequestV2: Equatable {
    let objectType: String
    let url: URL
    let sourceContext: InboundSourceContextV2
}

struct RuleMatchV2: Equatable {
    let scheme: String?
    let domain: String?
    let path: String?
    let query: String?
    let source: String?
    let modifierKeys: [String]?
    let focusHint: String?
    let context: String?
    let mimeTypes: [String]?
    let extensions: [String]?
}

enum RuleActionV2: Equatable {
    case alwaysOpenIn(bundleIdentifier: String)
    case alwaysAsk
}

struct RuleRecordV2: Equatable {
    let ruleId: String
    let priority: Int
    let createdAt: Int
    let host: String?
    let match: RuleMatchV2
    let action: RuleActionV2
    let targetReference: Any?
}

struct RuleEvaluationContextV2: Equatable {
    let modifierKeys: [String]
    let focusHint: String?
    let context: String?
    let mimeType: String?
    let pathExtension: String?
}

struct ExecutionPlanV2: Equatable {
    let preferredTargetBundleIdentifier: String?
}

struct RuleEngineV2 {
    func evaluate(
        for _: InboundRequestV2,
        rules _: [RuleRecordV2],
        context _: RuleEvaluationContextV2 = RuleEvaluationContextV2(modifierKeys: [], focusHint: nil, context: nil, mimeType: nil, pathExtension: nil)
    ) -> ExecutionPlanV2 {
        fatalError("ChooseBrowser module unavailable")
    }
}
#endif

final class FilePredicateRuleTests: XCTestCase {
    private func makeFileRequest(urlString: String) -> InboundRequestV2 {
        InboundRequestV2(
            objectType: .file,
            url: URL(string: urlString)!,
            sourceContext: InboundSourceContextV2()
        )
    }

    private func makeLinkRequest(urlString: String) -> InboundRequestV2 {
        InboundRequestV2(
            objectType: .link,
            url: URL(string: urlString)!,
            sourceContext: InboundSourceContextV2()
        )
    }

    private func makeRule(
        id: String,
        priority: Int,
        createdAt: Int,
        match: RuleMatchV2,
        bundleIdentifier: String
    ) -> RuleRecordV2 {
        RuleRecordV2(
            ruleId: id,
            priority: priority,
            createdAt: createdAt,
            host: nil,
            match: match,
            action: .alwaysOpenIn(bundleIdentifier: bundleIdentifier),
            targetReference: nil
        )
    }

    func testMatchesFileObjectByMimeAndExtension() {
        let engine = RuleEngineV2()
        let request = makeFileRequest(urlString: "file:///tmp/report.PDF")

        let rule = makeRule(
            id: "file-pdf",
            priority: 100,
            createdAt: 1,
            match: RuleMatchV2(
                scheme: nil,
                domain: nil,
                path: nil,
                query: nil,
                source: nil,
                modifierKeys: nil,
                focusHint: nil,
                context: nil,
                mimeTypes: ["application/pdf"],
                extensions: ["pdf"]
            ),
            bundleIdentifier: "com.example.PDFApp"
        )

        let plan = engine.evaluate(for: request, rules: [rule])
        XCTAssertEqual(plan.preferredTargetBundleIdentifier, "com.example.PDFApp")
    }

    func testPrefersFilePredicateRuleWhenBothURLAndFileRulesMatch() {
        let engine = RuleEngineV2()
        let request = makeFileRequest(urlString: "https://example.com/docs/report.pdf")

        let urlRule = makeRule(
            id: "url-only",
            priority: 50,
            createdAt: 1,
            match: RuleMatchV2(
                scheme: "https",
                domain: "example.com",
                path: "/docs/*",
                query: nil,
                source: nil,
                modifierKeys: nil,
                focusHint: nil,
                context: nil,
                mimeTypes: nil,
                extensions: nil
            ),
            bundleIdentifier: "com.example.URLBrowser"
        )

        let fileAwareRule = makeRule(
            id: "file-aware",
            priority: 50,
            createdAt: 2,
            match: RuleMatchV2(
                scheme: "https",
                domain: "example.com",
                path: "/docs/*",
                query: nil,
                source: nil,
                modifierKeys: nil,
                focusHint: nil,
                context: nil,
                mimeTypes: ["application/pdf"],
                extensions: ["pdf"]
            ),
            bundleIdentifier: "com.example.PDFBrowser"
        )

        let plan = engine.evaluate(for: request, rules: [urlRule, fileAwareRule])
        XCTAssertEqual(plan.preferredTargetBundleIdentifier, "com.example.PDFBrowser")
    }

    func testStrictMimeMismatchFallsBackToChooserDeterministically() {
        let engine = RuleEngineV2()
        let request = makeFileRequest(urlString: "file:///tmp/report.pdf")

        let strictRule = makeRule(
            id: "strict-pdf",
            priority: 100,
            createdAt: 1,
            match: RuleMatchV2(
                scheme: nil,
                domain: nil,
                path: nil,
                query: nil,
                source: nil,
                modifierKeys: nil,
                focusHint: nil,
                context: nil,
                mimeTypes: ["application/pdf"],
                extensions: ["pdf"]
            ),
            bundleIdentifier: "com.example.StrictPDFApp"
        )

        let plan = engine.evaluate(
            for: request,
            rules: [strictRule],
            context: RuleEvaluationContextV2(
                modifierKeys: [],
                focusHint: nil,
                context: nil,
                mimeType: "image/png",
                pathExtension: "pdf"
            )
        )

        XCTAssertNil(plan.preferredTargetBundleIdentifier)
    }

    func testMatchesFileBackedLinkByExtensionWhenContextNotProvided() {
        let engine = RuleEngineV2()
        let request = makeLinkRequest(urlString: "https://example.com/assets/manual.PDF")

        let extensionRule = makeRule(
            id: "file-backed-link",
            priority: 30,
            createdAt: 1,
            match: RuleMatchV2(
                scheme: "https",
                domain: "example.com",
                path: "/assets/*",
                query: nil,
                source: nil,
                modifierKeys: nil,
                focusHint: nil,
                context: nil,
                mimeTypes: nil,
                extensions: ["pdf"]
            ),
            bundleIdentifier: "com.example.FileViewer"
        )

        let plan = engine.evaluate(for: request, rules: [extensionRule])
        XCTAssertEqual(plan.preferredTargetBundleIdentifier, "com.example.FileViewer")
    }
}
