import AppKit
import Combine
import Foundation

/// `NSFilePresenter` tracks atomic saves (write-temp-then-rename); the initial render is synchronous to avoid a flash.
final class DocumentWatcher: NSObject, ObservableObject, NSFilePresenter {
    /// Lets the UI announce content changes but not re-themes.
    enum ChangeSource {
        case disk
        case appearance
    }

    @Published private(set) var html: String
    /// Raw source, kept in sync with `html` so a copy reflects what's on disk.
    @Published private(set) var text: String
    var bodyHTML: String { lastResult.html }
    private(set) var lastChangeSource: ChangeSource = .disk
    let fileURL: URL?

    var presentedItemURL: URL? { fileURL }
    let presentedItemOperationQueue: OperationQueue = .main

    private var palette: ReaderThemePalette
    private let themeProvider: (Bool) -> ReaderThemePalette
    private var isRegistered = false
    private var reloadWorkItem: DispatchWorkItem?
    private var appearanceObservation: NSKeyValueObservation?
    private var lastResult: MarkdownRenderer.Result
    private var themeObservation: NSObjectProtocol?

    convenience init(initialText: String, fileURL: URL?, isDark: Bool) {
        let provider: (Bool) -> ReaderThemePalette = { dark in
            ReaderThemeCatalog.palette(for: .default, scheme: dark ? .dark : .light)
        }
        self.init(
            initialText: initialText,
            fileURL: fileURL,
            initialPalette: provider(isDark),
            themeProvider: provider
        )
    }

    init(initialText: String, fileURL: URL?, initialPalette: ReaderThemePalette,
         themeProvider: @escaping (Bool) -> ReaderThemePalette) {
        let result = MarkdownRenderer.render(initialText)
        palette = initialPalette
        self.themeProvider = themeProvider
        lastResult = result
        html = HTMLTemplate.wrap(
            body: result.html,
            hasMermaid: result.hasMermaid,
            hasMath: result.hasMath,
            palette: initialPalette
        )
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
        themeObservation = NotificationCenter.default.addObserver(
            forName: .readerThemeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let dark = NSApplication.shared.effectiveAppearance.isDark
            self.applyTheme(self.themeProvider(dark))
        }
    }

    deinit {
        if isRegistered {
            NSFileCoordinator.removeFilePresenter(self)
        }
        if let themeObservation {
            NotificationCenter.default.removeObserver(themeObservation)
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

        guard let decodedText = decoded else { return }
        if decodedText != text { text = decodedText }
        let result = MarkdownRenderer.render(decodedText)
        lastResult = result
        let next = HTMLTemplate.wrap(
            body: result.html,
            hasMermaid: result.hasMermaid,
            hasMath: result.hasMath,
            palette: palette
        )
        if next != html {
            lastChangeSource = .disk
            html = next
        }
    }

    /// Internal so tests can drive a theme change without flipping the system.
    func appearanceDidChange(isDark dark: Bool) {
        applyTheme(themeProvider(dark))
    }

    /// Internal so tests can verify a family change without mutating shared defaults.
    func themeDidChange(to palette: ReaderThemePalette) {
        applyTheme(palette)
    }

    private func applyTheme(_ nextPalette: ReaderThemePalette) {
        guard nextPalette != palette else { return }
        palette = nextPalette
        lastChangeSource = .appearance
        html = HTMLTemplate.wrap(
            body: lastResult.html,
            hasMermaid: lastResult.hasMermaid,
            hasMath: lastResult.hasMath,
            palette: nextPalette
        )
    }
}
