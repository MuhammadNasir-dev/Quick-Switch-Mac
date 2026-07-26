import Foundation
import os

/// Centralised `os.Logger` categories.
///
/// The original code used `print()` on the window-enumeration hot path, which
/// serialises on stdout and shows up as multi-millisecond stalls when a hundred
/// windows are scanned. `Logger` is lock-free, level-filtered and free in
/// release builds when the level is disabled.
nonisolated enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.quickswitchmac.QuickSwitch"

    static let windows = Logger(subsystem: subsystem, category: "windows")
    static let input = Logger(subsystem: subsystem, category: "input")
    static let activation = Logger(subsystem: subsystem, category: "activation")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}

/// Lightweight signpost-free timing helper used by the enumerator.
@inlinable
nonisolated func measure<T>(_ body: () throws -> T) rethrows -> (value: T, seconds: Double) {
    let start = DispatchTime.now().uptimeNanoseconds
    let value = try body()
    let end = DispatchTime.now().uptimeNanoseconds
    return (value, Double(end - start) / 1_000_000_000)
}
