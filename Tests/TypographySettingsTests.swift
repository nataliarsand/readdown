import AppKit
import SwiftUI
import XCTest
@testable import ReadDown

final class TypographySettingsTests: XCTestCase {
    private static let suiteName = "com.heya.readdown.typography-settings-tests"
    private var store: UserDefaults!

    override func setUp() {
        super.setUp()
        store = UserDefaults(suiteName: Self.suiteName)
        store.removePersistentDomain(forName: Self.suiteName)
    }

    override func tearDown() {
        store.removePersistentDomain(forName: Self.suiteName)
        store = nil
        super.tearDown()
    }

    func testDefaultTypographyMatchesExistingReaderMetrics() {
        let preferences = TypographyPreferences(store: store, postsNotifications: false)
        XCTAssertEqual(preferences.ui, .defaultUI)
        XCTAssertEqual(preferences.body, .defaultBody)
        XCTAssertEqual(preferences.code, .defaultCode)
    }

    func testPersistsEachFontRoleIndependently() {
        let preferences = TypographyPreferences(store: store, postsNotifications: false)
        preferences.update(
            ReaderFontSelection(family: "Helvetica Neue", weight: .semibold, size: 14), for: .ui)
        preferences.update(
            ReaderFontSelection(family: "Avenir Next", weight: .regular, size: 18), for: .body)
        preferences.update(
            ReaderFontSelection(family: "Menlo", weight: .medium, size: 15), for: .code)

        let restored = TypographyPreferences(store: store, postsNotifications: false)
        XCTAssertEqual(restored.ui.family, "Helvetica Neue")
        XCTAssertEqual(restored.ui.weight, .semibold)
        XCTAssertEqual(restored.ui.size, 14)
        XCTAssertEqual(restored.body.family, "Avenir Next")
        XCTAssertEqual(restored.body.size, 18)
        XCTAssertEqual(restored.code.family, "Menlo")
        XCTAssertEqual(restored.code.weight, .medium)
    }

    func testClampsSizesToRoleSpecificRanges() {
        let preferences = TypographyPreferences(store: store, postsNotifications: false)
        preferences.update(
            ReaderFontSelection(family: ReaderFontSelection.systemFamily, weight: .regular, size: 99), for: .ui)
        preferences.update(
            ReaderFontSelection(family: ReaderFontSelection.systemFamily, weight: .regular, size: 2), for: .body)
        XCTAssertEqual(preferences.ui.size, ReaderFontRole.ui.sizeRange.upperBound)
        XCTAssertEqual(preferences.body.size, ReaderFontRole.body.sizeRange.lowerBound)
    }

    func testCustomFamilyIsEscapedForCSS() {
        let selection = ReaderFontSelection(family: "Example\"Font\nName", weight: .bold, size: 17)
        XCTAssertFalse(selection.cssFamily.contains("\n"))
        XCTAssertTrue(selection.cssFamily.contains("Example\\\"Font Name"))
    }

    func testNativeFontPreservesFamilyWeightAndSize() {
        let system = ReaderFontSelection(family: ReaderFontSelection.systemFamily, weight: .bold, size: 17)
        XCTAssertEqual(system.nsFont, NSFont.systemFont(ofSize: 17, weight: .bold))

        let monospaced = ReaderFontSelection(
            family: ReaderFontSelection.monospacedFamily, weight: .semibold, size: 18
        )
        XCTAssertEqual(monospaced.nsFont, NSFont.monospacedSystemFont(ofSize: 18, weight: .semibold))

        let named = ReaderFontSelection(family: "Helvetica Neue", weight: .bold, size: 16).nsFont
        XCTAssertEqual(named.familyName, "Helvetica Neue")
        XCTAssertEqual(named.pointSize, 16)
        XCTAssertTrue(named.fontDescriptor.symbolicTraits.contains(.bold))
    }

    func testTypographyEmitsIndependentCSSVariables() {
        let typography = ReaderTypography(
            ui: ReaderFontSelection(family: "Helvetica Neue", weight: .medium, size: 14),
            body: ReaderFontSelection(family: "Avenir Next", weight: .regular, size: 18),
            code: ReaderFontSelection(family: "Menlo", weight: .semibold, size: 15)
        )
        XCTAssertTrue(typography.cssVariables.contains("--ui-font-size: 14px"))
        XCTAssertTrue(typography.cssVariables.contains("--body-font-weight: 400"))
        XCTAssertTrue(typography.cssVariables.contains("--code-font-family: \"Menlo\""))
        XCTAssertTrue(typography.cssVariables.contains("--code-font-weight: 600"))
    }

    func testSettingsViewUsesThreeNativeFontComboBoxes() {
        let preferences = TypographyPreferences(store: store, postsNotifications: false)
        let hostingView = NSHostingView(rootView: TypographySettingsView(preferences: preferences))
        hostingView.frame = NSRect(x: 0, y: 0, width: 560, height: 420)
        hostingView.layoutSubtreeIfNeeded()

        let comboBoxes = descendants(of: hostingView).compactMap { $0 as? NSComboBox }
        XCTAssertEqual(comboBoxes.count, 3)
        XCTAssertTrue(comboBoxes.allSatisfy { $0.numberOfItems > 2 })
        XCTAssertTrue(comboBoxes.allSatisfy { $0.numberOfVisibleItems == 12 })

        let steppers = descendants(of: hostingView).compactMap { $0 as? NSStepper }
        XCTAssertEqual(steppers.count, 3)

        assertAligned(comboBoxes, edge: { $0.minX }, in: hostingView)
        assertAligned(steppers, edge: { $0.maxX }, in: hostingView)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants(of:))
    }

    private func assertAligned<View: NSView>(
        _ views: [View],
        edge: (NSRect) -> CGFloat,
        in hostingView: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let positions = views.map { edge(hostingView.convert($0.bounds, from: $0)) }
        guard let minimumEdge = positions.min(), let maximumEdge = positions.max() else {
            return XCTFail("Expected aligned controls", file: file, line: line)
        }
        XCTAssertEqual(maximumEdge, minimumEdge, accuracy: 1, file: file, line: line)
    }
}
