import Combine
import SwiftUI

/// Settings, split across tabs.
///
/// A single scrolling `Form` sized itself to its content — `.fixedSize(vertical:)`
/// on a stack of six sections produced a window taller than the screen, so the
/// bottom sat behind the Dock with no way to reach it and no resize handle to
/// fix it with. Tabs are also what macOS settings windows conventionally look
/// like, so this is the idiomatic answer rather than a workaround: each pane is
/// short enough to read at a glance, and the window stays a predictable size no
/// matter how many favourites are pinned.
struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var authorizer: AccessibilityAuthorizer
    @ObservedObject var launchAtLogin: LaunchAtLoginService
    @ObservedObject var favourites: FavouritesStore

    /// Bounds rather than a fixed size: the window is resizable, and a pane
    /// whose content outgrows the height scrolls instead of pushing the window
    /// off screen.
    enum Metrics {
        static let minimumWidth: CGFloat = 500
        static let idealWidth: CGFloat = 540
        static let minimumHeight: CGFloat = 340
        static let idealHeight: CGFloat = 430
    }

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            shortcut
                .tabItem { Label("Shortcut", systemImage: "keyboard") }
            appearance
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            windows
                .tabItem { Label("Windows", systemImage: "macwindow") }
            favouritesTab
                .tabItem { Label("Favourites", systemImage: "star") }
        }
        .frame(
            minWidth: Metrics.minimumWidth,
            idealWidth: Metrics.idealWidth,
            minHeight: Metrics.minimumHeight,
            idealHeight: Metrics.idealHeight
        )
        .onAppear { launchAtLogin.refresh() }
    }

    // MARK: - Panes

    private var general: some View {
        Form {
            Section {
                Toggle("Launch QuickSwitch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .disabled(isLaunchAtLoginUnavailable)

                if let explanation = launchAtLogin.explanation {
                    Label {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(explanation)
                                .fixedSize(horizontal: false, vertical: true)
                            if launchAtLogin.state == .requiresApproval {
                                Button("Open Login Items") { launchAtLogin.openLoginItemsSettings() }
                                    .controlSize(.small)
                            }
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Permissions") {
                HStack {
                    Image(systemName: authorizer.isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(authorizer.isTrusted ? .green : .orange)
                    Text(authorizer.isTrusted ? "Accessibility access granted" : "Accessibility access required")
                    Spacer()
                    if !authorizer.isTrusted {
                        Button("Open Settings") { authorizer.openSystemSettings() }
                            .controlSize(.small)
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
    }

    private var shortcut: some View {
        Form {
            Section {
                Picker("Summon with", selection: $preferences.modifier) {
                    ForEach(SwitcherModifier.allCases, id: \.self) { modifier in
                        Text("\(modifier.symbol)  \(modifier.displayName) + Tab").tag(modifier)
                    }
                }

                if preferences.modifier == .command {
                    caption("Command + Tab replaces the system app switcher while QuickSwitch is running.")
                }

                Toggle("Switch when the modifier is released", isOn: $preferences.confirmOnModifierRelease)
                caption("With this off, the switcher stays open until you press Return or Escape.")
            }

            Section("While the switcher is open") {
                shortcutRow("⌘L", "Cycle List → Grouped → Grid")
                shortcutRow("⌘D", "Pin or unpin the highlighted app")
                shortcutRow("⌘1–9", "Jump straight to a row")
                shortcutRow("↑ ↓", "Move the selection")
                shortcutRow("esc", "Close without switching")
            }
        }
        .formStyle(.grouped)
    }

    private var appearance: some View {
        Form {
            Section {
                Picker("Layout", selection: $preferences.layout) {
                    ForEach(SwitcherLayout.allCases, id: \.self) { layout in
                        Label(layout.displayName, systemImage: layout.symbolName).tag(layout)
                    }
                }
                .pickerStyle(.segmented)

                caption(preferences.layout.summary)

                Toggle("Show shortcut hints", isOn: $preferences.showShortcutHints)

                Stepper(
                    "Show up to \(preferences.maximumVisibleRows) rows before scrolling",
                    value: $preferences.maximumVisibleRows,
                    in: 4...16
                )
            }
        }
        .formStyle(.grouped)
    }

    private var windows: some View {
        Form {
            Section("Ordering") {
                Toggle("Show the active app's windows first", isOn: $preferences.showActiveAppWindowsFirst)
                caption(preferences.showActiveAppWindowsFirst
                        ? "Every window of the app you are in is grouped at the top, then everything else by most recent use."
                        : "Strict most-recently-used order — the second entry is whatever you were on immediately before.")
            }

            Section("Include") {
                Toggle("Minimised windows", isOn: $preferences.includeMinimized)
                Toggle("Windows on other Spaces", isOn: $preferences.includeOtherSpaces)
                caption("A Space is a Desktop you switch between with Control-Arrow or Mission Control. Turn this off to list only what is on the Desktop in front of you.")
            }
        }
        .formStyle(.grouped)
    }

    private var favouritesTab: some View {
        Form {
            Section {
                Toggle("Show favourite apps first", isOn: $preferences.favouritesFirst)
                caption("Press ⌘D while the switcher is open to pin or unpin the highlighted window's app. Favourites are remembered per app rather than per window, so they survive closing and reopening.")
            }

            Section("Pinned apps") {
                if favourites.isEmpty {
                    Text("Nothing pinned yet.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ForEach(favourites.bundleIdentifiers, id: \.self) { bundleID in
                        HStack(spacing: 8) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                            Text(FavouritesStore.displayName(for: bundleID))
                            Spacer()
                            Button {
                                favourites.remove(bundleID)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove \(FavouritesStore.displayName(for: bundleID)) from favourites")
                        }
                    }

                    HStack {
                        Spacer()
                        Button("Remove All", role: .destructive) { favourites.removeAll() }
                            .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Building blocks

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func shortcutRow(_ keys: String, _ description: String) -> some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 46, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                )
            Text(description)
                .font(.callout)
            Spacer()
        }
    }

    /// `unavailable` means the bundle sits somewhere macOS refuses to register,
    /// so the switch would fail no matter how often it were flipped.
    private var isLaunchAtLoginUnavailable: Bool {
        if case .unavailable = launchAtLogin.state { return true }
        return false
    }
}
