import Cocoa
import QuickLookUI
import WebKit

class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {

    private var webView: WKWebView!
    private var loadedBaseURL: URL?

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false
        let pagePrefs = WKWebpagePreferences()
        pagePrefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = pagePrefs

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        // Never `setValue(false, forKey: "drawsBackground")`: a private KVC key whose unknown-key throw can't be caught here, and Quick Look then spins forever.
        self.view = webView
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Only the preview's own load; a click, or anything else, goes nowhere.
        if navigationAction.navigationType != .linkActivated,
           let url = navigationAction.request.url, isOwnLoad(url) {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
    }

    private func isOwnLoad(_ url: URL) -> Bool {
        if url.absoluteString == "about:blank" { return true }
        guard url.isFileURL, let base = loadedBaseURL else { return false }
        return url.standardizedFileURL.path == base.standardizedFileURL.path
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            let markdown = try TextFileDecoder.decode(Data(contentsOf: url))
            let result = MarkdownRenderer.render(markdown)
            // Appearance source of truth is `NSAppearance`, not the media query.
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let html = HTMLTemplate.wrap(body: result.html, hasMermaid: result.hasMermaid, hasMath: result.hasMath, compact: true, isDark: isDark)
            loadedBaseURL = url.deletingLastPathComponent()
            webView.loadHTMLString(html, baseURL: loadedBaseURL)
            handler(nil)
        } catch {
            handler(error)
        }
    }
}
