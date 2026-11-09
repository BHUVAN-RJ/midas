import SwiftUI
import XCTest
@testable import Midas

/// The Sounds icon (founder, 2026-11-08: "lets go with a8 now"): option "A8 Bruh bubble" from
/// docs/mockups/sounds-icon-2026-11-07.html, drawn by the shell instead of the catalog's speaker.
final class SoundsIconTests: XCTestCase {

    func testSoundsShowsTheBubbleArtworkNotItsCatalogSymbol() {
        let entry = SidekickEntry(id: "soundboard", name: "Sounds", symbolName: "speaker.wave.2.fill", backgroundHex: "#30D5C8", version: "1")

        let content = SidekickIconContent.content(for: entry)

        XCTAssertEqual(content, .artwork(.soundsBruhBubble))
        XCTAssertEqual(SidekickArtwork.artwork(forSidekickId: "soundboard"), .soundsBruhBubble)
    }

    func testColoursAreTealByDayDeepTealAtNightWhiteBubbleInk() {
        let light = SoundsBubbleArtwork.colors(isDark: false)
        let dark = SoundsBubbleArtwork.colors(isDark: true)
        XCTAssertEqual(light.tile, "#30D5C8")
        XCTAssertEqual(dark.tile, "#22958C")
        XCTAssertEqual(light.bubble, "#FFFFFF")
        XCTAssertEqual(light.ink, "#111111")
        XCTAssertNotEqual(light.tile, dark.tile, "the tile must change at night")
        for hex in [light.tile, dark.tile, light.bubble, light.ink] {
            XCTAssertNotNil(SidekickColor.rgbComponents(fromHex: hex), hex)
        }
        XCTAssertEqual(SoundsBubbleArtwork.word, "BRUH")
    }

    func testTheBubbleHasTheMockupsOutlineAndTail() {
        let bubble = SoundsBubbleArtwork.bubblePath()
        // The SVG bubble spans x 10 to 90, from y 26 down to the tail's point at y 83
        let bounds = bubble.boundingRect
        XCTAssertEqual(bounds.minX, 10, accuracy: 0.5)
        XCTAssertEqual(bounds.maxX, 90, accuracy: 0.5)
        XCTAssertEqual(bounds.minY, 26, accuracy: 0.5)
        XCTAssertEqual(bounds.maxY, 83, accuracy: 0.5)
        XCTAssertTrue(bubble.contains(CGPoint(x: 50, y: 48)), "the middle of the box is bubble")
        XCTAssertTrue(bubble.contains(CGPoint(x: 33, y: 76)), "the tail is bubble")
        XCTAssertFalse(bubble.contains(CGPoint(x: 70, y: 78)), "below the box away from the tail is tile")
        XCTAssertFalse(bubble.contains(CGPoint(x: 11, y: 27)), "the corners are rounded")
    }

    func testTheSymbolTileFallbackStillMatchesTheArtworkColours() throws {
        // Builds without the artwork draw the manifest's symbol on its colours: the same Teal
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("sidekicks/soundboard/manifest.json")
        let data = try Data(contentsOf: url)
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let icon = try XCTUnwrap(manifest["icon"] as? [String: Any])
        XCTAssertEqual(icon["background"] as? String, SoundsBubbleArtwork.tileHex)
        XCTAssertEqual(icon["backgroundDark"] as? String, SoundsBubbleArtwork.darkTileHex)
    }
}
