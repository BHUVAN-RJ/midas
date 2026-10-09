import XCTest
@testable import Midas

@MainActor
final class SidekickStoreChannelTests: XCTestCase {
    private var storeFileURL: URL!
    private var store: LocalRecordStore!

    override func setUp() {
        super.setUp()
        let temporaryDirectory = FileManager.default.temporaryDirectory
        storeFileURL = temporaryDirectory.appending(path: "channel-records-\(UUID().uuidString).json")
        store = LocalRecordStore(fileURL: storeFileURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeFileURL)
        super.tearDown()
    }

    private func send(_ channel: SidekickStoreChannel, sidekickId: String, _ requestJSON: String) -> SidekickStoreChannel.Reply {
        channel.handle(sidekickId: sidekickId, requestBody: Data(requestJSON.utf8))
    }

    func testSetStoresUnderTheCallingSidekick() {
        let channel = SidekickStoreChannel(store: store)
        let reply = send(channel, sidekickId: "reminders", #"{"op":"set","key":"note:1","value":{"text":"hi"}}"#)
        XCTAssertEqual(reply.statusCode, 200)
        XCTAssertEqual(store.get(sidekickId: "reminders", key: "note:1")?["text"]?.stringValue, "hi")
        XCTAssertNil(store.get(sidekickId: "calendar", key: "note:1"))
    }

    func testGetReturnsValueOrNull() throws {
        try store.set(sidekickId: "reminders", key: "note:1", value: .string("hi"))
        let channel = SidekickStoreChannel(store: store)
        let foundReply = send(channel, sidekickId: "reminders", #"{"op":"get","key":"note:1"}"#)
        let missingReply = send(channel, sidekickId: "reminders", #"{"op":"get","key":"note:2"}"#)
        XCTAssertEqual(foundReply.body["value"], .string("hi"))
        XCTAssertEqual(missingReply.body["value"], .null)
    }

    func testQueryReturnsKeyValuePairs() throws {
        try store.set(sidekickId: "reminders", key: "note:1", value: .number(1))
        try store.set(sidekickId: "reminders", key: "other:1", value: .number(2))
        let channel = SidekickStoreChannel(store: store)
        let reply = send(channel, sidekickId: "reminders", #"{"op":"query","prefix":"note:"}"#)
        let records = reply.body["records"]?.arrayValue
        XCTAssertEqual(records?.count, 1)
        XCTAssertEqual(records?.first?["key"], .string("note:1"))
        XCTAssertEqual(records?.first?["value"], .number(1))
    }

    func testDeleteRemovesTheRecord() throws {
        try store.set(sidekickId: "reminders", key: "note:1", value: .number(1))
        let channel = SidekickStoreChannel(store: store)
        let reply = send(channel, sidekickId: "reminders", #"{"op":"delete","key":"note:1"}"#)
        XCTAssertEqual(reply.statusCode, 200)
        XCTAssertNil(store.get(sidekickId: "reminders", key: "note:1"))
    }

    func testBadRequestsAreRejectedWith400() {
        let channel = SidekickStoreChannel(store: store)
        let badBodies = [
            "not json",
            #"{"key":"a"}"#,
            #"{"op":"explode","key":"a"}"#,
            #"{"op":"set","value":1}"#,
            #"{"op":"set","key":"","value":1}"#,
            #"{"op":"set","key":"a"}"#,
        ]
        for badBody in badBodies {
            let reply = send(channel, sidekickId: "reminders", badBody)
            XCTAssertEqual(reply.statusCode, 400, "accepted: \(badBody)")
            XCTAssertEqual(reply.body["ok"], .bool(false))
        }
        XCTAssertEqual(store.queryAllSidekicks(keyPrefix: ""), [])
    }

    func testReservedPrefixValidatorRejectsBadValues() {
        func requireTitle(_ value: JSONValue) -> String? {
            value["title"] == nil ? "title required" : nil
        }
        let channel = SidekickStoreChannel(store: store, reservedValidators: ["reminder:": requireTitle])
        let rejectedReply = send(channel, sidekickId: "reminders", #"{"op":"set","key":"reminder:1","value":{}}"#)
        let acceptedReply = send(channel, sidekickId: "reminders", #"{"op":"set","key":"reminder:2","value":{"title":"x"}}"#)
        XCTAssertEqual(rejectedReply.statusCode, 400)
        XCTAssertEqual(rejectedReply.body["error"], .string("title required"))
        XCTAssertNil(store.get(sidekickId: "reminders", key: "reminder:1"))
        XCTAssertEqual(acceptedReply.statusCode, 200)
    }
}
