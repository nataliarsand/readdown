import Foundation

enum HTMLTemplate {

    private static let mermaidJS: String? = {
        guard let url = Bundle.main.url(forResource: "mermaid.min", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return js
    }()

    static func wrap(body: String, hasMermaid: Bool = false, compact: Bool = false) -> String {
        let fontSize = compact ? "14px" : "16px"
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src file: data: https: http:; font-src 'none'; connect-src 'none'; form-action 'none';">
        <meta name="color-scheme" content="light dark">
        <style>
        :root {
            --text: #24292f;
            --bg: #ffffff;
            --code-bg: #f6f8fa;
            --border: #d0d7de;
            --link: #0969da;
            --blockquote-text: #57606a;
            --blockquote-border: #d0d7de;
            --table-stripe: #eef1f5;
            --table-header: #e1e6eb;
        }

        @media screen and (prefers-color-scheme: dark) {
            :root {
                --text: #e6edf3;
                --bg: #0d1117;
                --code-bg: #161b22;
                --border: #3d444d;
                --link: #58a6ff;
                --blockquote-text: #8b949e;
                --blockquote-border: #30363d;
                --table-stripe: #161b22;
                --table-header: #252c35;
            }
        }

        * {
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans",
                         Helvetica, Arial, sans-serif, "Apple Color Emoji";
            font-size: \(fontSize);
            line-height: 1.6;
            color: var(--text);
            background: var(--bg);
            margin: 0;
            padding: 32px clamp(28px, 5vw, 96px);
            word-wrap: break-word;
            -webkit-print-color-adjust: exact;
            print-color-adjust: exact;
        }

        h1, h2, h3, h4, h5, h6 {
            margin-top: 24px;
            margin-bottom: 16px;
            font-weight: 600;
            line-height: 1.25;
        }

        h1 { font-size: 2em; padding-bottom: 0.3em; border-bottom: 1px solid var(--border); }
        h2 { font-size: 1.5em; padding-bottom: 0.3em; border-bottom: 1px solid var(--border); }
        h3 { font-size: 1.25em; }
        h4 { font-size: 1em; }
        h5 { font-size: 0.875em; }
        h6 { font-size: 0.85em; color: var(--blockquote-text); }

        p {
            margin-top: 0;
            margin-bottom: 16px;
        }

        a {
            color: var(--link);
            text-decoration: none;
        }

        a:hover {
            text-decoration: underline;
        }

        code {
            font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
            font-size: 85%;
            padding: 0.2em 0.4em;
            background: var(--code-bg);
            border-radius: 6px;
        }

        pre {
            padding: 16px;
            overflow: auto;
            font-size: 85%;
            line-height: 1.45;
            background: var(--code-bg);
            border-radius: 6px;
            margin-bottom: 16px;
            max-width: 100%;
        }

        pre code {
            padding: 0;
            background: transparent;
            border-radius: 0;
            font-size: 100%;
        }

        blockquote {
            margin: 0 0 16px 0;
            padding: 0 1em;
            color: var(--blockquote-text);
            border-left: 0.25em solid var(--blockquote-border);
        }

        ul, ol {
            margin-top: 0;
            margin-bottom: 16px;
            padding-left: 2em;
        }

        li + li {
            margin-top: 0.25em;
        }

        hr {
            height: 0;
            padding: 0;
            margin: 24px 0;
            border: 0;
            border-top: 0.25em solid var(--border);
        }

        img {
            max-width: 100%;
            height: auto;
            border-radius: 6px;
        }

        del {
            opacity: 0.6;
        }

        table {
            border-collapse: collapse;
            border-spacing: 0;
            margin-top: 0;
            margin-bottom: 16px;
            width: auto;
            max-width: 100%;
            overflow: auto;
            display: block;
        }

        th, td {
            padding: 6px 13px;
            border: 1px solid var(--border);
        }

        th {
            font-weight: 600;
            background: var(--table-header);
        }

        tr:nth-child(even) {
            background: var(--table-stripe);
        }

        ul.task-list {
            list-style: none;
            padding-left: 0;
            margin-bottom: 16px;
        }

        li.task-item {
            position: relative;
            padding-left: 1.7em;
            margin-top: 0.15em;
            margin-bottom: 0.15em;
            line-height: 1.5;
            overflow: hidden;
        }

        li.task-item input[type="checkbox"] {
            -webkit-appearance: none;
            appearance: none;
            position: absolute;
            left: 0;
            top: 0.25em;
            width: 16px;
            height: 16px;
            border: 1.5px solid var(--border);
            border-radius: 4px;
            background: var(--bg);
            cursor: default;
            margin: 0;
            -webkit-print-color-adjust: exact;
            print-color-adjust: exact;
        }

        li.task-item input[type="checkbox"]:checked {
            background: var(--link);
            border-color: var(--link);
        }

        li.task-item input[type="checkbox"]:checked::after {
            content: '';
            position: absolute;
            left: 4.5px;
            top: 1px;
            width: 4px;
            height: 8px;
            border: solid #fff;
            border-width: 0 2px 2px 0;
            transform: rotate(45deg);
        }
        pre.mermaid {
            background: transparent;
            padding: 0;
            text-align: center;
        }
        .mermaid svg {
            max-width: 100%;
            height: auto;
        }
        mark.rd-find {
            background: #fff59d;
            color: inherit;
            padding: 0;
            border-radius: 2px;
        }
        mark.rd-find-current {
            background: #ffa726;
            color: inherit;
            box-shadow: 0 0 0 2px #f57c00;
        }
        @media (prefers-color-scheme: dark) {
            mark.rd-find { background: #5d4037; color: #fff; }
            mark.rd-find-current { background: #ef6c00; color: #fff; }
        }
        \(SyntaxHighlight.css)
        @media print {
            body {
                padding: 0;
                margin: 0;
                font-size: 11pt;
                line-height: 1.5;
            }
            h1 { font-size: 18pt; }
            h2 { font-size: 15pt; }
            h3 { font-size: 13pt; }
            pre, pre code, .hljs {
                white-space: pre-wrap;
                word-wrap: break-word;
                font-size: 9pt;
            }
            pre, blockquote, table, img { page-break-inside: avoid; }
            h1, h2, h3, h4 { page-break-after: avoid; }
        }
        </style>
        </head>
        <body>
        \(body)
        <script>\(SyntaxHighlight.js)</script>
        <script>
        hljs.configure({ languages: [
            'bash', 'c', 'cpp', 'css', 'diff', 'go', 'java', 'javascript',
            'json', 'kotlin', 'python', 'ruby', 'rust', 'shell', 'sql',
            'swift', 'typescript', 'xml', 'yaml'
        ]});
        hljs.highlightAll();
        </script>
        <script>
        (function() {
            const MATCH = 'rd-find';
            const CURRENT = 'rd-find-current';
            let index = -1;
            function clear() {
                document.querySelectorAll('mark.' + MATCH).forEach(el => {
                    const t = document.createTextNode(el.textContent);
                    el.parentNode.replaceChild(t, el);
                });
                document.body.normalize();
                index = -1;
            }
            function escapeRe(s) { return s.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&'); }
            function highlight() {
                document.querySelectorAll('mark.' + CURRENT).forEach(el => el.classList.remove(CURRENT));
                const all = document.querySelectorAll('mark.' + MATCH);
                if (index < 0 || index >= all.length) return;
                all[index].classList.add(CURRENT);
                all[index].scrollIntoView({ block: 'center', behavior: 'smooth' });
            }
            window.__rdFind = {
                search(q) {
                    clear();
                    if (!q) return { total: 0, current: 0 };
                    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
                        acceptNode: (n) => n.parentElement && n.parentElement.closest('script,style') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT
                    });
                    const nodes = [];
                    let n;
                    while ((n = walker.nextNode())) nodes.push(n);
                    const re = new RegExp(escapeRe(q), 'gi');
                    let count = 0;
                    nodes.forEach(node => {
                        const text = node.nodeValue;
                        if (!re.test(text)) return;
                        re.lastIndex = 0;
                        const frag = document.createDocumentFragment();
                        let last = 0, m;
                        while ((m = re.exec(text)) !== null) {
                            if (m.index > last) frag.appendChild(document.createTextNode(text.slice(last, m.index)));
                            const mark = document.createElement('mark');
                            mark.className = MATCH;
                            mark.textContent = m[0];
                            frag.appendChild(mark);
                            last = m.index + m[0].length;
                            count++;
                        }
                        if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
                        node.parentNode.replaceChild(frag, node);
                    });
                    index = count > 0 ? 0 : -1;
                    highlight();
                    return { total: count, current: count > 0 ? 1 : 0 };
                },
                next() {
                    const all = document.querySelectorAll('mark.' + MATCH);
                    if (all.length === 0) return { total: 0, current: 0 };
                    index = (index + 1) % all.length;
                    highlight();
                    return { total: all.length, current: index + 1 };
                },
                prev() {
                    const all = document.querySelectorAll('mark.' + MATCH);
                    if (all.length === 0) return { total: 0, current: 0 };
                    index = (index - 1 + all.length) % all.length;
                    highlight();
                    return { total: all.length, current: index + 1 };
                },
                clear: clear
            };
        })();
        </script>
        \(hasMermaid && mermaidJS != nil ? """
        <script>\(mermaidJS!)</script>
        <script>
        mermaid.initialize({
            startOnLoad: true,
            theme: window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default',
            securityLevel: 'strict'
        });
        </script>
        """ : "")
        </body>
        </html>
        """
    }
}
