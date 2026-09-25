# Contributing

Thanks for helping. Readdown is source-available (see `LICENSE`): you can read, study, and contribute, but not redistribute.

## Before you start

Open an issue for anything bigger than a small fix, so we can agree on the shape before you spend time on it.

## Sending a change

- Keep each pull request to one fix or one feature.
- Add or update a test in `Tests/` for renderer changes. `xcodebuild test -project ReadDown.xcodeproj -scheme ReadDown -destination 'platform=macOS'` must pass; CI runs the same command.
- Add a line under the next version in `CHANGELOG.md`, written for users, not for developers.
- Keep comments to constraints and traps. Leave out rationale, roadmap, and product thinking.
- Commit under your own name and email so the change is credited to you. Merged changes keep your authorship.

## Performance and safety rules

These are the rules that have bitten before:

- No work in SwiftUI `body`; compute in `init` or stored properties.
- Never run highlight.js against every grammar; auto-detection stays on the curated subset.
- Compile regular expressions once, at module level.
- Every block parser in the renderer must advance the line index, and unclosed fences must consume to end of file.
- Raw HTML goes through the allowlist sanitizer; do not widen it without a test proving the dangerous case stays blocked.
