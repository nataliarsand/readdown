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
        appearanceMode = ReaderAppearanceMode(
            rawValue: store.string(forKey: Self.appearanceKey) ?? ""
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

struct ThemeSettingsView: View {
    @ObservedObject var preferences: ThemePreferences

    init(preferences: ThemePreferences = .shared) {
        self.preferences = preferences
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Appearance")
                    .font(.headline)
                Picker("Appearance", selection: $preferences.appearanceMode) {
                    ForEach(ReaderAppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            Divider()

            HStack(alignment: .top, spacing: 24) {
                ThemePickerColumn(
                    title: "Light Theme",
                    scheme: .light,
                    selection: $preferences.lightTheme
                )
                ThemePickerColumn(
                    title: "Dark Theme",
                    scheme: .dark,
                    selection: $preferences.darkTheme
                )
            }

            HStack(spacing: 12) {
                ThemePreviewCard(palette: preferences.palette(for: .light))
                ThemePreviewCard(palette: preferences.palette(for: .dark))
            }

            Text("Automatic follows the macOS appearance. Light and dark theme choices are saved independently.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(width: 520)
    }
}

private struct ThemePickerColumn: View {
    let title: String
    let scheme: ReaderColorScheme
    @Binding var selection: ReaderThemeFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Picker(title, selection: $selection) {
                ForEach(ReaderThemeFamily.allCases) { family in
                    Text(family.variantName(for: scheme)).tag(family)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            PaletteSwatches(palette: ReaderThemeCatalog.palette(for: selection, scheme: scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PaletteSwatches: View {
    let palette: ReaderThemePalette

    var body: some View {
        HStack(spacing: 5) {
            ForEach(
                [palette.background, palette.text, palette.link,
                 palette.purple, palette.green, palette.orange],
                id: \.self
            ) { color in
                Circle()
                    .fill(color.color)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(palette.border.color, lineWidth: 0.5))
            }
        }
        .accessibilityLabel("\(palette.displayName) palette preview")
    }
}

private struct ThemePreviewCard: View {
    let palette: ReaderThemePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(palette.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.text.color)
            Text("Markdown heading")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.text.color)
            Text("Readable body text with a link")
                .font(.caption)
                .foregroundStyle(palette.muted.color)
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
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(palette.codeBackground.color, in: RoundedRectangle(cornerRadius: 5))
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(palette.background.color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.border.color, lineWidth: 1)
        )
    }
}
