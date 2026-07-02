import SwiftUI

/// Window background matches the page color in `HTMLTemplate.swift` (`--bg`)
/// so the title bar area, resize flashes, and rubber-band overscroll all read
/// as one surface with the document.
enum ReaderTheme {
    static let pageBackground = dynamic(light: (0xFC, 0xFC, 0xFB), dark: (0x0D, 0x11, 0x17))
    /// Floating action pill — solid, slightly elevated above the page.
    /// Dark value matches the dark `--code-bg` so it reads as an elevated surface.
    static let pill = dynamic(light: (0xFF, 0xFF, 0xFF), dark: (0x16, 0x1B, 0x22))

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
            // WebView and header pills share one container that extends behind
            // the title bar, so the pills ride in the title-bar row itself
            // (ChatGPT/Craft-style floating header over the document).
            ZStack(alignment: .top) {
                WebView(baseURL: baseURL, findState: findState, watcher: watcher)
                    .frame(minWidth: 500, minHeight: 400)
                HStack(spacing: 0) {
                    titlePill
                    Spacer(minLength: 12)
                    actionPill
                }
                // Leading padding clears the native traffic lights.
                .padding(.top, 6)
                .padding(.leading, 76)
                .padding(.trailing, 12)
            }
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

    /// Floating title pill: the document name in its own capsule, next to the
    /// traffic lights. Replaces the system title, which is hidden — see
    /// `configureWindowChrome`.
    private var titlePill: some View {
        Text(fileURL?.lastPathComponent ?? "Untitled")
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Color(nsColor: ReaderTheme.pill), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    /// Floating action pill at the window's top-trailing corner, sitting in the
    /// title-bar row over the document (Craft-style). Custom rather than a
    /// SwiftUI `.toolbar` on purpose: toolbar items ship with the system glass
    /// capsule, an opaque header band, and non-working tooltips.
    private var actionPill: some View {
        HStack(spacing: 2) {
            PillIconButton(icon: "doc.on.doc", label: "Copy Markdown",
                           tooltip: "Copy Markdown", action: copyMarkdown)
            PillIconButton(icon: "magnifyingglass", label: "Find in Document",
                           tooltip: "Find in Document (⌘F)") {
                withAnimation(.easeOut(duration: 0.15)) {
                    findState.isVisible = true
                }
            }
            PillIconButton(icon: "folder", label: "Show in Finder",
                           tooltip: "Show in Finder (⇧⌘R)",
                           disabled: fileURL == nil) {
                guard let fileURL else { return }
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            }
        }
        .padding(4)
        .background(Color(nsColor: ReaderTheme.pill), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
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
    /// - Content extends behind the title bar via `.fullSizeContentView`; the
    ///   header is fully transparent (no material, no separator) and the
    ///   custom action pill floats over the document in that row.
    /// - Window background uses `ReaderTheme.pageBackground` so the header
    ///   area matches the document instead of the default system window gray.
    /// - An empty `NSToolbar` is attached so macOS Tahoe applies the larger
    ///   window corner radius (Apple scales the radius to toolbar height; a
    ///   window without a toolbar gets the smaller, title-bar-only radius).
    ///   It must stay empty — real toolbar items would bring back the system
    ///   toolbar background band.
    /// - The system title is hidden; the custom title pill shows the file name
    ///   instead. This trades away the macOS Document Title Menu (rename, move
    ///   to, duplicate), which is bolted to the system title — Show in Finder
    ///   and the File menu cover those flows.
    private func configureWindowChrome(_ window: NSWindow) {
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        if window.toolbar == nil {
            window.toolbar = NSToolbar()
        }
        // `.unifiedCompact` collapses title bar + toolbar into a single row
        // (title sits inline with traffic lights, like Messages). `.unified`
        // is taller and leaves an empty second row when the toolbar has no
        // items, which looks asymmetric.
        window.toolbarStyle = .unifiedCompact
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.titleVisibility = .hidden
        window.backgroundColor = ReaderTheme.pageBackground
    }
}

/// Icon button inside the floating action pill: rounded hover highlight,
/// tooltip, and an explicit VoiceOver label (SF Symbol names are not it).
private struct PillIconButton: View {
    let icon: String
    let label: String
    let tooltip: String
    var disabled = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(disabled ? .tertiary : .secondary)
                .frame(width: 30, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(hovered && !disabled ? 0.07 : 0))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovered = $0 }
        .help(tooltip)
        .accessibilityLabel(label)
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
