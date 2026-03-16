import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @AppStorage("hasPromptedDefault") private var hasPrompted = false
    @State private var showDefaultPrompt = false
    let dismissWindow: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Text("Thanks for downloading Readdown!")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("A clean, fast Markdown reader for macOS.\nJust open or hit space on any .md file to read it.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .font(.subheadline)

            Button("Open a .md File") {
                openMarkdownFile()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 2)

            Spacer().frame(height: 0)

            HStack(spacing: 4) {
                Text("Quick Look not working?")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Link("Setup guide",
                     destination: URL(string: "https://heya.studio/readdown/#setup")!)
                    .font(.caption)
            }

            Divider()
                .padding(.horizontal, 30)

            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    Text("Check out other apps at ")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Link("heya.studio",
                         destination: URL(string: "https://heya.studio")!)
                        .font(.subheadline)
                }

                HStack(spacing: 4) {
                    Text("If you enjoy it,")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Link("buy me a coffee \u{2615}",
                         destination: URL(string: "https://www.paypal.com/donate/?hosted_button_id=EFG82PKZJU3RC")!)
                        .font(.subheadline)
                }
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .frame(width: 320, height: 360)
        .onAppear {
            if !hasPrompted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showDefaultPrompt = true
                }
            }
        }
        .alert("Set as Default Markdown Reader?", isPresented: $showDefaultPrompt) {
            Button("Set as Default") {
                setAsDefaultMarkdownApp()
                hasPrompted = true
            }
            .keyboardShortcut(.defaultAction)
            Button("Skip", role: .cancel) {
                hasPrompted = true
            }
        } message: {
            Text("Set Readdown as your default app for .md files?")
        }
    }

    private func openMarkdownFile() {
        dismissWindow()

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            NSWorkspace.shared.open(url)
        }
    }

    private func setAsDefaultMarkdownApp() {
        let appURL = Bundle.main.bundleURL
        guard let mdType = UTType(filenameExtension: "md") else { return }
        try? NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: mdType)
    }
}
