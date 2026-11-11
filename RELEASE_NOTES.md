# v0.1.1 — Safe Links routing

Rules now match the embedded destination of Microsoft Safe Links URLs. The browser still opens the original protected URL, preserving Microsoft click-time checks. All seven matcher types share the same destination; priority, fallback and manual override continue to work. Malformed, ambiguous and overly nested wrappers use fallback. No remote redirect fetching.

The dry-run tester shows the destination hostname used. Reopening the installed app now brings Settings forward. Existing rules, profiles, default-browser and login settings are preserved.

Validation: 171 automated tests pass, including 11 new Safe Links regression tests. Fixtures use synthetic URLs, not user tracking tokens. Universal arm64/x86_64, minimum macOS13. Ad-hoc signed development prerelease; not notarized. Remaining acceptance gaps are documented in validation/VALIDATION.md.

Microsoft reference: https://learn.microsoft.com/en-us/defender-office-365/safe-links-about
