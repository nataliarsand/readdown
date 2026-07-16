# Changelog

Each version's **Highlights** block is what appears in the in-app update dialog. Keep it to ~5 short bullets grouped under `### New` / `### Fixed`. Everything below **Details** is full notes for GitHub / readdown.app.

## 1.16

### New
- **Math rendering** — inline (`$x^2$` or `\(x^2\)`) and display-block (`$$...$$` or `\[...\]`) TeX equations, fully offline
- Collapsible headings: fold a section away with the chevron in the margin
- Links to another local Markdown file now reveal the target in Finder

### Fixed
- Sharper Markdown: nested and mixed lists, setext headings, reference links and images, and clickable bare URLs
- Display math on the line right after a paragraph now renders as its own block
- Stronger handling of raw HTML inside documents

### Details

_Readdown 1.16 is sponsored by [Eixo](https://eixo.design). Make better product decisions and build with confidence in the age of AI._

**New**

- TeX math rendering via a bundled KaTeX (fonts embedded, fully offline). Math is detected and stashed before Markdown processing begins, so underscores and asterisks inside expressions are never treated as emphasis delimiters. Dollar amounts in prose (`$5` and `$10`) are not mistaken for math.
  - Inline syntax: `$x^2$` or `\(x^2\)`
  - Display (block) syntax: `$$\int_0^1 f(x)\,dx$$` (on its own line) or a `\[...\]` block
  - Renders correctly inside blockquotes
  - Graceful fallback: if a TeX expression fails to parse, the raw source is shown in a monospace font rather than crashing
- Collapsible headings (issue #11). Every heading gets a small chevron in the left margin; click it (or the heading) to fold the section beneath it. Subtle by default and out of the way until you reach for it.
- Following a relative link to another local `.md` or text file reveals it in Finder, so you can open it from there. (Readdown is sandboxed and can't open a sibling file you never selected, so it surfaces the target instead.)

**Fixed**

- Lists are more faithful: nested ordered lists, mixed bullet-and-number nesting, and loose items (blank line between them) all render with the right structure.
- Setext headings: a line underlined with `===` becomes an H1 and one underlined with `---` becomes an H2.
- Reference-style links and images (`[text][ref]`, `![alt][ref]`, and the collapsed/shortcut forms) now resolve, and links and images accept an optional title.
- Bare URLs in text (`https://example.com`) become clickable links, with trailing sentence punctuation left outside the link.
- Backslash escapes (`\*`, `\_`, `\[`, and the rest) render as literal characters instead of formatting.
- A display-math block (`$$...$$`) on the line immediately after a paragraph, with no blank line between them, now splits into its own centered equation instead of being pulled into the paragraph.
- A thematic break (`***` or `---`) directly under a list, with no blank line, now closes the list and draws a rule instead of being folded into the last item.
- Copying the document reflects the file on disk even after a whitespace-only change.
- Raw HTML passed through from a document is now governed by an allowlist of safe tags and attributes, so ordinary formatting still works while scripts and inline event handlers are neutralized.

**Thanks**

- @adivijaykumar for the math rendering contribution (issue #13, PR #14).

## 1.15

### New
- A cleaner reading view with a floating header: the file name and quick actions (copy, find, show in Finder) tuck into the title bar
- Copy the whole document, or any single code block, to the clipboard in one click
- Optional, anonymous usage stats to guide what gets improved, off unless you opt in

### Fixed
- Opening a file no longer reopens your entire previous session on top of it
- Mermaid diagrams re-theme instantly on light and dark switch, and printing or exporting to PDF from dark mode now comes out light
- Ordered lists keep their starting number, and bold or italic spanning a wrapped line inside a list item now render (issues #15, #16)

### Details

**New**

- A redesigned window with a floating header. The file name sits in its own pill next to the traffic lights, and a matching pill holds Copy to Clipboard, Find, and Show in Finder. The title bar is transparent so the document reads full width, with a soft blur under the header as you scroll. Show in Finder is also in the File menu and on ⇧⌘R.
- Copy to Clipboard copies the document's full Markdown source, with a checkmark to confirm. Every fenced code block gets its own copy button on hover.
- A redesigned About window with links to leave feedback, report a bug, or support the project.
- Optional usage stats. If you opt in, through a one-time prompt or the Help menu, Readdown sends an anonymous daily count of which features you use, along with the app and macOS version. There are no identifiers of any kind, and your documents never leave your Mac. It is off unless you say yes, and you can change your mind anytime in the Help menu.

**Fixed**

- Opening a file at launch now shows just that file. The app could previously restore your entire previous session first, burying the file you opened underneath it. Launching without a file, from the Dock or after an update, still restores your open documents.
- Mermaid diagrams re-theme the moment the system appearance changes, instead of staying in the old palette until the document is reopened.
- Printing and exporting to PDF from dark mode now produce light pages, so paper no longer inherits the dark theme (Mermaid diagrams especially, whose colors are baked into the diagram).
- Ordered lists starting at a number other than 1 (such as `2.`) now keep that start number instead of renumbering from 1 (issue #16).
- Inline bold and italic that span a wrapped line inside a list item now render, the same way they already did in paragraphs (issue #15).

**Thanks**

- @jantomec for the code-block copy button (PR #12).
- @troelskn for reporting the ordered-list and wrapped-emphasis issues (#15, #16).

## 1.14.1

### Fixed
- Heading anchor links now match GitHub's slug convention for headings with stripped punctuation (e.g. `# Foo — bar` produces `foo--bar`, not `foo-bar`), so anchor links from GitHub-style TOCs scroll to the right place

### Details

**Fixed**

- `# Foo — bar` and similar headings (with whitespace-surrounded punctuation that gets stripped) now produce GitHub-compatible slugs. The previous slug generator collapsed runs of whitespace into a single hyphen; GitHub converts each whitespace character individually, preserving consecutive hyphens. Without this fix, `[link](#foo--bar)` from a TOC silently failed to scroll.

**Thanks**

- @ReubenCowell — first-time contributor, caught and reported (PR #10).

## 1.14

### Fixed
- Documents with a paragraph line beginning with `#` followed by a digit (e.g. `#24`) no longer freeze the app (issue #8)
- Fenced code blocks inside list items render as real code blocks again (issue #9)
- Heading anchor links (`#section`) inside a document scroll to the target instead of being silently cancelled
- Underscores inside words (`snake_case`, `lots_of_underscores`) are no longer mistaken for italic/bold delimiters
- Mermaid diagrams in dark mode are legible again — every text label now picks up the dark theme
- Readdown no longer hangs at launch when the previous session's documents have moved or been deleted

### Details

**Fixed**

- Renderer no longer hangs on a paragraph line that starts with `#` immediately followed by a non-space character (issue #8). The paragraph collector previously rejected those lines on a bare `#`-prefix check while the heading parser rejected them for lacking a space — leaving the renderer with no branch that could claim the line. A defensive guard now also catches any future no-advance regression rather than risk a freeze.
- Fenced code blocks indented under a list item are recognized again and render as `<pre><code>` blocks inside the list item (issue #9). They had been silently absorbed into the surrounding prose because the continuation parser only checked for fences at column zero.
- Clicking a heading anchor link inside an open document now scrolls to the heading instead of being cancelled. The same-document check has been relaxed to tolerate the two real shapes the loader produces (an `about:blank` page URL for untitled docs and a trailing-slash mismatch for saved docs) while still routing external links with fragments to the system browser.
- Intra-word underscores stay literal. The underscore emphasis patterns now require word-boundary flanking (CommonMark §6.2), so `snake_case` identifiers, `lots_of_underscores_in_names`, and `some__double__underscores` render as plain text instead of italicising or bolding fragments of the word. Asterisk emphasis (`*italic*`, `**bold**`) is unchanged.
- Mermaid diagrams render correctly in dark mode. The previous detection (`window.matchMedia('(prefers-color-scheme: dark)')`) can return the wrong answer inside WKWebView — leaving every Mermaid diagram in its light palette on a dark page (invisible edge labels, dark-on-dark sequence messages, dark-on-dark pie chart legends). A luminance-based fallback now also checks the page's resolved background colour, so dark mode is reliably detected on screen.
- Readdown no longer hangs at launch when the previous session's saved documents have been moved or deleted (e.g. after a force-quit, sudden power off, or Time Machine restore). Two restoration mechanisms — Readdown's own and AppKit's automatic one — had been racing at launch; AppKit's path has no file-existence guard, so a stale doc reference could deadlock the app indefinitely. AppKit's redundant path is now disabled.

**Thanks**

- Issues #8 and #9 were reported by @troelskn — thank you.

## 1.13

### Fixed
- Code spans render exactly as written — underscores, asterisks, and HTML tags inside backticks stay literal
- Nested bullet lists render correctly
- Markdown files saved with a UTF-8 byte-order mark open cleanly
- Refined task-list checkboxes
- Mermaid diagrams use a refreshed theme that reads well in both light and dark mode

### Details

**Fixed**

- Inline code spans now render their content fully verbatim. Characters that would normally be interpreted as Markdown (underscores, asterisks) or as HTML (`<div>`, `<em>`, etc.) stay as plain text inside the code style. This also resolves a cascading bold/italic effect that could appear later in a document when a code span contained an HTML tag.
- Nested bullet lists now render inside the parent list item instead of as a sibling list — correct nesting and spacing.
- Files saved with a UTF-8 byte-order mark open cleanly. A first-line heading is recognized as a heading, not as paragraph text starting with an invisible character.
- Task-list checkboxes use a centered SVG checkmark and tighter label spacing.
- Mermaid diagrams: refreshed theme variables for both modes — edge labels (Yes/No) sit on a solid background that matches the document, arrows and text are tuned per mode for contrast, and the pie chart palette is high-contrast so small slices stay legible (issue #7).

**Under the hood**

- Update checks now send anonymous system info (macOS version, Mac model, CPU type) — no identifiers, no personal data — so we know which macOS versions to keep supporting.

## 1.12

### New
- Refreshed typography — warmer text, a cleaner heading scale, and restyled links and tables
- Linkable headings — every heading gets an anchor, so in-page `#section` links jump and scroll

### Fixed
- Quick Look previews no longer hang on a loading spinner on some recent macOS builds
- Open documents now reliably reappear after an update or relaunch

### Details

**New**

- Typography pass: warmer body text on a softer off-white background, a modular heading scale with balanced spacing, an always-on subtle link underline, and restyled tables. Dark-mode secondary text was brightened to meet WCAG AA contrast.
- Linkable headings: every heading now has a GitHub-style anchor (e.g. `getting-started`), so links to `#section` within a document jump to and smoothly scroll to the heading.

**Fixed**

- Quick Look: the preview extension relied on a private WebKit setting that some recent macOS builds no longer recognize, which left the preview stuck on a loading spinner. It has been removed — previews render reliably again.
- Documents that were open are now restored correctly after a Sparkle auto-update or relaunch; a timing issue that could drop the saved session on quit was fixed.

## 1.11

### New
- Live refresh — documents update automatically when edited in another app
- Refreshed window chrome — larger rounded corners and a cleaner title bar on macOS Tahoe
- Thin auto-hiding scrollbar
- Redesigned find bar

### Fixed
- Open documents reopen automatically after relaunch (Sparkle update, login, force-quit)
- Pinch-to-zoom now matches Cmd-scroll range (50%–300%) instead of stopping at 100%

### Details

**New**

- Live refresh: if you edit a Markdown file in VS Code, Obsidian, or any other editor, Readdown reloads the rendered view automatically and shows a small "Updated" indicator. Scroll position is preserved across reloads.
- Window chrome polish: on macOS Tahoe (26+), windows use a unified-compact toolbar and the larger native corner radius that matches Messages, Mail, and Bear. The title bar background flows continuously into the document area.
- Auto-hiding scrollbar: the side scrollbar is invisible at rest and fades in for a moment when you scroll.
- Find bar redesign: floating capsule near the top of the window instead of a full-width flush sheet.

**Fixed**

- Documents you had open before quitting (or before a Sparkle auto-update) reopen automatically on next launch via macOS state restoration.
- Pinch-to-zoom on the trackpad now uses the same 50%–300% range as Cmd-scroll and Cmd+/Cmd-. Previously WebKit's built-in handler clamped to 100% as the minimum, so you couldn't pinch out below the default size.

## 1.10

### New
- Fluid layout — documents reflow as you resize the window
- Window cascading when you open multiple files
- Zoom in / out / reset (Cmd +, Cmd -, Cmd 0), pinch and Cmd-scroll to zoom
- Find in document (Cmd+F) with live match counter

### Fixed
- "Set as Default" now prompts automatically on first launch
- Soft line breaks no longer force hard breaks — paragraphs reflow naturally
- HTML entities (`&copy;`, `&ndash;`, …) render correctly
- Wikipedia-style URLs with parens and underscores now work
- PDF / print output preserves syntax highlighting, rules, and checkbox fills

### Details

**Added**

- Fluid body width — document adapts to the window, resize freely and text reflows like a terminal.
- Window cascading — opening multiple files offsets each window instead of stacking them.
- Zoom in/out/reset via Cmd+=, Cmd-, Cmd+0. Pinch-zoom and Cmd-scroll also work.
- Find in document (Cmd+F) with match count, next/previous navigation, and auto-scroll to the current match.
- Autolinks — bare URLs in `<https://…>` and emails in `<you@example.com>` are clickable.
- HTML entities (`&copy;`, `&ndash;`, `&#169;`, `&#xA9;`) render as their characters, per CommonMark.
- HTML comments hidden instead of appearing as literal text.

**Fixed**

- Soft newlines in source no longer force hard `<br>` breaks — paragraphs reflow naturally.
- List item continuation lines flow inline with their item.
- Script tags inside code spans (or anywhere in text) are safely escaped — no more preview cutoff mid-document.
- "Set as Default" prompts automatically on first launch. Older macOS versions show manual setup instructions instead.
- Wikipedia-style links `/wiki/Foo_(bar)` with parentheses in the URL now work.
- Underscores, asterisks, tildes, and backticks inside URLs no longer get interpreted as markdown emphasis.
- PDF/print output now preserves syntax highlighting, horizontal rules, table stripes, and task-list checkbox fills.

## 1.9.3

### Highlights
- Security hardening for HTML passthrough
- Quick Look font fix
- Code block styling polish

## 1.9.2

### Highlights
- Fix Sparkle auto-update installer error on sandboxed builds
