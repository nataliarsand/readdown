import Combine
import XCTest
@testable import ReadDown

final class DocumentWatcherTests: XCTestCase {

    func testStampsDarkThemeAtInit() {
        let watcher = DocumentWatcher(initialText: "# Hi", fileURL: nil, isDark: true)
        XCTAssertTrue(watcher.html.contains("data-rd-theme=\"dark\""))
    }

    func testStampsLightThemeAtInit() {
        let watcher = DocumentWatcher(initialText: "# Hi", fileURL: nil, isDark: false)
        XCTAssertTrue(watcher.html.contains("data-rd-theme=\"light\""))
    }

    func testAppearanceChangeReRendersWithNewTheme() {
        let watcher = DocumentWatcher(initialText: "# Hi", fileURL: nil, isDark: false)
        watcher.appearanceDidChange(isDark: true)
        XCTAssertTrue(watcher.html.contains("data-rd-theme=\"dark\""))
        XCTAssertEqual(watcher.lastChangeSource, .appearance)
    }

    func testAppearanceChangeKeepsTextUntouched() {
        let watcher = DocumentWatcher(initialText: "# Hi\n\nBody", fileURL: nil, isDark: false)
        watcher.appearanceDidChange(isDark: true)
        XCTAssertEqual(watcher.text, "# Hi\n\nBody")
    }

    func testSameAppearanceDoesNotReRender() {
        let watcher = DocumentWatcher(initialText: "# Hi", fileURL: nil, isDark: false)
        let before = watcher.html
        watcher.appearanceDidChange(isDark: false)
        XCTAssertEqual(watcher.html, before)
    }

    func testThemeFamilyChangeReRendersWithoutChangingText() {
        let watcher = DocumentWatcher(initialText: "# Hi\n\nBody", fileURL: nil, isDark: false)
        let palette = ReaderThemeCatalog.palette(for: .nord, scheme: .light)
        watcher.themeDidChange(to: palette)
        XCTAssertTrue(watcher.html.contains("data-rd-theme-family=\"nord\""))
        XCTAssertTrue(watcher.html.contains("--bg: #ECEFF4"))
        XCTAssertEqual(watcher.text, "# Hi\n\nBody")
        XCTAssertEqual(watcher.lastChangeSource, .appearance)
    }

    func testPreferenceNotificationReRendersCurrentThemeFamily() {
        let suiteName = "com.heya.readdown.document-watcher-theme-tests"
        let store = UserDefaults(suiteName: suiteName)!
        store.removePersistentDomain(forName: suiteName)
        defer { store.removePersistentDomain(forName: suiteName) }
        let preferences = ThemePreferences(store: store, appliesApplicationAppearance: false)
        preferences.appearanceMode = .light
        let provider: (Bool) -> ReaderThemePalette = { dark in
            preferences.palette(systemIsDark: dark)
        }
        let watcher = DocumentWatcher(
            initialText: "# Hi",
            fileURL: nil,
            initialPalette: provider(false),
            themeProvider: provider
        )

        preferences.lightTheme = .ayu

        XCTAssertTrue(watcher.html.contains("data-rd-theme-family=\"ayu\""))
        XCTAssertTrue(watcher.html.contains("--bg: #FAFAFA"))
    }

    // MARK: - Disk reload (feeds auto-refresh and Copy to Clipboard)

    func testDiskChangeUpdatesHtmlAndText() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("doc.md")
        try "# First".write(to: file, atomically: true, encoding: .utf8)

        let watcher = DocumentWatcher(initialText: "# First", fileURL: file, isDark: false)
        try "# Second".write(to: file, atomically: true, encoding: .utf8)

        let updated = expectation(description: "html republished after disk change")
        let observation = watcher.$html.dropFirst().sink { _ in updated.fulfill() }
        defer { observation.cancel() }

        watcher.presentedItemDidChange()
        wait(for: [updated], timeout: 5)

        XCTAssertEqual(watcher.text, "# Second")
        XCTAssertTrue(watcher.html.contains("Second"))
        XCTAssertEqual(watcher.lastChangeSource, .disk)
    }

    func testDiskChangeSyncsTextEvenWhenHtmlUnchanged() throws {
        // Trailing whitespace changes the source but not the HTML; Copy must still match disk.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("doc.md")
        try "# Title".write(to: file, atomically: true, encoding: .utf8)

        let watcher = DocumentWatcher(initialText: "# Title", fileURL: file, isDark: false)
        try "# Title   ".write(to: file, atomically: true, encoding: .utf8)

        let updated = expectation(description: "text republished after whitespace-only change")
        let observation = watcher.$text.dropFirst().sink { _ in updated.fulfill() }
        defer { observation.cancel() }

        watcher.presentedItemDidChange()
        wait(for: [updated], timeout: 5)

        XCTAssertEqual(watcher.text, "# Title   ")
    }
}
