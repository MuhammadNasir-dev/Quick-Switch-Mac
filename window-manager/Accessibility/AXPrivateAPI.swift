import ApplicationServices
import CoreGraphics
import Foundation
import os

/// Access to `_AXUIElementGetWindow`.
///
/// There is no public API that maps an `AXUIElement` window back to its
/// `CGWindowID`, yet the mapping is required to correlate the Accessibility
/// window list (which is authoritative for titles, minimised state and
/// activation) with `CGWindowListCopyWindowInfo` (which is authoritative for
/// z-order, alpha and on-screen state).
///
/// The previous implementation declared the symbol with `@_silgen_name`, which
/// makes it a hard link-time dependency: if Apple ever removes or renames it,
/// the app fails to launch with a dyld error. Resolving it through `dlsym`
/// instead degrades gracefully — `windowID(of:)` simply returns `nil` and the
/// enumerator falls back to geometry/title correlation.
nonisolated enum AXPrivateAPI {
    private typealias GetWindowFunction =
        @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    /// `RTLD_DEFAULT` is not exposed to Swift; on Darwin it is `(void *)-2`.
    private static let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)

    private static let getWindow: GetWindowFunction? = {
        guard let symbol = dlsym(rtldDefault, "_AXUIElementGetWindow") else {
            Log.windows.error("_AXUIElementGetWindow unavailable; falling back to geometry matching")
            return nil
        }
        return unsafeBitCast(symbol, to: GetWindowFunction.self)
    }()

    /// `true` when the runtime exposes the window-number lookup.
    nonisolated static var isWindowIDLookupAvailable: Bool { getWindow != nil }

    /// The `CGWindowID` backing an Accessibility window element, if resolvable.
    nonisolated static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let getWindow else { return nil }
        var identifier: CGWindowID = 0
        guard getWindow(element, &identifier) == .success, identifier != 0 else { return nil }
        return identifier
    }
}
