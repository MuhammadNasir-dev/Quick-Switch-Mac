import Combine
import SwiftUI

/// Settings scene contents.
struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var authorizer: AccessibilityAuthorizer
    @ObservedObject var launchAtLogin: LaunchAtLoginService

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch QuickSwitch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .disabled(isLaunchAtLoginUnavailable)

                if let explanation = launchAtLogin.explanation {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(explanation)
                            .fixedSize(horizontal: false, vertical: true)
                        if launchAtLogin.state == .requiresApproval {
                            Button("Open Login Items") { launchAtLogin.openLoginItemsSettings() }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Shortcut") {
                Picker("Summon with", selection: $preferences.modifier) {
                    ForEach(SwitcherModifier.allCases, id: \.self) { modifier in
                        Text("\(modifier.symbol)  \(modifier.displayName) + Tab").tag(modifier)
                    }
                }
                if preferences.modifier == .command {
                    Text("Command + Tab replaces the system app switcher while this app is running.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Switch when the modifier is released", isOn: $preferences.confirmOnModifierRelease)
                Text("With this off, the switcher stays open until you press Return or Escape.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Picker("Layout", selection: $preferences.layout) {
                    ForEach(SwitcherLayout.allCases, id: \.self) { layout in
                        Label(layout.displayName, systemImage: layout.symbolName).tag(layout)
                    }
                }
                .pickerStyle(.segmented)

                Text(preferences.layout.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Press ⌘L while the switcher is open to cycle layouts.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Toggle("Show shortcut hints", isOn: $preferences.showShortcutHints)

                Stepper(
                    "Show up to \(preferences.maximumVisibleRows) rows before scrolling",
                    value: $preferences.maximumVisibleRows,
                    in: 4...16
                )
            }

            Section("Windows") {
                Toggle("Show the active app's windows first", isOn: $preferences.showActiveAppWindowsFirst)
                Text(preferences.showActiveAppWindowsFirst
                     ? "Every window of the app you are in is grouped at the top, then everything else by most recent use."
                     : "Strict most-recently-used order — the second entry is whatever you were on immediately before.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Include minimised windows", isOn: $preferences.includeMinimized)
                Toggle("Include windows on other Spaces", isOn: $preferences.includeOtherSpaces)
            }

            Section("Permissions") {
                HStack {
                    Image(systemName: authorizer.isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(authorizer.isTrusted ? .green : .orange)
                    Text(authorizer.isTrusted ? "Accessibility access granted" : "Accessibility access required")
                    Spacer()
                    if !authorizer.isTrusted {
                        Button("Open Settings") { authorizer.openSystemSettings() }
                    }
                }
                if authorizer.isSecureInputActive {
                    Label(
                        "Secure input is active — another app is blocking global shortcuts.",
                        systemImage: "keyboard.badge.ellipsis"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin.refresh() }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private extension SettingsView {
    /// `unavailable` means the bundle sits somewhere macOS refuses to register,
    /// so the switch would fail no matter how often it were flipped.
    var isLaunchAtLoginUnavailable: Bool {
        if case .unavailable = launchAtLogin.state { return true }
        return false
    }
}
