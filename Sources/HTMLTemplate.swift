import Foundation

enum CheckIcon {
    static let grid: CGFloat = 24
    static let points: [CGPoint] = [CGPoint(x: 20, y: 6), CGPoint(x: 9, y: 17), CGPoint(x: 4, y: 12)]
    static let strokeWidth: CGFloat = 2.5
    static let confirmSeconds: TimeInterval = 1.6

    static var svg: String {
        let pts = points.map { "\(Int($0.x)) \(Int($0.y))" }.joined(separator: " ")
        return "<svg viewBox=\"0 0 \(Int(grid)) \(Int(grid))\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"\(strokeWidth)\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><polyline points=\"\(pts)\"></polyline></svg>"
    }
}

enum CopyIcon {
    static let grid: CGFloat = 24
    static let strokeWidth: CGFloat = 2
    static let radius: CGFloat = 2.5
    static let front = CGRect(x: 8, y: 8, width: 13, height: 13)
    static let backCorners: [CGPoint] = [CGPoint(x: 16, y: 8), CGPoint(x: 16, y: 3), CGPoint(x: 3, y: 3),
                                         CGPoint(x: 3, y: 16), CGPoint(x: 8, y: 16)]

    static var svg: String {
        let c = backCorners.map { "\(n($0.x)) \(n($0.y))" }
        let r = n(radius)
        let back = "M\(c[0])V\(n(backCorners[1].y + radius))A\(r) \(r) 0 0 0 \(n(backCorners[1].x - radius)) \(n(backCorners[1].y))"
            + "H\(n(backCorners[2].x + radius))A\(r) \(r) 0 0 0 \(n(backCorners[2].x)) \(n(backCorners[2].y + radius))"
            + "V\(n(backCorners[3].y - radius))A\(r) \(r) 0 0 0 \(n(backCorners[3].x + radius)) \(n(backCorners[3].y))H\(n(backCorners[4].x))"
        return "<svg viewBox=\"0 0 \(Int(grid)) \(Int(grid))\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"\(n(strokeWidth))\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><rect x=\"\(n(front.minX))\" y=\"\(n(front.minY))\" width=\"\(n(front.width))\" height=\"\(n(front.height))\" rx=\"\(r)\"></rect><path d=\"\(back)\"></path></svg>"
    }

    private static func n(_ v: CGFloat) -> String {
        v == v.rounded() ? String(Int(v)) : String(Double(v))
    }
}

enum HTMLTemplate {

