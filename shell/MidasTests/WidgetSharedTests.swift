import XCTest
@testable import Midas

/// The app-to-widget contract in shell/Shared/WidgetShared.swift (founder plan, 2026-10-11).
final class WidgetSharedTests: XCTestCase {
    private func sampleEntries() -> [SidekickEntry] {
        let reminders = SidekickEntry(id: "reminders", name: "Reminders", symbolName: "checklist", backgroundHex: "#FFFFFF", version: "v1")
        let groceries = SidekickEntry(id: "groceries", name: "Groceries", symbolName: "cart", backgroundHex: "#30D5C8", version: "v2")
        return [reminders, groceries]
    }

    func testListSurvivesEncodeAndDecodeInOrder() throws {
        let savedAt = Date(timeIntervalSince1970: 1_791_700_000)
        let list = SharedSidekickList(sidekicks: sampleEntries(), savedAt: savedAt)
        let data = try list.encoded()
        let decoded = try XCTUnwrap(SharedSidekickList.decoded(from: data))
        XCTAssertEqual(decoded, list)
        XCTAssertEqual(decoded.sidekicks.map(\.id), ["reminders", "groceries"])
    }

    func testUnknownFormatVersionIsIgnored() throws {
        let list = SharedSidekickList(sidekicks: sampleEntries(), savedAt: Date())
        let data = try list.encoded()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["formatVersion"] = SharedSidekickList.currentFormatVersion + 1
        let futureData = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNil(SharedSidekickList.decoded(from: futureData))
    }

    func testGarbageIsIgnored() {
        XCTAssertNil(SharedSidekickList.decoded(from: Data("not json".utf8)))
    }

    func testOpenLinkRoundTrips() {
        let link = MidasLink.openSidekick(id: "reminders")
        XCTAssertEqual(link.url.absoluteString, "midas://open/reminders")
        XCTAssertEqual(MidasLink(url: link.url), link)
    }

    func testHomeLinkRoundTrips() {
        XCTAssertEqual(MidasLink.home.url.absoluteString, "midas://home")
        XCTAssertEqual(MidasLink(url: MidasLink.home.url), .home)
    }

    func testIdWithSlashStaysOneId() {
        let link = MidasLink.openSidekick(id: "a/b")
        XCTAssertEqual(MidasLink(url: link.url), link)
    }

    func testOtherLinksAreRejected() throws {
        let rejected = [
            "https://open/reminders",
            "midas://open",
            "midas://open/",
            "midas://open/reminders/extra",
            "midas://home/extra",
            "midas://delete/reminders"
        ]
        for text in rejected {
            let url = try XCTUnwrap(URL(string: text))
            XCTAssertNil(MidasLink(url: url), text)
        }
    }
}
