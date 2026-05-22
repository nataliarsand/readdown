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

/// `WKWebView` subclass that owns zoom for both Cmd-scroll and trackpad pinch.
/// Uses `pageZoom` instead of `setMagnification` because WebKit's magnification
/// API silently clamps to 1.0 as the lower bound — so pinch-to-zoom-out below
/// 100% doesn't work. `pageZoom` accepts the full 0.5–3.0 range and reflows
/// text on zoom changes (better UX for a reader than bitmap scaling).
final class ZoomableWebView: WKWebView {
    static let minZoom: CGFloat = 0.5
    static let maxZoom: CGFloat = 3.0

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            applyZoomDelta(event.scrollingDeltaY * 0.01)
            return
        }
        super.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        applyZoomDelta(event.magnification)
    }

    func applyZoomDelta(_ delta: CGFloat) {
        let new = max(Self.minZoom, min(Self.maxZoom, pageZoom + delta))
        pageZoom = new
    }

    func resetZoom() {
        pageZoom = 1.0
    }
}

struct WebView: NSViewRepresentable {
    let baseURL: URL?
    @ObservedObject var findState: FindState
    @ObservedObject var watcher: DocumentWatcher

    func makeCoordinator() -> Coordinator {
        Coordinator(baseURL: baseURL, findState: findState, watcher: watcher)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = ZoomableWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // ZoomableWebView handles pinch directly so the range matches Cmd-scroll (0.5–3.0).
        webView.allowsMagnification = false
        webView.loadHTMLString(watcher.html, baseURL: baseURL)
        context.coordinator.webView = webView
        context.coordinator.observeFindState()
        context.coordinator.observeWatcher()
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Content reloads are pushed by the Coordinator's Combine subscription on
        // `watcher.$html` — see `observeWatcher()`. Keeping `updateNSView` a no-op
        // avoids re-loading the 200KB embedded highlight.js on every SwiftUI rerender.
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var baseURL: URL?
        weak var webView: WKWebView?
        let findState: FindState
        let watcher: DocumentWatcher
        private var observers: [Any] = []
        private var findStateObserver: AnyCancellable?
        private var watcherObserver: AnyCancellable?
        private var activePrintOp: NSPrintOperation?
        private var pendingScrollY: Double?

        init(baseURL: URL?, findState: FindState, watcher: DocumentWatcher) {
            self.baseURL = baseURL
            self.findState = findState
            self.watcher = watcher
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

        /// Reload the WebView when the file changes on disk.
        /// `dropFirst()` skips the initial value — `makeNSView` already loaded it.
        func observeWatcher() {
            watcherObserver = watcher.$html
                .dropFirst()
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] html in
                    self?.reload(html)
                }
        }

        private func reload(_ html: String) {
            guard let webView else { return }
            // Capture current scroll so the reader doesn't lose their place when an
            // external editor saves. Sequencing matters: read scrollY *before*
            // loadHTMLString, since evaluateJavaScript is async and the reload would
            // otherwise reset position before we read it. Restored in didFinish.
            webView.evaluateJavaScript("window.scrollY") { [weak self] result, _ in
                guard let self, let webView = self.webView else { return }
                self.pendingScrollY = result as? Double
                webView.loadHTMLString(html, baseURL: self.baseURL)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let y = pendingScrollY else { return }
            pendingScrollY = nil
            webView.evaluateJavaScript("window.scrollTo(0, \(y))", completionHandler: nil)
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
            guard let webView = webView as? ZoomableWebView, webView.window == NSApp.keyWindow else { return }
            webView.applyZoomDelta(delta)
        }

        private func resetZoom() {
            guard let webView = webView as? ZoomableWebView, webView.window == NSApp.keyWindow else { return }
            webView.resetZoom()
        }

        /// Print/PDF configuration with Readdown's standard 36 pt margins.
        private func standardPrintInfo() -> NSPrintInfo {
            let printInfo = NSPrintInfo()
            printInfo.horizontalPagination = .fit
            printInfo.verticalPagination = .automatic
            printInfo.topMargin = 36
            printInfo.bottomMargin = 36
            printInfo.leftMargin = 36
            printInfo.rightMargin = 36
            return printInfo
        }

        private func handlePrint() {
            guard let webView, let window = webView.window, window == NSApp.keyWindow else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let webView = self.webView, let window = webView.window else { return }
                let printInfo = self.standardPrintInfo()

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
            let printInfo = standardPrintInfo()
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
                // Same-document fragment links (`#heading-anchor`) — let WebKit
                // handle the scroll natively. Detected when the URL has a
                // fragment and otherwise matches the document's loaded URL.
                if url.fragment != nil,
                   let current = webView.url,
                   url.scheme == current.scheme,
                   url.host == current.host,
                   url.path == current.path {
                    decisionHandler(.allow)
                    return
                }
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
