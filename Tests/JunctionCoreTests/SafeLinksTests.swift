import Foundation
import XCTest
@testable import JunctionCore

final class SafeLinksTests: XCTestCase {
    private let target = URL(string: "https://jira.example.com/browse/TEST-281?keep=a%26b+plus#details")!
    private func wrap(_ destination: URL, host: String = "aus01.safelinks.protection.outlook.com") -> URL {
        var c = URLComponents(string: "https://\(host)/")!
        c.queryItems = [URLQueryItem(name: "url", value: destination.absoluteString), URLQueryItem(name: "data", value: "synthetic-only"), URLQueryItem(name: "sdata", value: "a+b/c=")]
        return c.url!
    }
    private func engine(_ rules: [Rule]? = nil, version: Int = 2) -> RoutingEngine {
        RoutingEngine(config: Config(version: version, fallback: Fallback(app: "com.apple.Safari", profile: "Default"), rules: rules ?? [Rule(name: "Work Jira", match: Match(kind: .domainAndSubdomains, value: "jira.example.com"), action: .open(app: "com.vivaldi.Vivaldi", profile: "Profile 2"))]))
    }
    func testMatchesDestinationButPreservesEntireOriginalForLaunch() {
        let original = wrap(target)
        let trace = engine().trace(LinkEvent(url: original))
        XCTAssertEqual(trace.matchedRule, "Work Jira")
        XCTAssertEqual(trace.matchingURL, target)
        XCTAssertEqual(trace.input.url, original)
        XCTAssertEqual(trace.transformedURL, original)
        XCTAssertEqual(trace.decision, .open(app: "com.vivaldi.Vivaldi", profile: "Profile 2", url: original))
    }
    func testAllMatcherKindsUseSameDestinationRepresentation() {
        let values: [(MatchKind, String)] = [(.exactHost, "jira.example.com"), (.domainAndSubdomains, "example.com"), (.subdomainsOnly, "example.com"), (.keyword, "TEST-281"), (.urlPrefix, "https://jira.example.com/browse/"), (.wildcard, "jira.example.com/browse/*"), (.regex, "^https://jira\\.example\\.com/browse/TEST-281\\?")]
        for (kind, value) in values {
            let rule = Rule(name: "destination", match: Match(kind: kind, value: value), action: .open(app: "com.vivaldi.Vivaldi", profile: "Profile 2"))
            XCTAssertEqual(engine([rule]).trace(LinkEvent(url: wrap(target))).matchedRule, "destination", kind.rawValue)
        }
    }
    func testOrdinaryLinksAreUnchanged() {
        XCTAssertEqual(SafeLinks.matchingURL(for: target), target)
        XCTAssertEqual(engine().route(LinkEvent(url: target)).url, target)
    }
    func testOnlyExactMicrosoftDomainBoundaryIsRecognized() {
        for host in ["aus01.safelinks.protection.outlook.com.evil.test", "notsafelinks.protection.outlook.com", "example.com"] {
            let url = wrap(target, host: host)
            XCTAssertEqual(SafeLinks.matchingURL(for: url), url)
            XCTAssertNil(engine().trace(LinkEvent(url: url)).matchedRule)
        }
        XCTAssertEqual(SafeLinks.matchingURL(for: wrap(target, host: "AUS01.SAFELINKS.PROTECTION.OUTLOOK.COM")), target)
    }
    func testMalformedOrUnsafeWrapperFallsBackWithoutChangingOriginal() {
        let bad = [
            "https://aus01.safelinks.protection.outlook.com/", "https://aus01.safelinks.protection.outlook.com/?url=", "https://aus01.safelinks.protection.outlook.com/?url=%ZZ",
            "https://aus01.safelinks.protection.outlook.com/?url=https%253A%252F%252Fjira.example.com",
            "https://aus01.safelinks.protection.outlook.com/?url=javascript%3Aalert(1)",
            "https://aus01.safelinks.protection.outlook.com/?url=file%3A%2F%2F%2Ftmp%2Ffile",
            "https://aus01.safelinks.protection.outlook.com/?url=%2Frelative",
            "https://aus01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fuser%3Apassword%40jira.example.com",
            "https://aus01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fjira.example.com%2F%0Aunsafe",
            "https://aus01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fjira.example.com&url=https%3A%2F%2Fevil.test",
            "http://aus01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fjira.example.com",
            "https://aus01.safelinks.protection.outlook.com:8443/?url=https%3A%2F%2Fjira.example.com",
            "https://aus01.safelinks.protection.outlook.com/unexpected?url=https%3A%2F%2Fjira.example.com"
        ]
        for raw in bad {
            let original = URL(string: raw)!
            let trace = engine().trace(LinkEvent(url: original))
            XCTAssertNil(trace.matchedRule, raw)
            XCTAssertNil(trace.matchingURL, raw)
            XCTAssertEqual(trace.decision, .open(app: "com.apple.Safari", profile: "Default", url: original), raw)
        }
    }
    func testNestedWrappersHaveStrictDepthLimit() {
        var nested = target
        for _ in 0..<4 { nested = wrap(nested) }
        XCTAssertEqual(SafeLinks.matchingURL(for: nested), target)
        XCTAssertEqual(engine().route(LinkEvent(url: nested)).url, nested)
        nested = wrap(nested)
        XCTAssertNil(SafeLinks.matchingURL(for: nested))
        XCTAssertNil(engine().trace(LinkEvent(url: nested)).matchedRule)
    }
    func testDestinationEscapesPlusAndFragmentAreDecodedExactlyOnce() {
        XCTAssertEqual(SafeLinks.matchingURL(for: wrap(target))?.absoluteString, target.absoluteString)
        let escaped = URL(string: "https://jira.example.com/%252F?q=%2526&literal=a+b%2Bc#fragment")!
        XCTAssertEqual(SafeLinks.matchingURL(for: wrap(escaped)), escaped)
    }
    func testRulePriorityAndDisableStillApplyToDestination() {
        let first = Rule(name: "first", match: Match(kind: .keyword, value: "TEST-281"), action: .open(app: "com.google.Chrome", profile: nil))
        var second = first; second.id = UUID(); second.name = "second"
        XCTAssertEqual(engine([first, second]).trace(LinkEvent(url: wrap(target))).matchedRule, "first")
        var disabled = first; disabled.enabled = false
        XCTAssertEqual(engine([disabled, second]).trace(LinkEvent(url: wrap(target))).matchedRule, "second")
    }
    func testUnmatchedDestinationKeepsProtectedURLForFallback() {
        let original = wrap(URL(string: "https://unmatched.example.org/?q=1")!)
        XCTAssertEqual(engine().route(LinkEvent(url: original)), .open(app: "com.apple.Safari", profile: "Default", url: original))
    }
    func testManualOverrideStillUsesOriginalWrapper() {
        let original = wrap(target)
        XCTAssertEqual(engine().route(LinkEvent(url: original, forcePicker: true)), .prompt(url: original))
    }
    func testLegacyConfigurationRetainsOriginalMatchingSemantics() {
        let trace = engine(version: 1).trace(LinkEvent(url: wrap(target)))
        XCTAssertNil(trace.matchedRule)
        XCTAssertEqual(trace.matchingURL, trace.input.url)
    }
}
