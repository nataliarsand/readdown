import AppKit
import SwiftUI

final class AfterUpdateWindow: NSObject, NSWindowDelegate {
    static let shared = AfterUpdateWindow()

    private var window: NSWindow?
    private var answered = false

    func show() {
        guard window == nil else { return }
        answered = false
        let content = AfterUpdateView(answer: { [weak self] in self?.answer($0) },
                                      openFile: { [weak self] in self?.openFile() })
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
        window.contentView = NSHostingView(rootView: content)
        window.setContentSize(window.contentView?.fittingSize ?? .zero)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        UsageMetrics.record(.supportAskShown)
    }

    private func answer(_ answer: SupportAsk.Answer) {
        answered = true
        switch answer {
        case .support:
            UsageMetrics.record(.supportAskSupport)
            NSWorkspace.shared.open(SupportAsk.supportURL)
        case .alreadySupported:
            UsageMetrics.record(.supportAskAlready)
        }
        let frame = window?.frame
        window?.close()
        if let frame {
            ThanksPop.show(centeredIn: frame, style: .support)
        }
    }

    private func openFile() {
        guard MarkdownDocument.openChosenFiles() else { return }
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        if !answered {
            UsageMetrics.record(.supportAskLater)
        }
        window?.contentView = nil
        window = nil
    }
}

private struct AfterUpdateView: View {
    let answer: (SupportAsk.Answer) -> Void
    let openFile: () -> Void

    var body: some View {
        VStack(spacing: WindowLayout.spacing) {
            WindowHeader()

            Divider()

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

                Button(action: openFile) {
                    Text("Open a File")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
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
}
