import Foundation

/// State lives only in local defaults and is never sent.
enum SupportAsk {

    enum Answer {
        case support, alreadySupported
    }

    static let supportURL = URL(literal: "https://readdown.app/support?src=update")

    /// Overridable so tests don't touch the app's shared defaults.
    static var store: UserDefaults = .standard

    static let enabledKey = "supportAskEnabled"

    static var isEnabled: Bool { store.object(forKey: enabledKey) as? Bool ?? true }

    static func shouldShow(launch: LaunchHistory.Launch, consentPromptDue: Bool) -> Bool {
        isEnabled && launch.isUpdate && !consentPromptDue
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
