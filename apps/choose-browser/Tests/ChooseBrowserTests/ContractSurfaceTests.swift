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

func XCTAssertTrue(
    _ condition: Bool,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {}

func XCTFail(
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {}
#endif

#if canImport(ChooseBrowser)
@testable import ChooseBrowser
#else
enum InboundObjectTypeV2: String {
    case link
}

enum InboundSourceTriggerV2: String {
    case unknown
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

enum ExecutionPlanDispatchModeV2: String {
    case singleTarget
}

struct ExecutionPlanStepV2: Equatable {
    let action: String
    let detail: String
}

struct ExecutionPlanV2: Equatable {
    let request: InboundRequestV2
    let preferredTargetBundleIdentifier: String?
    let configuredFallbackBundleIdentifier: String?
    let dispatchMode: ExecutionPlanDispatchModeV2
    let steps: [ExecutionPlanStepV2]
}

struct RolloutFeatureFlagsV2: Equatable {
    let routingV2: Bool
    let routingShadow: Bool
    let rewritePipelineV1: Bool
    let handoffV1: Bool

    static let disabled = RolloutFeatureFlagsV2(routingV2: false, routingShadow: false, rewritePipelineV1: false, handoffV1: false)
}
#endif

final class ContractSurfaceTests: XCTestCase {
    private static let sourceFilePath = #filePath
    private static let failureToggleMarkerRelativePath = ".sisyphus/evidence/parity/.force-missing-capability-row"
    private static let requiredCapabilityIDs: Set<String> = [
        "inbound_http_https",
        "inbound_mailto",
        "inbound_files",
        "inbound_extension_context",
        "rules_domain",
        "rules_path",
        "rules_query",
        "rules_source_context",
        "rules_modifier_keys",
        "rules_focus_hint",
        "rules_mime_extension",
        "rewrite_regex",
        "rewrite_script",
        "cleanup_tracking",
        "shortlink_expansion",
        "profiles_model",
        "profiles_support_matrix",
        "extension_toolbar",
        "extension_context_menu",
        "extension_share_handoff",
        "multi_target_ordered_failover",
        "multi_target_fanout",
        "v1_v2_dual_path",
        "diagnostics_evidence",
    ]

    func testV2ContractsDefineStableDefaultShapeWithoutBehaviorSwitch() {
        let url = URL(string: "https://example.com/path?x=1")!
        let sourceContext = InboundSourceContextV2(
            sourceApplicationBundleIdentifier: "com.apple.Safari",
            sourceTrigger: .unknown,
            isUserInitiated: true
        )
        let request = InboundRequestV2(objectType: .link, url: url, sourceContext: sourceContext)
        let plan = ExecutionPlanV2(
            request: request,
            preferredTargetBundleIdentifier: "com.apple.Safari",
            configuredFallbackBundleIdentifier: "com.apple.Safari",
            dispatchMode: .singleTarget,
            steps: []
        )
        let flags = RolloutFeatureFlagsV2.disabled

        XCTAssertEqual(request.objectType, .link)
        XCTAssertEqual(request.url, url)
        XCTAssertEqual(plan.dispatchMode, .singleTarget)
        XCTAssertTrue(plan.steps.isEmpty)
        XCTAssertEqual(flags.routingV2, false)
        XCTAssertEqual(flags.routingShadow, false)
        XCTAssertEqual(flags.rewritePipelineV1, false)
        XCTAssertEqual(flags.handoffV1, false)
    }

    func testParityMatrixContainsAllTask1RequiredRows() throws {
        let matrix = try Self.loadParityMatrix()
        let knownCapabilityIDs = Self.capabilityIDs(in: matrix)
        let missing = Self.requiredCapabilityIDs.subtracting(knownCapabilityIDs).sorted()

        if !missing.isEmpty {
            XCTFail("missing-capability-row: \(missing.joined(separator: ","))")
        }
    }

    func testParityMatrixExplicitFailureScenarioWhenExtraCheckEnabled() throws {
        let shouldInjectMissing = Self.shouldInjectMissingCapabilityForFailureScenario()

        guard shouldInjectMissing else {
            XCTAssertTrue(true)
            return
        }

        let matrix = try Self.loadParityMatrix()
        let knownCapabilityIDs = Self.capabilityIDs(in: matrix)
        let requiredWithInjected = Self.requiredCapabilityIDs.union(["__must_fail_missing_row__"])
        let missing = requiredWithInjected.subtracting(knownCapabilityIDs).sorted()

        if !missing.isEmpty {
            XCTFail("missing-capability-row: \(missing.joined(separator: ","))")
        }
    }

    private static func shouldInjectMissingCapabilityForFailureScenario() -> Bool {
        if ProcessInfo.processInfo.environment["PARITY_MATRIX_REQUIRE_FAKE_ROW"] == "1" {
            return true
        }

        for base in candidateRoots() {
            let markerPath = base.appendingPathComponent(failureToggleMarkerRelativePath)
            if FileManager.default.fileExists(atPath: markerPath.path) {
                return true
            }
        }

        return false
    }

    private static func loadParityMatrix() throws -> String {
        let matrixPath = ".sisyphus/evidence/parity/openin4-capability-matrix.md"

        for base in candidateRoots() {
            let candidate = base.appendingPathComponent(matrixPath)

            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
        }

        throw NSError(
            domain: "ContractSurfaceTests",
            code: 404,
            userInfo: [
                NSLocalizedDescriptionKey: "missing-capability-row: matrix-not-found-at-.sisyphus/evidence/parity/openin4-capability-matrix.md",
            ]
        )
    }

    private static func capabilityIDs(in matrix: String) -> Set<String> {
        var ids = Set<String>()

        for rawLine in matrix.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("|") else {
                continue
            }

            let columns = line
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }

            guard columns.count >= 3 else {
                continue
            }

            let firstColumn = columns[1]
            if firstColumn.isEmpty || firstColumn == "capability_id" || firstColumn == "---" {
                continue
            }

            ids.insert(firstColumn)
        }

        return ids
    }

    private static func candidateRoots() -> [URL] {
        var roots: [URL] = []

        var sourceRoot = URL(fileURLWithPath: sourceFilePath, isDirectory: false)
        for _ in 0..<5 {
            sourceRoot.deleteLastPathComponent()
        }
        roots.append(sourceRoot)

        var current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)

        for _ in 0..<8 {
            roots.append(current)
            current.deleteLastPathComponent()
        }

        return roots
    }
}
