import Combine
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension Notification.Name {
    static let printDocument = Notification.Name("printDocument")
    static let showInFinder = Notification.Name("showInFinder")
    static let copyFilePath = Notification.Name("copyFilePath")
    static let exportPDF = Notification.Name("exportPDF")
    static let zoomIn = Notification.Name("zoomIn")
    static let zoomOut = Notification.Name("zoomOut")
    static let zoomReset = Notification.Name("zoomReset")
    static let findInDocument = Notification.Name("findInDocument")
    static let findNext = Notification.Name("findNext")
    static let findPrevious = Notification.Name("findPrevious")
    static let linkNotice = Notification.Name("linkNotice")
}

/// `pageZoom`, not `setMagnification`: WebKit clamps magnification at 1.0, so it can't zoom out.
final class ZoomableWebView: WKWebView {
    static let minZoom: CGFloat = 0.5
    static let maxZoom: CGFloat = 3.0

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
        config.userContentController.add(WeakScriptMessageHandler(context.coordinator), name: "rdUsage")

        let webView = ZoomableWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // Pinch goes through ZoomableWebView so it shares the ⌘+/− range.
        webView.allowsMagnification = false
        webView.loadHTMLString(watcher.html, baseURL: baseURL)
        context.coordinator.webView = webView
        context.coordinator.observeFindState()
        context.coordinator.observeWatcher()
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Must stay a no-op: the web view is read-only after load; reloads come from `observeWatcher()`.
    }

    /// Breaks the retain cycle from WKUserContentController to the Coordinator.
    final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
        private weak var delegate: WKScriptMessageHandler?

        init(_ delegate: WKScriptMessageHandler) {
            self.delegate = delegate
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            delegate?.userContentController(userContentController, didReceive: message)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if message.name == "rdUsage", message.body as? String == "copy_code" {
                UsageMetrics.record(.copyCodeBlock)
            }
        }

        var baseURL: URL?
        weak var webView: WKWebView?
        let findState: FindState
        let watcher: DocumentWatcher
        private var observers: [Any] = []
        private var findStateObserver: AnyCancellable?
        private var watcherObserver: AnyCancellable?
        private var activePrintOp: NSPrintOperation?
        private var pendingScrollY: Double?
        private var printRenderer: PrintRenderer?

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

        /// `dropFirst()` skips the value `makeNSView` already loaded.
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
            // Read scrollY before loading; the reload resets it. Restored in didFinish.
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

        // Counted here (menu/keyboard) but not on pinch, which fires per frame.
        private func adjustZoom(by delta: CGFloat) {
            guard let webView = webView as? ZoomableWebView, webView.window == NSApp.keyWindow else { return }
            UsageMetrics.record(.zoom)
            webView.applyZoomDelta(delta)
        }

        private func resetZoom() {
            guard let webView = webView as? ZoomableWebView, webView.window == NSApp.keyWindow else { return }
            UsageMetrics.record(.zoom)
            webView.resetZoom()
        }

        private func standardPrintInfo() -> NSPrintInfo {
            let margin: CGFloat = 36
            let printInfo = NSPrintInfo()
            printInfo.horizontalPagination = .fit
            printInfo.verticalPagination = .automatic
            printInfo.topMargin = margin
            printInfo.bottomMargin = margin
            printInfo.leftMargin = margin
            printInfo.rightMargin = margin
            return printInfo
        }

        /// Dark mode prints from an offscreen light render: Mermaid bakes its colours into the SVG.
        private func printSource(_ completion: @escaping (WKWebView) -> Void) {
            guard let live = webView else { return }
            guard NSApp.effectiveAppearance.isDark else {
                completion(live)
                return
            }
            printRenderer = PrintRenderer(text: watcher.text, baseURL: baseURL, width: live.bounds.width) { [weak self] lightView in
                completion(lightView)
                self?.printRenderer = nil
            }
        }

        private func handlePrint() {
            guard let webView, webView.window == NSApp.keyWindow else { return }
            UsageMetrics.record(.printDocument)
            printSource { [weak self] source in
                guard let self, let window = self.webView?.window else { return }
                let printInfo = self.standardPrintInfo()

                let op = source.printOperation(with: printInfo)
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
            UsageMetrics.record(.exportPDF)
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
                    self.printSource { source in
                        if continuous {
                            let config = WKPDFConfiguration()
                            source.createPDF(configuration: config) { result in
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
                            self.exportPaginatedPDF(webView: source, to: url, window: window)
                        }
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
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            // Anything that isn't a click is our own `loadHTMLString`; it never leaves the document.
            if navigationAction.navigationType != .linkActivated {
                decisionHandler(Coordinator.isOwnLoad(url) ? .allow : .cancel)
                return
            }
            switch Coordinator.linkDecision(for: url, page: webView.url) {
            case .allowInWebView:
                decisionHandler(.allow)
            case .openExternally:
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            case .revealInFinder:
                LocalLinkOpener.revealInFinder(url)
                decisionHandler(.cancel)
            case .askBeforeOpening:
                decisionHandler(.cancel)
                askToOpen(url)
            case .ignore:
                decisionHandler(.cancel)
            }
        }

        static func isOwnLoad(_ url: URL) -> Bool {
            url.isFileURL || url.scheme == "about"
        }

        enum LinkDecision: Equatable {
            case allowInWebView   // same-document `#fragment`
            case openExternally   // http/https/mailto
            case revealInFinder   // file:// text/markdown
            case askBeforeOpening // any other scheme: confirmed on every click, never remembered
            case ignore           // denied scheme, or a local file that isn't a document
        }

        /// The app name comes from Launch Services, never from the document.
        private func askToOpen(_ url: URL) {
            guard let window = webView?.window, let scheme = url.scheme else { return }
            guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) else {
                NotificationCenter.default.post(name: .linkNotice, object: window,
                                                userInfo: ["text": "No app on this Mac opens \(scheme) links"])
                return
            }
            var appName = FileManager.default.displayName(atPath: appURL.path)
            if appName.hasSuffix(".app") { appName.removeLast(4) }

            let alert = NSAlert()
            alert.messageText = "Open this link in \(appName)?"
            alert.informativeText = Self.middleTruncated(url.absoluteString, limit: 120)
            alert.addButton(withTitle: "Open")
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) { response in
                guard response == .alertFirstButtonReturn else {
                    UsageMetrics.record(.openLinkCancelled)
                    return
                }
                UsageMetrics.record(.openLinkConfirmed)
                NSWorkspace.shared.open(url)
            }
        }

        static func middleTruncated(_ text: String, limit: Int) -> String {
            guard text.count > limit else { return text }
            let head = limit / 2
            let tail = limit - head - 1
            return text.prefix(head) + "…" + text.suffix(tail)
        }

        static func linkDecision(for url: URL, page: URL?) -> LinkDecision {
            // An external URL carrying a fragment must still go through NSWorkspace.
            if url.fragment != nil, isSameDocumentFragment(click: url, page: page) {
                return .allowInWebView
            }
            // Only text documents, so a rendered file can't surface or launch anything else.
            if url.isFileURL {
                return isOpenableLocalDocument(url) ? .revealInFinder : .ignore
            }
            switch LinkScheme.kind(of: url.absoluteString) {
            case .web:
                return .openExternally
            case .custom:
                return .askBeforeOpening
            case .denied, .relative:
                return .ignore
            }
        }

        /// `loadHTMLString` reports `about:blank` with no baseURL, and a directory
        /// baseURL can differ from the click by a trailing slash; both are same-document.
        private static func isSameDocumentFragment(click: URL, page: URL?) -> Bool {
            guard let page = page, page.absoluteString != "about:blank" else {
                return click.scheme == nil || click.scheme == "about"
            }
            guard click.scheme == page.scheme, click.host == page.host else {
                return false
            }
            let clickPath = click.path
            let pagePath = page.path
            return clickPath == pagePath
                || clickPath + "/" == pagePath
                || clickPath == pagePath + "/"
        }

        /// The document types Readdown itself opens; never executables or bundles.
        private static let openableLocalExtensions: Set<String> = [
            "md", "markdown", "mdown", "mkd", "mdwn", "mdtxt", "mdtext",
            "txt", "text"
        ]

        private static func isOpenableLocalDocument(_ url: URL) -> Bool {
            openableLocalExtensions.contains(url.pathExtension.lowercased())
        }
    }
}

