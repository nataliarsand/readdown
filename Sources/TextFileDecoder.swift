import Foundation

enum TextFileDecoder {
    static func decode(_ data: Data) throws -> String {
        // A BOM decodes as a leading U+FEFF, which would hide a first-line `# heading`.
        func stripBOM(_ s: String) -> String {
            s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s
        }

        if let string = String(data: data, encoding: .utf8) {
            return stripBOM(string)
        }

        // UTF-32 before UTF-16: its LE BOM (FF FE 00 00) starts with the UTF-16 LE BOM.
        if data.count >= 2 {
            let b0 = data[0], b1 = data[1]
            if data.count >= 4 {
                let b2 = data[2], b3 = data[3]
                if (b0 == 0x00 && b1 == 0x00 && b2 == 0xFE && b3 == 0xFF)
                    || (b0 == 0xFF && b1 == 0xFE && b2 == 0x00 && b3 == 0x00) {
                    if let string = String(data: data, encoding: .utf32) {
                        return stripBOM(string)
                    }
                }
            }
            if (b0 == 0xFE && b1 == 0xFF) || (b0 == 0xFF && b1 == 0xFE) {
                if let string = String(data: data, encoding: .utf16) {
                    return stripBOM(string)
                }
            }
        }

        for encoding: String.Encoding in [.windowsCP1252, .isoLatin1, .macOSRoman] {
            if let string = String(data: data, encoding: encoding) {
                return stripBOM(string)
            }
        }

        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
}
