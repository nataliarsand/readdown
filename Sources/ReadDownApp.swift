import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var welcomeWindow: NSWindow?
    let updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    lazy var checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updaterController.updater)

    func applicationDidFinishLaunching(_ notification: Notification) {
        showWelcomeWindow()
        dismissDocumentGroupOpenPanel()
        resetQuickLook()
        _ = checkForUpdatesViewModel // force lazy init
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.updaterController.startUpdater()
        }
    }

    /// DocumentGroup shows an open panel on launch when no document is restored.
    /// Dismiss it after a short delay so the welcome window takes priority.
    private func dismissDocumentGroupOpenPanel() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let welcome = self?.welcomeWindow else { return }
            welcome.makeKeyAndOrderFront(nil)
            for window in NSApp.windows {
                if window !== welcome && window is NSOpenPanel {
                    window.close()
                }
            }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
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
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 360),
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
final class WindowCascader {
    static let shared = WindowCascader()
    private var nextPoint: NSPoint = .zero
    private var seen = Set<Int>()

    func cascade(_ window: NSWindow) {
        guard !seen.contains(window.windowNumber) else { return }
        seen.insert(window.windowNumber)
        nextPoint = window.cascadeTopLeft(from: nextPoint)
    }
}

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                callback(window)
            }
        }
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
    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ContentView(
                document: file.document,
                baseURL: file.fileURL?.deletingLastPathComponent()
            )
                .onAppear {
                    appDelegate.dismissWelcomeWindow()
                }
        }
        .defaultSize(width: 880, height: 720)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Readdown") {
                    showAboutPanel()
                }
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(viewModel: appDelegate.checkForUpdatesViewModel)
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
            }
        }
    }

    private func showAboutPanel() {
        let credits = NSMutableAttributedString()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.paragraphSpacing = 8

        let centeredAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]

        credits.append(NSAttributedString(
            string: "A clean, fast Markdown reader for macOS.\nJust open or hit space on any .md file to read it.\n\n",
            attributes: centeredAttrs
        ))

        let linkParagraph = NSMutableParagraphStyle()
        linkParagraph.alignment = .center
        let donateURL = URL(string: "https://www.paypal.com/donate/?hosted_button_id=EFG82PKZJU3RC")!
        let linkAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .link: donateURL,
            .paragraphStyle: linkParagraph
        ]
        credits.append(NSAttributedString(
            string: "Buy me a coffee \u{2615}",
            attributes: linkAttrs
        ))

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Readdown",
            .credits: credits,
            .applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            .version: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        ])
    }
}
