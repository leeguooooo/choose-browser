import SwiftUI

struct RootView: View {
    @ObservedObject var appModel: ChooseBrowserAppDelegate.ChooseBrowserAppModel
    private let placeholderURL = URL(string: "https://example.com")!

    var body: some View {
        if let session = appModel.chooserSession {
            ChooserView(url: session.requestURLs.first ?? placeholderURL, viewModel: session.viewModel)
                .padding(8)
                .frame(minWidth: 360, minHeight: 260)
        } else if appModel.showAdvancedPanel {
            advancedDashboardView
        } else {
            controlPanelView
        }
    }

    private var controlPanelView: some View {
        let lastActionText = "Last action: \(appModel.lastActionMessage)"

        return VStack(alignment: .leading, spacing: 14) {
            Text("ChooseBrowser")
                .font(.title2)
                .fontWeight(.semibold)

            DefaultBrowserStatusView(
                snapshot: appModel.defaultHandlerSnapshot,
                onOpenSystemSettings: {
                    appModel.openSystemDefaultBrowserSettings()
                },
                onSetAsDefaultBrowser: {
                    appModel.setAsDefaultBrowser()
                },
                onStart: nil
            )

            Text(lastActionText)
                .font(.caption)
                .foregroundColor(.secondary)
                .accessibilityLabel(lastActionText)
                .accessibilityIdentifier(AccessibilityIdentifiers.chooserLastActionLabel)
        }
        .padding(16)
        .frame(minWidth: 460, minHeight: 220)
    }

    private var advancedDashboardView: some View {
        let lastActionText = "Last action: \(appModel.lastActionMessage)"

        return VStack(alignment: .leading, spacing: 14) {
            Text("ChooseBrowser")
                .font(.title2)
                .fontWeight(.semibold)

            DefaultBrowserStatusView(
                snapshot: appModel.defaultHandlerSnapshot,
                onOpenSystemSettings: {
                    appModel.openSystemDefaultBrowserSettings()
                },
                onSetAsDefaultBrowser: {
                    appModel.setAsDefaultBrowser()
                },
                onStart: {
                    appModel.startFromOnboarding()
                }
            )

            SettingsView(
                candidates: appModel.settingsCandidates,
                fallbackBundleIdentifier: appModel.fallbackBundleIdentifier,
                hiddenBundleIdentifiers: appModel.hiddenBundleIdentifiers,
                onSelectFallback: { bundleIdentifier in
                    appModel.selectFallbackBundleIdentifier(bundleIdentifier)
                },
                onToggleHidden: { bundleIdentifier, isHidden in
                    appModel.setHidden(bundleIdentifier: bundleIdentifier, isHidden: isHidden)
                },
                onRunFallbackProbe: {
                    appModel.runFallbackProbe()
                },
                onSetAsDefaultBrowser: {
                    appModel.setAsDefaultBrowser()
                },
                isDefaultBrowserSet: appModel.defaultHandlerSnapshot.status == .configured
            )

            RuleEditorAdvancedView(
                domain: $appModel.advancedRuleDomain,
                path: $appModel.advancedRulePath,
                dispatchMode: appModel.advancedRuleDispatchMode,
                savedRules: appModel.advancedRuleSummaries,
                validationMessage: appModel.advancedRuleValidationMessage,
                onSelectDispatchMode: { mode in
                    appModel.selectAdvancedRuleDispatchMode(mode)
                },
                onSave: {
                    appModel.saveAdvancedRuleDraft()
                }
            )

            ProfileWorkspaceChooserView(
                profiles: appModel.availableProfiles,
                workspaces: appModel.availableWorkspaces,
                selectedProfile: appModel.selectedProfile,
                selectedWorkspace: appModel.selectedWorkspace,
                onSelectProfile: { profile in
                    appModel.selectProfile(profile)
                },
                onSelectWorkspace: { workspace in
                    appModel.selectWorkspace(workspace)
                }
            )

            Text(lastActionText)
                .font(.body)
                .accessibilityLabel(lastActionText)
                .accessibilityIdentifier(AccessibilityIdentifiers.chooserLastActionLabel)

            Text("Waiting for incoming URL routing requests.")
                .font(.body)
                .foregroundColor(.secondary)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 700, minHeight: 760)
    }
}
