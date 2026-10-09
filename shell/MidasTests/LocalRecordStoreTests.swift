import XCTest
@testable import Midas

@MainActor
final class LocalRecordStoreTests: XCTestCase {
    private var storeFileURL: URL!

    override func setUp() {
        super.setUp()
        let temporaryDirectory = FileManager.default.temporaryDirectory
        storeFileURL = temporaryDirectory.appending(path: "local-records-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeFileURL)
        super.tearDown()
    }

    func testSetThenGetReturnsTheValue() throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        try store.set(sidekickId: "reminders", key: "reminder:1", value: .object(["title": .string("Call mom")]))
        let storedValue = store.get(sidekickId: "reminders", key: "reminder:1")
        XCTAssertEqual(storedValue?["title"]?.stringValue, "Call mom")
    }

    func testRecordsSurviveARestart() throws {
        let firstStore = LocalRecordStore(fileURL: storeFileURL)
        try firstStore.set(sidekickId: "reminders", key: "reminder:1", value: .string("kept"))
        let reopenedStore = LocalRecordStore(fileURL: storeFileURL)
        XCTAssertEqual(reopenedStore.get(sidekickId: "reminders", key: "reminder:1"), .string("kept"))
    }

    func testDeleteRemovesTheRecordAcrossARestart() throws {
        let firstStore = LocalRecordStore(fileURL: storeFileURL)
        try firstStore.set(sidekickId: "reminders", key: "reminder:1", value: .string("gone soon"))
        try firstStore.delete(sidekickId: "reminders", key: "reminder:1")
        let reopenedStore = LocalRecordStore(fileURL: storeFileURL)
        XCTAssertNil(reopenedStore.get(sidekickId: "reminders", key: "reminder:1"))
    }

    func testSidekicksCannotSeeEachOthersRecords() throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        try store.set(sidekickId: "reminders", key: "reminder:1", value: .string("mine"))
        XCTAssertNil(store.get(sidekickId: "calendar", key: "reminder:1"))
        XCTAssertEqual(store.query(sidekickId: "calendar", keyPrefix: "reminder:"), [])
    }

    func testQueryReturnsOnlyMatchingPrefixSortedByKey() throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        try store.set(sidekickId: "reminders", key: "reminder:b", value: .number(2))
        try store.set(sidekickId: "reminders", key: "list:x", value: .number(9))
        try store.set(sidekickId: "reminders", key: "reminder:a", value: .number(1))
        let matchingRecords = store.query(sidekickId: "reminders", keyPrefix: "reminder:")
        let matchingKeys = matchingRecords.map(\.key)
        XCTAssertEqual(matchingKeys, ["reminder:a", "reminder:b"])
    }

    func testShellQueryAcrossSidekicksSeesEveryOwner() throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        try store.set(sidekickId: "reminders", key: "reminder:1", value: .number(1))
        try store.set(sidekickId: "birthdays", key: "reminder:1", value: .number(2))
        let allReminders = store.queryAllSidekicks(keyPrefix: "reminder:")
        let owners = allReminders.map(\.sidekickId)
        XCTAssertEqual(owners, ["birthdays", "reminders"])
    }

    func testObserversHearSetsAndDeletesButNotNoOpDeletes() throws {
        let store = LocalRecordStore(fileURL: storeFileURL)
        var heardChanges: [LocalRecordChange] = []
        func recordChange(_ change: LocalRecordChange) {
            heardChanges.append(change)
        }
        store.addChangeObserver(recordChange)
        try store.set(sidekickId: "reminders", key: "reminder:1", value: .number(1))
        try store.delete(sidekickId: "reminders", key: "reminder:1")
        try store.delete(sidekickId: "reminders", key: "reminder:never-existed")
        let expectedChange = LocalRecordChange(sidekickId: "reminders", key: "reminder:1")
        XCTAssertEqual(heardChanges, [expectedChange, expectedChange])
    }

    func testCorruptFileStartsAnEmptyStore() throws {
        try Data("not json".utf8).write(to: storeFileURL)
        let store = LocalRecordStore(fileURL: storeFileURL)
        XCTAssertEqual(store.queryAllSidekicks(keyPrefix: ""), [])
    }
}
