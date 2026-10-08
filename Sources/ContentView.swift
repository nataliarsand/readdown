import SwiftUI

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

/// Applied app-wide: `DocumentWatcher` observes `effectiveAppearance` and restamps the page.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    static let key = "appearanceMode"
    static var current: AppearanceMode {
        AppearanceMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum ReaderTheme {
    /// Matches the page `--bg`.
    static let pageBackground = dynamic(light: (0xFC, 0xFC, 0xFB), dark: (0x0D, 0x11, 0x17))
    static let pill = Color(nsColor: dynamic(light: (0xFF, 0xFF, 0xFF), dark: (0x16, 0x1B, 0x22)))
    /// Matches the page `--link`.
    static let link = Color(nsColor: dynamic(light: (0x09, 0x69, 0xDA), dark: (0x58, 0xA6, 0xFF)))
    /// Matches the page `--success`.
    static let success = Color(nsColor: dynamic(light: (0x1F, 0x96, 0x2C), dark: (0x2E, 0xBE, 0x3D)))
    static var successFill: Color { success.opacity(0.1) }
    static var successBorder: Color { success.opacity(0.25) }
    static let hairline = Color.primary.opacity(0.08)
    static let hoverFill = Color.primary.opacity(0.07)
    static let tileFill = Color.primary.opacity(0.08)
    static let tileHoverFill = Color.primary.opacity(0.13)

    static let controlRadius: CGFloat = 8
    static let panelRadius: CGFloat = 12
    static var panelShape: RoundedRectangle { RoundedRectangle(cornerRadius: panelRadius, style: .continuous) }

    static let appear = Animation.easeOut(duration: 0.15)
    static let disappear = Animation.easeIn(duration: 0.2)

    static let headerTopPadding: CGFloat = 6
    static let headerPillHeight: CGFloat = 34
    static var headerCenterFromTop: CGFloat { headerTopPadding + headerPillHeight / 2 }
    static var headerStripHeight: CGFloat { headerTopPadding * 2 + headerPillHeight }
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
    func floatingSurface(_ shape: some InsettableShape, fill: some ShapeStyle,
                         border: Color = ReaderTheme.hairline) -> some View {
        background(fill, in: shape)
            .overlay(shape.strokeBorder(border))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }
}

final class FindState: ObservableObject {
    @Published var isVisible = false
    @Published var searchText = ""
    @Published var totalMatches = 0
    @Published var currentMatch = 0  // 1-indexed; 0 means no active match
    @Published var focusRequest = 0
}

final class TableOfContentsState: ObservableObject {
    @Published var isAvailable = false
    @Published var isVisible = false

    var menuTitle: String { isVisible ? "Hide Table of Contents" : "Show Table of Contents" }
}

final class HistoryState: ObservableObject {
    @Published var canGoBack = false
    @Published var canGoForward = false
}

struct ContentView: View {
    @StateObject private var watcher: DocumentWatcher
    let baseURL: URL?
    let fileURL: URL?
    @StateObject private var findState = FindState()
    @StateObject private var tableOfContentsState = TableOfContentsState()
    @StateObject private var historyState = HistoryState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var window: NSWindow?
    @State private var toast: Toast?
    @State private var toastDismissWork: DispatchWorkItem?
    @StateObject private var tips = HeaderTipState()

    init(document: MarkdownDocument, baseURL: URL?, fileURL: URL? = nil) {
        // Appearance source of truth is `NSAppearance`; WebKit's media query is unreliable here.
        let isDark = NSApp.effectiveAppearance.isDark
        _watcher = StateObject(wrappedValue: DocumentWatcher(initialText: document.text, fileURL: fileURL, isDark: isDark))
        self.baseURL = baseURL
        self.fileURL = fileURL
    }

    var body: some View {
        ZStack(alignment: .top) {
            // The pills float in the title-bar row; the container extends behind it.
            ZStack(alignment: .top) {
                WebView(baseURL: baseURL, findState: findState,
                        tableOfContentsState: tableOfContentsState, historyState: historyState, watcher: watcher)
                    .frame(minWidth: 500, minHeight: 400)
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
                if findState.isVisible {
                    GeometryReader { proxy in
                        FindBar(state: findState)
                            .padding(.trailing, findBarTrailingInset(width: proxy.size.width))
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, ReaderTheme.headerStripHeight + 4)
                    .transition(dropIn)
                }
                if let toast {
                    ToastView(toast: toast)
                        .padding(.top, ReaderTheme.headerTopPadding)
                        .transition(dropIn)
                }
            }
                .ignoresSafeArea(.container, edges: .top)
                .focusedSceneObject(tableOfContentsState)
                .focusedSceneObject(historyState)
                .background(WindowAccessor { window in
                    self.window = window
                    WindowCascader.shared.cascade(window)
                    configureWindowChrome(window)
                })
        }
        .onReceive(NotificationCenter.default.publisher(for: .findInDocument)) { _ in
            // `isKeyWindow`, not `NSApp.keyWindow`: SwiftUI re-wraps windows.
            guard window?.isKeyWindow == true else { return }
            showFindBar()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showInFinder)) { _ in
            guard window?.isKeyWindow == true else { return }
            revealInFinder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .copyFilePath)) { _ in
            guard window?.isKeyWindow == true else { return }
            copyFilePath()
        }
        .onReceive(NotificationCenter.default.publisher(for: .linkNotice)) { notification in
            guard notification.object as? NSWindow == window,
                  let text = notification.userInfo?["text"] as? String else { return }
            showToast(Toast(text: text, kind: .info))
        }
        .onChange(of: watcher.html) { _ in
            if watcher.lastChangeSource == .disk {
                showToast(Toast(text: "File updated with latest changes", kind: .info))
            }
        }
    }

    /// Non-interactive so clicks reach the drag strip.
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

    /// Not `.toolbar`: it brings a system capsule, an opaque header band, and broken tooltips.
    private var actionPill: some View {
        HStack(spacing: 2) {
            CopyButton(text: { watcher.text },
                       html: { ClipboardExport.htmlFragment(fromRenderedBody: watcher.bodyHTML) }) {
                UsageMetrics.record(.copyFile)
                showToast(Toast(text: "Full contents copied to clipboard", kind: .success))
            }
            PillIconButton(icon: "magnifyingglass", label: "Find in Document",
                           shortcut: AppShortcut.find, action: showFindBar)
            PillIconButton(
                icon: "list.bullet.indent",
                label: tableOfContentsState.isAvailable
                    ? tableOfContentsState.menuTitle : "No headings to list",
                shortcut: tableOfContentsState.isAvailable ? AppShortcut.tableOfContents : nil,
                tint: tableOfContentsState.isVisible ? ReaderTheme.link : nil,
                disabled: !tableOfContentsState.isAvailable
            ) {
                NotificationCenter.default.post(name: .toggleTableOfContents, object: nil)
            }
            PillMenu(icon: "folder", label: "File Location", disabled: fileURL == nil) {
                Button("Show in Finder", action: revealInFinder)
                Button("Copy Path", action: copyFilePath)
            }
        }
        .padding(4)
        .floatingSurface(Capsule(), fill: ReaderTheme.pill)
        .environmentObject(tips)
        .overlayPreferenceValue(HeaderTipAnchor.self) { anchor in
            GeometryReader { proxy in
                if let anchor, let tip = tips.shown {
                    HeaderTipLayout(button: proxy[anchor]) {
                        HeaderTipBubble(tip: tip)
                    }
                    .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var dropIn: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

    private func findBarTrailingInset(width: CGFloat) -> CGFloat {
        guard tableOfContentsState.isVisible, width >= 720 else { return 0 }
        return 260 + ReaderTheme.headerEdgePadding
    }

    private func revealInFinder() {
        guard let fileURL else { return }
        UsageMetrics.record(.showInFinder)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private func copyFilePath() {
        guard let fileURL else { return }
        UsageMetrics.record(.copyPath)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(fileURL.path, forType: .string)
        showToast(Toast(text: "Path copied to clipboard", kind: .success))
    }

    private func showFindBar() {
        UsageMetrics.record(.findInDocument)
        withAnimation(ReaderTheme.appear) {
            findState.isVisible = true
        }
        findState.focusRequest += 1
    }

    private func showToast(_ new: Toast) {
        withAnimation(ReaderTheme.appear) {
            toast = new
        }
        toastDismissWork?.cancel()
        let work = DispatchWorkItem { dismissToast() }
        toastDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + CheckIcon.confirmSeconds, execute: work)
    }

    private func dismissToast() {
        toastDismissWork?.cancel()
        withAnimation(ReaderTheme.disappear) {
            toast = nil
        }
    }

    /// No `NSToolbar`: on Tahoe even an empty one paints an opaque header over the pills.
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

/// AppKit resets the button positions on every titlebar layout, hence the re-apply.
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

/// Restores the title-bar drag the WKWebView underneath would swallow.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}

extension CheckIcon {
    struct Shape: SwiftUI.Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.width / CheckIcon.grid
            var path = Path()
            path.addLines(CheckIcon.points.map { CGPoint(x: rect.minX + $0.x * s, y: rect.minY + $0.y * s) })
            return path
        }
    }

    struct View: SwiftUI.View {
        let size: CGFloat
        var body: some SwiftUI.View {
            Shape()
                .stroke(style: StrokeStyle(lineWidth: strokeWidth * size / grid, lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
        }
    }
}

extension CopyIcon {
    struct Shape: SwiftUI.Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.width / CopyIcon.grid
            func p(_ point: CGPoint) -> CGPoint { CGPoint(x: rect.minX + point.x * s, y: rect.minY + point.y * s) }
            var path = Path()
            let f = CopyIcon.front
            path.addRoundedRect(in: CGRect(origin: p(f.origin), size: CGSize(width: f.width * s, height: f.height * s)),
                                cornerSize: CGSize(width: CopyIcon.radius * s, height: CopyIcon.radius * s))
            let c = CopyIcon.backCorners
            path.move(to: p(c[0]))
            for i in 1...3 {
                path.addArc(tangent1End: p(c[i]), tangent2End: p(c[i + 1]), radius: CopyIcon.radius * s)
            }
            path.addLine(to: p(c[4]))
            return path
        }
    }

    struct View: SwiftUI.View {
        let size: CGFloat
        var body: some SwiftUI.View {
            Shape()
                .stroke(style: StrokeStyle(lineWidth: strokeWidth * size / grid, lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
        }
    }
}

struct Toast: Equatable {
    enum Kind {
        case success, info

        var foreground: Color {
            switch self {
            case .success: ReaderTheme.success
            case .info: .primary
            }
        }

        var fill: Color {
            switch self {
            case .success: ReaderTheme.successFill
            case .info: .clear
            }
        }

        var border: Color {
            switch self {
            case .success: ReaderTheme.successBorder
            case .info: ReaderTheme.hairline
            }
        }
    }

    let text: String
    let kind: Kind
}

private struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 10) {
            if toast.kind == .success {
                CheckIcon.View(size: 14)
            }
            Text(toast.text)
                .font(.system(size: 14, weight: .medium))
        }
        .foregroundStyle(toast.kind.foreground)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 14)
        .frame(height: ReaderTheme.headerPillHeight)
        .background(toast.kind.fill, in: Capsule())
        .floatingSurface(Capsule(), fill: ReaderTheme.pill, border: toast.kind.border)
        .allowsHitTesting(false)
    }
}

