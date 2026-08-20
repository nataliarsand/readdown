import XCTest
@testable import ReadDown

final class ClipboardExportTests: XCTestCase {

    private func export(_ markdown: String) -> String {
        ClipboardExport.htmlFragment(fromRenderedBody: MarkdownRenderer.render(markdown).html)
    }

    // MARK: - Semantic structure passes through

    func testHeadingsPassThroughAsBareTags() {
        let html = export("# Title\n\n## Section")
        XCTAssertTrue(html.contains("<h1"))
        XCTAssertTrue(html.contains("<h2"))
    }

    func testTablesPassThroughWithoutInlineStyles() {
        let html = export("| A | B |\n|---|---|\n| 1 | 2 |")
        XCTAssertTrue(html.contains("<table"))
        XCTAssertTrue(html.contains("<th"))
        XCTAssertTrue(html.contains("<td"))
        XCTAssertFalse(html.contains("<table style"))
        XCTAssertFalse(html.contains("<td style"))
    }

    // MARK: - Task checkboxes

    func testTaskCheckboxesBecomeBallotCharacters() {
        let html = export("- [ ] open\n- [x] done")
        XCTAssertFalse(html.contains("<input"))
        XCTAssertTrue(html.contains("☐"))
        XCTAssertTrue(html.contains("☑"))
    }

    // MARK: - Math

    func testInlineMathBecomesTeXSource() {
        let html = export("Euler: $e^{i\\pi} = -1$")
        XCTAssertFalse(html.contains("rd-math"))
        XCTAssertTrue(html.contains("$e^{i\\pi} = -1$"))
        XCTAssertTrue(html.contains("<code"))
    }

    func testDisplayMathBecomesTeXSourceBlock() {
        let html = export("$$\nx^2 + y^2 = z^2\n$$")
        XCTAssertFalse(html.contains("rd-math"))
        XCTAssertTrue(html.contains("$$"))
        XCTAssertTrue(html.contains("x^2 + y^2 = z^2"))
        XCTAssertTrue(html.contains("<pre"))
    }

    func testEscapedMathContentStaysEscaped() {
        let html = export("$a < b$")
        XCTAssertTrue(html.contains("a &lt; b"))
    }

    // MARK: - Code

    func testCodeBlocksCarryMonospaceStyle() {
        let html = export("```swift\nlet x = 1\n```")
        XCTAssertTrue(html.contains("<pre style=\"font-family:'Courier New',monospace\">"))
        XCTAssertTrue(html.contains("let x = 1"))
    }

    func testInlineCodeCarriesMonospaceStyle() {
        let html = export("Use `grep` here")
        XCTAssertTrue(html.contains("<code style=\"font-family:'Courier New',monospace\">grep</code>"))
    }

    // MARK: - Template ships the selection-copy cleaner

    func testTemplateInstallsCopyCleaner() {
        let html = HTMLTemplate.wrap(body: "<p>Hi</p>")
        XCTAssertTrue(html.contains("addEventListener('copy'"))
        XCTAssertTrue(html.contains("text/html"))
    }

    func testTemplateStashesMermaidSource() {
        let html = HTMLTemplate.wrap(body: "<pre class=\"mermaid\">graph TD</pre>", hasMermaid: true)
        XCTAssertTrue(html.contains("data-rd-src"))
    }
}
