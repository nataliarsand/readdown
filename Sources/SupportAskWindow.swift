import AppKit
import SwiftUI

/// Shown on this release's update screen; empty hides the list.
enum ReleaseHighlights {
    static let items: [String] = []
    static let changelogURL = URL(string: "https://readdown.app/changelog")!
}

final class SupportAskWindow: NSObject, NSWindowDelegate {
    static let shared = SupportAskWindow()

    private var window: NSWindow?
    private var answered = false

    func show() {
        guard window == nil else { return }
        answered = false
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: WindowLayout.width, height: 0),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        // Closing via the red button would over-release the window and crash the next reopen.
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SupportAskView(answer: { [weak self] in self?.answer($0) }))
        window.setContentSize(window.contentView?.fittingSize ?? .zero)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        UsageMetrics.record(.supportAskShown)
    }

    private func answer(_ answer: SupportAsk.Answer) {
        answered = true
        SupportAsk.record(answer)
        switch answer {
        case .support:
            UsageMetrics.record(.supportAskSupport)
            NSWorkspace.shared.open(SupportAsk.supportURL)
        case .later:
            UsageMetrics.record(.supportAskLater)
        case .alreadySupported:
            UsageMetrics.record(.supportAskAlready)
        }
        let frame = window?.frame
        window?.close()
        if answer != .later, let frame {
            ThanksPop.show(centeredIn: frame, style: .support)
        }
    }

    func windowWillClose(_ notification: Notification) {
        if !answered {
            SupportAsk.record(.later)
            UsageMetrics.record(.supportAskLater)
        }
        window?.contentView = nil
        window = nil
    }
}

private struct SupportAskView: View {
    let answer: (SupportAsk.Answer) -> Void

    var body: some View {
        VStack(spacing: WindowLayout.spacing) {
            WindowHeader(showsWhatsNew: ReleaseHighlights.items.isEmpty)

            Divider()

            highlights

            WindowMessage(
                title: "Thanks for reading with Readdown.",
                message: "It's free and built independently in my spare time. No ads, no account, your docs never leave your Mac.",
                signature: "Natalia"
            )

            VStack(spacing: 8) {
                Button {
                    answer(.support)
                } label: {
                    Label("Support Readdown", systemImage: "heart")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button("Maybe Later") {
                    answer(.later)
                }
                .buttonStyle(.link)
                .font(WindowType.body)
                .keyboardShortcut(.cancelAction)
            }

            WindowFooter {
                Button("I already chipped in") {
                    answer(.alreadySupported)
                }
                .buttonStyle(.link)
            }
        }
        .windowContent()
    }

    @ViewBuilder private var highlights: some View {
        if !ReleaseHighlights.items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEW IN THIS VERSION")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(ReleaseHighlights.items, id: \.self) { item in
                    Text("\u{2022} \(item)")
                        .font(.system(size: 12))
                }
                HStack {
                    Spacer()
                    Link("See all changes \u{2192}", destination: ReleaseHighlights.changelogURL)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: ReaderTheme.pageBackground), in: ReaderTheme.panelShape)
            .overlay(ReaderTheme.panelShape.strokeBorder(ReaderTheme.hairline))
        }
    }
}
