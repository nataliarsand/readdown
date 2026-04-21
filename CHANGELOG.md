# Changelog

Each version's **Highlights** block is what appears in the in-app update dialog. Keep it to ~5 short bullets grouped under `### New` / `### Fixed`. Everything below **Details** is full notes for GitHub / readdown.app.

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
