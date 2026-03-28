import Foundation

// MARK: - Pre-compiled Regex Patterns

private let fencePattern = try! NSRegularExpression(pattern: "^\\s{0,3}(`{3,}|~{3,})")
private let headingPattern = try! NSRegularExpression(pattern: "^\\s{0,3}#{1,6}(?:\\s+|$)")
private let ulPattern = try! NSRegularExpression(pattern: "^\\s*[-*+] ")
private let olPattern = try! NSRegularExpression(pattern: "^\\s*\\d+\\. ")
private let tableSepPattern = try! NSRegularExpression(pattern: "^\\s*\\|?[\\s:]*-+[\\s:]*\\|")

private let imagePattern = try! NSRegularExpression(pattern: "!\\[([^\\]]*)\\]\\(([^)]+)\\)")
private let linkPattern = try! NSRegularExpression(pattern: "\\[([^\\]]*)\\]\\(([^)]+)\\)")
private let codePattern = try! NSRegularExpression(pattern: "`([^`]+)`")
private let boldItalicStarPattern = try! NSRegularExpression(pattern: "\\*\\*\\*(.+?)\\*\\*\\*")
private let boldItalicUnderPattern = try! NSRegularExpression(pattern: "___(.+?)___")
private let boldStarPattern = try! NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*")
private let boldUnderPattern = try! NSRegularExpression(pattern: "__(.+?)__")
private let italicStarPattern = try! NSRegularExpression(pattern: "\\*(.+?)\\*")
private let italicUnderPattern = try! NSRegularExpression(pattern: "_(.+?)_")
private let strikePattern = try! NSRegularExpression(pattern: "~~(.+?)~~")
private let htmlTagPattern = try! NSRegularExpression(pattern: "</?[a-zA-Z][a-zA-Z0-9]*(?:\\s+[^>]*)?\\/?>")

enum MarkdownRenderer {

    static func render(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var html: [String] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Fenced code block (allow up to 3 leading spaces)
            if line.matchesPattern(fencePattern) {
                let stripped = line.drop(while: { $0 == " " || $0 == "\t" })
                let fenceChar: Character = stripped.first == "~" ? "~" : "`"
                let fenceLen = stripped.prefix(while: { $0 == fenceChar }).count
                let lang = String(stripped.dropFirst(fenceLen)).trimmingCharacters(in: .whitespaces)
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
                    code.append(escapeHTML(lines[i]))
                    i += 1
                }
                let langAttr = lang.isEmpty ? " class=\"nohighlight\"" : " class=\"language-\(escapeHTML(lang))\""
                html.append("<pre><code\(langAttr)>\(code.joined(separator: "\n"))</code></pre>")
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
                html.append("<h\(level)>\(inlineMarkdown(text))</h\(level)>")
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
                let inner = render(quoteLines.joined(separator: "\n"))
                html.append("<blockquote>\(inner)</blockquote>")
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
                    var continuations: [String] = []
                    while i < lines.count {
                        let next = lines[i]
                        let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                        if nextTrimmed.isEmpty {
                            var peek = i + 1
                            while peek < lines.count && lines[peek].trimmingCharacters(in: .whitespaces).isEmpty { peek += 1 }
                            if peek < lines.count && lines[peek].matchesPattern(olPattern) {
                                i = peek
                                break
                            }
                            break
                        }
                        if next.matchesPattern(ulPattern) || next.matchesPattern(olPattern)
                            || next.hasPrefix("#") || next.hasPrefix("```") || next.hasPrefix("~~~") || next.hasPrefix(">") {
                            break
                        }
                        continuations.append(nextTrimmed)
                        i += 1
                    }
                    let contHTML = continuations.isEmpty ? "" : "<br>" + continuations.map { inlineMarkdown($0) }.joined(separator: "<br>")
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
                html.append(blockLines.joined(separator: "\n"))
                continue
            }

