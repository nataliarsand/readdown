import Foundation

// MARK: - Pre-compiled Regex Patterns

private let fencePattern = try! NSRegularExpression(pattern: "^\\s{0,3}(`{3,}|~{3,})")
private let headingPattern = try! NSRegularExpression(pattern: "^\\s{0,3}#{1,6}(?:\\s+|$)")
private let ulPattern = try! NSRegularExpression(pattern: "^\\s*[-*+] ")
private let olPattern = try! NSRegularExpression(pattern: "^\\s*\\d+\\. ")
private let tableSepPattern = try! NSRegularExpression(pattern: "^\\s*\\|?[\\s:]*-+[\\s:]*\\|")

private let imagePattern = try! NSRegularExpression(pattern: "!\\[([^\\]]*)\\]\\(([^()]+(?:\\([^()]*\\)[^()]*)*)\\)")
private let linkPattern = try! NSRegularExpression(pattern: "\\[([^\\]]*)\\]\\(([^()]+(?:\\([^()]*\\)[^()]*)*)\\)")
private let autolinkURLPattern = try! NSRegularExpression(pattern: "<(https?://[^\\s<>]+)>")
private let autolinkEmailPattern = try! NSRegularExpression(pattern: "<([a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,})>")
private let codePattern = try! NSRegularExpression(pattern: "`([^`]+)`")
private let boldItalicStarPattern = try! NSRegularExpression(pattern: "\\*\\*\\*(.+?)\\*\\*\\*", options: .dotMatchesLineSeparators)
private let boldStarPattern = try! NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*", options: .dotMatchesLineSeparators)
private let italicStarPattern = try! NSRegularExpression(pattern: "\\*(.+?)\\*", options: .dotMatchesLineSeparators)
// Underscore variants require *word-boundary flanking* per CommonMark §6.2 —
// `_` adjacent to a letter, digit, or another `_` on either side is a literal
// underscore, not an emphasis delimiter. This keeps `snake_case`,
// `lots_of_underscores`, `some__double__underscores`, and the like rendering
// as plain text. The lookbehind/lookahead use Unicode letter (`\p{L}`) and
// number (`\p{N}`), plus `_` itself so an italic `_x_` can't sneak in between
// the two `__` of a bold run mid-word. (`*` emphasis is asymmetric and CAN
// flank inside words per CommonMark, so the star patterns above stay
// unchanged.)
private let boldItalicUnderPattern = try! NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_])___(.+?)___(?![\\p{L}\\p{N}_])", options: .dotMatchesLineSeparators)
private let boldUnderPattern = try! NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_])__(.+?)__(?![\\p{L}\\p{N}_])", options: .dotMatchesLineSeparators)
private let italicUnderPattern = try! NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_])_(.+?)_(?![\\p{L}\\p{N}_])", options: .dotMatchesLineSeparators)
private let strikePattern = try! NSRegularExpression(pattern: "~~(.+?)~~", options: .dotMatchesLineSeparators)
// Inline TeX math. `$…$` requires non-space flanking and a non-digit after the
// closing `$`, so prose like "it cost $5 and $7 today" isn't mis-parsed as a
// math span. `\(…\)` is the unambiguous LaTeX inline delimiter. Display math
// (`$$…$$`, `\[…\]`) is block-level and handled directly in `render`. The raw
// TeX is stashed verbatim and emitted into `<span class="rd-math …">` elements
// that the bundled MathJax turns into SVG in the WebView — so no later inline
// pass (escape, emphasis, link, …) can corrupt the source.
private let inlineMathDollarPattern = try! NSRegularExpression(pattern: "(?<![\\\\$])\\$(?=\\S)([^\\n$]*?[^\\s$])\\$(?![0-9$])")
private let inlineMathParenPattern = try! NSRegularExpression(pattern: "\\\\\\((.+?)\\\\\\)")
private let htmlTagPattern = try! NSRegularExpression(pattern: "<!--[\\s\\S]*?-->|</?[a-zA-Z][a-zA-Z0-9]*(?:\\s+[^>]*)?\\/?>")
private let dangerousAttrPattern = try! NSRegularExpression(pattern: "\\s+(?:on\\w+|srcdoc|formaction)\\s*=\\s*(?:\"[^\"]*\"|'[^']*'|[^\\s>]+)", options: .caseInsensitive)
private let htmlEntityPattern = try! NSRegularExpression(pattern: "&(?:[a-zA-Z][a-zA-Z0-9]{0,31}|#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6});")

