import Foundation

/// Decides whether a hover event reflects a real mouse movement.
///
/// The panel appears wherever the pointer already happens to be, and SwiftUI
/// delivers `onHover` for the row underneath it — even though the mouse has not
/// moved a pixel. Acting on that hands the selection to whatever the cursor was
/// resting over, so opening the switcher from the keyboard would start on an
/// arbitrary row rather than the previous window, and every subsequent arrow
/// press would fight the stationary pointer.
///
/// The system switcher behaves the same way this does: the pointer is ignored
/// until it is actually moved.
///
/// Keeping the rule in a small value type makes it testable without a window
/// server, which a `.onHover` closure buried in a view would not be.
struct PointerActivityGate {
    /// How far the pointer must travel before hover counts as intentional.
    ///
    /// Not zero: a mouse resting on a desk reports sub-pixel jitter, and an
    /// exact-equality check would let that through immediately.
    static let movementThreshold: CGFloat = 3

    /// Where the pointer was when hover was last suppressed, or `nil` once the
    /// user has taken control of the mouse.
    private var anchor: CGPoint?

    /// Ignores hover until the pointer moves away from `location`.
    ///
    /// Called when the panel opens and after every keyboard command, so
    /// returning to the keyboard re-suppresses a pointer that happens to be
    /// sitting over a different row.
    mutating func suppressHover(at location: CGPoint) {
        anchor = location
    }

    /// Whether a hover at `location` should move the selection.
    ///
    /// Mutating: the first genuine movement releases the gate, so subsequent
    /// hovers are accepted without re-measuring against a stale anchor.
    mutating func shouldAcceptHover(at location: CGPoint) -> Bool {
        guard let anchor else { return true }

        let dx = location.x - anchor.x
        let dy = location.y - anchor.y
        guard (dx * dx + dy * dy).squareRoot() > Self.movementThreshold else { return false }

        self.anchor = nil
        return true
    }

    /// `true` while the pointer is being ignored.
    var isSuppressed: Bool { anchor != nil }
}
