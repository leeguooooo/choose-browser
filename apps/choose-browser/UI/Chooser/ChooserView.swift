import AppKit
import SwiftUI

private struct KeyDownMonitor: ViewModifier {
    let onKeyDown: (NSEvent) -> Bool
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    onKeyDown(event) ? nil : event
                }
            }
            .onDisappear {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
            }
    }
}

private extension View {
    func onChooserKeyDown(_ handler: @escaping (NSEvent) -> Bool) -> some View {
        modifier(KeyDownMonitor(onKeyDown: handler))
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct ChooserView: View {
    let url: URL
    @ObservedObject var viewModel: ChooserViewModel
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // URL Header
            VStack(alignment: .leading, spacing: 2) {
                Text("Open with...")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search browsers...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        viewModel.triggerOpenOnce()
                    }
            }
            .padding(8)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 16)

            // Targets List
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 4) {
                        if viewModel.hasTargets {
                            ForEach(Array(viewModel.filteredTargets.enumerated()), id: \.element.id) { index, target in
                                targetRow(for: target, at: index)
                                    .id(index)
                            }
                        } else {
                            Text("No available browsers installed.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: viewModel.selectedIndex) { newIndex in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
            .frame(height: 320)

            Divider()

            // Footer
            HStack {
                shortcutHint(key: "↵", label: "Open")
                shortcutHint(key: "⌥↵", label: "Always")
                Spacer()
                shortcutHint(key: "⎋", label: "Cancel")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.03))
        }
        .frame(width: 420)
        .background(VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow))
        .onAppear {
            isSearchFieldFocused = true
        }
        .onChooserKeyDown { event in
            switch event.keyCode {
            case 125: // Down
                viewModel.moveSelection(delta: 1)
                return true
            case 126: // Up
                viewModel.moveSelection(delta: -1)
                return true
            case 36: // Enter
                if event.modifierFlags.contains(.option) {
                    viewModel.triggerRememberForHost()
                } else {
                    viewModel.triggerOpenOnce()
                }
                return true
            case 53: // Esc
                viewModel.triggerCancel()
                return true
            case 18...21, 23, 22, 26, 28, 25: // 1-9
                let number: Int
                switch event.keyCode {
                case 18: number = 1
                case 19: number = 2
                case 20: number = 3
                case 21: number = 4
                case 23: number = 5
                case 22: number = 6
                case 26: number = 7
                case 28: number = 8
                case 25: number = 9
                default: number = 0
                }
                if number > 0 && number <= viewModel.filteredTargets.count {
                    viewModel.select(index: number - 1)
                    if event.modifierFlags.contains(.option) {
                        viewModel.triggerRememberForHost()
                    } else {
                        viewModel.triggerOpenOnce()
                    }
                    return true
                }
                return false
            default:
                return false
            }
        }
    }

    @ViewBuilder
    private func targetRow(for target: ChooserTarget, at index: Int) -> some View {
        let isSelected = viewModel.isSelected(index: index)
        
        Button {
            viewModel.select(index: index)
            viewModel.triggerOpenOnce()
        } label: {
            HStack(spacing: 12) {
                AppIconView(url: target.applicationURL, size: 24)
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(target.displayName)
                        .font(.body)
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    if isSelected {
                        Text(target.id)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                Spacer()
                
                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isSelected ? Color.white.opacity(0.2) : Color.primary.opacity(0.05))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func shortcutHint(key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.1)))
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
