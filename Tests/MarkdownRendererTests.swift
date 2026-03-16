import XCTest
@testable import ReadDown

final class MarkdownRendererTests: XCTestCase {

    // MARK: - Headings

    func testHeadings() {
        XCTAssertEqual(MarkdownRenderer.render("# Hello"), "<h1>Hello</h1>")
        XCTAssertEqual(MarkdownRenderer.render("## Hello"), "<h2>Hello</h2>")
        XCTAssertEqual(MarkdownRenderer.render("### Hello"), "<h3>Hello</h3>")
        XCTAssertEqual(MarkdownRenderer.render("###### Hello"), "<h6>Hello</h6>")
    }

    func testHeadingWithInlineFormatting() {
        let result = MarkdownRenderer.render("# Hello **world**")
        XCTAssertTrue(result.contains("<strong>world</strong>"))
    }

    // MARK: - Emphasis

    func testBold() {
        XCTAssertEqual(MarkdownRenderer.render("**bold**"), "<p><strong>bold</strong></p>")
        XCTAssertEqual(MarkdownRenderer.render("__bold__"), "<p><strong>bold</strong></p>")
    }

    func testItalic() {
        XCTAssertEqual(MarkdownRenderer.render("*italic*"), "<p><em>italic</em></p>")
        XCTAssertEqual(MarkdownRenderer.render("_italic_"), "<p><em>italic</em></p>")
    }

    func testBoldItalic() {
        XCTAssertEqual(MarkdownRenderer.render("***both***"), "<p><strong><em>both</em></strong></p>")
    }

    func testStrikethrough() {
        XCTAssertEqual(MarkdownRenderer.render("~~deleted~~"), "<p><del>deleted</del></p>")
    }

    // MARK: - Code

    func testInlineCode() {
        XCTAssertEqual(MarkdownRenderer.render("`code`"), "<p><code>code</code></p>")
    }

    func testFencedCodeBlock() {
        let md = "```swift\nlet x = 1\n```"
        let result = MarkdownRenderer.render(md)
        XCTAssertTrue(result.contains("<pre><code class=\"language-swift\">"))
        XCTAssertTrue(result.contains("let x = 1"))
    }

    func testFencedCodeBlockNoLanguage() {
        let md = "```\nplain code\n```"
        let result = MarkdownRenderer.render(md)
        XCTAssertTrue(result.contains("<pre><code>"))
        XCTAssertTrue(result.contains("plain code"))
    }

    func testCodeBlockEscapesHTML() {
        let md = "```\n<div>test</div>\n```"
        let result = MarkdownRenderer.render(md)
        XCTAssertTrue(result.contains("&lt;div&gt;"))
    }

    // MARK: - Links and Images

    func testLink() {
        let result = MarkdownRenderer.render("[Click](https://example.com)")
        XCTAssertEqual(result, "<p><a href=\"https://example.com\">Click</a></p>")
    }

    func testImage() {
        let result = MarkdownRenderer.render("![Alt](https://example.com/img.png)")
        XCTAssertEqual(result, "<p><img src=\"https://example.com/img.png\" alt=\"Alt\"></p>")
    }

    func testMailtoLink() {
        let result = MarkdownRenderer.render("[Email](mailto:test@example.com)")
        XCTAssertTrue(result.contains("href=\"mailto:test@example.com\""))
    }

    func testAnchorLink() {
        let result = MarkdownRenderer.render("[Section](#section)")
        XCTAssertTrue(result.contains("href=\"#section\""))
    }

    // MARK: - URL Safety

    func testJavascriptURLBlocked() {
        let result = MarkdownRenderer.render("[xss](javascript:alert(1))")
        XCTAssertFalse(result.contains("href"))
        XCTAssertFalse(result.contains("javascript"))
    }

    func testDataURLBlocked() {
        let result = MarkdownRenderer.render("[xss](data:text/html,<script>alert(1)</script>)")
        XCTAssertFalse(result.contains("href"))
    }

    func testProtocolRelativeURLBlocked() {
        let result = MarkdownRenderer.render("[xss](//evil.com)")
        XCTAssertFalse(result.contains("href"))
    }

    func testSafeURLsAllowed() {
        let httpResult = MarkdownRenderer.render("[ok](https://example.com)")
        XCTAssertTrue(httpResult.contains("href"))

        let relativeResult = MarkdownRenderer.render("[ok](./file.md)")
        XCTAssertTrue(relativeResult.contains("href"))
    }

