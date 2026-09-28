import Foundation

/// One scheme policy for the renderer (what becomes an `<a>`) and the web view (what a click may do).
enum LinkScheme {

    enum Kind: Equatable {
        case relative          // no scheme: resolved against the document
        case web               // http, https, mailto: opens without asking
        case custom(String)    // any other well-formed scheme: opens only after a confirmation
        case denied            // runs code or automation, reaches files, shares or hosts, or drives system panes
    }

    /// Exact matches; `deniedPrefixes` covers the families (`ftp*`, `ms-*`, `x-apple.*`).
    static let deniedSchemes: Set<String> = [
        "file", "smb", "afp", "nfs", "cifs", "sftp", "tftp",
        "ssh", "telnet", "vnc", "x-man-page",
        "javascript", "vbscript", "data", "blob", "about",
        "applescript", "shortcuts", "help"
    ]
    static let deniedPrefixes = ["ftp", "ms-", "x-apple"]

    private static let webSchemes: Set<String> = ["http", "https", "mailto"]

    static func kind(of url: String) -> Kind {
        guard let scheme = scheme(of: url) else { return .relative }
        if isDenied(scheme) { return .denied }
        if webSchemes.contains(scheme) { return .web }
        return .custom(scheme)
    }

    static func isDenied(_ scheme: String) -> Bool {
        let s = scheme.lowercased()
        return deniedSchemes.contains(s) || deniedPrefixes.contains { s.hasPrefix($0) }
    }

    /// CommonMark's autolink scheme: 2–32 chars, letter first, then letters, digits, `+`, `.`, `-`.
    /// Anything shorter is a Windows drive letter, not a scheme.
    static func scheme(of url: String) -> String? {
        guard let colon = url.firstIndex(of: ":") else { return nil }
        let candidate = url[..<colon]
        guard (2...32).contains(candidate.count),
              let first = candidate.first, first.isASCII, first.isLetter,
              candidate.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "." || $0 == "-") })
        else { return nil }
        return candidate.lowercased()
    }
}
