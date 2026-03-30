import SwiftUI
import WebKit

extension Notification.Name {
    static let printDocument = Notification.Name("printDocument")
}

struct WebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator(baseURL: baseURL)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(html, baseURL: baseURL)
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Read-only document — HTML is computed once in ContentView.init
        // and never changes. No need to reload.
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var baseURL: URL?
        weak var webView: WKWebView?
        private var printObserver: Any?
        private var activePrintOp: NSPrintOperation?

        init(baseURL: URL?) {
            self.baseURL = baseURL
            super.init()
            printObserver = NotificationCenter.default.addObserver(
                forName: .printDocument, object: nil, queue: .main
            ) { [weak self] _ in
                self?.handlePrint()
            }
        }

        deinit {
            if let obs = printObserver {
                NotificationCenter.default.removeObserver(obs)
            }
        }

        private func handlePrint() {
            guard let webView, let window = webView.window, window == NSApp.keyWindow else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let webView = self.webView, let window = webView.window else { return }
                let printInfo = NSPrintInfo()
                printInfo.horizontalPagination = .fit
                printInfo.verticalPagination = .automatic
                printInfo.topMargin = 36
                printInfo.bottomMargin = 36
                printInfo.leftMargin = 36
                printInfo.rightMargin = 36

                let op = webView.printOperation(with: printInfo)
                op.showsPrintPanel = true
                op.showsProgressPanel = true
                op.printPanel.options.insert(.showsPreview)

                self.activePrintOp = op
                op.runModal(for: window, delegate: self, didRun: #selector(self.printDidRun), contextInfo: nil)
            }
        }

        @objc private func printDidRun() {
            activePrintOp = nil
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                guard isAllowedExternalURL(url) else {
                    decisionHandler(.cancel)
                    return
                }
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        private func isAllowedExternalURL(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else {
                return false
            }

            switch scheme {
            case "http", "https", "mailto":
                return true
            case "file":
                return baseURL?.isFileURL == true
            default:
                return false
            }
        }
    }
}