/// Tags whose content the browser treats as opaque until their closing tag. If we passed these
/// through unescaped, a user's literal `<script>` (even inside an inline code span) would open a
/// real script element and swallow the rest of the document. Always escape them.
private let alwaysEscapedTags: Set<String> = [
    "script", "style", "iframe", "object", "embed",
    "textarea", "noscript", "noembed", "frame", "frameset"
]

enum MarkdownRenderer {

    struct Result {
        let html: String
        let hasMath: Bool
        let hasMermaid: Bool
    }

    static func render(_ markdown: String) -> Result {
        let lines = markdown.components(separatedBy: "\n")
        var html: [String] = []
        var hasMermaid = false
        var i = 0
        // GitHub-style anchor slugs for heading IDs. Tracks duplicate counts so
        // `# Intro` and a later `# Intro` produce `intro` and `intro-1`.
        var headingSlugs: [String: Int] = [:]

        while i < lines.count {
            let line = lines[i]
            // Sentinel for the defensive no-advance guard at the bottom of this
            // loop — every branch below MUST move `i` forward. See issue #8.
            let iAtStart = i

            // Fenced code block (allow up to 3 leading spaces)
            if line.matchesPattern(fencePattern) {
                let stripped = line.drop(while: { $0 == " " || $0 == "\t" })
                let fenceChar: Character = stripped.first == "~" ? "~" : "`"
                let fenceLen = stripped.prefix(while: { $0 == fenceChar }).count
                let lang = String(stripped.dropFirst(fenceLen)).trimmingCharacters(in: .whitespaces)
                let isMermaid = lang.lowercased() == "mermaid"
                var code: [String] = []
                i += 1
                while i < lines.count {
                    let closeTrimmed = lines[i].drop(while: { $0 == " " || $0 == "\t" })
                    let closeLen = closeTrimmed.prefix(while: { $0 == fenceChar }).count
                    if closeLen >= fenceLen
                        && closeTrimmed.dropFirst(closeLen).allSatisfy({ $0.isWhitespace }) {
                        i += 1
                        break
                    }
                    code.append(isMermaid ? lines[i] : escapeHTML(lines[i]))
                    i += 1
                }
                if isMermaid {
                    hasMermaid = true
                    html.append("<pre class=\"mermaid\">\(code.joined(separator: "\n"))</pre>")
                } else {
                    let langAttr = lang.isEmpty ? "" : " class=\"language-\(escapeHTML(lang))\""
                    html.append("<pre><code\(langAttr)>\(code.joined(separator: "\n"))</code></pre>")
                }
                continue
            }

            // Display math block — `$$ … $$` or `\[ … \]`, single- or multi-line.
            // Checked after fenced code (so a code block containing `$$` stays
            // literal) and before the paragraph collector.
            if let mathHTML = parseDisplayMath(&i, lines: lines) {
                if !mathHTML.isEmpty { html.append(mathHTML) }
                continue
            }

            // Blank line
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }

            // Horizontal rule — only lines with 3+ of the same marker and nothing else
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isHorizontalRule(trimmed) {
                html.append("<hr>")
                i += 1
                continue
            }

            // Heading
            if line.matchesPattern(headingPattern) {
                let trimmedLine = String(line.drop(while: { $0 == " " || $0 == "\t" }))
                let level = min(trimmedLine.prefix(while: { $0 == "#" }).count, 6)
                let text = String(trimmedLine.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                let slug = uniqueSlug(for: text, existing: &headingSlugs)
                html.append("<h\(level) id=\"\(slug)\">\(inlineMarkdown(text))</h\(level)>")
                i += 1
                continue
            }

            // Table
            if line.contains("|") && i + 1 < lines.count
                && lines[i + 1].matchesPattern(tableSepPattern) {
                let headerCells = parseTableRow(line)
                let separatorCells = parseTableRow(lines[i + 1])
                var alignments: [String] = []
                for cell in separatorCells {
                    let t = cell.trimmingCharacters(in: .whitespaces)
                    let left = t.hasPrefix(":")
                    let right = t.hasSuffix(":")
                    if left && right {
                        alignments.append("center")
                    } else if right {
                        alignments.append("right")
                    } else {
                        alignments.append("left")
                    }
                }
                i += 2

                var tableHTML = "<table><thead><tr>"
                for (ci, cell) in headerCells.enumerated() {
                    let align = ci < alignments.count ? alignments[ci] : "left"
                    tableHTML += "<th align=\"\(align)\">\(inlineMarkdown(cell.trimmingCharacters(in: .whitespaces)))</th>"
                }
                tableHTML += "</tr></thead><tbody>"

                while i < lines.count && lines[i].contains("|")
                    && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    let cells = parseTableRow(lines[i])
                    tableHTML += "<tr>"
                    for ci in 0..<headerCells.count {
                        let align = ci < alignments.count ? alignments[ci] : "left"
                        let content = ci < cells.count ? cells[ci].trimmingCharacters(in: .whitespaces) : ""
                        tableHTML += "<td align=\"\(align)\">\(inlineMarkdown(content))</td>"
                    }
                    tableHTML += "</tr>"
                    i += 1
                }
                tableHTML += "</tbody></table>"
                html.append(tableHTML)
                continue
            }

            // Blockquote
            if line.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count && lines[i].hasPrefix(">") {
                    let content = String(lines[i].dropFirst(1))
                        .trimmingCharacters(in: .init(charactersIn: " "))
                    quoteLines.append(content)
                    i += 1
                }
                let innerResult = render(quoteLines.joined(separator: "\n"))
                if innerResult.hasMermaid { hasMermaid = true }
                html.append("<blockquote>\(innerResult.html)</blockquote>")
                continue
            }

