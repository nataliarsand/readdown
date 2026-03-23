import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @AppStorage("hasPromptedDefault") private var hasPrompted = false
    @State private var showDefaultPrompt = false
    @State private var qlEnabled = false
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

            // Quick Look setup callout
            if !qlEnabled {
                VStack(spacing: 6) {
                    Text("Enable Quick Look to preview .md files with Space in Finder.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    Button("Open Extensions Settings") {
                        openExtensionsSettings()
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
            } else {
                HStack(spacing: 4) {
                    Text("Quick Look not working?")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Link("Setup guide",
                         destination: URL(string: "https://heya.studio/readdown/#setup")!)
                        .font(.caption)
                }
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
            checkQLExtensionStatus()
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
            dismissWindow()
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
    }

    private func setAsDefaultMarkdownApp() {
        let appURL = Bundle.main.bundleURL
        guard let mdType = UTType(filenameExtension: "md") else { return }
        try? NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: mdType)
    }

    private func checkQLExtensionStatus() {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let qlID = bundleID + ".ReadDownQuickLook"
        let output = Process.run("/usr/bin/pluginkit", arguments: ["-m", "-i", qlID])
        qlEnabled = output?.contains(qlID) == true
    }

    private func openExtensionsSettings() {
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

private extension Process {
    static func run(_ path: String, arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
