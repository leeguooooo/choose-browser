import Combine
import Foundation

struct ChooserTarget: Identifiable, Equatable {
    let id: String
    let displayName: String
    let applicationURL: URL
}

final class ChooserViewModel: ObservableObject {
    @Published var searchQuery: String = "" {
        didSet {
            clampSelection()
        }
    }

    private let allTargets: [ChooserTarget]
    private let onOpenOnce: (ChooserTarget) -> Void
    private let onRememberForHost: (ChooserTarget) -> Void
    private let onCancel: () -> Void
    private let onOpenFallback: () -> Void

    private(set) var selectedIndex: Int = 0

    init(
        targets: [ChooserTarget],
        onOpenOnce: @escaping (ChooserTarget) -> Void,
        onRememberForHost: @escaping (ChooserTarget) -> Void,
        onCancel: @escaping () -> Void,
        onOpenFallback: @escaping () -> Void
    ) {
        self.allTargets = targets
        self.onOpenOnce = onOpenOnce
        self.onRememberForHost = onRememberForHost
        self.onCancel = onCancel
        self.onOpenFallback = onOpenFallback
    }

    var filteredTargets: [ChooserTarget] {
        guard !searchQuery.isEmpty else {
            return allTargets
        }

        let query = searchQuery.lowercased()

        return allTargets.filter { target in
            target.displayName.lowercased().contains(query) || target.id.lowercased().contains(query)
        }
    }

    var hasTargets: Bool {
        !filteredTargets.isEmpty
    }

    var selectedTarget: ChooserTarget? {
        let targets = filteredTargets
        guard !targets.isEmpty else {
            return nil
        }

        let index = max(0, min(selectedIndex, targets.count - 1))

        return targets[index]
    }

    func isSelected(index: Int) -> Bool {
        index == selectedIndex
    }

    func moveSelection(delta: Int) {
        let targets = filteredTargets
        guard !targets.isEmpty else {
            selectedIndex = 0
            return
        }

        let nextIndex = max(0, min(selectedIndex + delta, targets.count - 1))
        selectedIndex = nextIndex
        objectWillChange.send()
    }

    func select(index: Int) {
        let targets = filteredTargets
        guard targets.indices.contains(index) else {
            return
        }

        selectedIndex = index
        objectWillChange.send()
    }

    func triggerOpenOnce() {
        guard let target = selectedTarget else {
            onOpenFallback()
            return
        }

        onOpenOnce(target)
    }

    func triggerRememberForHost() {
        guard let target = selectedTarget else {
            onOpenFallback()
            return
        }

        onRememberForHost(target)
    }

    func triggerCancel() {
        onCancel()
    }

    func triggerOpenFallback() {
        onOpenFallback()
    }

    private func clampSelection() {
        let count = filteredTargets.count

        if count == 0 {
            selectedIndex = 0
        } else if selectedIndex >= count {
            selectedIndex = count - 1
        }
    }
}
