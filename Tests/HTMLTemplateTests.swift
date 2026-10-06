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

    // MARK: - Table of contents (main app only)

    func testTableOfContentsAssetsPresentInMainApp() {
        let result = HTMLTemplate.wrap(body: "<h1 id=\"intro\">Intro</h1>")
        XCTAssertTrue(result.contains("rd-table-of-contents"))
        XCTAssertTrue(result.contains("window.__rdTableOfContents"))
        XCTAssertTrue(result.contains("data-rd-search-exclude"))
    }

    func testTableOfContentsUsesReaderHairlineBorder() {
        let light = HTMLTemplate.wrap(body: "<h1 id=\"intro\">Intro</h1>")
        let dark = HTMLTemplate.wrap(body: "<h1 id=\"intro\">Intro</h1>", isDark: true)
        XCTAssertTrue(light.contains("--hairline: rgba(31, 35, 40, 0.08)"))
        XCTAssertTrue(dark.contains("--hairline: rgba(230, 237, 243, 0.08)"))
        XCTAssertTrue(light.contains("border: 1px solid var(--hairline)"))
        XCTAssertTrue(light.contains("border-bottom: 1px solid var(--hairline)"))
    }

    func testTableOfContentsMatchesReaderChromeGeometry() {
        let result = HTMLTemplate.wrap(body: "<h1 id=\"intro\">Intro</h1>")
        XCTAssertTrue(result.contains("right: 2px"))
        XCTAssertTrue(result.contains("border-radius: 17px"))
    }

    func testTableOfContentsAbsentInQuickLook() {
        let result = HTMLTemplate.wrap(body: "<h1 id=\"intro\">Intro</h1>", compact: true)
        XCTAssertFalse(result.contains("rd-table-of-contents"))
        XCTAssertFalse(result.contains("window.__rdTableOfContents"))
    }

    func testPrintHidesTableOfContents() {
        let result = HTMLTemplate.wrap(body: "<h1 id=\"intro\">Intro</h1>")
        XCTAssertTrue(result.contains("#rd-table-of-contents { display: none !important; }"))
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
