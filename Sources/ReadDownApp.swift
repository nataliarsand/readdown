import Sparkle
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
    var welcomeWindow: NSWindow?
    var updaterController: SPUStandardUpdaterController?
    @Published var checkForUpdatesViewModel: CheckForUpdatesViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        showWelcomeWindow()
        dismissDocumentGroupOpenPanel()
        scheduleQuickLookNotification()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
            self.updaterController = controller
            self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: controller.updater)
            controller.startUpdater()
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

    func dismissWelcomeWindow() {
        guard let window = welcomeWindow else { return }
        window.contentView = nil
        window.orderOut(nil)
        welcomeWindow = nil
    }

    // MARK: - Quick Look Notification

    private func scheduleQuickLookNotification() {
        let key = "hasPromptedQuickLook"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let center = UNUserNotificationCenter.current()

        let openAction = UNNotificationAction(
            identifier: "OPEN_SETTINGS",
            title: "Open Settings",
            options: .foreground
        )
        let category = UNNotificationCategory(
            identifier: "QUICKLOOK_SETUP",
            actions: [openAction],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])

        // Use .provisional so no permission dialog is shown to the user
        center.requestAuthorization(options: [.alert, .provisional]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "Quick Look Previews Enabled"
            content.body = "Hit Space on any .md file in Finder to preview it. You can manage this in Settings > Extensions > Quick Look."
            content.categoryIdentifier = "QUICKLOOK_SETUP"

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
            let request = UNNotificationRequest(
                identifier: "quicklook-setup",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == "OPEN_SETTINGS"
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            DispatchQueue.main.async { self.openExtensionsSettings() }
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }

    func openExtensionsSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences?Quick%20Look",
            "x-apple.systempreferences:com.apple.Extensions-Settings.QuickLookExtensions",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences"
        ]
        for urlString in urls {
            if let url = URL(string: urlString),
               NSWorkspace.shared.open(url) {
                return
            }
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preferences")!)
    }
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
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Readdown") {
                    showAboutPanel()
                }
            }
            CommandGroup(after: .appInfo) {
                if let viewModel = appDelegate.checkForUpdatesViewModel {
                    CheckForUpdatesView(viewModel: viewModel)
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
