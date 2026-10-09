import XCTest
@testable import Midas

/// BGTaskScheduler crashes the app at launch if it registers a task id the Info.plist does not
/// permit, and never runs it without the fetch background mode. Checks the built app's plist.
final class BackgroundRefreshConfigTests: XCTestCase {
    @MainActor
    func testInfoPlistPermitsTheReminderRefreshTask() {
        let permittedIdentifiers = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        XCTAssertTrue(permittedIdentifiers.contains(BackgroundRefresh.taskIdentifier), "permitted: \(permittedIdentifiers)")
    }

    func testInfoPlistEnablesBackgroundFetch() {
        let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        XCTAssertTrue(backgroundModes.contains("fetch"), "modes: \(backgroundModes)")
    }
}
