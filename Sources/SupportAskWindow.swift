import AppKit
import SwiftUI

/// Shown on this release's update screen; empty hides the list.
enum ReleaseHighlights {
    static let items: [String] = []
    static let changelogURL = URL(string: "https://readdown.app/changelog")!
}

final class SupportAskWindow: NSObject, NSWindowDelegate {
    static let shared = SupportAskWindow()
    static let width: CGFloat = 380

    private var window: NSWindow?
    private var answered = false

    func show() {
        guard window == nil else { return }
        answered = false
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 0),
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
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            HStack(spacing: 6) {
                Text("Readdown")
                    .font(.headline)
                VersionBadge()
            }

            whatsNew

            VStack(spacing: 4) {
                Text("Thanks for reading with Readdown.")
                    .font(.system(size: 14, weight: .semibold))
                Text("It's free and built independently in my spare time. No ads, no account, your docs never leave your Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Natalia")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                Button {
                    answer(.support)
                } label: {
                    Label("Support Readdown", systemImage: "cup.and.saucer")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button("Maybe Later") {
                    answer(.later)
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .keyboardShortcut(.cancelAction)
            }

            Divider()

            HStack {
                Spacer()
                Button("I already chipped in") {
                    answer(.alreadySupported)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 18)
        .frame(width: SupportAskWindow.width)
    }

    @ViewBuilder private var whatsNew: some View {
        if ReleaseHighlights.items.isEmpty {
            Link("See what's new \u{2192}", destination: ReleaseHighlights.changelogURL)
                .font(.subheadline)
        } else {
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
