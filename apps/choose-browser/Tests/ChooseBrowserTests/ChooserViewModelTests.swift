import Foundation
import XCTest

@testable import ChooseBrowser

final class ChooserViewModelTests: XCTestCase {
    private func makeTarget(_ id: String, _ name: String) -> ChooserTarget {
        ChooserTarget(
            id: id,
            displayName: name,
            applicationURL: URL(fileURLWithPath: "/Applications/\(name).app")
        )
    }

    func testMoveTargetPersistsNewOrder() {
        let alpha = makeTarget("com.browser.alpha", "Alpha")
        let beta = makeTarget("com.browser.beta", "Beta")
        let gamma = makeTarget("com.browser.gamma", "Gamma")
        var capturedOrders: [[String]] = []
        let viewModel = ChooserViewModel(
            targets: [alpha, beta, gamma],
            onOpenOnce: { _ in },
            onRememberForHost: { _ in },
            onCancel: {},
            onOpenFallback: {},
            onOrderChanged: { targets in
                capturedOrders.append(targets.map(\.id))
            }
        )

        viewModel.moveTarget(draggedTargetID: gamma.id, over: alpha.id)

        XCTAssertEqual(viewModel.filteredTargets.map(\.id), [gamma.id, alpha.id, beta.id])
        XCTAssertEqual(capturedOrders.last, [gamma.id, alpha.id, beta.id])
    }

    func testMoveTargetIgnoredWhileSearching() {
        let alpha = makeTarget("com.browser.alpha", "Alpha")
        let beta = makeTarget("com.browser.beta", "Beta")
        let gamma = makeTarget("com.browser.gamma", "Gamma")
        var onOrderChangedCalled = false
        let viewModel = ChooserViewModel(
            targets: [alpha, beta, gamma],
            onOpenOnce: { _ in },
            onRememberForHost: { _ in },
            onCancel: {},
            onOpenFallback: {},
            onOrderChanged: { _ in
                onOrderChangedCalled = true
            }
        )

        viewModel.searchQuery = "a"
        viewModel.moveTarget(draggedTargetID: gamma.id, over: alpha.id)

        XCTAssertEqual(viewModel.filteredTargets.map(\.id), [alpha.id, beta.id, gamma.id])
        XCTAssertFalse(onOrderChangedCalled)
    }

    func testMoveTargetDownwardUpdatesOrder() {
        let alpha = makeTarget("com.browser.alpha", "Alpha")
        let beta = makeTarget("com.browser.beta", "Beta")
        let gamma = makeTarget("com.browser.gamma", "Gamma")
        let viewModel = ChooserViewModel(
            targets: [alpha, beta, gamma],
            onOpenOnce: { _ in },
            onRememberForHost: { _ in },
            onCancel: {},
            onOpenFallback: {}
        )

        viewModel.moveTarget(draggedTargetID: alpha.id, over: beta.id)

        XCTAssertEqual(viewModel.filteredTargets.map(\.id), [beta.id, alpha.id, gamma.id])
    }
}