    // MARK: - Lists

    func testUnorderedList() {
        let md = "- one\n- two\n- three"
        let result = MarkdownRenderer.render(md)
        XCTAssertTrue(result.contains("<ul>"))
        XCTAssertTrue(result.contains("<li>one</li>"))
        XCTAssertTrue(result.contains("<li>two</li>"))
        XCTAssertTrue(result.contains("<li>three</li>"))
    }

    func testOrderedList() {
        let md = "1. first\n2. second"
        let result = MarkdownRenderer.render(md)
        XCTAssertTrue(result.contains("<ol>"))
        XCTAssertTrue(result.contains("<li>first</li>"))
        XCTAssertTrue(result.contains("<li>second</li>"))
    }

    func testTaskList() {
        let md = "- [ ] todo\n- [x] done"
        let result = MarkdownRenderer.render(md)
        XCTAssertTrue(result.contains("task-list"))
        XCTAssertTrue(result.contains("checkbox\" disabled"))
        XCTAssertTrue(result.contains("checkbox\" checked disabled"))
    }

    // MARK: - Blockquote

    func testBlockquote() {
        let result = MarkdownRenderer.render("> quoted text")
        XCTAssertTrue(result.contains("<blockquote>"))
        XCTAssertTrue(result.contains("quoted text"))
    }

    // MARK: - Horizontal Rule

    func testHorizontalRule() {
        XCTAssertEqual(MarkdownRenderer.render("---"), "<hr>")
        XCTAssertEqual(MarkdownRenderer.render("***"), "<hr>")
        XCTAssertEqual(MarkdownRenderer.render("___"), "<hr>")
    }

    func testHorizontalRuleNeedsThreeChars() {
        let result = MarkdownRenderer.render("--")
        XCTAssertFalse(result.contains("<hr>"))
    }

    // MARK: - Tables

    func testTable() {
        let md = "| A | B |\n| --- | --- |\n| 1 | 2 |"
        let result = MarkdownRenderer.render(md)
        XCTAssertTrue(result.contains("<table>"))
        XCTAssertTrue(result.contains("<th"))
        XCTAssertTrue(result.contains("<td"))
        XCTAssertTrue(result.contains("A"))
        XCTAssertTrue(result.contains("1"))
    }

    func testTableAlignment() {
        let md = "| Left | Center | Right |\n| :--- | :---: | ---: |\n| a | b | c |"
        let result = MarkdownRenderer.render(md)
        XCTAssertTrue(result.contains("align=\"left\""))
        XCTAssertTrue(result.contains("align=\"center\""))
        XCTAssertTrue(result.contains("align=\"right\""))
    }

    // MARK: - HTML Passthrough

    func testHTMLPassthrough() {
        let md = "<div>raw html</div>"
        let result = MarkdownRenderer.render(md)
        XCTAssertTrue(result.contains("<div>raw html</div>"))
    }

    // MARK: - HTML Escaping

    func testHTMLEscaping() {
        XCTAssertEqual(MarkdownRenderer.escapeHTML("<script>"), "&lt;script&gt;")
        XCTAssertEqual(MarkdownRenderer.escapeHTML("a & b"), "a &amp; b")
        XCTAssertEqual(MarkdownRenderer.escapeHTML("\"quoted\""), "&quot;quoted&quot;")
    }

    func testParagraphPreservesInlineHTML() {
        // Non-block HTML tags are preserved as inline HTML (by design)
        let result = MarkdownRenderer.render("Hello <em>world</em>")
        XCTAssertTrue(result.contains("<em>world</em>"))
    }

    func testCodeBlockEscapesAllHTML() {
        // Inside code blocks, ALL HTML must be escaped
        let md = "```\n<script>alert(1)</script>\n```"
        let result = MarkdownRenderer.render(md)
        XCTAssertFalse(result.contains("<script>"))
        XCTAssertTrue(result.contains("&lt;script&gt;"))
    }

    // MARK: - Empty / Edge Cases

    func testEmptyInput() {
        XCTAssertEqual(MarkdownRenderer.render(""), "")
    }

    func testBlankLines() {
        XCTAssertEqual(MarkdownRenderer.render("\n\n\n"), "")
    }
}
