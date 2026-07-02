import SwiftUI

/// Window background matches the page color in `HTMLTemplate.swift` (`--bg`)
/// so the title bar area, resize flashes, and rubber-band overscroll all read
/// as one surface with the document.
enum ReaderTheme {
    static let pageBackground = dynamic(light: (0xFC, 0xFC, 0xFB), dark: (0x0D, 0x11, 0x17))

    private static func dynamic(light: (Int, Int, Int), dark: (Int, Int, Int)) -> NSColor {
        NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat(rgb.0) / 255,
                green: CGFloat(rgb.1) / 255,
                blue: CGFloat(rgb.2) / 255,
                alpha: 1
            )
        }
    }
}

final class FindState: ObservableObject {
    @Published var isVisible = false
    @Published var searchText = ""
    @Published var totalMatches = 0
    @Published var currentMatch = 0  // 1-indexed; 0 means no active match
}

struct ContentView: View {
    @StateObject private var watcher: DocumentWatcher
    let baseURL: URL?
    let fileURL: URL?
    @StateObject private var findState = FindState()
    @State private var window: NSWindow?
    @State private var pillText: String?
    @State private var pillDismissWork: DispatchWorkItem?

    init(document: MarkdownDocument, baseURL: URL?, fileURL: URL? = nil) {
        // Resolve dark vs light at template-generation time so the embedded
        // Mermaid theme matches the page palette. WKWebView's JS-side dark-mode
        // signals (`matchMedia`, `getComputedStyle` of var()-resolved colors)
        // are unreliable, so the source of truth is Swift's `NSAppearance`.
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        _watcher = StateObject(wrappedValue: DocumentWatcher(initialText: document.text, fileURL: fileURL, isDark: isDark))
        self.baseURL = baseURL
        self.fileURL = fileURL
    }

    var body: some View {
        ZStack(alignment: .top) {
            WebView(baseURL: baseURL, findState: findState, watcher: watcher)
                .frame(minWidth: 500, minHeight: 400)
                .ignoresSafeArea(.container, edges: .top)
                .overlay(alignment: .bottomTrailing) {
                    if let pillText {
                        Text(pillText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.regularMaterial, in: Capsule())
                            .padding(16)
                            .transition(.opacity)
                    }
                }
                .background(WindowAccessor { window in
                    self.window = window
                    WindowCascader.shared.cascade(window)
                    configureWindowChrome(window)
                })

            if findState.isVisible {
                FindBar(state: findState)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .toolbar {
            // On macOS 26 the group renders as a floating Liquid Glass capsule
            // over the document (Craft-style); earlier systems draw bare icons.
            ToolbarItemGroup(placement: .primaryAction) {
                copyButton
                searchButton
                showInFinderButton
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .findInDocument)) { _ in
            // Only the front-most document should respond. `window?.isKeyWindow` asks the window
            // itself instead of comparing object references against `NSApp.keyWindow`, which can
            // mismatch when SwiftUI re-wraps hosting windows.
            guard window?.isKeyWindow == true else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                findState.isVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showInFinder)) { _ in
            guard window?.isKeyWindow == true, let fileURL else { return }
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
        .onChange(of: watcher.html) { _ in
            showPill("Updated")
        }
    }

    // Toolbar actions. `.help` sits on the Image, not the Button — tooltips on
    // toolbar Buttons don't render. Accessibility labels keep VoiceOver from
    // falling back to the SF Symbol names ("Copy", "Search", "Move").
    private var copyButton: some View {
        Button(action: copyMarkdown) {
            Image(systemName: "doc.on.doc")
                .help("Copy Markdown")
        }
        .accessibilityLabel("Copy Markdown")
    }

    private var searchButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                findState.isVisible = true
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .help("Find in Document (⌘F)")
        }
        .accessibilityLabel("Find in Document")
    }

    private var showInFinderButton: some View {
        Button {
            guard let fileURL else { return }
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } label: {
            Image(systemName: "folder")
                .help("Show in Finder (⇧⌘R)")
        }
        .accessibilityLabel("Show in Finder")
        .disabled(fileURL == nil)
    }

    /// Transient status pill at the card's bottom-trailing corner ("Updated", "Copied").
    private func showPill(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) {
            pillText = text
        }
        pillDismissWork?.cancel()
        let work = DispatchWorkItem {
            withAnimation(.easeIn(duration: 0.4)) {
                pillText = nil
            }
        }
        pillDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// Copies the document's raw markdown source (the whole file) to the clipboard.
    private func copyMarkdown() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(watcher.text, forType: .string)
        showPill("Copied")
    }

    /// Configure the NSWindow for a Bear/Messages-style chrome:
    /// - Content extends behind the toolbar via `.fullSizeContentView`; the
    ///   toolbar icons float over it (Liquid Glass capsule on macOS 26).
    /// - No hairline separator between the toolbar and the content.
    /// - Window background uses `ReaderTheme.pageBackground` so the toolbar
    ///   area matches the document instead of the default system window gray.
    /// - An `NSToolbar` is required so macOS Tahoe applies the larger window
    ///   corner radius (Apple scales the radius to toolbar height; a window
    ///   without a toolbar gets the smaller, title-bar-only radius). SwiftUI's
    ///   `.toolbar` items normally install one; the empty fallback covers
    ///   windows where that hasn't happened yet.
    ///
    /// We leave the system title visible — the macOS Document Title Menu (rename,
    /// move to, duplicate) is bolted to it, and the dropdown disappears the moment
    /// `titleVisibility = .hidden` is set.
    private func configureWindowChrome(_ window: NSWindow) {
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        if window.toolbar == nil {
            window.toolbar = NSToolbar()
        }
        // `.unifiedCompact` collapses title bar + toolbar into a single row
        // (title sits inline with traffic lights, like Messages). `.unified`
        // is taller and looks asymmetric with only a few icon items.
        window.toolbarStyle = .unifiedCompact
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = ReaderTheme.pageBackground
    }
}

struct FindBar: View {
    @ObservedObject var state: FindState
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Find", text: $state.searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { NotificationCenter.default.post(name: .findNext, object: nil) }

            if !state.searchText.isEmpty {
                Text(matchStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            Button(action: { NotificationCenter.default.post(name: .findPrevious, object: nil) }) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(state.searchText.isEmpty)

            Button(action: { NotificationCenter.default.post(name: .findNext, object: nil) }) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(state.searchText.isEmpty)

            Button(action: close) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .frame(maxWidth: 380)
        .padding(.horizontal, 16)
        .onAppear { searchFocused = true }
    }

    private var matchStatus: String {
        if state.totalMatches == 0 { return "No results" }
        return "\(state.currentMatch) of \(state.totalMatches)"
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.15)) {
            state.isVisible = false
        }
        state.searchText = ""
    }
}
