import XCTest
@testable import Midas

/// The shell design decisions of 2026-10-10: welcome wording, the icon grid home, the Reminders
/// icon (W2) and the left-edge swipe back.
final class ShellDesignTests: XCTestCase {

    // MARK: Welcome wording (option B)

    func testWelcomeButtonsUseTheChosenWording() {
        XCTAssertEqual(WelcomeCopy.newUserButton, "Get Started")
        XCTAssertEqual(WelcomeCopy.returningUserButton, "I've used Midas before")
    }

    // MARK: Home grid

    func testHomeGridHasFourIconsPerRow() {
        XCTAssertEqual(SidekickHomeLayout.columnCount, 4)
    }

    func testHomeGridKeepsTheServersOrder() {
        let calendar = makeEntry(id: "calendar")
        let reminders = makeEntry(id: "reminders")
        let notes = makeEntry(id: "notes")

        let tiles = SidekickHomeLayout.tiles(from: [notes, reminders, calendar])

        let tileIds = tiles.map(\.id)
        XCTAssertEqual(tileIds, ["notes", "reminders", "calendar"])
    }

    // MARK: Icons

    func testRemindersShowsItsDrawnIcon() {
        let reminders = makeEntry(id: "reminders", symbolName: "checklist", backgroundHex: "#FF9500")

        let content = SidekickIconContent.content(for: reminders)

        XCTAssertEqual(content, .artwork(.remindersList))
    }

    func testOtherSidekicksUseTheirManifestSymbolAndColor() {
        let birthdays = makeEntry(id: "birthdays", symbolName: "gift.fill", backgroundHex: "#AF52DE")

        let content = SidekickIconContent.content(for: birthdays)

        XCTAssertEqual(content, .symbol(name: "gift.fill", backgroundHex: "#AF52DE"))
    }

    func testRemindersIconIsTheChosenWhiteAndGreen() {
        XCTAssertEqual(RemindersListArtwork.tileHex, "#FFFFFF")
        XCTAssertEqual(RemindersListArtwork.doneHex, "#2FA65A")
        XCTAssertNotNil(SidekickColor.rgbComponents(fromHex: RemindersListArtwork.tileHex))
        XCTAssertNotNil(SidekickColor.rgbComponents(fromHex: RemindersListArtwork.doneHex))
        XCTAssertNotNil(SidekickColor.rgbComponents(fromHex: RemindersListArtwork.rowHex))
    }

    // MARK: Swipe back

    func testSwipeBackDoesNothingOnTheHomeGrid() {
        XCTAssertFalse(SidekickSwipeBack.shouldBegin(navigationStackDepth: 1))
        XCTAssertFalse(SidekickSwipeBack.shouldBegin(navigationStackDepth: 0))
    }

    func testSwipeBackWorksInsideASidekick() {
        XCTAssertTrue(SidekickSwipeBack.shouldBegin(navigationStackDepth: 2))
    }

    private func makeEntry(id: String, symbolName: String = "star", backgroundHex: String = "#000000") -> SidekickEntry {
        return SidekickEntry(id: id, name: id.capitalized, symbolName: symbolName, backgroundHex: backgroundHex, version: "1")
    }
}
