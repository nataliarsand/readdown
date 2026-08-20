import Foundation

private let inlineMathPattern = try! NSRegularExpression(
    pattern: "<span class=\"rd-math rd-math-inline\">([^<]*)</span>")
private let displayMathPattern = try! NSRegularExpression(
    pattern: "<div class=\"rd-math rd-math-display\">([^<]*)</div>")

/// Builds the HTML flavor for the full-document copy.
enum ClipboardExport {

    /// Rich editors won't infer monospace from bare `<pre>`/`<code>`.
    private static let monospace = "font-family:'Courier New',monospace"

    static func htmlFragment(fromRenderedBody body: String) -> String {
        var html = body

        html = replace(displayMathPattern, in: html, template: "<pre>\\$\\$$1\\$\\$</pre>")
        html = replace(inlineMathPattern, in: html, template: "<code>\\$$1\\$</code>")

        // Rich editors drop `<input>` checkboxes.
        html = html.replacingOccurrences(
            of: "<input type=\"checkbox\" checked disabled>", with: "☑")
        html = html.replacingOccurrences(
            of: "<input type=\"checkbox\" disabled>", with: "☐")

        html = html.replacingOccurrences(of: "<pre>", with: "<pre style=\"\(monospace)\">")
        html = html.replacingOccurrences(of: "<code>", with: "<code style=\"\(monospace)\">")
        return html
    }

    private static func replace(_ regex: NSRegularExpression, in html: String, template: String) -> String {
        regex.stringByReplacingMatches(
            in: html,
            range: NSRange(html.startIndex..., in: html),
            withTemplate: template)
    }
}
