import WebKit
import XCTest
@testable import ReadDown

final class LinkPolicyTests: XCTestCase {

    private typealias Decision = ReadDown.WebView.Coordinator.LinkDecision

    private func decide(_ url: String, page: String? = nil) -> Decision {
        ReadDown.WebView.Coordinator.linkDecision(
            for: URL(string: url)!,
            page: page.flatMap { URL(string: $0) }
        )
    }

    func testWebAndMailOpenExternally() {
        XCTAssertEqual(decide("https://example.com"), .openExternally)
        XCTAssertEqual(decide("http://example.com/path"), .openExternally)
        XCTAssertEqual(decide("mailto:hi@example.com"), .openExternally)
    }

    func testDeniedSchemesAreIgnored() {
        XCTAssertEqual(decide("javascript:alert(1)"), .ignore)
        XCTAssertEqual(decide("data:text/html,<b>x</b>"), .ignore)
        XCTAssertEqual(decide("ftp://example.com/file"), .ignore)
        XCTAssertEqual(decide("sftp://example.com/file"), .ignore)
        XCTAssertEqual(decide("smb://server/share"), .ignore)
        XCTAssertEqual(decide("ssh://host"), .ignore)
        XCTAssertEqual(decide("x-apple.systempreferences:com.apple.preference.security"), .ignore)
        XCTAssertEqual(decide("ms-settings:display"), .ignore)
        XCTAssertEqual(decide("shortcuts://run-shortcut?name=x"), .ignore)
        XCTAssertEqual(decide("about:blank"), .ignore)
    }

    func testCustomSchemesAskBeforeOpening() {
        XCTAssertEqual(decide("codex://open?file=notes.md"), .askBeforeOpening)
        XCTAssertEqual(decide("vscode://file/a.md"), .askBeforeOpening)
        XCTAssertEqual(decide("CODEX://open"), .askBeforeOpening)
    }

    func testCustomSchemeWithFragmentIsNotTreatedAsAnchor() {
        XCTAssertEqual(
            decide("codex://open#section", page: "file:///Users/x/dir/"),
            .askBeforeOpening
        )
    }

    func testDialogURLIsMiddleTruncated() {
        let short = "codex://open?file=a.md"
        XCTAssertEqual(ReadDown.WebView.Coordinator.middleTruncated(short, limit: 120), short)
        let long = "codex://open?" + String(repeating: "a", count: 200) + "&end=1"
        let shown = ReadDown.WebView.Coordinator.middleTruncated(long, limit: 120)
        XCTAssertEqual(shown.count, 120)
        XCTAssertTrue(shown.hasPrefix("codex://open?"))
        XCTAssertTrue(shown.hasSuffix("&end=1"))
        XCTAssertTrue(shown.contains("…"))
    }

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
        XCTAssertEqual(
            decide("https://evil.example/#x", page: "file:///Users/x/dir/"),
            .openExternally
        )
    }

    private final class SpyCoordinator: ReadDown.WebView.Coordinator {
        var answers: [(url: String, policy: WKNavigationActionPolicy)] = []

        override func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                              decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url?.absoluteString ?? ""
            super.webView(webView, decidePolicyFor: navigationAction) { policy in
                self.answers.append((url, policy))
                decisionHandler(policy)
            }
        }
    }

    private func loadedWebView(_ markdown: String, baseURL: URL? = nil) -> (WKWebView, SpyCoordinator) {
        let watcher = DocumentWatcher(initialText: markdown, fileURL: nil, isDark: false)
        let coordinator = SpyCoordinator(baseURL: baseURL, findState: FindState(), watcher: watcher)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        webView.navigationDelegate = coordinator
        webView.loadHTMLString(watcher.html, baseURL: baseURL)
        pump(until: { !coordinator.answers.isEmpty && webView.isLoading == false })
        return (webView, coordinator)
    }

    private func pump(seconds: TimeInterval = 1.0, until done: () -> Bool = { false }) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline, !done() {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    func testOwnLoadIsAllowed() {
        let (_, untitled) = loadedWebView("hi")
        XCTAssertEqual(untitled.answers.first?.url, "about:blank")
        XCTAssertEqual(untitled.answers.first?.policy, .allow)
        let (_, saved) = loadedWebView("hi", baseURL: URL(fileURLWithPath: "/tmp/", isDirectory: true))
        XCTAssertEqual(saved.answers.first?.url, "file:///tmp/")
        XCTAssertEqual(saved.answers.first?.policy, .allow)
    }

    func testClickOnCustomSchemeLinkIsCancelledInTheWebView() {
        let (webView, coordinator) = loadedWebView("[Open](codex://open?file=x)")
        coordinator.answers.removeAll()
        webView.evaluateJavaScript("document.querySelector('a').click()")
        pump(until: { !coordinator.answers.isEmpty })
        XCTAssertEqual(coordinator.answers.map(\.url), ["codex://open?file=x"])
        XCTAssertEqual(coordinator.answers.first?.policy, .cancel)
    }

    func testScriptedNavigationToCustomSchemeIsCancelled() {
        let (webView, coordinator) = loadedWebView("hi")
        coordinator.answers.removeAll()
        webView.evaluateJavaScript("location.href = 'codex://open'")
        pump(until: { !coordinator.answers.isEmpty })
        XCTAssertEqual(coordinator.answers.first?.url, "codex://open")
        XCTAssertEqual(coordinator.answers.first?.policy, .cancel)
    }

    func testSameDocumentAnchorClickStaysInTheWebView() {
        let folder = URL(fileURLWithPath: "/tmp/", isDirectory: true)
        let (webView, coordinator) = loadedWebView("[Go](#target)\n\n# Target", baseURL: folder)
        coordinator.answers.removeAll()
        webView.evaluateJavaScript("document.querySelector('a').click()")
        pump(until: { !coordinator.answers.isEmpty })
        XCTAssertEqual(coordinator.answers.first?.url, "file:///tmp/#target")
        XCTAssertEqual(coordinator.answers.first?.policy, .allow)
    }
}
