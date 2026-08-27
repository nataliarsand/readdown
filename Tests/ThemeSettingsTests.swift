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
        let hostingView = NSHostingView(rootView: ThemeSettingsView(preferences: preferences))
        hostingView.frame = NSRect(x: 0, y: 0, width: 560, height: 460)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertLessThanOrEqual(hostingView.fittingSize.width, 560)
        XCTAssertLessThanOrEqual(hostingView.fittingSize.height, 460)
    }
}
