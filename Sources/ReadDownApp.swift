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

        AppearanceMode.current.apply()
        resetQuickLook()
        _ = checkForUpdatesViewModel // eager: the Check for Updates menu item won't render if this resolves later
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.updaterController.startUpdater()
        }

        // Decided before the consent alert can mark itself prompted.
        let afterUpdate = SupportAsk.shouldShow(launch: LaunchHistory.current,
                                                consentPromptDue: UsageMetrics.isPromptDue)

        // application(_:open:) can land after this callback; restoring synchronously would resurrect the old session over the opened file.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.dismissOpenPanels()
            var nothingOpen = false
            if !self.launchedWithFiles && NSDocumentController.shared.documents.isEmpty {
                let restoredCount = DocumentSession.shared.restorePreviousSession()
                nothingOpen = restoredCount == 0 && NSDocumentController.shared.documents.isEmpty
            }
            if nothingOpen {
                afterUpdate ? AfterUpdateWindow.shared.show() : self.showWelcomeWindow()
            } else if afterUpdate {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.showUpdatedPillWhenActive()
                }
            }
        }

        UsageMetrics.sendIfDue()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            UsageMetrics.promptForConsentIfNeeded()
        }
    }

    private func showUpdatedPillWhenActive() {
        if NSApp.isActive, let frame = NSApp.mainWindow?.frame {
            ThanksPop.show(centeredIn: frame, style: .updated)
            return
        }
        var observer: NSObjectProtocol?
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            if let observer { NotificationCenter.default.removeObserver(observer) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard let frame = NSApp.mainWindow?.frame else { return }
                ThanksPop.show(centeredIn: frame, style: .updated)
            }
        }
    }

    /// AppKit's own restoration races `DocumentSession.restorePreviousSession()` and deadlocks window creation on inconsistent state; only ours runs.
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

    /// DocumentGroup opens only the first of several launch URLs; NSDocumentController opens each.
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
        // Closing via the red button would over-release the window and crash the next reopen.
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: WelcomeView(dismissWindow: { [weak self] in
            self?.dismissWelcomeWindow()
        }))
        window.makeKeyAndOrderFront(nil)
        welcomeWindow = window
    }

    /// The standard about panel clips a credits block this size.
    func showAboutWindow() {
        if let existing = aboutWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: WindowLayout.width, height: 0),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AboutView())
        window.setContentSize(window.contentView?.fittingSize ?? .zero)
        window.center()
        window.makeKeyAndOrderFront(nil)
        aboutWindow = window
    }

    /// Re-scan so Readdown's extension is picked up after a competing one is removed.
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

/// Windows appearing within the launch grace period are state-restored and keep their saved positions.
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

/// Sandboxed reopen needs security-scoped bookmarks; DocumentGroup's own restoration is unreliable.
/// Quit fires every `.onDisappear` unregister, so unregisters are ignored once terminating.
final class DocumentSession {
    static let shared = DocumentSession()
    private static let bookmarksKey = "openDocumentBookmarks"
    private var bookmarks: [String: Data] = [:]
    // Security-scoped grants, each balanced by a stop on close.
    private var scopedURLs: [String: URL] = [:]
    private var isTerminating = false
    private let queue = DispatchQueue(label: "com.heya.readdown.documentsession")

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Sparkle relaunches immediately after willTerminate; an async write wouldn't land.
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

    /// Returns the count attempted; the opens themselves are async.
    /// Runs once at launch before any document exists, so it bypasses `queue`.
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

/// Fires before first display; chrome configured any later misses AppKit's Tahoe corner-radius decision.
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
        Button("Check for Updates…") {
            viewModel.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}

@main
struct ReadDownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage(UsageMetrics.consentKey) private var shareUsageData = false
    @AppStorage(AppearanceMode.key) private var appearanceMode = AppearanceMode.system
    @AppStorage(SupportAsk.enabledKey) private var showSupportAsk = true

