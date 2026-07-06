import AppKit
import SwiftUI

/// A brief "Thank you!" pill that springs in centered, then fades out.
enum ThanksPop {

    static func show(centeredIn rect: NSRect) {
        let size = NSSize(width: 260, height: 100)
        let origin = NSPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        )

        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.contentView = NSHostingView(rootView: ThanksPopView())
        window.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.35
                window.animator().alphaValue = 0
            }, completionHandler: {
                window.orderOut(nil)
            })
        }
    }
}

private struct ThanksPopView: View {
    @State private var shown = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "party.popper.fill")
                .foregroundStyle(.orange)
            Text("Thank you!")
                .fontWeight(.semibold)
        }
        .font(.system(size: 15))
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .floatingSurface(Capsule(), fill: ReaderTheme.pill)
        .scaleEffect(shown ? 1 : 0.5)
        .opacity(shown ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                shown = true
            }
        }
    }
}
