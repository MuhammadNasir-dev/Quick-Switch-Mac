import ApplicationServices
import Foundation

/// A hashable, `Sendable` box around `AXUIElement`.
///
/// `AXUIElement` is a CoreFoundation type: it is safe to use from any thread
/// (the Accessibility client library serialises the underlying IPC itself), but
/// Swift cannot prove that, and the imported type provides neither `Hashable`
/// nor `Sendable`. Boxing it once keeps the `@unchecked Sendable` escape hatch
/// confined to a single, documented location instead of spreading it across
/// every model and service.
nonisolated struct AXElementRef: @unchecked Sendable, Hashable, CustomStringConvertible {
    let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = element
    }

    static func == (lhs: AXElementRef, rhs: AXElementRef) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }

    var description: String { "AXElementRef(\(CFHash(element)))" }
}
