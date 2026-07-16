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
// Backslash escape: `\` + ASCII punctuation → literal (CommonMark §2.4). `$` excluded
// (escaped dollars are handled by the math pass).
private let backslashEscapePattern = try! NSRegularExpression(pattern: "\\\\([!-#%-/:-@\\[-`{-~])")
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
// that the bundled math renderer typesets in the WebView — so no later inline
// pass (escape, emphasis, link, …) can corrupt the source.
private let inlineMathDollarPattern = try! NSRegularExpression(pattern: "(?<![\\\\$])\\$(?!\\d)(?=\\S)([^\\n$]*?[^\\s$])\\$(?![0-9$])")
private let inlineMathParenPattern = try! NSRegularExpression(pattern: "\\\\\\((.+?)\\\\\\)")
private let htmlTagPattern = try! NSRegularExpression(pattern: "<!--[\\s\\S]*?-->|</?[a-zA-Z][a-zA-Z0-9]*(?:\\s+[^>]*)?\\/?>")
// Scans a tag's attributes as (name, value?) tokens; only allowlisted names survive,
// so any `on*` handler (with or without leading space) is dropped.
private let attrScanPattern = try! NSRegularExpression(pattern: "([a-zA-Z_:][-a-zA-Z0-9_:.]*)(?:\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s\"'`=<>]+))?")
private let htmlEntityPattern = try! NSRegularExpression(pattern: "&(?:[a-zA-Z][a-zA-Z0-9]{0,31}|#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6});")

