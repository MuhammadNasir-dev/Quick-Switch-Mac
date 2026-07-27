import AppKit
import SwiftUI

/// The About box: icon, name, version, copyright.
///
/// Every value is read from the bundle via `AppInfo`, so it cannot disagree
/// with what actually shipped.
struct AboutView: View {
    var onClose: () -> Void

    /// 64pt is a native icon representation, so a 1× display draws the 64px rep
    /// and a 2× display the 128px one. An arbitrary size such as 72 would force
    /// both to resample and look soft — the same pixel-grid issue as the
    /// menu-bar icon.
    private let iconSize: CGFloat = 64

    var body: some View {
        VStack(spacing: 0) {
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
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 28)
            .padding(.horizontal, 28)
            .padding(.bottom, 20)

            Divider()

            Text(AppInfo.copyright)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 24)

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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("About \(AppInfo.name), version \(AppInfo.displayVersion)")
    }
}
