import XCTest
@testable import Midas

/// The Folder widget's logic in shell/Shared/FolderWidgetLayout.swift (brief
/// docs/briefs/widget-extension.md, founder plan 2026-10-11).
final class FolderWidgetLayoutTests: XCTestCase {

    // MARK: Words on screen (docs/WRITING.md; the brief allows exactly these four)

    func testTheWidgetUsesOnlyTheFourApprovedPhrases() {
        XCTAssertEqual(FolderWidgetCopy.displayName, "Folder")
        XCTAssertEqual(FolderWidgetCopy.description, "Sidekicks on your Home Screen.")
        XCTAssertEqual(FolderWidgetCopy.sidekicksParameterTitle, "Sidekicks")
        XCTAssertEqual(FolderWidgetCopy.empty, "Open Midas")
    }

    // MARK: Limits per family: 2x2, 4x2, 4x4

    func testLimitsAreFourEightSixteen() {
        XCTAssertEqual(FolderWidgetFamily.small.tileLimit, 4)
        XCTAssertEqual(FolderWidgetFamily.medium.tileLimit, 8)
        XCTAssertEqual(FolderWidgetFamily.large.tileLimit, 16)
    }

    func testGridsAreTwoByTwoFourByTwoFourByFour() {
        XCTAssertEqual(FolderWidgetFamily.small.columnCount, 2)
        XCTAssertEqual(FolderWidgetFamily.small.rowCount, 2)
        XCTAssertEqual(FolderWidgetFamily.medium.columnCount, 4)
        XCTAssertEqual(FolderWidgetFamily.medium.rowCount, 2)
        XCTAssertEqual(FolderWidgetFamily.large.columnCount, 4)
        XCTAssertEqual(FolderWidgetFamily.large.rowCount, 4)
    }

    func testMoreTilesThanTheFamilyHoldsAreCutAtTheLimit() {
        let twenty = makeEntries(count: 20)

        for family in FolderWidgetFamily.allCases {
            let tiles = FolderWidgetLayout.tiles(pickedIds: [], sharedList: twenty, family: family)
            XCTAssertEqual(tiles.count, family.tileLimit, "\(family)")
        }
    }

    func testPickedTilesAreCutAtTheLimitToo() {
        let twenty = makeEntries(count: 20)
        let allPicked = twenty.map(\.id)

        let smallTiles = FolderWidgetLayout.tiles(pickedIds: allPicked, sharedList: twenty, family: .small)

        XCTAssertEqual(smallTiles.map(\.id), ["s0", "s1", "s2", "s3"])
    }

    // MARK: Default fill: nothing picked gives the first tiles in home grid order

    func testNothingPickedGivesTheFirstOfTheSharedListPerFamily() {
        let twenty = makeEntries(count: 20)
        let homeGridIds = twenty.map(\.id)

        let smallTiles = FolderWidgetLayout.tiles(pickedIds: [], sharedList: twenty, family: .small)
        let mediumTiles = FolderWidgetLayout.tiles(pickedIds: [], sharedList: twenty, family: .medium)
        let largeTiles = FolderWidgetLayout.tiles(pickedIds: [], sharedList: twenty, family: .large)

        XCTAssertEqual(smallTiles.map(\.id), Array(homeGridIds.prefix(4)))
        XCTAssertEqual(mediumTiles.map(\.id), Array(homeGridIds.prefix(8)))
        XCTAssertEqual(largeTiles.map(\.id), Array(homeGridIds.prefix(16)))
    }

    func testAShortSharedListFillsOnlyWhatItHas() {
        let three = makeEntries(count: 3)

        let largeTiles = FolderWidgetLayout.tiles(pickedIds: [], sharedList: three, family: .large)

        XCTAssertEqual(largeTiles.map(\.id), ["s0", "s1", "s2"])
    }

    // MARK: Picked order kept, unknown ids dropped

    func testPickedOrderIsTheOrderShown() {
        let entries = makeEntries(count: 6)

        let tiles = FolderWidgetLayout.tiles(pickedIds: ["s4", "s1", "s5"], sharedList: entries, family: .medium)

        XCTAssertEqual(tiles.map(\.id), ["s4", "s1", "s5"])
    }

    func testPickedIdsNoLongerInTheListAreDropped() {
        let entries = makeEntries(count: 3)

        let tiles = FolderWidgetLayout.tiles(pickedIds: ["s2", "deleted", "s0"], sharedList: entries, family: .small)

        XCTAssertEqual(tiles.map(\.id), ["s2", "s0"])
    }

    func testAnIdPickedTwiceShowsOnce() {
        let entries = makeEntries(count: 3)

        let tiles = FolderWidgetLayout.tiles(pickedIds: ["s1", "s1", "s0"], sharedList: entries, family: .small)

        XCTAssertEqual(tiles.map(\.id), ["s1", "s0"])
    }

    func testPickedTilesCarryTheSharedListsNameAndIcon() {
        let reminders = SidekickEntry(id: "reminders", name: "Reminders", symbolName: "checklist", backgroundHex: "#FFFFFF", version: "v3")

        let tiles = FolderWidgetLayout.tiles(pickedIds: ["reminders"], sharedList: [reminders], family: .small)

        XCTAssertEqual(tiles, [reminders])
    }

    // MARK: Empty state

    func testNoSharedListIsTheEmptyState() {
        let content = FolderWidgetLayout.content(pickedIds: [], sharedList: nil, family: .small)

        XCTAssertEqual(content, .empty)
    }

    func testAnEmptySharedListIsTheEmptyStateEvenWithPickedIds() {
        let content = FolderWidgetLayout.content(pickedIds: ["reminders"], sharedList: [], family: .large)

        XCTAssertEqual(content, .empty)
    }

    func testASharedListWithSidekicksIsNotTheEmptyState() {
        let entries = makeEntries(count: 2)

        let content = FolderWidgetLayout.content(pickedIds: [], sharedList: entries, family: .small)

        XCTAssertEqual(content, .tiles(entries))
    }

    func testPickedIdsAllGoneFallBackToTheDefaultFill() {
        let entries = makeEntries(count: 2)

        let content = FolderWidgetLayout.content(pickedIds: ["gone"], sharedList: entries, family: .small)

        XCTAssertEqual(content, .tiles(entries))
    }

    // MARK: Rows for drawing

    func testRowsFollowTheFamilyColumnsAndTheLastRowMayBeShort() {
        let five = makeEntries(count: 5)

        let smallRows = FolderWidgetLayout.rows(of: Array(five.prefix(3)), family: .small)
        let mediumRows = FolderWidgetLayout.rows(of: five, family: .medium)

        XCTAssertEqual(smallRows.map { row in row.map(\.id) }, [["s0", "s1"], ["s2"]])
        XCTAssertEqual(mediumRows.map { row in row.map(\.id) }, [["s0", "s1", "s2", "s3"], ["s4"]])
    }

    func testNoTilesGiveNoRows() {
        XCTAssertEqual(FolderWidgetLayout.rows(of: [], family: .large).count, 0)
    }

    // MARK: Helpers

    private func makeEntries(count: Int) -> [SidekickEntry] {
        var entries: [SidekickEntry] = []
        for index in 0..<count {
            let entry = SidekickEntry(id: "s\(index)", name: "Sidekick \(index)", symbolName: "star", backgroundHex: "#FF6347", version: "1")
            entries.append(entry)
        }
        return entries
    }
}
