import XCTest
@testable import ReadDown

final class UsageMetricsTests: XCTestCase {

    // An isolated suite: the test runner is hosted by the app, so touching
    // UserDefaults.standard would wipe the real install's consent and counts.
    private static let suiteName = "com.heya.readdown.usage-metrics-tests"
    private var testStore: UserDefaults!

    override func setUp() {
        super.setUp()
        testStore = UserDefaults(suiteName: Self.suiteName)
        testStore.removePersistentDomain(forName: Self.suiteName)
        UsageMetrics.store = testStore
    }

    override func tearDown() {
        testStore.removePersistentDomain(forName: Self.suiteName)
        UsageMetrics.store = .standard
        super.tearDown()
    }

    private var storedCounts: [String: Int]? {
        testStore.dictionary(forKey: "usageMetricsCounts") as? [String: Int]
    }

    // MARK: - Consent gating

    func testNothingIsCountedWithoutConsent() {
        UsageMetrics.record(.copyFile)
        UsageMetrics.record(.findInDocument)
        XCTAssertNil(storedCounts, "declined or unasked users must accumulate nothing, even locally")
    }

    func testRecordCountsAfterConsent() {
        UsageMetrics.setConsent(true)
        UsageMetrics.record(.copyFile)
        UsageMetrics.record(.copyFile)
        UsageMetrics.record(.showInFinder)
        XCTAssertEqual(storedCounts?["copy_file"], 2)
        XCTAssertEqual(storedCounts?["show_in_finder"], 1)
    }

    func testWithdrawingConsentDiscardsPendingCounts() {
        UsageMetrics.setConsent(true)
        UsageMetrics.record(.printDocument)
        UsageMetrics.setConsent(false)
        XCTAssertNil(storedCounts)
        UsageMetrics.record(.printDocument)
        XCTAssertNil(storedCounts, "counting must stop the moment consent is withdrawn")
    }

    func testConsentAnswerMarksPromptAsAnswered() {
        XCTAssertFalse(UsageMetrics.wasPrompted)
        UsageMetrics.setConsent(false)
        XCTAssertTrue(UsageMetrics.wasPrompted)
    }

    // MARK: - Payload contract (what the consent prompt promises)

    func testPayloadCarriesOnlyVersionOsAndCounts() {
        let payload = UsageMetrics.payload(counts: ["find": 3])
        XCTAssertEqual(Set(payload.keys), ["version", "os", "counts"],
                       "any new payload field is a privacy-contract change and must be deliberate")
        XCTAssertEqual(payload["counts"] as? [String: Int], ["find": 3])
    }

    func testPayloadOsIsMajorMinorOnly() {
        // Patch version could narrow the anonymity set for rare configs.
        let os = UsageMetrics.payload(counts: [:])["os"] as? String ?? ""
        XCTAssertEqual(os.split(separator: ".").count, 2)
    }
}
