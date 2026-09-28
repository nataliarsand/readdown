import Foundation

// MARK: - Pre-compiled Regex Patterns

private let fencePattern = try! NSRegularExpression(pattern: "^\\s{0,3}(`{3,}|~{3,})")
private let headingPattern = try! NSRegularExpression(pattern: "^\\s{0,3}#{1,6}(?:\\s+|$)")
private let ulPattern = try! NSRegularExpression(pattern: "^\\s*[-*+] ")
private let olPattern = try! NSRegularExpression(pattern: "^\\s*\\d+\\. ")
private let tableSepPattern = try! NSRegularExpression(pattern: "^\\s*\\|?[\\s:]*-+[\\s:]*\\|")

private let imagePattern = try! NSRegularExpression(pattern: "!\\[([^\\]]*)\\]\\(([^()]+(?:\\([^()]*\\)[^()]*)*)\\)")
private let linkPattern = try! NSRegularExpression(pattern: "\\[([^\\]]*)\\]\\(([^()]+(?:\\([^()]*\\)[^()]*)*)\\)")
private let autolinkURLPattern = try! NSRegularExpression(pattern: "<([A-Za-z][A-Za-z0-9+.\\-]{1,31}:[^\\s<>]*)>")
private let autolinkEmailPattern = try! NSRegularExpression(pattern: "<([a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,})>")
private let codePattern = try! NSRegularExpression(pattern: "`([^`]+)`")
// `$` is excluded: escaped dollars belong to the math pass.
private let backslashEscapePattern = try! NSRegularExpression(pattern: "\\\\([!-#%-/:-@\\[-`{-~])")
private let boldItalicStarPattern = try! NSRegularExpression(pattern: "\\*\\*\\*(.+?)\\*\\*\\*", options: .dotMatchesLineSeparators)
private let boldStarPattern = try! NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*", options: .dotMatchesLineSeparators)
private let italicStarPattern = try! NSRegularExpression(pattern: "\\*(.+?)\\*", options: .dotMatchesLineSeparators)
// Underscore emphasis needs word-boundary flanking (CommonMark §6.2) so `snake_case` stays literal; `*` may flank inside words.
private let boldItalicUnderPattern = try! NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_])___(.+?)___(?![\\p{L}\\p{N}_])", options: .dotMatchesLineSeparators)
private let boldUnderPattern = try! NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_])__(.+?)__(?![\\p{L}\\p{N}_])", options: .dotMatchesLineSeparators)
private let italicUnderPattern = try! NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_])_(.+?)_(?![\\p{L}\\p{N}_])", options: .dotMatchesLineSeparators)
private let strikePattern = try! NSRegularExpression(pattern: "~~(.+?)~~", options: .dotMatchesLineSeparators)
// `$…$` needs non-space flanking and no digit after the closer, so "$5 and $7" stays prose.
private let inlineMathDollarPattern = try! NSRegularExpression(pattern: "(?<![\\\\$])\\$(?!\\d)(?=\\S)([^\\n$]*?[^\\s$])\\$(?![0-9$])")
private let inlineMathParenPattern = try! NSRegularExpression(pattern: "\\\\\\((.+?)\\\\\\)")
private let htmlTagPattern = try! NSRegularExpression(pattern: "<!--[\\s\\S]*?-->|</?[a-zA-Z][a-zA-Z0-9]*(?:\\s+[^>]*)?\\/?>")
// Only allowlisted attribute names survive the scan, so any `on*` handler is dropped.
private let attrScanPattern = try! NSRegularExpression(pattern: "([a-zA-Z_:][-a-zA-Z0-9_:.]*)(?:\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s\"'`=<>]+))?")
private let htmlEntityPattern = try! NSRegularExpression(pattern: "&(?:[a-zA-Z][a-zA-Z0-9]{0,31}|#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6});")

