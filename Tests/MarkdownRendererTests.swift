import XCTest
@testable import ReadDown

final class MarkdownRendererTests: XCTestCase {

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
        XCTAssertEqual(
            MarkdownRenderer.render("## Getting Started").html,
            "<h2 id=\"getting-started\">Getting Started</h2>"
        )
        XCTAssertEqual(
            MarkdownRenderer.render("## What's New?").html,
            "<h2 id=\"whats-new\">What&#39;s New?</h2>"
        )
        let dup = MarkdownRenderer.render("# Intro\n\n# Intro\n\n# Intro").html
        XCTAssertTrue(dup.contains("<h1 id=\"intro\">Intro</h1>"))
        XCTAssertTrue(dup.contains("<h1 id=\"intro-1\">Intro</h1>"))
        XCTAssertTrue(dup.contains("<h1 id=\"intro-2\">Intro</h1>"))
        XCTAssertEqual(
            MarkdownRenderer.render("## Café Münchner").html,
            "<h2 id=\"café-münchner\">Café Münchner</h2>"
        )
        // Consecutive hyphens match GitHub's slug algorithm; collapsing them breaks TOC-tool links.
        XCTAssertEqual(
            MarkdownRenderer.render("## Intro to Programming — Spec Points").html,
            "<h2 id=\"intro-to-programming--spec-points\">Intro to Programming — Spec Points</h2>"
        )
    }

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

    func testInlineCode() {
        XCTAssertEqual(MarkdownRenderer.render("`code`").html, "<p><code>code</code></p>")
    }

    func testUnderscoresInCodeSpanAreNotEmphasis() {
        // Issue #6: two code spans in one paragraph.
        let twoLines = MarkdownRenderer.render(
            "This is test `test_text.md`\nAnother line `~/test_text.md`").html
        XCTAssertTrue(twoLines.contains("<code>test_text.md</code>"))
        XCTAssertTrue(twoLines.contains("<code>~/test_text.md</code>"))
        XCTAssertFalse(twoLines.contains("<em>"))

        XCTAssertEqual(MarkdownRenderer.render("`a_b_c`").html, "<p><code>a_b_c</code></p>")
        XCTAssertEqual(MarkdownRenderer.render("`a*b*c`").html, "<p><code>a*b*c</code></p>")
    }

    func testHtmlTagsInCodeSpanAreLiteral() {
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

    func testFrontMatterRendersAsYAMLCodeBlock() {
        let md = "---\nname: skill\ndescription: <b>x</b>\n---\n# Title"
        let result = MarkdownRenderer.render(md).html
        XCTAssertTrue(result.hasPrefix("<pre><code class=\"language-yaml\">name: skill\ndescription: &lt;b&gt;x&lt;/b&gt;</code></pre>"))
        XCTAssertTrue(result.contains("<h1"))
        XCTAssertFalse(result.contains("<hr>"))
    }

    func testFrontMatterClosedByDots() {
        let result = MarkdownRenderer.render("---\na: 1\n...\ntext").html
        XCTAssertTrue(result.contains("language-yaml\">a: 1</code>"))
        XCTAssertTrue(result.contains("<p>text</p>"))
    }

    func testFrontMatterOnlyOnFirstLine() {
        let result = MarkdownRenderer.render("intro\n\n---\na: 1\n---\n").html
        XCTAssertFalse(result.contains("language-yaml"))
        XCTAssertTrue(result.contains("<hr>"))
    }

    func testUnclosedOrEmptyFrontMatterIsNotSwallowed() {
        let unclosed = MarkdownRenderer.render("---\na: 1\ntext").html
        XCTAssertFalse(unclosed.contains("language-yaml"))
        XCTAssertTrue(unclosed.contains("<hr>"))
        XCTAssertTrue(unclosed.contains("text"))
        let empty = MarkdownRenderer.render("---\n---\ntext").html
        XCTAssertFalse(empty.contains("language-yaml"))
        XCTAssertTrue(empty.contains("text"))
    }

    func testFrontMatterLinksNotHarvestedAsReferences() {
        let result = MarkdownRenderer.render("---\n[ref]: https://a.example\n---\n[ref][]").html
        XCTAssertTrue(result.contains("language-yaml"))
        XCTAssertFalse(result.contains("href=\"https://a.example\""))
    }

    func testDeeplyIndentedFenceStaysParagraphText() {
        let result = MarkdownRenderer.render("Intro\n\n     ```\nafter").html
        XCTAssertTrue(result.contains("```"))
        XCTAssertTrue(result.contains("after"))
        XCTAssertFalse(result.contains("<pre>"))
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

    func testCustomSchemeLinkRenders() {
        let html = MarkdownRenderer.render("[Open](codex://open?file=notes.md)").html
        XCTAssertTrue(html.contains("<a href=\"codex://open?file=notes.md\">Open</a>"))
    }

    func testCustomSchemeReferenceLinkRenders() {
        let html = MarkdownRenderer.render("[Open][ed]\n\n[ed]: vscode://file/a.md").html
        XCTAssertTrue(html.contains("href=\"vscode://file/a.md\""))
    }

    func testCustomSchemeAngleAutolinkRenders() {
        let html = MarkdownRenderer.render("<codex://open>").html
        XCTAssertTrue(html.contains("<a href=\"codex://open\">codex://open</a>"))
    }

    func testBareCustomSchemeTextStaysPlain() {
        let html = MarkdownRenderer.render("Try codex://open?file=x now").html
        XCTAssertFalse(html.contains("<a "))
        XCTAssertTrue(html.contains("codex://open?file=x"))
    }

    func testDeniedSchemesStayLiteral() {
        let denied = [
            "file:///etc/hosts", "smb://server/share", "afp://server/vol", "nfs://host/x", "cifs://host/x",
            "ftp://host/x", "ftps://host/x", "sftp://host/x", "tftp://host/x",
            "ssh://host", "telnet://host", "vnc://host", "x-man-page://ls",
            "ms-settings:display", "ms-word:ofe|u|x", "x-apple.systempreferences:com.apple.x",
            "x-apple-helpbasic://x", "javascript:alert(1)", "vbscript:x", "data:text/html,x",
            "blob:https://x", "about:blank", "applescript://x", "shortcuts://run-shortcut?name=x", "help:anchor",
            "FILE:///etc/hosts", "Smb://server/share"
        ]
        for url in denied {
            let html = MarkdownRenderer.render("[x](\(url))").html
            XCTAssertFalse(html.contains("href"), url)
            XCTAssertTrue(html.contains("x"), url)
        }
    }

    func testDeniedSchemeSmuggledWithTabStaysLiteral() {
        let html = MarkdownRenderer.render("[x](sm\tb://server/share)").html
        XCTAssertFalse(html.contains("href"))
    }

    func testRawHTMLEntityObfuscatedSchemesFollowTheDenylist() {
        // The browser decodes `&colon;` before it parses the scheme.
        let denied = MarkdownRenderer.render("<a href=\"file&colon;///etc/hosts\">x</a>").html
        XCTAssertFalse(denied.contains("href"))
        let numeric = MarkdownRenderer.render("<a href=\"smb&#58;//server/share\">x</a>").html
        XCTAssertFalse(numeric.contains("href"))
        let custom = MarkdownRenderer.render("<a href=\"codex&colon;//open\">x</a>").html
        XCTAssertTrue(custom.contains("href"))
    }

    func testWindowsDriveLetterStaysLiteral() {
        let html = MarkdownRenderer.render("[x](C:\\Users\\me\\notes.md)").html
        XCTAssertFalse(html.contains("href"))
    }

    func testRelativePathWithColonRenders() {
        let html = MarkdownRenderer.render("[x](./notes/10:30-standup.md)").html
        XCTAssertTrue(html.contains("href=\"./notes/10:30-standup.md\""))
    }

    func testSafeURLsAllowed() {
        let httpResult = MarkdownRenderer.render("[ok](https://example.com)").html
        XCTAssertTrue(httpResult.contains("href"))

        let relativeResult = MarkdownRenderer.render("[ok](./file.md)").html
        XCTAssertTrue(relativeResult.contains("href"))
    }

    func testDataURIImageRenders() {
        let uri = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMBAQDJ/pLvAAAAAElFTkSuQmCC"
        let result = MarkdownRenderer.render("![red dot](\(uri))").html
        XCTAssertTrue(result.contains("<img src=\"\(uri)\" alt=\"red dot\">"), result)
    }

    func testDataURIReferenceImageRenders() {
        let uri = "data:image/gif;base64,R0lGODlhAQABAAAAACwAAAAAAQABAAA="
        let result = MarkdownRenderer.render("![dot][d]\n\n[d]: \(uri)").html
        XCTAssertTrue(result.contains("<img src=\"\(uri)\" alt=\"dot\">"), result)
    }

    func testRawImgDataURIPassesThrough() {
        let uri = "data:image/jpeg;base64,/9j/4AAQSkZJRg=="
        let result = MarkdownRenderer.render("<img src=\"\(uri)\" alt=\"x\">").html
        XCTAssertTrue(result.contains("src=\"\(uri)\""), result)
    }

    /// `data:text/html` as an image source is an XSS vector.
    func testNonImageDataURIStillBlocked() {
        let htmlImg = MarkdownRenderer.render("![x](data:text/html,<script>alert(1)</script>)").html
        XCTAssertFalse(htmlImg.contains("<img"))
        let dataLink = MarkdownRenderer.render("[x](data:image/png;base64,AAAA)").html
        XCTAssertFalse(dataLink.contains("href"), "data: URIs stay blocked for links")
    }

    func testUnorderedList() {
        let md = "- one\n- two\n- three"
        let result = MarkdownRenderer.render(md).html
        XCTAssertTrue(result.contains("<ul>"))
        XCTAssertTrue(result.contains("<li>one</li>"))
        XCTAssertTrue(result.contains("<li>two</li>"))
        XCTAssertTrue(result.contains("<li>three</li>"))
    }

    func testNestedUnorderedList() {
        let basic = MarkdownRenderer.render("- parent\n  - child").html
        XCTAssertEqual(basic, "<ul><li>parent<ul><li>child</li></ul></li></ul>")
        XCTAssertFalse(basic.contains("</li><ul>"))

        let mixed = MarkdownRenderer.render("- a\n  - a1\n- b").html
        XCTAssertEqual(mixed, "<ul><li>a<ul><li>a1</li></ul></li><li>b</li></ul>")
    }

    func testBoldDoesNotLeakAcrossListItemsWhenCodeSpansContainHTMLTags() {
        let md = """
        **Apply when (setting):**

        - Don't wrap `b3nd` in `<strong>`, `<em>`, `**…**`, `*…*`, or any equivalent.
        - Don't ship bold/italic cuts of the logo font. One face, one weight.
        - Don't let surrounding context cascade into the word — `<b-3>` resets by default.
        """
        let html = MarkdownRenderer.render(md).html

        XCTAssertTrue(html.contains("<strong>Apply when (setting):</strong>"))
        XCTAssertFalse(html.contains("<strong>Don't ship"))
        XCTAssertFalse(html.contains("<strong>Don't let"))
        XCTAssertTrue(html.contains("<code>&lt;strong&gt;</code>"))
        XCTAssertTrue(html.contains("<code>&lt;em&gt;</code>"))
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

    func testFencedCodeInsideOrderedListItem() {
        let md = """
        1. Lorem ipsum dolor sit amet:
           ```bash
           bin/foobar --yoinks
           ```
        2. Bish bash bosh:
           ```bash
           bin/foobar --yoinks
           ```
        """
        let html = MarkdownRenderer.render(md).html
        let preCount = html.components(separatedBy: "<pre><code class=\"language-bash\">").count - 1
        XCTAssertEqual(preCount, 2, "Both list items should contain a fenced code block")
        XCTAssertTrue(html.contains("bin/foobar --yoinks"))
        XCTAssertFalse(html.contains("```bash"), "Raw fence should not appear as text")
    }

    func testFencedCodeInsideUnorderedListItem() {
        let md = """
        - intro line
          ```swift
          let x = 1
          ```
        - next item
        """
        let html = MarkdownRenderer.render(md).html
        XCTAssertTrue(html.contains("<pre><code class=\"language-swift\">let x = 1</code></pre>"))
        XCTAssertTrue(html.contains("<li>next item</li>"))
    }

    func testBareFencedCodeInsideListItem() {
        let md = """
        - prefix
          ```
          plain code
          ```
        """
        let html = MarkdownRenderer.render(md).html
        XCTAssertTrue(html.contains("<pre><code>plain code</code></pre>"))
    }

    func testUnclosedFencedCodeInsideListItemConsumesToEOF() {
        let md = """
        - start
          ```bash
          oops no close
        """
        let html = MarkdownRenderer.render(md).html
        XCTAssertTrue(html.contains("<pre><code class=\"language-bash\">"))
        XCTAssertTrue(html.contains("oops no close"))
    }

    func testSoftNewlineBecomesSpace() {
        let result = MarkdownRenderer.render("line one\nline two").html
        XCTAssertEqual(result, "<p>line one line two</p>")
    }

    func testHardBreakWithTwoTrailingSpaces() {
        let result = MarkdownRenderer.render("line one  \nline two").html
        XCTAssertEqual(result, "<p>line one<br>line two</p>")
    }

    func testBlockquote() {
        let result = MarkdownRenderer.render("> quoted text").html
        XCTAssertTrue(result.contains("<blockquote>"))
        XCTAssertTrue(result.contains("quoted text"))
    }

    func testHorizontalRule() {
        XCTAssertEqual(MarkdownRenderer.render("---").html, "<hr>")
        XCTAssertEqual(MarkdownRenderer.render("***").html, "<hr>")
        XCTAssertEqual(MarkdownRenderer.render("___").html, "<hr>")
    }

    func testHorizontalRuleNeedsThreeChars() {
        let result = MarkdownRenderer.render("--").html
        XCTAssertFalse(result.contains("<hr>"))
    }

    func testSetextH1() {
        XCTAssertEqual(MarkdownRenderer.render("Title\n===").html, "<h1 id=\"title\">Title</h1>")
    }

    func testSetextH2() {
        XCTAssertEqual(MarkdownRenderer.render("Title\n---").html, "<h2 id=\"title\">Title</h2>")
    }

    func testDashesAloneAreHorizontalRule() {
        XCTAssertEqual(MarkdownRenderer.render("---").html, "<hr>")
        XCTAssertEqual(MarkdownRenderer.render("\n---").html, "<hr>")
    }

    func testSetextWithInlineFormatting() {
        XCTAssertEqual(
            MarkdownRenderer.render("**Bold** title\n===").html,
            "<h1 id=\"bold-title\"><strong>Bold</strong> title</h1>"
        )
    }

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

    func testHTMLPassthrough() {
        let md = "<div>raw html</div>"
        let result = MarkdownRenderer.render(md).html
        XCTAssertTrue(result.contains("<div>raw html</div>"))
    }

    func testScriptTagInInlineCodeDoesNotBreakPreview() {
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
        let result = MarkdownRenderer.render("Copyright &copy; 2025 &ndash; &#169; &#xA9;").html
        XCTAssertTrue(result.contains("&copy;"))
        XCTAssertTrue(result.contains("&ndash;"))
        XCTAssertTrue(result.contains("&#169;"))
        XCTAssertTrue(result.contains("&#xA9;"))
        XCTAssertFalse(result.contains("&amp;copy;"))
    }

    func testStrayAmpersandStillEscaped() {
        let result = MarkdownRenderer.render("Tom & Jerry").html
        XCTAssertTrue(result.contains("Tom &amp; Jerry"))
    }

    func testHTMLCommentPreserved() {
        let result = MarkdownRenderer.render("Before <!-- hidden --> after").html
        XCTAssertTrue(result.contains("<!-- hidden -->"))
        XCTAssertFalse(result.contains("&lt;!--"))
    }

    func testBlockLevelScriptIsEscaped() {
        let result = MarkdownRenderer.render("<div><script>alert(1)</script></div>").html
        XCTAssertTrue(result.contains("&lt;script&gt;"))
        XCTAssertFalse(result.contains("<script>"))
    }

    func testEventHandlerWithoutLeadingSpaceIsStripped() {
        let result = MarkdownRenderer.render("<img src=\"x\"onerror=\"alert(1)\">").html
        XCTAssertFalse(result.lowercased().contains("onerror"))
        XCTAssertTrue(result.contains("<img"))
    }

    func testEventHandlerWithSpaceIsStripped() {
        let result = MarkdownRenderer.render("<a href=\"#\" onclick=\"steal()\">x</a>").html
        XCTAssertFalse(result.lowercased().contains("onclick"))
        XCTAssertTrue(result.contains("href=\"#\""))
    }

    func testDangerousTagsAreEscaped() {
        for tag in ["<iframe src=\"x\">", "<style>body{}</style>", "<base href=\"//evil\">",
                    "<meta http-equiv=\"refresh\">", "<link rel=\"x\">", "<svg onload=\"alert(1)\">",
                    "<object data=\"x\">", "<form action=\"x\">"] {
            let result = MarkdownRenderer.render(tag).html
            XCTAssertTrue(result.contains("&lt;"), "\(tag) should be escaped to text")
        }
    }

    func testSafeInlineHTMLStillPasses() {
        let result = MarkdownRenderer.render("A <span class=\"hl\">x</span>, <kbd>Cmd</kbd>, <br> end").html
        XCTAssertTrue(result.contains("<span class=\"hl\">"))
        XCTAssertTrue(result.contains("<kbd>"))
        XCTAssertTrue(result.contains("<br>"))
    }

    func testCenterTagPassesThrough() {
        let result = MarkdownRenderer.render("<center>middle</center>").html
        XCTAssertTrue(result.contains("<center>middle</center>"))
    }

    func testUnsafeAttributesDroppedSafeKept() {
        let result = MarkdownRenderer.render("<div class=\"ok\" style=\"x\" onmouseover=\"y\">z</div>").html
        XCTAssertTrue(result.contains("class=\"ok\""))
        XCTAssertFalse(result.lowercased().contains("onmouseover"))
        XCTAssertFalse(result.contains("style="))
    }

    func testScriptContentIsOpaque() {
        let result = MarkdownRenderer.render("<div><script>x=1;<h2>LEAK</h2></script></div>").html
        XCTAssertFalse(result.contains("<h2>"), "script content must be opaque, not rendered")
        XCTAssertTrue(result.contains("&lt;h2&gt;"))
    }

    func testBackslashEscapesEmphasis() {
        XCTAssertEqual(MarkdownRenderer.render("\\*not italic\\*").html, "<p>*not italic*</p>")
        XCTAssertEqual(MarkdownRenderer.render("a\\_b\\_c").html, "<p>a_b_c</p>")
    }

    func testBackslashEscapesBlockStarters() {
        XCTAssertEqual(MarkdownRenderer.render("\\# not a heading").html, "<p># not a heading</p>")
        XCTAssertEqual(MarkdownRenderer.render("\\- not a list").html, "<p>- not a list</p>")
    }

    func testBackslashEscapesBracketsAndAngle() {
        // A whole line of `\[…\]` is display math, so the brackets sit mid-line.
        XCTAssertEqual(MarkdownRenderer.render("see \\[1\\] here").html, "<p>see [1] here</p>")
        XCTAssertEqual(MarkdownRenderer.render("less than \\< here").html, "<p>less than &lt; here</p>")
    }

    func testBackslashInsideCodeSpanIsLiteral() {
        XCTAssertEqual(MarkdownRenderer.render("`a\\*b`").html, "<p><code>a\\*b</code></p>")
    }

    func testBackslashBeforeNonPunctuationIsLiteral() {
        XCTAssertEqual(MarkdownRenderer.render("path C:\\next").html, "<p>path C:\\next</p>")
    }

    func testEscapedDollarStillNotMath() {
        XCTAssertEqual(MarkdownRenderer.render("costs \\$5 today").html, "<p>costs $5 today</p>")
    }

    func testRawHTMLDangerousURLSchemesDropped() {
        let a = MarkdownRenderer.render("<a href=\"javascript:alert(1)\">x</a>").html
        XCTAssertFalse(a.lowercased().contains("javascript:"))
        XCTAssertTrue(a.contains("<a"))
        let img = MarkdownRenderer.render("<img src=\"javascript:alert(1)\">").html
        XCTAssertFalse(img.lowercased().contains("javascript:"))
        let safe = MarkdownRenderer.render("<a href=\"https://example.com\">x</a>").html
        XCTAssertTrue(safe.contains("href=\"https://example.com\""))
    }

    func testRawHTMLEntityEncodedSchemesDropped() {
        // The scheme check must decode entities the way the browser will.
        let colon = MarkdownRenderer.render("<a href=\"javascript&colon;alert(1)\">x</a>").html
        XCTAssertFalse(colon.contains("href"))
        let hexTab = MarkdownRenderer.render("<a href=\"jav&#x09;ascript:alert(1)\">x</a>").html
        XCTAssertFalse(hexTab.contains("href"))
        let numeric = MarkdownRenderer.render("<a href=\"javascript&#58;alert(1)\">x</a>").html
        XCTAssertFalse(numeric.contains("href"))
        let noSemi = MarkdownRenderer.render("<a href=\"javascript&#58alert(1)\">x</a>").html
        XCTAssertFalse(noSemi.contains("href"))
        let safeAmp = MarkdownRenderer.render("<a href=\"https://example.com/?a=1&amp;b=2\">x</a>").html
        XCTAssertTrue(safeAmp.contains("href=\"https://example.com/?a=1&amp;b=2\""))
    }

    func testLinkTabSmuggledSchemeDropped() {
        // `jav<TAB>ascript:` navigates as `javascript:`.
        let result = MarkdownRenderer.render("[x](jav\tascript:alert(1))").html
        XCTAssertFalse(result.contains("href"))
    }

    func testIndentedTopLevelFenceDeindentsContent() {
        // CommonMark §6.7: content is de-indented by up to the opener's indent.
        let html = MarkdownRenderer.render("  ```\n  code\n  ```").html
        XCTAssertTrue(html.contains("<pre><code>code</code></pre>"))
    }

    func testTableSwallowsAdjacentPipeLine() {
        // Pinned to GitHub: a pipe line right after a table is another row.
        let md = "| A | B |\n|---|---|\n| 1 | 2 |\nprose | with pipe"
        XCTAssertTrue(MarkdownRenderer.render(md).html.contains("<td align=\"left\">prose</td>"))
    }

    func testLinkURLWithParens() {
        // The underscore is entity-encoded so the italic pass cannot touch the href.
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
        let result = MarkdownRenderer.render("<javascript:alert(1)>").html
        XCTAssertFalse(result.contains("<a href=\"javascript:"))
    }

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

    func testInlineDollarMath() {
        let result = MarkdownRenderer.render("Euler: $e^{i\\pi}+1=0$ done")
        XCTAssertTrue(result.html.contains("<span class=\"rd-math rd-math-inline\">e^{i\\pi}+1=0</span>"))
        XCTAssertTrue(result.hasMath)
        XCTAssertFalse(result.hasMermaid)
    }

    func testInlineParenMath() {
        let result = MarkdownRenderer.render("Inline \\(x^2\\) here")
        XCTAssertTrue(result.html.contains("<span class=\"rd-math rd-math-inline\">x^2</span>"))
        XCTAssertTrue(result.hasMath)
    }

    func testDisplayDollarMathSingleLine() {
        let result = MarkdownRenderer.render("$$\\int_0^1 x\\,dx$$")
        XCTAssertTrue(result.html.contains("<div class=\"rd-math rd-math-display\">\\int_0^1 x\\,dx</div>"))
        XCTAssertTrue(result.hasMath)
    }

    func testDisplayMathMultiLine() {
        let result = MarkdownRenderer.render("$$\nx = y\n+ z\n$$").html
        XCTAssertTrue(result.contains("<div class=\"rd-math rd-math-display\">x = y\n+ z</div>"))
    }

    func testDisplayBracketMath() {
        let result = MarkdownRenderer.render("\\[ a^2 + b^2 \\]").html
        XCTAssertTrue(result.contains("<div class=\"rd-math rd-math-display\">a^2 + b^2</div>"))
    }

    func testMathProtectedFromInlineMarkdown() {
        let underscores = MarkdownRenderer.render("$a_i + b_j$").html
        XCTAssertTrue(underscores.contains("a_i + b_j"))
        XCTAssertFalse(underscores.contains("<em>"))

        let stars = MarkdownRenderer.render("$a * b * c$").html
        XCTAssertTrue(stars.contains("<span class=\"rd-math rd-math-inline\">a * b * c</span>"))
        XCTAssertFalse(stars.contains("<strong>"))
        XCTAssertFalse(stars.contains("<em>"))
    }

    /// KaTeX reads the source back through `textContent`, so entities round-trip.
    func testMathHTMLEscaped() {
        let result = MarkdownRenderer.render("$a < b & c$").html
        XCTAssertTrue(result.contains("a &lt; b &amp; c"))
        XCTAssertFalse(result.contains("a < b"))
    }

    func testCodeSpanBeatsMath() {
        let result = MarkdownRenderer.render("Use `$x$` in code")
        XCTAssertTrue(result.html.contains("<code>$x$</code>"))
        XCTAssertFalse(result.hasMath)
    }

    func testFenceBeatsDisplayMath() {
        let result = MarkdownRenderer.render("```\n$$not math$$\n```")
        XCTAssertTrue(result.html.contains("<pre><code>"))
        XCTAssertTrue(result.html.contains("$$not math$$"))
        XCTAssertFalse(result.hasMath)
    }

    func testDollarAmountsAreNotMath() {
        let result = MarkdownRenderer.render("It cost $5 and then $10 total")
        XCTAssertFalse(result.hasMath)
        XCTAssertFalse(result.html.contains("rd-math"))
    }

    /// A digit right after the opening `$` marks currency, not TeX.
    func testDollarBeforeDigitIsNotMath() {
        let result = MarkdownRenderer.render("It cost $5:$x$ is odd notation")
        XCTAssertFalse(result.html.contains(">5:<"))
    }

    func testEscapedDollarIsLiteral() {
        let result = MarkdownRenderer.render("Price is \\$5 today")
        XCTAssertTrue(result.html.contains("Price is $5 today"))
        XCTAssertFalse(result.hasMath)
    }

    func testDisplayMathSplitsFromParagraph() {
        let result = MarkdownRenderer.render("Some text\n$$x^2$$").html
        XCTAssertTrue(result.contains("<p>Some text</p>"))
        XCTAssertTrue(result.contains("rd-math-display"))
    }

    func testMathInBlockquoteSetsHasMath() {
        let result = MarkdownRenderer.render("> Euler $e^{i\\pi}=-1$")
        XCTAssertTrue(result.hasMath)
        XCTAssertTrue(result.html.contains("rd-math-inline"))
    }

    func testNoMathFlagForPlainText() {
        XCTAssertFalse(MarkdownRenderer.render("just regular **prose** here").hasMath)
    }

    func testDoubleDollarInProseIsNotDisplayMath() {
        let result = MarkdownRenderer.render("Revenue was $$5 million\nNext line of prose")
        XCTAssertFalse(result.hasMath)
        XCTAssertTrue(result.html.contains("$$5 million"))
        XCTAssertTrue(result.html.contains("Next line of prose"))
    }

    func testBackslashBracketInProseIsNotDisplayMath() {
        let result = MarkdownRenderer.render("See \\[RFC 1234] for details\nNext paragraph")
        XCTAssertFalse(result.hasMath)
        XCTAssertTrue(result.html.contains("Next paragraph"))
    }

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

    func testEmptyInput() {
        XCTAssertEqual(MarkdownRenderer.render("").html, "")
    }

    func testBlankLines() {
        XCTAssertEqual(MarkdownRenderer.render("\n\n\n").html, "")
    }

    /// Issue #8 repro: a paragraph line starting with `#24` must still advance the parser.
    func testParagraphLineStartingWithHashNumberDoesNotHang() {
        let input = """
        # test

        Lorem Ipsum is simply dummy text of the printing and typesetting industry. Lorem
        Ipsum has been the industry's standard dummy text ever since 1966, when designers
        at Letraset and James Mosley, the librarian at St Bride Printing Library, took a
        1914 Cicero translation and scrambled it to make dummy text for Letraset's Body
        #24 Type sheets. It has survived not only many decades, but also the leap into
        electronic typesetting, remaining essentially unchanged.
        """
        let html = MarkdownRenderer.render(input).html
        XCTAssertTrue(html.contains("<h1 id=\"test\">test</h1>"))
        XCTAssertTrue(html.contains("#24 Type sheets"),
                      "Line beginning with `#24` should be paragraph content, not split off")
        XCTAssertTrue(html.contains("<p>") && html.contains("</p>"))
    }

    func testStandaloneHashNumberIsParagraph() {
        let html = MarkdownRenderer.render("#24").html
        XCTAssertEqual(html, "<p>#24</p>")
    }

    func testHashWithoutSpaceFollowedByLetterIsParagraph() {
        XCTAssertEqual(MarkdownRenderer.render("#hashtag").html, "<p>#hashtag</p>")
        XCTAssertEqual(MarkdownRenderer.render("#-foo").html, "<p>#-foo</p>")
    }

    func testLoneHashIsEmptyHeading() {
        XCTAssertEqual(MarkdownRenderer.render("#").html, "<h1 id=\"section\"></h1>")
    }

    func testIntraWordUnderscoresAreNotItalic() {
        let html = MarkdownRenderer.render("lots_of_underscores_in_names").html
        XCTAssertFalse(html.contains("<em>"), "Intra-word `_` must not italicize")
        XCTAssertTrue(html.contains("lots_of_underscores_in_names"))
    }

    func testIntraWordDoubleUnderscoresAreNotBold() {
        let html = MarkdownRenderer.render("some__double__underscores").html
        XCTAssertFalse(html.contains("<strong>"), "Intra-word `__` must not bold")
        XCTAssertTrue(html.contains("some__double__underscores"))
    }

    func testStandaloneUnderscoreItalicStillWorks() {
        XCTAssertEqual(MarkdownRenderer.render("_italic_").html, "<p><em>italic</em></p>")
    }

    func testStandaloneDoubleUnderscoreBoldStillWorks() {
        XCTAssertEqual(MarkdownRenderer.render("__bold__").html, "<p><strong>bold</strong></p>")
    }

    func testUnderscoreItalicFlanksPunctuation() {
        let html = MarkdownRenderer.render("(_x_)").html
        XCTAssertTrue(html.contains("<em>x</em>"))
    }

    func testUnderscoreFlankingRespectsUnicodeLetters() {
        let html = MarkdownRenderer.render("мир_слов_здесь").html
        XCTAssertFalse(html.contains("<em>"))
    }

    func testSnakeCaseStaysLiteral() {
        let html = MarkdownRenderer.render("Use snake_case for variables").html
        XCTAssertFalse(html.contains("<em>"))
        XCTAssertTrue(html.contains("snake_case"))
    }

    func testMermaidHTMLCarriesThemeAttribute() {
        let md = """
        # x

        ```mermaid
        flowchart TD
          A[Start] --> B[End]
        ```
        """
        let renderResult = MarkdownRenderer.render(md)
        XCTAssertTrue(renderResult.hasMermaid)

        let darkHTML = HTMLTemplate.wrap(body: renderResult.html, hasMermaid: true, isDark: true)
        XCTAssertTrue(darkHTML.contains("data-rd-theme=\"dark\""))
        XCTAssertTrue(darkHTML.contains("dataset.rdTheme"))
        XCTAssertTrue(darkHTML.contains("dark ? 'dark' : 'default'"))

        let lightHTML = HTMLTemplate.wrap(body: renderResult.html, hasMermaid: true, isDark: false)
        XCTAssertTrue(lightHTML.contains("data-rd-theme=\"light\""))
    }

    func testOrderedListHonorsStartNumber() {
        let html = MarkdownRenderer.render("2. two\n3. three").html
        XCTAssertTrue(html.contains("<ol start=\"2\">"))
        XCTAssertTrue(html.contains("<li>two</li><li>three</li>"))
    }

    func testOrderedListStartingAtZero() {
        let html = MarkdownRenderer.render("0. zero\n1. one").html
        XCTAssertTrue(html.contains("<ol start=\"0\">"))
    }

    func testOrderedListStartingAtOneHasNoStartAttribute() {
        let html = MarkdownRenderer.render("1. one\n2. two").html
        XCTAssertTrue(html.contains("<ol>"))
        XCTAssertFalse(html.contains("start="))
    }

    func testBoldAcrossWrappedListItemLines() {
        let md = """
        - Inline bold on list item **doesn't
          render**, if it line-wraps
        """
        let html = MarkdownRenderer.render(md).html
        XCTAssertTrue(html.contains("<strong>doesn&#39;t render</strong>"),
                      "emphasis must span soft-wrapped list item lines, got: \(html)")
    }

    func testItalicAcrossWrappedOrderedListItemLines() {
        let md = """
        1. first *wraps
           here* fine
        2. second
        """
        let html = MarkdownRenderer.render(md).html
        XCTAssertTrue(html.contains("<em>wraps here</em>"))
    }

    func testCodeSpanAcrossWrappedListItemStaysLiteral() {
        let md = """
        - uses `some
          code` inline
        """
        let html = MarkdownRenderer.render(md).html
        XCTAssertTrue(html.contains("<code>some code</code>"))
    }

    func testNestedOrderedList() {
        let html = MarkdownRenderer.render("1. a\n   1. b").html
        XCTAssertEqual(html, "<ol><li>a<ol><li>b</li></ol></li></ol>")
    }

    func testNestedOrderedListKeepsStart() {
        let html = MarkdownRenderer.render("1. a\n   3. b\n   4. c").html
        XCTAssertEqual(html, "<ol><li>a<ol start=\"3\"><li>b</li><li>c</li></ol></li></ol>")
    }

    func testUnorderedSublistInsideOrderedItem() {
        let html = MarkdownRenderer.render("1. a\n   - b\n2. c").html
        XCTAssertEqual(html, "<ol><li>a<ul><li>b</li></ul></li><li>c</li></ol>")
    }

    func testOrderedSublistInsideUnorderedItem() {
        let html = MarkdownRenderer.render("- a\n  1. b\n- c").html
        XCTAssertEqual(html, "<ul><li>a<ol><li>b</li></ol></li><li>c</li></ul>")
    }

    func testDeeplyNestedMixedList() {
        let md = """
        1. a
           - b
             1. c
        """
        let html = MarkdownRenderer.render(md).html
        XCTAssertEqual(html, "<ol><li>a<ul><li>b<ol><li>c</li></ol></li></ul></li></ol>")
    }

    func testLooseUnorderedListWrapsItemsInParagraphs() {
        let html = MarkdownRenderer.render("- a\n\n- b").html
        XCTAssertEqual(html, "<ul><li><p>a</p></li><li><p>b</p></li></ul>")
    }

    func testLooseOrderedListWrapsItemsInParagraphs() {
        let html = MarkdownRenderer.render("1. a\n\n2. b").html
        XCTAssertEqual(html, "<ol><li><p>a</p></li><li><p>b</p></li></ol>")
    }

    func testMultiParagraphItemStaysInList() {
        let md = """
        - first

          second paragraph
        - third
        """
        let html = MarkdownRenderer.render(md).html
        XCTAssertEqual(html, "<ul><li><p>first</p><p>second paragraph</p></li><li><p>third</p></li></ul>")
    }

    func testLinkWithTitle() {
        XCTAssertEqual(
            MarkdownRenderer.render("[x](https://a.com \"hi\")").html,
            "<p><a href=\"https://a.com\" title=\"hi\">x</a></p>"
        )
    }

    func testImageWithTitle() {
        XCTAssertEqual(
            MarkdownRenderer.render("![a](https://a.com/i.png \"hi\")").html,
            "<p><img src=\"https://a.com/i.png\" alt=\"a\" title=\"hi\"></p>"
        )
    }

    func testLinkWithSingleQuotedTitle() {
        XCTAssertEqual(
            MarkdownRenderer.render("[x](https://a.com 'hi')").html,
            "<p><a href=\"https://a.com\" title=\"hi\">x</a></p>"
        )
    }

    func testLinkWithoutTitleUnchanged() {
        XCTAssertEqual(
            MarkdownRenderer.render("[Click](https://example.com)").html,
            "<p><a href=\"https://example.com\">Click</a></p>"
        )
    }

    func testLinkTitleIsHTMLEscaped() {
        XCTAssertEqual(
            MarkdownRenderer.render("[x](https://a.com \"a<b&c\")").html,
            "<p><a href=\"https://a.com\" title=\"a&lt;b&amp;c\">x</a></p>"
        )
    }

    func testFullReferenceLink() {
        XCTAssertEqual(
            MarkdownRenderer.render("[text][ref]\n\n[ref]: https://a.com").html,
            "<p><a href=\"https://a.com\">text</a></p>"
        )
    }

    func testCollapsedReferenceLink() {
        XCTAssertEqual(
            MarkdownRenderer.render("[text][]\n\n[text]: https://a.com").html,
            "<p><a href=\"https://a.com\">text</a></p>"
        )
    }

    func testShortcutReferenceLink() {
        XCTAssertEqual(
            MarkdownRenderer.render("[ref]\n\n[ref]: https://a.com").html,
            "<p><a href=\"https://a.com\">ref</a></p>"
        )
    }

    func testReferenceLinkLabelIsCaseInsensitive() {
        XCTAssertEqual(
            MarkdownRenderer.render("[Text][REF]\n\n[ref]: https://a.com").html,
            "<p><a href=\"https://a.com\">Text</a></p>"
        )
    }

    func testReferenceLinkWithTitle() {
        XCTAssertEqual(
            MarkdownRenderer.render("[text][ref]\n\n[ref]: https://a.com \"hi\"").html,
            "<p><a href=\"https://a.com\" title=\"hi\">text</a></p>"
        )
    }

    func testUndefinedReferenceRendersLiteral() {
        XCTAssertEqual(
            MarkdownRenderer.render("[text][nope]\n\n[real]: https://a.com").html,
            "<p>[text][nope]</p>"
        )
    }

    func testReferenceDefinitionLineDoesNotRender() {
        XCTAssertEqual(MarkdownRenderer.render("[ref]: https://a.com").html, "")
    }

    func testReferenceLinkInsideListItem() {
        XCTAssertEqual(
            MarkdownRenderer.render("- see [text][ref]\n\n[ref]: https://a.com").html,
            "<ul><li>see <a href=\"https://a.com\">text</a></li></ul>"
        )
    }

    func testFullReferenceImage() {
        XCTAssertEqual(
            MarkdownRenderer.render("![alt][img]\n\n[img]: https://a.com/i.png").html,
            "<p><img src=\"https://a.com/i.png\" alt=\"alt\"></p>"
        )
    }

    func testCollapsedReferenceImage() {
        XCTAssertEqual(
            MarkdownRenderer.render("![alt][]\n\n[alt]: https://a.com/i.png").html,
            "<p><img src=\"https://a.com/i.png\" alt=\"alt\"></p>"
        )
    }

    func testShortcutReferenceImage() {
        XCTAssertEqual(
            MarkdownRenderer.render("![alt]\n\n[alt]: https://a.com/i.png").html,
            "<p><img src=\"https://a.com/i.png\" alt=\"alt\"></p>"
        )
    }

    func testReferenceImageWithTitle() {
        XCTAssertEqual(
            MarkdownRenderer.render("![alt][img]\n\n[img]: https://a.com/i.png \"cap\"").html,
            "<p><img src=\"https://a.com/i.png\" alt=\"alt\" title=\"cap\"></p>"
        )
    }

    func testUndefinedReferenceImageRendersLiteral() {
        XCTAssertEqual(
            MarkdownRenderer.render("![alt][nope]\n\n[real]: https://a.com/i.png").html,
            "<p>![alt][nope]</p>"
        )
    }

    func testReferenceImageUnsafeURLDropped() {
        let html = MarkdownRenderer.render("![x][bad]\n\n[bad]: javascript:alert(1)").html
        XCTAssertFalse(html.contains("<img"))
        XCTAssertFalse(html.contains("javascript"))
    }

    func testReferenceImageInsideListItem() {
        XCTAssertEqual(
            MarkdownRenderer.render("- ![alt][img]\n\n[img]: https://a.com/i.png").html,
            "<ul><li><img src=\"https://a.com/i.png\" alt=\"alt\"></li></ul>"
        )
    }

    func testThematicBreakClosesListWithoutBlankLine() {
        XCTAssertEqual(
            MarkdownRenderer.render("- a\n***").html,
            "<ul><li>a</li></ul>\n<hr>"
        )
    }

    func testBareURLAutolinked() {
        XCTAssertEqual(
            MarkdownRenderer.render("Visit https://x.com now").html,
            "<p>Visit <a href=\"https://x.com\">https://x.com</a> now</p>"
        )
    }

    func testBareURLInCodeSpanNotAutolinked() {
        XCTAssertEqual(
            MarkdownRenderer.render("`https://x.com`").html,
            "<p><code>https://x.com</code></p>"
        )
    }

    func testBareURLTrailingPunctuationTrimmed() {
        XCTAssertEqual(
            MarkdownRenderer.render("(see https://x.com).").html,
            "<p>(see <a href=\"https://x.com\">https://x.com</a>).</p>"
        )
    }
}
