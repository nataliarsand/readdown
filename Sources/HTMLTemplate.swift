import Foundation

enum HTMLTemplate {

    private static let mermaidJS: String? = {
        guard let url = Bundle.main.url(forResource: "mermaid.min", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return js
    }()

    static func wrap(body: String, hasMermaid: Bool = false, compact: Bool = false, isDark: Bool = false) -> String {
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
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src file: data: https: http:; font-src 'none'; connect-src 'none'; form-action 'none';">
        <meta name="color-scheme" content="light dark">
        <style>
        :root {
            --text: #1f2328;            /* warmer than pure black, gentler on backlit screens */
            --bg: #fcfcfb;              /* a hair off-white to reduce glare; matches ReaderTheme.pageBackground */
            --muted: #57606a;           /* secondary text — blockquotes, h6, captions */
            --code-bg: #f6f8fa;
            --border: #d0d7de;
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
