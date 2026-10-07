import AppKit
import SwiftUI

/// What this release adds, in one line; written per release.
enum ReleaseHighlights {
    static let summary = "Version 1.19 adds a table of contents and Back. See what's new for the details."
}

/// The first launch after an update: the support ask when its rules allow, otherwise a plain note.
final class AfterUpdateWindow: NSObject, NSWindowDelegate {
    static let shared = AfterUpdateWindow()

    private var window: NSWindow?
    private var asksForSupport = false
    private var answered = false

    func show(asksForSupport: Bool) {
        guard window == nil else { return }
        self.asksForSupport = asksForSupport
        answered = false
        let content: AnyView = asksForSupport
            ? AnyView(SupportAskView(answer: { [weak self] in self?.answer($0) }))
            : AnyView(UpToDateView(openFile: { [weak self] in self?.openFile() }))
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
        if asksForSupport {
            UsageMetrics.record(.supportAskShown)
        }
    }

    /// A document opening takes over from the plain note; the support ask stays until answered.
    func dismissNote() {
        guard !asksForSupport else { return }
        window?.close()
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

    private func openFile() {
        guard let url = MarkdownDocument.chooseFile() else { return }
        window?.close()
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    func windowWillClose(_ notification: Notification) {
        if asksForSupport && !answered {
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
}

private struct UpToDateView: View {
    let openFile: () -> Void

    var body: some View {
        VStack(spacing: WindowLayout.spacing) {
            WindowHeader()

            Divider()

            WindowMessage(title: "Readdown is up to date", message: LocalizedStringKey(ReleaseHighlights.summary))

            Button(action: openFile) {
                Text("Open a File")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            WindowFooter {
                Link("Report a Bug", destination: AppLink.issues)
            }
        }
        .windowContent()
    }
}
