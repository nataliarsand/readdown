import Foundation

/// State lives only in local defaults and is never sent.
enum SupportAsk {

    enum Answer {
        case support, later, alreadySupported
    }

    static let supportURL = URL(string: "https://readdown.app/support?src=update")!

    /// Overridable so tests don't touch the app's shared defaults.
    static var store: UserDefaults = .standard

    static let enabledKey = "supportAskEnabled"
    private static let answerKeys: [Answer: String] = [
        .support: "supportAskSupportAt",
        .later: "supportAskLaterAt",
        .alreadySupported: "supportAskAlreadyAt",
    ]

    private static let day: TimeInterval = 24 * 60 * 60
    static let minimumInstallAge = 28 * day
    static let quietPeriods: [Answer: TimeInterval] = [
        .support: 180 * day,
        .later: 90 * day,
        .alreadySupported: 365 * day,
    ]

    static var isEnabled: Bool { store.object(forKey: enabledKey) as? Bool ?? true }

    static func record(_ answer: Answer, at date: Date = Date()) {
        guard let key = answerKeys[answer] else { return }
        store.set(date, forKey: key)
    }

    static func shouldShow(launch: LaunchHistory.Launch, installDate: Date,
                           consentPromptDue: Bool, now: Date = Date()) -> Bool {
        guard isEnabled, launch.isUpdate, !launch.isPatchRelease, !consentPromptDue else { return false }
        guard now.timeIntervalSince(installDate) >= minimumInstallAge else { return false }
        return quietPeriods.allSatisfy { answer, quiet in
            guard let key = answerKeys[answer], let at = store.object(forKey: key) as? Date else { return true }
            return now.timeIntervalSince(at) >= quiet
        }
    }

    /// The sandbox container is created on first launch, so its age is the install age.
    static var installDate: Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: NSHomeDirectory())
        return attributes?[.creationDate] as? Date ?? Date()
    }
}

/// Read once per launch: the stored build is overwritten as soon as it's read.
enum LaunchHistory {

    struct Launch {
        let previousBuild: String?
        let currentBuild: String
        let version: String

        var isFreshInstall: Bool { previousBuild == nil }
        var isUpdate: Bool { previousBuild.map { $0 != currentBuild } ?? false }
        /// 1.18.1 is a patch release; 1.18 and 1.18.0 are not.
        var isPatchRelease: Bool {
            let parts = version.split(separator: ".")
            return parts.count > 2 && parts[2] != "0"
        }
    }

    static let lastBuildKey = "lastLaunchedBuild"
    static let unknownBuild = "unknown"
    /// Builds before 1.19 stored the build only when the Welcome window appeared, so for most
    /// existing users it's missing; any of these keys proves an earlier launch.
    private static let priorUseKeys = ["usageMetricsPrompted", "hasPromptedDefault", "openDocumentBookmarks"]

    static let current: Launch = record(
        in: .standard,
        build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    )

    static func record(in store: UserDefaults, build: String, version: String) -> Launch {
        var previous = store.string(forKey: lastBuildKey)
        if previous == nil, priorUseKeys.contains(where: { store.object(forKey: $0) != nil }) {
            previous = unknownBuild
        }
        store.set(build, forKey: lastBuildKey)
        return Launch(previousBuild: previous, currentBuild: build, version: version)
    }
}
