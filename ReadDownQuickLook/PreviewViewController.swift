import Cocoa
import QuickLookUI
import WebKit

class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {

    private var webView: WKWebView!

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false
        let pagePrefs = WKWebpagePreferences()
        pagePrefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = pagePrefs

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        // Do NOT use `setValue(false, forKey: "drawsBackground")` here — that is a
        // private, undocumented KVC key on WKWebView. If a macOS release removes or
        // renames it, `setValue` throws NSUnknownKeyException inside loadView(),
        // which Swift can't catch — the extension crashes before producing a view
        // and Quick Look shows an endless spinner (GitHub issue #5). The HTML
        // template paints its own opaque background and carries a `color-scheme`
        // meta tag, so no background manipulation is needed — the main app's
        // WebView renders the same content without it.
        self.view = webView
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            let markdown = try TextFileDecoder.decode(Data(contentsOf: url))
            let result = MarkdownRenderer.render(markdown)
            // Resolve dark vs light for the embedded Mermaid theme — see ContentView.init.
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let html = HTMLTemplate.wrap(body: result.html, hasMermaid: result.hasMermaid, hasMath: result.hasMath, compact: true, isDark: isDark)
            webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
            handler(nil)
        } catch {
            handler(error)
        }
    }
}
