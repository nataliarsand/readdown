import Foundation

enum HTMLTemplate {

    private static let mermaidJS: String? = {
        guard let url = Bundle.main.url(forResource: "mermaid.min", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return js
    }()

    // KaTeX: fast HTML+CSS math rendering. Its stylesheet has the woff2 math
    // fonts embedded as `data:` URIs, so nothing loads over the network — it
    // renders under the page's strict CSP (with `font-src data:`) like the
    // bundled Mermaid. Lighter than MathJax and covers the math the vast
    // majority of documents use. Both are injected only when a doc has math.
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
        // Blur veil under the header. Disabled in print (fixed = every page).
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
        let tableOfContentsCSS = compact ? "" : """
        /* Table of contents. It lives inside the rendered page so a normal
           full-page live reload rebuilds it from the new heading DOM. */
        #rd-table-of-contents {
            position: fixed;
            z-index: 20;
            top: 58px;
            right: 12px;
            bottom: 12px;
            width: 260px;
            display: flex;
            flex-direction: column;
            color: var(--text);
            background: var(--bg);
            border: 1px solid var(--hairline);
            border-radius: 12px;
            box-shadow: 0 8px 28px rgba(0, 0, 0, 0.16);
            opacity: 0;
            visibility: hidden;
            pointer-events: none;
            transform: translateX(12px);
            transition: opacity 0.16s ease, transform 0.16s ease, visibility 0.16s;
            overflow: hidden;
        }
        body.rd-table-of-contents-open #rd-table-of-contents {
            opacity: 1;
            visibility: visible;
            pointer-events: auto;
            transform: translateX(0);
        }
        .rd-toc-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            flex: 0 0 auto;
            min-height: 42px;
            padding: 6px 8px 6px 14px;
            border-bottom: 1px solid var(--hairline);
            font-size: 12px;
            font-weight: 600;
            letter-spacing: 0.02em;
            color: var(--muted);
            -webkit-user-select: none;
            user-select: none;
        }
        .rd-toc-close {
            width: 28px;
            height: 28px;
            padding: 0;
            border: 0;
            border-radius: 6px;
            color: var(--muted);
            background: transparent;
            font: inherit;
            font-size: 17px;
            line-height: 28px;
            cursor: default;
        }
        .rd-toc-close:hover,
        .rd-toc-close:focus-visible {
            color: var(--text);
            background: var(--code-bg);
            outline: none;
        }
        .rd-toc-list {
            flex: 1 1 auto;
            min-height: 0;
            padding: 8px;
            overflow-x: hidden;
            overflow-y: auto;
        }
        .rd-toc-link {
            display: block;
            padding-top: 5px;
            padding-right: 9px;
            padding-bottom: 5px;
            border-radius: 6px;
            color: var(--muted);
            font-size: 12px;
            line-height: 1.35;
            text-decoration: none;
            text-overflow: ellipsis;
            white-space: nowrap;
            overflow: hidden;
            cursor: default;
        }
        .rd-toc-link:hover,
        .rd-toc-link:focus-visible {
            color: var(--text);
            background: var(--code-bg);
            outline: none;
            text-decoration: none;
        }
        .rd-toc-link.rd-toc-active {
            color: var(--link);
            background: var(--code-bg);
            font-weight: 600;
        }
        @media (min-width: 720px) {
            body.rd-table-of-contents-open {
                padding-right: calc(clamp(28px, 5vw, 96px) + 280px);
            }
        }
        @media (max-width: 640px) {
            #rd-table-of-contents {
                left: 12px;
                width: auto;
            }
        }
        @media print {
            #rd-table-of-contents { display: none !important; }
        }
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
            --text: #1f2328;            /* warmer than pure black, gentler on backlit screens */
            --bg: #fcfcfb;              /* a hair off-white to reduce glare; matches ReaderTheme.pageBackground */
            --muted: #57606a;           /* secondary text — blockquotes, h6, captions */
            --code-bg: #f6f8fa;
            --border: #d0d7de;
            --hairline: rgba(31, 35, 40, 0.08); /* matches ReaderTheme.hairline */
            --link: #0969da;
            --link-underline: rgba(9, 105, 218, 0.35);
            --blockquote-border: #d0d7de;
            --table-stripe: #f6f8fa;
            --table-header: #eef1f5;
            --scrollbar-thumb: rgba(0, 0, 0, 0.32);
        }

        @media screen and (prefers-color-scheme: dark) {
            :root {
                --text: #e6edf3;
                --bg: #0d1117;
                --muted: #9198a1;       /* lifted from #8b949e for WCAG AA contrast */
                --code-bg: #161b22;
                --border: #3d444d;
                --hairline: rgba(230, 237, 243, 0.08);
                --link: #58a6ff;
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
        \(tableOfContentsCSS)

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

        /* Modular scale on 1.25 (major third). Em-relative margins so heading
           breathing room scales with the heading size — h1 gets more space
           above and below than h4 automatically. */
        h1, h2, h3, h4, h5, h6 {
            margin: 1.6em 0 0.6em;
            font-weight: 600;
            line-height: 1.25;
            /* When an anchor link scrolls to a heading, leave room for the
               toolbar (which extends over the top of the content area). */
            scroll-margin-top: 56px;
            position: relative;
        }
        /* Collapsible sections: a quiet left-gutter chevron (hover to reveal) folds the
           section down to the next same-or-higher heading. Absolutely positioned. */
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
        /* Collapsed: chevron points right and stays faintly visible as a hint. */
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

        /* First element shouldn't push the page down — body padding-top
           already provides the chrome clearance. */
        body > :first-child { margin-top: 0; }

        p {
            margin-top: 0;
            margin-bottom: 1em;
        }

        /* Always-on subtle underline — easier to scan for links than hover-only
           underline, but quieter than the default. */
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
        }

        pre code {
            padding: 0;
            background: transparent;
            border-radius: 0;
            font-size: 100%;
        }

        /* Copy button. Lives on a non-scrolling wrapper so it stays pinned to the
           top-right while the <pre> scrolls horizontally underneath it. Hidden by
           default, revealed on hover/focus — keeps the reading view quiet and means
           it never shows up in printed or exported output (no hover at render time). */
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
            color: #1a7f37;
            border-color: #1a7f37;
        }

        @media screen and (prefers-color-scheme: dark) {
            .rd-copy-btn.rd-copied {
                color: #3fb950;
                border-color: #3fb950;
            }
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
        }
        .mermaid svg {
            max-width: 100%;
            height: auto;
        }
        /* Math (KaTeX). Display blocks center and scroll horizontally so a wide
           equation never forces the page wider. KaTeX renders with the current
           text color, so math inherits `--text` and adapts to dark mode for free.
           KaTeX's own stylesheet — with the math fonts embedded as data: URIs —
           is injected only for documents that contain math. A failed expression
           renders its raw source via KaTeX's `.katex-error` styling. */
        .rd-math-display {
            display: block;
            margin: 1.25em 0;
            text-align: center;
            overflow-x: auto;
            overflow-y: hidden;
        }
        .rd-math-inline { display: inline; }
        /* .rd-math-display already supplies the vertical rhythm; drop KaTeX's own. */
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
        /* Autohide scrollbar: invisible by default, fades in while scrolling.
           Thin Bear-style: ~6px visible thumb (10px track, 2px transparent border). */
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
        // Copy button for fenced code blocks (ChatGPT-style). Wraps each
        // <pre><code> in a positioned container and pins a button to the
        // top-right. Runs after highlightAll so the highlighted DOM is final;
        // Mermaid blocks are <pre class="mermaid"> with no <code> child, so the
        // `pre > code` selector skips them.
        (function() {
            const COPY_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>';
            const CHECK_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>';

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
                }, 1600);
            }

            function copyCode(code, btn) {
                // textContent gives the exact source (newlines preserved, HTML
                // entities and highlight.js token spans resolved back to plain text).
                const text = code.textContent;
                // Prefer the async Clipboard API; fall back to execCommand, which is
                // the reliable path inside WKWebView's loadHTMLString context.
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
                        acceptNode: (n) => n.parentElement && n.parentElement.closest('script,style,[data-rd-search-exclude]') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT
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
        \(compact ? "" : """
        <script>
        // Build the table of contents from the final heading DOM rather than
        // parsing Markdown a second time. This keeps setext headings, inline
        // formatting, duplicate slugs, and live reloads aligned with the renderer.
        (function() {
            var headings = Array.from(document.querySelectorAll('h1,h2,h3,h4,h5,h6'))
                .filter(function(h) {
                    return !h.closest('[data-rd-search-exclude]')
                        && h.id && h.textContent.trim().length > 0;
                });
            var panel = null;
            var links = new Map();
            var updateScheduled = false;

            function visibleHeadings() {
                return headings.filter(function(h) { return h.getClientRects().length > 0; });
            }

            function capturePosition() {
                var candidates = visibleHeadings();
                var anchor = candidates.length > 0 ? candidates[0] : null;
                for (var i = 0; i < candidates.length; i++) {
                    if (candidates[i].getBoundingClientRect().top <= 80) {
                        anchor = candidates[i];
                    } else {
                        break;
                    }
                }
                return {
                    scrollY: window.scrollY,
                    anchorID: anchor ? anchor.id : null,
                    anchorOffset: anchor ? anchor.getBoundingClientRect().top : null
                };
            }

            function restorePosition(state) {
                var anchor = state.anchorID ? document.getElementById(state.anchorID) : null;
                if (anchor && typeof state.anchorOffset === 'number') {
                    window.scrollBy(0, anchor.getBoundingClientRect().top - state.anchorOffset);
                } else if (typeof state.scrollY === 'number') {
                    window.scrollTo(0, state.scrollY);
                }
            }

            function isVisible() {
                return !!panel && document.body.classList.contains('rd-table-of-contents-open');
            }

            function notifyHost() {
                var state = { available: headings.length > 0, visible: isVisible() };
                try {
                    window.webkit.messageHandlers.rdTableOfContents.postMessage(state);
                } catch (e) {}
            }

            function updateActive() {
                updateScheduled = false;
                var candidates = visibleHeadings();
                if (candidates.length === 0) return;
                var active = candidates[0];
                for (var i = 0; i < candidates.length; i++) {
                    if (candidates[i].getBoundingClientRect().top <= 96) {
                        active = candidates[i];
                    } else {
                        break;
                    }
                }
                if (window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2) {
                    active = candidates[candidates.length - 1];
                }
                links.forEach(function(link, heading) {
                    var selected = heading === active;
                    link.classList.toggle('rd-toc-active', selected);
                    if (selected) link.setAttribute('aria-current', 'location');
                    else link.removeAttribute('aria-current');
                });
            }

            function scheduleActiveUpdate() {
                if (updateScheduled) return;
                updateScheduled = true;
                window.requestAnimationFrame(updateActive);
            }

            function setVisible(visible, preservePosition) {
                if (!panel) return false;
                var position = preservePosition ? capturePosition() : null;
                document.body.classList.toggle('rd-table-of-contents-open', !!visible);
                panel.setAttribute('aria-hidden', visible ? 'false' : 'true');
                if (position) {
                    window.requestAnimationFrame(function() {
                        restorePosition(position);
                        scheduleActiveUpdate();
                    });
                }
                notifyHost();
                return isVisible();
            }

            window.__rdTableOfContents = {
                toggle: function() { return setVisible(!isVisible(), true); },
                capture: function() {
                    var state = capturePosition();
                    state.tableOfContentsVisible = isVisible();
                    return state;
                },
                restore: function(state) {
                    if (typeof state.tableOfContentsVisible === 'boolean') {
                        setVisible(state.tableOfContentsVisible, false);
                    }
                    // Two frames let the new page and its outline layout settle
                    // before the heading-relative reading position is restored.
                    window.requestAnimationFrame(function() {
                        window.requestAnimationFrame(function() {
                            restorePosition(state);
                            scheduleActiveUpdate();
                        });
                    });
                }
            };

            if (headings.length === 0) {
                notifyHost();
                return;
            }

            panel = document.createElement('aside');
            panel.id = 'rd-table-of-contents';
            panel.setAttribute('aria-label', 'Table of Contents');
            panel.setAttribute('aria-hidden', 'true');
            panel.setAttribute('data-rd-search-exclude', '');

            var header = document.createElement('div');
            header.className = 'rd-toc-header';
            var title = document.createElement('span');
            title.textContent = 'Contents';
            var close = document.createElement('button');
            close.type = 'button';
            close.className = 'rd-toc-close';
            close.setAttribute('aria-label', 'Close Table of Contents');
            close.textContent = '×';
            close.addEventListener('click', function() { setVisible(false, true); });
            header.appendChild(title);
            header.appendChild(close);
            panel.appendChild(header);

            var list = document.createElement('nav');
            list.className = 'rd-toc-list';
            var minimumLevel = headings.reduce(function(minimum, h) {
                return Math.min(minimum, Number(h.tagName.substring(1)));
            }, 6);

            headings.forEach(function(heading) {
                var link = document.createElement('a');
                var level = Number(heading.tagName.substring(1));
                link.className = 'rd-toc-link';
                link.href = '#' + encodeURIComponent(heading.id);
                link.textContent = heading.textContent.trim();
                link.title = link.textContent;
                link.style.paddingLeft = (9 + (level - minimumLevel) * 12) + 'px';
                link.addEventListener('click', function(event) {
                    event.preventDefault();
                    heading.scrollIntoView({ behavior: 'smooth', block: 'start' });
                    if (window.innerWidth < 720) setVisible(false, false);
                });
                links.set(heading, link);
                list.appendChild(link);
            });
            panel.appendChild(list);
            document.body.appendChild(panel);

            window.addEventListener('scroll', scheduleActiveUpdate, { passive: true });
            setVisible(window.innerWidth >= 1000, false);
            updateActive();
        })();
        </script>
        """)
        <script>
        // Autohide scrollbar: add `rd-scrolling` class for 700ms after any scroll event.
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
        // Collapsible headings: fold the section down to the next same-or-higher
        // heading. Headings are flat siblings, so the fold walks nextElementSibling.
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
        // Render only the `.rd-math` elements the renderer emitted — never a
        // document-wide scan — so a stray `$` in prose and any `<pre>`/`<code>`
        // stay literal. KaTeX renders synchronously; `throwOnError: false` shows
        // the raw TeX in its own error styling instead of throwing, matching the
        // graceful fallback the renderer set up.
        (function() {
            var nodes = document.querySelectorAll('.rd-math');
            for (var i = 0; i < nodes.length; i++) {
                var el = nodes[i];
                var display = el.classList.contains('rd-math-display');
                try {
                    // textContent gives the raw TeX back (the browser decodes the
                    // HTML-escaped `<`, `&`, … the renderer wrote).
                    katex.render(el.textContent, el, { displayMode: display, throwOnError: false });
                } catch (e) {
                    // Leave the source text in place; just flag it.
                    el.classList.add('rd-math-error');
                }
            }
        })();
        </script>
        """ : "")
        \(hasMermaid && mermaidJS != nil ? """
        <script>\(mermaidJS!)</script>
        <script>
        // Mermaid theming. Two layers:
        //   1. `theme: 'dark' | 'default'` — Mermaid's built-in palettes. These
        //      are baked into the bundle and apply reliably inside WKWebView.
        //      `theme: 'base'` (which would let themeVariables alone define the
        //      palette) silently failed to apply our overrides under WKWebView
        //      even though it worked in Safari — the "fix" shipped in 1.13
        //      never actually took effect on users' machines. Always start
        //      from a built-in theme.
        //   2. `themeVariables` — overrides on top, tuned to Readdown's palette
        //      so diagrams blend with the document. Mermaid stacks these on
        //      top of the chosen theme, so we keep both Readdown branding
        //      AND a working baseline.
        //
        // Dark-mode detection: Swift decides up-front (via NSApp.effectiveAppearance
        // when the template is generated) and emits `data-rd-theme` on `<body>`.
        // JS detection alternatives all failed in WKWebView — matchMedia returns
        // stale results, getComputedStyle doesn't resolve CSS variables, and
        // freshly-injected probe elements don't get styles applied synchronously.
        // Reading a pre-emitted data attribute removes every race condition.
        const dark = document.body.dataset.rdTheme === 'dark';
        // Mermaid's built-in `'dark'` palette renders pie slices in nearly-
        // black against our nearly-black document background — invisible.
        // Pass only the pie-related `themeVariables` (which Mermaid stacks on
        // top of the named theme) so the slices and legend are legible.
        // Don't be tempted to add other themeVariables here — passing a wider
        // set silently disables the named theme's per-diagram styling under
        // WKWebView (the bug shipped in 1.13).
        // `edgeLabelBackground` is also overridden so flowchart edge labels
        // (`Yes`/`No`) sit on the document background instead of Mermaid's
        // default gray box, which looks pasted-on against our near-black page.
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
