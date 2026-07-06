import SwiftUI

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

/// Colors and metrics for the reader chrome. Values track `HTMLTemplate.swift`.
enum ReaderTheme {
    /// Matches the page `--bg`, so chrome reads as one surface with the document.
    static let pageBackground = dynamic(light: (0xFC, 0xFC, 0xFB), dark: (0x0D, 0x11, 0x17))
    static let pill = Color(nsColor: dynamic(light: (0xFF, 0xFF, 0xFF), dark: (0x16, 0x1B, 0x22)))
    /// Matches the code-block copy button's confirmed state.
    static let copyConfirm = Color(nsColor: dynamic(light: (0x1A, 0x7F, 0x37), dark: (0x3F, 0xB9, 0x50)))
    static let hairline = Color.primary.opacity(0.08)

    static let headerTopPadding: CGFloat = 6
    static let headerPillHeight: CGFloat = 34
    static var headerCenterFromTop: CGFloat { headerTopPadding + headerPillHeight / 2 }
    static var headerStripHeight: CGFloat { headerTopPadding * 2 + headerPillHeight }
    /// Clears the traffic lights.
    static let headerLeadingClearance: CGFloat = 76
    static let headerEdgePadding: CGFloat = 12

    private static func dynamic(light: (Int, Int, Int), dark: (Int, Int, Int)) -> NSColor {
        NSColor(name: nil) { appearance in
            let rgb = appearance.isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat(rgb.0) / 255,
                green: CGFloat(rgb.1) / 255,
                blue: CGFloat(rgb.2) / 255,
                alpha: 1
            )
        }
    }
}

extension View {
    /// Filled shape with a hairline border and soft shadow, for the pills and find bar.
    func floatingSurface(_ shape: some InsettableShape, fill: some ShapeStyle) -> some View {
        background(fill, in: shape)
            .overlay(shape.strokeBorder(ReaderTheme.hairline))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
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
        let isDark = NSApp.effectiveAppearance.isDark
        _watcher = StateObject(wrappedValue: DocumentWatcher(initialText: document.text, fileURL: fileURL, isDark: isDark))
        self.baseURL = baseURL
        self.fileURL = fileURL
    }

    var body: some View {
        ZStack(alignment: .top) {
            // The pills float in the title-bar row; the container extends behind it.
            ZStack(alignment: .top) {
                WebView(baseURL: baseURL, findState: findState, watcher: watcher)
                    .frame(minWidth: 500, minHeight: 400)
                // Over the web view, under the pills: restores header dragging,
                // which the web view would otherwise swallow.
                WindowDragArea()
                    .frame(height: ReaderTheme.headerStripHeight)
                    .frame(maxWidth: .infinity, alignment: .top)
                HStack(spacing: 0) {
                    titlePill
                    Spacer(minLength: ReaderTheme.headerEdgePadding)
                    actionPill
                }
                .padding(.top, ReaderTheme.headerTopPadding)
                .padding(.leading, ReaderTheme.headerLeadingClearance)
                .padding(.trailing, ReaderTheme.headerEdgePadding)
            }
                .ignoresSafeArea(.container, edges: .top)
                .overlay(alignment: .bottomTrailing) {
                    if let pillText {
                        StatusPill(text: pillText)
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
            // Only the key window responds. `isKeyWindow` is more reliable than
            // comparing against `NSApp.keyWindow` when SwiftUI re-wraps windows.
            guard window?.isKeyWindow == true else { return }
            showFindBar()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showInFinder)) { _ in
            guard window?.isKeyWindow == true else { return }
            revealInFinder()
        }
        .onChange(of: watcher.html) { _ in
            if watcher.lastChangeSource == .disk {
                showPill("Updated")
            }
        }
    }

    /// The file name, replacing the hidden system title. Non-interactive so
    /// clicks fall through to the drag strip.
    private var titlePill: some View {
        Text(fileURL?.lastPathComponent ?? "Untitled")
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 14)
            .frame(height: ReaderTheme.headerPillHeight)
            .floatingSurface(Capsule(), fill: ReaderTheme.pill)
            .allowsHitTesting(false)
    }

    /// Custom rather than `.toolbar`, which brings a system capsule, an opaque
    /// header band, and non-working tooltips.
    private var actionPill: some View {
        HStack(spacing: 2) {
            CopyButton(text: { watcher.text }) {
                UsageMetrics.record(.copyFile)
                showPill("Full contents copied to clipboard")
            }
            PillIconButton(icon: "magnifyingglass", label: "Find in Document",
                           action: showFindBar)
            PillIconButton(icon: "folder", label: "Show in Finder",
                           disabled: fileURL == nil, action: revealInFinder)
        }
        .padding(4)
        .floatingSurface(Capsule(), fill: ReaderTheme.pill)
    }

