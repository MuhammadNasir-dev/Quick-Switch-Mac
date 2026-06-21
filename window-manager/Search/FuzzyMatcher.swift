import Foundation

/// A scored subsequence matcher in the spirit of Sublime Text / Raycast.
///
/// Requirements: matching must be fuzzy, must cover both the application name
/// and the window title, and must run on every keystroke over the full window
/// list without a visible hitch. A full Levenshtein pass is both the wrong
/// semantics (users type abbreviations, not typos) and needlessly quadratic, so
/// this is a greedy subsequence scan with positional bonuses.
///
/// Scoring, highest first:
/// * exact match, then prefix match — these always outrank fuzzy hits,
/// * runs of consecutive characters,
/// * matches at word / camel-case boundaries,
/// * earlier matches over later ones,
/// with a penalty for every skipped character.
nonisolated enum FuzzyMatcher {
    struct Match: Equatable {
        let score: Int
        /// Indices into the *original* candidate string, for highlighting.
        let matchedIndices: [Int]
    }

    private enum Weight {
        static let exact = 1_000
        static let prefix = 400
        static let wordBoundaryStart = 200
        static let consecutive = 30
        static let boundary = 25
        static let camelBoundary = 20
        static let leadingPenalty = -2
        static let skipPenalty = -3
        static let maximumLeadingPenalty = -30
    }

    /// Scores `query` against `candidate`. Returns `nil` when the query is not
    /// a subsequence of the candidate.
    ///
    /// An empty query matches everything with score 0, which lets callers use a
    /// single code path for the unfiltered list.
    static func match(query: String, candidate: String) -> Match? {
        guard !query.isEmpty else { return Match(score: 0, matchedIndices: []) }
        guard !candidate.isEmpty else { return nil }

        let queryChars = Array(query.lowercased())
        let candidateChars = Array(candidate)
        let loweredCandidate = Array(candidate.lowercased())
        guard queryChars.count <= candidateChars.count else { return nil }

        var score = 0
        var indices: [Int] = []
        indices.reserveCapacity(queryChars.count)

        var candidateIndex = 0
        var previousMatchIndex = -1

        for queryChar in queryChars {
            var found = false
            while candidateIndex < loweredCandidate.count {
                if loweredCandidate[candidateIndex] == queryChar {
                    found = true
                    break
                }
                candidateIndex += 1
            }
            guard found else { return nil }

            if previousMatchIndex >= 0 {
                let gap = candidateIndex - previousMatchIndex - 1
                if gap == 0 {
                    score += Weight.consecutive
                } else {
                    score += gap * Weight.skipPenalty
                }
            } else {
                score += max(Weight.maximumLeadingPenalty, candidateIndex * Weight.leadingPenalty)
            }

            if isBoundary(at: candidateIndex, in: candidateChars) {
                score += Weight.boundary
            }
            if isCamelBoundary(at: candidateIndex, in: candidateChars) {
                score += Weight.camelBoundary
            }
            // Exact-case agreement is a weak but useful signal.
            if candidateIndex < candidateChars.count, candidateChars[candidateIndex] == queryChar {
                score += 1
            }

            indices.append(candidateIndex)
            previousMatchIndex = candidateIndex
            candidateIndex += 1
        }

        let lowerCandidate = candidate.lowercased()
        let lowerQuery = query.lowercased()
        if lowerCandidate == lowerQuery {
            score += Weight.exact
        } else if lowerCandidate.hasPrefix(lowerQuery) {
            score += Weight.prefix
        } else if wordStarts(in: candidateChars).contains(where: { start in
            hasPrefix(loweredCandidate, from: start, prefix: queryChars)
        }) {
            score += Weight.wordBoundaryStart
        }

        // Shorter candidates are better matches for the same query.
        score -= candidateChars.count / 8

        return Match(score: score, matchedIndices: indices)
    }

    /// Scores a window, taking the better of its title and its application
    /// name, plus a bonus when the query spans both ("saf git" → Safari/GitHub).
    static func score(query: String, window: AppWindow) -> Match? {
        guard !query.isEmpty else { return Match(score: 0, matchedIndices: []) }

        let titleMatch = match(query: query, candidate: window.displayTitle)
        let appMatch = match(query: query, candidate: window.appName)
        // "Safari — ChatGPT" style combined text catches queries that straddle
        // the two fields, which a per-field match alone would reject.
        let combinedMatch = match(query: query, candidate: "\(window.appName) \(window.displayTitle)")

        let candidates = [titleMatch, appMatch, combinedMatch].compactMap { $0 }
        guard let best = candidates.max(by: { $0.score < $1.score }) else { return nil }

        // Title hits are what the user is usually after in a window switcher.
        if let titleMatch, titleMatch.score == best.score {
            return Match(score: best.score + 10, matchedIndices: titleMatch.matchedIndices)
        }
        return best
    }

    // MARK: - Boundaries

    private static func isBoundary(at index: Int, in characters: [Character]) -> Bool {
        guard index > 0 else { return true }
        let previous = characters[index - 1]
        return previous == " " || previous == "-" || previous == "_" || previous == "/"
            || previous == "." || previous == "—" || previous == "–" || previous == ":"
    }

    private static func isCamelBoundary(at index: Int, in characters: [Character]) -> Bool {
        guard index > 0, index < characters.count else { return false }
        let current = characters[index]
        let previous = characters[index - 1]
        return current.isUppercase && previous.isLowercase
    }

    private static func wordStarts(in characters: [Character]) -> [Int] {
        var starts: [Int] = []
        for index in characters.indices where isBoundary(at: index, in: characters) {
            starts.append(index)
        }
        return starts
    }

    private static func hasPrefix(_ characters: [Character], from start: Int, prefix: [Character]) -> Bool {
        guard start + prefix.count <= characters.count else { return false }
        for offset in prefix.indices where characters[start + offset] != prefix[offset] {
            return false
        }
        return true
    }
}