            // Unordered list (including task lists)
            if line.matchesPattern(ulPattern) {
                html.append(parseUnorderedList(&i, lines: lines))
                continue
            }

            // Ordered list
            if line.matchesPattern(olPattern) {
                var items: [String] = []
                while i < lines.count && lines[i].matchesPattern(olPattern) {
                    let text = lines[i].removingMatch(of: olPattern)
                    i += 1
                    let contHTML = collectListItemContinuation(&i, lines: lines, ownPattern: olPattern)
                    items.append("<li>\(inlineMarkdown(text))\(contHTML)</li>")
                }
                html.append("<ol>\(items.joined())</ol>")
                continue
            }

            // HTML block — pass through raw
            if isHTMLBlockStart(line) {
                var blockLines: [String] = []
                while i < lines.count {
                    let l = lines[i]
                    if l.trimmingCharacters(in: .whitespaces).isEmpty {
                        i += 1
                        break
                    }
                    blockLines.append(l)
                    i += 1
                }
                html.append(blockLines.map { stripDangerousAttributes($0) }.joined(separator: "\n"))
                continue
            }

            // Paragraph — collect contiguous non-blank, non-special lines.
            // The heading check must mirror `headingPattern` exactly (`#` + space
            // or end-of-line): a bare `hasPrefix("#")` rejects lines like `#24`
            // which the heading branch above also (rightly) rejects, leaving the
            // paragraph branch unable to claim them and `i` stuck — an infinite
            // loop (issue #8).
            var para: [String] = []
            while i < lines.count {
                let l = lines[i]
                let t = l.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || l.matchesPattern(headingPattern) || l.hasPrefix(">")
                    || t.hasPrefix("```") || t.hasPrefix("~~~")
                    || l.matchesPattern(ulPattern) || l.matchesPattern(olPattern)
                    || isHTMLBlockStart(l) {
                    break
                }
                if l.contains("|") && i + 1 < lines.count
                    && lines[i + 1].matchesPattern(tableSepPattern) {
                    break
                }
                if isHorizontalRule(t) {
                    break
                }
                para.append(l)
                i += 1
            }
            if !para.isEmpty {
                html.append("<p>\(inlineMarkdown(para.joined(separator: "\n")))</p>")
            }

