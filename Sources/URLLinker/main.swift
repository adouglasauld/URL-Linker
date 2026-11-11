import AppKit
import SwiftUI
import Combine
import JunctionCore
import JunctionMacKit
import UniformTypeIdentifiers

struct FailedLink: Identifiable { let id = UUID(); let url: URL; let reason: String }
@MainActor final class Model: ObservableObject {
    let store = ConfigStore()
    @Published var config: Config
    @Published var browsers: [Browser] = []
    @Published var message = ""
    @Published var failed: [FailedLink] = []
    @Published var defaultStatus = ""
    @Published var testURL = ""
    @Published var testResult = ""
    let undo = UndoManager()
    var engine: RoutingEngine { RoutingEngine(config: config) }
    init() {
        config = store.config
        if let error = store.lastError { message = error.description }
        store.onChange = { [weak self] c in self?.config = c }
        store.onError = { [weak self] e in self?.message = e.description }
        store.bootstrapIfMissing(); store.startWatching(); refresh(); status()
    }
    func refresh() {
        Task {
            let list = await Task.detached { BrowserDiscovery.installedBrowsers() }.value
            browsers = list
        }
    }
    func save(_ c: Config) {
        do { let old = config; try store.save(c); config = c; message = ""; undo.registerUndo(withTarget: self) { target in MainActor.assumeIsolated { target.save(old) } } }
        catch { message = error.localizedDescription }
    }
    func test() {
        do { let url = try URLPolicy.validate(testURL); let trace = engine.trace(LinkEvent(url: url)); testResult = "\(trace.matchedRule.map { "Rule: \($0)" } ?? "Fallback") → \(destination(trace.decision))"
            if let matchURL = trace.matchingURL, matchURL != url { testResult += "\nMatched Safe Links destination: \(matchURL.host ?? ""). Original protected link will be opened." }
            else if trace.matchingURL == nil { testResult += "\nInvalid Safe Links destination; using fallback." } }
        catch { testResult = "Invalid HTTP/HTTPS URL" }
    }
    func destination(_ decision: RoutingDecision) -> String {
        switch decision { case .open(let app, let profile, _): return app + (profile.map { " / \($0)" } ?? "")
        case .fallback(let app, _): return app
        default: return "Unsupported imported action" }
    }
    func route(_ url: URL, manual: Bool = false) {
        guard (try? URLPolicy.validate(url.absoluteString)) != nil else { message = "Unsupported URL"; return }
        if manual { picker(url); return }
        let decision = engine.route(LinkEvent(url: url))
        let fallback = config.fallback
        let target: (String, String?)
        switch decision {
        case .open(let app, let profile, _): target = (app, profile)
        case .fallback(let app, _): target = (app, fallback.profile)
        default: retain(url, reason: "Unsupported automatic action"); return
        }
        Task {
            let launcher = BrowserLauncher()
            let first = await launcher.launch(url: url, app: target.0, profile: target.1)
            switch first {
            case .handedOff: break
            case .uncertain: retain(url, reason: "May have opened; no automatic retry")
            case .definiteFailure(let reason):
                if target.0 == fallback.app && target.1 == fallback.profile { retain(url, reason: reason); return }
                let result = await launcher.launch(url: url, app: fallback.app, profile: fallback.profile)
                switch result { case .handedOff: message = "Used configured fallback: " + reason
                case .uncertain: retain(url, reason: "Fallback may have opened; no automatic retry")
                case .definiteFailure(let fallbackReason): retain(url, reason: reason + "; " + fallbackReason) }
            }
        }
    }

