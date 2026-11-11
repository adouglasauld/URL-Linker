import Foundation
import XCTest
@testable import JunctionCore

/// Independent acceptance fixtures derived from FR-02–FR-12, not implementation internals.
final class URLRouterAcceptanceTests: XCTestCase {
    private func trace(_ kind: MatchKind, _ value: String, _ input: String) -> RoutingTrace {
        let config = Config(stripTrackingParams: false, rules: [Rule(name: "fixture", match: Match(kind: kind, value: value), action: .open(app: "com.google.Chrome", profile: "Profile 1"))])
        return RoutingEngine(config: config).trace(LinkEvent(url: URL(string: input)!))
    }
    private func assertMatch(_ kind: MatchKind, _ value: String, yes: [String], no: [String], file: StaticString = #filePath, line: UInt = #line) {
        for input in yes { XCTAssertEqual(trace(kind, value, input).matchedRule, "fixture", input, file: file, line: line) }
        for input in no { XCTAssertNil(trace(kind, value, input).matchedRule, input, file: file, line: line) }
    }
    func testExactHostBoundaries() {
        assertMatch(.exactHost, "example.com", yes: ["https://EXAMPLE.com:8443/a", "http://example.com/?a=b#c"], no: ["https://a.example.com", "https://badexample.com", "https://example.com.evil.test"])
    }
    func testDomainIncludesApexAndNestedChildrenOnly() {
        assertMatch(.domainAndSubdomains, "example.com", yes: ["https://example.com", "https://a.example.com", "https://a.b.example.com"], no: ["https://notexample.com", "https://example.com.evil.test"])
    }
    func testSubdomainsExcludeParent() {
        assertMatch(.subdomainsOnly, "example.com", yes: ["https://a.example.com", "https://a.b.example.com"], no: ["https://example.com", "https://notexample.com", "https://example.com.evil.test"])
    }
    func testKeywordIncludesQueryAndFragmentButDoesNotDecodeEscapes() {
        assertMatch(.keyword, "team", yes: ["https://example.com/TEAM", "https://example.com/?q=TeAm", "https://example.com/#TEAM"], no: ["https://example.com/%74eam", "https://example.com/no-match"])
    }
    func testPrefixIsLiteralAndPathCaseSensitive() {
        assertMatch(.urlPrefix, "https://example.com/work", yes: ["https://example.com/work/1", "https://example.com/worker"], no: ["https://example.com/Work", "http://example.com/work", "https://example.com.evil.test/work"])
    }
    func testWildcardRetainsApexAndNestedSubdomainConvention() {
        assertMatch(.wildcard, "*.example.com/work/*", yes: ["https://example.com/work/1", "https://a.b.example.com/work/deep/1"], no: ["https://example.com/Work/1", "https://evil.test/work/1"])
    }
    func testRegexSearchAndExplicitCaseOption() {
        assertMatch(.regex, "(?i)ticket=[a-z]+", yes: ["https://example.com/?TICKET=ABC"], no: ["https://example.com/?ticket=123"])
        assertMatch(.regex, "^https://example\\.com/$", yes: ["https://example.com/"], no: ["https://example.com/x", "https://evil.test/?u=https://example.com/"])
    }
    func testDisabledRuleAndStoredPriorityControlWinner() {
        var first = Rule(name: "first", match: Match(kind: .keyword, value: "example"), action: .open(app: "com.google.Chrome", profile: "Profile 1"))
        let second = Rule(name: "second", match: Match(kind: .exactHost, value: "example.com"), action: .open(app: "com.microsoft.edgemac", profile: "Default"))
        let event = LinkEvent(url: URL(string: "https://example.com/?keep=1#fragment")!)
        func winner(_ rules: [Rule]) -> String? { RoutingEngine(config: Config(stripTrackingParams: false, rules: rules)).trace(event).matchedRule }
        XCTAssertEqual(winner([first, second]), "first")
        XCTAssertEqual(winner([second, first]), "second")
        first.enabled = false
        XCTAssertEqual(winner([first, second]), "second")
    }
    func testRuleIDSurvivesSaveRoundTrip() throws {
        let rule = Rule(name: "stable", match: Match(kind: .exactHost, value: "example.com"), action: .open(app: "com.google.Chrome", profile: "Profile 1"))
        let decoded = try JSONDecoder().decode(Rule.self, from: JSONEncoder().encode(rule))
        XCTAssertEqual(decoded.id, rule.id)
    }
    func testFallbackPersistsProfile() throws {
        let fallback = Fallback(app: "com.microsoft.edgemac", profile: "Profile 2")
        let decoded = try JSONDecoder().decode(Fallback.self, from: JSONEncoder().encode(fallback))
        XCTAssertEqual(decoded.profile, "Profile 2")
    }
    func testURLIngressPreservesGeneralWebURLsAndRejectsUnsafeInputs() throws {
        for raw in ["http://example.com/path?q=a%26b#fragment", "https://example.com:8443/a%20b?x=1", "https://127.0.0.1/a", "https://[::1]/"] {
            XCTAssertEqual(try URLPolicy.validate(raw).absoluteString, raw)
        }
        for raw in ["file:///tmp/a", "mailto:a@example.com", "/relative", "https://user:password@example.com/", "https://example.com/%ZZ", "https://example.com/\nunsafe", "https://example.com/" + String(repeating: "a", count: 32769)] {
            XCTAssertThrowsError(try URLPolicy.validate(raw), raw)
        }
    }
}
