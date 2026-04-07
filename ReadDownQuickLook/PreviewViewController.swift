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
        webView.setValue(false, forKey: "drawsBackground")
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
            let html = HTMLTemplate.wrap(body: result.html, hasMermaid: result.hasMermaid, compact: true)
            webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
            handler(nil)
        } catch {
            handler(error)
        }
    }
}
