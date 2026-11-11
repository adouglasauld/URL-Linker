#if canImport(AppKit)
import Foundation
import XCTest
@testable import JunctionMacKit

final class URLRouterMetadataAcceptanceTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("url-linker-catalog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    private func directory(_ name: String) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
    }
    private func metadata(_ cache: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: ["profile": ["info_cache": cache], "unrelated": "not-returned"]).write(to: root.appendingPathComponent("Local State"))
    }
    func testFriendlyLabelsNeverReplaceStableDirectoryIDs() throws {
        try directory("Default"); try directory("Profile 1")
        try metadata(["Default": ["name": "Work"], "Profile 1": ["name": "Work"]])
        let result = try ChromiumProfiles.profiles(root: root)
        XCTAssertEqual(Set(result.map(\.directory)), ["Default", "Profile 1"])
        XCTAssertEqual(result.map(\.displayName), ["Work", "Work"])
    }
    func testMissingProfileAndHostileMetadataKeysAreNotReturned() throws {
        try directory("Default")
        try metadata(["Default": ["name": "valid"], "Profile 2": ["name": "missing"], "../../outside": ["name": "hostile"], "--incognito": ["name": "argument"]])
        XCTAssertEqual(try ChromiumProfiles.profiles(root: root).map(\.directory), ["Default"])
        XCTAssertThrowsError(try ChromiumProfiles.existingDirectory("Profile 2", root: root))
        for key in ["../Default", "/tmp", "Profile 01", "Profile 0", "Profile 1000000", "--incognito", "Default\n"] {
            XCTAssertThrowsError(try ChromiumProfiles.existingDirectory(key, root: root), key)
        }
    }
    func testSymlinkedProfileCannotEscapeBrowserRoot() throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Profile 1"), withDestinationURL: outside)
        try metadata(["Profile 1": ["name": "escape"]])
        XCTAssertThrowsError(try ChromiumProfiles.existingDirectory("Profile 1", root: root))
        XCTAssertTrue(try ChromiumProfiles.profiles(root: root).isEmpty)
    }
    func testSymlinkedMetadataCannotEscapeBrowserRoot() throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("{\"profile\":{\"info_cache\":{}}}".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Local State"), withDestinationURL: outside)
        XCTAssertThrowsError(try ChromiumProfiles.profiles(root: root))
    }
    func testMalformedAndMissingMetadataProduceErrors() throws {
        XCTAssertThrowsError(try ChromiumProfiles.profiles(root: root))
        for data in [Data("{".utf8), Data("{}".utf8), Data("{\"profile\":{\"info_cache\":[]}}".utf8)] {
            try data.write(to: root.appendingPathComponent("Local State"))
            XCTAssertThrowsError(try ChromiumProfiles.profiles(root: root))
        }
    }
    func testMetadataSizeAndEntryBoundsRejectRatherThanTruncate() throws {
        try Data(repeating: 32, count: 4_194_305).write(to: root.appendingPathComponent("Local State"))
        XCTAssertThrowsError(try ChromiumProfiles.profiles(root: root))
        var cache: [String: Any] = [:]
        for i in 1...129 { cache["Profile \(i)"] = ["name": "fixture"] }
        try metadata(cache)
        XCTAssertThrowsError(try ChromiumProfiles.profiles(root: root))
    }
    func testProfileLabelIsSanitizedAndBounded() throws {
        try directory("Default")
        try metadata(["Default": ["name": "Work\n\t" + String(repeating: "A", count: 200)]])
        let profile = try XCTUnwrap(ChromiumProfiles.profiles(root: root).first)
        XCTAssertLessThanOrEqual(profile.displayName.unicodeScalars.count, 160)
        XCTAssertFalse(profile.displayName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains))
        XCTAssertEqual(profile.directory, "Default")
    }
}
#endif
