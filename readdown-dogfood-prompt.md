# Readdown v1.6 — Clean Install Dogfood Test

You are dogfooding **Readdown**, a read-only Markdown reader for macOS. The goal is to test every feature exactly as a first-time user would, starting from a fresh download. The source repo is at `~/Dev/Readdown` but **do not build from source** — we're testing the released binary.

## Phase 0: Clean Slate

Remove any existing Readdown installation and state so we start fresh:

```bash
# Quit Readdown if running
osascript -e 'quit app "Readdown"' 2>/dev/null

# Remove the app from Applications
rm -rf /Applications/Readdown.app

# Also check and remove from user Applications
rm -rf ~/Applications/Readdown.app

# Clear all stored preferences and state
defaults delete com.nataliarsand.ReadDown 2>/dev/null

# Clear Quick Look cache so the extension re-registers
qlmanage -r cache 2>/dev/null
qlmanage -r 2>/dev/null

# Remove any leftover Quick Look extension registration
pluginkit -e ignore -i com.nataliarsand.ReadDown.ReadDownQuickLook 2>/dev/null
```

Verify the slate is clean:
- `ls /Applications/ | grep -i readdown` should return nothing
- `defaults read com.nataliarsand.ReadDown 2>&1` should say "domain does not exist"

## Phase 1: Download & Install

1. Download the DMG from the latest GitHub release:
   ```bash
   cd ~/Downloads
   curl -L -o Readdown.dmg https://github.com/nataliarsand/readdown/releases/latest/download/Readdown.dmg
   ```

2. Mount the DMG and copy to Applications:
   ```bash
   hdiutil attach Readdown.dmg
   cp -R /Volumes/Readdown/Readdown.app /Applications/
   hdiutil detach /Volumes/Readdown
   ```

3. Verify the app is signed and notarized:
   ```bash
   codesign -vvv /Applications/Readdown.app
   spctl --assess --verbose /Applications/Readdown.app
   ```
   Both should pass with no errors.

4. Check the version matches 1.6:
   ```bash
   defaults read /Applications/Readdown.app/Contents/Info.plist CFBundleShortVersionString
   ```

## Phase 2: Create Test Markdown Files

Create a comprehensive test file that exercises ALL rendering features. Save it to a temp location:

```bash
mkdir -p /tmp/readdown-test
```

Create `/tmp/readdown-test/full-test.md` with content that tests:

- **Headings**: h1 through h6
- **Paragraphs**: Regular text with line breaks (trailing double spaces)
- **Bold**, *italic*, ***bold italic***, ~~strikethrough~~, `inline code`
- **Links**: regular `[text](url)`, mailto links
- **Images**: at least one with `![alt](url)` — use a small public image URL
- **Unordered lists**: with `-`, `*`, `+` markers, and nested items
- **Ordered lists**: with multi-line continuation
- **Task lists**: with `- [ ]` and `- [x]` items
- **Blockquotes**: including nested blockquotes (`> > nested`)
- **Code blocks**: fenced with triple backticks, with language specifiers for at least: `python`, `javascript`, `swift`, `bash`, `json`, `html`  — verify syntax highlighting renders for each
- **Tables**: with left, center, and right alignment using colons in the separator row
- **Horizontal rules**: `---`
- **Inline HTML**: e.g. `<mark>highlighted</mark>`, `<details><summary>...</summary>...</details>`
- **Edge cases**: Empty code blocks, deeply nested lists, tables with mismatched columns, very long lines

Also create separate test files:

- `/tmp/readdown-test/utf16-test.md` — save as UTF-16 encoding: `echo "# UTF-16 Test" | iconv -f UTF-8 -t UTF-16 > /tmp/readdown-test/utf16-test.md`
- `/tmp/readdown-test/latin1-test.md` — save as ISO-8859-1: `echo "# Café résumé naïve" | iconv -f UTF-8 -t ISO-8859-1 > /tmp/readdown-test/latin1-test.md`
- `/tmp/readdown-test/empty.md` — empty file: `touch /tmp/readdown-test/empty.md`
- `/tmp/readdown-test/large.md` — a large file (generate 1000+ lines of markdown with mixed content)
- `/tmp/readdown-test/security-test.md` — contains potentially unsafe links to verify they're blocked: `javascript:alert(1)`, `data:text/html,...`, `//protocol-relative.com`, `C:\windows\path`

## Phase 3: First Launch & Welcome Flow

1. Launch Readdown for the first time:
   ```bash
   open /Applications/Readdown.app
   ```

2. **Verify the Welcome window appears** with:
   - App icon
   - "Thanks for downloading Readdown!" message
   - "Open a .md File" button
   - Link to heya.studio/readdown/#setup (Quick Look troubleshooting)
   - Developer website link
   - PayPal donation link

3. **Verify the "Set as Default" prompt** appears shortly after:
   - An alert asking to set Readdown as the default .md reader
   - Click "Set as Default" and verify it registers:
     ```bash
     # After accepting, check the default handler
     duti -x md 2>/dev/null || echo "Install duti to check, or verify manually by right-clicking a .md file > Get Info > Open With"
     ```

4. **Verify Quick Look notification** appears ~3 seconds after launch:
   - Should show "Quick Look Previews Enabled" notification
   - The "Open Settings" button should open System Settings > Login Items & Extensions

5. Use the Welcome window's "Open a .md File" button to open `full-test.md`
   - Welcome window should close automatically

## Phase 4: Markdown Rendering Tests

With `full-test.md` open, verify each element renders correctly:

