import XCTest
@testable import Midas

// The one record validator on the phone: shell/sdk/record-schema.js and shell-types.js run in
// JavaScriptCore (unified data plan, section 3). The messages here are the same strings the
// backend fixtures (backend/test/record-schema.test.ts) expect from the same file.

private let itemTypes: JSONValue = .object([
    "reminder:": .object([
        "$type": .string("reminders.item"),
        "schema": .object([
            "type": .string("object"),
            "required": .array([.string("title")]),
            "properties": .object([
                "title": .object(["type": .string("string"), "minLength": .number(1)]),
                "at": .object(["type": .string("string"), "format": .string("date-time")]),
                "done": .object(["type": .string("boolean")]),
            ]),
        ]),
    ]),
])

@MainActor
final class RecordSchemaEngineTests: XCTestCase {
    private func makeEngine() throws -> RecordSchemaEngine {
        try RecordSchemaEngine(bundle: Bundle(for: RecordSchemaEngine.self))
    }

    /// The scripts the app ships are the repo's shell/sdk files, byte for byte, so the phone and
    /// the Worker never run different validators.
    func testTheAppShipsTheRepoValidatorUnchanged() throws {
        let appBundle = Bundle(for: RecordSchemaEngine.self)
        let sdkFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "sdk")
        for resourceName in [RecordSchemaEngine.validatorResourceName, RecordSchemaEngine.shellTypesResourceName] {
            let shippedURL = try XCTUnwrap(appBundle.url(forResource: resourceName, withExtension: "js"), "\(resourceName).js is not in the app bundle")
            let shipped = try String(contentsOf: shippedURL, encoding: .utf8)
            let source = try String(contentsOf: sdkFolder.appending(path: "\(resourceName).js"), encoding: .utf8)
            XCTAssertEqual(shipped, source, "\(resourceName).js in the app differs from shell/sdk")
        }
    }

    func testCheckRecordAcceptsAFitAndNamesTheProblemOtherwise() throws {
        let engine = try makeEngine()
        let good: JSONValue = .object(["$type": .string("reminders.item"), "title": .string("Call"), "at": .string("2026-10-15T09:30:00.000Z"), "extra": .bool(true)])
        XCTAssertNil(engine.checkRecord(types: itemTypes, key: "reminder:1", value: good))
        XCTAssertEqual(engine.checkRecord(types: itemTypes, key: "reminder:1", value: .object(["$type": .string("reminders.item"), "title": .string("")])), "reminders.item.title must not be empty")
        XCTAssertEqual(engine.checkRecord(types: itemTypes, key: "reminder:1", value: .object(["title": .string("Call")])), "reminders.item.$type must be \"reminders.item\"")
        XCTAssertEqual(engine.checkRecord(types: itemTypes, key: "reminder:1", value: .object(["$type": .string("reminders.item"), "title": .string("x"), "at": .number(1760515200000)])), "reminders.item.at must be a string, not a number")
        XCTAssertEqual(engine.checkRecord(types: itemTypes, key: "reminder:1", value: .object(["$type": .string("reminders.item"), "title": .string("x"), "done": .null])), "reminders.item.done must be true or false, not null")
        XCTAssertEqual(engine.checkRecord(types: itemTypes, key: "task:1", value: good), "no record type is declared for task:1")
        XCTAssertEqual(engine.checkRecord(types: itemTypes, key: "reminder:1", value: .string("text")), "reminders.item must be an object, not a string")
        // No types: a Sidekick from before schemas is not checked.
        XCTAssertNil(engine.checkRecord(types: nil, key: "task:1", value: .object(["anything": .number(1)])))
    }

    func testStampTypeAndTypeName() throws {
        let engine = try makeEngine()
        let stamped = engine.stampType(types: itemTypes, key: "reminder:1", value: .object(["title": .string("Call"), "$type": .string("wrong")]))
        XCTAssertEqual(stamped["$type"], .string("reminders.item"))
        XCTAssertEqual(stamped["title"], .string("Call"))
        XCTAssertEqual(engine.stampType(types: itemTypes, key: "task:1", value: .object(["title": .string("Call")])), .object(["title": .string("Call")]))
        XCTAssertEqual(engine.stampType(types: itemTypes, key: "reminder:1", value: .string("text")), .string("text"))
        XCTAssertEqual(engine.typeName(types: itemTypes, key: "reminder:9"), "reminders.item")
        XCTAssertNil(engine.typeName(types: itemTypes, key: "list:9"))
    }

    func testTheShellTypesAreLoadedAndApply() throws {
        let engine = try makeEngine()
        XCTAssertEqual(engine.typeName(types: engine.shellTypes, key: "widget:meds"), "midas.widget")
        XCTAssertEqual(engine.typeName(types: engine.shellTypes, key: "request:r1"), "midas.request")
        XCTAssertNil(engine.typeName(types: engine.shellTypes, key: "reminder:1"))
        XCTAssertEqual(engine.checkRecord(types: engine.shellTypes, key: "widget:meds", value: .object(["$type": .string("midas.widget"), "small": .object([:])])), "midas.widget.name is required")
        XCTAssertNil(engine.checkRecord(types: engine.shellTypes, key: "request:r1", value: .object(["$type": .string("midas.request"), "kind": .string("import.apple-reminders"), "status": .string("pending")])))
    }

    func testValidateOneSchemaChecksTheMidasFormats() throws {
        let engine = try makeEngine()
        let schema: JSONValue = .object(["type": .string("object"), "properties": .object([
            "at": .object(["type": .string("string"), "format": .string("date-time")]),
            "zone": .object(["type": .string("string"), "format": .string("time-zone")]),
            "time": .object(["type": .string("string"), "format": .string("wall-time")]),
        ])])
        XCTAssertNil(engine.validate(schema: schema, value: .object(["at": .string("2026-10-15T09:30:00+02:00"), "zone": .string("Asia/Kolkata"), "time": .string("09:30")]), typeName: "t"))
        XCTAssertEqual(engine.validate(schema: schema, value: .object(["at": .string("2026-10-15T09:30:00")]), typeName: "t"), "t.at must be an ISO 8601 date and time with an offset, like 2026-10-15T09:30:00.000Z")
        XCTAssertEqual(engine.validate(schema: schema, value: .object(["zone": .string("Mars/Olympus")]), typeName: "t"), "t.zone is not a known time zone")
        XCTAssertEqual(engine.validate(schema: schema, value: .object(["time": .string("9:30")]), typeName: "t"), "t.time must be a time like 09:30")
    }

    /// store.update merges in Swift (JSONMergePatch) and the SDK's documented rule is the JS
    /// mergePatch; both must give the same answer on the same cases.
    func testSwiftAndJavaScriptMergePatchAgree() throws {
        let engine = try makeEngine()
        let target: JSONValue = .object(["title": .string("Call"), "snoozedUntil": .string("2026-10-15T10:00:00Z"), "repeat": .object(["every": .string("week"), "interval": .number(2)]), "tags": .array([.string("a")])])
        let patch: JSONValue = .object(["snoozedUntil": .null, "done": .bool(true), "repeat": .object(["interval": .number(3)]), "tags": .array([.string("b")])])
        let expected: JSONValue = .object(["title": .string("Call"), "done": .bool(true), "repeat": .object(["every": .string("week"), "interval": .number(3)]), "tags": .array([.string("b")])])
        XCTAssertEqual(JSONMergePatch.apply(patch, to: target), expected)
        XCTAssertEqual(engine.mergePatch(target: target, patch: patch), expected)
        // A patch on nothing builds the record; a non-object patch replaces.
        let fromNothing: JSONValue = .object(["a": .object(["b": .number(1)]), "c": .null])
        XCTAssertEqual(JSONMergePatch.apply(fromNothing, to: nil), .object(["a": .object(["b": .number(1)])]))
        XCTAssertEqual(engine.mergePatch(target: nil, patch: fromNothing), .object(["a": .object(["b": .number(1)])]))
        XCTAssertEqual(JSONMergePatch.apply(.string("text"), to: target), .string("text"))
        XCTAssertEqual(engine.mergePatch(target: target, patch: .string("text")), .string("text"))
    }

    func testABrokenScriptIsAnError() {
        XCTAssertThrowsError(try RecordSchemaEngine(validatorSource: "this is not javascript(", shellTypesSource: "var MidasShellTypes = {};"))
    }
}
