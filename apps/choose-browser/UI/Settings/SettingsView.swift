import SwiftUI

struct SettingsView: View {
    let candidates: [ExecutionTarget]
    let fallbackBundleIdentifier: String?
    let hiddenBundleIdentifiers: Set<String>
    let updateStatusMessage: String?
    let onSelectFallback: (String?) -> Void
    let onToggleHidden: (String, Bool) -> Void
    let onRunFallbackProbe: () -> Void
    let onCheckForUpdates: () -> Void
    let onSetAsDefaultBrowser: () -> Void
    let isDefaultBrowserSet: Bool

    var body: some View {
        let fallbackText = "Fallback: \(selectedFallbackDisplayName)"
        let setDefaultButtonTitle = isDefaultBrowserSet ? "Default browser configured" : "Set as default browser"

        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.headline)

            Text(fallbackText)
                .font(.caption)
                .foregroundColor(.secondary)
                .accessibilityLabel(fallbackText)
                .accessibilityIdentifier(AccessibilityIdentifiers.settingsSelectedFallbackLabel)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button("No fallback") {
                        onSelectFallback(nil)
                    }

                    ForEach(candidates, id: \.bundleIdentifier) { target in
                        Button(target.displayName) {
                            onSelectFallback(target.bundleIdentifier)
                        }
                        .accessibilityIdentifier(AccessibilityIdentifiers.settingsFallbackOption(target.bundleIdentifier))
                    }
                }
            }

            if !candidates.isEmpty {
                Divider()

                Text("Hidden apps")
                    .font(.subheadline)

                ForEach(candidates, id: \.bundleIdentifier) { target in
                    Toggle(
                        isOn: Binding(
                            get: {
                                hiddenBundleIdentifiers.contains(target.bundleIdentifier)
                            },
                            set: { isHidden in
                                onToggleHidden(target.bundleIdentifier, isHidden)
                            }
                        )
                    ) {
                        Text(target.displayName)
                            .font(.caption)
                    }
                    .toggleStyle(.switch)
                    .accessibilityIdentifier(AccessibilityIdentifiers.settingsHiddenToggle(target.bundleIdentifier))
                }
            }

            HStack(spacing: 10) {
                Button("Run Fallback Probe") {
                    onRunFallbackProbe()
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.settingsRunFallbackProbeButton)
                .disabled(candidates.isEmpty)

                Button("Check for Updates") {
                    onCheckForUpdates()
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.settingsCheckForUpdatesButton)

                Button(setDefaultButtonTitle) {
                    onSetAsDefaultBrowser()
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.settingsSetAsDefaultButton)
                .disabled(isDefaultBrowserSet)

                Spacer(minLength: 0)
            }

            if let updateStatusMessage, !updateStatusMessage.isEmpty {
                Text(updateStatusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var selectedFallbackDisplayName: String {
        guard let fallbackBundleIdentifier else {
            return "none"
        }

        if let target = candidates.first(where: { $0.bundleIdentifier == fallbackBundleIdentifier }) {
            return target.displayName
        }

        return fallbackBundleIdentifier
    }
}
