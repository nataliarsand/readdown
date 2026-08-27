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
        XCTAssertTrue(HTMLTemplate.wrap(body: "", isDark: false)
            .contains("color-scheme\" content=\"light"))
        XCTAssertTrue(HTMLTemplate.wrap(body: "", isDark: true)
            .contains("color-scheme\" content=\"dark"))
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

    func testStampsThemeOnBody() {
        XCTAssertTrue(HTMLTemplate.wrap(body: "", isDark: true).contains("data-rd-theme=\"dark\""))
        XCTAssertTrue(HTMLTemplate.wrap(body: "", isDark: false).contains("data-rd-theme=\"light\""))
    }

    func testInjectsSelectedThemePalette() {
        let palette = ReaderThemeCatalog.palette(for: .catppuccin, scheme: .light)
        let result = HTMLTemplate.wrap(body: "", palette: palette)
        XCTAssertTrue(result.contains("data-rd-theme-family=\"catppuccin\""))
        XCTAssertTrue(result.contains("--bg: #EFF1F5"))
        XCTAssertTrue(result.contains("--text: #4C4F69"))
        XCTAssertTrue(result.contains("--syntax-keyword: #8839EF"))
    }

    func testSyntaxHighlightUsesThemeVariables() {
        let result = HTMLTemplate.wrap(body: "<pre><code class=\"language-swift\">let x = 1</code></pre>")
        XCTAssertTrue(result.contains(".hljs-keyword"))
        XCTAssertTrue(result.contains("color: var(--syntax-keyword)"))
        XCTAssertTrue(result.contains("background: var(--code-bg)"))
    }

    func testInjectsIndependentTypographyVariables() {
        let typography = ReaderTypography(
            ui: ReaderFontSelection(family: "Helvetica Neue", weight: .medium, size: 14),
            body: ReaderFontSelection(family: "Avenir Next", weight: .regular, size: 18),
            code: ReaderFontSelection(family: "Menlo", weight: .semibold, size: 15)
        )
        let result = HTMLTemplate.wrap(body: "<p>Body</p><code>Code</code>", typography: typography)
        XCTAssertTrue(result.contains("--ui-font-size: 14px"))
        XCTAssertTrue(result.contains("--body-font-family: \"Avenir Next\""))
        XCTAssertTrue(result.contains("--body-font-size: 18px"))
        XCTAssertTrue(result.contains("--code-font-family: \"Menlo\""))
        XCTAssertTrue(result.contains("--code-font-weight: 600"))
        XCTAssertTrue(result.contains("font-family: var(--body-font-family)"))
        XCTAssertTrue(result.contains("font-family: var(--code-font-family)"))
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

    func testCodeCopyAssetsPresent() {
        let result = HTMLTemplate.wrap(body: "")
        XCTAssertTrue(result.contains("rd-copy-btn"))
        XCTAssertTrue(result.contains("rd-codeblock"))
    }

    func testInjectsKaTeXWhenHasMath() {
        let result = HTMLTemplate.wrap(
            body: "<span class=\"rd-math rd-math-inline\">x^2</span>", hasMath: true)
        XCTAssertTrue(result.contains("katex.render("))
        XCTAssertTrue(result.contains("throwOnError: false"))
        XCTAssertTrue(result.contains("font-src data:"))
    }

    func testNoKaTeXWhenNoMath() {
        let result = HTMLTemplate.wrap(body: "<p>no math here</p>", hasMath: false)
        XCTAssertFalse(result.contains("katex.render("))
        XCTAssertTrue(result.contains("font-src 'none'"))
    }

    func testMathStylesAlwaysPresent() {
        let result = HTMLTemplate.wrap(body: "")
        XCTAssertTrue(result.contains("rd-math-display"))
    }
}
