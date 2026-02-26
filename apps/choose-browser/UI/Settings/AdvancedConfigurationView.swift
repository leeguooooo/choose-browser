import SwiftUI

struct RuleEditorAdvancedView: View {
    @Binding var domain: String
    @Binding var path: String
    let dispatchMode: ExecutionPlanDispatchModeV2
    let savedRules: [String]
    let validationMessage: String?
    let onSelectDispatchMode: (ExecutionPlanDispatchModeV2) -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Advanced Rule Editor")
                .font(.subheadline)
                .fontWeight(.semibold)

            TextField("Domain", text: $domain)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(AccessibilityIdentifiers.ruleEditorDomainField)

            TextField("Path", text: $path)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(AccessibilityIdentifiers.ruleEditorPathField)

            HStack(spacing: 8) {
                Button("Single") {
                    onSelectDispatchMode(.singleTarget)
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.ruleEditorDispatchSingle)

                Button("Failover") {
                    onSelectDispatchMode(.orderedFailover)
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.ruleEditorDispatchFailover)

                Button("Fanout") {
                    onSelectDispatchMode(.fanout)
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.ruleEditorDispatchFanout)
            }

            Text("Dispatch mode: \(dispatchMode.rawValue)")
                .font(.caption)
                .foregroundColor(.secondary)
                .accessibilityIdentifier(AccessibilityIdentifiers.ruleEditorDispatchModeLabel)

            Button("Save Rule") {
                onSave()
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.ruleEditorSaveButton)

            if let validationMessage, !validationMessage.isEmpty {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .accessibilityIdentifier(AccessibilityIdentifiers.ruleEditorValidationLabel)
            }

            Text("Saved rules: \(savedRules.count)")
                .font(.caption)
                .foregroundColor(.secondary)
                .accessibilityIdentifier(AccessibilityIdentifiers.ruleEditorSavedRulesCountLabel)

            ForEach(Array(savedRules.enumerated()), id: \.offset) { index, value in
                Text(value)
                    .font(.caption)
                    .accessibilityIdentifier(AccessibilityIdentifiers.ruleEditorSavedRule(index))
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ProfileWorkspaceChooserView: View {
    let profiles: [String]
    let workspaces: [String]
    let selectedProfile: String?
    let selectedWorkspace: String?
    let onSelectProfile: (String) -> Void
    let onSelectWorkspace: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profiles & Workspaces")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("Profile: \(selectedProfile ?? "none")")
                .font(.caption)
                .foregroundColor(.secondary)
                .accessibilityIdentifier(AccessibilityIdentifiers.profileWorkspaceSelectedProfileLabel)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(profiles, id: \.self) { profile in
                        Button(profile) {
                            onSelectProfile(profile)
                        }
                        .accessibilityIdentifier(AccessibilityIdentifiers.profileWorkspaceProfileOption(profile))
                    }
                }
            }

            Text("Workspace: \(selectedWorkspace ?? "none")")
                .font(.caption)
                .foregroundColor(.secondary)
                .accessibilityIdentifier(AccessibilityIdentifiers.profileWorkspaceSelectedWorkspaceLabel)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(workspaces, id: \.self) { workspace in
                        Button(workspace) {
                            onSelectWorkspace(workspace)
                        }
                        .accessibilityIdentifier(AccessibilityIdentifiers.profileWorkspaceWorkspaceOption(workspace))
                    }
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
