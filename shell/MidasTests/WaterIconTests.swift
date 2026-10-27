import SwiftUI
import XCTest
@testable import Midas

/// The Water icon (founder, 2026-10-26: "add glass"): option "D · Glass" from
/// docs/mockups/water-icon-2026-10-26.html, drawn by the shell instead of the catalog's drop.
final class WaterIconTests: XCTestCase {

    func testWaterShowsTheGlassArtworkNotItsCatalogSymbol() {
        let entry = SidekickEntry(id: "hydration", name: "Water", symbolName: "drop.fill", backgroundHex: "#30D5C8", version: "1")

        let content = SidekickIconContent.content(for: entry)

        XCTAssertEqual(content, .artwork(.waterGlass))
    }

    func testColoursAreWatersTideColours() {
        XCTAssertEqual(WaterGlassArtwork.sandHex, "#F4EEE3")
        XCTAssertEqual(WaterGlassArtwork.seaHex, "#9CCFD3")
        XCTAssertEqual(WaterGlassArtwork.inkHex, "#24343A")
        for hex in [WaterGlassArtwork.sandHex, WaterGlassArtwork.seaHex, WaterGlassArtwork.inkHex] {
            XCTAssertNotNil(SidekickColor.rgbComponents(fromHex: hex), hex)
        }
    }

    func testTheGlassHasTheMockupsOutline() {
        // The SVG tumbler spans x 30 to 70 (rim) and y 24 (rim) to 84 (base)
        let bounds = WaterGlassArtwork.glassPath().boundingRect
        XCTAssertEqual(bounds.minX, 30, accuracy: 0.5)
        XCTAssertEqual(bounds.maxX, 70, accuracy: 0.5)
        XCTAssertEqual(bounds.minY, 24, accuracy: 0.5)
        XCTAssertEqual(bounds.maxY, 84, accuracy: 0.5)
    }

    func testTheSeaStandsAtHalfWithAWave() {
        let sea = WaterGlassArtwork.seaPath()
        // Midline at 50; the wave rises above it on the left and dips below it on the right
        XCTAssertEqual(WaterGlassArtwork.seaLevel, 50)
        XCTAssertTrue(sea.contains(CGPoint(x: 25, y: 48)), "the crest on the left is water")
        XCTAssertFalse(sea.contains(CGPoint(x: 75, y: 52)), "the trough on the right is air")
        XCTAssertTrue(sea.contains(CGPoint(x: 50, y: 80)))
    }
}
