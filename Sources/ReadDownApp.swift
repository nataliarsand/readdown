import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var welcomeWindow: NSWindow?
    var aboutWindow: NSWindow?
    let updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    lazy var checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updaterController.updater)
    private var launchedWithFiles = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Skip the launch sequence when hosting the test runner.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        resetQuickLook()
        _ = checkForUpdatesViewModel // force lazy init
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.updaterController.startUpdater()
        }

        // Defer the restore decision. macOS may deliver application(_:open:) —
        // which sets launchedWithFiles and opens the clicked document — around
        // or just after this callback, so restoring synchronously here would
        // resurrect the whole previous session before we know a file was opened.
        // Waiting a beat, then skipping restore if a file was opened (flag set,
        // or a document already exists), means opening a file shows just that
        // file while a plain Dock/Spotlight launch still restores the old set.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.dismissOpenPanels()
            if self.launchedWithFiles || !NSDocumentController.shared.documents.isEmpty {
                return
            }
            let restoredCount = DocumentSession.shared.restorePreviousSession()
            if restoredCount == 0 && NSDocumentController.shared.documents.isEmpty {
                self.showWelcomeWindow()
            }
        }

        UsageMetrics.sendIfDue()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            UsageMetrics.promptForConsentIfNeeded()
        }
    }

    /// We manage session restoration ourselves via `DocumentSession.restorePreviousSession()`
    /// — see `applicationDidFinishLaunching` above. AppKit's automatic
    /// `NSDocumentControllerPersistentRestoration` mechanism (which this method
    /// opts into when it returns `true`) was racing with our restoration: both
    /// fired concurrently at launch, AppKit had no file-existence guard, and the
    /// two flows deadlocked SwiftUI's `AppWindowsController.makeWindowController`
    /// when state was inconsistent (force-quit with files since deleted, Time
    /// Machine restore, etc.) — the app would hang at launch with no window.
    /// Return `false` so AppKit skips its own restoration and only ours runs.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    private func dismissOpenPanels() {
        for window in NSApp.windows where window is NSOpenPanel {
            window.close()
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    /// SwiftUI's DocumentGroup only opens the first URL when multiple files are
    /// passed at launch (Finder multi-select → Open With Readdown). Route through
    /// NSDocumentController so each file gets its own window. Setting the flag
    /// also tells `applicationDidFinishLaunching` to skip session restoration —
    /// the user opened these files explicitly, they don't want the old set too.
    func application(_ application: NSApplication, open urls: [URL]) {
        launchedWithFiles = true
        for url in urls {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showWelcomeWindow()
        }
        return true
    }

    func showWelcomeWindow() {
        if let existing = welcomeWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: WelcomeView.windowSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        window.contentView = NSHostingView(rootView: WelcomeView(dismissWindow: { [weak self] in
            self?.dismissWelcomeWindow()
        }))
        window.makeKeyAndOrderFront(nil)
        welcomeWindow = window
    }

    /// Custom About window — replaces the standard about panel, which clips a
    /// credits block this size and reads as a wall of links.
    func showAboutWindow() {
        if let existing = aboutWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: AboutView.windowSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: AboutView())
        window.makeKeyAndOrderFront(nil)
        aboutWindow = window
    }

    /// Reset Quick Look so the system re-scans extensions.
    /// Ensures Readdown's QL extension is picked up if a competing one was removed.
    private func resetQuickLook() {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
            process.arguments = ["-r"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        }
    }

    func dismissWelcomeWindow() {
        guard let window = welcomeWindow else { return }
        window.contentView = nil
        window.orderOut(nil)
        welcomeWindow = nil
    }

}

/// Offsets each new document window so multiple open files don't stack on top of each other.
/// Windows that appear during the launch grace period are assumed to be coming from macOS state
/// restoration and keep their saved positions instead of getting cascaded away.
final class WindowCascader {
    static let shared = WindowCascader()
    private static let launchGrace: TimeInterval = 2.0
    private let launchTime = Date()
    private var nextPoint: NSPoint = .zero
    private var seen = Set<Int>()

