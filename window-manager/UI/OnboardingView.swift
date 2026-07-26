import AppKit
import Combine
import SwiftUI

/// Explains and recovers from the missing-Accessibility state.
///
/// "Detect missing permissions, guide the user, recover automatically": the
/// view watches `AccessibilityAuthorizer`, so the moment the checkbox is ticked
/// in System Settings the panel flips to the granted state and closes itself —
/// no relaunch, no manual retry.
struct OnboardingView: View {
    @ObservedObject var authorizer: AccessibilityAuthorizer
    @ObservedObject var preferences: Preferences
    var onDone: () -> Void

    /// Force-unwrap-free constant for a URL that is known-good at compile time.
    static let website = URL(string: "https://quickswitchmac.com") ?? URL(fileURLWithPath: "/")

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if authorizer.isTrusted {
                grantedState
            } else {
                permissionSteps
            }

            Divider()
            shortcutSummary

            HStack {
                Link("quickswitchmac.com", destination: Self.website)
                    .font(.caption)
                Spacer()
                Button(authorizer.isTrusted ? "Done" : "Close", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 30))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("QuickSwitch")
                    .font(.title2.weight(.semibold))
                Text("Switch between every open window, not just apps.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var grantedState: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility access granted").font(.body.weight(.medium))
                Text("The switcher is running in the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }

    private var permissionSteps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility access required").font(.body.weight(.medium))
                    Text("macOS only lets an app read window titles and focus other apps' windows with this permission. It cannot be granted programmatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "lock.shield.fill").foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 6) {
                stepRow(1, "Open Privacy & Security → Accessibility.")
                stepRow(2, "Enable QuickSwitch in the list.")
                stepRow(3, "Come back here — it detects the change automatically.")
            }
            .padding(.leading, 4)

            HStack(spacing: 10) {
                Button("Open System Settings") { authorizer.openSystemSettings() }
                    .buttonStyle(.borderedProminent)
                Button("Request Access") { authorizer.requestTrust() }
                Button("Reveal App") { authorizer.revealApplicationInFinder() }
            }

            // The single most common way to get stuck, and completely opaque
            // without an explanation: macOS records a decision per code
            // signature and then stops prompting, so an entry left over from an
            // earlier build can never be switched back on.
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Switch already on, but still not working?", systemImage: "wrench.and.screwdriver")
                        .font(.caption.weight(.semibold))
                    Text("Select QuickSwitch in the list, remove it with −, then drag the app back in with +. macOS only offers the permission prompt once per build, so an entry from a previous version cannot be re-approved — it has to be replaced.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
        }
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(text).font(.caption)
        }
    }

    private var shortcutSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shortcuts").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                ShortcutHint(keys: ["\(preferences.modifier.symbol)⇥"], label: "open / next")
                ShortcutHint(keys: ["⇧\(preferences.modifier.symbol)⇥"], label: "previous")
                ShortcutHint(keys: ["⌘1–9"], label: "jump")
                ShortcutHint(keys: ["esc"], label: "cancel")
            }
            Text("Start typing while the switcher is open to filter by app name or window title.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
