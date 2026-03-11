import SwiftUI

struct ContentView: View {
    let document: MarkdownDocument
    let baseURL: URL?

    var body: some View {
        let html = HTMLTemplate.wrap(body: MarkdownRenderer.render(document.text))
        WebView(html: html, baseURL: baseURL)
            .frame(minWidth: 500, minHeight: 400)
    }
}
