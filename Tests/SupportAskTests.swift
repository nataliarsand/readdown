import XCTest
@testable import ReadDown

final class SupportAskTests: XCTestCase {

    // The runner is hosted by the app: UserDefaults.standard would overwrite the real install's state.
    private static let suiteName = "com.heya.readdown.support-ask-tests"
    private var testStore: UserDefaults!
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    override func setUp() {
        super.setUp()
        testStore = UserDefaults(suiteName: Self.suiteName)
        testStore.removePersistentDomain(forName: Self.suiteName)
        SupportAsk.store = testStore
    }

    override func tearDown() {
        testStore.removePersistentDomain(forName: Self.suiteName)
        SupportAsk.store = .standard
        super.tearDown()
    }

    private func update(version: String = "1.19") -> LaunchHistory.Launch {
        LaunchHistory.Launch(previousBuild: "20", currentBuild: "21", version: version)
    }

    private func shows(_ launch: LaunchHistory.Launch, installedDaysAgo: Double = 60, consentDue: Bool = false) -> Bool {
        SupportAsk.shouldShow(launch: launch, installDate: now.addingTimeInterval(-installedDaysAgo * day),
                              consentPromptDue: consentDue, now: now)
    }

    func testShowsAfterUpdateForEstablishedInstall() {
        XCTAssertTrue(shows(update()))
    }

    func testNeverOnFreshInstallSameBuildPatchOrConsentLaunch() {
        XCTAssertFalse(shows(LaunchHistory.Launch(previousBuild: nil, currentBuild: "21", version: "1.19")))
        XCTAssertFalse(shows(LaunchHistory.Launch(previousBuild: "21", currentBuild: "21", version: "1.19")))
        XCTAssertFalse(shows(update(version: "1.19.1")))
        XCTAssertFalse(shows(update(), consentDue: true))
        XCTAssertFalse(shows(update(), installedDaysAgo: 10))
    }

    func testQuietPeriodsPerAnswer() {
        SupportAsk.record(.later, at: now.addingTimeInterval(-89 * day))
        XCTAssertFalse(shows(update()))
        SupportAsk.record(.later, at: now.addingTimeInterval(-91 * day))
        XCTAssertTrue(shows(update()))
        SupportAsk.record(.alreadySupported, at: now.addingTimeInterval(-300 * day))
        XCTAssertFalse(shows(update()))
    }

    func testToggleOffSilencesIt() {
        testStore.set(false, forKey: SupportAsk.enabledKey)
        XCTAssertFalse(shows(update()))
    }

    func testMissingBuildWithPriorUseCountsAsUpdate() {
        testStore.set(true, forKey: "usageMetricsPrompted")
        let launch = LaunchHistory.record(in: testStore, build: "21", version: "1.19")
        XCTAssertTrue(launch.isUpdate)
        XCTAssertFalse(LaunchHistory.record(in: testStore, build: "21", version: "1.19").isUpdate)
    }

    func testFirstEverLaunchIsFreshInstall() {
        XCTAssertTrue(LaunchHistory.record(in: testStore, build: "21", version: "1.19").isFreshInstall)
    }
}