    private static let mermaidJS: String? = {
        guard let url = Bundle.main.url(forResource: "mermaid.min", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return js
    }()

    // KaTeX's stylesheet embeds its fonts as data: URIs, which the CSP's font-src allows.
    private static let katexJS: String? = {
        guard let url = Bundle.main.url(forResource: "katex.min", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return js
    }()

    private static let katexCSS: String? = {
        guard let url = Bundle.main.url(forResource: "katex.min", withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return css
    }()

    static func wrap(body: String, hasMermaid: Bool = false, hasMath: Bool = false, compact: Bool = false, isDark: Bool = false) -> String {
        let fontSize = compact ? "14px" : "16px"
        // Extra clearance for the floating header; Quick Look (compact) has none.
        let topPadding = compact ? "32px" : "64px"
        // Blur veil under the header; a fixed element would repeat on every printed page.
        let headerBlur = compact ? "" : """
        body::before {
            content: "";
            position: fixed;
            top: 0; left: 0; right: 0;
            height: 64px;
            pointer-events: none;
            z-index: 10;
            -webkit-backdrop-filter: blur(10px);
            backdrop-filter: blur(10px);
            -webkit-mask-image: linear-gradient(to bottom, black 30%, transparent 100%);
            mask-image: linear-gradient(to bottom, black 30%, transparent 100%);
        }
        @media print { body::before { display: none; } }
        """
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src file: data: https: http:; font-src \(hasMath ? "data:" : "'none'"); connect-src 'none'; form-action 'none';">
        <meta name="color-scheme" content="light dark">
        <style>
        :root {
            --text: #1f2328;
            --bg: #fcfcfb;              /* must match ReaderTheme.pageBackground */
            --muted: #57606a;
            --code-bg: #eef1f5;
            --border: #d0d7de;
            --link: #0969da;
            --success: #1f962c;         /* must match ReaderTheme.success */
            --link-underline: rgba(9, 105, 218, 0.35);
            --blockquote-border: #d0d7de;
            --table-stripe: #f2f4f7;
            --table-header: #eef1f5;
            --scrollbar-thumb: rgba(0, 0, 0, 0.32);
        }

        @media screen and (prefers-color-scheme: dark) {
            :root {
                --text: #e6edf3;
                --bg: #0d1117;
                --muted: #9198a1;       /* WCAG AA against --bg */
                --code-bg: #161b22;
                --border: #3d444d;
                --link: #58a6ff;
                --success: #2ebe3d;
                --link-underline: rgba(88, 166, 255, 0.40);
                --blockquote-border: #30363d;
                --table-stripe: #161b22;
                --table-header: #252c35;
                --scrollbar-thumb: rgba(255, 255, 255, 0.32);
            }
        }

        * {
            box-sizing: border-box;
        }

        html {
            scroll-behavior: smooth;
        }

        \(headerBlur)

        body {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI",
                         "Noto Sans", Helvetica, Arial, sans-serif, "Apple Color Emoji";
            font-size: \(fontSize);
            line-height: 1.6;
            color: var(--text);
            background: var(--bg);
            margin: 0;
            padding: \(topPadding) clamp(28px, 5vw, 96px) 32px clamp(28px, 5vw, 96px);
            word-wrap: break-word;
            overflow-x: hidden;
            -webkit-font-smoothing: antialiased;
            text-rendering: optimizeLegibility;
            -webkit-print-color-adjust: exact;
            print-color-adjust: exact;
        }

        /* Sizes follow a 1.25 modular scale; em margins scale with the heading. */
        h1, h2, h3, h4, h5, h6 {
            margin: 1.6em 0 0.6em;
            font-weight: 600;
            line-height: 1.25;
            /* anchor targets clear the floating header */
            scroll-margin-top: 56px;
            position: relative;
        }
        .rd-fold {
            position: absolute;
            left: -1.15rem;
            top: 0.42em;
            width: 14px;
            height: 14px;
            color: var(--muted);
            opacity: 0;
            cursor: default;
            transition: opacity 0.15s ease, transform 0.15s ease;
            -webkit-user-select: none;
            user-select: none;
        }
        .rd-fold svg { width: 100%; height: 100%; display: block; }
        h1:hover > .rd-fold, h2:hover > .rd-fold, h3:hover > .rd-fold,
        h4:hover > .rd-fold, h5:hover > .rd-fold, h6:hover > .rd-fold { opacity: 0.3; }
        .rd-fold:hover { opacity: 0.7; }
        .rd-collapsed > .rd-fold { transform: rotate(-90deg); opacity: 0.28; }
        .rd-fold-hidden { display: none !important; }
        @media print {
            .rd-fold { display: none; }
            .rd-fold-hidden { display: revert !important; }
        }
        h1 { font-size: 1.95em; letter-spacing: -0.015em; }
        h2 { font-size: 1.56em; letter-spacing: -0.01em; }
        h3 { font-size: 1.25em; }
        h4 { font-size: 1em; }
        h5 { font-size: 0.875em; }
        h6 { font-size: 0.85em; color: var(--muted); }

        /* body padding already clears the header */
        body > :first-child { margin-top: 0; }

        p {
            margin-top: 0;
            margin-bottom: 1em;
        }

        a {
            color: var(--link);
            text-decoration: underline;
            text-decoration-color: var(--link-underline);
            text-decoration-thickness: 1px;
            text-underline-offset: 2px;
        }

        a:hover {
            text-decoration-color: var(--link);
        }

        code {
            font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
            font-size: 0.875em;
            padding: 0.15em 0.35em;
            background: var(--code-bg);
            border-radius: 4px;
        }

        pre {
            padding: 16px 20px;
            overflow: auto;
            font-size: 0.875em;
            line-height: 1.55;
            background: var(--code-bg);
            border-radius: 8px;
            margin: 1.25em 0;
            max-width: 100%;
            white-space: pre-wrap;
            overflow-wrap: break-word;
            /* 2ch sits off the 4-space code grid, so a wrapped continuation can't read as new code. */
            text-indent: 2ch hanging each-line;
        }

        pre code, pre code.hljs {
            padding: 0;
            background: transparent;
            border-radius: 0;
            font-size: 100%;
        }

        /* The wrapper doesn't scroll with the <pre>, so the copy button stays pinned. */
        .rd-codeblock {
            position: relative;
        }

        .rd-copy-btn {
            position: absolute;
            top: 8px;
            right: 10px;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            width: 28px;
            height: 28px;
            padding: 0;
            color: var(--muted);
            background: var(--code-bg);
            border: 1px solid var(--border);
            border-radius: 6px;
            cursor: default;
            opacity: 0;
            transition: opacity 0.15s ease, color 0.15s ease, border-color 0.15s ease;
            -webkit-user-select: none;
            user-select: none;
        }

        .rd-codeblock:hover .rd-copy-btn,
        .rd-copy-btn:focus-visible {
            opacity: 1;
        }

        .rd-copy-btn:hover {
            color: var(--text);
            border-color: var(--muted);
        }

        .rd-copy-btn.rd-copied {
            opacity: 1;
            color: var(--success);
            border-color: var(--success);
        }

        .rd-copy-btn svg {
            display: block;
            width: 16px;
            height: 16px;
        }

        blockquote {
            margin: 0 0 1em 0;
            padding: 0 1em;
            color: var(--muted);
            border-left: 3px solid var(--blockquote-border);
        }

        ul, ol {
            margin-top: 0;
            margin-bottom: 1em;
            padding-left: 2em;
        }

        li + li {
            margin-top: 0.35em;
        }

        hr {
            height: 0;
            padding: 0;
            margin: 2em 0;
            border: 0;
            border-top: 1px solid var(--border);
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
            margin: 0 0 1em 0;
            width: auto;
            max-width: 100%;
            overflow: auto;
            display: block;
            font-size: 0.95em;
        }

        th, td {
            padding: 8px 14px;
            border: 1px solid var(--border);
        }

        th {
            font-weight: 600;
            background: var(--table-header);
            text-align: left;
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
            padding-left: 1.55em;
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
            background-color: var(--link);
            border-color: var(--link);
            background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3E%3Cpath fill='none' stroke='%23fff' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round' d='M3.5 8.5 6.7 11.7 12.5 4.8'/%3E%3C/svg%3E");
            background-repeat: no-repeat;
            background-position: center;
            background-size: 100% 100%;
        }
        pre.mermaid {
            background: transparent;
            padding: 0;
            text-align: center;
            /* pre's hanging indent pushes wrapped diagram labels past their foreignObject */
            text-indent: 0;
        }
        .mermaid svg {
            max-width: 100%;
            height: auto;
        }
        /* Mermaid boxes flowchart labels in a fixed-width foreignObject; wrapping lets it grow the node instead of clipping. */
        pre.mermaid svg[aria-roledescription="flowchart-v2"] .nodeLabel p {
            white-space: normal;
            overflow-wrap: anywhere;
        }
        /* Display math scrolls horizontally so a wide equation never widens the page. */
        .rd-math-display {
            display: block;
            margin: 1.25em 0;
            text-align: center;
            overflow-x: auto;
            overflow-y: hidden;
        }
        .rd-math-inline { display: inline; }
        /* .rd-math-display owns the vertical margin */
        .katex-display { margin: 0 !important; }
        .rd-math-error,
        .katex-error {
            color: #cf222e;
            font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
            font-size: 0.875em;
            white-space: pre-wrap;
        }
        @media screen and (prefers-color-scheme: dark) {
            .rd-math-error,
            .katex-error { color: #ff7b72; }
        }
        /* Scrollbar shows only while body.rd-scrolling is set by script. */
        ::-webkit-scrollbar {
            width: 10px;
            height: 10px;
            background: transparent;
        }
        ::-webkit-scrollbar-track { background: transparent; }
        ::-webkit-scrollbar-thumb {
            background: transparent;
            border-radius: 5px;
            border: 2px solid transparent;
            background-clip: content-box;
            transition: background-color 0.25s ease;
        }
        body.rd-scrolling::-webkit-scrollbar-thumb {
            background-color: var(--scrollbar-thumb);
            background-clip: content-box;
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
            .rd-copy-btn { display: none; }
        }
        </style>
        </head>
        <body data-rd-theme="\(isDark ? "dark" : "light")">
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
        // Runs after highlightAll; Mermaid <pre>s have no <code> child, so `pre > code` skips them.
        (function() {
            const COPY_ICON = '\(CopyIcon.svg)';
            const CHECK_ICON = '\(CheckIcon.svg)';

            function legacyCopy(text) {
                const ta = document.createElement('textarea');
                ta.value = text;
                ta.setAttribute('readonly', '');
                ta.style.position = 'fixed';
                ta.style.top = '0';
                ta.style.left = '0';
                ta.style.opacity = '0';
                document.body.appendChild(ta);
                ta.select();
                let ok = false;
                try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
                document.body.removeChild(ta);
                return ok;
            }

            function showCopied(btn) {
                // No-op unless the host installed the handler.
                try { window.webkit.messageHandlers.rdUsage.postMessage('copy_code'); } catch (e) {}
                btn.classList.add('rd-copied');
                btn.innerHTML = CHECK_ICON;
                btn.setAttribute('aria-label', 'Copied');
                clearTimeout(btn._rdTimer);
                btn._rdTimer = setTimeout(function() {
                    btn.classList.remove('rd-copied');
                    btn.innerHTML = COPY_ICON;
                    btn.setAttribute('aria-label', 'Copy code');
                }, \(Int(CheckIcon.confirmSeconds * 1000)));
            }

            function copyCode(code, btn) {
                const text = code.textContent;
                // execCommand is the reliable path under loadHTMLString.
                if (navigator.clipboard && navigator.clipboard.writeText) {
                    navigator.clipboard.writeText(text).then(
                        function() { showCopied(btn); },
                        function() { if (legacyCopy(text)) showCopied(btn); }
                    );
                } else if (legacyCopy(text)) {
                    showCopied(btn);
                }
            }

            document.querySelectorAll('pre > code').forEach(function(code) {
                const pre = code.parentElement;
                const wrap = document.createElement('div');
                wrap.className = 'rd-codeblock';
                pre.parentNode.insertBefore(wrap, pre);
                wrap.appendChild(pre);

                const btn = document.createElement('button');
                btn.type = 'button';
                btn.className = 'rd-copy-btn';
                btn.setAttribute('aria-label', 'Copy code');
                btn.innerHTML = COPY_ICON;
                btn.addEventListener('click', function() { copyCode(code, btn); });
                wrap.appendChild(btn);
            });
        })();
        </script>
        <script>
        // Rewrites Cmd+C: WebKit's default serialization bakes computed styles into the paste.
        (function() {
            // Null prototype so inherited names can't pass the allowlist.
            var KEEP_ATTRS = Object.assign(Object.create(null),
                { href: 1, src: 1, alt: 1, title: 1, colspan: 1, rowspan: 1, start: 1 });
            // cloneContents() drops ancestors that fully contain the range, so a
            // selection inside one block would lose its block identity.
            var WRAP = /^(H[1-6]|P|PRE|CODE|BLOCKQUOTE|EM|STRONG|B|I|DEL|A)$/;
            var WRAP_TABLE = /^(TABLE|THEAD|TBODY|TR|TD|TH)$/;
            var WRAP_LIST = /^(LI|UL|OL)$/;
            var MONO = "font-family:'Courier New',monospace";

            function shouldWrap(node, content) {
                var tag = node.tagName;
                if (WRAP_TABLE.test(tag)) return content.querySelector('td, th') !== null;
                if (WRAP_LIST.test(tag)) return content.querySelector('li') !== null;
                return WRAP.test(tag);
            }

            function clean(root) {
                root.querySelectorAll('.rd-fold, .rd-fold-hidden, .rd-copy-btn, script, style, button').forEach(function(el) {
                    el.remove();
                });
                root.querySelectorAll('mark.rd-find, mark.rd-find-current').forEach(function(el) {
                    el.replaceWith(document.createTextNode(el.textContent));
                });
                // KaTeX's markup repeats the text across MathML and HTML layers.
                root.querySelectorAll('.rd-math').forEach(function(el) {
                    var display = el.classList.contains('rd-math-display');
                    var ann = el.querySelector('annotation[encoding="application/x-tex"]');
                    var tex = (ann ? ann.textContent : el.textContent).trim();
                    var out = document.createElement(display ? 'pre' : 'code');
                    out.textContent = display ? '$$' + tex + '$$' : '$' + tex + '$';
                    el.replaceWith(out);
                });
                // The rendered SVG doesn't survive an HTML paste.
                root.querySelectorAll('pre.mermaid').forEach(function(el) {
                    var out = document.createElement('pre');
                    out.textContent = el.getAttribute('data-rd-src') || el.textContent;
                    el.replaceWith(out);
                });
                root.querySelectorAll('svg').forEach(function(el) { el.remove(); });
                root.querySelectorAll('input[type="checkbox"]').forEach(function(el) {
                    el.replaceWith(document.createTextNode(el.checked ? '☑' : '☐'));
                });
                root.querySelectorAll('.rd-codeblock').forEach(function(el) {
                    var pre = el.querySelector('pre');
                    if (pre) { el.replaceWith(pre); } else { el.remove(); }
                });
                root.querySelectorAll('code').forEach(function(el) {
                    el.textContent = el.textContent;
                });
                root.querySelectorAll('*').forEach(function(el) {
                    for (var i = el.attributes.length - 1; i >= 0; i--) {
                        var name = el.attributes[i].name;
                        if (!KEEP_ATTRS[name]) el.removeAttribute(name);
                    }
                });
                root.querySelectorAll('pre, code').forEach(function(el) {
                    el.setAttribute('style', MONO);
                });
                // Removed siblings leave blank text nodes that paste as empty lines.
                Array.prototype.slice.call(root.childNodes).forEach(function(n) {
                    if (n.nodeType === 3 && !n.textContent.trim()) n.remove();
                });
            }

            window.__rdCopy = {
                htmlForSelection: function() {
                    var sel = window.getSelection();
                    if (!sel || sel.isCollapsed || sel.rangeCount === 0) return null;
                    var range = sel.getRangeAt(0);
                    var content = document.createElement('div');
                    content.appendChild(range.cloneContents());
                    var node = range.commonAncestorContainer;
                    if (node.nodeType !== 1) node = node.parentElement;
                    while (node && node !== document.body) {
                        if (shouldWrap(node, content)) {
                            var w = node.cloneNode(false);
                            while (content.firstChild) w.appendChild(content.firstChild);
                            content.appendChild(w);
                        }
                        node = node.parentElement;
                    }
                    clean(content);
                    return content.innerHTML;
                }
            };

            document.addEventListener('copy', function(e) {
                // The code-block button's execCommand fallback copies from a hidden textarea.
                if (e.target && (e.target.tagName === 'TEXTAREA' || e.target.tagName === 'INPUT')) return;
                if (!e.clipboardData) return;
                var html = window.__rdCopy.htmlForSelection();
                if (html === null) return;
                e.clipboardData.setData('text/html', html);
                e.clipboardData.setData('text/plain', window.getSelection().toString());
                e.preventDefault();
            });
        })();
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
        <script>
        (function() {
            let timer;
            window.addEventListener('scroll', () => {
                document.body.classList.add('rd-scrolling');
                clearTimeout(timer);
                timer = setTimeout(() => document.body.classList.remove('rd-scrolling'), 700);
            }, { passive: true });
        })();
        </script>
        \(compact ? "" : """
        <script>
        // Headings are flat siblings, so a section runs to the next same-or-higher heading.
        (function() {
            var CH = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"></polyline></svg>';
            function level(el) {
                return el && el.tagName && /^H[1-6]$/.test(el.tagName) ? +el.tagName.charAt(1) : 0;
            }
            document.querySelectorAll('h1,h2,h3,h4,h5,h6').forEach(function(h) {
                var lvl = level(h);
                var btn = document.createElement('span');
                btn.className = 'rd-fold';
                btn.innerHTML = CH;
                btn.setAttribute('role', 'button');
                btn.setAttribute('aria-label', 'Collapse section');
                h.insertBefore(btn, h.firstChild);
                btn.addEventListener('click', function(e) {
                    e.preventDefault();
                    e.stopPropagation();
                    var collapsed = h.classList.toggle('rd-collapsed');
                    btn.setAttribute('aria-label', collapsed ? 'Expand section' : 'Collapse section');
                    var el = h.nextElementSibling;
                    while (el) {
                        var l = level(el);
                        if (l > 0 && l <= lvl) break;
                        el.classList.toggle('rd-fold-hidden', collapsed);
                        el = el.nextElementSibling;
                    }
                });
            });
        })();
        </script>
        """)
        \(hasMath && katexJS != nil && katexCSS != nil ? """
        <style>\(katexCSS!)</style>
        <script>\(katexJS!)</script>
        <script>
        // Only renderer-emitted .rd-math nodes; a document-wide scan would eat stray `$` in prose and code.
        (function() {
            var nodes = document.querySelectorAll('.rd-math');
            for (var i = 0; i < nodes.length; i++) {
                var el = nodes[i];
                var display = el.classList.contains('rd-math-display');
                try {
                    katex.render(el.textContent, el, { displayMode: display, throwOnError: false });
                } catch (e) {
                    el.classList.add('rd-math-error');
                }
            }
        })();
        </script>
        """ : "")
        \(hasMermaid && mermaidJS != nil ? """
        <script>\(mermaidJS!)</script>
        <script>
        // Swift stamps data-rd-theme; matchMedia and getComputedStyle report stale values in WKWebView.
        const dark = document.body.dataset.rdTheme === 'dark';
        // Keep to a built-in theme with these few overrides: `theme: 'base'` or a wider
        // themeVariables set silently drops per-diagram styling under WKWebView.
        const themeVars = dark ? {
            edgeLabelBackground: '#0d1117',
            pie1: '#58a6ff', pie2: '#f59e0b', pie3: '#34d399',
            pie4: '#a78bfa', pie5: '#f87171',
            pieTitleTextColor: '#e6edf3',
            pieSectionTextColor: '#0d1117',
            pieLegendTextColor: '#e6edf3',
            pieStrokeColor: '#0d1117',
            pieOuterStrokeColor: '#3d444d',
            pieOpacity: '1'
        } : {
            edgeLabelBackground: '#fcfcfb',
            pie1: '#0969da', pie2: '#f59e0b', pie3: '#10b981',
            pie4: '#8b5cf6', pie5: '#ef4444',
            pieTitleTextColor: '#1f2328',
            pieSectionTextColor: '#ffffff',
            pieLegendTextColor: '#1f2328',
            pieStrokeColor: '#ffffff',
            pieOuterStrokeColor: '#d0d7de',
            pieOpacity: '1'
        };
        document.querySelectorAll('pre.mermaid').forEach(function(el) {
            el.setAttribute('data-rd-src', el.textContent);
        });
        mermaid.initialize({
            startOnLoad: true,
            theme: dark ? 'dark' : 'default',
            themeVariables: themeVars,
            securityLevel: 'strict'
        });
        </script>
        """ : "")
        </body>
        </html>
        """
    }
}
