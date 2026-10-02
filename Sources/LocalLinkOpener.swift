import AppKit
import Foundation

/// Sandboxed: a sibling file can't be read without a grant, but revealing it in Finder needs none.
enum LocalLinkOpener {

    static func revealInFinder(_ target: URL) {
        let fileURL = URL(fileURLWithPath: target.path)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}
