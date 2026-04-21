import SwiftUI
import UniformTypeIdentifiers

/// Reusable version pill — surface this anywhere a Readdown version needs to be displayed.
/// Reads from `CFBundleShortVersionString`, so the bundle is the single source of truth.
struct VersionBadge: View {
    var version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

    var body: some View {
        Text(version)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .quaternaryLabelColor))
            )
    }
}

/// Quick-reference for the app's keyboard shortcuts. Surfaced from the Help menu.
enum ShortcutsHelp {
    static func show() {
        let alert = NSAlert()
        alert.messageText = "Keyboard Shortcuts"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Got it")

        let host = NSHostingView(rootView: ShortcutsListView())
        host.frame = NSRect(x: 0, y: 0, width: 320, height: host.intrinsicContentSize.height)
        alert.accessoryView = host
        alert.runModal()
    }
}

private struct ShortcutsListView: View {
    private let groups: [(String, [(String, String)])] = [
        ("File", [
            ("⌘O", "Open file"),
            ("⌘W", "Close window"),
        ]),
        ("Find", [
            ("⌘F", "Find in document"),
            ("⌘G", "Find next"),
            ("⇧⌘G", "Find previous"),
            ("Esc", "Close find bar"),
        ]),
        ("Zoom", [
            ("⌘=", "Zoom in"),
            ("⌘-", "Zoom out"),
            ("⌘0", "Actual size"),
            ("⌘ + scroll", "Zoom (pinch also works)"),
        ]),
        ("Export", [
            ("⌘P", "Print"),
            ("⇧⌘E", "Export as PDF"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(groups, id: \.0) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.0.uppercased())
                        .font(.caption2)
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                        ForEach(group.1, id: \.0) { row in
                            GridRow {
                                Text(row.0)
                                    .font(.system(.callout, design: .monospaced))
                                    .frame(width: 96, alignment: .leading)
                                Text(row.1)
                                    .font(.callout)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Shared "set as default" helpers surfaced from the welcome and the Help menu.
enum DefaultAppHelp {
    /// macOS 14, 15, and 26.0–26.3.x silently reject `NSWorkspace.setDefaultApplication` from
    /// sandboxed apps (sandboxd logs "Unentitled request to set default handler"). Apple
    /// re-enabled the sandboxed path in macOS 26.4. On anything older, calling the API looks
    /// like it worked but nothing changes — so we skip straight to the manual instructions.
    static func nativePromptLikelyWorks() -> Bool {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.majorVersion > 26 || (v.majorVersion == 26 && v.minorVersion >= 4)
    }

    static func show() {
        let alert = NSAlert()
        alert.messageText = "Set Readdown as your default Markdown reader"
        alert.informativeText = """
        1. In Finder, find any .md file.
        2. Right-click the file → Get Info.
        3. Under "Open with:", choose Readdown.
        4. Click "Change All…" to apply to every .md file.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Got it")
        alert.runModal()
    }
}

struct WelcomeView: View {
    @AppStorage("hasPromptedDefault") private var hasPrompted = false
    @AppStorage("lastLaunchedBuild") private var lastLaunchedBuild = ""
    @State private var qlEnabled = false
    @State private var isPostUpdate = false
    @State private var isDefault = false
    let dismissWindow: () -> Void

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            if isPostUpdate {
                postUpdateContent
            } else {
                freshInstallContent
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .frame(width: 320, height: 360)
        .onAppear(perform: onAppear)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshSetupStatus()
        }
    }

    private func onAppear() {
        let isFreshInstall = lastLaunchedBuild.isEmpty && !hasPrompted
        isPostUpdate = !isFreshInstall
        lastLaunchedBuild = currentBuild
        refreshSetupStatus()

        // On fresh install with a macOS that actually honours sandboxed default-app requests,
        // trigger the native prompt proactively. The user downloaded this app — asking whether
        // to open .md files with it now is obviously on-topic, and the system dialog is clearer
        // than any confirmation we could build ourselves.
        if isFreshInstall && !isDefault && DefaultAppHelp.nativePromptLikelyWorks() {
            hasPrompted = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                requestDefaultAppChange()
            }
        }
    }

    private var freshInstallContent: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("Welcome to Readdown")
                    .font(.headline)
                VersionBadge()
            }

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

            Spacer(minLength: 0)

            // Only surface these when the user actually needs to act. On modern macOS the
            // default-app flow is automatic (see onAppear); this link is only shown on older
            // macOS where we can't trigger the native prompt reliably.
            if !isDefault && !DefaultAppHelp.nativePromptLikelyWorks() {
                Button("Set Readdown as default for .md files") {
                    DefaultAppHelp.show()
                    refreshSetupStatus()
                }
                .font(.caption)
                .buttonStyle(.link)
            }

            if !qlEnabled {
                VStack(spacing: 4) {
                    Text("Preview .md files with Space in Finder")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    Button("Enable Quick Look") {
                        openExtensionsSettings()
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
            }

            Divider()

            footerLinks
        }
    }

    private var postUpdateContent: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("Readdown")
                    .font(.headline)
                VersionBadge()
            }

            Link(destination: URL(string: "https://readdown.app/#changelog")!) {
                Text("See what's new \u{2192}")
                    .font(.subheadline)
            }

            Button("Open a .md File") {
                openMarkdownFile()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 2)

            Spacer(minLength: 0)

            if !qlEnabled {
                VStack(spacing: 4) {
                    Text("Preview .md files with Space in Finder")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    Button("Enable Quick Look") {
                        openExtensionsSettings()
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
            }

            VStack(spacing: 2) {
                Text("Found something off?")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Link("Report an issue on GitHub",
                     destination: URL(string: "https://github.com/nataliarsand/readdown/issues/new")!)
                    .font(.caption)
            }

            Divider()

            footerLinks
        }
    }

    private var footerLinks: some View {
        HStack {
            Link("readdown.app", destination: URL(string: "https://readdown.app")!)
                .font(.caption)
            Spacer()
            Link(destination: URL(string: "https://www.paypal.com/donate/?hosted_button_id=EFG82PKZJU3RC")!) {
                Text("Buy me a coffee \u{2615}")
                    .font(.caption)
            }
        }
    }

    private func refreshSetupStatus() {
        isDefault = isReaddownDefaultForMarkdown()
        qlEnabled = isQLExtensionEnabled()
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

    /// Triggers the macOS native "Use Readdown? / Keep TextEdit?" confirmation when the OS
    /// supports it; otherwise falls back to manual instructions.
    private func requestDefaultAppChange() {
        guard DefaultAppHelp.nativePromptLikelyWorks() else {
            DefaultAppHelp.show()
            refreshSetupStatus()
            return
        }
        let appURL = Bundle.main.bundleURL
        var seen = Set<String>()
        var utis: [UTType] = []
        for ext in ["md", "markdown", "mdown", "mkd"] {
            if let uti = UTType(filenameExtension: ext), seen.insert(uti.identifier).inserted {
                utis.append(uti)
            }
        }
        if let fallback = UTType("net.daringfireball.markdown"), seen.insert(fallback.identifier).inserted {
            utis.append(fallback)
        }
        for uti in utis {
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: uti) { _ in
                DispatchQueue.main.async { refreshSetupStatus() }
            }
        }
    }

    private func isReaddownDefaultForMarkdown() -> Bool {
        guard let uti = UTType(filenameExtension: "md") else { return false }
        let current = NSWorkspace.shared.urlForApplication(toOpen: uti)?.resolvingSymlinksInPath().path
        let ours = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        return current == ours
    }

    /// `pluginkit -m -i <id>` emits `+  <id>` when the extension is enabled and `-  <id>` when
    /// it's disabled but still registered. If the sandbox blocks the process, or the output is
    /// empty, default to "enabled" — nagging the user about an extension that is actually on is
    /// worse than quietly missing one that's off.
    private func isQLExtensionEnabled() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let qlID = bundleID + ".ReadDownQuickLook"
        guard let output = Process.run("/usr/bin/pluginkit", arguments: ["-m", "-i", qlID]),
              !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        for raw in output.split(separator: "\n") {
            let line = raw.drop(while: { $0 == " " })
            if line.contains(qlID) { return line.hasPrefix("+") }
        }
        return true
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
