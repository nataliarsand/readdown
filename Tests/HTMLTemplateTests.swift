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
}
