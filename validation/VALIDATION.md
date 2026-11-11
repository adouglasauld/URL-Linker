# Developer validation — 11 November 2026

Development checkpoint, not release certification. Automated suites are run by the implementation developer after the independent test developer authors them. Tests use temporary files and injected launch boundaries; no actual browser/default-handler changes are made.

## Build and tests

- Native debug app builds with no third-party runtime dependencies.
- Universal release bundle builds for arm64 and x86_64, macOS13 deployment target, with ad-hoc Hardened Runtime signature and strict signature verification in bundle script.
- Developer final `swift test` exited **0**: **160 XCTest tests passed** (130 Core + 30 MacKit), including **29 independently authored acceptance tests**. Logs: final-tests.log and package.log.
- Two final legacy fixture corrections explicitly select version1: ConfigStoreTests.testInvalidFileKeepsLastGood (clipboard fixture) and testUnknownDeepLinkTargetReported (deep-link fixture). Their assertions remain unchanged; v2 validation and all independent29 tests remain strict.
- Authoritative app staging path: `/private/tmp/URLLinker-artifacts/URL Linker.app`. Metadata-free deliverable: `app/dist/URL-Linker.zip`. Do not use the earlier workspace `.app`: Documents/FileProvider metadata can invalidate signatures there. Final staging strict signature verification and ZIP integrity check pass.
- Baseline attempt inside sandbox failed compiler-cache write permissions. Approved outside-sandbox compiler runs were then used. The initial upstream suite was run while independent acceptance tests were already added, so it is not represented as a pristine passing upstream baseline.
- Legacy tests for transformations, picker fallback and deep links explicitly use version1. Legacy dispatcher assertions changed only for intentional safe profile identity/failure behaviour and exact Jira argv. Independent acceptance assertions were not weakened.

## Implemented

Seven typed match modes, first-enabled-match ordering, stable rule UUID persistence, fallback profile, graphical rule editor and dry-run tester, installed browser/profile discovery using bounded confined Local State metadata, explicit argv profile launch, HTTP/HTTPS handler declarations and explicit system-default request, manual picker, bounded failed-link recovery, JSON import/export, v1 compatible browser-rule conversion with repair refusal, no updater/cloud execution, shared Core/MacKit regression suites.

Production BrowserLauncher uses a once-completed 10-second deadline with uncertain-result handling. Explicit configured fallback is attempted once only after definite failure. Regex is compiled with the routing snapshot; progress deadline stops evaluation and selects fallback instead of evaluating later rules. No assertion is made that ICU progress callbacks provide a hard wall-clock timeout.

## Outstanding specification and release gates

This is a runnable development build; the complete specification is not yet accepted. Remaining implementation gaps must stay visible:

- Exact prescribed version2 external JSON schema is not yet implemented: retained Junction field names/action models are used with typed match additions. Unknown keys are not strictly rejected. Configuration conflict revisions and backup-write errors need explicit handling; version-future read-only recovery enforcement needs completion.
- Regex worker isolation/hard responsiveness verification, total evaluation budget and precompiled typed wildcard/prefix strategies remain pending. Routing fallback on a soft regex timeout currently has no explicit trace reason in the UI.
- Per-browser launch serialization and asynchronous startup queue/backpressure are not yet implemented. Startup configuration read remains synchronous before event registration; cold-start concurrent event behaviour needs a real integration check.
- Rich discovery error states are not yet surfaced independently in GUI (missing/malformed/permission-denied metadata currently shares a status message). Profile metadata access without FDA has not been demonstrated on a clean account here.
- Undo registrations exist but need responder-chain integration and runtime acceptance. Rule copy/paste envelope, menu/context command coverage, larger-text/VoiceOver acceptance, login-item optional preference and polished recovery/quit-discard behaviour remain incomplete.
- Manual-picker keyboard behaviour and failure notification status item need native verification/refinement. The first Settings presentation may activate during first-ever URL launch.
- Chrome/Edge/Vivaldi stopped/running exact-profile tests, macOS13 runtime, clean-permission/privacy tests, real Launch Services registration/cold-start delivery and performance/idle measurements were not run. Historical Jira Vivaldi evidence is not claimed as URL Linker evidence.
- No distribution identity was supplied; Developer ID signing/notarization/stapling and clean-machine installation remain open.

No Full Disk Access or Accessibility permission requirement was introduced, but absence of such a requirement across supported systems remains a runtime acceptance gate. No test creates/removes real browser profiles or reads their contents.