1. **Headings**: All 6 levels visible with proper sizing hierarchy. h1 and h2 should have underline borders.
2. **Inline formatting**: Bold, italic, bold-italic, strikethrough, inline code all render with correct styling.
3. **Links**: Clickable, open in system browser (not inside Readdown). Test by clicking one.
4. **Images**: Render inline, responsive (max-width 100%).
5. **Lists**: Proper indentation, nesting works, bullet styles correct.
6. **Task lists**: Checkboxes visible, checked items show blue checkbox with checkmark, boxes are NOT interactive (read-only).
7. **Code blocks**: Proper monospace font, background color, border radius. **Syntax highlighting active** — keywords, strings, comments should be color-coded for each language.
8. **Tables**: Headers bold, rows have alternating background, alignment (left/center/right) respected.
9. **Blockquotes**: Left border visible, nested blockquotes properly indented.
10. **Horizontal rules**: Visible divider line.
11. **Inline HTML**: `<mark>` renders as highlighted, `<details>` is collapsible.

## Phase 5: Dark Mode

1. Switch macOS to dark mode:
   ```bash
   osascript -e 'tell app "System Events" to tell appearance preferences to set dark mode to true'
   ```

2. Verify Readdown automatically switches:
   - Background changes to dark (#0d1117)
   - Text changes to light (#e6edf3)
   - Code blocks have dark background (#161b22)
   - Links are bright blue (#58a6ff)
   - Table stripe colors update
   - Syntax highlighting colors remain legible

3. Switch back to light mode:
   ```bash
   osascript -e 'tell app "System Events" to tell appearance preferences to set dark mode to false'
   ```

4. Verify everything switches back cleanly.

## Phase 6: File Encoding Tests

Open each encoding test file and verify it renders without errors:

```bash
open -a Readdown /tmp/readdown-test/utf16-test.md
open -a Readdown /tmp/readdown-test/latin1-test.md
open -a Readdown /tmp/readdown-test/empty.md
open -a Readdown /tmp/readdown-test/large.md
```

- UTF-16 file should render the heading correctly
- Latin-1 file should show accented characters (Café, résumé, naïve)
- Empty file should open without crashing (blank window)
- Large file should open without excessive delay (under 2 seconds)

## Phase 7: Security Tests

Open the security test file:
```bash
open -a Readdown /tmp/readdown-test/security-test.md
```

Verify:
- `javascript:` links are NOT clickable / do nothing
- `data:` URLs are blocked
- Protocol-relative URLs (`//`) are blocked
- Windows paths (`C:\...`) are blocked
- Regular `https://` links still work correctly

## Phase 8: Quick Look Preview

1. Navigate to the test files in Finder:
   ```bash
   open /tmp/readdown-test/
   ```

2. Select `full-test.md` in Finder and press **Space**

3. Verify Quick Look shows rendered markdown (not raw text):
   - Headings are styled
   - Code blocks have formatting
   - Tables render properly
   - Dark mode matches system appearance

4. Press Space again to dismiss.

5. Test Quick Look on other files: `utf16-test.md`, `empty.md`

If Quick Look shows raw text instead of rendered markdown, the extension isn't registered. Troubleshoot:
```bash
# Check if the Quick Look extension is registered
pluginkit -m -i com.nataliarsand.ReadDown.ReadDownQuickLook

# Reset Quick Look
qlmanage -r
qlmanage -r cache

# You may need to toggle the extension on in:
# System Settings > Login Items & Extensions > Extensions > Quick Look
```

## Phase 9: Auto-Update (Sparkle)

1. In Readdown's menu bar, go to **Readdown > Check for Updates...**
2. Verify the menu item exists and is clickable
3. Since we just installed v1.6 (the latest), it should report "You're up to date!" or similar
4. Verify the update check doesn't crash the app

You can also verify the appcast URL is reachable:
```bash
curl -s https://heya.studio/readdown/appcast.xml | head -20
```

## Phase 10: Edge Cases & Misc

1. **Read-only behavior**: Try File > Save or Cmd+S — should do nothing or show no save option (the app never writes to files).

2. **Multiple documents**: Open several .md files simultaneously — each should render in its own window.
   ```bash
   open -a Readdown /tmp/readdown-test/full-test.md /tmp/readdown-test/utf16-test.md /tmp/readdown-test/large.md
   ```

3. **Window minimum size**: Try resizing a window smaller than 500x400 — should stop at the minimum.

4. **File extensions**: Test all supported extensions:
   ```bash
   cp /tmp/readdown-test/full-test.md /tmp/readdown-test/test.markdown
   cp /tmp/readdown-test/full-test.md /tmp/readdown-test/test.mdown
   cp /tmp/readdown-test/full-test.md /tmp/readdown-test/test.mkd
   open -a Readdown /tmp/readdown-test/test.markdown
   open -a Readdown /tmp/readdown-test/test.mdown
   open -a Readdown /tmp/readdown-test/test.mkd
   ```

5. **Relaunch with no windows**: Quit and reopen — the Welcome window should appear again since `NSQuitAlwaysKeepsWindows` is false.

6. **About dialog**: Go to Readdown > About Readdown:
   - Should show version 1.6
   - Should show "Buy me a coffee" link
   - PayPal link should work

7. **External link handling**: Click an `https://` link in a rendered document — should open in the default browser, NOT in Readdown.

## Reporting

For each phase, report:
- **PASS** / **FAIL** / **PARTIAL** with details
- Screenshots of any failures
- Any crashes (check `~/Library/Logs/DiagnosticReports/` for crash logs)
- Performance notes (slow rendering, laggy scrolling, etc.)
- Any visual glitches

```bash
# Check for recent crash logs
ls -lt ~/Library/Logs/DiagnosticReports/ 2>/dev/null | grep -i readdown | head -5
```
