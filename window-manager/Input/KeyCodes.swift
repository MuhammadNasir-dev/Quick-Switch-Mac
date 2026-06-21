import CoreGraphics
import Foundation

/// Virtual key codes used by the switcher.
///
/// Hard-coded ANSI codes are correct here: virtual key codes are *positional*
/// and identical across keyboard layouts, unlike the characters they produce.
nonisolated enum KeyCode {
    static let tab: Int64 = 48
    static let `return`: Int64 = 36
    static let keypadEnter: Int64 = 76
    static let escape: Int64 = 53
    static let space: Int64 = 49
    static let delete: Int64 = 51
    static let forwardDelete: Int64 = 117
    static let arrowLeft: Int64 = 123
    static let arrowRight: Int64 = 124
    static let arrowDown: Int64 = 125
    static let arrowUp: Int64 = 126
    static let home: Int64 = 115
    static let end: Int64 = 119
    static let pageUp: Int64 = 116
    static let pageDown: Int64 = 121
    static let graveAccent: Int64 = 50
    /// ⌘L toggles between the list and grid layouts.
    static let letterL: Int64 = 37

    /// Number-row digits 1…9 then 0, in order.
    static let digitRow: [Int64] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]

    /// Returns 1…9 for the corresponding digit key, or `nil`.
    static func digit(for keyCode: Int64) -> Int? {
        guard let index = digitRow.firstIndex(of: keyCode), index < 9 else { return nil }
        return index + 1
    }
}

/// The modifier that summons the switcher.
///
/// Declaration order drives the Settings picker, so the default (Option) comes
/// first. Raw values are persisted, so they must not be renamed.
nonisolated enum SwitcherModifier: String, CaseIterable, Sendable {
    /// Default. Unclaimed by macOS, so it works alongside the system switcher.
    case option
    /// Takes over Command-Tab, replacing the system app switcher entirely.
    case command
    case control

    var flag: CGEventFlags {
        switch self {
        case .command: .maskCommand
        case .option: .maskAlternate
        case .control: .maskControl
        }
    }

    var symbol: String {
        switch self {
        case .command: "⌘"
        case .option: "⌥"
        case .control: "⌃"
        }
    }

    var displayName: String {
        switch self {
        case .command: "Command"
        case .option: "Option"
        case .control: "Control"
        }
    }
}