private struct PillIcon<Glyph: View>: View {
    private static var hitArea: CGSize { CGSize(width: 30, height: 26) }
    private static var hoverShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ReaderTheme.controlRadius, style: .continuous)
    }

    var tint: Color?
    var disabled = false
    let hovered: Bool
    @ViewBuilder let glyph: () -> Glyph

    var body: some View {
        glyph()
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(disabled ? AnyShapeStyle(.tertiary)
                                      : tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
            .frame(width: Self.hitArea.width, height: Self.hitArea.height)
            .background(
                Self.hoverShape
                    .fill(hovered && !disabled ? ReaderTheme.hoverFill : .clear)
            )
            .contentShape(Self.hoverShape)
    }
}

private struct PillIconButton<Glyph: View>: View {
    let label: String
    var shortcut: KeyboardShortcut?
    var tint: Color?
    var disabled = false
    let action: () -> Void
    @ViewBuilder let glyph: () -> Glyph
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            PillIcon(tint: tint, disabled: disabled, hovered: hovered, glyph: glyph)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovered = $0 }
        .headerTip(HeaderTip(label: label, shortcut: shortcut))
        .accessibilityLabel(label)
    }
}

extension PillIconButton where Glyph == Image {
    init(icon: String, label: String, shortcut: KeyboardShortcut? = nil, tint: Color? = nil,
         disabled: Bool = false, action: @escaping () -> Void) {
        self.init(label: label, shortcut: shortcut, tint: tint, disabled: disabled, action: action) {
            Image(systemName: icon)
        }
    }
}

