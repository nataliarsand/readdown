import SwiftUI

struct WelcomeView: View {
    var onSetDefault: () -> Void
    var onDismiss: () -> Void

    @State private var didSetDefault = false

    var body: some View {
        VStack(spacing: 20) {
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)
            }
            Text("Welcome to Readdown")
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Default Markdown Reader")
                        .fontWeight(.medium)
                        .font(.callout)
                    Text("Open all .md files with Readdown.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if didSetDefault {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Button("Set as Default") {
                        onSetDefault()
                        withAnimation { didSetDefault = true }
                    }
                    .controlSize(.small)
                }
            }
            .padding(16)
            .background(.quaternary.opacity(0.5))
            .cornerRadius(8)
            .padding(.horizontal, 24)

            Button(action: onDismiss) {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 24)
        .frame(width: 360)
    }
}
