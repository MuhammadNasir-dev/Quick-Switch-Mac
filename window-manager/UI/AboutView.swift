import AppKit
import SwiftUI

/// Icon, name, version, tagline, website and copyright.
///
/// Split out from the About *window* so the same block can appear as a Settings
/// pane. Every value is read from the bundle via `AppInfo`, so neither copy can
/// disagree with what actually shipped.
struct AboutContent: View {
    /// 64pt is a native icon representation, so a 1x display draws the 64px rep
    /// and a 2x display the 128px one. An arbitrary size such as 72 would force
    /// both to resample and look soft — the same pixel-grid issue as the
    /// menu-bar icon.
    var iconSize: CGFloat = 64

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: AppInfo.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)
                .accessibilityHidden(true)

            VStack(spacing: 3) {
                Text(AppInfo.name)
                    .font(.system(size: 20, weight: .semibold))

                Text("Version \(AppInfo.displayVersion)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text("Switch between every open window, not just apps.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Link("quickswitchmac.com", destination: AppInfo.website)
                .font(.system(size: 12))

            Text(AppInfo.copyright)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("About \(AppInfo.name), version \(AppInfo.displayVersion)")
    }
}

/// The standalone About window, opened from the menu bar.
struct AboutView: View {
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            AboutContent()
                .padding(.top, 28)
                .padding(.horizontal, 28)
                .padding(.bottom, 22)

            Divider()

            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }
}
