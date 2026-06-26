import SwiftUI

struct RootView: View {
    @ObservedObject var appModel: ChooseBrowserAppDelegate.ChooseBrowserAppModel
    private let placeholderURL = URL(string: "https://example.com")!

    static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return "v\(version)"
    }

    var body: some View {
        Group {
            if let session = appModel.chooserSession {
                ChooserView(url: session.requestURLs.first ?? placeholderURL, viewModel: session.viewModel)
            } else if appModel.showAdvancedPanel {
                advancedDashboardView
            } else {
                controlPanelView
            }
        }
        .confirmationDialog(
            "New Version Available",
            isPresented: Binding(
                // Never let the update prompt cover the chooser — choosing a
                // browser is the primary action. The prompt waits until no
                // chooser session is active (i.e. the idle/settings surface).
                get: { appModel.updatePrompt != nil && appModel.chooserSession == nil },
                set: { isPresented in
                    if !isPresented {
                        appModel.dismissUpdatePrompt()
                    }
                }
            ),
            presenting: appModel.updatePrompt
        ) { _ in
            Button("Download") {
                appModel.openCurrentUpdateRelease()
            }

            Button("Ignore This Version", role: .destructive) {
                appModel.ignoreCurrentUpdateVersion()
            }

            Button("Later", role: .cancel) {
                appModel.dismissUpdatePrompt()
            }
        } message: { prompt in
            Text("v\(prompt.version) is available.")
        }
    }

    private var controlPanelView: some View {
        let lastActionText = "Last action: \(appModel.lastActionMessage)"

        return VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 52, height: 52)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("ChooseBrowser")
                        .font(.title.weight(.semibold))

                    Text("\(Self.appVersion) · Pick a browser for every link")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

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
        .padding(24)
        .frame(minWidth: 480, minHeight: 240)
        .background(.regularMaterial)
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
                updateStatusMessage: appModel.updateStatusMessage,
                onSelectFallback: { bundleIdentifier in
                    appModel.selectFallbackBundleIdentifier(bundleIdentifier)
                },
                onToggleHidden: { bundleIdentifier, isHidden in
                    appModel.setHidden(bundleIdentifier: bundleIdentifier, isHidden: isHidden)
                },
                onRunFallbackProbe: {
                    appModel.runFallbackProbe()
                },
                onCheckForUpdates: {
                    appModel.checkForUpdates(manual: true)
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
