import XCTest
@testable import Midas

/// Words on the repair layer, as the founder approved them on 2026-10-13 (docs/WRITING.md).
final class RepairCopyTests: XCTestCase {
    func testLayerButtons() {
        XCTAssertEqual(RepairCopy.cancelLabel, "Cancel")
        XCTAssertEqual(RepairCopy.undoButton, "Undo")
        XCTAssertEqual(RepairCopy.clearButton, "Clear")
        XCTAssertEqual(RepairCopy.sendButton, "Send")
        XCTAssertEqual(RepairCopy.textPlaceholder, "What to fix")
    }

    func testPermissionScreen() {
        XCTAssertEqual(RepairCopy.permissionTitle, "Speak While You Draw")
        XCTAssertEqual(RepairCopy.continueButton, "Continue")
        XCTAssertEqual(RepairCopy.notNowButton, "Not Now")
        XCTAssertEqual(RepairCopy.openSettingsButton, "Open Settings")
    }

    func testNoPeriodsOnTitlesOrButtons() {
        let labels = [
            RepairCopy.cancelLabel, RepairCopy.undoButton, RepairCopy.clearButton, RepairCopy.sendButton,
            RepairCopy.textPlaceholder, RepairCopy.permissionTitle, RepairCopy.continueButton,
            RepairCopy.notNowButton, RepairCopy.openSettingsButton,
        ]
        for label in labels {
            XCTAssertFalse(label.hasSuffix("."), "\(label) ends with a period")
            XCTAssertFalse(label.contains("  "), "\(label) has a double space")
        }
    }
}