    func retain(_ url: URL, reason: String) {
        if failed.count < 100 { failed.append(FailedLink(url: url, reason: reason)) }
        else { message = "Failure queue full. This URL was rejected: \(url.absoluteString)" }
    }
    func status() {
        defaultStatus = ["http", "https"].map { scheme in
            let current = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "\(scheme)://example.invalid")!)
            return "\(scheme.uppercased()): \(current == Bundle.main.bundleURL ? "URL Linker" : "another application")"
        }.joined(separator: " · ")
    }
    func makeDefault() {
        guard browsers.contains(where: { $0.bundleID == config.fallback.app }) else { message = "Choose an installed fallback first"; return }
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "http") { _ in
            NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "https") { _ in Task { @MainActor in self.status() } }
        }
    }
    func picker(_ url: URL) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 450, height: 240), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Open URL Manually"; panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ManualPicker(model: self, url: url, close: { panel.close() }))
        panel.center(); panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        panels.append(panel)
    }
    private var panels: [NSPanel] = []
    func importConfig() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var c = try ConfigStore.load(from: url)
            if c.version == 1 {
                guard !c.fallback.isPicker, c.enabledRewriters.isEmpty, c.customRewriters.isEmpty else { message = "Import requires repair: picker fallback or rewrites unsupported. Source unchanged."; return }
                var migrated: [Rule] = []
                for original in c.rules {
                    guard original.match.sourceApps.isEmpty, original.rewrite == nil, case .open(let app, let profile) = original.action else { message = "Unsupported source-app condition or action in \(original.name). Source unchanged."; return }
                    var directory: String? = profile
                    if let profile, !ProfileDirectory.isValid(profile) {
                        let matches = browsers.first(where: { $0.bundleID == app })?.profiles.filter { $0.displayName == profile } ?? []
                        guard matches.count == 1 else { message = "Resolve ambiguous/unavailable profile for \(original.name) before import."; return }
                        directory = matches[0].directory
                    }
                    var conditions = original.match.patterns.map { Match(kind: .wildcard, value: $0) }
                    if let regex = original.match.regex { conditions.append(Match(kind: .regex, value: regex)) }
                    guard !conditions.isEmpty else { message = "Rule has no supported matcher: \(original.name)"; return }
                    for condition in conditions { migrated.append(Rule(name: original.name, notes: original.notes, enabled: original.enabled, match: condition, action: .open(app: app, profile: directory))) }
                }
                c = Config(version: 2, fallback: c.fallback, stripTrackingParams: false, rules: migrated)
            }
            let alert = NSAlert(); alert.messageText = "Replace configuration?"; alert.informativeText = "Import \(c.rules.count) rules. Current configuration has a local backup."; alert.addButton(withTitle: "Import"); alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn { save(c) }
        } catch { message = error.localizedDescription }
    }
    func exportConfig() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "config.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(config).write(to: url, options: .atomic) } catch { message = error.localizedDescription }
    }
}

