import AppKit
import Foundation
import SwiftUI

enum ReaderFontRole: String, CaseIterable, Identifiable {
    case ui
    case body
    case code

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ui: return "UI Font"
        case .body: return "Body Font"
        case .code: return "Code Font"
        }
    }

    var previewText: String {
        switch self {
        case .ui: return "Reader controls and navigation"
        case .body: return "The quick brown fox jumps over the lazy dog."
        case .code: return "let theme = \"custom\""
        }
    }

    var settingsDescription: String {
        switch self {
        case .ui: return "Controls and navigation."
        case .body: return "Markdown prose and headings."
        case .code: return "Code blocks and inline code."
        }
    }

    var sizeRange: ClosedRange<Double> {
        switch self {
        case .ui: return 10...20
        case .body: return 12...28
        case .code: return 10...24
        }
    }
}

enum ReaderFontWeight: Int, CaseIterable, Codable, Identifiable {
    case light = 300
    case regular = 400
    case medium = 500
    case semibold = 600
    case bold = 700

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .regular: return "Regular"
        case .medium: return "Medium"
        case .semibold: return "Semibold"
        case .bold: return "Bold"
        }
    }

    var swiftUIWeight: Font.Weight {
        switch self {
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

struct ReaderFontSelection: Codable, Equatable {
    static let systemFamily = "__system__"
    static let monospacedFamily = "__monospaced__"

    var family: String
    var weight: ReaderFontWeight
    var size: Double

    static let defaultUI = ReaderFontSelection(family: systemFamily, weight: .medium, size: 13)
    static let defaultBody = ReaderFontSelection(family: systemFamily, weight: .regular, size: 16)
    static let defaultCode = ReaderFontSelection(family: monospacedFamily, weight: .regular, size: 14)

    var displayFamilyName: String {
        switch family {
        case Self.systemFamily: return "System"
        case Self.monospacedFamily: return "System Monospaced"
        default: return family
        }
    }

    var swiftUIFont: Font {
        let size = CGFloat(size)
        switch family {
        case Self.systemFamily:
            return .system(size: size, weight: weight.swiftUIWeight)
        case Self.monospacedFamily:
            return .system(size: size, weight: weight.swiftUIWeight, design: .monospaced)
        default:
            return .custom(family, size: size).weight(weight.swiftUIWeight)
        }
    }

    var cssFamily: String {
        switch family {
        case Self.systemFamily:
            return "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"Segoe UI\", \"Noto Sans\", Helvetica, Arial, sans-serif"
        case Self.monospacedFamily:
            return "ui-monospace, SFMono-Regular, \"SF Mono\", Menlo, Consolas, monospace"
        default:
            let escaped = family
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            return "\"\(escaped)\", -apple-system, BlinkMacSystemFont, sans-serif"
        }
    }

    func clamped(for role: ReaderFontRole) -> ReaderFontSelection {
        var copy = self
        copy.size = min(max(size, role.sizeRange.lowerBound), role.sizeRange.upperBound)
        return copy
    }
}

struct ReaderTypography: Equatable {
    var ui: ReaderFontSelection
    var body: ReaderFontSelection
    var code: ReaderFontSelection

    static let `default` = ReaderTypography(
        ui: .defaultUI,
        body: .defaultBody,
        code: .defaultCode
    )

    var cssVariables: String {
        """
        --ui-font-family: \(ui.cssFamily);
        --ui-font-size: \(format(ui.size))px;
        --ui-font-weight: \(ui.weight.rawValue);
        --body-font-family: \(body.cssFamily);
        --body-font-size: \(format(body.size))px;
        --body-font-weight: \(body.weight.rawValue);
        --code-font-family: \(code.cssFamily);
        --code-font-size: \(format(code.size))px;
        --code-font-weight: \(code.weight.rawValue);
        """
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

extension Notification.Name {
    static let readerTypographyDidChange = Notification.Name("readerTypographyDidChange")
}

final class TypographyPreferences: ObservableObject {
    static let shared = TypographyPreferences()

    static let uiKey = "readerUIFont"
    static let bodyKey = "readerBodyFont"
    static let codeKey = "readerCodeFont"

    @Published private(set) var ui: ReaderFontSelection
    @Published private(set) var body: ReaderFontSelection
    @Published private(set) var code: ReaderFontSelection

    private let store: UserDefaults
    private let postsNotifications: Bool

    init(store: UserDefaults = .standard, postsNotifications: Bool = true) {
        self.store = store
        self.postsNotifications = postsNotifications
        ui = Self.decode(Self.uiKey, from: store) ?? .defaultUI
        body = Self.decode(Self.bodyKey, from: store) ?? .defaultBody
        code = Self.decode(Self.codeKey, from: store) ?? .defaultCode
    }

    var typography: ReaderTypography { ReaderTypography(ui: ui, body: body, code: code) }

    static var installedFontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func availableFamilies(for role: ReaderFontRole) -> [String] {
        var values = [ReaderFontSelection.systemFamily, ReaderFontSelection.monospacedFamily]
        values.append(contentsOf: Self.installedFontFamilies)
        let current = selection(for: role).family
        if !values.contains(current) { values.append(current) }
        return values
    }

    func selection(for role: ReaderFontRole) -> ReaderFontSelection {
        switch role {
        case .ui: return ui
        case .body: return body
        case .code: return code
        }
    }

    func update(_ selection: ReaderFontSelection, for role: ReaderFontRole) {
        let selection = selection.clamped(for: role)
        guard selection != self.selection(for: role) else { return }
        switch role {
        case .ui: ui = selection
        case .body: body = selection
        case .code: code = selection
        }
        let key: String
        switch role {
        case .ui: key = Self.uiKey
        case .body: key = Self.bodyKey
        case .code: key = Self.codeKey
        }
        if let data = try? JSONEncoder().encode(selection) { store.set(data, forKey: key) }
        if postsNotifications {
            NotificationCenter.default.post(name: .readerTypographyDidChange, object: self)
        }
    }

    private static func decode(_ key: String, from store: UserDefaults) -> ReaderFontSelection? {
        guard let data = store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ReaderFontSelection.self, from: data)
    }
}

struct TypographySettingsView: View {
    @ObservedObject var preferences: TypographyPreferences

    init(preferences: TypographyPreferences = .shared) {
        self.preferences = preferences
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ReaderSettingsLayout.sectionSpacing) {
            ReaderSettingsSection(
                "Text Styles",
                detail: "Changes apply immediately to open documents."
            ) {
                ForEach(ReaderFontRole.allCases) { role in
                    FontRoleSettingsRow(role: role, preferences: preferences)

                    if role != .code {
                        ReaderSettingsSeparator()
                    }
                }
            }
        }
        .padding(ReaderSettingsLayout.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct FontRoleSettingsRow: View {
    let role: ReaderFontRole
    @ObservedObject var preferences: TypographyPreferences

    private var selection: ReaderFontSelection { preferences.selection(for: role) }

    var body: some View {
        ReaderSettingsRow(
            title: role.displayName,
            detail: role.settingsDescription,
            minimumHeight: 92
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    FontFamilyComboBox(
                        selection: familyBinding,
                        options: preferences.availableFamilies(for: role)
                    )
                    .frame(width: 154)

                    Picker("Weight", selection: weightBinding) {
                        ForEach(ReaderFontWeight.allCases) { weight in
                            Text(weight.displayName).tag(weight)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                    .accessibilityLabel("\(role.displayName) weight")

                    Stepper(value: sizeBinding, in: role.sizeRange, step: 1) {
                        Text("\(Int(selection.size.rounded())) pt")
                            .monospacedDigit()
                            .frame(width: 38, alignment: .trailing)
                    }
                    .frame(width: 70)
                    .accessibilityLabel("\(role.displayName) size")
                }

                Text(role.previewText)
                    .font(selection.swiftUIFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
            }
            .frame(width: ReaderSettingsLayout.controlWidth, alignment: .trailing)
        }
    }

    private var familyBinding: Binding<String> {
        Binding(
            get: { selection.family },
            set: { family in
                var next = selection
                next.family = family
                preferences.update(next, for: role)
            }
        )
    }

    private var weightBinding: Binding<ReaderFontWeight> {
        Binding(
            get: { selection.weight },
            set: { weight in
                var next = selection
                next.weight = weight
                preferences.update(next, for: role)
            }
        )
    }

    private var sizeBinding: Binding<Double> {
        Binding(
            get: { selection.size },
            set: { size in
                var next = selection
                next.size = size
                preferences.update(next, for: role)
            }
        )
    }

}

private struct FontFamilyComboBox: NSViewRepresentable {
    @Binding var selection: String
    let options: [String]

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.delegate = context.coordinator
        comboBox.completes = true
        comboBox.numberOfVisibleItems = 12
        comboBox.usesDataSource = false
        comboBox.addItems(withObjectValues: labels)
        comboBox.stringValue = displayName(for: selection)
        comboBox.setAccessibilityLabel("Font family")
        return comboBox
    }

    func updateNSView(_ comboBox: NSComboBox, context: Context) {
        context.coordinator.parent = self
        if comboBox.objectValues as? [String] != labels {
            comboBox.removeAllItems()
            comboBox.addItems(withObjectValues: labels)
        }
        if comboBox.currentEditor() == nil {
            comboBox.stringValue = displayName(for: selection)
        }
    }

    private var labels: [String] {
        options.map { displayName(for: $0) }
    }

    private func displayName(for family: String) -> String {
        ReaderFontSelection(family: family, weight: .regular, size: 12).displayFamilyName
    }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: FontFamilyComboBox

        init(parent: FontFamilyComboBox) {
            self.parent = parent
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            commit(comboBox)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            commit(comboBox)
        }

        private func commit(_ comboBox: NSComboBox) {
            let index = comboBox.indexOfSelectedItem
            if index >= 0, index < parent.options.count {
                parent.selection = parent.options[index]
                return
            }
            let typed = comboBox.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !typed.isEmpty else { return }
            if let matchedIndex = parent.labels.firstIndex(where: {
                $0.compare(typed, options: .caseInsensitive) == .orderedSame
            }) {
                parent.selection = parent.options[matchedIndex]
            } else {
                parent.selection = typed
            }
        }
    }
}
