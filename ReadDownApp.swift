import SwiftUI
import UniformTypeIdentifiers

@main
struct ReadDownApp: App {
    @AppStorage("hasPromptedDefault") private var hasPrompted = false
    @State private var showWelcome = false

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ContentView(document: file.document)
                .onAppear {
                    if !hasPrompted {
                        showWelcome = true
                    }
                }
                .sheet(isPresented: $showWelcome, onDismiss: { hasPrompted = true }) {
                    WelcomeView(
                        onSetDefault: { setAsDefaultMarkdownApp() },
                        onDismiss: { showWelcome = false }
                    )
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Readdown") {
                    showAboutPanel()
                }
            }
        }
    }

    private func setAsDefaultMarkdownApp() {
        let appURL = Bundle.main.bundleURL
        guard let mdType = UTType(filenameExtension: "md") else { return }
        try? NSWorkspace.shared.setDefaultApplication(at: appURL,
                                                       toOpen: mdType)
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
            string: "A clean, fast Markdown reader for macOS.\nJust open .md files and read — no editing, no clutter.\n\n",
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