private final class PrintRenderer: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let hasMermaid: Bool
    private let completion: (WKWebView) -> Void
    private var finished = false

    init(text: String, baseURL: URL?, width: CGFloat, completion: @escaping (WKWebView) -> Void) {
        let result = MarkdownRenderer.render(text)
        hasMermaid = result.hasMermaid
        self.completion = completion
        let html = HTMLTemplate.wrap(body: result.html, hasMermaid: result.hasMermaid, hasMath: result.hasMath, isDark: false)
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: max(width, 320), height: 10))
        // `isDark: false` doesn't reach the `prefers-color-scheme` palette; the view appearance does.
        webView.appearance = NSAppearance(named: .aqua)
        webView.underPageBackgroundColor = .white
        super.init()
        webView.navigationDelegate = self
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasMermaid ? waitForMermaid() : finish()
    }

    /// Mermaid renders after load; bounded so a failed diagram can't hang printing.
    private func waitForMermaid(attempt: Int = 0) {
        let js = """
        (function() {
            var pending = document.querySelectorAll('pre.mermaid');
            var drawn = document.querySelectorAll('pre.mermaid svg');
            return pending.length === 0 || drawn.length >= pending.length;
        })()
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self else { return }
            if (result as? Bool) == true || attempt >= 40 {
                self.finish()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.waitForMermaid(attempt: attempt + 1)
                }
            }
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        completion(webView)
    }
}
