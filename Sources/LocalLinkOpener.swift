import AppKit
import Foundation

/// Handles a link inside a rendered document that points at another local file.
///
/// Readdown is sandboxed, so it can't read a sibling file the user never opened.
/// Rather than prompt for folder access, a local link reveals its target in
/// Finder — Finder has the access, so there's no permission panel — and the
/// reader opens it from there (space to preview, double-click to open here).
enum LocalLinkOpener {

    /// Reveal the file a local link points at in Finder. `target` may carry a
    /// `#fragment`; Finder selects the file by path.
    static func revealInFinder(_ target: URL) {
        let fileURL = URL(fileURLWithPath: target.path)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}
