import Foundation

enum AccessibilityIdentifiers {
    static let chooserWindow = "chooser.window"
    static let chooserSearchField = "chooser.searchField"
    static let chooserOpenOnceButton = "chooser.openOnceButton"
    static let chooserRememberButton = "chooser.rememberButton"
    static let chooserCancelButton = "chooser.cancelButton"
    static let chooserFallbackButton = "chooser.fallbackButton"
    static let chooserURLPreview = "chooser.urlPreview"
    static let chooserEmptyStateText = "chooser.emptyStateText"
    static let chooserSelectedBundleIDLabel = "chooser.selectedBundleIDLabel"
    static let chooserLastActionLabel = "chooser.lastActionLabel"

    static let onboardingStatusBadge = "onboarding.statusBadge"
    static let onboardingOpenSettingsButton = "onboarding.openSettingsButton"
    static let onboardingStartButton = "onboarding.startButton"
    static let onboardingHTTPHandlerLabel = "onboarding.httpHandlerLabel"
    static let onboardingHTTPSHandlerLabel = "onboarding.httpsHandlerLabel"

    static let settingsSelectedFallbackLabel = "settings.selectedFallbackLabel"
    static let settingsRunFallbackProbeButton = "settings.runFallbackProbeButton"
    static let settingsSetAsDefaultButton = "settings.setAsDefaultButton"
    static let ruleEditorDomainField = "ruleEditor.domainField"
    static let ruleEditorPathField = "ruleEditor.pathField"
    static let ruleEditorDispatchSingle = "ruleEditor.dispatch.single"
    static let ruleEditorDispatchFailover = "ruleEditor.dispatch.failover"
    static let ruleEditorDispatchFanout = "ruleEditor.dispatch.fanout"
    static let ruleEditorDispatchModeLabel = "ruleEditor.dispatchModeLabel"
    static let ruleEditorSaveButton = "ruleEditor.saveButton"
    static let ruleEditorValidationLabel = "ruleEditor.validationLabel"
    static let ruleEditorSavedRulesCountLabel = "ruleEditor.savedRulesCountLabel"
    static let profileWorkspaceSelectedProfileLabel = "profileWorkspace.selectedProfileLabel"
    static let profileWorkspaceSelectedWorkspaceLabel = "profileWorkspace.selectedWorkspaceLabel"

    static func chooserAppRow(_ index: Int) -> String {
        "chooser.appRow.\(index)"
    }

    static func settingsFallbackOption(_ bundleIdentifier: String) -> String {
        "settings.fallbackOption.\(bundleIdentifier)"
    }

    static func settingsHiddenToggle(_ bundleIdentifier: String) -> String {
        "settings.hiddenToggle.\(bundleIdentifier)"
    }

    static func ruleEditorSavedRule(_ index: Int) -> String {
        "ruleEditor.savedRule.\(index)"
    }

    static func profileWorkspaceProfileOption(_ profile: String) -> String {
        "profileWorkspace.profileOption.\(normalizedIdentifierComponent(profile))"
    }

    static func profileWorkspaceWorkspaceOption(_ workspace: String) -> String {
        "profileWorkspace.workspaceOption.\(normalizedIdentifierComponent(workspace))"
    }

    private static func normalizedIdentifierComponent(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let replaced = lowered.map { scalar -> Character in
            if scalar.isLetter || scalar.isNumber {
                return scalar
            }

            return "_"
        }
        return String(replaced)
    }
}
