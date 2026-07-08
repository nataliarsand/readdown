import Combine
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension Notification.Name {
    static let printDocument = Notification.Name("printDocument")
    static let showInFinder = Notification.Name("showInFinder")
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
        // Weak proxy: the content controller retains its handlers.
        config.userContentController.add(WeakScriptMessageHandler(context.coordinator), name: "rdUsage")

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

        /// Print/PDF configuration with Readdown's standard 36 pt margins.
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

        /// Provides the WebView to print/export from. In dark mode this is a
        /// light-themed offscreen render, so paper never inherits the dark
        /// palette — Mermaid bakes its colours into the generated SVG, so the
        /// on-screen view can't just be reused. In light mode it's the live view.
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
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                switch Coordinator.linkDecision(for: url, page: webView.url) {
                case .allowInWebView:
                    decisionHandler(.allow)
                case .openExternally:
                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel)
                case .revealInFinder:
                    LocalLinkOpener.revealInFinder(url)
                    decisionHandler(.cancel)
                case .ignore:
                    decisionHandler(.cancel)
                }
                return
            }
            decisionHandler(.allow)
        }

        /// What to do with an activated link. Pulled out as a pure function so
        /// the policy is unit-testable without a live WebView.
        enum LinkDecision: Equatable {
            case allowInWebView   // same-document `#fragment` — let WebKit scroll
            case openExternally   // http/https/mailto — hand to NSWorkspace
            case revealInFinder   // file:// text/markdown — reveal in Finder
            case ignore           // refuse — unknown scheme, or a local file
                                  // that isn't a document worth revealing
        }

        static func linkDecision(for url: URL, page: URL?) -> LinkDecision {
            // Same-document fragment links (`#heading-anchor`) — let WebKit
            // handle the scroll natively. The earlier strict scheme/host/path
            // triple-match against the page URL rejected real intra-doc clicks
            // because `loadHTMLString(_:baseURL:)` reports `about:blank` for an
            // untitled doc and a trailing-slash-mismatched directory URL for a
            // saved one — that broke all heading anchors from 1.12 onward.
            // `isSameDocumentFragment` accepts both shapes while still rejecting
            // external links that happen to carry a fragment (e.g.
            // `https://evil/#x`), which must still go through NSWorkspace.
            if url.fragment != nil, isSameDocumentFragment(click: url, page: page) {
                return .allowInWebView
            }
            // Relative links between documents (`[details](notes.md)`) resolve to
            // a file:// URL against the doc's directory. Reveal the target in
            // Finder when it's a text/markdown file. Anything else local — an app
            // bundle, a binary, a disk image — is ignored so a rendered document
            // can't trick the reader into surfacing or launching it.
            if url.isFileURL {
                return isOpenableLocalDocument(url) ? .revealInFinder : .ignore
            }
            return isAllowedExternalURL(url) ? .openExternally : .ignore
        }

        /// Returns `true` when `click` is a fragment URL pointing inside the
        /// currently-loaded document. Tolerates the two real-world shapes the
        /// loader produces: an `about:blank` page URL (loaded with no baseURL),
        /// and a directory baseURL whose path differs from the click's only by
        /// a trailing slash.
        private static func isSameDocumentFragment(click: URL, page: URL?) -> Bool {
            // No real page URL yet, or page is `about:blank` — accept only when
            // the click URL is itself `about:`-scoped (which is what a bare
            // `#frag` resolves to in that document context).
            guard let page = page, page.absoluteString != "about:blank" else {
                return click.scheme == nil || click.scheme == "about"
            }
            // Otherwise: scheme + host must match, and paths must match modulo
            // a single trailing slash on either side.
            guard click.scheme == page.scheme, click.host == page.host else {
                return false
            }
            let clickPath = click.path
            let pagePath = page.path
            return clickPath == pagePath
                || clickPath + "/" == pagePath
                || clickPath == pagePath + "/"
        }

        private static func isAllowedExternalURL(_ url: URL) -> Bool {
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

        /// Text/markdown document extensions a relative link may point at. Matches
        /// the document types Readdown itself opens, so a cross-link lands the
        /// reader on the target instead of doing nothing. Deliberately excludes
        /// executables, app bundles, and other file types.
        private static let openableLocalExtensions: Set<String> = [
            "md", "markdown", "mdown", "mkd", "mdwn", "mdtxt", "mdtext",
            "txt", "text"
        ]

        private static func isOpenableLocalDocument(_ url: URL) -> Bool {
            openableLocalExtensions.contains(url.pathExtension.lowercased())
        }
    }
}

/// Renders a document into an offscreen, light-themed WebView for print/PDF
/// output, then calls back once it (including any Mermaid diagrams) has
/// finished laying out. Held by the Coordinator until the operation completes.
private final class PrintRenderer: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let hasMermaid: Bool
    private let completion: (WKWebView) -> Void
    private var finished = false

    init(text: String, baseURL: URL?, width: CGFloat, completion: @escaping (WKWebView) -> Void) {
        let result = MarkdownRenderer.render(text)
        hasMermaid = result.hasMermaid
        self.completion = completion
        let html = HTMLTemplate.wrap(body: result.html, hasMermaid: result.hasMermaid, isDark: false)
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: max(width, 320), height: 10))
        // Force light appearance so the page CSS `prefers-color-scheme` also
        // resolves light — `isDark: false` only covers Mermaid and the theme
        // attribute, not the media-query palette.
        webView.appearance = NSAppearance(named: .aqua)
        webView.underPageBackgroundColor = .white
        super.init()
        webView.navigationDelegate = self
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasMermaid ? waitForMermaid() : finish()
    }

    /// Mermaid renders asynchronously after load; wait until every diagram has
    /// produced its SVG (bounded, so a failed render can't hang printing).
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
