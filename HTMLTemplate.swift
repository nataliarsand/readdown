import Foundation

enum HTMLTemplate {

    static func wrap(body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
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
        }

        @media (prefers-color-scheme: dark) {
            :root {
                --text: #e6edf3;
                --bg: #0d1117;
                --code-bg: #161b22;
                --border: #30363d;
                --link: #58a6ff;
                --blockquote-text: #8b949e;
                --blockquote-border: #30363d;
            }
        }

        * {
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans",
                         Helvetica, Arial, sans-serif, "Apple Color Emoji";
            font-size: 16px;
            line-height: 1.6;
            color: var(--text);
            background: var(--bg);
            max-width: 820px;
            margin: 0 auto;
            padding: 32px 28px;
            word-wrap: break-word;
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
            height: 0.25em;
            padding: 0;
            margin: 24px 0;
            background-color: var(--border);
            border: 0;
            border-radius: 2px;
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
            background: var(--code-bg);
        }

        tr:nth-child(even) {
            background: var(--code-bg);
        }

        ul.task-list {
            list-style: none;
            padding-left: 0;
        }

        li.task-item {
            position: relative;
            padding-left: 1.7em;
            margin-top: 0.15em;
            margin-bottom: 0.15em;
            line-height: 1.5;
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
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}
