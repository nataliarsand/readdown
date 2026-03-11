import Foundation

enum TextFileDecoder {
    private static let fallbackEncodings: [String.Encoding] = [
        .utf8,
        .utf16,
        .utf16LittleEndian,
        .utf16BigEndian,
        .utf32,
        .utf32LittleEndian,
        .utf32BigEndian,
        .windowsCP1252,
        .isoLatin1,
        .macOSRoman
    ]

    static func decode(_ data: Data) throws -> String {
        for encoding in fallbackEncodings {
            if let string = String(data: data, encoding: encoding) {
                return string
            }
        }

        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
}