            // Paragraph — collect contiguous non-blank, non-special lines
            var para: [String] = []
            while i < lines.count {
                let l = lines[i]
                let t = l.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || l.hasPrefix("#") || l.hasPrefix(">")
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
        }

        return html.joined(separator: "\n")
    }

    // MARK: - Inline Markdown

    private static func escapeHTMLPreservingTags(_ text: String) -> String {
        let ns = text as NSString
        let matches = htmlTagPattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return escapeHTML(text) }
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
        var s = escapeHTMLPreservingTags(text)

        // Images: ![alt](url)
        s = s.replacing(imagePattern) { match in
            let url = sanitizedMarkdownURL(match[2])
            guard isSafeURL(url) else { return match[0] }
            return "<img src=\"\(escapeHTML(url))\" alt=\"\(match[1])\">"
        }

        // Links: [text](url)
        s = s.replacing(linkPattern) { match in
            let url = sanitizedMarkdownURL(match[2])
            guard isSafeURL(url) else { return "\(match[1])" }
            return "<a href=\"\(escapeHTML(url))\">\(match[1])</a>"
        }

        // Inline code
        s = s.replacing(codePattern) { match in
            "<code>\(match[1])</code>"
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

        // Line breaks (two trailing spaces or single newline within a paragraph)
        s = s.replacingOccurrences(of: "  \n", with: "<br>\n")
        s = s.replacingOccurrences(of: "\n", with: "<br>\n")

        return s
    }

    // MARK: - Unordered List Helpers

    private static func listItemIndent(_ line: String) -> Int {
        line.prefix(while: { $0 == " " || $0 == "\t" }).reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }

    private static func parseUnorderedList(_ i: inout Int, lines: [String]) -> String {
        let baseIndent = listItemIndent(lines[i])
        var hasTaskItem = false
        var result = ""

        while i < lines.count && lines[i].matchesPattern(ulPattern) {
            let currentIndent = listItemIndent(lines[i])
            if currentIndent < baseIndent { break }

            if currentIndent > baseIndent {
                result += parseUnorderedList(&i, lines: lines)
                continue
            }

            let text = lines[i].removingMatch(of: ulPattern)
            i += 1

            // Collect continuation lines
            var continuations: [String] = []
            while i < lines.count {
                let next = lines[i]
                let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty {
                    var peek = i + 1
                    while peek < lines.count && lines[peek].trimmingCharacters(in: .whitespaces).isEmpty { peek += 1 }
                    if peek < lines.count && lines[peek].matchesPattern(ulPattern) {
                        i = peek
                        break
                    }
                    break
                }
                if next.matchesPattern(ulPattern) || next.matchesPattern(olPattern)
                    || next.hasPrefix("#") || next.hasPrefix("```") || next.hasPrefix("~~~") || next.hasPrefix(">") {
                    break
                }
                continuations.append(nextTrimmed)
                i += 1
            }

            let contHTML = continuations.isEmpty ? "" : "<br>" + continuations.map { inlineMarkdown($0) }.joined(separator: "<br>")
            if text == "[ ]" || text.hasPrefix("[ ] ") {
                let content = text.count > 4 ? String(text.dropFirst(4)) : ""
                result += "<li class=\"task-item\"><input type=\"checkbox\" disabled> \(inlineMarkdown(content))\(contHTML)</li>"
                hasTaskItem = true
            } else if text == "[x]" || text == "[X]" || text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
                let content = text.count > 4 ? String(text.dropFirst(4)) : ""
                result += "<li class=\"task-item\"><input type=\"checkbox\" checked disabled> \(inlineMarkdown(content))\(contHTML)</li>"
                hasTaskItem = true
            } else {
                result += "<li>\(inlineMarkdown(text))\(contHTML)</li>"
            }
        }

        let cls = hasTaskItem ? " class=\"task-list\"" : ""
        return "<ul\(cls)>\(result)</ul>"
    }

    // MARK: - Block Helpers

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
