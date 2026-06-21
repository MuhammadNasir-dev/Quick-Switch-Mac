import AppKit
import SwiftUI

/// Bridges `NSVisualEffectView` so the panel uses the system material.
///
/// HIG asks transient overlays to use vibrancy rather than a hand-picked
/// translucent black — the original view hard-coded `Color.black.opacity(0.82)`
/// and white text, which is unreadable in Light Mode and ignores Increase
/// Contrast and Reduce Transparency.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        // Without this the material stops updating when our app is not active,
        // which is *always* the case for a non-activating panel.
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
    }
}
