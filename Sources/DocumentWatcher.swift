import AppKit
import Combine
import Foundation

/// Renders a document to HTML, re-rendering when the file changes on disk or
/// the system appearance changes. `NSFilePresenter` tracks atomic saves
/// (write-temp-then-rename); the initial render is synchronous to avoid a flash.
final class DocumentWatcher: NSObject, ObservableObject, NSFilePresenter {
    /// Lets the UI show the "Updated" pill for content changes but not re-themes.
    enum ChangeSource {
        case disk
        case appearance
    }

    @Published private(set) var html: String
    /// Raw source, kept in sync with `html` so a copy reflects what's on disk.
    @Published private(set) var text: String
    private(set) var lastChangeSource: ChangeSource = .disk
    let fileURL: URL?

    var presentedItemURL: URL? { fileURL }
    let presentedItemOperationQueue: OperationQueue = .main

    private var isDark: Bool
    private var isRegistered = false
    private var reloadWorkItem: DispatchWorkItem?
    private var appearanceObservation: NSKeyValueObservation?

    init(initialText: String, fileURL: URL?, isDark: Bool) {
        let result = MarkdownRenderer.render(initialText)
        self.isDark = isDark
        self.html = HTMLTemplate.wrap(body: result.html, hasMermaid: result.hasMermaid, isDark: isDark)
        self.text = initialText
        self.fileURL = fileURL
        super.init()
        if fileURL != nil {
            NSFileCoordinator.addFilePresenter(self)
            isRegistered = true
        }
        // `.shared`, not `NSApp`: safe to observe under the test runner too.
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] app, _ in
            let dark = app.effectiveAppearance.isDark
            DispatchQueue.main.async {
                self?.appearanceDidChange(isDark: dark)
            }
        }
    }

    deinit {
        if isRegistered {
            NSFileCoordinator.removeFilePresenter(self)
        }
    }

    func presentedItemDidChange() {
        // Coalesce the burst of FS events a single save can fire.
        reloadWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        reloadWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func reload() {
        guard let fileURL else { return }
        let coordinator = NSFileCoordinator(filePresenter: self)
        var coordError: NSError?
        var decoded: String?

        coordinator.coordinate(readingItemAt: fileURL, options: [], error: &coordError) { url in
            guard let data = try? Data(contentsOf: url) else { return }
            decoded = try? TextFileDecoder.decode(data)
        }

        guard let text = decoded else { return }
        let result = MarkdownRenderer.render(text)
        let next = HTMLTemplate.wrap(body: result.html, hasMermaid: result.hasMermaid, isDark: isDark)
        if next != html {
            self.text = text
            lastChangeSource = .disk
            html = next
        }
    }

    /// Internal so tests can drive a theme change without flipping the system.
    func appearanceDidChange(isDark dark: Bool) {
        guard dark != isDark else { return }
        isDark = dark
        let result = MarkdownRenderer.render(text)
        lastChangeSource = .appearance
        html = HTMLTemplate.wrap(body: result.html, hasMermaid: result.hasMermaid, isDark: dark)
    }
}
