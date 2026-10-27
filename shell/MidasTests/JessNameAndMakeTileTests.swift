import UIKit
import XCTest
@testable import Midas

// The built-in Sidekicks look the same everywhere (founder, 2026-10-26): jess's tile is named
// "Jess" with a capital J (founder, 2026-10-23), and Make, like jess, draws its written tile in
// widget folders too, not the catalog's `plus` on black.
final class JessNameAndMakeTileTests: XCTestCase {
    func testJessIsNamedWithACapitalJEvenWhenTheCatalogSaysLowercase() throws {
        let body = Data(##"{"sidekicks":[{"id":"jess","name":"jess","icon":{"symbol":"circle.circle.fill","background":"#000000"},"reads":[],"version":"built-in","builtIn":true},{"id":"reminders","name":"Reminders","icon":{"symbol":"checklist","background":"#FF9500"},"reads":[],"version":"v5"}]}"##.utf8)
        let entries = try RemoteSidekickDirectoryFetcher.entries(from: body)
        XCTAssertEqual(entries.map(\.name), ["Jess", "Reminders"])
        XCTAssertEqual(entries.first?.id, "jess", "only the shown name changes, never the id")
    }

    func testMakeIsDrawnAsItsWrittenTileNotTheCatalogSymbol() {
        let makeFromCatalog = SidekickEntry(id: "make", name: "Make", symbolName: "plus", backgroundHex: "#000000", version: "built-in")
        XCTAssertEqual(SidekickIconContent.content(for: makeFromCatalog), .artwork(.makeWord))
        XCTAssertEqual(MakeTileIcon.imageName, MakeTileArtwork.imageName)
    }

    func testTheWidgetExtensionCarriesTheMakeTile() throws {
        let plugIns = try XCTUnwrap(Bundle.main.builtInPlugInsURL, "the app has no PlugIns folder")
        let widgetBundle = try XCTUnwrap(Bundle(url: plugIns.appendingPathComponent("MidasWidgets.appex")), "MidasWidgets.appex is not embedded")
        XCTAssertNotNil(UIImage(named: MakeTileArtwork.imageName, in: widgetBundle, compatibleWith: nil), "the widget extension cannot load MakeTile")
    }
}
