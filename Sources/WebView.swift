import Combine
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension Notification.Name {
    static let printDocument = Notification.Name("printDocument")
    static let exportPDF = Notification.Name("exportPDF")
    static let zoomIn = Notification.Name("zoomIn")
    static let zoomOut = Notification.Name("zoomOut")
    static let zoomReset = Notification.Name("zoomReset")
    static let findInDocument = Notification.Name("findInDocument")
    static let findNext = Notification.Name("findNext")
    static let findPrevious = Notification.Name("findPrevious")
}

/// `WKWebView` subclass that adds Cmd-scroll zoom on top of the trackpad pinch already enabled
/// by `allowsMagnification = true`. Other scroll events pass through unchanged.
final class ZoomableWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let delta = event.scrollingDeltaY * 0.01
            let new = max(0.5, min(3.0, magnification + delta))
            setMagnification(new, centeredAt: .zero)
            return
        }
        super.scrollWheel(with: event)
    }
}

struct WebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    @ObservedObject var findState: FindState

    func makeCoordinator() -> Coordinator {
        Coordinator(baseURL: baseURL, findState: findState)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = ZoomableWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.loadHTMLString(html, baseURL: baseURL)
        context.coordinator.webView = webView
        context.coordinator.observeFindState()
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Read-only document — HTML is computed once in ContentView.init
        // and never changes. No need to reload.
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var baseURL: URL?
        weak var webView: WKWebView?
        let findState: FindState
        private var observers: [Any] = []
        private var findStateObserver: AnyCancellable?
        private var activePrintOp: NSPrintOperation?

        init(baseURL: URL?, findState: FindState) {
            self.baseURL = baseURL
            self.findState = findState
            super.init()
            observe(.printDocument) { $0.handlePrint() }
            observe(.exportPDF) { $0.handleExportPDF() }
            observe(.zoomIn) { $0.adjustZoom(by: 0.1) }
            observe(.zoomOut) { $0.adjustZoom(by: -0.1) }
            observe(.zoomReset) { $0.resetZoom() }
            observe(.findNext) { $0.findCurrent(backwards: false) }
            observe(.findPrevious) { $0.findCurrent(backwards: true) }
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }

        func observeFindState() {
            findStateObserver = findState.$searchText
                .dropFirst()
                .removeDuplicates()
                .sink { [weak self] text in
                    self?.performFind(text)
                }
        }

        private func findCurrent(backwards: Bool) {
            guard let webView, webView.window == NSApp.keyWindow else { return }
            evaluateFind(backwards ? "window.__rdFind.prev()" : "window.__rdFind.next()")
        }

        private func performFind(_ text: String) {
            guard let webView else { return }
            if text.isEmpty {
                webView.evaluateJavaScript("window.__rdFind.clear()", completionHandler: nil)
                findState.totalMatches = 0
                findState.currentMatch = 0
                return
            }
            let escaped = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
            evaluateFind("window.__rdFind.search('\(escaped)')")
        }

        private func evaluateFind(_ js: String) {
            guard let webView else { return }
            webView.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self, let dict = result as? [String: Any],
                      let total = dict["total"] as? Int,
                      let current = dict["current"] as? Int else { return }
                self.findState.totalMatches = total
                self.findState.currentMatch = current
            }
        }

        private func observe(_ name: Notification.Name, _ action: @escaping (Coordinator) -> Void) {
            let token = NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                action(self)
            }
            observers.append(token)
        }

        private func adjustZoom(by delta: CGFloat) {
            guard let webView, webView.window == NSApp.keyWindow else { return }
            let new = max(0.5, min(3.0, webView.magnification + delta))
            webView.setMagnification(new, centeredAt: .zero)
        }

        private func resetZoom() {
            guard let webView, webView.window == NSApp.keyWindow else { return }
            webView.setMagnification(1.0, centeredAt: .zero)
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
            default:
                return false
            }
        }
    }
}
