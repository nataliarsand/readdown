import XCTest
@testable import ReadDown

final class MarkdownRendererTests: XCTestCase {

    // MARK: - Headings

    func testHeadings() {
        XCTAssertEqual(MarkdownRenderer.render("# Hello").html, "<h1 id=\"hello\">Hello</h1>")
        XCTAssertEqual(MarkdownRenderer.render("## Hello").html, "<h2 id=\"hello\">Hello</h2>")
        XCTAssertEqual(MarkdownRenderer.render("### Hello").html, "<h3 id=\"hello\">Hello</h3>")
        XCTAssertEqual(MarkdownRenderer.render("###### Hello").html, "<h6 id=\"hello\">Hello</h6>")
    }

    func testHeadingWithInlineFormatting() {
        let result = MarkdownRenderer.render("# Hello **world**").html
        XCTAssertTrue(result.contains("<strong>world</strong>"))
    }

    func testHeadingSlugs() {
        // Spaces become hyphens, punctuation is stripped, case is lowered.
        XCTAssertEqual(
            MarkdownRenderer.render("## Getting Started").html,
            "<h2 id=\"getting-started\">Getting Started</h2>"
        )
        XCTAssertEqual(
            MarkdownRenderer.render("## What's New?").html,
            "<h2 id=\"whats-new\">What&#39;s New?</h2>"
        )
        // Duplicate headings get -1, -2 suffixes.
        let dup = MarkdownRenderer.render("# Intro\n\n# Intro\n\n# Intro").html
        XCTAssertTrue(dup.contains("<h1 id=\"intro\">Intro</h1>"))
        XCTAssertTrue(dup.contains("<h1 id=\"intro-1\">Intro</h1>"))
        XCTAssertTrue(dup.contains("<h1 id=\"intro-2\">Intro</h1>"))
        // Unicode letters survive.
        XCTAssertEqual(
            MarkdownRenderer.render("## Café Münchner").html,
            "<h2 id=\"café-münchner\">Café Münchner</h2>"
        )
    }

    // MARK: - Emphasis

    func testBold() {
        XCTAssertEqual(MarkdownRenderer.render("**bold**").html, "<p><strong>bold</strong></p>")
        XCTAssertEqual(MarkdownRenderer.render("__bold__").html, "<p><strong>bold</strong></p>")
    }

    func testItalic() {
        XCTAssertEqual(MarkdownRenderer.render("*italic*").html, "<p><em>italic</em></p>")
        XCTAssertEqual(MarkdownRenderer.render("_italic_").html, "<p><em>italic</em></p>")
    }

    func testBoldItalic() {
        XCTAssertEqual(MarkdownRenderer.render("***both***").html, "<p><strong><em>both</em></strong></p>")
    }

    func testStrikethrough() {
        XCTAssertEqual(MarkdownRenderer.render("~~deleted~~").html, "<p><del>deleted</del></p>")
    }

    // MARK: - Code

    func testInlineCode() {
        XCTAssertEqual(MarkdownRenderer.render("`code`").html, "<p><code>code</code></p>")
    }

    func testUnderscoresInCodeSpanAreNotEmphasis() {
        // Issue #6: the emphasis passes reached inside code spans and ate
        // underscores (turning them into <em>). Code span content must render
        // verbatim per CommonMark — including across two code spans in one
        // paragraph, which is what the original report hit.
        let twoLines = MarkdownRenderer.render(
            "This is test `test_text.md`\nAnother line `~/test_text.md`").html
        XCTAssertTrue(twoLines.contains("<code>test_text.md</code>"))
        XCTAssertTrue(twoLines.contains("<code>~/test_text.md</code>"))
        XCTAssertFalse(twoLines.contains("<em>"))

        XCTAssertEqual(MarkdownRenderer.render("`a_b_c`").html, "<p><code>a_b_c</code></p>")
        XCTAssertEqual(MarkdownRenderer.render("`a*b*c`").html, "<p><code>a*b*c</code></p>")
    }

    func testHtmlTagsInCodeSpanAreLiteral() {
        // Code span content must be fully verbatim — HTML tags inside it render
        // as escaped text, not real markup.
        XCTAssertEqual(MarkdownRenderer.render("`<div>`").html, "<p><code>&lt;div&gt;</code></p>")
        let em = MarkdownRenderer.render("`<em>hi</em>`").html
        XCTAssertTrue(em.contains("<code>&lt;em&gt;hi&lt;/em&gt;</code>"))
        XCTAssertFalse(em.contains("<em>"))
    }