/// HTML sanitization is an allowlist: `safeTags` pass (keeping only `safeAttributes`),
/// everything else is escaped to text. Fail-safe — unknowns are neutralized, not emitted.
private let safeTags: Set<String> = [
    "a", "abbr", "address", "article", "aside", "b", "bdi", "bdo", "blockquote",
    "br", "caption", "cite", "code", "col", "colgroup", "dd", "del", "details",
    "dfn", "div", "dl", "dt", "em", "figcaption", "figure", "footer", "h1", "h2",
    "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "i", "img", "ins", "kbd",
    "li", "main", "mark", "nav", "ol", "p", "pre", "q", "rp", "rt", "ruby", "s",
    "samp", "section", "small", "span", "strong", "sub", "summary", "sup",
    "table", "tbody", "td", "tfoot", "th", "thead", "time", "tr", "u", "ul",
    "var", "wbr",
]
private let safeAttributes: Set<String> = [
    "href", "src", "alt", "title", "class", "id", "name", "width", "height",
    "align", "valign", "colspan", "rowspan", "start", "reversed", "type",
    "datetime", "cite", "dir", "lang", "span", "scope",
]
/// Raw-text elements: their content is escaped wholesale so nested tags can't leak out.
private let rawTextTags: Set<String> = [
    "script", "style", "textarea", "title", "xmp", "noscript", "noembed",
    "iframe", "noframes",
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

            // Lists — ordered, unordered, and task lists all go through one
            // indented parser so nesting, mixed marker types, and loose items
            // behave uniformly.
            if line.matchesPattern(ulPattern) || line.matchesPattern(olPattern) {
                html.append(parseList(&i, lines: lines, baseIndent: listItemIndent(line), hasMermaid: &hasMermaid))
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
                // Sanitize the whole block as one string so raw-text opacity
                // (e.g. a multi-line `<script>…</script>`) is tracked across lines.
                html.append(escapeHTMLPreservingTags(blockLines.joined(separator: "\n")))
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
                    || isDisplayMathOpener(l) || isHTMLBlockStart(l) {
                    break
                }
                if l.contains("|") && i + 1 < lines.count
                    && lines[i + 1].matchesPattern(tableSepPattern) {
                    break
                }
                if isHorizontalRule(t) {
                    break
                }
                // Setext heading: this paragraph line is underlined by `===`
                // (h1) or `---` (h2). The underline converts only this one line,
                // so flush any earlier collected lines as their own paragraph
                // first. A `---` with no preceding text is an <hr> (handled by
                // the branch above), so reaching here means a real heading.
                if i + 1 < lines.count, let level = setextUnderline(lines[i + 1]) {
                    if !para.isEmpty {
                        html.append("<p>\(inlineMarkdown(para.joined(separator: "\n")))</p>")
                        para.removeAll()
                    }
                    let slug = uniqueSlug(for: t, existing: &headingSlugs)
                    html.append("<h\(level) id=\"\(slug)\">\(inlineMarkdown(t))</h\(level)>")
                    i += 2
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
        // Inside a raw-text element (script/style/…), escape everything up to its close tag.
        var rawText: String?
        for match in matches {
            let r = match.range
            let between = ns.substring(with: NSRange(location: lastEnd, length: r.location - lastEnd))
            result += rawText != nil ? escapeHTML(between) : escapeHTMLKeepingEntities(between)
            let tag = ns.substring(with: r)
            let (name, isClosing) = htmlTagName(tag)
            if let open = rawText {
                result += escapeHTML(tag)
                if isClosing && name == open { rawText = nil }
            } else {
                result += sanitizeHTMLTag(tag)
                if !isClosing && rawTextTags.contains(name) { rawText = name }
            }
            lastEnd = r.location + r.length
        }
        let tail = ns.substring(from: lastEnd)
        result += rawText != nil ? escapeHTML(tail) : escapeHTMLKeepingEntities(tail)
        return result
    }

    /// The lowercased tag name and whether it's a closing tag. `("", false)` for
    /// comments and anything that isn't a well-formed tag.
    private static func htmlTagName(_ tag: String) -> (name: String, isClosing: Bool) {
        var s = Substring(tag)
        guard s.first == "<" else { return ("", false) }
        s = s.dropFirst()
        let isClosing = s.first == "/"
        if isClosing { s = s.dropFirst() }
        return (String(s.prefix(while: { $0.isLetter || $0.isNumber })).lowercased(), isClosing)
    }

    /// Re-emits a safe tag keeping only allowlisted attributes; escapes any other tag.
    private static func sanitizeHTMLTag(_ tag: String) -> String {
        // Comments matched the full `<!-- … -->` pattern already; they're inert.
        if tag.hasPrefix("<!--") { return tag }
        var s = Substring(tag)
        guard s.first == "<" else { return escapeHTML(tag) }
        s = s.dropFirst()
        let isClosing = s.first == "/"
        if isClosing { s = s.dropFirst() }
        let name = String(s.prefix(while: { $0.isLetter || $0.isNumber })).lowercased()
        guard !name.isEmpty, safeTags.contains(name) else { return escapeHTML(tag) }
        if isClosing { return "</\(name)>" }

        // Opening / self-closing tag: keep only allowlisted attributes.
        let selfClosing = tag.hasSuffix("/>")
        var body = String(s.dropFirst(name.count))
        if body.hasSuffix(">") { body.removeLast() }
        if body.hasSuffix("/") { body.removeLast() }
        var out = "<" + name
        let bns = body as NSString
        for m in attrScanPattern.matches(in: body, range: NSRange(location: 0, length: bns.length)) {
            let attrName = bns.substring(with: m.range(at: 1)).lowercased()
            guard safeAttributes.contains(attrName) else { continue }
            // Drop href/src carrying a dangerous scheme (defense in depth; the
            // WebView also refuses the navigation on click).
            if (attrName == "href" || attrName == "src"), m.range(at: 2).location != NSNotFound {
                var value = bns.substring(with: m.range(at: 2))
                if value.count >= 2, let q = value.first, q == "\"" || q == "'", value.last == q {
                    value = String(value.dropFirst().dropLast())
                }
                if !isSafeURL(value) { continue }
            }
            out += " " + bns.substring(with: m.range)
        }
        return out + (selfClosing ? " />" : ">")
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

        // Backslash escapes: code/math already stashed, so `\<punct>` is now a literal
        // no later pass can treat as syntax. Restored, HTML-escaped, at the end.
        var escapedChars: [String] = []
        s = s.replacing(backslashEscapePattern) { match in
            escapedChars.append(match[1])
            return "\u{E005}\(escapedChars.count - 1)\u{E006}"
        }

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

        // Restore math spans (raw TeX wrapped for the math renderer) and the escaped-dollar
        // placeholder, then code spans — all after the delimiter-based passes.
        for (idx, span) in mathSpans.enumerated() {
            s = s.replacingOccurrences(of: "\u{E002}\(idx)\u{E003}", with: span)
        }
        s = s.replacingOccurrences(of: "\u{E004}", with: "$")

        // Restore code spans now that all delimiter-based passes are done.
        for (idx, span) in codeSpans.enumerated() {
            s = s.replacingOccurrences(of: "\u{E000}\(idx)\u{E001}", with: span)
        }

        // Restore backslash-escaped literals last, HTML-escaping so `\<` → &lt;.
        for (idx, ch) in escapedChars.enumerated() {
            s = s.replacingOccurrences(of: "\u{E005}\(idx)\u{E006}", with: escapeHTML(ch))
        }

        return s
    }

    // MARK: - List Helpers

    /// One block inside a list item: a prose paragraph (raw, pre-inline) or a
    /// finished HTML block (fenced code or a nested list).
    private enum ListPiece { case para(String); case block(String) }

    private static func listItemIndent(_ line: String) -> Int {
        line.prefix(while: { $0 == " " || $0 == "\t" }).reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }

    private static func nextNonBlank(after index: Int, in lines: [String]) -> Int? {
        var j = index
        while j < lines.count {
            if !lines[j].trimmingCharacters(in: .whitespaces).isEmpty { return j }
            j += 1
        }
        return nil
    }

    /// A line that, when it appears under-indented, ends a list item's lazy
    /// continuation: another marker, a heading, a blockquote, or a code fence.
    private static func endsItemContinuation(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return line.matchesPattern(ulPattern) || line.matchesPattern(olPattern)
            || line.matchesPattern(headingPattern) || line.hasPrefix(">")
            || t.hasPrefix("```") || t.hasPrefix("~~~")
    }

    private static func dropIndent(_ line: String, _ columns: Int) -> String {
        var s = Substring(line)
        var c = 0
        while c < columns, let f = s.first, f == " " || f == "\t" {
            s = s.dropFirst()
            c += (f == "\t" ? 4 : 1)
        }
        return String(s)
    }

    /// Unified ordered/unordered/task list parser, advancing `i`. Handles
    /// arbitrary nesting by indentation, mixed marker types (a `-` sublist under
    /// a `1.` item and vice versa), tight vs loose items, ordered `start`
    /// numbers (issue #16), and task checkboxes. Every path advances `i` or
    /// breaks, preserving the no-hang invariant (issue #8).
    private static func parseList(_ i: inout Int, lines: [String], baseIndent: Int, hasMermaid: inout Bool) -> String {
        let ordered = lines[i].matchesPattern(olPattern)
        var startNumber = 1
        var firstItem = true
        var items: [(pieces: [ListPiece], task: Int)] = []  // task: 0 none, 1 open, 2 done
        var loose = false
        var hasTask = false

        while i < lines.count {
            // A blank line only continues the list when a same-type sibling
            // follows at this indent; otherwise the list ends here.
            if lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                guard let peek = nextNonBlank(after: i, in: lines),
                      listItemIndent(lines[peek]) == baseIndent,
                      (ordered ? lines[peek].matchesPattern(olPattern)
                               : lines[peek].matchesPattern(ulPattern))
                else { break }
                loose = true
                i = peek
            }

            let line = lines[i]
            if listItemIndent(line) != baseIndent { break }
            guard ordered ? line.matchesPattern(olPattern) : line.matchesPattern(ulPattern) else { break }

            // Marker geometry: everything after the "-, *, +" or "N." plus one space.
            let afterLead = line.drop(while: { $0 == " " || $0 == "\t" })
            let markerBodyLen: Int
            if ordered {
                let digits = afterLead.prefix(while: { $0.isNumber })
                if firstItem { startNumber = Int(digits) ?? 1 }
                markerBodyLen = digits.count + 2   // "." + " "
            } else {
                markerBodyLen = 2                  // bullet + " "
            }
            firstItem = false
            let contentIndent = baseIndent + markerBodyLen
            var text = String(afterLead.dropFirst(markerBodyLen))
            i += 1

            // Task checkbox (unordered only) — split the marker off the label.
            var task = 0
            if !ordered {
                if text == "[ ]" || text.hasPrefix("[ ] ") { task = 1 }
                else if text == "[x]" || text == "[X]" || text.hasPrefix("[x] ") || text.hasPrefix("[X] ") { task = 2 }
                if task != 0 {
                    hasTask = true
                    text = text.count > 4 ? String(text.dropFirst(4)) : ""
                }
            }

            let pieces = collectItem(&i, lines: lines, baseIndent: baseIndent,
                                     contentIndent: contentIndent, firstText: text,
                                     loose: &loose, hasMermaid: &hasMermaid)
            items.append((pieces, task))
        }

        var body = ""
        for item in items {
            var inner = ""
            for piece in item.pieces {
                switch piece {
                case .para(let raw): inner += loose ? "<p>\(inlineMarkdown(raw))</p>" : inlineMarkdown(raw)
                case .block(let h): inner += h
                }
            }
            switch item.task {
            case 1: body += "<li class=\"task-item\"><input type=\"checkbox\" disabled> \(inner)</li>"
            case 2: body += "<li class=\"task-item\"><input type=\"checkbox\" checked disabled> \(inner)</li>"
            default: body += "<li>\(inner)</li>"
            }
        }

        if ordered {
            let startAttr = startNumber == 1 ? "" : " start=\"\(startNumber)\""
            return "<ol\(startAttr)>\(body)</ol>"
        }
        return "<ul\(hasTask ? " class=\"task-list\"" : "")>\(body)</ul>"
    }

    /// Collects one list item's blocks, advancing `i`. Prose runs are joined
    /// before inline processing so emphasis spans a soft wrap (issue #15).
    /// Indented content that still belongs to the item — nested lists, fenced
    /// code (issue #9), and continuation paragraphs — stays inside the item; a
    /// blank line before such content makes the list loose.
    private static func collectItem(_ i: inout Int, lines: [String], baseIndent: Int, contentIndent: Int,
                                    firstText: String, loose: inout Bool, hasMermaid: inout Bool) -> [ListPiece] {
        var pieces: [ListPiece] = []
        var prose: [String] = firstText.isEmpty ? [] : [firstText]
        func flush() {
            guard !prose.isEmpty else { return }
            pieces.append(.para(prose.joined(separator: " ")))
            prose.removeAll()
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                // Keep the item open only if the following content is indented
                // into it; a multi-block item makes the list loose.
                guard let peek = nextNonBlank(after: i, in: lines),
                      listItemIndent(lines[peek]) >= contentIndent else { break }
                loose = true
                flush()
                i = peek
                continue
            }

            let indent = listItemIndent(line)

            if indent >= contentIndent {
                // Fenced code block inside the item (issue #9).
                if trimmed.matchesPattern(fencePattern) {
                    flush()
                    let openerIndent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
                    pieces.append(.block(consumeFence(&i, lines: lines, openerIndent: openerIndent, hasMermaid: &hasMermaid)))
                    continue
                }
                // Nested list of either type — de-indent to test the marker.
                let deindented = dropIndent(line, contentIndent)
                if deindented.matchesPattern(ulPattern) || deindented.matchesPattern(olPattern) {
                    flush()
                    pieces.append(.block(parseList(&i, lines: lines, baseIndent: indent, hasMermaid: &hasMermaid)))
                    continue
                }
                prose.append(trimmed)
                i += 1
                continue
            }

            // Under-indented: a dedent, a sibling marker, or a new block ends the
            // item; a plain line is a lazy paragraph continuation.
            if indent < baseIndent { break }
            if endsItemContinuation(line) { break }
            prose.append(trimmed)
            i += 1
        }

        flush()
        return pieces
    }

    /// Consumes a fenced code block, advancing `i` past the closing fence (or to
    /// EOF if unclosed). Each content line is de-indented by up to `openerIndent`
    /// columns (CommonMark §6.7) so list-item indentation doesn't leak into the
    /// rendered code.
    private static func consumeFence(_ i: inout Int, lines: [String], openerIndent: Int, hasMermaid: inout Bool) -> String {
        let stripped = lines[i].drop(while: { $0 == " " || $0 == "\t" })
        let fenceChar: Character = stripped.first == "~" ? "~" : "`"
        let fenceLen = stripped.prefix(while: { $0 == fenceChar }).count
        let lang = String(stripped.dropFirst(fenceLen)).trimmingCharacters(in: .whitespaces)
        let isMermaid = lang.lowercased() == "mermaid"
        var code: [String] = []
        i += 1
        while i < lines.count {
            let l = lines[i]
            let closeTrimmed = l.drop(while: { $0 == " " || $0 == "\t" })
            let closeLen = closeTrimmed.prefix(while: { $0 == fenceChar }).count
            if closeLen >= fenceLen && closeTrimmed.dropFirst(closeLen).allSatisfy({ $0.isWhitespace }) {
                i += 1
                break
            }
            let content = dropIndent(l, openerIndent)
            code.append(isMermaid ? content : escapeHTML(content))
            i += 1
        }
        if isMermaid {
            hasMermaid = true
            return "<pre class=\"mermaid\">\(code.joined(separator: "\n"))</pre>"
        }
        let langAttr = lang.isEmpty ? "" : " class=\"language-\(escapeHTML(lang))\""
        return "<pre><code\(langAttr)>\(code.joined(separator: "\n"))</code></pre>"
    }

    // MARK: - Block Helpers

    /// Parses a display-math block opening at `lines[i]` (`$$ … $$` or `\[ … \]`),
    /// advancing `i` past it. Returns the rendered `<div>` (raw TeX inside, for the
    /// bundled math renderer to typeset), `""` for an empty block, or `nil` when the line
    /// doesn't open display math — in which case `i` is left untouched so the caller
    /// can keep trying other block types. An unterminated block consumes to EOF
    /// rather than hanging.
    /// True when `line` opens a display-math block that `parseDisplayMath` would
    /// claim — either single-line (`$$x^2$$` / `\[x^2\]`) or a bare opener
    /// (`$$` / `\[` alone). Used so the paragraph collector releases a math line
    /// that follows prose with no blank line between them. Mirrors the opener
    /// tests in `parseDisplayMath`, so `$$5 million` / `\[RFC 1234]` stay prose.
    private static func isDisplayMathOpener(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let closeTok: String
        if trimmed.hasPrefix("$$") { closeTok = "$$" }
        else if trimmed.hasPrefix("\\[") { closeTok = "\\]" }
        else { return false }
        let rest = String(trimmed.dropFirst(2))
        if rest.range(of: closeTok) != nil { return true }          // single-line
        return rest.trimmingCharacters(in: .whitespaces).isEmpty     // bare opener
    }

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

    /// Setext underline level: 1 for a line of only `=`, 2 for a line of only
    /// `-`, `nil` otherwise. The caller applies it to the immediately-preceding
    /// paragraph line. Precedence with `<hr>` is resolved by the caller: a bare
    /// `-` run only reaches here when it follows a paragraph line.
    private static func setextUnderline(_ line: String) -> Int? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if t.allSatisfy({ $0 == "=" }) { return 1 }
        if t.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
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