struct DestinationPicker: View {
    let browsers: [Browser]
    @Binding var app: String
    @Binding var profile: String
    var body: some View {
        Picker("Browser", selection: $app) {
            if !browsers.contains(where: { $0.bundleID == app }) { Text(app.isEmpty ? "Choose Browser" : app + " (unavailable)").tag(app) }
            ForEach(browsers) { browser in Text(browser.name).tag(browser.bundleID) }
        }.onChange(of: app) { _ in profile = "" }
        Picker("Profile", selection: $profile) {
            Text("Use browser default profile").tag("")
            if !profile.isEmpty && !(browsers.first(where: { $0.bundleID == app })?.profiles.contains(where: { $0.directory == profile }) ?? false) { Text(profile + " (unavailable)").tag(profile) }
            ForEach(browsers.first(where: { $0.bundleID == app })?.profiles ?? []) { p in Text("\(p.displayName) — \(p.directory)").tag(p.directory) }
        }
    }
}
struct ManualPicker: View {
    @ObservedObject var model: Model
    let url: URL
    let close: () -> Void
    @State private var app = "com.apple.Safari"
    @State private var profile = ""
    var body: some View {
        Form { Text(url.absoluteString).lineLimit(2).textSelection(.enabled)
            DestinationPicker(browsers: model.browsers, app: $app, profile: $profile)
            HStack { Button("Cancel", action: close).keyboardShortcut(.cancelAction); Spacer(); Button("Open") {
                let selectedApp = app; let selectedProfile = profile.isEmpty ? nil : profile
                Task { let result = await BrowserLauncher().launch(url: url, app: selectedApp, profile: selectedProfile)
                    switch result { case .handedOff: break; case .uncertain: model.retain(url, reason: "May have opened"); case .definiteFailure(let reason): model.retain(url, reason: reason) }
                }; close()
            }.keyboardShortcut(.defaultAction) }
        }.padding()
    }
}
struct RuleDraft: Identifiable { var id: UUID { rule.id }; var rule: Rule }
struct Editor: View {
    @ObservedObject var model: Model
    let initial: Rule
    let finish: (Rule?) -> Void
    @State private var name = ""
    @State private var kind = MatchKind.exactHost
    @State private var value = ""
    @State private var app = "com.apple.Safari"
    @State private var profile = ""
    @State private var enabled = true
    private var rule: Rule { Rule(id: initial.id, name: name, enabled: enabled, match: Match(kind: kind, value: value), action: .open(app: app, profile: profile.isEmpty ? nil : profile)) }
    private var problems: [String] { ConfigStore.validate(Config(fallback: model.config.fallback, rules: [rule])) }
    var body: some View {
        Form {
            TextField("Name", text: $name); Toggle("Enabled", isOn: $enabled)
            Picker("Match", selection: $kind) { ForEach(MatchKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            TextField("Value", text: $value)
            Text(kind == .subdomainsOnly ? "Matches nested subdomains, excluding the parent." : kind == .wildcard ? "Junction wildcard: *.example.com includes the parent; query is ignored." : "First enabled matching rule wins.").font(.caption)
            DestinationPicker(browsers: model.browsers, app: $app, profile: $profile)
            if let problem = problems.first { Text(problem).foregroundStyle(.red) }
            HStack { Button("Cancel") { finish(nil) }.keyboardShortcut(.cancelAction); Spacer(); Button("Save") { finish(rule) }.disabled(!problems.isEmpty).keyboardShortcut(.defaultAction) }
        }.padding().frame(width: 550).onAppear {
            name = initial.name; kind = initial.match.kind ?? .wildcard; value = initial.match.value ?? initial.match.patterns.first ?? ""; enabled = initial.enabled
            if case .open(let a, let p) = initial.action { app = a; profile = p ?? "" }
        }
    }
}
struct SettingsView: View {
    @ObservedObject var model: Model
    @State private var selected: UUID?
    @State private var draft: RuleDraft?
    @State private var fallback = "com.apple.Safari"
    @State private var fallbackProfile = ""
    var body: some View {
        TabView {
            VStack {
                List(selection: $selected) {
                    ForEach(model.config.rules) { r in
                        HStack { Image(systemName: r.enabled ? "checkmark.circle" : "pause.circle"); VStack(alignment: .leading) { Text(r.name); Text("\(r.match.kind?.rawValue ?? "wildcard"): \(r.match.value ?? r.match.patterns.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary) }; Spacer(); if case .open(let app, let profile) = r.action { Text(app + (profile.map { " / \($0)" } ?? "")).font(.caption) } }.tag(r.id)
                    }.onMove { source, target in var c = model.config; c.rules.move(fromOffsets: source, toOffset: target); model.save(c) }
                }
                HStack {
                    Button("Add") { draft = RuleDraft(rule: Rule(name: "New Rule", match: Match(kind: .exactHost, value: "example.com"), action: .open(app: model.config.fallback.app, profile: nil))) }.keyboardShortcut("n")
                    Button("Edit") { if let r = model.config.rules.first(where: { $0.id == selected }) { draft = RuleDraft(rule: r) } }.disabled(selected == nil)
                    Button("Duplicate") { if var r = model.config.rules.first(where: { $0.id == selected }) { r.id = UUID(); r.name += " Copy"; var c = model.config; c.rules.append(r); model.save(c) } }.disabled(selected == nil)
                    Button("Delete") { var c = model.config; c.rules.removeAll { $0.id == selected }; model.save(c) }.disabled(selected == nil)
                    Button("Enable/Disable") { if let i = model.config.rules.firstIndex(where: { $0.id == selected }) { var c = model.config; c.rules[i].enabled.toggle(); model.save(c) } }.disabled(selected == nil)
                    Button("Up") { move(-1) }.disabled(selected == nil); Button("Down") { move(1) }.disabled(selected == nil)
                }
                Divider()
                HStack { TextField("Test HTTP/HTTPS URL", text: $model.testURL).onSubmit { model.test() }; Button("Test") { model.test() }; Button("Open Manually…") { if let url = try? URLPolicy.validate(model.testURL) { model.picker(url) } } }
                Text(model.testResult).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.padding().tabItem { Text("Rules") }
            VStack(alignment: .leading) { Button("Refresh Browsers") { model.refresh() }; List(model.browsers) { b in VStack(alignment: .leading) { Text(b.name + " — " + b.bundleID); ForEach(b.profiles) { p in Text("\(p.displayName) — \(p.directory)").font(.caption) }; if b.profiles.isEmpty { Text("No profiles available; browser may be uninitialized or metadata inaccessible.").font(.caption) } } } }.padding().tabItem { Text("Browsers") }
            Form {
                Text(model.defaultStatus); Button("Make Default…") { model.makeDefault() }; Button("Refresh Status") { model.status() }
                DestinationPicker(browsers: model.browsers, app: $fallback, profile: $fallbackProfile)
                Button("Save Fallback") { var c = model.config; c.fallback = Fallback(app: fallback, profile: fallbackProfile.isEmpty ? nil : fallbackProfile); model.save(c) }
                HStack { Button("Import…") { model.importConfig() }; Button("Export…") { model.exportConfig() } }
                Text("URL Linker routes locally. No account, cloud sync, telemetry, Accessibility automation or automatic updates.")
                Text("Junction © 2026 Nahian — MIT. Complete notice is included in the app Resources.")
            }.padding().tabItem { Text("General") }
            List(model.failed) { failure in VStack(alignment: .leading) { Text(failure.reason); Text(failure.url.absoluteString).textSelection(.enabled); HStack { Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(failure.url.absoluteString, forType: .string) }; Button("Retry") { model.route(failure.url) }; Button("Open Manually…") { model.picker(failure.url) }; Button("Dismiss") { model.failed.removeAll { $0.id == failure.id } } } } }.tabItem { Text("Failed Links (\(model.failed.count))") }
        }.frame(minWidth: 760, minHeight: 520).overlay(alignment: .bottom) { if !model.message.isEmpty { Text(model.message).padding(8).background(.regularMaterial).textSelection(.enabled) } }
        .onAppear { fallback = model.config.fallback.app; fallbackProfile = model.config.fallback.profile ?? "" }
        .sheet(item: $draft) { d in Editor(model: model, initial: d.rule) { result in if let r = result { var c = model.config; if let i = c.rules.firstIndex(where: { $0.id == r.id }) { c.rules[i] = r } else { c.rules.append(r) }; model.save(c) }; draft = nil } }
    }
    private func move(_ amount: Int) { guard let i = model.config.rules.firstIndex(where: { $0.id == selected }), model.config.rules.indices.contains(i + amount) else { return }; var c = model.config; c.rules.swapAt(i, i + amount); model.save(c) }
}
@MainActor final class Delegate: NSObject, NSApplicationDelegate {
    var model: Model!; var window: NSWindow!; var item: NSStatusItem!
    func applicationWillFinishLaunching(_ notification: Notification) {
        model = Model()
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(receive(_:reply:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        let menu = NSMenu(); let app = NSMenu(); let top = NSMenuItem(); top.submenu = app; menu.addItem(top)
        app.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ","); app.addItem(withTitle: "Quit URL Linker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenu(title: "Edit"); for (title, action, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] { edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key) }; let e = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); e.submenu = edit; menu.addItem(e); NSApp.mainMenu = menu
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 620), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "URL Linker Settings"; window.isReleasedWhenClosed = false; window.setFrameAutosaveName("URLLinkerSettings"); window.contentView = NSHostingView(rootView: SettingsView(model: model))
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength); item.button?.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "URL Linker")
        let menu = NSMenu(); menu.addItem(withTitle: "Settings / Test URL…", action: #selector(settings), keyEquivalent: ","); menu.addItem(withTitle: "Quit URL Linker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); item.menu = menu
        if !UserDefaults.standard.bool(forKey: "hasOpenedSettings") { settings(); UserDefaults.standard.set(true, forKey: "hasOpenedSettings") }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { settings(); return true }
    @objc func settings() { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func receive(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue, let url = try? URLPolicy.validate(text) else { model.message = "Rejected invalid or unsupported URL"; return }
        model.route(url, manual: NSEvent.modifierFlags.contains(.option))
    }
}
MainActor.assumeIsolated { let app = NSApplication.shared; let delegate = Delegate(); app.delegate = delegate; app.setActivationPolicy(.accessory); app.run() }
