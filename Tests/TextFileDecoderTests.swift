import XCTest
@testable import ReadDown

final class TextFileDecoderTests: XCTestCase {

    func testUTF8() throws {
        let data = "Hello, world!".data(using: .utf8)!
        let result = try TextFileDecoder.decode(data)
        XCTAssertEqual(result, "Hello, world!")
    }

    func testUTF8WithEmoji() throws {
        let data = "Hello 🌍".data(using: .utf8)!
        let result = try TextFileDecoder.decode(data)
        XCTAssertEqual(result, "Hello 🌍")
    }

    func testUTF16() throws {
        let data = "Héllo wörld".data(using: .utf16)!
        let result = try TextFileDecoder.decode(data)
        XCTAssertTrue(result.contains("Héllo"))
    }

    func testNonUTF8FallbackDoesNotThrow() throws {
        // Data that's invalid UTF-8 should still decode via fallback
        var data = "hello".data(using: .utf8)!
        data.append(contentsOf: [0xe9, 0xf1, 0xfc]) // Latin-1 accented chars
        XCTAssertNil(String(data: data, encoding: .utf8))
        let result = try TextFileDecoder.decode(data)
        XCTAssertFalse(result.isEmpty)
    }

    func testWindowsCP1252() throws {
        let data = "smart quotes".data(using: .windowsCP1252)!
        let result = try TextFileDecoder.decode(data)
        XCTAssertEqual(result, "smart quotes")
    }

    func testEmptyData() throws {
        let data = Data()
        let result = try TextFileDecoder.decode(data)
        XCTAssertEqual(result, "")
    }
}
