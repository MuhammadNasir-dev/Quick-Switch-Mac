import Foundation

/// A dotted release version, compared the way humans expect.
///
/// `String` comparison gets this wrong in the case that matters most —
/// `"1.10" < "1.9"` lexicographically — which would tell every user on 1.9 that
/// 1.10 is an older build and silently stop offering updates. Comparing numeric
/// components avoids that, and tolerating differing component counts means
/// `1.2` and `1.2.0` are the same release rather than an infinite update prompt.
nonisolated struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    let components: [Int]
    let original: String

    init(_ string: String) {
        original = string
        // Ignore anything after a dash so `1.2.0-beta.1` still orders sensibly
        // against `1.2.0`, and drop non-numeric noise rather than trapping.
        let core = string.split(separator: "-", maxSplits: 1).first.map(String.init) ?? string
        components = core
            .split(separator: ".")
            .map { part in Int(part.filter(\.isNumber)) ?? 0 }
    }

    var description: String { original }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            // A missing component is zero: 1.2 and 1.2.0 are the same release.
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
