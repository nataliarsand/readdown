import AppKit
import SwiftUI

/// The parts every small Readdown window (About, the post-update note) is built from,
/// so they share one header, message style and footer.
enum WindowLayout {
    static let width: CGFloat = 380
    static let iconSize: CGFloat = 64
    static let spacing: CGFloat = 16
}

/// One type scale for these windows; `.caption` is 10pt on macOS, too small here.
enum WindowType {
    static let name = Font.system(size: 18, weight: .semibold)
    static let title = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13)
    static let small = Font.system(size: 11)
    static let tile = Font.system(size: 12, weight: .medium)
}

struct VersionBadge: View {
    var version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

    var body: some View {
        Text(version)
            .font(WindowType.small)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(ReaderTheme.hoverFill, in: Capsule())
    }
}

struct WindowHeader: View {
    var version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    var showsWhatsNew = true

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: WindowLayout.iconSize, height: WindowLayout.iconSize)
            HStack(spacing: 6) {
                Text("Readdown")
                    .font(WindowType.name)
                VersionBadge(version: version)
            }
            if showsWhatsNew {
                Link("See what's new \u{2192}", destination: ReleaseHighlights.changelogURL)
                    .font(WindowType.body)
            }
        }
    }
}

struct WindowMessage: View {
    let title: String
    let message: LocalizedStringKey
    var signature: String?

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(WindowType.title)
            Text(message)
                .font(WindowType.body)
                .foregroundStyle(.secondary)
                .tint(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let signature {
                Text(signature)
                    .font(WindowType.small)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct WindowFooter<Trailing: View>: View {
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: 12) {
            Divider()
            HStack {
                Link("readdown.app", destination: URL(string: "https://readdown.app")!)
                Spacer()
                trailing
            }
            .font(WindowType.small)
        }
    }
}

extension View {
    func windowContent() -> some View {
        padding(.horizontal, 28)
            .padding(.top, 36)
            .padding(.bottom, 16)
            .frame(width: WindowLayout.width)
    }
}
