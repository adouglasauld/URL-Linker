import AppKit
import Foundation
import JunctionCore

public enum LaunchResult: Equatable, Sendable {
    case handedOff
    case definiteFailure(String)
    case uncertain
}
/// Explicit application launch only. Fallback orchestration belongs to the caller.
@MainActor public final class BrowserLauncher {
    public init() {}
    public func launch(url: URL, app: String, profile: String?) async -> LaunchResult {
        guard !["com.jnahian.junction", "au.com.urllinker.app", Bundle.main.bundleIdentifier ?? ""].contains(app),
              let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app), Bundle(url: application)?.bundleIdentifier == app,
              NSWorkspace.shared.urlsForApplications(toOpen: url).contains(where: { Bundle(url: $0)?.bundleIdentifier == app }) else { return .definiteFailure("Browser unavailable or cannot handle URL") }
        if let profile {
            guard let subpath = ChromiumProfiles.dataDirectories[app], ["com.google.Chrome", "com.microsoft.edgemac", "com.vivaldi.Vivaldi"].contains(app) else { return .definiteFailure("Profile selection is unsupported for this browser") }
            let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support").appendingPathComponent(subpath)
            let exists = await Task.detached { (try? ChromiumProfiles.existingDirectory(profile, root: root)) != nil }.value
            guard exists else { return .definiteFailure("Selected profile is missing or inaccessible") }
        }
        return await withCheckedContinuation { continuation in
            let pending = PendingLaunch(continuation)
            pending.timer = Task { try? await Task.sleep(nanoseconds: 10_000_000_000); if !Task.isCancelled { pending.finish(.uncertain) } }
            let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
            let callback: @Sendable (NSRunningApplication?, Error?) -> Void = { _, error in Task { @MainActor in pending.finish(error == nil ? .handedOff : .definiteFailure("Browser rejected launch request")) } }
            if let profile {
                configuration.createsNewApplicationInstance = true
                configuration.arguments = ["--profile-directory=\(profile)", "--ignore-profile-directory-if-not-exists", "--new-window", url.absoluteString]
                NSWorkspace.shared.openApplication(at: application, configuration: configuration, completionHandler: callback)
            } else { NSWorkspace.shared.open([url], withApplicationAt: application, configuration: configuration, completionHandler: callback) }
        }
    }
}
@MainActor private final class PendingLaunch {
    var continuation: CheckedContinuation<LaunchResult, Never>?
    var timer: Task<Void, Never>?
    init(_ c: CheckedContinuation<LaunchResult, Never>) { continuation = c }
    func finish(_ result: LaunchResult) { guard let c = continuation else { return }; continuation = nil; timer?.cancel(); timer = nil; c.resume(returning: result) }
}
