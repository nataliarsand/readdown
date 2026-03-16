import Foundation

enum MarkdownRenderer {

    static func render(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var html: [String] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Fenced code block
            if line.hasPrefix("```") {
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    code.append(escapeHTML(lines[i]))
                    i += 1
                }
                i += 1 // skip closing ```
                let langAttr = lang.isEmpty ? "" : " class=\"language-\(escapeHTML(lang))\""
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
            if trimmed.count >= 3 {
                let stripped = trimmed.filter { !$0.isWhitespace }
                let unique = Set(stripped)
                if unique.count == 1 && stripped.count >= 3, let ch = unique.first, "-*_".contains(ch) {
                    html.append("<hr>")
                    i += 1
                    continue
                }
            }

            // Heading
            if line.matches(pattern: "^\\s{0,3}#{1,6}(?:\\s+|$)") {
                let trimmedLine = String(line.drop(while: { $0 == " " || $0 == "\t" }))
                let level = min(trimmedLine.prefix(while: { $0 == "#" }).count, 6)
                let text = String(trimmedLine.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                html.append("<h\(level)>\(inlineMarkdown(text))</h\(level)>")
                i += 1
                continue
            }

            // Table
            if line.contains("|") && i + 1 < lines.count
                && lines[i + 1].matches(pattern: "^\\s*\\|?[\\s:]*-+[\\s:]*\\|") {
                // Parse header row
                let headerCells = parseTableRow(line)
                // Parse separator row for alignment
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
                i += 2 // skip header + separator

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
            if line.matches(pattern: "^\\s*[-*+] ") {
                var hasTaskItem = false
                var items: [String] = []
                while i < lines.count && lines[i].matches(pattern: "^\\s*[-*+] ") {
                    let text = lines[i].replacingOccurrences(of: "^\\s*[-*+] ", with: "", options: .regularExpression)
                    i += 1
                    // Collect continuation lines (indented or plain text that isn't a new block)
                    var continuations: [String] = []
                    while i < lines.count {
                        let next = lines[i]
                        let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                        if nextTrimmed.isEmpty {
                            // Blank line: continue list if next non-blank line is a list item
                            var peek = i + 1
                            while peek < lines.count && lines[peek].trimmingCharacters(in: .whitespaces).isEmpty { peek += 1 }
                            if peek < lines.count && lines[peek].matches(pattern: "^\\s*[-*+] ") {
                                i = peek
                                break
                            }
                            break
                        }
                        if next.matches(pattern: "^\\s*[-*+] ") || next.matches(pattern: "^\\s*\\d+\\. ")
                            || next.hasPrefix("#") || next.hasPrefix("```") || next.hasPrefix(">") {
                            break
                        }
                        continuations.append(nextTrimmed)
                        i += 1
                    }
                    let contHTML = continuations.isEmpty ? "" : "<br>" + continuations.map { inlineMarkdown($0) }.joined(separator: "<br>")
                    if text.hasPrefix("[ ] ") {
                        items.append("<li class=\"task-item\"><input type=\"checkbox\" disabled> \(inlineMarkdown(String(text.dropFirst(4))))\(contHTML)</li>")
                        hasTaskItem = true
                    } else if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
                        items.append("<li class=\"task-item\"><input type=\"checkbox\" checked disabled> \(inlineMarkdown(String(text.dropFirst(4))))\(contHTML)</li>")
                        hasTaskItem = true
                    } else {
                        items.append("<li>\(inlineMarkdown(text))\(contHTML)</li>")
                    }
                }
                let cls = hasTaskItem ? " class=\"task-list\"" : ""
                html.append("<ul\(cls)>\(items.joined())</ul>")
                continue
            }

            // Ordered list
            if line.matches(pattern: "^\\s*\\d+\\. ") {
                var items: [String] = []
                while i < lines.count && lines[i].matches(pattern: "^\\s*\\d+\\. ") {
                    let text = lines[i].replacingOccurrences(of: "^\\s*\\d+\\. ", with: "", options: .regularExpression)
                    i += 1
                    var continuations: [String] = []
                    while i < lines.count {
                        let next = lines[i]
                        let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                        if nextTrimmed.isEmpty {
                            // Blank line: continue list if next non-blank line is a list item
                            var peek = i + 1
                            while peek < lines.count && lines[peek].trimmingCharacters(in: .whitespaces).isEmpty { peek += 1 }
                            if peek < lines.count && lines[peek].matches(pattern: "^\\s*\\d+\\. ") {
                                i = peek
                                break
                            }
                            break
                        }
                        if next.matches(pattern: "^\\s*[-*+] ") || next.matches(pattern: "^\\s*\\d+\\. ")
                            || next.hasPrefix("#") || next.hasPrefix("```") || next.hasPrefix(">") {
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
                if t.isEmpty || l.hasPrefix("#") || l.hasPrefix(">") || l.hasPrefix("```")
                    || l.matches(pattern: "^\\s*[-*+] ") || l.matches(pattern: "^\\s*\\d+\\. ")
                    || isHTMLBlockStart(l) {
                    break
                }
                // Break if this line starts a table
                if l.contains("|") && i + 1 < lines.count
                    && lines[i + 1].matches(pattern: "^\\s*\\|?[\\s:]*-+[\\s:]*\\|") {
                    break
                }
                // Check HR
                if t.count >= 3 {
                    let stripped = t.filter { !$0.isWhitespace }
                    let unique = Set(stripped)
                    if unique.count == 1 && stripped.count >= 3, let ch = unique.first, "-*_".contains(ch) {
                        break
                    }
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
        guard let regex = try? NSRegularExpression(pattern: "</?[a-zA-Z][a-zA-Z0-9]*(?:\\s+[^>]*)?\\/?>", options: []) else {
            return escapeHTML(text)
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
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
        s = s.replacing(pattern: "!\\[([^\\]]*)\\]\\(([^)]+)\\)") { match in
            let url = sanitizedMarkdownURL(match[2])
            guard isSafeURL(url) else { return match[0] }
            return "<img src=\"\(escapeHTML(url))\" alt=\"\(match[1])\">"
        }

        // Links: [text](url)
        s = s.replacing(pattern: "\\[([^\\]]*)\\]\\(([^)]+)\\)") { match in
            let url = sanitizedMarkdownURL(match[2])
            guard isSafeURL(url) else { return "\(match[1])" }
            return "<a href=\"\(escapeHTML(url))\">\(match[1])</a>"
        }

        // Inline code
        s = s.replacing(pattern: "`([^`]+)`") { match in
            "<code>\(match[1])</code>"
        }

        // Bold + italic
        s = s.replacing(pattern: "\\*\\*\\*(.+?)\\*\\*\\*") { match in
            "<strong><em>\(match[1])</em></strong>"
        }
        s = s.replacing(pattern: "___(.+?)___") { match in
            "<strong><em>\(match[1])</em></strong>"
        }

        // Bold
        s = s.replacing(pattern: "\\*\\*(.+?)\\*\\*") { match in
            "<strong>\(match[1])</strong>"
        }
        s = s.replacing(pattern: "__(.+?)__") { match in
            "<strong>\(match[1])</strong>"
        }

        // Italic
        s = s.replacing(pattern: "\\*(.+?)\\*") { match in
            "<em>\(match[1])</em>"
        }
        s = s.replacing(pattern: "_(.+?)_") { match in
            "<em>\(match[1])</em>"
        }

        // Strikethrough
        s = s.replacing(pattern: "~~(.+?)~~") { match in
            "<del>\(match[1])</del>"
        }

        // Line breaks
        s = s.replacingOccurrences(of: "  \n", with: "<br>\n")

        return s
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

        // Reject Windows drive paths and other scheme-like prefixes.
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
    func matches(pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }

    func replacing(pattern: String, using transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return self
        }
        let nsRange = NSRange(startIndex..., in: self)
        var result = self
        // Process matches in reverse so ranges stay valid
        let matches = regex.matches(in: self, options: [], range: nsRange).reversed()
        for match in matches {
            var groups: [String] = []
            for g in 0..<match.numberOfRanges {
                if let r = Range(match.range(at: g), in: self) {
                    groups.append(String(self[r]))
                } else {
                    groups.append("")
                }
            }
            if let fullRange = Range(match.range(at: 0), in: result) {
                result.replaceSubrange(fullRange, with: transform(groups))
            }
        }
        return result
    }
}