            // Belt-and-braces: if every branch above somehow declined this line
            // without advancing `i`, force-advance so the renderer can never
            // hang the app. The targeted heading-check fix above closes the
            // known case (issue #8); this guard catches any future regression.
            if i == iAtStart {
                i += 1
            }
        }

        let joined = html.joined(separator: "\n")
        // Inline math is stashed deep inside `inlineMarkdown` (which only returns a
        // String), and display math nested in blockquotes bubbles up through the
        // recursive `render`. Scanning the assembled HTML for the `rd-math` marker
        // catches both without threading a flag through every call site.
        let hasMath = joined.contains("class=\"rd-math")
        return Result(html: joined, hasMath: hasMath, hasMermaid: hasMermaid)
    }

    // MARK: - Inline Markdown

    private static func escapeHTMLPreservingTags(_ text: String) -> String {
        let ns = text as NSString
        let matches = htmlTagPattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return escapeHTMLKeepingEntities(text) }
        var result = ""
        var lastEnd = 0
        for match in matches {
            let r = match.range
            result += escapeHTMLKeepingEntities(ns.substring(with: NSRange(location: lastEnd, length: r.location - lastEnd)))
            let tag = ns.substring(with: r)
            if isAlwaysEscapedTag(tag) {
                result += escapeHTML(tag)
            } else {
                result += stripDangerousAttributes(tag)
            }
            lastEnd = r.location + r.length
        }
        result += escapeHTMLKeepingEntities(ns.substring(from: lastEnd))
        return result
    }

    private static func isAlwaysEscapedTag(_ tag: String) -> Bool {
        var s = tag
        if s.hasPrefix("<") { s = String(s.dropFirst()) }
        if s.hasPrefix("/") { s = String(s.dropFirst()) }
        let name = s.prefix(while: { $0.isLetter || $0.isNumber }).lowercased()
        return alwaysEscapedTags.contains(name)
    }

    /// Like `escapeHTML`, but passes valid HTML entity references (`&copy;`, `&#169;`, `&#xA9;`)
    /// through unchanged so they render as the intended character. Per CommonMark 6.2.
    private static func escapeHTMLKeepingEntities(_ string: String) -> String {
        let ns = string as NSString
        let matches = htmlEntityPattern.matches(in: string, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return escapeHTML(string) }
        var result = ""
        var lastEnd = 0
        for match in matches {
            let r = match.range
            result += escapeHTML(ns.substring(with: NSRange(location: lastEnd, length: r.location - lastEnd)))
            result += ns.substring(with: r)
            lastEnd = r.location + r.length
        }
        result += escapeHTML(ns.substring(from: lastEnd))
        return result
    }

    private static func inlineMarkdown(_ text: String) -> String {
        // Inline code — pulled out *first* so no later inline pass (autolink,
        // escape, link, emphasis, …) can reach inside a code span. CommonMark:
        // code span content is literal. The U+E000/U+E001 Private Use
        // delimiters carry no markdown meaning, so later passes skip them.
        var codeSpans: [String] = []
        var s = text.replacing(codePattern) { match in
            codeSpans.append("<code>\(escapeHTML(match[1]))</code>")
            return "\u{E000}\(codeSpans.count - 1)\u{E001}"
        }

        // Inline math — stashed before every other inline pass so emphasis,
        // escaping, and link parsing can't reach into the TeX source. Code spans
        // are already removed above, so `` `$x$` `` stays literal code. `\$` is an
        // escaped literal dollar and must never open a math span, so park it
        // first and restore it at the very end. `\(…\)` is tried before `$…$`.
        s = s.replacingOccurrences(of: "\\$", with: "\u{E004}")
        var mathSpans: [String] = []
        func stashMath(_ tex: String) -> String {
            mathSpans.append("<span class=\"rd-math rd-math-inline\">\(escapeHTML(tex))</span>")
            return "\u{E002}\(mathSpans.count - 1)\u{E003}"
        }
        s = s.replacing(inlineMathParenPattern) { stashMath($0[1]) }
        s = s.replacing(inlineMathDollarPattern) { stashMath($0[1]) }

        // Autolinks: <https://…> and <user@example.com>. Rewrite to <a> tags before escaping
        // so the rest of the pipeline treats them like any other HTML link.
        s = s.replacing(autolinkURLPattern) { match in
            let url = match[1]
            guard isSafeURL(url) else { return match[0] }
            return "<a href=\"\(escapeURLForAttribute(url))\">\(escapeURLForAttribute(url))</a>"
        }
        s = s.replacing(autolinkEmailPattern) { match in
            let email = match[1]
            return "<a href=\"mailto:\(escapeURLForAttribute(email))\">\(escapeURLForAttribute(email))</a>"
        }
        s = escapeHTMLPreservingTags(s)

        // Images: ![alt](url)
        s = s.replacing(imagePattern) { match in
            let url = sanitizedMarkdownURL(match[2])
            guard isSafeURL(url) else { return match[0] }
            return "<img src=\"\(escapeURLForAttribute(url))\" alt=\"\(match[1])\">"
        }

        // Links: [text](url)
        s = s.replacing(linkPattern) { match in
            let url = sanitizedMarkdownURL(match[2])
            guard isSafeURL(url) else { return "\(match[1])" }
            return "<a href=\"\(escapeURLForAttribute(url))\">\(match[1])</a>"
        }

        // Bold + italic
        s = s.replacing(boldItalicStarPattern) { match in
            "<strong><em>\(match[1])</em></strong>"
        }
        s = s.replacing(boldItalicUnderPattern) { match in
            "<strong><em>\(match[1])</em></strong>"
        }

        // Bold
        s = s.replacing(boldStarPattern) { match in
            "<strong>\(match[1])</strong>"
        }
        s = s.replacing(boldUnderPattern) { match in
            "<strong>\(match[1])</strong>"
        }

        // Italic
        s = s.replacing(italicStarPattern) { match in
            "<em>\(match[1])</em>"
        }
        s = s.replacing(italicUnderPattern) { match in
            "<em>\(match[1])</em>"
        }

        // Strikethrough
        s = s.replacing(strikePattern) { match in
            "<del>\(match[1])</del>"
        }

        // CommonMark: two trailing spaces + newline = hard break. Bare newline = soft break (space) so text reflows.
        s = s.replacingOccurrences(of: "  \n", with: "<br>")
        s = s.replacingOccurrences(of: "\n", with: " ")

        // Restore math spans (raw TeX wrapped for MathJax) and the escaped-dollar
        // placeholder, then code spans — all after the delimiter-based passes.
        for (idx, span) in mathSpans.enumerated() {
            s = s.replacingOccurrences(of: "\u{E002}\(idx)\u{E003}", with: span)
        }
        s = s.replacingOccurrences(of: "\u{E004}", with: "$")

        // Restore code spans now that all delimiter-based passes are done.
        for (idx, span) in codeSpans.enumerated() {
            s = s.replacingOccurrences(of: "\u{E000}\(idx)\u{E001}", with: span)
        }

        return s
    }

    // MARK: - List Helpers

    private static func listItemIndent(_ line: String) -> Int {
        line.prefix(while: { $0 == " " || $0 == "\t" }).reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }

    /// Collects continuation lines for the current list item, advancing `i` past them.
    /// `ownPattern` is the list's own item pattern — a blank line followed by another item of
    /// `ownPattern` continues the list (consumes the blank); anything else terminates it.
    ///
    /// An indented fenced code block inside the continuation is rendered inline
    /// as a block-level `<pre><code>` (issue #9). Without this, the indented
    /// fence wouldn't match `next.hasPrefix("\`\`\`")` and the whole code block
    /// would collapse into prose.
    private static func collectListItemContinuation(_ i: inout Int, lines: [String], ownPattern: NSRegularExpression) -> String {
        var output = ""
        var paragraph: [String] = []

        // Flush any accumulated prose continuation as inline text. Block
        // elements (code fences) flush before they emit so the block sits
        // *between* paragraph fragments, not glued onto one.
        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            output += " " + paragraph.map { inlineMarkdown($0) }.joined(separator: " ")
            paragraph.removeAll()
        }

        while i < lines.count {
            let next = lines[i]
            let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
            if nextTrimmed.isEmpty {
                var peek = i + 1
                while peek < lines.count && lines[peek].trimmingCharacters(in: .whitespaces).isEmpty { peek += 1 }
                if peek < lines.count && lines[peek].matchesPattern(ownPattern) {
                    i = peek
                }
                break
            }

            // Fenced code block inside the item — recognize the fence on the
            // *trimmed* line so list indentation can't hide it. CommonMark §6.7
            // strips the opener's leading-space count from each content line so
            // the code renders flush against `<pre>` rather than carrying the
            // list-item indent into the rendered output.
            if nextTrimmed.matchesPattern(fencePattern) {
                flushParagraph()
                let openerIndent = next.prefix(while: { $0 == " " || $0 == "\t" }).count
                let fenceChar: Character = nextTrimmed.first == "~" ? "~" : "`"
                let fenceLen = nextTrimmed.prefix(while: { $0 == fenceChar }).count
                let lang = String(nextTrimmed.dropFirst(fenceLen)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count {
                    let l = lines[i]
                    let closeTrimmed = l.drop(while: { $0 == " " || $0 == "\t" })
                    let closeLen = closeTrimmed.prefix(while: { $0 == fenceChar }).count
                    if closeLen >= fenceLen
                        && closeTrimmed.dropFirst(closeLen).allSatisfy({ $0.isWhitespace }) {
                        i += 1
                        break
                    }
                    // Strip up to `openerIndent` leading whitespace chars.
                    var content = Substring(l)
                    var stripped = 0
                    while stripped < openerIndent, let first = content.first, first == " " || first == "\t" {
                        content = content.dropFirst()
                        stripped += 1
                    }
                    code.append(escapeHTML(String(content)))
                    i += 1
                }
                let langAttr = lang.isEmpty ? "" : " class=\"language-\(escapeHTML(lang))\""
                output += "<pre><code\(langAttr)>\(code.joined(separator: "\n"))</code></pre>"
                continue
            }

            // Anything that starts a new block at the parent level ends the
            // continuation. The heading check mirrors `headingPattern` (same
            // reason as the paragraph collector — see issue #8).
            if next.matchesPattern(ulPattern) || next.matchesPattern(olPattern)
                || next.matchesPattern(headingPattern) || next.hasPrefix(">") {
                break
            }
            paragraph.append(nextTrimmed)
            i += 1
        }

        flushParagraph()
        return output
    }

    private static func parseUnorderedList(_ i: inout Int, lines: [String]) -> String {
        let baseIndent = listItemIndent(lines[i])
        var hasTaskItem = false
        var result = ""

        while i < lines.count && lines[i].matchesPattern(ulPattern) {
            let currentIndent = listItemIndent(lines[i])
            if currentIndent < baseIndent { break }

            // A more-indented line with no item yet at this level — parse it as
            // a standalone nested list (defensive; well-formed input won't hit
            // this, since nested runs are consumed per-item below).
            if currentIndent > baseIndent {
                result += parseUnorderedList(&i, lines: lines)
                continue
            }

            let text = lines[i].removingMatch(of: ulPattern)
            i += 1

            let contHTML = collectListItemContinuation(&i, lines: lines, ownPattern: ulPattern)

            // A run of more-indented items immediately after this one is this
            // item's nested list — it must render *inside* the <li>. Appending
            // it as a sibling would emit a <ul> as a direct child of <ul>,
            // which is invalid HTML.
            var nestedHTML = ""
            while i < lines.count && lines[i].matchesPattern(ulPattern)
                && listItemIndent(lines[i]) > baseIndent {
                nestedHTML += parseUnorderedList(&i, lines: lines)
            }

            if text == "[ ]" || text.hasPrefix("[ ] ") {
                let content = text.count > 4 ? String(text.dropFirst(4)) : ""
                result += "<li class=\"task-item\"><input type=\"checkbox\" disabled> \(inlineMarkdown(content))\(contHTML)\(nestedHTML)</li>"
                hasTaskItem = true
            } else if text == "[x]" || text == "[X]" || text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
                let content = text.count > 4 ? String(text.dropFirst(4)) : ""
                result += "<li class=\"task-item\"><input type=\"checkbox\" checked disabled> \(inlineMarkdown(content))\(contHTML)\(nestedHTML)</li>"
                hasTaskItem = true
            } else {
                result += "<li>\(inlineMarkdown(text))\(contHTML)\(nestedHTML)</li>"
            }
        }

        let cls = hasTaskItem ? " class=\"task-list\"" : ""
        return "<ul\(cls)>\(result)</ul>"
    }

    // MARK: - Block Helpers

    /// Parses a display-math block opening at `lines[i]` (`$$ … $$` or `\[ … \]`),
    /// advancing `i` past it. Returns the rendered `<div>` (raw TeX inside, for the
    /// bundled MathJax to typeset), `""` for an empty block, or `nil` when the line
    /// doesn't open display math — in which case `i` is left untouched so the caller
    /// can keep trying other block types. An unterminated block consumes to EOF
    /// rather than hanging.
    private static func parseDisplayMath(_ i: inout Int, lines: [String]) -> String? {
        let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
        let isDollar = trimmed.hasPrefix("$$")
        let isBracket = trimmed.hasPrefix("\\[")
        guard isDollar || isBracket else { return nil }
        let closeTok = isDollar ? "$$" : "\\]"

        let rest = String(trimmed.dropFirst(2))

        // Single-line form: opener and closer on the same line, e.g. `$$x^2$$`.
        if let r = rest.range(of: closeTok) {
            i += 1
            let tex = String(rest[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            return tex.isEmpty ? "" : "<div class=\"rd-math rd-math-display\">\(escapeHTML(tex))</div>"
        }

        // Multi-line form: only enter when the opener line is blank after the
        // delimiter — `$$x^2` (no closer on the same line) is prose, not math.
        // This prevents `$$5 million` or `\[RFC 1234]` from eating subsequent
        // lines as TeX content.
        guard rest.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var content: [String] = []
        i += 1
        while i < lines.count {
            if let r = lines[i].range(of: closeTok) {
                let before = String(lines[i][..<r.lowerBound])
                if !before.trimmingCharacters(in: .whitespaces).isEmpty { content.append(before) }
                i += 1
                break
            }
            content.append(lines[i])
            i += 1
        }
        let tex = content.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return tex.isEmpty ? "" : "<div class=\"rd-math rd-math-display\">\(escapeHTML(tex))</div>"
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        let stripped = trimmed.filter { !$0.isWhitespace }
        let unique = Set(stripped)
        return unique.count == 1 && stripped.count >= 3
            && unique.first.map { "-*_".contains($0) } == true
    }

    // MARK: - Table Helpers

    private static func parseTableRow(_ line: String) -> [String] {
        var row = line.trimmingCharacters(in: .whitespaces)
        if row.hasPrefix("|") { row = String(row.dropFirst()) }
        if row.hasSuffix("|") { row = String(row.dropLast()) }
        return row.components(separatedBy: "|")
    }

    // MARK: - Helpers

    static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// Escapes a URL for use in an `href`/`src` attribute and neutralizes chars that would
    /// otherwise match later inline regex passes (italic/bold/strike/code) and corrupt the
    /// attribute. Browsers decode the entities back to the original characters on navigation.
    private static func escapeURLForAttribute(_ url: String) -> String {
        escapeHTML(url)
            .replacingOccurrences(of: "_", with: "&#95;")
            .replacingOccurrences(of: "*", with: "&#42;")
            .replacingOccurrences(of: "~", with: "&#126;")
            .replacingOccurrences(of: "`", with: "&#96;")
    }

    private static func stripDangerousAttributes(_ tag: String) -> String {
        let range = NSRange(location: 0, length: (tag as NSString).length)
        return dangerousAttrPattern.stringByReplacingMatches(in: tag, range: range, withTemplate: "")
    }

    private static let htmlBlockTags: Set<String> = [
        "address", "article", "aside", "blockquote", "body", "center",
        "details", "dialog", "dd", "dir", "div", "dl", "dt", "fieldset",
        "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4",
        "h5", "h6", "header", "hgroup", "hr", "li", "main", "nav", "ol",
        "p", "pre", "section", "summary", "table", "tbody", "td", "tfoot",
        "th", "thead", "tr", "ul",
    ]

    private static func isHTMLBlockStart(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("<") else { return false }
        let rest = trimmed.dropFirst()
        let afterSlash = rest.hasPrefix("/") ? rest.dropFirst() : rest
        let tagName = String(afterSlash.prefix(while: { $0.isLetter || $0.isNumber })).lowercased()
        return htmlBlockTags.contains(tagName)
    }

    private static func isSafeURL(_ url: String) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        if trimmed.isEmpty || lowercased.hasPrefix("//") {
            return false
        }
        if lowercased.hasPrefix("#") || lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") || lowercased.hasPrefix("mailto:") {
            return true
        }

        if let components = URLComponents(string: trimmed),
           let scheme = components.scheme?.lowercased(),
           !scheme.isEmpty {
            if ["http", "https", "mailto"].contains(scheme) {
                return true
            }
            return false
        }

        if let colonIndex = trimmed.firstIndex(of: ":") {
            let beforeColon = trimmed[..<colonIndex]
            if beforeColon.count == 1 || beforeColon.allSatisfy({ $0.isLetter }) {
                return false
            }
        }

        return true
    }

    private static func sanitizedMarkdownURL(_ url: String) -> String {
        url
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    /// GitHub-style heading slug. Lowercase, strip punctuation (keep letters,
    /// digits, hyphens, underscores, and Unicode letters like accented chars),
    /// convert whitespace to hyphens, trim, and deduplicate against earlier
    /// headings in the same document.
    private static func uniqueSlug(for text: String, existing: inout [String: Int]) -> String {
        var slug = text.lowercased()
        // Drop inline HTML tags so e.g. `## <code>foo</code>` slugs to `foo`.
        slug = slug.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Keep letters (Unicode), digits, hyphens, underscores, and whitespace; drop the rest.
        slug = slug.replacingOccurrences(of: "[^\\p{L}\\p{N}\\-_\\s]", with: "", options: .regularExpression)
        // Each whitespace char becomes one hyphen — `\s+ -> -` would collapse
        // runs, but GitHub preserves them (e.g. `Foo — bar` strips the em dash
        // leaving two spaces, which become `foo--bar`, not `foo-bar`). TOCs
        // generated by GitHub-style tools depend on the preserved gap.
        slug = slug.replacingOccurrences(of: "\\s", with: "-", options: .regularExpression)
        // Trim leading/trailing hyphens.
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        // Fallback if the heading was entirely punctuation.
        if slug.isEmpty { slug = "section" }

        let count = existing[slug, default: 0]
        existing[slug] = count + 1
        return count == 0 ? slug : "\(slug)-\(count)"
    }
}

