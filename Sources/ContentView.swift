import SwiftUI

struct ContentView: View {
    let document: MarkdownDocument

    var body: some View {
        let html = HTMLTemplate.wrap(body: MarkdownRenderer.render(document.text))
        WebView(html: html)
            .frame(minWidth: 500, minHeight: 400)
    }
}
