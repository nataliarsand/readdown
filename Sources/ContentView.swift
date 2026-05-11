import SwiftUI

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
    @State private var showUpdatedPill = false
    @State private var pillDismissWork: DispatchWorkItem?

    init(document: MarkdownDocument, baseURL: URL?, fileURL: URL? = nil) {
        _watcher = StateObject(wrappedValue: DocumentWatcher(initialText: document.text, fileURL: fileURL))
        self.baseURL = baseURL
        self.fileURL = fileURL
    }

    var body: some View {
        ZStack(alignment: .top) {
            WebView(baseURL: baseURL, findState: findState, watcher: watcher)
                .frame(minWidth: 500, minHeight: 400)
                .ignoresSafeArea(.container, edges: .top)
                .overlay(alignment: .bottomTrailing) {
                    if showUpdatedPill {
                        Text("Updated")
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
        .onChange(of: watcher.html) { _ in
            withAnimation(.easeOut(duration: 0.2)) {
                showUpdatedPill = true
            }
            pillDismissWork?.cancel()
            let work = DispatchWorkItem {
                withAnimation(.easeIn(duration: 0.4)) {
                    showUpdatedPill = false
                }
            }
            pillDismissWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        }
    }

    /// Configure the NSWindow for a Bear/Messages-style chrome:
    /// - Content extends behind the toolbar via `.fullSizeContentView`.
    /// - No hairline separator between the toolbar and the content.
    /// - Window background uses the *text background* color so the toolbar area
    ///   matches the document (white in light, near-black in dark) instead of the
    ///   default system window gray.
    /// - An empty `NSToolbar` is attached so macOS Tahoe applies the larger
    ///   window corner radius (Apple scales the radius to toolbar height; a
    ///   window without a toolbar gets the smaller, title-bar-only radius).
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
            // `.unifiedCompact` collapses title bar + toolbar into a single row
            // (title sits inline with traffic lights, like Messages). `.unified`
            // is taller and leaves an empty second row when the toolbar has no
            // items, which looks asymmetric.
            window.toolbarStyle = .unifiedCompact
        }
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = NSColor.textBackgroundColor
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