private struct PillMenu<Items: View>: View {
    let icon: String
    let label: String
    var disabled = false
    @ViewBuilder let items: () -> Items
    @State private var hovered = false

    var body: some View {
        Menu(content: items) {
            PillIcon(disabled: disabled, hovered: hovered) { Image(systemName: icon) }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(disabled)
        .onHover { hovered = $0 }
        .headerTip(HeaderTip(label: label))
        .accessibilityLabel(label)
    }
}

private struct CopyButton: View {
    let text: () -> String
    var html: () -> String? = { nil }
    var onCopied: () -> Void = {}
    @State private var confirmed = false
    @State private var resetWork: DispatchWorkItem?

    var body: some View {
        PillIconButton(
            label: confirmed ? "Copied" : "Copy to Clipboard",
            tint: confirmed ? ReaderTheme.success : nil,
            action: copy
        ) {
            if confirmed {
                CheckIcon.View(size: 14)
            } else {
                CopyIcon.View(size: 16)
            }
        }
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text(), forType: .string)
        if let html = html() {
            pasteboard.setString(html, forType: .html)
        }
        confirmed = true
        resetWork?.cancel()
        let work = DispatchWorkItem { confirmed = false }
        resetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + CheckIcon.confirmSeconds, execute: work)
        onCopied()
    }
}