    func testFencedCodeBlock() {
        let md = "```swift\nlet x = 1\n```"
        let result = MarkdownRenderer.render(md).html
        XCTAssertTrue(result.contains("<pre><code class=\"language-swift\">"))
        XCTAssertTrue(result.contains("let x = 1"))
    }

    func testFencedCodeBlockNoLanguage() {
        let md = "```\nplain code\n```"
        let result = MarkdownRenderer.render(md).html
        XCTAssertTrue(result.contains("<pre><code>"))
        XCTAssertFalse(result.contains("nohighlight"))
        XCTAssertTrue(result.contains("plain code"))
    }

    func testCodeBlockEscapesHTML() {
        let md = "```\n<div>test</div>\n```"
        let result = MarkdownRenderer.render(md).html
        XCTAssertTrue(result.contains("&lt;div&gt;"))
    }

    // MARK: - Links and Images

    func testLink() {
        let result = MarkdownRenderer.render("[Click](https://example.com)").html
        XCTAssertEqual(result, "<p><a href=\"https://example.com\">Click</a></p>")
    }

    func testImage() {
        let result = MarkdownRenderer.render("![Alt](https://example.com/img.png)").html
        XCTAssertEqual(result, "<p><img src=\"https://example.com/img.png\" alt=\"Alt\"></p>")
    }

    func testMailtoLink() {
        let result = MarkdownRenderer.render("[Email](mailto:test@example.com)").html
        XCTAssertTrue(result.contains("href=\"mailto:test@example.com\""))
    }

    func testAnchorLink() {
        let result = MarkdownRenderer.render("[Section](#section)").html
        XCTAssertTrue(result.contains("href=\"#section\""))
    }

    // MARK: - URL Safety

    func testJavascriptURLBlocked() {
        let result = MarkdownRenderer.render("[xss](javascript:alert(1))").html
        XCTAssertFalse(result.contains("href"))
        XCTAssertFalse(result.contains("javascript"))
    }

    func testDataURLBlocked() {
        let result = MarkdownRenderer.render("[xss](data:text/html,<script>alert(1)</script>)").html
        XCTAssertFalse(result.contains("href"))
    }

    func testProtocolRelativeURLBlocked() {
        let result = MarkdownRenderer.render("[xss](//evil.com)").html
        XCTAssertFalse(result.contains("href"))
    }

    func testSafeURLsAllowed() {
        let httpResult = MarkdownRenderer.render("[ok](https://example.com)").html
        XCTAssertTrue(httpResult.contains("href"))

        let relativeResult = MarkdownRenderer.render("[ok](./file.md)").html
        XCTAssertTrue(relativeResult.contains("href"))
    }

    // MARK: - Lists

    func testUnorderedList() {
        let md = "- one\n- two\n- three"
        let result = MarkdownRenderer.render(md).html
        XCTAssertTrue(result.contains("<ul>"))
        XCTAssertTrue(result.contains("<li>one</li>"))
        XCTAssertTrue(result.contains("<li>two</li>"))
        XCTAssertTrue(result.contains("<li>three</li>"))
    }

    func testNestedUnorderedList() {
        // A nested list was emitted as a sibling <ul> of the parent <li>
        // (invalid HTML). It must render *inside* the parent <li>.
        let basic = MarkdownRenderer.render("- parent\n  - child").html
        XCTAssertEqual(basic, "<ul><li>parent<ul><li>child</li></ul></li></ul>")
        XCTAssertFalse(basic.contains("</li><ul>"))

        // A top-level item after a nested run stays a sibling of the right <li>.
        let mixed = MarkdownRenderer.render("- a\n  - a1\n- b").html
        XCTAssertEqual(mixed, "<ul><li>a<ul><li>a1</li></ul></li><li>b</li></ul>")
    }

