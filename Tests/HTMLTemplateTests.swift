import XCTest
@testable import ReadDown

final class HTMLTemplateTests: XCTestCase {

    func testWrapsBodyInHTML() {
        let result = HTMLTemplate.wrap(body: "<p>Hello</p>")
        XCTAssertTrue(result.contains("<!DOCTYPE html>"))
        XCTAssertTrue(result.contains("<html>"))
        XCTAssertTrue(result.contains("</html>"))
        XCTAssertTrue(result.contains("<p>Hello</p>"))
    }

    func testIncludesDarkModeSupport() {
        let result = HTMLTemplate.wrap(body: "")
        XCTAssertTrue(result.contains("prefers-color-scheme: dark"))
        XCTAssertTrue(result.contains("color-scheme\" content=\"light dark"))
    }

    func testIncludesCharsetMeta() {
        let result = HTMLTemplate.wrap(body: "")
        XCTAssertTrue(result.contains("charset=\"utf-8\"") || result.contains("charset=utf-8"))
    }

    func testIncludesTaskListStyles() {
        let result = HTMLTemplate.wrap(body: "")
        XCTAssertTrue(result.contains("task-list"))
        XCTAssertTrue(result.contains("task-item"))
    }

    func testInjectsMathJaxWhenHasMath() {
        let result = HTMLTemplate.wrap(
            body: "<span class=\"rd-math rd-math-inline\">x^2</span>", hasMath: true)
        // Config emitted before the bundle, plus our explicit conversion call.
        XCTAssertTrue(result.contains("window.MathJax = {"))
        XCTAssertTrue(result.contains("MathJax.tex2svg("))
        XCTAssertTrue(result.contains("enableAssistiveMml: false"))
        XCTAssertTrue(result.contains("enableMenu: false"))
    }

    func testNoMathJaxWhenNoMath() {
        let result = HTMLTemplate.wrap(body: "<p>no math here</p>", hasMath: false)
        XCTAssertFalse(result.contains("window.MathJax"))
        XCTAssertFalse(result.contains("MathJax.tex2svg("))
    }

    func testMathStylesAlwaysPresent() {
        let result = HTMLTemplate.wrap(body: "")
        XCTAssertTrue(result.contains("rd-math-display"))
    }
}
