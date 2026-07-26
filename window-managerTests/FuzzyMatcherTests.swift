import CoreGraphics
import Testing
@testable import QuickSwitch

@Suite("Fuzzy matching")
struct FuzzyMatcherTests {
    @Test("An empty query matches everything")
    func emptyQueryMatches() {
        let match = FuzzyMatcher.match(query: "", candidate: "Safari")
        #expect(match?.score == 0)
    }

    @Test("A query longer than the candidate never matches")
    func tooLongQuery() {
        #expect(FuzzyMatcher.match(query: "abcdefgh", candidate: "abc") == nil)
    }

    @Test("Non-subsequences are rejected")
    func rejectsNonSubsequence() {
        #expect(FuzzyMatcher.match(query: "xyz", candidate: "Safari") == nil)
    }

    @Test("Abbreviations match across word boundaries")
    func matchesAbbreviation() {
        #expect(FuzzyMatcher.match(query: "ad", candidate: "AppDelegate.swift") != nil)
        #expect(FuzzyMatcher.match(query: "npm", candidate: "npm run dev") != nil)
    }

    @Test("Exact matches outrank prefixes, which outrank scattered matches")
    func scoreOrdering() throws {
        let exact = try #require(FuzzyMatcher.match(query: "safari", candidate: "Safari"))
        let prefix = try #require(FuzzyMatcher.match(query: "safa", candidate: "Safari Technology"))
        let scattered = try #require(FuzzyMatcher.match(query: "sfi", candidate: "Some Fine Idea"))
        #expect(exact.score > prefix.score)
        #expect(prefix.score > scattered.score)
    }

    @Test("Consecutive runs beat scattered hits in the same candidate length")
    func consecutiveBeatsScattered() throws {
        let consecutive = try #require(FuzzyMatcher.match(query: "git", candidate: "xxx git xxx"))
        let scattered = try #require(FuzzyMatcher.match(query: "git", candidate: "gxixtxxxxxx"))
        #expect(consecutive.score > scattered.score)
    }

    @Test("Matching is case-insensitive")
    func caseInsensitive() {
        #expect(FuzzyMatcher.match(query: "GITHUB", candidate: "GitHub") != nil)
        #expect(FuzzyMatcher.match(query: "github", candidate: "GitHub") != nil)
    }

    @Test("Matched indices point at the right characters")
    func matchedIndices() throws {
        let match = try #require(FuzzyMatcher.match(query: "gh", candidate: "GitHub"))
        let characters = Array("GitHub")
        let matched = match.matchedIndices.map { characters[$0] }
        #expect(matched == ["G", "H"])
    }

    @Test("Windows match on app name, on title, or across both")
    func windowScoring() {
        let window = WindowFixtures.make(id: 1, app: "Safari", title: "ChatGPT — OpenAI")
        #expect(FuzzyMatcher.score(query: "safari", window: window) != nil)
        #expect(FuzzyMatcher.score(query: "chatgpt", window: window) != nil)
        #expect(FuzzyMatcher.score(query: "saf chat", window: window) != nil)
        #expect(FuzzyMatcher.score(query: "zzzz", window: window) == nil)
    }

    @Test("Untitled windows fall back to the app name for matching")
    func untitledWindow() {
        let window = WindowFixtures.make(id: 1, app: "Terminal", title: "   ")
        #expect(window.displayTitle == "Terminal")
        #expect(FuzzyMatcher.score(query: "term", window: window) != nil)
    }

    @Test("Scoring stays fast over a large window list", .timeLimit(.minutes(1)))
    func performance() {
        let windows = (0..<2_000).map {
            WindowFixtures.make(id: CGWindowID($0), app: "App\($0 % 40)", title: "Document \($0).swift")
        }
        var hits = 0
        for _ in 0..<10 {
            hits += windows.compactMap { FuzzyMatcher.score(query: "doc", window: $0) }.count
        }
        #expect(hits == 20_000)
    }
}