    func testBoldDoesNotLeakAcrossListItemsWhenCodeSpansContainHTMLTags() {
        // DECISIONS.md regression: a bullet whose code spans contained `<strong>`
        // and `<em>` (real HTML tag names) used to leak those tags through and
        // turn every following <li> bold via the parser's active-formatting list.
        let md = """
        **Apply when (setting):**

        - Don't wrap `b3nd` in `<strong>`, `<em>`, `**…**`, `*…*`, or any equivalent.
        - Don't ship bold/italic cuts of the logo font. One face, one weight.
        - Don't let surrounding context cascade into the word — `<b-3>` resets by default.
        """
        let html = MarkdownRenderer.render(md).html

        XCTAssertTrue(html.contains("<strong>Apply when (setting):</strong>"))
        // The bullets must not be wrapped in <strong>.
        XCTAssertFalse(html.contains("<strong>Don't ship"))
        XCTAssertFalse(html.contains("<strong>Don't let"))
        // The HTML-tag code spans must render as escaped literal text.
        XCTAssertTrue(html.contains("<code>&lt;strong&gt;</code>"))
        XCTAssertTrue(html.contains("<code>&lt;em&gt;</code>"))
        // And there must be no unbalanced/raw <strong> or <em> outside <code>.
        XCTAssertFalse(html.contains("<code><strong>"))
        XCTAssertFalse(html.contains("<code><em>"))
    }

    func testOrderedList() {
        let md = "1. first\n2. second"
        let result = MarkdownRenderer.render(md).html
        XCTAssertTrue(result.contains("<ol>"))
        XCTAssertTrue(result.contains("<li>first</li>"))
        XCTAssertTrue(result.contains("<li>second</li>"))
    }

    func testTaskList() {
        let md = "- [ ] todo\n- [x] done"
        let result = MarkdownRenderer.render(md).html
        XCTAssertTrue(result.contains("task-list"))
        XCTAssertTrue(result.contains("checkbox\" disabled"))
        XCTAssertTrue(result.contains("checkbox\" checked disabled"))
    }

    func testListItemContinuationFlows() {
        let md = "- first item that wraps\n  onto a second source line\n- second item"
        let result = MarkdownRenderer.render(md).html
        XCTAssertTrue(result.contains("<li>first item that wraps onto a second source line</li>"))
        XCTAssertFalse(result.contains("<br>"))
    }

    // MARK: - Line breaks

    func testSoftNewlineBecomesSpace() {
        let result = MarkdownRenderer.render("line one\nline two").html
        XCTAssertEqual(result, "<p>line one line two</p>")
    }

    func testHardBreakWithTwoTrailingSpaces() {
        let result = MarkdownRenderer.render("line one  \nline two").html
        XCTAssertEqual(result, "<p>line one<br>line two</p>")
    }

    // MARK: - Blockquote

    func testBlockquote() {
        let result = MarkdownRenderer.render("> quoted text").html
        XCTAssertTrue(result.contains("<blockquote>"))
        XCTAssertTrue(result.contains("quoted text"))
    }

    // MARK: - Horizontal Rule

    func testHorizontalRule() {
        XCTAssertEqual(MarkdownRenderer.render("---").html, "<hr>")
        XCTAssertEqual(MarkdownRenderer.render("***").html, "<hr>")
        XCTAssertEqual(MarkdownRenderer.render("___").html, "<hr>")
    }

    func testHorizontalRuleNeedsThreeChars() {
        let result = MarkdownRenderer.render("--").html
        XCTAssertFalse(result.contains("<hr>"))
    }

    // MARK: - Tables

    func testTable() {
        let md = "| A | B |\n| --- | --- |\n| 1 | 2 |"
        let result = MarkdownRenderer.render(md).html
        XCTAssertTrue(result.contains("<table>"))
        XCTAssertTrue(result.contains("<th"))
        XCTAssertTrue(result.contains("<td"))
        XCTAssertTrue(result.contains("A"))
        XCTAssertTrue(result.contains("1"))
    }

    func testTableAlignment() {
        let md = "| Left | Center | Right |\n| :--- | :---: | ---: |\n| a | b | c |"
        let result = MarkdownRenderer.render(md).html
        XCTAssertTrue(result.contains("align=\"left\""))
        XCTAssertTrue(result.contains("align=\"center\""))
        XCTAssertTrue(result.contains("align=\"right\""))
    }

    // MARK: - HTML Passthrough

    func testHTMLPassthrough() {
        let md = "<div>raw html</div>"
        let result = MarkdownRenderer.render(md).html
        XCTAssertTrue(result.contains("<div>raw html</div>"))
    }

