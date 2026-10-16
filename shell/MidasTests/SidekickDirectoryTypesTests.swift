import XCTest
@testable import Midas

// GET /sidekicks lists each Sidekick's manifest whole, types included (unified data, 2026-10-15:
// schemas live in manifest.json). The directory keeps the types next to the entries, cached on
// the phone, so the write gate checks records offline too.

private let remindersTypesJSON = #"{"reminder:":{"$type":"reminders.item","schema":{"type":"object","required":["title"]}}}"#

private final class StubListingFetcher: SidekickDirectoryFetching, @unchecked Sendable {
    var listings: [SidekickListing]

    init(listings: [SidekickListing]) {
        self.listings = listings
    }

    func fetchSidekicks() async throws -> [SidekickEntry] {
        var entries: [SidekickEntry] = []
        for listing in listings {
            entries.append(listing.entry)
        }
        return entries
    }

    func fetchListings() async throws -> [SidekickListing] {
        listings
    }
}

final class SidekickDirectoryListingDecodingTests: XCTestCase {
    func testAListingCarriesItsTypesAndAnOlderOneHasNone() throws {
        let reply = """
        {"sidekicks":[
          {"id":"reminders","name":"Reminders","icon":{"symbol":"checklist","background":"#FF9500"},"reads":[],"version":"v2","types":\(remindersTypesJSON)},
          {"id":"notes","name":"Notes","icon":{"symbol":"note.text","background":"#FFCC00"},"reads":[],"version":"n1"},
          {"id":"old","name":"Old","icon":{"symbol":"clock","background":"#8E8E93"},"reads":[],"version":"o1","types":null}
        ]}
        """
        let listings = try RemoteSidekickDirectoryFetcher.listings(from: Data(reply.utf8))
        XCTAssertEqual(listings.count, 3)
        XCTAssertEqual(listings[0].entry.id, "reminders")
        XCTAssertEqual(listings[0].types?["reminder:"]?["$type"], .string("reminders.item"))
        XCTAssertNil(listings[1].types)
        XCTAssertNil(listings[2].types)
        // The entries list the grid uses is unchanged.
        let entries = try RemoteSidekickDirectoryFetcher.entries(from: Data(reply.utf8))
        XCTAssertEqual(entries.map(\.id), ["reminders", "notes", "old"])
    }
}

@MainActor
final class SidekickDirectoryTypesTests: XCTestCase {
    private var cacheURL: URL!

    override func setUp() {
        super.setUp()
        let folder = FileManager.default.temporaryDirectory.appending(path: "directory-types-\(UUID().uuidString)")
        cacheURL = folder.appending(path: "midas-sidekicks-test.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent())
        super.tearDown()
    }

    /// No widget to reload in a test.
    nonisolated private static func reloadNothing() {}

    private func remindersListing() throws -> SidekickListing {
        let types = try JSONDecoder().decode(JSONValue.self, from: Data(remindersTypesJSON.utf8))
        let entry = SidekickEntry(id: "reminders", name: "Reminders", symbolName: "checklist", backgroundHex: "#FF9500", version: "v2")
        return SidekickListing(entry: entry, types: types)
    }

    func testRefreshKeepsTypesAndVersionsAndCachesThemForTheNextLaunch() async throws {
        let notesEntry = SidekickEntry(id: "notes", name: "Notes", symbolName: "note.text", backgroundHex: "#FFCC00", version: "n1")
        let fetcher = StubListingFetcher(listings: [try remindersListing(), SidekickListing(entry: notesEntry, types: nil)])
        let writer = SharedSidekickListWriter(fileURL: nil, now: Date.init, reloadWidgets: Self.reloadNothing)
        let directory = SidekickDirectory(cacheFileURL: cacheURL, fetcher: fetcher, sharedListWriter: writer)
        XCTAssertNil(directory.types(forSidekickId: "reminders"))
        XCTAssertNil(directory.version(forSidekickId: "reminders"))

        await directory.refresh()
        XCTAssertEqual(directory.types(forSidekickId: "reminders")?["reminder:"]?["$type"], .string("reminders.item"))
        XCTAssertNil(directory.types(forSidekickId: "notes"))
        XCTAssertEqual(directory.version(forSidekickId: "reminders"), "v2")
        XCTAssertEqual(directory.version(forSidekickId: "notes"), "n1")
        XCTAssertNil(directory.version(forSidekickId: "calendar"))

        // Next launch, offline: the cached types are there before any fetch.
        let failingFetcher = StubListingFetcher(listings: [])
        let relaunched = SidekickDirectory(cacheFileURL: cacheURL, fetcher: failingFetcher, sharedListWriter: writer)
        XCTAssertEqual(relaunched.types(forSidekickId: "reminders")?["reminder:"]?["$type"], .string("reminders.item"))
        XCTAssertEqual(relaunched.version(forSidekickId: "reminders"), "v2")
        XCTAssertEqual(SidekickDirectory.typesCacheFileURL(besides: cacheURL).lastPathComponent, "midas-sidekicks-test-types.json")
    }

    func testAFetcherThatKnowsOnlyEntriesListsNoTypes() async throws {
        let fetcher = EntriesOnlyFetcher()
        let listings = try await fetcher.fetchListings()
        XCTAssertEqual(listings.count, 1)
        XCTAssertEqual(listings[0].entry.id, "reminders")
        XCTAssertNil(listings[0].types)
    }
}

/// An older test double shape: entries only, relying on the protocol's default listings.
private struct EntriesOnlyFetcher: SidekickDirectoryFetching {
    func fetchSidekicks() async throws -> [SidekickEntry] {
        [SidekickEntry(id: "reminders", name: "Reminders", symbolName: "checklist", backgroundHex: "#FF9500", version: "v2")]
    }
}
