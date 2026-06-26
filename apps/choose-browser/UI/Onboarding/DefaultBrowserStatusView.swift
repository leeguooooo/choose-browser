import SwiftUI

struct DefaultBrowserStatusView: View {
    let snapshot: DefaultHandlerSnapshot
    let onOpenSystemSettings: () -> Void
    let onSetAsDefaultBrowser: () -> Void
    let onStart: (() -> Void)?

    var body: some View {
        let isConfigured = snapshot.status == .configured
        let descriptionText = isConfigured
            ? "ChooseBrowser is your default browser. Links will open with the picker."
            : "Set ChooseBrowser as your default browser so every link opens with the picker."
        let setDefaultButtonTitle = isConfigured ? "Default Configured" : "Set as Default"

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: statusSymbol)
                    .font(.title3)
                    .foregroundStyle(statusColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Default Browser")
                        .font(.headline)

                    Text(descriptionText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(descriptionText)
                }

                Spacer(minLength: 8)

                Text(snapshot.status.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor)
                    .accessibilityLabel(snapshot.status.rawValue)
                    .accessibilityIdentifier(AccessibilityIdentifiers.onboardingStatusBadge)
            }

            HStack(spacing: 10) {
                Button {
                    onSetAsDefaultBrowser()
                } label: {
                    Label(setDefaultButtonTitle, systemImage: isConfigured ? "checkmark.circle.fill" : "star.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isConfigured)
                .accessibilityIdentifier(AccessibilityIdentifiers.settingsSetAsDefaultButton)

                Button {
                    onOpenSystemSettings()
                } label: {
                    Label("System Settings", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier(AccessibilityIdentifiers.onboardingOpenSettingsButton)

                if let onStart {
                    Button {
                        onStart()
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(AccessibilityIdentifiers.onboardingStartButton)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(statusColor.opacity(0.25), lineWidth: 1)
        )
    }

    private var statusSymbol: String {
        switch snapshot.status {
        case .configured:
            return "checkmark.seal.fill"
        case .partial:
            return "exclamationmark.triangle.fill"
        case .notConfigured:
            return "xmark.seal.fill"
        }
    }

    private var statusColor: Color {
        switch snapshot.status {
        case .configured:
            return .green
        case .partial:
            return .orange
        case .notConfigured:
            return .red
        }
    }
}