    func testScriptTagInInlineCodeDoesNotBreakPreview() {
        // Issue #3: Literal `<script>` inside a code span used to be preserved as a real tag,
        // causing the browser to swallow everything after it as script source.
        let result = MarkdownRenderer.render("Add a `<script>` tag").html
        XCTAssertTrue(result.contains("<code>&lt;script&gt;</code>"))
        XCTAssertFalse(result.contains("<code><script>"))
    }

    func testBareScriptTagIsEscaped() {
        let result = MarkdownRenderer.render("<script>alert(1)</script>").html
        XCTAssertTrue(result.contains("&lt;script&gt;"))
        XCTAssertFalse(result.contains("<script>"))
    }

    func testHTMLEntitiesPassThrough() {
        // Issue #4: Valid HTML entities (named, decimal, hex) render as their character.
        let result = MarkdownRenderer.render("Copyright &copy; 2025 &ndash; &#169; &#xA9;").html
        XCTAssertTrue(result.contains("&copy;"))
        XCTAssertTrue(result.contains("&ndash;"))
        XCTAssertTrue(result.contains("&#169;"))
        XCTAssertTrue(result.contains("&#xA9;"))
        XCTAssertFalse(result.contains("&amp;copy;"))
    }

    func testStrayAmpersandStillEscaped() {
        // Not a valid entity — must still be escaped to avoid malformed HTML.
        let result = MarkdownRenderer.render("Tom & Jerry").html
        XCTAssertTrue(result.contains("Tom &amp; Jerry"))
    }

    func testHTMLCommentPreserved() {
        let result = MarkdownRenderer.render("Before <!-- hidden --> after").html
        XCTAssertTrue(result.contains("<!-- hidden -->"))
        XCTAssertFalse(result.contains("&lt;!--"))
    }

    // MARK: - Links

    func testLinkURLWithParens() {
        // e.g. Wikipedia links like /wiki/Foo_(bar). Underscore is entity-encoded in the href
        // so the later italic regex pass (`_..._`) can't corrupt the attribute.
        let result = MarkdownRenderer.render("[Wiki](https://en.wikipedia.org/wiki/Foo_(bar))").html
        XCTAssertTrue(result.contains("<a href=\"https://en.wikipedia.org/wiki/Foo&#95;(bar)\">Wiki</a>"))
        XCTAssertFalse(result.contains("<em>"))
    }

    func testAutolinkURL() {
        let result = MarkdownRenderer.render("Visit <https://example.com> today").html
        XCTAssertTrue(result.contains("<a href=\"https://example.com\">https://example.com</a>"))
    }

    func testAutolinkEmail() {
        let result = MarkdownRenderer.render("Email <hi@example.com> please").html
        XCTAssertTrue(result.contains("<a href=\"mailto:hi@example.com\">hi@example.com</a>"))
    }

    func testAutolinkRejectsUnsafeScheme() {
        // javascript: or other non-http schemes must not become clickable links.
        let result = MarkdownRenderer.render("<javascript:alert(1)>").html
        XCTAssertFalse(result.contains("<a href=\"javascript:"))
    }

    // MARK: - HTML Escaping

    func testHTMLEscaping() {
        XCTAssertEqual(MarkdownRenderer.escapeHTML("<script>"), "&lt;script&gt;")
        XCTAssertEqual(MarkdownRenderer.escapeHTML("a & b"), "a &amp; b")
        XCTAssertEqual(MarkdownRenderer.escapeHTML("\"quoted\""), "&quot;quoted&quot;")
    }

    func testParagraphPreservesInlineHTML() {
        let result = MarkdownRenderer.render("Hello <em>world</em>").html
        XCTAssertTrue(result.contains("<em>world</em>"))
    }

    func testCodeBlockEscapesAllHTML() {
        let md = "```\n<script>alert(1)</script>\n```"
        let result = MarkdownRenderer.render(md).html
        XCTAssertFalse(result.contains("<script>"))
        XCTAssertTrue(result.contains("&lt;script&gt;"))
    }

    // MARK: - Mermaid

