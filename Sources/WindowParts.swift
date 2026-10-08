import AppKit
import SwiftUI

extension URL {
    init(literal: StaticString) {
        guard let url = URL(string: "\(literal)") else { preconditionFailure("Invalid URL: \(literal)") }
        self = url
    }
}

enum AppLink {
    static let site = URL(literal: "https://readdown.app")
    static let help = URL(literal: "https://readdown.app/help")
    static let changelog = URL(literal: "https://readdown.app/changelog")
    static let issues = URL(literal: "https://github.com/nataliarsand/readdown/issues")
    static let review = URL(literal: "https://www.producthunt.com/products/readdown/reviews/new")
}

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
            Link("See what's new \u{2192}", destination: AppLink.changelog)
                .font(WindowType.body)
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
                Link("readdown.app", destination: AppLink.site)
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