private let refDefPattern = try! NSRegularExpression(pattern: "^\\s{0,3}\\[([^\\]]+)\\]:\\s*(\\S+)(?:\\s+(?:\"([^\"]*)\"|'([^']*)'|\\(([^)]*)\\)))?\\s*$")
private let fullRefPattern = try! NSRegularExpression(pattern: "(?<!!)\\[([^\\]]*)\\]\\[([^\\]]*)\\]")
private let shortcutRefPattern = try! NSRegularExpression(pattern: "(?<![!\\]])\\[([^\\]]+)\\](?![\\[(])")
private let fullRefImagePattern = try! NSRegularExpression(pattern: "!\\[([^\\]]*)\\]\\[([^\\]]*)\\]")
private let shortcutRefImagePattern = try! NSRegularExpression(pattern: "!\\[([^\\]]+)\\](?![\\[(])")
// Deliberately greedy; trailing punctuation is trimmed in code.
private let bareURLPattern = try! NSRegularExpression(pattern: "https?://[^\\s<>]+")

private let slugTagPattern = try! NSRegularExpression(pattern: "<[^>]+>")
private let slugStripPattern = try! NSRegularExpression(pattern: "[^\\p{L}\\p{N}\\-_\\s]")
private let slugSpacePattern = try! NSRegularExpression(pattern: "\\s")

/// Reference-link definitions, keyed by lowercased label.
private typealias RefDefs = [String: (url: String, title: String?)]