    func testMermaidBlockUsesMermaidClass() {
        let md = "```mermaid\ngraph TD\n    A-->B\n```"
        let result = MarkdownRenderer.render(md)
        XCTAssertTrue(result.html.contains("<pre class=\"mermaid\">"))
        XCTAssertFalse(result.html.contains("<code"))
        XCTAssertTrue(result.hasMermaid)
    }

    func testMermaidBlockNotEscaped() {
        let md = "```mermaid\ngraph TD\n    A-->B\n```"
        let result = MarkdownRenderer.render(md).html
        XCTAssertTrue(result.contains("A-->B"))
        XCTAssertFalse(result.contains("&gt;"))
    }

    func testMermaidCaseInsensitive() {
        let md = "```Mermaid\ngraph TD\n    A-->B\n```"
        let result = MarkdownRenderer.render(md)
        XCTAssertTrue(result.html.contains("<pre class=\"mermaid\">"))
        XCTAssertTrue(result.hasMermaid)
    }

    func testNoMermaidFlagForRegularCode() {
        let md = "```swift\nlet x = 1\n```"
        let result = MarkdownRenderer.render(md)
        XCTAssertFalse(result.hasMermaid)
    }

    // MARK: - Tilde Fences

    func testTildeFenceWithLanguage() {
        let md = "~~~ruby\nputs 'hi'\n~~~"
        let result = MarkdownRenderer.render(md).html
        XCTAssertTrue(result.contains("<pre><code class=\"language-ruby\">"))
        XCTAssertTrue(result.contains("puts &#39;hi&#39;"))
    }

    func testTildeFenceNoLanguage() {
        let md = "~~~\nplain\n~~~"
        let result = MarkdownRenderer.render(md).html
        XCTAssertTrue(result.contains("<pre><code>"))
        XCTAssertFalse(result.contains("nohighlight"))
    }

    func testUnclosedCodeBlock() {
        let md = "```\nno closing fence\nstill going"
        let result = MarkdownRenderer.render(md).html
        XCTAssertTrue(result.contains("<pre><code"))
        XCTAssertTrue(result.contains("no closing fence"))
        XCTAssertTrue(result.contains("still going"))
    }

    // MARK: - Inline Replacement Edge Cases

    func testMultipleInlinePatternsOnOneLine() {
        let result = MarkdownRenderer.render("**bold** and *italic* and `code` and [link](https://x.com)").html
        XCTAssertTrue(result.contains("<strong>bold</strong>"))
        XCTAssertTrue(result.contains("<em>italic</em>"))
        XCTAssertTrue(result.contains("<code>code</code>"))
        XCTAssertTrue(result.contains("<a href=\"https://x.com\">link</a>"))
    }

    func testMultipleLinksOnOneLine() {
        let result = MarkdownRenderer.render("[a](https://a.com) and [b](https://b.com)").html
        XCTAssertTrue(result.contains("href=\"https://a.com\""))
        XCTAssertTrue(result.contains("href=\"https://b.com\""))
    }

    func testMultipleBoldOnOneLine() {
        let result = MarkdownRenderer.render("**one** then **two** then **three**").html
        let count = result.components(separatedBy: "<strong>").count - 1
        XCTAssertEqual(count, 3)
    }

    func testEmojiInParagraph() {
        let result = MarkdownRenderer.render("Hello 🎉 world 🚀").html
        XCTAssertTrue(result.contains("🎉"))
        XCTAssertTrue(result.contains("🚀"))
    }

    func testUnicodeInBold() {
        let result = MarkdownRenderer.render("**café** and *naïve*").html
        XCTAssertTrue(result.contains("<strong>café</strong>"))
        XCTAssertTrue(result.contains("<em>naïve</em>"))
    }

    func testSnakeCaseNotItalicized() {
        let result = MarkdownRenderer.render("use my_var here").html
        XCTAssertTrue(result.contains("my_var"))
    }

    func testLinkWithSpecialCharsInURL() {
        let result = MarkdownRenderer.render("[search](https://google.com/search?q=hello&lang=en)").html
        XCTAssertTrue(result.contains("href=\"https://google.com/search?q=hello&amp;lang=en\""))
    }

    // MARK: - Empty / Edge Cases

    func testEmptyInput() {
        XCTAssertEqual(MarkdownRenderer.render("").html, "")
    }

    func testBlankLines() {
        XCTAssertEqual(MarkdownRenderer.render("\n\n\n").html, "")
    }
}
