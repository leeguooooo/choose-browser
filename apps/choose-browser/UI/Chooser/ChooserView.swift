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

struct ChooserView: View {
    let url: URL
    @ObservedObject var viewModel: ChooserViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.hasTargets {
                List {
                    ForEach(Array(viewModel.filteredTargets.enumerated()), id: \.element.id) { index, target in
                        Button {
                            viewModel.select(index: index)
                            viewModel.triggerOpenOnce()
                        } label: {
                            HStack(spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.body.monospacedDigit())
                                    .foregroundColor(.secondary)

                                Text(target.displayName)
                                    .font(.body)
                                    .foregroundColor(.primary)

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(viewModel.isSelected(index: index) ? Color.accentColor.opacity(0.16) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(AccessibilityIdentifiers.chooserAppRow(index))
                    }
                }
                .listStyle(.plain)
                .frame(height: 220, alignment: .top)
            } else {
                Text("No available browsers installed.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
                    .accessibilityIdentifier(AccessibilityIdentifiers.chooserEmptyStateText)
            }
        }
        .padding(12)
        .frame(width: 360)
        .background(Color(NSColor.windowBackgroundColor))
        .accessibilityIdentifier(AccessibilityIdentifiers.chooserWindow)
        .onChooserKeyDown { event in
            switch event.keyCode {
            case 125:
                viewModel.moveSelection(delta: 1)
                return true
            case 126:
                viewModel.moveSelection(delta: -1)
                return true
            case 36:
                viewModel.triggerOpenOnce()
                return true
            case 53:
                viewModel.triggerCancel()
                return true
            default:
                return false
            }
        }
    }
}
