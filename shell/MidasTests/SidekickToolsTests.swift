import XCTest
@testable import Midas

// The jess router's tools on the phone (founder, 2026-10-21): each Sidekick's tools.js runs in its
// own JavaScriptCore context, a handler's ops go through RecordWriter.apply (write gate and size
// limit on every record before anything is written), tools.js is kept per version, and the
// directory keeps each Sidekick's agent block next to its types.

private let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let losAngeles = "America/Los_Angeles"
// Tuesday Oct 20, 2026, 10:00 in Los Angeles
private let nowText = "2026-10-20T17:00:00.000Z"

private func sidekickFile(_ sidekickId: String, _ fileName: String) throws -> String {
    try String(contentsOf: repoRoot.appending(path: "sidekicks/\(sidekickId)/\(fileName)"), encoding: .utf8)
}

private func manifest(_ sidekickId: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(try sidekickFile(sidekickId, "manifest.json").utf8))
}

private func json(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private func toolVerbs(in manifest: JSONValue, sidekickId: String) -> [String] {
    guard case .array(let tools)? = manifest["agent"]?["tools"] else {
        return []
    }
    var verbs: [String] = []
    for tool in tools {
        if case .string(let name)? = tool["name"] {
            verbs.append(String(name.dropFirst(sidekickId.count + 1)))
        }
    }
    return verbs.sorted()
}

/// Counts fetches; answers each version with a script whose result text names the version.
private final class CountingToolsFetcher: SidekickToolsFetching, @unchecked Sendable {
    var fetchedVersions: [String] = []

    func fetchTools(sidekickId: String, version: String) async throws -> String {
        fetchedVersions.append(version)
        if version == "missing" {
            throw SidekickToolsFetchError.noTools
        }
        return """
        var MidasSidekickTools = {
          context: function () { return { version: '\(version)' }; },
          handlers: { ping: function () { return { ops: [], result: { text: '\(version)' } }; } }
        };
        """
    }
}

private final class StubListingFetcher: SidekickDirectoryFetching, @unchecked Sendable {
    let listings: [SidekickListing]

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

@MainActor
final class SidekickToolsTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appending(path: "sidekick-tools-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    nonisolated private static func reloadNothing() {}

    private var now: Date {
        ReminderRecord.parseDate(.string(nowText))!
    }

    /// A store whose write gate checks every record against the Sidekick's real manifest types.
    private func makeGatedStore(sidekickId: String) throws -> LocalRecordStore {
        let engine = try RecordSchemaEngine(bundle: Bundle(for: RecordSchemaEngine.self))
        let types = try manifest(sidekickId)["types"]
        let store = LocalRecordStore(fileURL: folder.appending(path: "records.json"))
        func typesFor(requestedSidekickId: String) -> JSONValue? {
            requestedSidekickId == sidekickId ? types : nil
        }
        store.writeGate = RecordTypeGate.make(engine: engine, typesProvider: typesFor)
        return store
    }

    private func seedReminders(into store: LocalRecordStore) throws {
        try store.set(sidekickId: "reminders", key: "list:groceries", value: try json(##"{"$type":"reminders.list","name":"Groceries","color":"#34C759","icon":"cart","createdAt":"2026-10-02T00:00:00.000Z"}"##))
        try store.set(sidekickId: "reminders", key: "reminder:callmom00001", value: try json(#"{"$type":"reminders.item","title":"Call Mom","done":false,"timeZone":"America/Los_Angeles","createdAt":"2026-10-10T00:00:00.000Z"}"#))
    }

    // MARK: The engine runs the real tools.js

    func testBothSidekicksLoadWithAHandlerForEveryTool() throws {
        for sidekickId in ["reminders", "care-reminders"] {
            let engine = try SidekickToolsEngine(source: try sidekickFile(sidekickId, "tools.js"))
            let verbs = toolVerbs(in: try manifest(sidekickId), sidekickId: sidekickId)
            XCTAssertFalse(verbs.isEmpty, sidekickId)
            XCTAssertEqual(engine.handlerNames(), verbs, sidekickId)
        }
    }

    func testAddRunsInJavaScriptCoreAndItsRecordPassesTheWriteGate() throws {
        let store = try makeGatedStore(sidekickId: "reminders")
        try seedReminders(into: store)
        let engine = try SidekickToolsEngine(source: try sidekickFile("reminders", "tools.js"))
        let input = try json(#"{"title":"Bananas","notes":null,"list":"groceries","when":{"date":"2026-10-21","time":"18:00","allDay":false,"at":"2026-10-22T01:00:00.000Z","repeat":null,"timeZone":"America/Los_Angeles"}}"#)
        let records = store.query(sidekickId: "reminders", keyPrefix: "")
        let result = try engine.run(verb: "add", input: input, records: records, now: now)
        XCTAssertEqual(result.text, "Added Bananas")
        XCTAssertEqual(result.at, "2026-10-22T01:00:00.000Z")
        XCTAssertEqual(result.allDay, false)
        guard case .changes(let ops) = result.outcome, ops.count == 1, case .set(let key, let value) = ops[0] else {
            return XCTFail("expected one set, got \(result.outcome)")
        }
        XCTAssertTrue(key.hasPrefix("reminder:"))
        XCTAssertEqual(value["list"], .string("groceries"))
        XCTAssertEqual(value["createdAt"], .string(nowText))

        try RecordWriter(store: store).apply(sidekickId: "reminders", ops: ops)
        let stored = store.get(sidekickId: "reminders", key: key)
        XCTAssertEqual(stored?["title"], .string("Bananas"))
        XCTAssertEqual(stored?["$type"], .string("reminders.item"))
        XCTAssertEqual(store.query(sidekickId: "reminders", keyPrefix: "reminder:").count, 2)
    }

    func testCompleteMarksTheNamedReminderDoneThroughTheWriter() throws {
        let store = try makeGatedStore(sidekickId: "reminders")
        try seedReminders(into: store)
        let engine = try SidekickToolsEngine(source: try sidekickFile("reminders", "tools.js"))
        let records = store.query(sidekickId: "reminders", keyPrefix: "")
        let result = try engine.run(verb: "complete", input: try json(#"{"item":"call mom"}"#), records: records, now: now)
        guard case .changes(let ops) = result.outcome else {
            return XCTFail("expected changes, got \(result.outcome)")
        }
        try RecordWriter(store: store).apply(sidekickId: "reminders", ops: ops)
        let stored = store.get(sidekickId: "reminders", key: "reminder:callmom00001")
        XCTAssertEqual(stored?["done"], .bool(true))
        XCTAssertEqual(stored?["completedAt"], .string(nowText))
    }

    func testARefusalChangesNothing() throws {
        let store = try makeGatedStore(sidekickId: "reminders")
        try seedReminders(into: store)
        let before = store.query(sidekickId: "reminders", keyPrefix: "")
        let engine = try SidekickToolsEngine(source: try sidekickFile("reminders", "tools.js"))
        let result = try engine.run(verb: "complete", input: try json(#"{"item":"walk the dog"}"#), records: before, now: now)
        XCTAssertEqual(result.outcome, .refused(reason: "not-found"))
        XCTAssertEqual(store.query(sidekickId: "reminders", keyPrefix: ""), before)
    }

    func testContextListsTheListsAndItemsForTheRouter() throws {
        let store = try makeGatedStore(sidekickId: "reminders")
        try seedReminders(into: store)
        let engine = try SidekickToolsEngine(source: try sidekickFile("reminders", "tools.js"))
        let context = try engine.context(records: store.query(sidekickId: "reminders", keyPrefix: ""), now: now)
        let contextText = String(decoding: try JSONEncoder().encode(context), as: UTF8.self)
        XCTAssertTrue(contextText.contains("Groceries"), contextText)
        XCTAssertTrue(contextText.contains("Call Mom"), contextText)
    }

    func testABrokenScriptAThrowingHandlerAndAMissingHandlerAreErrorsNotCrashes() throws {
        XCTAssertThrowsError(try SidekickToolsEngine(source: "throw new Error('boom');"))
        XCTAssertThrowsError(try SidekickToolsEngine(source: "var Other = {};"))
        let source = """
        var MidasSidekickTools = {
          context: function () { return {}; },
          handlers: {
            explode: function () { throw new Error('bad input'); },
            sloppy: function () { return { ops: [{ op: 'rename', key: 'a:1' }], result: { text: 'x' } }; }
          }
        };
        """
        let engine = try SidekickToolsEngine(source: source)
        XCTAssertThrowsError(try engine.run(verb: "explode", input: .object([:]), records: [], now: now)) { error in
            XCTAssertEqual(error as? SidekickToolsError, .handlerFailed("bad input"))
        }
        XCTAssertThrowsError(try engine.run(verb: "fly", input: .object([:]), records: [], now: now)) { error in
            XCTAssertEqual(error as? SidekickToolsError, .noHandler("fly"))
        }
        XCTAssertThrowsError(try engine.run(verb: "sloppy", input: .object([:]), records: [], now: now)) { error in
            XCTAssertEqual(error as? SidekickToolsError, .badResult("sloppy gave an op that is neither set nor delete"))
        }
        // The context still works after a handler threw.
        XCTAssertEqual(try engine.context(records: [], now: now), .object([:]))
    }

    // MARK: RecordWriter.apply

    func testApplyWritesNothingWhenOneRecordFailsTheGate() throws {
        let store = try makeGatedStore(sidekickId: "reminders")
        try seedReminders(into: store)
        let before = store.query(sidekickId: "reminders", keyPrefix: "")
        let good = SidekickToolOp.set(key: "reminder:newone000001", value: try json(#"{"title":"Fine","done":false,"timeZone":"America/Los_Angeles","createdAt":"2026-10-20T17:00:00.000Z"}"#))
        let bad = SidekickToolOp.set(key: "reminder:broken000001", value: try json(#"{"title":"","done":"yes"}"#))
        let removal = SidekickToolOp.delete(key: "reminder:callmom00001")
        XCTAssertThrowsError(try RecordWriter(store: store).apply(sidekickId: "reminders", ops: [good, removal, bad])) { error in
            let reason = (error as? RecordRefusal)?.reason ?? ""
            XCTAssertTrue(reason.hasPrefix("reminder:broken000001: "), reason)
        }
        XCTAssertEqual(store.query(sidekickId: "reminders", keyPrefix: ""), before)
    }

    func testApplyStoresAndDeletesInOrder() throws {
        let store = try makeGatedStore(sidekickId: "reminders")
        try seedReminders(into: store)
        let added = SidekickToolOp.set(key: "reminder:newone000001", value: try json(#"{"title":"Fine","done":false,"timeZone":"America/Los_Angeles","createdAt":"2026-10-20T17:00:00.000Z"}"#))
        try RecordWriter(store: store).apply(sidekickId: "reminders", ops: [added, .delete(key: "reminder:callmom00001")])
        XCTAssertEqual(store.get(sidekickId: "reminders", key: "reminder:newone000001")?["$type"], .string("reminders.item"))
        XCTAssertNil(store.get(sidekickId: "reminders", key: "reminder:callmom00001"))
    }

    // MARK: tools.js per version

    func testToolsAreFetchedOncePerVersionAndKeptOnThePhone() async throws {
        let fetcher = CountingToolsFetcher()
        let library = SidekickToolsLibrary(cacheDirectoryURL: folder.appending(path: "tools"), fetcher: fetcher)
        let first = try await library.engine(sidekickId: "reminders", version: "v1")
        let again = try await library.engine(sidekickId: "reminders", version: "v1")
        XCTAssertTrue(first === again)
        XCTAssertEqual(try first.run(verb: "ping", input: .object([:]), records: [], now: now).text, "v1")
        let second = try await library.engine(sidekickId: "reminders", version: "v2")
        XCTAssertEqual(try second.run(verb: "ping", input: .object([:]), records: [], now: now).text, "v2")
        XCTAssertEqual(fetcher.fetchedVersions, ["v1", "v2"])

        // Next launch: the saved file is used without a fetch.
        let relaunchFetcher = CountingToolsFetcher()
        let relaunched = SidekickToolsLibrary(cacheDirectoryURL: folder.appending(path: "tools"), fetcher: relaunchFetcher)
        let fromDisk = try await relaunched.engine(sidekickId: "reminders", version: "v1")
        XCTAssertEqual(try fromDisk.run(verb: "ping", input: .object([:]), records: [], now: now).text, "v1")
        XCTAssertEqual(relaunchFetcher.fetchedVersions, [])

        do {
            _ = try await relaunched.engine(sidekickId: "notes", version: "missing")
            XCTFail("a version without tools must throw")
        } catch {
            XCTAssertEqual(error as? SidekickToolsFetchError, .noTools)
        }
    }

    func testTheToolsRequestNamesTheVersionAndCarriesTheSession() {
        let origin = URL(string: "https://midas.example")!
        let request = RemoteSidekickToolsFetcher.toolsRequest(platformOrigin: origin, sidekickId: "reminders", version: "v3", token: "abc")
        XCTAssertEqual(request.url?.absoluteString, "https://midas.example/sidekicks/reminders/tools.js?version=v3")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
    }

    // MARK: The directory keeps the agent block

    func testTheListingCarriesTheAgentBlockAndTheDirectoryCachesIt() async throws {
        let reply = """
        {"sidekicks":[
          {"id":"reminders","name":"Reminders","icon":{"symbol":"checklist","background":"#FF9500"},"reads":[],"version":"v2","agent":{"description":"Everyday reminders.","tools":[]}},
          {"id":"notes","name":"Notes","icon":{"symbol":"note.text","background":"#FFCC00"},"reads":[],"version":"n1"}
        ]}
        """
        let listings = try RemoteSidekickDirectoryFetcher.listings(from: Data(reply.utf8))
        XCTAssertEqual(listings[0].agent?["description"], .string("Everyday reminders."))
        XCTAssertNil(listings[1].agent)

        let cacheURL = folder.appending(path: "midas-sidekicks-test.json")
        let writer = SharedSidekickListWriter(fileURL: nil, now: Date.init, reloadWidgets: Self.reloadNothing)
        let directory = SidekickDirectory(cacheFileURL: cacheURL, fetcher: StubListingFetcher(listings: listings), sharedListWriter: writer)
        await directory.refresh()
        XCTAssertEqual(directory.agent(forSidekickId: "reminders")?["description"], .string("Everyday reminders."))
        XCTAssertNil(directory.agent(forSidekickId: "notes"))

        let relaunched = SidekickDirectory(cacheFileURL: cacheURL, fetcher: StubListingFetcher(listings: []), sharedListWriter: writer)
        XCTAssertEqual(relaunched.agent(forSidekickId: "reminders")?["description"], .string("Everyday reminders."))
        XCTAssertEqual(SidekickDirectory.agentsCacheFileURL(besides: cacheURL).lastPathComponent, "midas-sidekicks-test-agents.json")
    }
}
