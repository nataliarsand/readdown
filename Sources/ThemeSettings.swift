import AppKit
import Foundation
import SwiftUI

enum ReaderColorScheme: String, CaseIterable {
    case light
    case dark

    var isDark: Bool { self == .dark }
}

enum ReaderAppearanceMode: String, CaseIterable, Identifiable {
    case automatic
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    func resolvedScheme(systemIsDark: Bool) -> ReaderColorScheme {
        switch self {
        case .automatic: return systemIsDark ? .dark : .light
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum ReaderThemeFamily: String, CaseIterable, Identifiable {
    case `default`
    case catppuccin
    case nord
    case one
    case github
    case xcode
    case notion
    case material
    case ayu

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: return "Default"
        case .catppuccin: return "Catppuccin"
        case .nord: return "Nord"
        case .one: return "One"
        case .github: return "GitHub"
        case .xcode: return "Xcode"
        case .notion: return "Notion"
        case .material: return "Material"
        case .ayu: return "Ayu"
        }
    }

    func variantName(for scheme: ReaderColorScheme) -> String {
        switch (self, scheme) {
        case (.default, .light): return "Default Light"
        case (.default, .dark): return "Default Dark"
        case (.catppuccin, .light): return "Catppuccin Latte"
        case (.catppuccin, .dark): return "Catppuccin Mocha"
        case (.nord, .light): return "Nord Snow Storm"
        case (.nord, .dark): return "Nord Polar Night"
        case (.one, .light): return "One Light"
        case (.one, .dark): return "One Dark"
        case (.github, .light): return "GitHub Light"
        case (.github, .dark): return "GitHub Dark"
        case (.xcode, .light): return "Xcode Light"
        case (.xcode, .dark): return "Xcode Dark"
        case (.notion, .light): return "Notion Light"
        case (.notion, .dark): return "Notion Dark"
        case (.material, .light): return "Material Light"
        case (.material, .dark): return "Material Dark"
        case (.ayu, .light): return "Ayu Light"
        case (.ayu, .dark): return "Ayu Mirage"
        }
    }
}

struct ReaderColor: Equatable, Hashable {
    let value: UInt32

    init(_ value: UInt32) {
        self.value = value & 0x00FF_FFFF
    }

    var red: Int { Int((value >> 16) & 0xFF) }
    var green: Int { Int((value >> 8) & 0xFF) }
    var blue: Int { Int(value & 0xFF) }

    var cssHex: String { String(format: "#%06X", value) }

    func cssRGBA(alpha: Double) -> String {
        String(format: "rgba(%d, %d, %d, %.2f)", red, green, blue, alpha)
    }

