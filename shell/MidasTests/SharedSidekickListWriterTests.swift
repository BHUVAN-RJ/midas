import XCTest
@testable import Midas

/// Counts widget reloads so a test can tell whether the writer asked WidgetKit to redraw.
private final class ReloadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

/// Returns a fixed list, as GET /sidekicks would.
private struct FixedDirectoryFetcher: SidekickDirectoryFetching {
    let entries: [SidekickEntry]

    func fetchSidekicks() async throws -> [SidekickEntry] {
        entries
    }
}

private let remindersEntry = SidekickEntry(id: "reminders", name: "Reminders", symbolName: "checklist", backgroundHex: "#FF9500", version: "v2")
private let calendarEntry = SidekickEntry(id: "calendar", name: "Calendar", symbolName: "calendar", backgroundHex: "#FF3B30", version: "c1")
private let groceriesEntry = SidekickEntry(id: "groceries", name: "Groceries", symbolName: "cart", backgroundHex: "#30D5C8", version: "g1")

private let fixedNow = Date(timeIntervalSince1970: 1_791_700_000)

/// The app side of the widget contract: the list the home grid shows lands in the App Group file.
final class SharedSidekickListWriterTests: XCTestCase {
    private var sharedFileURL: URL!
    private var cacheFileURL: URL!
    private var reloads: ReloadCounter!

    override func setUp() async throws {
        let uniqueName = UUID().uuidString
        sharedFileURL = FileManager.default.temporaryDirectory.appending(path: "widget-list-\(uniqueName).json")
        cacheFileURL = FileManager.default.temporaryDirectory.appending(path: "directory-cache-\(uniqueName).json")
        reloads = ReloadCounter()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: sharedFileURL)
        try? FileManager.default.removeItem(at: cacheFileURL)
    }

    private func makeWriter(fileURL: URL?) -> SharedSidekickListWriter {
        let counter = reloads!
        return SharedSidekickListWriter(fileURL: fileURL, now: { fixedNow }, reloadWidgets: counter.increment)
    }

    private func readSharedList() throws -> SharedSidekickList {
        let data = try Data(contentsOf: sharedFileURL)
        return try XCTUnwrap(SharedSidekickList.decoded(from: data))
    }

    func testWritesTheListInOrderAtTheSharedPathAndReloadsWidgets() throws {
        let writer = makeWriter(fileURL: sharedFileURL)
        writer.write(entries: [calendarEntry, remindersEntry, groceriesEntry])

        let savedList = try readSharedList()
        XCTAssertEqual(savedList.sidekicks, [calendarEntry, remindersEntry, groceriesEntry])
        XCTAssertEqual(savedList.savedAt, fixedNow)
        XCTAssertEqual(reloads.value, 1)
    }

    func testANewListReplacesTheOldOne() throws {
        let writer = makeWriter(fileURL: sharedFileURL)
        writer.write(entries: [remindersEntry, calendarEntry])
        writer.write(entries: [groceriesEntry])

        let savedList = try readSharedList()
        XCTAssertEqual(savedList.sidekicks, [groceriesEntry])
        XCTAssertEqual(reloads.value, 2)
    }

    func testDoesNothingWithoutAnAppGroup() {
        let writer = makeWriter(fileURL: nil)
        writer.write(entries: [remindersEntry])

        XCTAssertFalse(FileManager.default.fileExists(atPath: sharedFileURL.path))
        XCTAssertEqual(reloads.value, 0)
    }

    @MainActor
    func testADirectoryRefreshWritesTheServerList() async throws {
        let fetcher = FixedDirectoryFetcher(entries: [groceriesEntry, remindersEntry])
        let directory = SidekickDirectory(cacheFileURL: cacheFileURL, fetcher: fetcher, sharedListWriter: makeWriter(fileURL: sharedFileURL))
        let reloadsBeforeRefresh = reloads.value

        await directory.refresh()

        let savedList = try readSharedList()
        XCTAssertEqual(savedList.sidekicks, [groceriesEntry, remindersEntry])
        XCTAssertEqual(reloads.value, reloadsBeforeRefresh + 1)
    }

    // A widget must show Sidekicks before the first server answer: the cached list goes out at launch.
    @MainActor
    func testLaunchWritesTheCachedList() async throws {
        let firstFetcher = FixedDirectoryFetcher(entries: [calendarEntry, groceriesEntry])
        let firstLaunch = SidekickDirectory(cacheFileURL: cacheFileURL, fetcher: firstFetcher, sharedListWriter: makeWriter(fileURL: sharedFileURL))
        await firstLaunch.refresh()
        try FileManager.default.removeItem(at: sharedFileURL)

        let offlineFetcher = FixedDirectoryFetcher(entries: [])
        let secondLaunch = SidekickDirectory(cacheFileURL: cacheFileURL, fetcher: offlineFetcher, sharedListWriter: makeWriter(fileURL: sharedFileURL))
        XCTAssertEqual(secondLaunch.entries, [calendarEntry, groceriesEntry])

        let savedList = try readSharedList()
        XCTAssertEqual(savedList.sidekicks, [calendarEntry, groceriesEntry])
    }
}