/// Allowlist: any tag or attribute not listed is escaped to text, never emitted.
private let safeTags: Set<String> = [
    "a", "abbr", "address", "article", "aside", "b", "bdi", "bdo", "blockquote",
    "br", "caption", "center", "cite", "code", "col", "colgroup", "dd", "del",
    "details", "dfn", "div", "dl", "dt", "em", "figcaption", "figure", "footer", "h1", "h2",
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
        var lines = markdown.components(separatedBy: "\n")
        var html: [String] = []
        // Peeled off before reference harvesting so nothing inside it is read as a definition.
        if let end = frontMatterEnd(lines) {
            let yaml = lines[1..<end].map(escapeHTML).joined(separator: "\n")
            html.append("<pre><code class=\"language-yaml\">\(yaml)</code></pre>")
            lines.removeFirst(end + 1)
        }
        let refs = collectReferenceDefinitions(&lines)
        var hasMermaid = false
        var i = 0
        var headingSlugs: [String: Int] = [:]

        while i < lines.count {
            let line = lines[i]
            // Every branch below must advance `i`; the guard at the bottom catches one that doesn't.
            let iAtStart = i

            if line.matchesPattern(fencePattern) {
                let openerIndent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
                html.append(consumeFence(&i, lines: lines, openerIndent: openerIndent, hasMermaid: &hasMermaid))
                continue
            }

            // After fenced code, so a `$$` inside a code block stays literal.
            if let mathHTML = parseDisplayMath(&i, lines: lines) {
                if !mathHTML.isEmpty { html.append(mathHTML) }
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isHorizontalRule(trimmed) {
                html.append("<hr>")
                i += 1
                continue
            }

            if line.matchesPattern(headingPattern) {
                let trimmedLine = String(line.drop(while: { $0 == " " || $0 == "\t" }))
                let level = min(trimmedLine.prefix(while: { $0 == "#" }).count, 6)
                let text = String(trimmedLine.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                let slug = uniqueSlug(for: text, existing: &headingSlugs)
                html.append("<h\(level) id=\"\(slug)\">\(inlineMarkdown(text, refs: refs))</h\(level)>")
                i += 1
                continue
            }

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
                    tableHTML += "<th align=\"\(align)\">\(inlineMarkdown(cell.trimmingCharacters(in: .whitespaces), refs: refs))</th>"
                }
                tableHTML += "</tr></thead><tbody>"

                while i < lines.count && lines[i].contains("|")
                    && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    let cells = parseTableRow(lines[i])
                    tableHTML += "<tr>"
                    for ci in 0..<headerCells.count {
                        let align = ci < alignments.count ? alignments[ci] : "left"
                        let content = ci < cells.count ? cells[ci].trimmingCharacters(in: .whitespaces) : ""
                        tableHTML += "<td align=\"\(align)\">\(inlineMarkdown(content, refs: refs))</td>"
                    }
                    tableHTML += "</tr>"
                    i += 1
                }
                tableHTML += "</tbody></table>"
                html.append(tableHTML)
                continue
            }

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

            if line.matchesPattern(ulPattern) || line.matchesPattern(olPattern) {
                html.append(parseList(&i, lines: lines, baseIndent: listItemIndent(line), hasMermaid: &hasMermaid, refs: refs))
                continue
            }

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
                // One string, so a multi-line `<script>…</script>` is tracked across lines.
                html.append(escapeHTMLPreservingTags(blockLines.joined(separator: "\n")))
                continue
            }

            // Every stop test must mirror the main loop's: a looser one (bare `hasPrefix`) leaves a line unclaimed and `i` stuck (issue #8).
            var para: [String] = []
            while i < lines.count {
                let l = lines[i]
                let t = l.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || l.matchesPattern(headingPattern) || l.hasPrefix(">")
                    || l.matchesPattern(fencePattern)
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
                // A setext underline converts only this line; earlier lines flush as their own paragraph.
                if i + 1 < lines.count, let level = setextUnderline(lines[i + 1]) {
                    if !para.isEmpty {
                        html.append("<p>\(inlineMarkdown(para.joined(separator: "\n"), refs: refs))</p>")
                        para.removeAll()
                    }
                    let slug = uniqueSlug(for: t, existing: &headingSlugs)
                    html.append("<h\(level) id=\"\(slug)\">\(inlineMarkdown(t, refs: refs))</h\(level)>")
                    i += 2
                    break
                }
                para.append(l)
                i += 1
            }
            if !para.isEmpty {
                html.append("<p>\(inlineMarkdown(para.joined(separator: "\n"), refs: refs))</p>")
            }

            // No branch may leave `i` unmoved; a stuck line hangs the app (issue #8).
            if i == iAtStart {
                i += 1
            }
        }

        let joined = html.joined(separator: "\n")
        // Inline math is stashed inside `inlineMarkdown` and blockquote math comes through the recursive render; scanning the HTML catches both.
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

    /// `("", false)` for comments and anything that isn't a well-formed tag.
    private static func htmlTagName(_ tag: String) -> (name: String, isClosing: Bool) {
        var s = Substring(tag)
        guard s.first == "<" else { return ("", false) }
        s = s.dropFirst()
        let isClosing = s.first == "/"
        if isClosing { s = s.dropFirst() }
        return (String(s.prefix(while: { $0.isLetter || $0.isNumber })).lowercased(), isClosing)
    }

    /// Escapes, rather than drops, any tag outside the allowlist.
    private static func sanitizeHTMLTag(_ tag: String) -> String {
        // Comments are inert.
        if tag.hasPrefix("<!--") { return tag }
        var s = Substring(tag)
        guard s.first == "<" else { return escapeHTML(tag) }
        s = s.dropFirst()
        let isClosing = s.first == "/"
        if isClosing { s = s.dropFirst() }
        let name = String(s.prefix(while: { $0.isLetter || $0.isNumber })).lowercased()
        guard !name.isEmpty, safeTags.contains(name) else { return escapeHTML(tag) }
        if isClosing { return "</\(name)>" }

        let selfClosing = tag.hasSuffix("/>")
        var body = String(s.dropFirst(name.count))
        if body.hasSuffix(">") { body.removeLast() }
        if body.hasSuffix("/") { body.removeLast() }
        var out = "<" + name
        let bns = body as NSString
        for m in attrScanPattern.matches(in: body, range: NSRange(location: 0, length: bns.length)) {
            let attrName = bns.substring(with: m.range(at: 1)).lowercased()
            guard safeAttributes.contains(attrName) else { continue }
            // Defense in depth: the WebView also refuses these schemes on click.
            if (attrName == "href" || attrName == "src"), m.range(at: 2).location != NSNotFound {
                var value = bns.substring(with: m.range(at: 2))
                if value.count >= 2, let q = value.first, q == "\"" || q == "'", value.last == q {
                    value = String(value.dropFirst().dropLast())
                }
                // Re-emitted verbatim, so `javascript&colon;…` must be decoded before the check.
                let decoded = decodeEntitiesForURLCheck(value)
                let allowed = attrName == "src" ? isSafeImageSource(decoded) : isSafeURL(decoded)
                if !allowed { continue }
            }
            out += " " + bns.substring(with: m.range)
        }
        return out + (selfClosing ? " />" : ">")
    }

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

    private static func inlineMarkdown(_ text: String, refs: RefDefs = [:]) -> String {
        // Code spans come out first so no later pass reaches inside them; the Private Use delimiters carry no markdown meaning.
        var codeSpans: [String] = []
        var s = text.replacing(codePattern) { match in
            codeSpans.append("<code>\(escapeHTML(match[1]))</code>")
            return "\u{E000}\(codeSpans.count - 1)\u{E001}"
        }

        // `\$` is parked first so an escaped dollar can never open a math span.
        s = s.replacingOccurrences(of: "\\$", with: "\u{E004}")
        var mathSpans: [String] = []
        func stashMath(_ tex: String) -> String {
            mathSpans.append("<span class=\"rd-math rd-math-inline\">\(escapeHTML(tex))</span>")
            return "\u{E002}\(mathSpans.count - 1)\u{E003}"
        }
        s = s.replacing(inlineMathParenPattern) { stashMath($0[1]) }
        s = s.replacing(inlineMathDollarPattern) { stashMath($0[1]) }

        var escapedChars: [String] = []
        s = s.replacing(backslashEscapePattern) { match in
            escapedChars.append(match[1])
            return "\u{E005}\(escapedChars.count - 1)\u{E006}"
        }

        s = s.replacing(autolinkURLPattern) { match in
            let url = match[1]
            guard isSafeURL(url) else { return match[0] }
            return "<a href=\"\(escapeURLForAttribute(url))\">\(escapeURLForAttribute(url))</a>"
        }
        s = s.replacing(autolinkEmailPattern) { match in
            let email = match[1]
            return "<a href=\"mailto:\(escapeURLForAttribute(email))\">\(escapeURLForAttribute(email))</a>"
        }

        // Alt/title are escaped here: `escapeHTMLPreservingTags` re-emits attribute values verbatim.
        s = s.replacing(imagePattern) { match in
            let (rawURL, title) = splitLinkDestination(match[2])
            let url = sanitizedMarkdownURL(rawURL)
            guard isSafeImageSource(url) else { return match[0] }
            let titleAttr = title.map { " title=\"\(escapeHTML($0))\"" } ?? ""
            return "<img src=\"\(escapeURLForAttribute(url))\" alt=\"\(escapeHTML(match[1]))\"\(titleAttr)>"
        }

        // Link text stays raw so the later passes can still escape and emphasise it.
        s = s.replacing(linkPattern) { match in
            let (rawURL, title) = splitLinkDestination(match[2])
            let url = sanitizedMarkdownURL(rawURL)
            guard isSafeURL(url) else { return "\(match[1])" }
            let titleAttr = title.map { " title=\"\(escapeHTML($0))\"" } ?? ""
            return "<a href=\"\(escapeURLForAttribute(url))\"\(titleAttr)>\(match[1])</a>"
        }

        if !refs.isEmpty {
            s = s.replacing(fullRefImagePattern) { match in
                let label = match[2].isEmpty ? match[1] : match[2]
                return referenceImage(alt: match[1], label: label, refs: refs) ?? match[0]
            }
            s = s.replacing(shortcutRefImagePattern) { match in
                referenceImage(alt: match[1], label: match[1], refs: refs) ?? match[0]
            }
            s = s.replacing(fullRefPattern) { match in
                let label = match[2].isEmpty ? match[1] : match[2]
                return referenceAnchor(text: match[1], label: label, refs: refs) ?? match[0]
            }
            s = s.replacing(shortcutRefPattern) { match in
                referenceAnchor(text: match[1], label: match[1], refs: refs) ?? match[0]
            }
        }

        s = autolinkBareURLs(s)

        s = escapeHTMLPreservingTags(s)

        s = s.replacing(boldItalicStarPattern) { match in
            "<strong><em>\(match[1])</em></strong>"
        }
        s = s.replacing(boldItalicUnderPattern) { match in
            "<strong><em>\(match[1])</em></strong>"
        }

        s = s.replacing(boldStarPattern) { match in
            "<strong>\(match[1])</strong>"
        }
        s = s.replacing(boldUnderPattern) { match in
            "<strong>\(match[1])</strong>"
        }

        s = s.replacing(italicStarPattern) { match in
            "<em>\(match[1])</em>"
        }
        s = s.replacing(italicUnderPattern) { match in
            "<em>\(match[1])</em>"
        }

        s = s.replacing(strikePattern) { match in
            "<del>\(match[1])</del>"
        }

        s = s.replacingOccurrences(of: "  \n", with: "<br>")
        s = s.replacingOccurrences(of: "\n", with: " ")

        // Restores must follow every delimiter-based pass.
        for (idx, span) in mathSpans.enumerated() {
            s = s.replacingOccurrences(of: "\u{E002}\(idx)\u{E003}", with: span)
        }
        s = s.replacingOccurrences(of: "\u{E004}", with: "$")

        for (idx, span) in codeSpans.enumerated() {
            s = s.replacingOccurrences(of: "\u{E000}\(idx)\u{E001}", with: span)
        }

        for (idx, ch) in escapedChars.enumerated() {
            s = s.replacingOccurrences(of: "\u{E005}\(idx)\u{E006}", with: escapeHTML(ch))
        }

        return s
    }

    // MARK: - Reference Links & Autolinking

    /// Blanks each definition line in place; labels are case-insensitive and the first definition wins.
    private static func collectReferenceDefinitions(_ lines: inout [String]) -> RefDefs {
        var refs: RefDefs = [:]
        var inFence = false
        var fenceChar: Character = "`"
        var fenceLen = 0
        for idx in lines.indices {
            let line = lines[idx]
            let stripped = line.drop(while: { $0 == " " || $0 == "\t" })
            if inFence {
                let closeLen = stripped.prefix(while: { $0 == fenceChar }).count
                if closeLen >= fenceLen && stripped.dropFirst(closeLen).allSatisfy({ $0.isWhitespace }) {
                    inFence = false
                }
                continue
            }
            if line.matchesPattern(fencePattern) {
                fenceChar = stripped.first == "~" ? "~" : "`"
                fenceLen = stripped.prefix(while: { $0 == fenceChar }).count
                inFence = true
                continue
            }
            if let def = parseRefDef(line) {
                let key = def.label.lowercased()
                if refs[key] == nil { refs[key] = (def.url, def.title) }
                lines[idx] = ""
            }
        }
        return refs
    }

    private static func parseRefDef(_ line: String) -> (label: String, url: String, title: String?)? {
        let ns = line as NSString
        guard let m = refDefPattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        let label = ns.substring(with: m.range(at: 1))
        let url = ns.substring(with: m.range(at: 2))
        var title: String?
        for g in [3, 4, 5] where m.range(at: g).location != NSNotFound {
            title = ns.substring(with: m.range(at: g))
            break
        }
        return (label, url, title)
    }

    /// `nil` when the label is undefined or the URL unsafe; the caller keeps the literal text.
    private static func referenceAnchor(text: String, label: String, refs: RefDefs) -> String? {
        guard let def = refs[label.lowercased()] else { return nil }
        let url = sanitizedMarkdownURL(def.url)
        guard isSafeURL(url) else { return nil }
        let titleAttr = def.title.map { " title=\"\(escapeHTML($0))\"" } ?? ""
        return "<a href=\"\(escapeURLForAttribute(url))\"\(titleAttr)>\(text)</a>"
    }

    private static func referenceImage(alt: String, label: String, refs: RefDefs) -> String? {
        guard let def = refs[label.lowercased()] else { return nil }
        let url = sanitizedMarkdownURL(def.url)
        guard isSafeImageSource(url) else { return nil }
        let titleAttr = def.title.map { " title=\"\(escapeHTML($0))\"" } ?? ""
        return "<img src=\"\(escapeURLForAttribute(url))\" alt=\"\(escapeHTML(alt))\"\(titleAttr)>"
    }

    /// A title delimiter must follow whitespace, so a URL like `Foo_(bar)` keeps its parens.
    private static func splitLinkDestination(_ dest: String) -> (url: String, title: String?) {
        let trimmed = dest.trimmingCharacters(in: .whitespaces)
        guard let closer = trimmed.last else { return (trimmed, nil) }
        let opener: Character
        switch closer {
        case "\"": opener = "\""
        case "'": opener = "'"
        case ")": opener = "("
        default: return (trimmed, nil)
        }
        let body = trimmed.dropLast()
        guard let openIdx = body.lastIndex(of: opener), openIdx > body.startIndex,
              body[body.index(before: openIdx)].isWhitespace else {
            return (trimmed, nil)
        }
        let title = String(body[body.index(after: openIdx)...])
        let url = String(body[..<openIdx]).trimmingCharacters(in: .whitespaces)
        return (url, title)
    }

    /// Skips tag interiors and the text of an open `<a>`, so an existing link is never re-linked.
    private static func autolinkBareURLs(_ text: String) -> String {
        let ns = text as NSString
        let matches = htmlTagPattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return linkifyBareURLs(text) }
        var result = ""
        var lastEnd = 0
        var anchorDepth = 0
        for m in matches {
            let r = m.range
            let between = ns.substring(with: NSRange(location: lastEnd, length: r.location - lastEnd))
            result += anchorDepth > 0 ? between : linkifyBareURLs(between)
            let tag = ns.substring(with: r)
            result += tag
            let (name, isClosing) = htmlTagName(tag)
            if name == "a" {
                if isClosing { anchorDepth = max(0, anchorDepth - 1) }
                else if !tag.hasSuffix("/>") { anchorDepth += 1 }
            }
            lastEnd = r.location + r.length
        }
        let tail = ns.substring(from: lastEnd)
        result += anchorDepth > 0 ? tail : linkifyBareURLs(tail)
        return result
    }

    private static func linkifyBareURLs(_ text: String) -> String {
        text.replacing(bareURLPattern) { match in
            var url = Substring(match[0])
            var trailing = ""
            loop: while let last = url.last {
                switch last {
                case "?", "!", ".", ",", ":", ";", "*", "_", "~", "'", "\"":
                    trailing = String(last) + trailing
                    url = url.dropLast()
                case ")":
                    // Only an unbalanced `)` is trimmed, so `…/Foo_(bar)` keeps its paren.
                    guard url.filter({ $0 == ")" }).count > url.filter({ $0 == "(" }).count else { break loop }
                    trailing = String(last) + trailing
                    url = url.dropLast()
                default:
                    break loop
                }
            }
            let u = String(url)
            guard !u.isEmpty, isSafeURL(u) else { return match[0] }
            let safe = escapeURLForAttribute(u)
            return "<a href=\"\(safe)\">\(safe)</a>\(trailing)"
        }
    }

    // MARK: - List Helpers

    /// `.para` is raw markdown, `.block` finished HTML.
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

    private static func endsItemContinuation(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return line.matchesPattern(ulPattern) || line.matchesPattern(olPattern)
            || line.matchesPattern(headingPattern) || line.hasPrefix(">")
            || t.hasPrefix("```") || t.hasPrefix("~~~")
            || isHorizontalRule(t)
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

    /// Every path advances `i` or breaks; a stuck index hangs the app.
    private static func parseList(_ i: inout Int, lines: [String], baseIndent: Int, hasMermaid: inout Bool, refs: RefDefs = [:]) -> String {
        let ordered = lines[i].matchesPattern(olPattern)
        var startNumber = 1
        var firstItem = true
        var items: [(pieces: [ListPiece], task: Int)] = []  // task: 0 none, 1 open, 2 done
        var loose = false
        var hasTask = false

        while i < lines.count {
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
                                     loose: &loose, hasMermaid: &hasMermaid, refs: refs)
            items.append((pieces, task))
        }

        var body = ""
        for item in items {
            var inner = ""
            for piece in item.pieces {
                switch piece {
                case .para(let raw): inner += loose ? "<p>\(inlineMarkdown(raw, refs: refs))</p>" : inlineMarkdown(raw, refs: refs)
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

    /// Prose runs are joined before inline processing so emphasis can span a soft wrap.
    private static func collectItem(_ i: inout Int, lines: [String], baseIndent: Int, contentIndent: Int,
                                    firstText: String, loose: inout Bool, hasMermaid: inout Bool,
                                    refs: RefDefs = [:]) -> [ListPiece] {
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
                guard let peek = nextNonBlank(after: i, in: lines),
                      listItemIndent(lines[peek]) >= contentIndent else { break }
                loose = true
                flush()
                i = peek
                continue
            }

            let indent = listItemIndent(line)

            if indent >= contentIndent {
                if trimmed.matchesPattern(fencePattern) {
                    flush()
                    let openerIndent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
                    pieces.append(.block(consumeFence(&i, lines: lines, openerIndent: openerIndent, hasMermaid: &hasMermaid)))
                    continue
                }
                let deindented = dropIndent(line, contentIndent)
                if deindented.matchesPattern(ulPattern) || deindented.matchesPattern(olPattern) {
                    flush()
                    pieces.append(.block(parseList(&i, lines: lines, baseIndent: indent, hasMermaid: &hasMermaid, refs: refs)))
                    continue
                }
                prose.append(trimmed)
                i += 1
                continue
            }

            if indent < baseIndent { break }
            if endsItemContinuation(line) { break }
            prose.append(trimmed)
            i += 1
        }

        flush()
        return pieces
    }

    /// `nil` for an unclosed or empty block, which the normal parser then treats as a rule.
    private static func frontMatterEnd(_ lines: [String]) -> Int? {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        for k in 1..<lines.count {
            let t = lines[k].trimmingCharacters(in: .whitespaces)
            if t == "---" || t == "..." { return k > 1 ? k : nil }
        }
        return nil
    }

    /// An unclosed fence consumes to EOF; content is de-indented by up to `openerIndent` so list indentation doesn't leak into the code.
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

    /// Must mirror the opener tests in `parseDisplayMath`, so the paragraph collector releases exactly the lines it will claim.
    private static func isDisplayMathOpener(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let closeTok: String
        if trimmed.hasPrefix("$$") { closeTok = "$$" }
        else if trimmed.hasPrefix("\\[") { closeTok = "\\]" }
        else { return false }
        let rest = String(trimmed.dropFirst(2))
        if rest.range(of: closeTok) != nil { return true }
        return rest.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// `""` for an empty block; `nil` with `i` untouched when the line doesn't open display math. An unterminated block consumes to EOF.
    private static func parseDisplayMath(_ i: inout Int, lines: [String]) -> String? {
        let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
        let isDollar = trimmed.hasPrefix("$$")
        let isBracket = trimmed.hasPrefix("\\[")
        guard isDollar || isBracket else { return nil }
        let closeTok = isDollar ? "$$" : "\\]"

        let rest = String(trimmed.dropFirst(2))

        if let r = rest.range(of: closeTok) {
            i += 1
            let tex = String(rest[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            return tex.isEmpty ? "" : "<div class=\"rd-math rd-math-display\">\(escapeHTML(tex))</div>"
        }

        // An opener with trailing text and no closer is prose, so `$$5 million` can't eat the following lines as TeX.
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

    /// Precondition: the caller has already ruled out `<hr>`, so a bare `-` run here follows a paragraph line.
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

    /// `_ * ~ \`` are entity-encoded so later emphasis/code passes can't corrupt the attribute; browsers decode them back.
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

    /// Named references resolving to characters that affect scheme parsing.
    private static let namedEntitiesForURLCheck: [String: Character] = [
        "amp": "&", "AMP": "&", "lt": "<", "LT": "<", "gt": ">", "GT": ">",
        "quot": "\"", "QUOT": "\"", "apos": "'", "colon": ":", "semi": ";",
        "sol": "/", "bsol": "\\", "num": "#", "Tab": "\t", "NewLine": "\n",
    ]

    /// Mirrors browser decoding: numeric references resolve with or without the trailing `;`, unknown ones stay literal.
    private static func decodeEntitiesForURLCheck(_ value: String) -> String {
        guard value.contains("&") else { return value }
        var result = ""
        var s = Substring(value)
        while let amp = s.firstIndex(of: "&") {
            result += s[..<amp]
            var rest = s[s.index(after: amp)...]
            if rest.first == "#" {
                rest = rest.dropFirst()
                let isHex = rest.first == "x" || rest.first == "X"
                if isHex { rest = rest.dropFirst() }
                let digits = rest.prefix(while: { $0.isASCII && (isHex ? $0.isHexDigit : $0.isNumber) })
                if !digits.isEmpty, digits.count <= 7,
                   let code = UInt32(digits, radix: isHex ? 16 : 10),
                   let scalar = Unicode.Scalar(code) {
                    result.append(Character(scalar))
                    rest = rest.dropFirst(digits.count)
                    if rest.first == ";" { rest = rest.dropFirst() }
                    s = rest
                    continue
                }
            } else {
                let name = rest.prefix(while: { $0.isLetter || $0.isNumber })
                if !name.isEmpty, rest.dropFirst(name.count).first == ";",
                   let ch = namedEntitiesForURLCheck[String(name)] {
                    result.append(ch)
                    s = rest.dropFirst(name.count + 1)
                    continue
                }
            }
            result.append("&")
            s = s[s.index(after: amp)...]
        }
        result += s
        return result
    }

    private static func isSafeURL(_ url: String) -> Bool {
        // Browsers strip tab/newline/CR before parsing, so `jav\tascript:` navigates as `javascript:`.
        var trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(where: { $0 == "\t" || $0 == "\n" || $0 == "\r" }) {
            trimmed.removeAll(where: { $0 == "\t" || $0 == "\n" || $0 == "\r" })
        }
        if trimmed.isEmpty || trimmed.hasPrefix("//") {
            return false
        }
        switch LinkScheme.kind(of: trimmed) {
        case .denied:
            return false
        case .web, .custom:
            return true
        case .relative:
            // `C:\…` is a drive letter, never a relative path.
            if let colonIndex = trimmed.firstIndex(of: ":"), trimmed[..<colonIndex].count == 1 {
                return false
            }
            return true
        }
    }

    /// `data:image/…` is safe only as an `<img>` source (rendered statically, CSP allows `img-src data:`); a `data:` href stays blocked.
    private static func isSafeImageSource(_ url: String) -> Bool {
        // Prefix test first: data URIs can run to megabytes of base64.
        if url.drop(while: \.isWhitespace).prefix(11).lowercased() == "data:image/" {
            return true
        }
        return isSafeURL(url)
    }

    private static func sanitizedMarkdownURL(_ url: String) -> String {
        url
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private static func uniqueSlug(for text: String, existing: inout [String: Int]) -> String {
        var slug = text.lowercased()
        slug = slug.replacingMatches(of: slugTagPattern, with: "")
        slug = slug.replacingMatches(of: slugStripPattern, with: "")
        // One hyphen per whitespace char, not per run: GitHub keeps the gap (`Foo — bar` becomes `foo--bar`) and TOC tools depend on it.
        slug = slug.replacingMatches(of: slugSpacePattern, with: "-")
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
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

    func replacingMatches(of regex: NSRegularExpression, with template: String) -> String {
        regex.stringByReplacingMatches(in: self, range: NSRange(startIndex..., in: self), withTemplate: template)
    }

    func replacing(_ regex: NSRegularExpression, using transform: ([String]) -> String) -> String {
        let nsRange = NSRange(startIndex..., in: self)
        let matches = regex.matches(in: self, range: nsRange)
        if matches.isEmpty { return self }

        // Single forward pass: ranges from the original go stale once the string is mutated.
        let ns = self as NSString
        var result = ""
        var lastEnd = 0
        for match in matches {
            let matchRange = match.range
            if matchRange.location > lastEnd {
                result += ns.substring(with: NSRange(location: lastEnd, length: matchRange.location - lastEnd))
            }
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
        if lastEnd < ns.length {
            result += ns.substring(from: lastEnd)
        }
        return result
    }
}
