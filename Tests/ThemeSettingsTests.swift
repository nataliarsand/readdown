import AppKit
import SwiftUI
import XCTest
@testable import ReadDown

final class ThemeSettingsTests: XCTestCase {
    private static let suiteName = "com.heya.readdown.theme-settings-tests"
    private var store: UserDefaults!

    override func setUp() {
        super.setUp()
        store = UserDefaults(suiteName: Self.suiteName)
        store.removePersistentDomain(forName: Self.suiteName)
    }

    override func tearDown() {
        store.removePersistentDomain(forName: Self.suiteName)
        store = nil
        super.tearDown()
    }

    func testDefaultsToAutomaticAndDefaultThemes() {
        let preferences = ThemePreferences(store: store, appliesApplicationAppearance: false)
        XCTAssertEqual(preferences.appearanceMode, .automatic)
        XCTAssertEqual(preferences.lightTheme, .default)
        XCTAssertEqual(preferences.darkTheme, .default)
    }

    func testPersistsLightAndDarkSelectionsIndependently() {
        let preferences = ThemePreferences(store: store, appliesApplicationAppearance: false)
        preferences.appearanceMode = .dark
        preferences.lightTheme = .catppuccin
        preferences.darkTheme = .nord

        let restored = ThemePreferences(store: store, appliesApplicationAppearance: false)
        XCTAssertEqual(restored.appearanceMode, .dark)
        XCTAssertEqual(restored.lightTheme, .catppuccin)
        XCTAssertEqual(restored.darkTheme, .nord)
        XCTAssertEqual(restored.palette(for: .light).displayName, "Catppuccin Latte")
        XCTAssertEqual(restored.palette(for: .dark).displayName, "Nord Polar Night")
    }

    func testAutomaticFollowsSystemAppearance() {
        let preferences = ThemePreferences(store: store, appliesApplicationAppearance: false)
        XCTAssertEqual(preferences.resolvedScheme(systemIsDark: false), .light)
        XCTAssertEqual(preferences.resolvedScheme(systemIsDark: true), .dark)
    }

    func testForcedAppearanceIgnoresSystemAppearance() {
        let preferences = ThemePreferences(store: store, appliesApplicationAppearance: false)
        preferences.appearanceMode = .light
        XCTAssertEqual(preferences.resolvedScheme(systemIsDark: true), .light)
        preferences.appearanceMode = .dark
        XCTAssertEqual(preferences.resolvedScheme(systemIsDark: false), .dark)
    }

    func testCatalogContainsNineLightAndNineDarkPalettes() {
        XCTAssertEqual(ReaderThemeFamily.allCases.count, 9)
        XCTAssertEqual(ReaderThemeCatalog.allPalettes.count, 18)
        XCTAssertEqual(Set(ReaderThemeCatalog.allPalettes.map(\.id)).count, 18)
    }

    func testEveryPaletteHasReadablePrimaryTextContrast() {
        for palette in ReaderThemeCatalog.allPalettes {
            XCTAssertGreaterThanOrEqual(
                palette.text.contrastRatio(with: palette.background),
                4.5,
                "\(palette.displayName) primary text is below WCAG AA contrast"
            )
        }
    }

