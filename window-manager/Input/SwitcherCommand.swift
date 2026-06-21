import Foundation

/// A user intent decoded from a raw key event.
///
/// Decoding in the tap callback and shipping a semantic command to the main
/// actor keeps the callback free of any application logic — important, because
/// the callback runs on the input thread and must return a consume/pass-through
/// decision synchronously for *every keystroke on the system*.
nonisolated enum SwitcherCommand: Equatable, Sendable {
    /// Summon the switcher (or advance it, when already visible).
    case invoke(reverse: Bool)
    /// Step the selection linearly (Tab, Left, Right). One item at a time in
    /// both layouts.
    case move(Int)
    /// Move the selection vertically (Up, Down, Page Up, Page Down). One row —
    /// which is one item in the list and a whole row of cards in the grid.
    case moveVertical(Int)
    /// Jump to the first or last row.
    case moveToEdge(first: Bool)
    /// Select the 1-based row and confirm.
    case selectIndex(Int)
    /// Activate the current selection.
    case confirm
    /// Dismiss without switching.
    case cancel
    /// Append text typed by the user to the search query.
    case insertText(String)
    /// Remove the last character of the search query.
    case deleteBackward
    /// Clear the whole query.
    case clearQuery
    /// Switch between the list and grid layouts without leaving the panel.
    case toggleLayout
    /// The summoning modifier was released.
    case modifierReleased
}
