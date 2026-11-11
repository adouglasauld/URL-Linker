#if canImport(AppKit)
import AppKit
import XCTest
import JunctionCore
@testable import JunctionMacKit

/// All system calls are injected; these tests must never open a browser.
final class URLRouterFailureAcceptanceTests: XCTestCase {
    private let url = URL(string: "https://example.com/?preserve=1#fragment")!
    private func environment() -> Dispatcher.Environment {
        Dispatcher.Environment(applicationURL: { _ in nil }, family: { _ in .chromium }, firefoxProfileExists: { _, _ in false }, chromiumProfiles: { _ in [] }, webApp: { _ in nil }, webAppProfile: { _ in nil }, openURLs: { _, _, _, _ in XCTFail("Unexpected launch") }, openApplication: { _, _, _ in XCTFail("Unexpected launch") }, openDefault: { _ in XCTFail("Must never re-enter the system default handler") })
    }
    func testMissingTargetAndFallbackStopWithoutDefaultHandler() {
        var env = environment()
        var resolutions: [String] = []
        env.applicationURL = { id in resolutions.append(id); return nil }
        let result = Dispatcher(fallbackApp: "com.apple.Safari", environment: env).openInBrowser(bundleID: "com.google.Chrome", profile: "Profile 1", urls: [url])
        guard case .failed = result else { return XCTFail("Both explicit destinations absent must fail safely: \(result)") }
        XCTAssertLessThanOrEqual(resolutions.count, 2)
    }
    func testMissingFallbackSelectedDirectlyIsNotRetried() {
        var env = environment()
        var resolutions: [String] = []
        env.applicationURL = { id in resolutions.append(id); return nil }
        let result = Dispatcher(fallbackApp: "com.apple.Safari", environment: env).openInBrowser(bundleID: "com.apple.Safari", profile: nil, urls: [url])
        guard case .failed = result else { return XCTFail("Missing fallback must stop: \(result)") }
        XCTAssertEqual(resolutions, ["com.apple.Safari"])
    }
    func testDirectoryIdentityIsSavedEvenWhenFriendlyLabelUnique() {
        let profiles = [BrowserProfile(directory: "Profile 1", displayName: "Work")]
        XCTAssertEqual(profiles.ruleValue(for: profiles[0]), "Profile 1")
    }
    func testDuplicateFriendlyLabelsStillIdentifyDirectories() {
        let profiles = [BrowserProfile(directory: "Default", displayName: "Work"), BrowserProfile(directory: "Profile 1", displayName: "Work")]
        XCTAssertEqual(profiles.ruleValue(for: profiles[0]), "Default")
        XCTAssertEqual(profiles.ruleValue(for: profiles[1]), "Profile 1")
    }
    func testFallbackMissingProfileIsNeverLaunchedUnchecked() {
        var env = environment()
        env.applicationURL = { id in id == "com.microsoft.edgemac" ? URL(fileURLWithPath: "/Applications/Test Edge.app") : nil }
        var dispatcher = Dispatcher(fallbackApp: "com.microsoft.edgemac", environment: env)
        dispatcher.fallbackProfile = "Profile 99"
        let result = dispatcher.openInBrowser(bundleID: "com.google.Chrome", profile: "Default", urls: [url])
        guard case .failed = result else { return XCTFail("Missing fallback profile must be validated before launch: \(result)") }
    }
    func testSameBrowserDifferentFallbackProfileCanRecover() {
        var env = environment()
        env.applicationURL = { _ in URL(fileURLWithPath: "/Applications/Test Chrome.app") }
        env.chromiumProfiles = { _ in [BrowserProfile(directory: "Default", displayName: "Personal")] }
        var launches: [[String]] = []
        env.openApplication = { _, config, completion in launches.append(config.arguments); completion?(.opened) }
        var dispatcher = Dispatcher(fallbackApp: "com.google.Chrome", environment: env)
        dispatcher.fallbackProfile = "Default"
        _ = dispatcher.openInBrowser(bundleID: "com.google.Chrome", profile: "Profile 99", urls: [url])
        XCTAssertEqual(launches.count, 1)
        XCTAssertEqual(launches.first?.first, "--profile-directory=Default")
    }
    func testSelfTargetFailsWithoutAttemptingOSLaunch() {
        var env = environment()
        env.applicationURL = { _ in XCTFail("Self target must be refused before resolution"); return nil }
        let result = Dispatcher(fallbackApp: "com.apple.Safari", environment: env).openInBrowser(bundleID: "au.com.urllinker.app", profile: nil, urls: [url])
        guard case .failed = result else { return XCTFail("Self target must fail") }
    }

}
#endif
