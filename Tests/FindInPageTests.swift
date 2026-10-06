import PDFKit
import WebKit
import XCTest
@testable import ReadDown

/// Drives the real in-page JavaScript inside a WKWebView, on the same HTML the app ships.
final class FindInPageTests: XCTestCase {

    // MARK: - Harness

    private func loadDocument(
        _ markdown: String,
        palette: ReaderThemePalette? = nil
    ) -> WKWebView {
        let result = MarkdownRenderer.render(markdown)
        let html = HTMLTemplate.wrap(
            body: result.html,
            hasMermaid: result.hasMermaid,
            hasMath: result.hasMath,
            palette: palette
        )
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        webView.loadHTMLString(html, baseURL: nil)
        waitUntilTrue(webView, "typeof window.__rdFind === 'object'")
        return webView
    }

    private func waitUntilTrue(_ webView: WKWebView, _ js: String,
                               timeout: TimeInterval = 10,
                               file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (evaluate(webView, js) as? Bool) == true { return }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        XCTFail("Timed out waiting for: \(js)", file: file, line: line)
    }

    @discardableResult
    private func evaluate(_ webView: WKWebView, _ js: String) -> Any? {
        var value: Any?
        var finished = false
        webView.evaluateJavaScript(js) { result, _ in
            value = result
            finished = true
        }
        while !finished {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return value
    }

    private func findCounts(_ webView: WKWebView, _ call: String) -> (total: Int, current: Int) {
        let dict = evaluate(webView, "window.__rdFind.\(call)") as? [String: Any]
        return (dict?["total"] as? Int ?? -1, dict?["current"] as? Int ?? -1)
    }

    func testSearchCountsAllMatches() {
        let webView = loadDocument("alpha beta alpha\n\nAnother alpha here.")
        let counts = findCounts(webView, "search('alpha')")
        XCTAssertEqual(counts.total, 3)
        XCTAssertEqual(counts.current, 1)
    }

    func testSearchIsCaseInsensitive() {
        let webView = loadDocument("Alpha ALPHA alpha")
        XCTAssertEqual(findCounts(webView, "search('alpha')").total, 3)
    }

    func testNextAdvancesAndWrapsAround() {
        let webView = loadDocument("one two one two one")
        _ = findCounts(webView, "search('one')")
        XCTAssertEqual(findCounts(webView, "next()").current, 2)
        XCTAssertEqual(findCounts(webView, "next()").current, 3)
        XCTAssertEqual(findCounts(webView, "next()").current, 1)  // wraps
    }

    func testPreviousWrapsBackwards() {
        let webView = loadDocument("one two one")
        _ = findCounts(webView, "search('one')")
        XCTAssertEqual(findCounts(webView, "prev()").current, 2)  // wraps to last
    }

    func testNoMatchesReturnsZero() {
        let webView = loadDocument("nothing to see")
        let counts = findCounts(webView, "search('zebra')")
        XCTAssertEqual(counts.total, 0)
        XCTAssertEqual(counts.current, 0)
    }

    func testClearRemovesAllHighlights() {
        let webView = loadDocument("match match")
        _ = findCounts(webView, "search('match')")
        _ = evaluate(webView, "window.__rdFind.clear()")
        let marks = evaluate(webView, "document.querySelectorAll('mark.rd-find').length") as? Int
        XCTAssertEqual(marks, 0)
    }

    func testCopyButtonInjectedPerFencedBlock() {
        let webView = loadDocument("""
        ```swift
        let a = 1
        ```

        prose between

        ```python
        b = 2
        ```
        """)
        let buttons = evaluate(webView, "document.querySelectorAll('.rd-copy-btn').length") as? Int
        XCTAssertEqual(buttons, 2)
        let label = evaluate(
            webView,
            "document.querySelector('.rd-copy-btn').getAttribute('aria-label')"
        ) as? String
        XCTAssertEqual(label, "Copy code")
    }

    func testNoCopyButtonOnMermaidBlocks() {
        let webView = loadDocument("""
        ```mermaid
        graph TD; A-->B;
        ```
        """)
        let buttons = evaluate(webView, "document.querySelectorAll('.rd-copy-btn').length") as? Int
        XCTAssertEqual(buttons, 0)
    }

    func testHighlightedCodeKeepsTheBlockBackground() {
        let webView = loadDocument("```swift\nlet x = 1\n```")
        let bg = evaluate(webView, "getComputedStyle(document.querySelector('pre code.hljs')).backgroundColor") as? String
        XCTAssertEqual(bg, "rgba(0, 0, 0, 0)")
    }

    func testCodeCopyButtonUsesTheSharedCheck() {
        let webView = loadDocument("```\nx\n```")
        let svg = evaluate(webView, "document.querySelector('.rd-copy-btn').click(), document.querySelector('.rd-copy-btn').innerHTML") as? String
        XCTAssertEqual(svg, CheckIcon.svg)
    }

    private func selectAllAndExport(_ webView: WKWebView) -> String? {
        evaluate(webView, """
        (function() {
            getSelection().selectAllChildren(document.body);
            return window.__rdCopy.htmlForSelection();
        })()
        """) as? String
    }

    func testSelectionCopyStripsClassesAndChrome() {
        let webView = loadDocument("""
        # Title

        | A | B |
        |---|---|
        | 1 | 2 |

        - [ ] open
        - [x] done
        """)
        let html = selectAllAndExport(webView) ?? ""
        XCTAssertTrue(html.contains("<h1>"))
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertFalse(html.contains("class="))
        XCTAssertFalse(html.contains("rd-fold"))
        XCTAssertFalse(html.contains("<svg"))
        XCTAssertFalse(html.contains("<input"))
        XCTAssertTrue(html.contains("☐"))
        XCTAssertTrue(html.contains("☑"))
    }

    func testSelectionCopyKeepsLinksAndImages() {
        let webView = loadDocument("[site](https://example.com) and ![alt text](pic.png)")
        let html = selectAllAndExport(webView) ?? ""
        XCTAssertTrue(html.contains("href=\"https://example.com\""))
        XCTAssertTrue(html.contains("alt=\"alt text\""))
    }

    func testSelectionCopyStylesCodeMonospace() {
        let webView = loadDocument("""
        ```swift
        let a = 1
        ```
        """)
        let html = selectAllAndExport(webView) ?? ""
        XCTAssertTrue(html.contains("Courier New"))
        XCTAssertTrue(html.contains("let a = 1"), "got: \(html)")
        XCTAssertFalse(html.contains("rd-copy-btn"))
        XCTAssertFalse(html.contains("<button"))
        XCTAssertFalse(html.contains("<span"))
    }

    /// cloneContents alone would return bare text.
    func testSelectionInsideHeadingExportsHeadingTag() {
        let webView = loadDocument("# Alphabet Soup")
        let html = evaluate(webView, """
        (function() {
            var h = document.querySelector('h1');
            var t = h.lastChild;
            var r = document.createRange();
            r.setStart(t, 0); r.setEnd(t, 8);
            var s = getSelection(); s.removeAllRanges(); s.addRange(r);
            return window.__rdCopy.htmlForSelection();
        })()
        """) as? String ?? ""
        XCTAssertTrue(html.contains("<h1>"), "got: \(html)")
    }

    func testSelectionCopyExportsMathAsTeX() {
        let webView = loadDocument("Euler: $e^{i\\pi} = -1$")
        waitUntilTrue(webView, "document.querySelectorAll('.katex').length >= 1")
        let html = selectAllAndExport(webView) ?? ""
        XCTAssertTrue(html.contains("$e^{i\\pi} = -1$"), "got: \(html)")
        XCTAssertFalse(html.contains("katex"))
    }

    func testSelectionCopyExportsMermaidSource() {
        let webView = loadDocument("""
        ```mermaid
        graph TD; A-->B;
        ```
        """)
        waitUntilTrue(webView, "document.querySelectorAll('pre.mermaid svg').length >= 1")
        let html = selectAllAndExport(webView) ?? ""
        XCTAssertTrue(html.contains("graph TD"), "got: \(html)")
        XCTAssertFalse(html.contains("<svg"))
    }

    func testCopyEventRewritesClipboardData() {
        let webView = loadDocument("# Title\n\nBody text.")
        let json = evaluate(webView, """
        (function() {
            var captured = null;
            document.addEventListener('copy', function(e) {
                captured = { prevented: e.defaultPrevented, html: e.clipboardData.getData('text/html') };
            });
            getSelection().selectAllChildren(document.body);
            document.execCommand('copy');
            return JSON.stringify(captured);
        })()
        """) as? String ?? ""
        XCTAssertTrue(json.contains("\"prevented\":true"), "got: \(json)")
        XCTAssertTrue(json.contains("<h1>"), "got: \(json)")
    }

    func testSelectionInsideTableCellExportsPlainText() {
        let webView = loadDocument("| Alpha | Beta |\n|---|---|\n| gamma | delta |")
        let html = evaluate(webView, """
        (function() {
            var td = document.querySelector('td');
            var r = document.createRange();
            r.selectNodeContents(td);
            var s = getSelection(); s.removeAllRanges(); s.addRange(r);
            return window.__rdCopy.htmlForSelection();
        })()
        """) as? String ?? ""
        XCTAssertFalse(html.contains("<table"), "got: \(html)")
        XCTAssertTrue(html.contains("gamma"))
    }

    func testSelectionInsideListItemExportsPlainText() {
        let webView = loadDocument("- first bullet\n- second bullet")
        let html = evaluate(webView, """
        (function() {
            var li = document.querySelector('li');
            var r = document.createRange();
            r.selectNodeContents(li);
            var s = getSelection(); s.removeAllRanges(); s.addRange(r);
            return window.__rdCopy.htmlForSelection();
        })()
        """) as? String ?? ""
        XCTAssertFalse(html.contains("<li"), "got: \(html)")
        XCTAssertTrue(html.contains("first bullet"))
    }

    func testSelectionAcrossCellsKeepsTable() {
        let webView = loadDocument("| Alpha | Beta |\n|---|---|\n| gamma | delta |")
        let html = evaluate(webView, """
        (function() {
            var r = document.createRange();
            r.selectNodeContents(document.querySelector('tbody tr'));
            var s = getSelection(); s.removeAllRanges(); s.addRange(r);
            return window.__rdCopy.htmlForSelection();
        })()
        """) as? String ?? ""
        XCTAssertTrue(html.contains("<table>"), "got: \(html)")
        XCTAssertTrue(html.contains("<td>"))
    }

    func testCollapsedSectionExcludedFromExport() {
        let webView = loadDocument("# One\n\nvisible text\n\n# Two\n\nhidden text")
        let html = evaluate(webView, """
        (function() {
            var folds = document.querySelectorAll('.rd-fold');
            folds[folds.length - 1].click();
            getSelection().selectAllChildren(document.body);
            return window.__rdCopy.htmlForSelection();
        })()
        """) as? String ?? ""
        XCTAssertTrue(html.contains("visible text"), "got: \(html)")
        XCTAssertFalse(html.contains("hidden text"), "got: \(html)")
    }

    func testCollapsedSelectionExportsNothing() {
        let webView = loadDocument("Some text")
        let result = evaluate(webView, """
        (function() {
            getSelection().removeAllRanges();
            return window.__rdCopy.htmlForSelection() === null;
        })()
        """) as? Bool
        XCTAssertEqual(result, true)
    }

    func testMermaidFlowchartDynamicallyWrapsLongLabels() {
        let webView = loadDocument("""
        ```mermaid
        graph TB
            subgraph L1["Presentation Layer"]
                Preview["Synthetic document<br/>Preview surface"]
            end

            subgraph L2["Integration Layer"]
                Adapter["SyntheticBridgePlugin<br/>+ SyntheticBridgeViewModel extension<br/>No additional domain model is created"]
            end

            Preview -->|"Synthetic event"| Adapter
        ```
        """)
        waitUntilTrue(webView, "document.querySelector('pre.mermaid svg') !== null")

        let geometry = evaluate(webView, """
        (() => {
            const svg = document.querySelector('pre.mermaid svg');
            const node = Array.from(svg.querySelectorAll('g.node')).find(
                candidate => candidate.textContent.includes('SyntheticBridgePlugin')
            );
            const label = node.querySelector('.nodeLabel');
            const paragraph = label.querySelector('p');
            const box = node.querySelector('foreignObject');
            const boxRect = box.getBoundingClientRect();
            const walker = document.createTreeWalker(label, NodeFilter.SHOW_TEXT);
            const textRects = [];
            while (walker.nextNode()) {
                const range = document.createRange();
                range.selectNodeContents(walker.currentNode);
                textRects.push(...range.getClientRects());
            }
            const tolerance = 0.5;
            const isClipped = textRects.some(rect =>
                rect.left < boxRect.left - tolerance
                    || rect.right > boxRect.right + tolerance
                    || rect.top < boxRect.top - tolerance
                    || rect.bottom > boxRect.bottom + tolerance
            );
            const paragraphStyle = getComputedStyle(paragraph);
            return {
                isClipped,
                whiteSpace: paragraphStyle.whiteSpace,
                overflowWrap: paragraphStyle.overflowWrap,
                boxHeight: box.height.baseVal.value,
                lineHeight: parseFloat(paragraphStyle.lineHeight)
            };
        })()
        """) as? [String: Any]

        XCTAssertEqual(geometry?["isClipped"] as? Bool, false, "Mermaid clipped a flowchart label")
        XCTAssertEqual(geometry?["whiteSpace"] as? String, "normal")
        XCTAssertEqual(geometry?["overflowWrap"] as? String, "anywhere")
        let boxHeight = geometry?["boxHeight"] as? Double ?? 0
        let lineHeight = geometry?["lineHeight"] as? Double ?? .infinity
        XCTAssertGreaterThan(boxHeight, lineHeight * 3,
            "Mermaid did not grow the node for dynamically wrapped lines")
    }

    func testMermaidFlowchartUsesReaderThemePalette() {
        let palette = ReaderThemeCatalog.palette(for: .catppuccin, scheme: .light)
        let webView = loadDocument("""
        ```mermaid
        graph TB
            subgraph Cluster["Synthetic Cluster"]
                A["Synthetic Node A"] --> B["Synthetic Node B"]
            end
        ```
        """, palette: palette)
        waitUntilTrue(webView, "document.querySelector('pre.mermaid svg') !== null")

        let styles = evaluate(webView, """
        (() => {
            const svg = document.querySelector('pre.mermaid svg');
            return {
                nodeFill: getComputedStyle(svg.querySelector('g.node rect')).fill,
                nodeStroke: getComputedStyle(svg.querySelector('g.node rect')).stroke,
                clusterFill: getComputedStyle(svg.querySelector('g.cluster rect')).fill,
                clusterStroke: getComputedStyle(svg.querySelector('g.cluster rect')).stroke,
                lineStroke: getComputedStyle(svg.querySelector('.flowchart-link')).stroke,
                nodeText: getComputedStyle(svg.querySelector('.nodeLabel')).color
            };
        })()
        """) as? [String: String]

        XCTAssertEqual(styles?["nodeFill"], "rgb(230, 233, 239)")
        XCTAssertEqual(styles?["nodeStroke"], "rgb(188, 192, 204)")
        XCTAssertEqual(styles?["clusterFill"], "rgb(220, 224, 232)")
        XCTAssertEqual(styles?["clusterStroke"], "rgb(188, 192, 204)")
        XCTAssertEqual(styles?["lineStroke"], "rgb(108, 111, 133)")
        XCTAssertEqual(styles?["nodeText"], "rgb(76, 79, 105)")
    }

    func testMermaidAuthorStylesOverrideReaderThemePalette() {
        let palette = ReaderThemeCatalog.palette(for: .catppuccin, scheme: .light)
        let webView = loadDocument("""
        ```mermaid
        graph TB
            A["Author Styled Node"] --> B["Default Node"]
            style A fill:#123456,stroke:#654321,color:#ffffff
        ```
        """, palette: palette)
        waitUntilTrue(webView, "document.querySelector('pre.mermaid svg') !== null")

        let styles = evaluate(webView, """
        (() => {
            const node = Array.from(document.querySelectorAll('pre.mermaid g.node')).find(
                candidate => candidate.textContent.includes('Author Styled Node')
            );
            return {
                fill: getComputedStyle(node.querySelector('rect')).fill,
                stroke: getComputedStyle(node.querySelector('rect')).stroke,
                text: getComputedStyle(node.querySelector('.nodeLabel')).color
            };
        })()
        """) as? [String: String]

        XCTAssertEqual(styles?["fill"], "rgb(18, 52, 86)")
        XCTAssertEqual(styles?["stroke"], "rgb(101, 67, 33)")
        XCTAssertEqual(styles?["text"], "rgb(255, 255, 255)")
    }

    // MARK: - Print/PDF always renders light (Mermaid dark-on-paper fix)

    /// The print/PDF path renders with the light template so paper never
    /// inherits the dark palette. Exercises the full pipeline the fix uses —
    /// light HTML + a real Mermaid render + `createPDF` — and checks the
    /// resulting PDF's background is light, not the dark page colour.
    func testMermaidPrintPDFBackgroundIsLight() throws {
        let result = MarkdownRenderer.render("""
        # Diagram

        ```mermaid
        flowchart TD
          A[Start] --> B[End]
        ```
        """)
        XCTAssertTrue(result.hasMermaid)
        let html = HTMLTemplate.wrap(body: result.html, hasMermaid: true, isDark: false)
        XCTAssertTrue(html.contains("data-rd-theme=\"light\""))

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        webView.appearance = NSAppearance(named: .aqua)   // matches PrintRenderer
        webView.underPageBackgroundColor = .white
        webView.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
        waitUntilTrue(webView, "document.querySelectorAll('pre.mermaid svg').length >= 1")

        let exp = expectation(description: "createPDF")
        var pdfData: Data?
        webView.createPDF(configuration: WKPDFConfiguration()) { result in
            if case .success(let data) = result { pdfData = data }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10)

        let data = try XCTUnwrap(pdfData, "createPDF produced no data")
        let page = try XCTUnwrap(PDFDocument(data: data)?.page(at: 0))
        let brightness = try cornerBrightness(of: page)
        XCTAssertGreaterThan(brightness, 0.7,
            "print background must be light; brightness \(brightness) suggests the dark palette leaked to paper")
    }

    /// The thumbnail keeps the page aspect ratio; letterbox margins would sample as transparent.
    private func cornerBrightness(of page: PDFPage) throws -> CGFloat {
        let bounds = page.bounds(for: .mediaBox)
        let w: CGFloat = 160
        let h = (w * bounds.height / bounds.width).rounded()
        let image = page.thumbnail(of: NSSize(width: w, height: h), for: .mediaBox)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        // Lower-centre: body background, clear of content and the page edge.
        let color = try XCTUnwrap(
            rep.colorAt(x: Int(w / 2), y: Int(h * 0.7))?.usingColorSpace(.sRGB))
        return color.brightnessComponent
    }
}
