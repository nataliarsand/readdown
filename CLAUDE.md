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
- `heya-studio/build.sh` clones readdown-website at build time into `/readdown`
- GitHub webhook on readdown-website auto-triggers heya-studio redeploy
- To manually redeploy: push to readdown-website or push empty commit to heya-studio

## Performance & Reliability Principles
Readdown's core promise is "clean and fast." Every change must preserve this.

### No work in SwiftUI `body`
- `body` can be called many times by SwiftUI. Never do rendering, regex, or string building inside it.
- Compute expensive values in `init` or as stored properties. `body` should only compose views.

### No unbounded JS execution in WebKit
- **Never enable highlight.js auto-detection.** Always use `cssSelector` to restrict hljs to code blocks with explicit language classes. Auto-detection runs every bundled grammar and can cause catastrophic backtracking (the root cause of the 19.7GB RAM incident).
- Code blocks without a language specifier must get `class="nohighlight"`.
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

## License
- Source-available (not open source) — view/study/contribute allowed, redistribution prohibited
- See `LICENSE` file
