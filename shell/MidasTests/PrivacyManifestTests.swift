import XCTest

/// Apple privacy manifest (founder, 2026-10-31): the built Midas app carries PrivacyInfo.xcprivacy,
/// says it does not track, and declares UserDefaults with reason CA92.1 (the app's own settings).
/// The tests run inside the app, so Bundle.main is the built Midas.app.
final class PrivacyManifestTests: XCTestCase {
    private static let userDefaultsCategory = "NSPrivacyAccessedAPICategoryUserDefaults"
    private static let appOwnDefaultsReason = "CA92.1"

    private func loadBundledManifest() throws -> [String: Any] {
        let manifestURL = try XCTUnwrap(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "PrivacyInfo.xcprivacy is not in the app bundle at \(Bundle.main.bundlePath)"
        )
        let manifestData = try Data(contentsOf: manifestURL)
        let propertyList = try PropertyListSerialization.propertyList(from: manifestData, format: nil)
        return try XCTUnwrap(propertyList as? [String: Any], "manifest is not a dictionary")
    }

    func testBundledManifestSaysNoTracking() throws {
        let manifest = try loadBundledManifest()
        let trackingValue = try XCTUnwrap(manifest["NSPrivacyTracking"] as? Bool, "NSPrivacyTracking missing")
        XCTAssertFalse(trackingValue)
        let trackingDomains = try XCTUnwrap(manifest["NSPrivacyTrackingDomains"] as? [String], "NSPrivacyTrackingDomains missing")
        XCTAssertEqual(trackingDomains, [])
    }

    func testBundledManifestDeclaresUserDefaultsForOwnSettings() throws {
        let manifest = try loadBundledManifest()
        let accessedTypes = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]], "NSPrivacyAccessedAPITypes missing")
        let userDefaultsEntries = accessedTypes.filter(isUserDefaultsEntry)
        XCTAssertEqual(userDefaultsEntries.count, 1, "expected one UserDefaults entry, found \(userDefaultsEntries.count)")
        let reasons = userDefaultsEntries.first?["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
        XCTAssertTrue(reasons.contains(Self.appOwnDefaultsReason), "UserDefaults reasons are \(reasons), expected \(Self.appOwnDefaultsReason)")
    }

    private func isUserDefaultsEntry(_ entry: [String: Any]) -> Bool {
        let category = entry["NSPrivacyAccessedAPIType"] as? String
        return category == Self.userDefaultsCategory
    }
}
