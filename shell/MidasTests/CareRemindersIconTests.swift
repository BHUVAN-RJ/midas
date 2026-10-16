import SwiftUI
import XCTest
@testable import Midas

/// The care-reminders icon (founder, 2026-10-12): mockup "2 · Size by urgency" from
/// docs/mockups/care-reminders-icon-2026-10-12.html, drawn by the shell.
final class CareRemindersIconTests: XCTestCase {

    func testCareRemindersShowsTheSizeByUrgencyArtwork() {
        let entry = SidekickEntry(id: "care-reminders", name: "Reminders", symbolName: "pills.fill", backgroundHex: "#9CAF88", version: "1")

        let content = SidekickIconContent.content(for: entry)

        XCTAssertEqual(content, .artwork(.careUrgencyTiles))
    }

    func testTheOtherRemindersKeepsItsOwnIcon() {
        XCTAssertEqual(SidekickArtwork.artwork(forSidekickId: "reminders"), .remindersList)
    }

    func testTilesMatchTheMockup() {
        let colours = CareUrgencyArtwork.tiles.map(\.hex)
        // Teal (big, most urgent), Apricot, then Sage, Lavender, Butter, Clay
        XCTAssertEqual(colours, ["#0F6E6E", "#FFB86B", "#9CAF88", "#C9B3FF", "#FFE48A", "#D9805F"])
        XCTAssertEqual(CareUrgencyArtwork.tiles[0].rect, CGRect(x: 140, y: 140, width: 744, height: 420))
        XCTAssertEqual(CareUrgencyArtwork.tiles[1].rect, CGRect(x: 140, y: 604, width: 420, height: 280))
        XCTAssertEqual(CareUrgencyArtwork.backgroundHex, "#FAF8F5")
        for hex in colours + [CareUrgencyArtwork.backgroundHex, CareUrgencyArtwork.bellHex] {
            XCTAssertNotNil(SidekickColor.rgbComponents(fromHex: hex), hex)
        }
    }

    func testTheBellHasTheMockupsOutline() {
        // The SVG bell spans x 32 to 224 and y 24 (top of the dome) to 232 (bottom of the clapper)
        let bounds = CareUrgencyIcon.bellPath().boundingRect
        XCTAssertEqual(bounds.minX, 32, accuracy: 0.5)
        XCTAssertEqual(bounds.maxX, 224, accuracy: 0.5)
        XCTAssertEqual(bounds.minY, 24, accuracy: 0.5)
        XCTAssertEqual(bounds.maxY, 232, accuracy: 0.5)
    }

    func testTheBellSitsInsideTheBigTile() {
        let bell = CareUrgencyIcon.bellPath().boundingRect
        let origin = CareUrgencyArtwork.bellOrigin
        let scale = CareUrgencyArtwork.bellScale
        let placed = CGRect(x: origin.x + bell.minX * scale, y: origin.y + bell.minY * scale,
                            width: bell.width * scale, height: bell.height * scale)
        XCTAssertTrue(CareUrgencyArtwork.tiles[0].rect.contains(placed), "the bell spills out of the teal tile: \(placed)")
    }
}
