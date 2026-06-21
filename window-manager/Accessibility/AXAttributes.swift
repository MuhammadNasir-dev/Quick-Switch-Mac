import ApplicationServices
import CoreGraphics
import Foundation

/// Attribute names that Apple ships as string constants without Swift symbols.
nonisolated enum AXAttribute {
    /// Present on windows of apps that support native full screen.
    static let fullScreen = "AXFullScreen"
}

/// Type-safe wrappers over the C Accessibility attribute API.
///
/// Every accessor is failable rather than force-unwrapping or force-casting.
/// The original code did `AXValueGetValue(posVal as! AXValue, …)`, which traps
/// whenever an application returns an unexpected type — something Electron and
/// Java apps do routinely during window teardown.
nonisolated enum AX {
    /// Copies an attribute and bridges it to `T`, returning `nil` on any failure.
    nonisolated static func value<T>(_ element: AXUIElement, _ attribute: String, as _: T.Type = T.self) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else {
            return nil
        }
        return raw as? T
    }

    nonisolated static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute, as: String.self)
    }

    nonisolated static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        // CFBoolean bridges to Bool; NSNumber-returning apps bridge too.
        if let flag: Bool = value(element, attribute) { return flag }
        if let number: NSNumber = value(element, attribute) { return number.boolValue }
        return nil
    }

    /// Copies an attribute and validates that it really is an `AXValue` of the
    /// expected kind before unwrapping it.
    ///
    /// The `CFGetTypeID` guard is what makes the subsequent cast safe: the
    /// original code went straight to `posVal as! AXValue`, which traps whenever
    /// an application returns something else — a routine occurrence in Electron
    /// and Java apps during window teardown.
    private nonisolated static func boxedValue(
        _ element: AXUIElement,
        _ attribute: String,
        type: AXValueType
    ) -> AXValue? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let boxed = raw,
              CFGetTypeID(boxed) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(boxed, to: AXValue.self)
        guard AXValueGetType(axValue) == type else { return nil }
        return axValue
    }

    nonisolated static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let boxed = boxedValue(element, attribute, type: .cgPoint) else { return nil }
        var result = CGPoint.zero
        // `withUnsafeMutablePointer` rather than `&result`: taking a raw pointer
        // to a generic or inout binding is only well-defined for a concrete,
        // reference-free type accessed through an explicit pointer scope.
        let ok = withUnsafeMutablePointer(to: &result) { AXValueGetValue(boxed, .cgPoint, $0) }
        return ok ? result : nil
    }

    nonisolated static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let boxed = boxedValue(element, attribute, type: .cgSize) else { return nil }
        var result = CGSize.zero
        let ok = withUnsafeMutablePointer(to: &result) { AXValueGetValue(boxed, .cgSize, $0) }
        return ok ? result : nil
    }

    /// The window's frame in Accessibility (top-left origin, global) coordinates.
    nonisolated static func frame(_ element: AXUIElement) -> CGRect? {
        guard let origin = point(element, kAXPositionAttribute as String),
              let size = size(element, kAXSizeAttribute as String) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    nonisolated static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        value(element, attribute, as: [AXUIElement].self) ?? []
    }

    @discardableResult
    nonisolated static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    @discardableResult
    nonisolated static func setFlag(_ element: AXUIElement, _ attribute: String, _ flag: Bool) -> Bool {
        set(element, attribute, flag ? kCFBooleanTrue : kCFBooleanFalse)
    }

    @discardableResult
    nonisolated static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    /// Bounds how long a single Accessibility round-trip may block.
    ///
    /// Without this a hung application (a spinning-beachball Electron app, a
    /// stopped process under a debugger) blocks the enumerator for the system
    /// default of six seconds. Everything the switcher reads is optional
    /// metadata, so a short timeout that skips the app is strictly better.
    nonisolated static func setMessagingTimeout(_ element: AXUIElement, seconds: Float) {
        AXUIElementSetMessagingTimeout(element, seconds)
    }
}
