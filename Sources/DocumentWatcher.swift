import Combine
import Foundation

/// Watches the document on disk and republishes rendered HTML when the file changes.
///
/// Uses `NSFilePresenter` so it cooperates with the sandbox and tracks atomic
/// replacement (editors that write-temp-then-rename, like VS Code). The initial
/// HTML is rendered synchronously in `init` so the first paint has no flash.
final class DocumentWatcher: NSObject, ObservableObject, NSFilePresenter {
    @Published private(set) var html: String
    let fileURL: URL?

    var presentedItemURL: URL? { fileURL }
    let presentedItemOperationQueue: OperationQueue = .main

    private let isDark: Bool
    private var isRegistered = false
    private var reloadWorkItem: DispatchWorkItem?

    init(initialText: String, fileURL: URL?, isDark: Bool) {
        let result = MarkdownRenderer.render(initialText)
        self.isDark = isDark
        self.html = HTMLTemplate.wrap(body: result.html, hasMermaid: result.hasMermaid, hasMath: result.hasMath, isDark: isDark)
        self.fileURL = fileURL
        super.init()
        if fileURL != nil {
            NSFileCoordinator.addFilePresenter(self)
            isRegistered = true
        }
    }

    deinit {
        if isRegistered {
            NSFileCoordinator.removeFilePresenter(self)
        }
    }

    func presentedItemDidChange() {
        // Coalesce rapid bursts — some editors fire several FS events for a single
        // save (truncate, write, rename). 50 ms is below human perception but
        // collapses a burst into one re-render.
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
        let next = HTMLTemplate.wrap(body: result.html, hasMermaid: result.hasMermaid, hasMath: result.hasMath, isDark: isDark)
        if next != html {
            html = next
        }
    }
}
