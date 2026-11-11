import Foundation
import XCTest
@testable import JunctionCore

final class URLRouterConfigurationAcceptanceTests: XCTestCase {
    func testInvalidTypedMatchersAreRejectedBeforeRouting() {
        let cases: [(MatchKind, String)] = [(.exactHost, "example.com/path"), (.exactHost, "example.com:8443"), (.exactHost, "a..example.com"), (.keyword, ""), (.regex, "["), (.urlPrefix, "relative/path"), (.domainAndSubdomains, "127.0.0.1")]
        for (kind, value) in cases {
            let c = Config(rules: [Rule(name: "invalid", match: Match(kind: kind, value: value), action: .open(app: "com.google.Chrome", profile: nil))])
            XCTAssertFalse(ConfigStore.validate(c).isEmpty, "Must reject \(kind): \(value)")
        }
    }
    func testFutureVersionAndDuplicateRuleIDsAreRejected() {
        XCTAssertFalse(ConfigStore.validate(Config(version: 999)).isEmpty)
        let rule = Rule(name: "same ID", match: Match(kind: .keyword, value: "example"), action: .open(app: "com.google.Chrome", profile: nil))
        XCTAssertFalse(ConfigStore.validate(Config(rules: [rule, rule])).isEmpty)
    }
    func testInvalidSaveLeavesLastCommittedStateIntact() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("config.json")
        let store = ConfigStore(fileURL: file)
        let valid = Config(stripTrackingParams: false, rules: [Rule(name: "last good", match: Match(kind: .exactHost, value: "example.com"), action: .open(app: "com.google.Chrome", profile: nil))])
        try store.save(valid)
        let before = try Data(contentsOf: file)
        let invalid = Config(rules: [Rule(name: "bad", match: Match(kind: .regex, value: "["), action: .open(app: "com.google.Chrome", profile: nil))])
        XCTAssertThrowsError(try store.save(invalid))
        XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertEqual(store.config.rules.first?.name, "last good")
    }
    func testCorruptExternalReloadRetainsLastGoodRules() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("config.json")
        let store = ConfigStore(fileURL: file)
        try store.save(Config(stripTrackingParams: false, rules: [Rule(name: "retained", match: Match(kind: .keyword, value: "keep"), action: .open(app: "com.google.Chrome", profile: nil))]))
        try Data("{broken".utf8).write(to: file)
        store.reload()
        XCTAssertNotNil(store.lastError)
        XCTAssertEqual(store.config.rules.first?.name, "retained")
    }
}
