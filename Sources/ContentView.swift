import SwiftUI

final class FindState: ObservableObject {
    @Published var isVisible = false
    @Published var searchText = ""
    @Published var totalMatches = 0
    @Published var currentMatch = 0  // 1-indexed; 0 means no active match
}

struct ContentView: View {
    let html: String
    let baseURL: URL?
    @StateObject private var findState = FindState()
    @State private var window: NSWindow?

    init(document: MarkdownDocument, baseURL: URL?) {
        let result = MarkdownRenderer.render(document.text)
        self.html = HTMLTemplate.wrap(body: result.html, hasMermaid: result.hasMermaid)
        self.baseURL = baseURL
    }

    var body: some View {
        ZStack(alignment: .top) {
            WebView(html: html, baseURL: baseURL, findState: findState)
                .frame(minWidth: 500, minHeight: 400)
                .background(WindowAccessor { window in
                    self.window = window
                    WindowCascader.shared.cascade(window)
                })

            if findState.isVisible {
                FindBar(state: findState)
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
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.primary.opacity(0.1)), alignment: .bottom)
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
