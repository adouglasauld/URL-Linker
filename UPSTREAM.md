# Upstream baseline

Downloaded Junction source: https://github.com/jnahian/junction
Commit: 2e3ba19882a0aa2ddb79b0f26ff6e3324eaff3a5.
This is an independently created repository, not a GitHub fork. Upstream history and MIT attribution are retained. The local assessment checkout reference/Junction remains untouched.

Retained and adapted: Foundation routing/configuration/JSONC/file watcher/wildcard engine, browser discovery and dispatcher, resource loading and Core/MacKit regression suites. GUI target is a standalone SwiftUI/AppKit implementation in Sources/URLLinker. Upstream old GUI/CLI sources remain as excluded reference code; neither is compiled or shipped. Sparkle/ArgumentParser are not target dependencies. Cloud mirror source remains for its upstream regression tests; the executable never instantiates it.

Jira source was inspected as an algorithm reference. The bounded metadata reader and profile argv adapter were independently implemented here rather than copying Jira application source. Bundle identifiers/profile roots and documented launch arguments are used as interoperability facts. Junction MIT notice is preserved and included in the app bundle.
