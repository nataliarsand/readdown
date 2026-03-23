import Foundation

enum TextFileDecoder {
    static func decode(_ data: Data) throws -> String {
        // Try UTF-8 first (most common)
        if let string = String(data: data, encoding: .utf8) {
            return string
        }

        // Try BOM-based encodings (UTF-16/32 only make sense with a BOM)
        if data.count >= 2 {
            let b0 = data[0], b1 = data[1]
            // UTF-16 BOM
            if (b0 == 0xFE && b1 == 0xFF) || (b0 == 0xFF && b1 == 0xFE) {
                if let string = String(data: data, encoding: .utf16) {
                    return string
                }
            }
            // UTF-32 BOM
            if data.count >= 4 {
                let b2 = data[2], b3 = data[3]
                if (b0 == 0x00 && b1 == 0x00 && b2 == 0xFE && b3 == 0xFF)
                    || (b0 == 0xFF && b1 == 0xFE && b2 == 0x00 && b3 == 0x00) {
                    if let string = String(data: data, encoding: .utf32) {
                        return string
                    }
                }
            }
        }

        // Fall back to legacy single-byte encodings
        for encoding: String.Encoding in [.windowsCP1252, .isoLatin1, .macOSRoman] {
            if let string = String(data: data, encoding: encoding) {
                return string
            }
        }

        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
}