    var nsColor: NSColor {
        NSColor(
            srgbRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }

    var color: Color { Color(nsColor: nsColor) }

    var relativeLuminance: Double {
        func component(_ value: Int) -> Double {
            let normalized = Double(value) / 255
            return normalized <= 0.04045
                ? normalized / 12.92
                : pow((normalized + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * component(red) + 0.7152 * component(green) + 0.0722 * component(blue)
    }

    func contrastRatio(with other: ReaderColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

struct ReaderThemePalette: Equatable, Identifiable {
    let family: ReaderThemeFamily
    let scheme: ReaderColorScheme
    let background: ReaderColor
    let text: ReaderColor
    let muted: ReaderColor
    let surface: ReaderColor
    let codeBackground: ReaderColor
    let border: ReaderColor
    let link: ReaderColor
    let tableStripe: ReaderColor
    let tableHeader: ReaderColor
    let red: ReaderColor
    let purple: ReaderColor
    let blue: ReaderColor
    let green: ReaderColor
    let orange: ReaderColor
    let yellow: ReaderColor

    var id: String { "\(family.rawValue)-\(scheme.rawValue)" }
    var displayName: String { family.variantName(for: scheme) }

    var cssVariables: String {
        """
        --text: \(text.cssHex);
        --bg: \(background.cssHex);
        --muted: \(muted.cssHex);
        --surface: \(surface.cssHex);
        --code-bg: \(codeBackground.cssHex);
        --border: \(border.cssHex);
        --hairline: \(text.cssRGBA(alpha: 0.08));
        --link: \(link.cssHex);
        --link-underline: \(link.cssRGBA(alpha: 0.36));
        --blockquote-border: \(border.cssHex);
        --table-stripe: \(tableStripe.cssHex);
        --table-header: \(tableHeader.cssHex);
        --scrollbar-thumb: \(text.cssRGBA(alpha: 0.32));
        --success: \(green.cssHex);
        --danger: \(red.cssHex);
        --find-bg: \(yellow.cssRGBA(alpha: scheme.isDark ? 0.30 : 0.42));
        --find-current-bg: \(orange.cssRGBA(alpha: scheme.isDark ? 0.58 : 0.68));
        --syntax-text: \(text.cssHex);
        --syntax-keyword: \(purple.cssHex);
        --syntax-title: \(blue.cssHex);
        --syntax-literal: \(orange.cssHex);
        --syntax-string: \(green.cssHex);
        --syntax-built-in: \(yellow.cssHex);
        --syntax-comment: \(muted.cssHex);
        --syntax-tag: \(red.cssHex);
        --syntax-addition-bg: \(green.cssRGBA(alpha: scheme.isDark ? 0.18 : 0.12));
        --syntax-deletion-bg: \(red.cssRGBA(alpha: scheme.isDark ? 0.20 : 0.12));
        """
    }
}

enum ReaderThemeCatalog {
    static func palette(for family: ReaderThemeFamily, scheme: ReaderColorScheme) -> ReaderThemePalette {
        switch (family, scheme) {
        case (.default, .light):
            return make(.default, .light, 0xFCFCFB, 0x1F2328, 0x57606A, 0xFFFFFF, 0xF6F8FA,
                        0xD0D7DE, 0x0969DA, 0xF6F8FA, 0xEEF1F5,
                        0xCF222E, 0x8250DF, 0x0969DA, 0x1A7F37, 0xBC4C00, 0x9A6700)
        case (.default, .dark):
            return make(.default, .dark, 0x0D1117, 0xE6EDF3, 0x9198A1, 0x161B22, 0x161B22,
                        0x3D444D, 0x58A6FF, 0x161B22, 0x252C35,
                        0xFF7B72, 0xD2A8FF, 0x79C0FF, 0x3FB950, 0xFFA657, 0xE3B341)

        case (.catppuccin, .light):
            return make(.catppuccin, .light, 0xEFF1F5, 0x4C4F69, 0x6C6F85, 0xE6E9EF, 0xE6E9EF,
                        0xBCC0CC, 0x1E66F5, 0xE6E9EF, 0xDCE0E8,
                        0xD20F39, 0x8839EF, 0x1E66F5, 0x40A02B, 0xFE640B, 0xDF8E1D)
        case (.catppuccin, .dark):
            return make(.catppuccin, .dark, 0x1E1E2E, 0xCDD6F4, 0xA6ADC8, 0x313244, 0x181825,
                        0x45475A, 0x89B4FA, 0x181825, 0x313244,
                        0xF38BA8, 0xCBA6F7, 0x89B4FA, 0xA6E3A1, 0xFAB387, 0xF9E2AF)

        case (.nord, .light):
            return make(.nord, .light, 0xECEFF4, 0x2E3440, 0x4C566A, 0xE5E9F0, 0xE5E9F0,
                        0xD8DEE9, 0x5E81AC, 0xE5E9F0, 0xD8DEE9,
                        0xBF616A, 0xB48EAD, 0x5E81AC, 0xA3BE8C, 0xD08770, 0xEBCB8B)
        case (.nord, .dark):
            return make(.nord, .dark, 0x2E3440, 0xECEFF4, 0xD8DEE9, 0x3B4252, 0x3B4252,
                        0x4C566A, 0x88C0D0, 0x3B4252, 0x434C5E,
                        0xBF616A, 0xB48EAD, 0x81A1C1, 0xA3BE8C, 0xD08770, 0xEBCB8B)

        case (.one, .light):
            return make(.one, .light, 0xFAFAFA, 0x383A42, 0x696C77, 0xF0F0F0, 0xF0F0F0,
                        0xD3D3D3, 0x4078F2, 0xF3F3F3, 0xEAEAEB,
                        0xE45649, 0xA626A4, 0x4078F2, 0x50A14F, 0xC18401, 0x986801)
        case (.one, .dark):
            return make(.one, .dark, 0x282C34, 0xABB2BF, 0x7F848E, 0x21252B, 0x21252B,
                        0x3E4451, 0x61AFEF, 0x21252B, 0x2C313A,
                        0xE06C75, 0xC678DD, 0x61AFEF, 0x98C379, 0xD19A66, 0xE5C07B)

        case (.github, .light):
            return make(.github, .light, 0xFFFFFF, 0x1F2328, 0x656D76, 0xF6F8FA, 0xF6F8FA,
                        0xD0D7DE, 0x0969DA, 0xF6F8FA, 0xEAEEF2,
                        0xCF222E, 0x8250DF, 0x0969DA, 0x1A7F37, 0xBC4C00, 0x9A6700)
        case (.github, .dark):
            return make(.github, .dark, 0x0D1117, 0xE6EDF3, 0x8D96A0, 0x161B22, 0x161B22,
                        0x30363D, 0x4493F8, 0x161B22, 0x21262D,
                        0xFF7B72, 0xD2A8FF, 0x79C0FF, 0x7EE787, 0xFFA657, 0xE3B341)

        case (.xcode, .light):
            return make(.xcode, .light, 0xFFFFFF, 0x000000, 0x5D6B78, 0xF5F5F5, 0xF5F5F5,
                        0xE1E1E1, 0x0E0EFF, 0xF7F7F7, 0xE8F2FF,
                        0xC51A16, 0x9B2387, 0x0F68A0, 0x357A3A, 0x816C00, 0x816C00)
        case (.xcode, .dark):
            return make(.xcode, .dark, 0x1F1F24, 0xFFFFFF, 0x92A1B0, 0x303139, 0x303139,
                        0x41424A, 0x5482FB, 0x25262C, 0x303139,
                        0xFC6A5D, 0xFC5FA3, 0x67B7A4, 0x9EF1DD, 0xFD8F3F, 0xD0BF69)

        case (.notion, .light):
            return make(.notion, .light, 0xFFFFFF, 0x37352F, 0x787774, 0xF7F6F3, 0xF7F6F3,
                        0xE9E9E7, 0x337EA9, 0xFBFBFA, 0xF1F1EF,
                        0xEB5757, 0x9065B0, 0x337EA9, 0x448361, 0xD9730D, 0xCB912F)
        case (.notion, .dark):
            return make(.notion, .dark, 0x191919, 0xFFFFFF, 0x9B9A97, 0x252525, 0x252525,
                        0x373737, 0x529CCA, 0x202020, 0x2F2F2F,
                        0xFF7369, 0x9A6DD7, 0x529CCA, 0x4DAB9A, 0xFFA344, 0xFFDC49)

        case (.material, .light):
            return make(.material, .light, 0xFFFBFE, 0x1D1B20, 0x49454F, 0xF3EDF7, 0xF3EDF7,
                        0xCAC4D0, 0x6750A4, 0xF7F2FA, 0xE8DEF8,
                        0xB3261E, 0x7D5260, 0x6750A4, 0x386A20, 0x8C4A60, 0x7D5700)
        case (.material, .dark):
            return make(.material, .dark, 0x1D1B20, 0xE6E1E5, 0xCAC4D0, 0x2B2930, 0x211F26,
                        0x49454F, 0xD0BCFF, 0x211F26, 0x36343B,
                        0xF2B8B5, 0xD0BCFF, 0xA8C7FA, 0xB7F397, 0xFFB1C8, 0xE9C16C)

        case (.ayu, .light):
            return make(.ayu, .light, 0xFAFAFA, 0x5C6166, 0x8A9199, 0xF3F4F5, 0xF3F4F5,
                        0xD9D8D7, 0x399EE6, 0xF5F6F7, 0xE7E8E9,
                        0xE65050, 0xA37ACC, 0x399EE6, 0x6CBF43, 0xFA8D3E, 0xF2AE49)
        case (.ayu, .dark):
            return make(.ayu, .dark, 0x1F2430, 0xCBCCC6, 0x707A8C, 0x242936, 0x191E2A,
                        0x343D46, 0x73D0FF, 0x191E2A, 0x272D3A,
                        0xFF6666, 0xDFBFFF, 0x73D0FF, 0xBAE67E, 0xFFA759, 0xFFD580)
        }
    }

    static var allPalettes: [ReaderThemePalette] {
        ReaderThemeFamily.allCases.flatMap { family in
            ReaderColorScheme.allCases.map { palette(for: family, scheme: $0) }
        }
    }

    private static func make(
        _ family: ReaderThemeFamily, _ scheme: ReaderColorScheme,
        _ background: UInt32, _ text: UInt32, _ muted: UInt32,
        _ surface: UInt32, _ codeBackground: UInt32, _ border: UInt32,
        _ link: UInt32, _ tableStripe: UInt32, _ tableHeader: UInt32,
        _ red: UInt32, _ purple: UInt32, _ blue: UInt32,
        _ green: UInt32, _ orange: UInt32, _ yellow: UInt32
    ) -> ReaderThemePalette {
        ReaderThemePalette(
            family: family, scheme: scheme,
            background: ReaderColor(background), text: ReaderColor(text), muted: ReaderColor(muted),
            surface: ReaderColor(surface), codeBackground: ReaderColor(codeBackground), border: ReaderColor(border),
            link: ReaderColor(link), tableStripe: ReaderColor(tableStripe), tableHeader: ReaderColor(tableHeader),
            red: ReaderColor(red), purple: ReaderColor(purple), blue: ReaderColor(blue),
            green: ReaderColor(green), orange: ReaderColor(orange), yellow: ReaderColor(yellow)
        )
    }
}

extension Notification.Name {
    static let readerThemeDidChange = Notification.Name("readerThemeDidChange")
}

final class ThemePreferences: ObservableObject {
    static let shared = ThemePreferences()

    static let appearanceKey = "readerAppearanceMode"
    static let lightThemeKey = "readerLightTheme"
    static let darkThemeKey = "readerDarkTheme"
    private static let legacyAppearanceKey = "appearanceMode"

    @Published var appearanceMode: ReaderAppearanceMode {
        didSet {
            guard appearanceMode != oldValue else { return }
            store.set(appearanceMode.rawValue, forKey: Self.appearanceKey)
            preferencesDidChange(updateAppearance: true)
        }
    }

    @Published var lightTheme: ReaderThemeFamily {
        didSet {
            guard lightTheme != oldValue else { return }
            store.set(lightTheme.rawValue, forKey: Self.lightThemeKey)
            preferencesDidChange(updateAppearance: false)
        }
    }

    @Published var darkTheme: ReaderThemeFamily {
        didSet {
            guard darkTheme != oldValue else { return }
            store.set(darkTheme.rawValue, forKey: Self.darkThemeKey)
            preferencesDidChange(updateAppearance: false)
        }
    }

    private let store: UserDefaults
    private let appliesApplicationAppearance: Bool

    init(store: UserDefaults = .standard, appliesApplicationAppearance: Bool = true) {
        self.store = store
        self.appliesApplicationAppearance = appliesApplicationAppearance
        let storedAppearance = store.string(forKey: Self.appearanceKey)
        let legacyAppearance = store.string(forKey: Self.legacyAppearanceKey)
        let migratedAppearance = legacyAppearance == "system" ? "automatic" : legacyAppearance
        appearanceMode = ReaderAppearanceMode(
            rawValue: storedAppearance ?? migratedAppearance ?? ""
        ) ?? .automatic
        lightTheme = ReaderThemeFamily(
            rawValue: store.string(forKey: Self.lightThemeKey) ?? ""
        ) ?? .default
        darkTheme = ReaderThemeFamily(
            rawValue: store.string(forKey: Self.darkThemeKey) ?? ""
        ) ?? .default
    }

    func resolvedScheme(systemIsDark: Bool) -> ReaderColorScheme {
        appearanceMode.resolvedScheme(systemIsDark: systemIsDark)
    }

    func palette(systemIsDark: Bool) -> ReaderThemePalette {
        palette(for: resolvedScheme(systemIsDark: systemIsDark))
    }

    func palette(for scheme: ReaderColorScheme) -> ReaderThemePalette {
        let family = scheme == .dark ? darkTheme : lightTheme
        return ReaderThemeCatalog.palette(for: family, scheme: scheme)
    }

    func applyApplicationAppearance() {
        guard appliesApplicationAppearance else { return }
        let appearance: NSAppearance?
        switch appearanceMode {
        case .automatic: appearance = nil
        case .light: appearance = NSAppearance(named: .aqua)
        case .dark: appearance = NSAppearance(named: .darkAqua)
        }
        NSApp.appearance = appearance
    }

    private func preferencesDidChange(updateAppearance: Bool) {
        if updateAppearance { applyApplicationAppearance() }
        NotificationCenter.default.post(name: .readerThemeDidChange, object: self)
    }
}

enum ReaderSettingsLayout {
    static let pagePadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 18
    static let rowHorizontalPadding: CGFloat = 14
    static let rowVerticalPadding: CGFloat = 11
    static let rowLabelWidth: CGFloat = 126
    static let rowSpacing: CGFloat = 18
    static let controlWidth: CGFloat = 330
    static let themePickerWidth: CGFloat = 208
    static let cornerRadius: CGFloat = 10
}

struct ReaderSettingsSection<Content: View>: View {
    let title: String
    let detail: String?
    private let content: Content

    init(
        _ title: String,
        detail: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: ReaderSettingsLayout.cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .clipShape(
                RoundedRectangle(cornerRadius: ReaderSettingsLayout.cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ReaderSettingsLayout.cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 0.5)
            )
        }
    }
}

struct ReaderSettingsRow<Control: View>: View {
    let title: String
    let detail: String
    let minimumHeight: CGFloat
    private let control: Control

    init(
        title: String,
        detail: String,
        minimumHeight: CGFloat = 58,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.detail = detail
        self.minimumHeight = minimumHeight
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: ReaderSettingsLayout.rowSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: ReaderSettingsLayout.rowLabelWidth, alignment: .leading)

            control
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, ReaderSettingsLayout.rowHorizontalPadding)
        .padding(.vertical, ReaderSettingsLayout.rowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: minimumHeight)
    }
}

struct ReaderSettingsSeparator: View {
    var body: some View {
        Divider()
            .padding(.leading, ReaderSettingsLayout.rowHorizontalPadding)
    }
}

struct ThemeSettingsView: View {
    @ObservedObject var preferences: ThemePreferences
    @ObservedObject var typographyPreferences: TypographyPreferences

    init(
        preferences: ThemePreferences = .shared,
        typographyPreferences: TypographyPreferences = .shared
    ) {
        self.preferences = preferences
        self.typographyPreferences = typographyPreferences
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ReaderSettingsLayout.sectionSpacing) {
            ReaderSettingsSection("Appearance") {
                ReaderSettingsRow(
                    title: "Mode",
                    detail: "Automatic follows the macOS appearance."
                ) {
                    Picker("Appearance", selection: $preferences.appearanceMode) {
                        ForEach(ReaderAppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                }
            }

            ReaderSettingsSection(
                "Theme Pair",
                detail: "Light and dark selections are saved independently."
            ) {
                ReaderSettingsRow(
                    title: "Light Theme",
                    detail: "Used in light appearance."
                ) {
                    ThemeSelectionControl(
                        scheme: .light,
                        selection: $preferences.lightTheme,
                        font: typographyPreferences.ui.nsFont
                    )
                }

                ReaderSettingsSeparator()

                ReaderSettingsRow(
                    title: "Dark Theme",
                    detail: "Used in dark appearance."
                ) {
                    ThemeSelectionControl(
                        scheme: .dark,
                        selection: $preferences.darkTheme,
                        font: typographyPreferences.ui.nsFont
                    )
                }
            }

            ReaderSettingsSection("Preview") {
                ThemePreviewPair(
                    lightPalette: preferences.palette(for: .light),
                    darkPalette: preferences.palette(for: .dark)
                )
            }
        }
        .padding(ReaderSettingsLayout.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ThemeSelectionControl: View {
    let scheme: ReaderColorScheme
    @Binding var selection: ReaderThemeFamily
    let font: NSFont

    var body: some View {
        HStack(spacing: 12) {
            PaletteSwatches(
                palette: ReaderThemeCatalog.palette(for: selection, scheme: scheme)
            )

            ThemePopUpPicker(scheme: scheme, selection: $selection, font: font)
                .frame(width: ReaderSettingsLayout.themePickerWidth)
        }
        .frame(width: 300, alignment: .trailing)
    }
}

private struct ThemePopUpPicker: NSViewRepresentable {
    let scheme: ReaderColorScheme
    @Binding var selection: ReaderThemeFamily
    let font: NSFont

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.alignment = .left
        button.autoenablesItems = false
        button.cell?.lineBreakMode = .byTruncatingTail
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionDidChange(_:))
        update(button)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        update(button)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        // Size the control itself, not an invisible frame around its title-sized bezel.
        CGSize(width: ReaderSettingsLayout.themePickerWidth, height: nsView.intrinsicContentSize.height)
    }

    private func update(_ button: NSPopUpButton) {
        let families = ReaderThemeFamily.allCases
        let titles = families.map { $0.variantName(for: scheme) }
        if button.itemTitles != titles {
            button.removeAllItems()
            button.addItems(withTitles: titles)
        }
        if button.font != font {
            button.font = font
            button.menu?.font = font
            button.invalidateIntrinsicContentSize()
        }
        if let index = families.firstIndex(of: selection), button.indexOfSelectedItem != index {
            button.selectItem(at: index)
        }
        button.setAccessibilityIdentifier("theme-picker-\(scheme.rawValue)")
        button.setAccessibilityLabel(scheme == .light ? "Light Theme" : "Dark Theme")
    }

    final class Coordinator: NSObject {
        var parent: ThemePopUpPicker

        init(parent: ThemePopUpPicker) {
            self.parent = parent
        }

        @objc func selectionDidChange(_ button: NSPopUpButton) {
            let families = ReaderThemeFamily.allCases
            guard families.indices.contains(button.indexOfSelectedItem) else { return }
            parent.selection = families[button.indexOfSelectedItem]
        }
    }
}

private struct PaletteSwatches: View {
    let palette: ReaderThemePalette

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(color.color)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(palette.border.color, lineWidth: 0.5))
            }
        }
        .accessibilityLabel("\(palette.displayName) palette preview")
    }

    private var colors: [ReaderColor] {
        [palette.background, palette.text, palette.link,
         palette.purple, palette.green, palette.orange]
    }
}

private struct ThemePreviewPair: View {
    let lightPalette: ReaderThemePalette
    let darkPalette: ReaderThemePalette

    var body: some View {
        HStack(spacing: 0) {
            ThemePreviewPane(palette: lightPalette)

            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(width: 0.5)

            ThemePreviewPane(palette: darkPalette)
        }
        .frame(height: 102)
    }
}

private struct ThemePreviewPane: View {
    let palette: ReaderThemePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(palette.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.text.color)
            Text("Markdown heading")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.text.color)
            (
                Text("Readable body text with a ")
                    .foregroundColor(palette.muted.color)
                + Text("link")
                    .foregroundColor(palette.link.color)
                    .underline()
            )
                .font(.caption)
                .lineLimit(1)
            HStack(spacing: 5) {
                Text("let")
                    .foregroundStyle(palette.purple.color)
                Text("theme")
                    .foregroundStyle(palette.blue.color)
                Text("=")
                    .foregroundStyle(palette.muted.color)
                Text("\"active\"")
                    .foregroundStyle(palette.green.color)
            }
            .font(.system(size: 11, design: .monospaced))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.background.color)
    }
}
