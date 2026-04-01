import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension Notification.Name {
    static let printDocument = Notification.Name("printDocument")
    static let exportPDF = Notification.Name("exportPDF")
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
        private var exportPDFObserver: Any?
        private var activePrintOp: NSPrintOperation?

        init(baseURL: URL?) {
            self.baseURL = baseURL
            super.init()
            printObserver = NotificationCenter.default.addObserver(
                forName: .printDocument, object: nil, queue: .main
            ) { [weak self] _ in
                self?.handlePrint()
            }
            exportPDFObserver = NotificationCenter.default.addObserver(
                forName: .exportPDF, object: nil, queue: .main
            ) { [weak self] _ in
                self?.handleExportPDF()
            }
        }

        deinit {
            if let obs = printObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            if let obs = exportPDFObserver {
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

        private func handleExportPDF() {
            guard let webView, let window = webView.window, window == NSApp.keyWindow else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let webView = self.webView, let window = webView.window else { return }
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.pdf]
                savePanel.nameFieldStringValue = self.suggestedPDFName()

                let layoutPicker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26), pullsDown: false)
                layoutPicker.addItems(withTitles: ["Continuous (single page)", "Paginated"])
                let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 36))
                let label = NSTextField(labelWithString: "Layout:")
                label.font = .systemFont(ofSize: 13)
                label.frame = NSRect(x: 0, y: 8, width: 50, height: 20)
                layoutPicker.frame = NSRect(x: 54, y: 4, width: 220, height: 26)
                accessory.addSubview(label)
                accessory.addSubview(layoutPicker)
                savePanel.accessoryView = accessory

                savePanel.beginSheetModal(for: window) { response in
                    guard response == .OK, let url = savePanel.url else { return }
                    let continuous = layoutPicker.indexOfSelectedItem == 0
                    if continuous {
                        let config = WKPDFConfiguration()
                        webView.createPDF(configuration: config) { result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success(let data):
                                    do {
                                        try data.write(to: url)
                                    } catch {
                                        self.showExportError(error.localizedDescription, window: window)
                                    }
                                case .failure(let error):
                                    self.showExportError(error.localizedDescription, window: window)
                                }
                            }
                        }
                    } else {
                        self.exportPaginatedPDF(webView: webView, to: url, window: window)
                    }
                }
            }
        }

        private func exportPaginatedPDF(webView: WKWebView, to url: URL, window: NSWindow) {
            let printInfo = NSPrintInfo()
            printInfo.horizontalPagination = .fit
            printInfo.verticalPagination = .automatic
            printInfo.topMargin = 36
            printInfo.bottomMargin = 36
            printInfo.leftMargin = 36
            printInfo.rightMargin = 36
            printInfo.jobDisposition = .save
            printInfo.dictionary().setObject(url, forKey: NSPrintInfo.AttributeKey.jobSavingURL as NSCopying)

            let op = webView.printOperation(with: printInfo)
            op.showsPrintPanel = false
            op.showsProgressPanel = true

            self.activePrintOp = op
            op.runModal(for: window, delegate: self, didRun: #selector(self.printDidRun), contextInfo: nil)
        }

        private func showExportError(_ message: String, window: NSWindow) {
            let alert = NSAlert()
            alert.messageText = "PDF Export Failed"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.beginSheetModal(for: window)
        }

        private func suggestedPDFName() -> String {
            if let title = webView?.window?.title, !title.isEmpty {
                let name = (title as NSString).deletingPathExtension
                return name + ".pdf"
            }
            return "Untitled.pdf"
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