    /// Shared by the pill, the File menu, and ⇧⌘R.
    private func revealInFinder() {
        guard let fileURL else { return }
        UsageMetrics.record(.showInFinder)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private func showFindBar() {
        UsageMetrics.record(.findInDocument)
        withAnimation(.easeOut(duration: 0.15)) {
            findState.isVisible = true
        }
    }

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

    /// Transparent, full-height header with the pills floating over the content.
    /// No `NSToolbar`: on Tahoe even an empty one draws an opaque header backdrop
    /// that would cover the pills. Hiding the title drops the Document Title Menu;
    /// Show in Finder and the File menu cover those actions.
    private func configureWindowChrome(_ window: NSWindow) {
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        window.toolbar = nil
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.titleVisibility = .hidden
        window.backgroundColor = ReaderTheme.pageBackground
        TrafficLightAligner.attach(to: window, centerFromTop: ReaderTheme.headerCenterFromTop)
    }
}

/// Centers the traffic lights on the pill row. Re-applied on titlebar layout
/// (resize, key-state changes), which resets the button positions.
final class TrafficLightAligner {
    private static var associatedKey: UInt8 = 0

    static func attach(to window: NSWindow, centerFromTop: CGFloat) {
        guard objc_getAssociatedObject(window, &associatedKey) == nil else { return }
        let aligner = TrafficLightAligner(window: window, centerFromTop: centerFromTop)
        objc_setAssociatedObject(window, &associatedKey, aligner, .OBJC_ASSOCIATION_RETAIN)
    }

    private weak var window: NSWindow?
    private let centerFromTop: CGFloat
    private var observers: [Any] = []

    private init(window: NSWindow, centerFromTop: CGFloat) {
        self.window = window
        self.centerFromTop = centerFromTop
        realign()
        let events: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
        ]
        for name in events {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] _ in
                self?.realign()
            })
        }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func realign() {
        applyOffset()
        // Again after AppKit's own layout pass settles.
        DispatchQueue.main.async { [weak self] in
            self?.applyOffset()
        }
    }

    private func applyOffset() {
        guard let window else { return }
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for type in buttons {
            guard let button = window.standardWindowButton(type),
                  let superview = button.superview else { continue }
            let frameInWindow = superview.convert(button.frame, to: nil)
            let desiredCenterY = window.frame.height - centerFromTop
            let delta = desiredCenterY - frameInWindow.midY
            guard abs(delta) > 0.5 else { continue }
            var origin = button.frame.origin
            origin.y += superview.isFlipped ? -delta : delta
            button.setFrameOrigin(origin)
        }
    }
}

/// A transparent strip that drags the window on mouse-down, restoring the
/// title-bar drag the WKWebView underneath would otherwise swallow.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}

/// Transient feedback pill ("Updated", "Full contents copied to clipboard").
private struct StatusPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
    }
}

/// Icon button with a hover highlight and an explicit accessibility label.
private struct PillIconButton: View {
    private static let hitArea = CGSize(width: 30, height: 26)
    private static let hoverShape = RoundedRectangle(cornerRadius: 8, style: .continuous)
    private static let hoverOpacity = 0.07

    let icon: String
    let label: String
    var tint: Color?
    var disabled = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(disabled ? AnyShapeStyle(.tertiary)
                                          : tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                .frame(width: Self.hitArea.width, height: Self.hitArea.height)
                .background(
                    Self.hoverShape
                        .fill(Color.primary.opacity(hovered && !disabled ? Self.hoverOpacity : 0))
                )
                .contentShape(Self.hoverShape)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovered = $0 }
        .accessibilityLabel(label)
    }
}

/// Copy button that swaps to a checkmark after copying, matching the code-block one.
private struct CopyButton: View {
    private static let confirmationSeconds: TimeInterval = 1.6

    let text: () -> String
    var onCopied: () -> Void = {}
    @State private var confirmed = false
    @State private var resetWork: DispatchWorkItem?

    var body: some View {
        PillIconButton(
            icon: confirmed ? "checkmark" : "square.on.square",
            label: confirmed ? "Copied" : "Copy to Clipboard",
            tint: confirmed ? ReaderTheme.copyConfirm : nil
        ) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text(), forType: .string)
            confirmed = true
            resetWork?.cancel()
            let work = DispatchWorkItem { confirmed = false }
            resetWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.confirmationSeconds, execute: work)
            onCopied()
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
        .padding(.vertical, 6)
        .floatingSurface(RoundedRectangle(cornerRadius: 10, style: .continuous), fill: .regularMaterial)
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
