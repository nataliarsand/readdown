import Cocoa
import QuickLookUI
import WebKit

class PreviewViewController: NSViewController, QLPreviewingController {

    private var webView: WKWebView!

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false
        let pagePrefs = WKWebpagePreferences()
        pagePrefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = pagePrefs

        webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        self.view = webView
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            let markdown = try TextFileDecoder.decode(Data(contentsOf: url))
            let result = MarkdownRenderer.render(markdown)
            let html = HTMLTemplate.wrap(body: result.html, hasMermaid: result.hasMermaid)
            webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
            handler(nil)
        } catch {
            handler(error)
        }
    }
}