enum AppShortcut {
    static let find = KeyboardShortcut("f", modifiers: .command)
    static let tableOfContents = KeyboardShortcut("t", modifiers: [.command, .option])
    static let back = KeyboardShortcut("[", modifiers: .command)
    static let forward = KeyboardShortcut("]", modifiers: .command)
}

extension KeyboardShortcut {
    var symbols: String {
        let order: [(EventModifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return order.filter { modifiers.contains($0.0) }.map(\.1).joined() + String(key.character).uppercased()
    }
}

struct HeaderTip: Equatable {
    let label: String
    var shortcut: KeyboardShortcut?

    static func == (a: HeaderTip, b: HeaderTip) -> Bool {
        a.label == b.label && a.shortcut?.symbols == b.shortcut?.symbols
    }
}

/// Native `.help` waits about a second and can't show a shortcut.
final class HeaderTipState: ObservableObject {
    private static let delay: TimeInterval = 0.35
    /// Moving to the next button soon after shows its tip at once, as AppKit does.
    private static let warmWindow: TimeInterval = 0.5
    private static let handoff: TimeInterval = 0.06

    @Published private(set) var shown: HeaderTip?
    private var hovered: HeaderTip?
    private var pending: DispatchWorkItem?
    private var lastHidden = Date.distantPast
    private var clickMonitor: Any?

    func hover(_ tip: HeaderTip, _ inside: Bool) {
        if inside {
            pending?.cancel()
            hovered = tip
            if shown != nil || Date().timeIntervalSince(lastHidden) < Self.warmWindow {
                show(tip)
            } else {
                schedule(after: Self.delay) { [weak self] in self?.show(tip) }
            }
        } else if hovered == tip {
            pending?.cancel()
            hovered = nil
            // The next button's enter follows this exit; waiting lets the tip swap without a blink.
            schedule(after: Self.handoff) { [weak self] in self?.hide() }
        }
    }

    private func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) {
        let work = DispatchWorkItem(block: action)
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func show(_ tip: HeaderTip) {
        guard hovered == tip else { return }
        if shown == nil {
            withAnimation(ReaderTheme.appear) { shown = tip }
        } else {
            shown = tip
        }
        // A click opens a menu or changes the button; the tip would sit over it.
        clickMonitor = clickMonitor ?? NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.hovered = nil
            self?.hide()
            return event
        }
    }

    private func hide() {
        pending?.cancel()
        guard hovered == nil else { return }
        if shown != nil { lastHidden = Date() }
        withAnimation(ReaderTheme.disappear) { shown = nil }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    deinit {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    }
}

struct HeaderTipAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

private struct HeaderTipModifier: ViewModifier {
    let tip: HeaderTip
    @EnvironmentObject private var tips: HeaderTipState

    func body(content: Content) -> some View {
        content
            .onHover { tips.hover(tip, $0) }
            .anchorPreference(key: HeaderTipAnchor.self, value: .bounds) { tips.shown == tip ? $0 : nil }
    }
}

extension View {
    func headerTip(_ tip: HeaderTip) -> some View {
        modifier(HeaderTipModifier(tip: tip))
    }
}

/// A layout, not measured state, so a new tip is placed by its own width on its first frame.
private struct HeaderTipLayout: Layout {
    let button: CGRect

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let x = min(button.midX - size.width / 2, bounds.width - size.width)
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.maxY + HeaderTipBubble.gap),
                          proposal: ProposedViewSize(size))
        }
    }
}

