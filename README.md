# URL Linker

Development prerelease · macOS 13+ · Apple silicon and Intel

Download the ZIP from [Releases](https://github.com/adouglasauld/URL-Linker/releases), extract it and move **URL Linker.app** to Applications. This development build is ad-hoc signed and is not notarized. macOS may require an explicit Open action in Privacy & Security.

Set URL Linker as the default browser in General settings. macOS launches it when a link is opened; **launch at login is unnecessary and is not configured**. It remains in the menu bar after launching. With no rules, links open in the configured fallback (Safari by default).

Native macOS 13+ HTTP/HTTPS router adapted from Junction. Local configuration lives in `~/Library/Application Support/URL Linker/config.json`, separately from Junction.

Build: `swift build`. Test: `swift test`. Universal app: `./Scripts/bundle-app.sh` stages `/private/tmp/URLLinker-artifacts/URL Linker.app` and delivers `dist/URL-Linker.zip` (avoiding Documents metadata signature corruption). The bundle script ad-hoc signs by default; set CODESIGN_IDENTITY for an owner's signing identity. This development build is not notarized. Build toolchain used here: Xcode27.2 SDK; deployment target13.

Open the app, choose General → fallback browser/profile, configure Rules and use Test without launching. Make Default is an explicit user action. Closing Settings leaves the status item active. No default-browser changes, browser opens or privacy grants are performed by the automated suite. All launches specify a destination app; unmatched URLs use the exact fallback, including profile. A failed launch is held in Failed Links for explicit retry/copy/manual opening. An uncertain launch is never retried automatically.

Read validation/VALIDATION.md before treating this as a release. Source implementation and automated tests do not close the clean-account privacy/browser matrix or native accessibility/runtime gates.
