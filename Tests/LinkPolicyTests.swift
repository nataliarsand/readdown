import XCTest
@testable import ReadDown

/// The link-click policy: what happens when a reader clicks a link inside a
/// rendered document. Local markdown/text links open the sibling; anchors
/// scroll in place; apps, binaries, and unknown schemes are refused.
final class LinkPolicyTests: XCTestCase {

    private typealias Decision = WebView.Coordinator.LinkDecision

    private func decide(_ url: String, page: String? = nil) -> Decision {
        WebView.Coordinator.linkDecision(
            for: URL(string: url)!,
            page: page.flatMap { URL(string: $0) }
        )
    }

    // MARK: - External links

    func testWebAndMailOpenExternally() {
        XCTAssertEqual(decide("https://example.com"), .openExternally)
        XCTAssertEqual(decide("http://example.com/path"), .openExternally)
        XCTAssertEqual(decide("mailto:hi@example.com"), .openExternally)
    }

    func testUnknownSchemesAreIgnored() {
        XCTAssertEqual(decide("javascript:alert(1)"), .ignore)
        XCTAssertEqual(decide("data:text/html,<b>x</b>"), .ignore)
        XCTAssertEqual(decide("ftp://example.com/file"), .ignore)
    }

    // MARK: - Local document links (the fix)

    func testLocalMarkdownAndTextRevealInFinder() {
        XCTAssertEqual(decide("file:///Users/x/dir/02-notes.md"), .revealInFinder)
        XCTAssertEqual(decide("file:///Users/x/dir/README.markdown"), .revealInFinder)
        XCTAssertEqual(decide("file:///Users/x/dir/notes.txt"), .revealInFinder)
        XCTAssertEqual(decide("file:///Users/x/a/../b/deep.mkd"), .revealInFinder)
    }

    func testLocalDocWithFragmentStillReveals() {
        XCTAssertEqual(
            decide("file:///Users/x/dir/README.md#setup", page: "file:///Users/x/dir/current.md"),
            .revealInFinder
        )
    }

    func testLocalNonDocumentsAreRefused() {
        // A rendered document must not be able to launch an app or open a binary.
        XCTAssertEqual(decide("file:///Applications/Calculator.app"), .ignore)
        XCTAssertEqual(decide("file:///tmp/evil.sh"), .ignore)
        XCTAssertEqual(decide("file:///tmp/disk.dmg"), .ignore)
        XCTAssertEqual(decide("file:///Users/x/dir/subfolder"), .ignore) // no extension
    }

    // MARK: - Same-document fragments (must keep working — regressed once in 1.12)

    func testSameDocFragmentSavedDocStaysInWebView() {
        XCTAssertEqual(
            decide("file:///Users/x/dir/#heading", page: "file:///Users/x/dir/"),
            .allowInWebView
        )
    }

    func testBareFragmentOnUntitledDocStaysInWebView() {
        XCTAssertEqual(decide("#heading", page: "about:blank"), .allowInWebView)
    }

    func testExternalLinkWithFragmentIsNotTreatedAsAnchor() {
        // `https://evil/#x` carries a fragment but is not the current document.
        XCTAssertEqual(
            decide("https://evil.example/#x", page: "file:///Users/x/dir/"),
            .openExternally
        )
    }
}