// MARK: - String Regex Helpers

private extension String {
    func matchesPattern(_ regex: NSRegularExpression) -> Bool {
        let range = NSRange(startIndex..., in: self)
        return regex.firstMatch(in: self, range: range) != nil
    }

    func removingMatch(of regex: NSRegularExpression) -> String {
        let range = NSRange(startIndex..., in: self)
        return regex.stringByReplacingMatches(in: self, range: range, withTemplate: "")
    }

    func replacing(_ regex: NSRegularExpression, using transform: ([String]) -> String) -> String {
        let nsRange = NSRange(startIndex..., in: self)
        let matches = regex.matches(in: self, range: nsRange)
        if matches.isEmpty { return self }

        // Build result forward, copying unmatched segments and transformed matches
        let ns = self as NSString
        var result = ""
        var lastEnd = 0
        for match in matches {
            let matchRange = match.range
            // Copy text before this match
            if matchRange.location > lastEnd {
                result += ns.substring(with: NSRange(location: lastEnd, length: matchRange.location - lastEnd))
            }
            // Extract groups from original string
            var groups: [String] = []
            for g in 0..<match.numberOfRanges {
                let gr = match.range(at: g)
                if gr.location != NSNotFound {
                    groups.append(ns.substring(with: gr))
                } else {
                    groups.append("")
                }
            }
            result += transform(groups)
            lastEnd = matchRange.location + matchRange.length
        }
        // Copy remaining text
        if lastEnd < ns.length {
            result += ns.substring(from: lastEnd)
        }
        return result
    }
}
