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

    func testUTF32LittleEndian() throws {
        // FF FE 00 00 starts with the UTF-16LE BOM, so UTF-32 must be tested first.
        var data = Data([0xFF, 0xFE, 0x00, 0x00])
        data.append(contentsOf: [0x48, 0x00, 0x00, 0x00, 0x69, 0x00, 0x00, 0x00]) // "Hi"
        let result = try TextFileDecoder.decode(data)
        XCTAssertEqual(result, "Hi")
    }

    func testUTF32BigEndian() throws {
        var data = Data([0x00, 0x00, 0xFE, 0xFF])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x48, 0x00, 0x00, 0x00, 0x69]) // "Hi"
        let result = try TextFileDecoder.decode(data)
        XCTAssertEqual(result, "Hi")
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

    func testUTF8BOMIsStripped() throws {
        // A UTF-8 file saved with a BOM must not keep the leading U+FEFF, or an
        // invisible char precedes the content and a first-line heading fails to parse.
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append("# Heading".data(using: .utf8)!)
        let result = try TextFileDecoder.decode(data)
        XCTAssertEqual(result, "# Heading")
        XCTAssertFalse(result.hasPrefix("\u{FEFF}"))
    }
}
