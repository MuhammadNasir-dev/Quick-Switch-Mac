import Combine
import SwiftUI

/// Settings scene contents.
struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var authorizer: AccessibilityAuthorizer

    var body: some View {
        Form {
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
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
