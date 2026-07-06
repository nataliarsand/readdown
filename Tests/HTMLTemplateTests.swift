import XCTest
@testable import ReadDown

final class HTMLTemplateTests: XCTestCase {

    func testWrapsBodyInHTML() {
        let result = HTMLTemplate.wrap(body: "<p>Hello</p>")
        XCTAssertTrue(result.contains("<!DOCTYPE html>"))
        XCTAssertTrue(result.contains("<html>"))
        XCTAssertTrue(result.contains("</html>"))
        XCTAssertTrue(result.contains("<p>Hello</p>"))
    }

    func testIncludesDarkModeSupport() {
        let result = HTMLTemplate.wrap(body: "")
        XCTAssertTrue(result.contains("prefers-color-scheme: dark"))
        XCTAssertTrue(result.contains("color-scheme\" content=\"light dark"))
    }

    func testIncludesCharsetMeta() {
        let result = HTMLTemplate.wrap(body: "")
        XCTAssertTrue(result.contains("charset=\"utf-8\"") || result.contains("charset=utf-8"))
    }

    func testIncludesTaskListStyles() {
        let result = HTMLTemplate.wrap(body: "")
        XCTAssertTrue(result.contains("task-list"))
        XCTAssertTrue(result.contains("task-item"))
    }

    // MARK: - Theme stamp (drives Mermaid light/dark)

    func testStampsThemeOnBody() {
        XCTAssertTrue(HTMLTemplate.wrap(body: "", isDark: true).contains("data-rd-theme=\"dark\""))
        XCTAssertTrue(HTMLTemplate.wrap(body: "", isDark: false).contains("data-rd-theme=\"light\""))
    }

    // MARK: - Header blur (main app only)

    func testHeaderBlurPresentInMainApp() {
        let result = HTMLTemplate.wrap(body: "")
        XCTAssertTrue(result.contains("backdrop-filter"))
        XCTAssertTrue(result.contains("body::before"))
    }

    func testHeaderBlurAbsentInQuickLook() {
        let result = HTMLTemplate.wrap(body: "", compact: true)
        XCTAssertFalse(result.contains("backdrop-filter"))
    }

    // MARK: - Print / Export as PDF contract

    func testPrintDisablesHeaderBlur() {
        // A fixed-position ::before would repeat on every printed page.
        let result = HTMLTemplate.wrap(body: "")
        XCTAssertTrue(result.contains("@media print { body::before { display: none; } }"))
    }

    func testPrintStylesKeepBlocksTogether() {
        let result = HTMLTemplate.wrap(body: "")
        XCTAssertTrue(result.contains("@media print"))
        XCTAssertTrue(result.contains("page-break-inside: avoid"))
        XCTAssertTrue(result.contains("page-break-after: avoid"))
    }

    // MARK: - Code-copy assets ship in the page

    func testCodeCopyAssetsPresent() {
        let result = HTMLTemplate.wrap(body: "")
        XCTAssertTrue(result.contains("rd-copy-btn"))
        XCTAssertTrue(result.contains("rd-codeblock"))
    }
}
