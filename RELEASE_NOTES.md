# v0.1.0 — development prerelease

Native macOS HTTP/HTTPS router adapted from Junction. Includes seven match modes, ordered rules, browser/profile routing, explicit fallback, graphical editor, dry-run tester and manual override. Chrome, Edge and Vivaldi profile adapters use fixed directory identities and bounded metadata reads. No cloud account, updater or login-startup requirement.

Universal arm64/x86_64 build, minimum macOS 13. Ad-hoc signed; not Developer ID signed or notarized.

Validation: 160 automated tests passed, including 29 independent acceptance tests. See validation/VALIDATION.md for remaining implementation gaps and unverified real-browser, permission and macOS 13 runtime checks. This is not a production-ready release.

Junction copyright and complete MIT notice are retained in LICENSE and bundled Resources.