    func cascade(_ window: NSWindow) {
        guard !seen.contains(window.windowNumber) else { return }
        seen.insert(window.windowNumber)
        guard Date().timeIntervalSince(launchTime) > Self.launchGrace else { return }
        nextPoint = window.cascadeTopLeft(from: nextPoint)
    }
}

/// Persists which document URLs are currently open across launches via
/// security-scoped bookmarks. Sandboxed apps lose access to file URLs after
/// quit unless they keep a bookmark, and SwiftUI DocumentGroup doesn't
/// implement state restoration reliably — so we track ourselves.
///
/// During quit, every ContentView's `.onDisappear` fires and would normally
/// unregister its URL — wiping the session before we get to save it. We watch
/// `NSApplication.willTerminateNotification` and ignore unregister calls once
/// the app is terminating, so the last-known set of open files is what gets
/// restored on next launch.
final class DocumentSession {
    static let shared = DocumentSession()
    private static let bookmarksKey = "openDocumentBookmarks"
    private var bookmarks: [String: Data] = [:]
    // URLs we hold a security-scoped access grant on (from restored bookmarks).
    // Tracked so each start can be balanced with a stop when the document closes.
    private var scopedURLs: [String: URL] = [:]
    private var isTerminating = false
    private let queue = DispatchQueue(label: "com.heya.readdown.documentsession")

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Synchronous flush: Sparkle relaunches the app immediately after
            // willTerminate, so we can't trust async writes to land. Block the
            // shutdown long enough to persist + force the defaults to disk.
            self?.queue.sync {
                self?.isTerminating = true
                self?.persistLocked()
            }
            UserDefaults.standard.synchronize()
        }
    }

    func register(_ url: URL) {
        queue.async {
            let key = url.path
            guard self.bookmarks[key] == nil else { return }
            do {
                let data = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                self.bookmarks[key] = data
                self.persistLocked()
            } catch {
                NSLog("[DocumentSession] bookmarkData failed for %@: %@",
                      url.path, error.localizedDescription)
            }
        }
    }

    func unregister(_ url: URL) {
        queue.async {
            guard !self.isTerminating else { return }
            self.bookmarks.removeValue(forKey: url.path)
            // Release the security-scoped grant taken in restorePreviousSession().
            if let scoped = self.scopedURLs.removeValue(forKey: url.path) {
                scoped.stopAccessingSecurityScopedResource()
            }
            self.persistLocked()
        }
    }

    private func persistLocked() {
        let values = Array(bookmarks.values)
        UserDefaults.standard.set(values, forKey: Self.bookmarksKey)
    }

    /// Reopens documents from the previous session. Returns the count attempted.
    /// The actual `openDocument` calls are async; the count is what we asked for.
    ///
    /// Called once at launch, before any document window exists — so it mutates
    /// `bookmarks`/`scopedURLs` directly. Anything running later must use `queue`.
    @discardableResult
    func restorePreviousSession() -> Int {
        guard let saved = UserDefaults.standard.array(forKey: Self.bookmarksKey) as? [Data] else { return 0 }
        var attempted = 0
        for data in saved {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else { continue }
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            // Hold security-scoped access for the restored URL; balanced by a
            // stop in unregister(_:) when the document window closes.
            if url.startAccessingSecurityScopedResource() {
                scopedURLs[url.path] = url
            }
            bookmarks[url.path] = data
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            attempted += 1
        }
        return attempted
    }
}

