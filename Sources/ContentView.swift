import SwiftUI

struct ContentView: View {
    let html: String
    let baseURL: URL?

    init(document: MarkdownDocument, baseURL: URL?) {
        let result = MarkdownRenderer.render(document.text)
        self.html = HTMLTemplate.wrap(body: result.html, hasMermaid: result.hasMermaid)
        self.baseURL = baseURL
    }

    var body: some View {
        WebView(html: html, baseURL: baseURL)
            .frame(minWidth: 500, minHeight: 400)
    }
}
