import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @AppStorage("hasPromptedDefault") private var hasPrompted = false
    @State private var showDefaultPrompt = false
    let dismissWindow: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)

            Text("Welcome to Readdown")
                .font(.title)
                .fontWeight(.semibold)

            Text("A clean, fast Markdown reader for macOS.")
                .foregroundStyle(.secondary)

            Button("Open a .md File") {
                openMarkdownFile()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding(40)
        .frame(width: 380, height: 340)
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
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            NSWorkspace.shared.open(url)
            dismissWindow()
        }
    }

    private func setAsDefaultMarkdownApp() {
        let appURL = Bundle.main.bundleURL
        guard let mdType = UTType(filenameExtension: "md") else { return }
        try? NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: mdType)
    }
}
