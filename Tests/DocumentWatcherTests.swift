import Combine
import XCTest
@testable import ReadDown

final class DocumentWatcherTests: XCTestCase {

    // MARK: - Theme stamping

    func testStampsDarkThemeAtInit() {
        let watcher = DocumentWatcher(initialText: "# Hi", fileURL: nil, isDark: true)
        XCTAssertTrue(watcher.html.contains("data-rd-theme=\"dark\""))
    }

    func testStampsLightThemeAtInit() {
        let watcher = DocumentWatcher(initialText: "# Hi", fileURL: nil, isDark: false)
        XCTAssertTrue(watcher.html.contains("data-rd-theme=\"light\""))
    }

    // MARK: - Live appearance change (the Mermaid dark-mode fix)

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
}