    func testSettingsViewFitsTheSettingsWindow() {
        let preferences = ThemePreferences(store: store, appliesApplicationAppearance: false)
        let typography = TypographyPreferences(store: store, postsNotifications: false)
        let hostingView = NSHostingView(rootView: ThemeSettingsView(
            preferences: preferences, typographyPreferences: typography
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 560, height: 460)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertLessThanOrEqual(hostingView.fittingSize.width, 560)
        XCTAssertLessThanOrEqual(hostingView.fittingSize.height, 460)
    }

    func testThemePickerControlsHaveEqualBounds() throws {
        let preferences = ThemePreferences(store: store, appliesApplicationAppearance: false)
        preferences.lightTheme = .catppuccin
        preferences.darkTheme = .catppuccin
        let typography = TypographyPreferences(store: store, postsNotifications: false)
        let hostingView = NSHostingView(rootView: ThemeSettingsView(
            preferences: preferences, typographyPreferences: typography
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        defer { window.contentView = nil }

        let pickers = descendants(of: hostingView).compactMap { $0 as? NSPopUpButton }
        XCTAssertEqual(pickers.count, 2)
        let light = try XCTUnwrap(pickers.first { $0.accessibilityIdentifier() == "theme-picker-light" })
        let dark = try XCTUnwrap(pickers.first { $0.accessibilityIdentifier() == "theme-picker-dark" })
        let lightFrame = hostingView.convert(light.bounds, from: light)
        let darkFrame = hostingView.convert(dark.bounds, from: dark)

        XCTAssertEqual(light.titleOfSelectedItem, "Catppuccin Latte")
        XCTAssertEqual(dark.titleOfSelectedItem, "Catppuccin Mocha")
        XCTAssertEqual(lightFrame.width, ReaderSettingsLayout.themePickerWidth, accuracy: 0.5)
        XCTAssertEqual(lightFrame.width, darkFrame.width, accuracy: 0.5)
        XCTAssertEqual(lightFrame.height, darkFrame.height, accuracy: 0.5)
        XCTAssertEqual(lightFrame.minX, darkFrame.minX, accuracy: 0.5)
        XCTAssertEqual(lightFrame.maxX, darkFrame.maxX, accuracy: 0.5)

        let families = ReaderThemeFamily.allCases
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearanceName)
            for size in [13.0, 20.0] {
                typography.update(
                    ReaderFontSelection(family: "Helvetica Neue", weight: .medium, size: size),
                    for: .ui
                )
                for (index, family) in families.enumerated() {
                    preferences.lightTheme = family
                    preferences.darkTheme = families.reversed()[index]
                    flushLayout(hostingView)

                    XCTAssertEqual(light.titleOfSelectedItem, preferences.palette(for: .light).displayName)
                    XCTAssertEqual(dark.titleOfSelectedItem, preferences.palette(for: .dark).displayName)
                    let updatedLight = hostingView.convert(light.bounds, from: light)
                    let updatedDark = hostingView.convert(dark.bounds, from: dark)
                    XCTAssertEqual(updatedLight.width, ReaderSettingsLayout.themePickerWidth, accuracy: 0.5)
                    XCTAssertEqual(updatedLight.width, updatedDark.width, accuracy: 0.5)
                    XCTAssertEqual(updatedLight.height, updatedDark.height, accuracy: 0.5)
                    XCTAssertEqual(updatedLight.minX, updatedDark.minX, accuracy: 0.5)
                    XCTAssertEqual(updatedLight.maxX, updatedDark.maxX, accuracy: 0.5)
                    XCTAssertEqual(updatedLight.height, light.intrinsicContentSize.height, accuracy: 0.5)
                    XCTAssertEqual(light.font?.pointSize, CGFloat(size))
                    XCTAssertEqual(dark.font?.pointSize, CGFloat(size))
                    XCTAssertEqual(light.font?.familyName, "Helvetica Neue")
                }
            }
        }
    }

    func testThemePickerActionsPersistEachSchemeIndependently() throws {
        let preferences = ThemePreferences(store: store, appliesApplicationAppearance: false)
        let typography = TypographyPreferences(store: store, postsNotifications: false)
        let hostingView = NSHostingView(rootView: ThemeSettingsView(
            preferences: preferences, typographyPreferences: typography
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 560, height: 460)
        hostingView.layoutSubtreeIfNeeded()

        let pickers = descendants(of: hostingView).compactMap { $0 as? NSPopUpButton }
        let light = try XCTUnwrap(pickers.first { $0.accessibilityIdentifier() == "theme-picker-light" })
        let dark = try XCTUnwrap(pickers.first { $0.accessibilityIdentifier() == "theme-picker-dark" })
        XCTAssertEqual(light.itemTitles, ReaderThemeFamily.allCases.map { $0.variantName(for: .light) })
        XCTAssertEqual(dark.itemTitles, ReaderThemeFamily.allCases.map { $0.variantName(for: .dark) })
        XCTAssertEqual(light.accessibilityLabel(), "Light Theme")
        XCTAssertEqual(dark.accessibilityLabel(), "Dark Theme")

        light.selectItem(withTitle: "Catppuccin Latte")
        XCTAssertTrue(light.sendAction(light.action, to: light.target))
        XCTAssertEqual(preferences.lightTheme, .catppuccin)
        XCTAssertEqual(preferences.darkTheme, .default)

        dark.selectItem(withTitle: "Nord Polar Night")
        XCTAssertTrue(dark.sendAction(dark.action, to: dark.target))
        XCTAssertEqual(preferences.lightTheme, .catppuccin)
        XCTAssertEqual(preferences.darkTheme, .nord)

        let restored = ThemePreferences(store: store, appliesApplicationAppearance: false)
        XCTAssertEqual(restored.lightTheme, .catppuccin)
        XCTAssertEqual(restored.darkTheme, .nord)
    }

    private func flushLayout(_ view: NSView) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        view.layoutSubtreeIfNeeded()
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants(of:))
    }
}
