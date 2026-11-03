import SwiftUI
import XCTest
@testable import Midas

// Build 22 feedback (founder, 2026-11-02, screenshot of Make's "Built by Hand"): a short sheet
// floated above the bottom with all four corners rounded ("a square just hanging"). Short sheets
// now sit on the bottom edge (BottomEdgeSheet): top corners rounded, down under the home
// indicator, the page dimmed; swipe down or tap the page to close. Make's first-open sheet, the
// Third-Party Services ask and C3 "Delete <Sidekick>?" use it.

private func bottomSheetShellRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
}

private func shellSource(_ fileName: String) throws -> String {
    try String(contentsOf: bottomSheetShellRoot().appending(path: "Midas/\(fileName)"), encoding: .utf8)
}

final class Build22BottomSheetTests: XCTestCase {
    func testASwipeDownFarOrFastCloses() {
        XCTAssertTrue(BottomEdgeSheetSpec.closes(translation: 120, predicted: 130))
        XCTAssertTrue(BottomEdgeSheetSpec.closes(translation: 40, predicted: 300), "a fling")
        XCTAssertFalse(BottomEdgeSheetSpec.closes(translation: 40, predicted: 60))
        XCTAssertFalse(BottomEdgeSheetSpec.closes(translation: 0, predicted: 0))
    }

    func testTheSheetShowsOnTheDimmedPageInBothModes() {
        XCTAssertEqual(BottomEdgeSheetSpec.background(.light), RepairTokens.light.paper)
        XCTAssertEqual(BottomEdgeSheetSpec.background(.dark), RepairTokens.dark.paper2, "dark paper is the page's own black")
        XCTAssertNotEqual(BottomEdgeSheetSpec.background(.dark), RepairTokens.dark.paper)
    }

    func testTheSheetSitsOnTheBottomEdgeWithOnlyTopCornersRounded() throws {
        let source = try shellSource("BottomEdgeSheet.swift")
        XCTAssertTrue(source.contains("UnevenRoundedRectangle(topLeadingRadius: BottomEdgeSheetSpec.cornerRadius, topTrailingRadius: BottomEdgeSheetSpec.cornerRadius"))
        XCTAssertFalse(source.contains("bottomLeadingRadius"), "no rounded bottom corners")
        XCTAssertTrue(source.contains(".ignoresSafeArea(edges: .bottom)"), "down to the screen's edge")
        XCTAssertFalse(source.contains("presentationDetents"), "not a system sheet at a partial height (floats on iOS 26)")
    }

    func testMakeConsentAndC3UseIt() throws {
        let make = try shellSource("MakeWelcomeSheet.swift")
        XCTAssertTrue(make.contains(".bottomEdgeSheet(isPresented: $isShown)"))
        XCTAssertFalse(make.contains("presentationDetents"))
        let consent = try shellSource("AIConsent.swift")
        XCTAssertTrue(consent.contains(".bottomEdgeSheet(isPresented: $center.isAskShown, onDismiss: center.askDismissed)"))
        XCTAssertFalse(consent.contains("presentationDetents"))
        let app = try shellSource("MidasApp.swift")
        XCTAssertTrue(app.contains(".bottomEdgeSheet(item: $sidekickToDelete)"))
        let settings = try shellSource("SettingsView.swift")
        XCTAssertFalse(settings.contains(".presentationDetents([.height(Self.height)])"), "C3 is no longer a floating sheet")
    }
}
