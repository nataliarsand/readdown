# Readdown

A clean, fast Markdown reader for macOS. Document-based SwiftUI app with Quick Look extension.

## Project Structure
- `ReadDownApp.swift` — App entry point, welcome flow, about panel
- `ContentView.swift` — Main document view (WKWebView)
- `MarkdownRenderer.swift` — Markdown-to-HTML renderer
- `HTMLTemplate.swift` — GitHub-style HTML/CSS template with dark mode
- `ReadDownQuickLook/` — Quick Look preview extension (appex)
- `scripts/release.sh` — Build, sign, notarize, DMG release pipeline

## Developer Credentials
- Apple ID: nataliarsand@gmail.com
- Team ID: 8NLGURB6UX
- Keychain profile for notarization: "Readdown"
- Store credentials: `xcrun notarytool store-credentials "Readdown" --apple-id nataliarsand@gmail.com --team-id 8NLGURB6UX`

## Release
- `./scripts/release.sh` — full release with notarization
- `./scripts/release.sh --skip-notarize` — skip notarization for local testing
- GitHub release: `gh release create vX.Y --title "Readdown X.Y" release/Readdown.dmg`

## Website
- Repo: `~/Dev/readdown-website` (GitHub: nataliarsand/readdown-website)
- Live: https://heya.studio/readdown/
- Hosted via Cloudflare Pages on the `heya-studio` project (`~/Dev/heya-studio`)
- **heya-studio serves the site directly** — readdown content lives in `heya-studio/readdown/`
- readdown-website is the source of truth but does NOT auto-deploy — changes must be copied to heya-studio and pushed there
- Appcast must be updated in BOTH repos: `readdown-website/readdown/appcast.xml` AND `heya-studio/readdown/appcast.xml`

## Performance & Reliability Principles
Readdown's core promise is "clean and fast." Every change must preserve this.

### No work in SwiftUI `body`
- `body` can be called many times by SwiftUI. Never do rendering, regex, or string building inside it.
- Compute expensive values in `init` or as stored properties. `body` should only compose views.

### No unbounded JS execution in WebKit
- **Never run highlight.js against all bundled grammars.** Use the `languages` config to restrict auto-detection to a curated subset of ~19 common languages. Full auto-detection against all ~35 grammars caused catastrophic backtracking (19.7GB RAM incident).
- Code blocks with an explicit language tag use that grammar directly. Bare code blocks run safe auto-detection against the curated subset.
- When adding new JS libraries (e.g., Mermaid), evaluate their CPU/memory behavior on large inputs before shipping.

### Pre-compile regex patterns
- All `NSRegularExpression` patterns must be compiled once as module-level constants — never inside loops or frequently called functions.
- Prefer simple string operations (`hasPrefix`, `contains`) over regex when the pattern is trivial.

### WKWebView is read-only
- The document never changes after load. `updateNSView` should be a no-op — never compare or reload the full HTML string (which includes ~200KB of embedded highlight.js).
- HTML is computed once in `ContentView.init` and loaded once in `makeNSView`.

### Rendering safety
- Every block parser in `MarkdownRenderer.render()` must advance the line index `i`. A block that fails to advance `i` creates an infinite loop.
- Fenced code blocks must handle missing closing fences (consume to EOF).
- The `replacing` helper must build results in a single forward pass — never mutate a string using ranges from the original (they become invalid after replacement).

## Release Mindset
Readdown has real users with auto-updates. Every release goes straight to their machines.

- **"Works on my machine" is not enough.** Always think from the perspective of a user downloading for the first time or receiving an auto-update. The dev machine has stale state, debug builds, old bundle IDs, and cached preferences that hide real issues.
- **Ship fixes and features separately.** If a user reports a problem after an update, you need to know if it's the fix or the new feature. Never mix them.
- **Test the release artifact, not the debug build.** Run `release.sh --skip-notarize`, mount the DMG, and test from there. The debug build in DerivedData is not what users get.
- **Verify the update pipeline end-to-end.** After pushing an appcast, `curl` the live URL to confirm it updated. Cloudflare caching and stale repos have caused silent failures before.
- **Bump version before building.** Sparkle compares build numbers. If you rebuild without bumping, existing users won't see the update.

## License
- Source-available (not open source) — view/study/contribute allowed, redistribution prohibited
- See `LICENSE` file
