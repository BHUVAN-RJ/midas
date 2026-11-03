import XCTest
import UIKit
@testable import Midas

// Home title H2 (founder, 2026-11-02, docs/mockups/home-title-2026-11-02.html): "Midas" in the hand on
// the left, on the first tile's edge; the initial's right edge on the last tile's edge.
final class HomeTopBarTests: XCTestCase {

    /// The left edge of the first icon and the right edge of the last, worked out by hand from the
    /// grid's own numbers (4 columns, 20 pt margins, 8 pt between columns, 60 pt icons).
    private func iconEdges(screenWidth: CGFloat) -> (left: CGFloat, right: CGFloat) {
        let columnWidth = (screenWidth - 40 - 24) / 4
        let firstCentre = 20 + columnWidth / 2
        let lastCentre = screenWidth - 20 - columnWidth / 2
        return (firstCentre - 30, lastCentre + 30)
    }

    func testTitleIsInTheHand() {
        XCTAssertEqual(HomeTopBarSpec.title, "Midas")
        XCTAssertEqual(HomeTopBarSpec.titleFontName, "Caveat-Bold")
        XCTAssertEqual(HomeTopBarSpec.titleSize, 40)
        // The font is bundled: without it iOS falls back to the system font, the bug reported.
        XCTAssertNotNil(UIFont(name: HomeTopBarSpec.titleFontName, size: HomeTopBarSpec.titleSize))
    }

    func testInsetIsTheTileEdgeOnAnIPhone16Pro() {
        XCTAssertEqual(HomeTopBarSpec.sideInset(screenWidth: 402), 32.25, accuracy: 0.001)
    }

    func testTitleAndInitialSitOnTheOuterTilesAtEverySize() {
        for screenWidth: CGFloat in [375, 393, 402, 430, 440] {
            let inset = HomeTopBarSpec.sideInset(screenWidth: screenWidth)
            let edges = iconEdges(screenWidth: screenWidth)
            XCTAssertEqual(inset, edges.left, accuracy: 0.001, "title, width \(screenWidth)")
            XCTAssertEqual(screenWidth - inset, edges.right, accuracy: 0.001, "initial, width \(screenWidth)")
        }
    }

    func testInsetIsNotTheOldTwentyPointMargin() {
        // Build 22 put the initial 20 pt from the edge, about 12 pt outside the tiles.
        XCTAssertGreaterThan(HomeTopBarSpec.sideInset(screenWidth: 402) - 20, 12)
    }

    func testGridUsesTheSameNumbers() {
        XCTAssertEqual(SidekickHomeLayout.sideMargin, 20)
        XCTAssertEqual(SidekickHomeLayout.columnSpacing, 8)
        XCTAssertEqual(SidekickHomeLayout.iconSize, 60)
        XCTAssertEqual(SidekickHomeLayout.columnCount, 4)
    }

    func testInitialLinesUpWithTheMiddleOfTheCapitals() {
        let font = UIFont(name: "Caveat-Bold", size: 40)
        let expected = (font?.capHeight ?? 0) / 2
        XCTAssertGreaterThan(expected, 5)
        XCTAssertEqual(HomeTopBarSpec.halfCapHeight, expected, accuracy: 0.001)
    }
}
