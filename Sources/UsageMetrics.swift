import AppKit
import Foundation

/// Opt-in, anonymous feature-usage counters. Inert until the user consents.
enum UsageMetrics {

    enum Feature: String {
        case copyFile = "copy_file"
        case copyCodeBlock = "copy_code"
        case findInDocument = "find"
        case showInFinder = "show_in_finder"
        case printDocument = "print"
        case exportPDF = "export_pdf"
        case zoom = "zoom"
        case documentOpened = "open_document"
        case consentGranted = "consent_granted"
    }

    /// Overridable so tests don't touch the app's shared defaults.
    static var store: UserDefaults = .standard

    static let consentKey = "usageMetricsConsent"
    private static let promptedKey = "usageMetricsPrompted"
    private static let countsKey = "usageMetricsCounts"
    private static let lastSendKey = "usageMetricsLastSend"
    // Hidden per-machine opt-out for developer/QA builds, so my own usage never
    // pollutes the aggregate. Set once per Mac:
    //   defaults write com.heya.readdown usageMetricsDevOptOut -bool YES
    private static let devOptOutKey = "usageMetricsDevOptOut"
    private static let endpoint = URL(string: "https://readdown.app/api/track-usage")!
    private static let sendInterval: TimeInterval = 24 * 60 * 60

    static var hasConsent: Bool { store.bool(forKey: consentKey) }
    static var wasPrompted: Bool { store.bool(forKey: promptedKey) }
    /// A machine that has opted out of contributing (developer QA). When set,
    /// nothing is recorded or transmitted — consent semantics are unchanged for
    /// everyone else.
    static var isSuppressed: Bool { store.bool(forKey: devOptOutKey) }

    static func setConsent(_ granted: Bool) {
        store.set(granted, forKey: consentKey)
        store.set(true, forKey: promptedKey)
        if !granted {
            store.removeObject(forKey: countsKey)
        }
    }

    static func record(_ feature: Feature) {
        guard hasConsent, !isSuppressed else { return }
        var counts = store.dictionary(forKey: countsKey) as? [String: Int] ?? [:]
        counts[feature.rawValue, default: 0] += 1
        store.set(counts, forKey: countsKey)
    }

    /// Counts reset only after a confirmed send, so an offline day rolls forward.
    static func sendIfDue(now: Date = Date()) {
        guard hasConsent, !isSuppressed else { return }
        let counts = store.dictionary(forKey: countsKey) as? [String: Int] ?? [:]
        guard !counts.isEmpty else { return }
        let last = store.object(forKey: lastSendKey) as? Date ?? .distantPast
        guard now.timeIntervalSince(last) >= sendInterval else { return }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload(counts: counts))

        URLSession.shared.dataTask(with: request) { _, response, _ in
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            DispatchQueue.main.async {
                store.removeObject(forKey: countsKey)
                store.set(now, forKey: lastSendKey)
            }
        }.resume()
    }

    static func payload(counts: [String: Int]) -> [String: Any] {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return [
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            "os": "\(os.majorVersion).\(os.minorVersion)",
            "counts": counts,
        ]
    }

    /// Asks once; the Help-menu toggle takes over after any answer.
    static func promptForConsentIfNeeded() {
        guard !wasPrompted, !hasConsent else { return }
        store.set(true, forKey: promptedKey)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Help make Readdown better"
        alert.informativeText = """
        Share anonymous usage stats so updates focus on what you actually use.

        Just feature counts, nothing else. No identifiers, and your documents \
        never leave your Mac.

        Change your mind anytime in the Help menu.
        """
        alert.addButton(withTitle: "Count Me In")
        alert.addButton(withTitle: "No Thanks")
        let dialogFrame = alert.window.frame
        let granted = alert.runModal() == .alertFirstButtonReturn
        setConsent(granted)
        if granted {
            record(.consentGranted)
            ThanksPop.show(centeredIn: NSApp.mainWindow?.frame ?? dialogFrame)
        }
    }
}