    /// Applies on set rather than via `onChange`, which doesn't fire for a menu Picker.
    private var appearanceSelection: Binding<AppearanceMode> {
        Binding(get: { appearanceMode }, set: { mode in
            appearanceMode = mode
            mode.apply()
            UsageMetrics.record(.appearance)
        })
    }

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
        // Scene-level: a window-level override is undone on SwiftUI's next update pass.
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
                Button("Copy Path") {
                    NotificationCenter.default.post(name: .copyFilePath, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .printItem) {
                Button("Export as PDF…") {
                    NotificationCenter.default.post(name: .exportPDF, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()

                Button("Print…") {
                    NotificationCenter.default.post(name: .printDocument, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Picker("Appearance", selection: appearanceSelection) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Divider()

                PageNavigationCommands()

                Divider()

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
                Button("Find…") {
                    NotificationCenter.default.post(name: .findInDocument, object: nil)
                }
                .keyboardShortcut(AppShortcut.find)

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
                    NSWorkspace.shared.open(AppLink.help)
                }
                Button("Keyboard Shortcuts…") {
                    ShortcutsHelp.show()
                }
                Button("Set as Default Markdown Reader…") {
                    DefaultAppHelp.show()
                }
                Button("Send Feedback…") {
                    NSWorkspace.shared.open(AppLink.issues)
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
                Toggle("Show Thank-You After Updates", isOn: $showSupportAsk)
            }
        }
    }

}

private struct PageNavigationCommands: View {
    @FocusedObject private var tableOfContents: TableOfContentsState?
    @FocusedObject private var history: HistoryState?

    var body: some View {
        Button(tableOfContents?.menuTitle ?? "Show Table of Contents") {
            NotificationCenter.default.post(name: .toggleTableOfContents, object: nil)
        }
        .keyboardShortcut(AppShortcut.tableOfContents)
        .disabled(tableOfContents?.isAvailable != true)

        Button("Back") {
            NotificationCenter.default.post(name: .navigateBack, object: nil)
        }
        .keyboardShortcut(AppShortcut.back)
        .disabled(history?.canGoBack != true)

        Button("Forward") {
            NotificationCenter.default.post(name: .navigateForward, object: nil)
        }
        .keyboardShortcut(AppShortcut.forward)
        .disabled(history?.canGoForward != true)
    }
}

struct AboutView: View {
    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    private var year: String { String(Calendar.current.component(.year, from: Date())) }

    var body: some View {
        VStack(spacing: WindowLayout.spacing) {
            WindowHeader(version: version)

            Divider()

            WindowMessage(
                title: "A clean, fast Markdown reader.",
                message: "Just open or hit space on any .md file to read it. Built by Natalia at [Eixo.design](https://eixo.design/?utm_source=readdown&utm_medium=app&utm_campaign=about) with help from its [contributors and sponsors](https://readdown.app/thanks)."
            )

            HStack(spacing: 8) {
                AboutActionButton(icon: "star.bubble", title: "Feedback",
                                  url: AppLink.review)
                AboutActionButton(icon: "ladybug", title: "Report a Bug",
                                  url: AppLink.issues)
                AboutActionButton(icon: "heart", title: "Support",
                                  url: URL(literal: "https://readdown.app/support?src=about"))
            }

            WindowFooter {
                Text("\u{00A9} \(year) Readdown")
                    .foregroundStyle(.secondary)
            }
        }
        .windowContent()
    }
}

private struct AboutActionButton: View {
    let icon: String
    let title: String
    let url: URL
    @State private var hovered = false

    var body: some View {
        Link(destination: url) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(ReaderTheme.link)
                    .frame(height: 20)
                Text(title)
                    .font(WindowType.tile)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: ReaderTheme.controlRadius, style: .continuous)
                    .fill(hovered ? ReaderTheme.tileHoverFill : ReaderTheme.tileFill)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