/// Calls back the moment the hosting view is added to an `NSWindow`, *before*
/// the window is first displayed. We avoid `DispatchQueue.main.async` here so
/// chrome configuration (toolbar, fullSizeContentView, background) is in place
/// before AppKit decides the Tahoe corner radius. Async ran after first
/// display, which left some windows (e.g. those opened directly from Finder)
/// with the smaller "title-bar-only" radius.
final class WindowAccessNSView: NSView {
    var onWindow: ((NSWindow) -> Void)?
    private var notified = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !notified, let window else { return }
        notified = true
        onWindow?(window)
    }
}

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowAccessNSView()
        view.onWindow = callback
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject var viewModel: CheckForUpdatesViewModel

    var body: some View {
        Button("Check for Updates...") {
            viewModel.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}

@main
struct ReadDownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage(UsageMetrics.consentKey) private var shareUsageData = false
    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ContentView(
                document: file.document,
                baseURL: file.fileURL?.deletingLastPathComponent(),
                fileURL: file.fileURL
            )
                .onAppear {
                    appDelegate.dismissWelcomeWindow()
                    UsageMetrics.record(.documentOpened)
                    if let url = file.fileURL {
                        DocumentSession.shared.register(url)
                    }
                }
                .onDisappear {
                    if let url = file.fileURL {
                        DocumentSession.shared.unregister(url)
                    }
                }
        }
        // Hidden title bar at the scene level, so SwiftUI never installs a
        // toolbar/title of its own. A window-level override alone gets undone
        // on SwiftUI's next update pass — the header band would reappear a
        // moment after the window opens. The pills in ContentView are the
        // visible header.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 880, height: 720)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Readdown") {
                    appDelegate.showAboutWindow()
                }
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(viewModel: appDelegate.checkForUpdatesViewModel)
            }
            CommandGroup(after: .saveItem) {
                Button("Show in Finder") {
                    NotificationCenter.default.post(name: .showInFinder, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .printItem) {
                Button("Export as PDF...") {
                    NotificationCenter.default.post(name: .exportPDF, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()

                Button("Print...") {
                    NotificationCenter.default.post(name: .printDocument, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Zoom In") {
                    NotificationCenter.default.post(name: .zoomIn, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    NotificationCenter.default.post(name: .zoomOut, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    NotificationCenter.default.post(name: .zoomReset, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)
            }
            CommandGroup(replacing: .textEditing) {
                Button("Find...") {
                    NotificationCenter.default.post(name: .findInDocument, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Find Next") {
                    NotificationCenter.default.post(name: .findNext, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Find Previous") {
                    NotificationCenter.default.post(name: .findPrevious, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("Readdown Help") {
                    NSWorkspace.shared.open(URL(string: "https://readdown.app/#faq")!)
                }
                Button("Keyboard Shortcuts…") {
                    ShortcutsHelp.show()
                }
                Button("Set as Default Markdown Reader…") {
                    DefaultAppHelp.show()
                }
                Button("Send Feedback...") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/nataliarsand/readdown/issues")!)
                }

                Divider()

                // Via setConsent so switching off also clears pending counts.
                Toggle("Share Anonymous Usage Data", isOn: Binding(
                    get: { shareUsageData },
                    set: { granted in
                        UsageMetrics.setConsent(granted)
                        shareUsageData = granted
                    }
                ))
            }
        }
    }

}

/// Custom About window content. Hierarchy over a link dump: icon, name,
/// version, tagline; then attribution as one sentence with subtle links; then
/// the support actions as a row of buttons.
struct AboutView: View {
    static let windowSize = NSSize(width: 380, height: 452)

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 76, height: 76)

            VStack(spacing: 3) {
                Text("Readdown")
                    .font(.system(size: 22, weight: .semibold))
                Text("Version \(version)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("A clean, fast Markdown reader for macOS. Just open or hit space on any .md file to read it.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Divider().frame(width: 160)

            Text("Built by Natalia at [Eixo.design](https://eixo.design/?utm_source=readdown&utm_medium=app&utm_campaign=about) with help from its [contributors](https://github.com/nataliarsand/readdown/graphs/contributors).")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .tint(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                AboutActionButton(icon: "star.bubble", title: "Feedback",
                                  url: "https://www.producthunt.com/products/readdown/reviews/new")
                AboutActionButton(icon: "ladybug", title: "Report a Bug",
                                  url: "https://github.com/nataliarsand/readdown/issues")
                AboutActionButton(icon: "cup.and.saucer", title: "Buy a Coffee",
                                  url: "https://www.paypal.com/donate/?hosted_button_id=EFG82PKZJU3RC")
            }

            Link("readdown.app", destination: URL(string: "https://readdown.app")!)
                .font(.caption)
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(width: AboutView.windowSize.width)
    }
}

/// A compact icon+label card used for the About window's support actions.
private struct AboutActionButton: View {
    let icon: String
    let title: String
    let url: String
    @State private var hovered = false

    var body: some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                Text(title)
                    .font(.caption2)
            }
            .foregroundStyle(.primary)
            .frame(width: 92, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(hovered ? 0.10 : 0.05))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
