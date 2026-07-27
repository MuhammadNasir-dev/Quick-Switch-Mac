import AppKit
import SwiftUI

/// Bridges `NSVisualEffectView` so the panel uses the system material.
///
/// HIG asks transient overlays to use vibrancy rather than a hand-picked
/// translucent black — the original view hard-coded `Color.black.opacity(0.82)`
/// and white text, which is unreadable in Light Mode and ignores Increase
/// Contrast and Reduce Transparency.
struct VisualEffectBackground: NSViewRepresentable {
    /// `.popover` rather than `.hudWindow`.
    ///
    /// The HUD material is deliberately dark in *both* appearances — it exists
    /// for heads-up overlays that are always dark chrome. Drawing semantic label
    /// colours on it means near-black text on a near-black panel in Light Mode,
    /// which is exactly the unreadable combination this was meant to avoid.
    /// `.popover` follows the system appearance, so `.primary` and `.secondary`
    /// stay legible either way.
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        // Without this the material stops updating when our app is not active,
        // which is *always* the case for a non-activating panel.
        view.isEmphasized = true
        // Follow the system appearance rather than inheriting whatever the
        // (never-active) host app happens to have.
        view.appearance = nil
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
    }
}
