# Changelog

Each version's **Highlights** block is what appears in the in-app update dialog. Keep it to ~5 short bullets grouped under `### New` / `### Fixed`. Everything below **Details** is full notes for GitHub / readdown.app.

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
