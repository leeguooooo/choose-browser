import SwiftUI

struct DefaultBrowserStatusView: View {
    let snapshot: DefaultHandlerSnapshot
    let onOpenSystemSettings: () -> Void
    let onStart: () -> Void

    var body: some View {
        let statusText = snapshot.status.rawValue
        let httpHandlerText = "http: \(snapshot.httpHandlerBundleIdentifier ?? "unknown")"
        let httpsHandlerText = "https: \(snapshot.httpsHandlerBundleIdentifier ?? "unknown")"

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Default Browser")
                    .font(.headline)

                Spacer()

                Text(statusText)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.2))
                    .foregroundColor(statusColor)
                    .clipShape(Capsule())
                    .accessibilityLabel(statusText)
                    .accessibilityIdentifier(AccessibilityIdentifiers.onboardingStatusBadge)
            }

            Text(httpHandlerText)
                .font(.caption)
                .foregroundColor(.secondary)
                .accessibilityLabel(httpHandlerText)
                .accessibilityIdentifier(AccessibilityIdentifiers.onboardingHTTPHandlerLabel)

            Text(httpsHandlerText)
                .font(.caption)
                .foregroundColor(.secondary)
                .accessibilityLabel(httpsHandlerText)
                .accessibilityIdentifier(AccessibilityIdentifiers.onboardingHTTPSHandlerLabel)

            HStack(spacing: 10) {
                Button("Open macOS Browser Settings") {
                    onOpenSystemSettings()
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.onboardingOpenSettingsButton)

                Button("Start") {
                    onStart()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(AccessibilityIdentifiers.onboardingStartButton)

                Spacer(minLength: 0)
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