struct HeaderTipBubble: View {
    static let gap: CGFloat = 8

    let tip: HeaderTip

    var body: some View {
        HStack(spacing: 8) {
            Text(tip.label)
                .font(.system(size: 13))
            if let shortcut = tip.shortcut {
                Text(shortcut.symbols)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(ReaderTheme.hoverFill, in: Capsule())
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.leading, 12)
        .padding(.trailing, tip.shortcut == nil ? 12 : 6)
        .padding(.vertical, 6)
        .floatingSurface(Capsule(), fill: ReaderTheme.pill)
    }
}

struct FindBar: View {
    @ObservedObject var state: FindState
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Find", text: $state.searchText, prompt: Text("Find").foregroundColor(.secondary))
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { NotificationCenter.default.post(name: .findNext, object: nil) }

            if !state.searchText.isEmpty {
                Text(matchStatus)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            Button(action: { NotificationCenter.default.post(name: .findPrevious, object: nil) }) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(state.searchText.isEmpty)
            .opacity(state.searchText.isEmpty ? 0.4 : 1)
            .accessibilityLabel("Previous Match")

            Button(action: { NotificationCenter.default.post(name: .findNext, object: nil) }) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(state.searchText.isEmpty)
            .opacity(state.searchText.isEmpty ? 0.4 : 1)
            .accessibilityLabel("Next Match")

            Button(action: close) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Close Find")
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(.secondary)
        .floatingSurface(ReaderTheme.panelShape, fill: ReaderTheme.pill)
        .frame(maxWidth: 380)
        .padding(.horizontal, 16)
        .onAppear(perform: focusAndSelectSearchText)
        .onChange(of: state.focusRequest) { _ in
            focusAndSelectSearchText()
        }
    }

    private var matchStatus: String {
        if state.totalMatches == 0 { return "No results" }
        return "\(state.currentMatch) of \(state.totalMatches)"
    }

    private func close() {
        withAnimation(ReaderTheme.disappear) {
            state.isVisible = false
        }
        state.searchText = ""
    }

    private func focusAndSelectSearchText() {
        searchFocused = true
        DispatchQueue.main.async {
            (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectAll(nil)
        }
    }
}
