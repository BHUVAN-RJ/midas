import XCTest
@testable import Midas

// Make's records, written (docs/briefs/make-contract.md sections 2, 3 and 8, founder 2026-10-24):
// every write goes through the store's gate with the built-in Sidekicks' types (native-types.js,
// a copy in this test bundle until the backend's file lands), H1's Send writes the request and its
// first message, the thread's words answer the open card or go as a message, a card is answered
// once, the founder's reply and status writes, and the center's change counter.

@MainActor
final class MakeWriterTests: XCTestCase {
    private var fileURL: URL!
    private var defaultsSuite = ""

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory.appending(path: "make-writer-\(UUID().uuidString).json")
        defaultsSuite = "make-writer-\(UUID().uuidString)"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
        super.tearDown()
    }

    /// The app's validator and shell types, and this bundle's native types.
    private func makeEngine(withNativeTypes: Bool = true) throws -> RecordSchemaEngine {
        let appBundle = Bundle(for: RecordSchemaEngine.self)
        let validatorURL = try XCTUnwrap(appBundle.url(forResource: "record-schema", withExtension: "js"))
        let shellTypesURL = try XCTUnwrap(appBundle.url(forResource: "shell-types", withExtension: "js"))
        let nativeTypesURL = try XCTUnwrap(Bundle(for: MakeWriterTests.self).url(forResource: "native-types", withExtension: "js"))
        let nativeTypesSource = withNativeTypes ? try String(contentsOf: nativeTypesURL, encoding: .utf8) : nil
        return try RecordSchemaEngine(
            validatorSource: String(contentsOf: validatorURL, encoding: .utf8),
            shellTypesSource: String(contentsOf: shellTypesURL, encoding: .utf8),
            nativeTypesSource: nativeTypesSource
        )
    }

    private static func noManifestTypes(sidekickId: String) -> JSONValue? {
        nil
    }

    private func makeGatedStore() throws -> LocalRecordStore {
        let store = LocalRecordStore(fileURL: fileURL)
        store.writeGate = RecordTypeGate.make(engine: try makeEngine(), typesProvider: Self.noManifestTypes)
        return store
    }

    private static let fixedNow = Date(timeIntervalSince1970: 1_792_000_000)

    private static func now() -> Date {
        fixedNow
    }

    private func makeWriter(_ store: LocalRecordStore) -> MakeWriter {
        MakeWriter(store: store, now: Self.now)
    }

    private func personRecords(_ store: LocalRecordStore) -> [LocalRecord] {
        store.query(sidekickId: MakeSidekick.id, keyPrefix: "")
    }

    private func putCard(_ store: LocalRecordStore, cardId: String, ownWords: Bool, sidekickId: String = MakeSidekick.id, key: String? = nil) throws {
        let card: JSONValue = .object([
            "question": .string("Forgetting or not knowing when?"),
            "kind": .string("choice"),
            "options": .array([.object(["id": .string("option001"), "label": .string("Forgetting")])]),
            "allowsOwnWords": .bool(ownWords),
            "sentAt": .string("2026-10-14T10:00:00.000Z"),
        ])
        try store.set(sidekickId: sidekickId, key: key ?? "card:request01:\(cardId)", value: card)
    }

    // MARK: Native types

    func testTheEngineLoadsTheBuiltInSidekicksTypesWhenShipped() throws {
        let engine = try makeEngine()
        XCTAssertEqual(Set(engine.nativeTypes.keys), [MakeSidekick.id, MakeSidekick.inboxId])
        XCTAssertEqual(engine.typeName(types: engine.nativeTypes[MakeSidekick.id], key: "req:abc"), "make.request")
        XCTAssertEqual(engine.typeName(types: engine.nativeTypes[MakeSidekick.inboxId], key: "person:u1"), "make.person")

        let withoutFile = try makeEngine(withNativeTypes: false)
        XCTAssertTrue(withoutFile.nativeTypes.isEmpty, "an app built without native-types.js still starts")
    }

    func testShellTypesWinThenNativeTypesThenTheManifest() throws {
        let engine = try makeEngine()
        func manifestTypes(sidekickId: String) -> JSONValue? {
            .object(["note:": .object(["$type": .string("page.note"), "schema": .object(["type": .string("object")])])])
        }
        let shell = RecordTypeGate.typesFor(key: "request:abc", sidekickId: MakeSidekick.id, engine: engine, typesProvider: manifestTypes)
        XCTAssertEqual(shell, engine.shellTypes, "request: is the shell's in every Sidekick, Make included")
        let native = RecordTypeGate.typesFor(key: "req:abc", sidekickId: MakeSidekick.id, engine: engine, typesProvider: manifestTypes)
        XCTAssertEqual(native, engine.nativeTypes[MakeSidekick.id])
        let manifest = RecordTypeGate.typesFor(key: "note:1", sidekickId: "notes", engine: engine, typesProvider: manifestTypes)
        XCTAssertEqual(manifest, manifestTypes(sidekickId: "notes"))
    }

    func testTheGateRefusesRecordsThatBreakTheContract() throws {
        let store = try makeGatedStore()
        let time = JSONValue.string("2026-10-14T10:00:00.000Z")
        let bothAnswers: JSONValue = .object(["cardId": .string("card00001"), "optionId": .string("option001"), "text": .string("Both"), "sentAt": time])
        XCTAssertThrowsError(try store.set(sidekickId: MakeSidekick.id, key: "answer:request01:card00001", value: bothAnswers))
        let builtWithoutPlan: JSONValue = .object(["title": .string("Plants"), "status": .string("built"), "createdAt": time, "updatedAt": time, "sidekickId": .string("plants")])
        XCTAssertThrowsError(try store.set(sidekickId: MakeSidekick.inboxId, key: "req:user0001:request01", value: builtWithoutPlan))
        let fromNobody: JSONValue = .object(["from": .string("bot"), "text": .string("Hi"), "sentAt": time])
        XCTAssertThrowsError(try store.set(sidekickId: MakeSidekick.id, key: "message:request01:message01", value: fromNobody))
        XCTAssertTrue(personRecords(store).isEmpty)
        XCTAssertEqual(store.pendingOpCount, 0)
    }

    // MARK: The person's side

    func testNewRequestWritesASentRequestAndItsFirstMessage() throws {
        let store = try makeGatedStore()
        let writer = makeWriter(store)
        let words = "  My plants keep dying. I forget to water them.  "
        let reqId = try XCTUnwrap(writer.newRequest(words: words))
        XCTAssertEqual(reqId.count, 32)

        let request = try XCTUnwrap(store.get(sidekickId: MakeSidekick.id, key: "req:\(reqId)"))
        XCTAssertEqual(request["$type"], .string("make.request"))
        XCTAssertEqual(request["status"], .string("sent"))
        XCTAssertEqual(request["title"], .string("My plants keep dying. I forget to water them."))
        XCTAssertEqual(request["createdAt"], .string(MakeTime.string(Self.fixedNow)))
        XCTAssertNil(request["sidekickId"])

        let messages = store.query(sidekickId: MakeSidekick.id, keyPrefix: "message:\(reqId):")
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.value["from"], .string("person"))
        XCTAssertEqual(messages.first?.value["text"], .string("My plants keep dying. I forget to water them."))
        XCTAssertEqual(messages.first?.value["$type"], .string("make.message"))
        XCTAssertEqual(store.pendingOpCount, 2)
    }

    func testTheTitleIsTheWordsUpTo200AndEmptyWordsWriteNothing() throws {
        let store = try makeGatedStore()
        let writer = makeWriter(store)
        XCTAssertNil(try writer.newRequest(words: "   \n "))
        XCTAssertTrue(personRecords(store).isEmpty)

        let long = String(repeating: "a", count: 250)
        let reqId = try XCTUnwrap(writer.newRequest(words: long))
        let title = store.get(sidekickId: MakeSidekick.id, key: "req:\(reqId)")?["title"]?.stringValue
        XCTAssertEqual(title?.count, 200)
        let text = store.query(sidekickId: MakeSidekick.id, keyPrefix: "message:\(reqId):").first?.value["text"]?.stringValue
        XCTAssertEqual(text?.count, 250, "the message keeps every word")
    }

    func testThreadWordsAnswerTheOpenCardThatTakesOwnWordsThenGoAsMessages() throws {
        let store = try makeGatedStore()
        let writer = makeWriter(store)
        try putCard(store, cardId: "card00001", ownWords: true)
        let ref = MakeThreadRef(userId: nil, reqId: "request01")

        try writer.send(words: "Both, honestly", in: MakeRecords.thread(ref, in: personRecords(store)), reqId: "request01")
        let answer = try XCTUnwrap(store.get(sidekickId: MakeSidekick.id, key: "answer:request01:card00001"))
        XCTAssertEqual(answer["text"], .string("Both, honestly"))
        XCTAssertNil(answer["optionId"])
        XCTAssertEqual(answer["$type"], .string("make.answer"))

        // The card is answered now: the next words are a message
        try writer.send(words: "Also the cactus", in: MakeRecords.thread(ref, in: personRecords(store)), reqId: "request01")
        let messages = store.query(sidekickId: MakeSidekick.id, keyPrefix: "message:request01:")
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.value["text"], .string("Also the cactus"))
    }

    func testACardWithoutOwnWordsLeavesThePillsWordsAsAMessage() throws {
        let store = try makeGatedStore()
        let writer = makeWriter(store)
        try putCard(store, cardId: "card00002", ownWords: false)
        let ref = MakeThreadRef(userId: nil, reqId: "request01")
        try writer.send(words: "Not sure", in: MakeRecords.thread(ref, in: personRecords(store)), reqId: "request01")
        XCTAssertNil(store.get(sidekickId: MakeSidekick.id, key: "answer:request01:card00002"))
        XCTAssertEqual(store.query(sidekickId: MakeSidekick.id, keyPrefix: "message:request01:").count, 1)
    }

    func testACardIsAnsweredOnce() throws {
        let store = try makeGatedStore()
        let writer = makeWriter(store)
        try putCard(store, cardId: "card00003", ownWords: true)
        try writer.answer(reqId: "request01", cardId: "card00003", optionId: "option001", text: nil)
        try writer.answer(reqId: "request01", cardId: "card00003", optionId: "option999", text: nil)
        let answer = store.get(sidekickId: MakeSidekick.id, key: "answer:request01:card00003")
        XCTAssertEqual(answer?["optionId"], .string("option001"))
        XCTAssertEqual(store.query(sidekickId: MakeSidekick.id, keyPrefix: "answer:").count, 1)
        XCTAssertEqual(store.pendingOpCount, 2, "the card and one answer; the second Send wrote nothing")
    }

    // MARK: The founder's side

    func testTheFoundersReplyIsAMakerMessageCarryingTheUserId() throws {
        let store = try makeGatedStore()
        let writer = makeWriter(store)
        try writer.reply(words: "Ferns or cactus?", userId: "user0001", reqId: "request01")
        let messages = store.query(sidekickId: MakeSidekick.inboxId, keyPrefix: "message:user0001:request01:")
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.value["from"], .string("maker"))
        XCTAssertEqual(messages.first?.value["userId"], .string("user0001"))
        XCTAssertEqual(messages.first?.value["$type"], .string("make.message"))
        XCTAssertTrue(personRecords(store).isEmpty, "the server copies it to the person; the phone writes only the inbox")
    }

    func testStatusWritesKeepUnknownFieldsAndBuiltNeedsTheSidekickAndPlan() throws {
        let store = try makeGatedStore()
        let writer = makeWriter(store)
        let key = "req:user0001:request01"
        let original: JSONValue = .object([
            "title": .string("Plants"),
            "status": .string("sent"),
            "createdAt": .string("2026-10-13T10:00:00.000Z"),
            "updatedAt": .string("2026-10-13T10:00:00.000Z"),
            "userId": .string("user0001"),
            "fromANewerServer": .string("kept"),
        ])
        try store.set(sidekickId: MakeSidekick.inboxId, key: key, value: original)
        func currentRequest() throws -> MakeRequest {
            let records = store.query(sidekickId: MakeSidekick.inboxId, keyPrefix: "")
            return try XCTUnwrap(MakeRecords.requests(in: records, inInbox: true).first)
        }

        try writer.setStatus(.looking, request: currentRequest())
        let looking = try XCTUnwrap(store.get(sidekickId: MakeSidekick.inboxId, key: key))
        XCTAssertEqual(looking["status"], .string("looking"))
        XCTAssertEqual(looking["fromANewerServer"], .string("kept"))
        XCTAssertEqual(looking["createdAt"], .string("2026-10-13T10:00:00.000Z"))
        XCTAssertEqual(looking["updatedAt"], .string(MakeTime.string(Self.fixedNow)))

        // Built without a plan is not written
        try writer.setStatus(.built, request: currentRequest(), sidekickId: "plants", plan: "  ")
        XCTAssertEqual(store.get(sidekickId: MakeSidekick.inboxId, key: key)?["status"], .string("looking"))

        try writer.setStatus(.built, request: currentRequest(), sidekickId: "plants", plan: "Ferns weekly, cactus monthly")
        let built = try XCTUnwrap(store.get(sidekickId: MakeSidekick.inboxId, key: key))
        XCTAssertEqual(built["status"], .string("built"))
        XCTAssertEqual(built["sidekickId"], .string("plants"))
        XCTAssertEqual(built["plan"], .string("Ferns weekly, cactus monthly"))
        XCTAssertEqual(built["builtAt"], .string(MakeTime.string(Self.fixedNow)))
        XCTAssertEqual(built["$type"], .string("make.request"))
    }

    // MARK: The center

    private static func noSync() async {}

    private func makeCenter(_ store: LocalRecordStore) throws -> MakeCenter {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        let api = MakeAPI(platformOrigin: URL(string: "https://example.invalid")!, session: .shared, sessionToken: Self.noToken)
        return MakeCenter(store: store, api: api, defaults: defaults, sync: Self.noSync)
    }

    nonisolated private static func noToken() -> String? {
        nil
    }

    func testTheCenterRedrawsOnMakeAndInboxRecordsOnly() throws {
        let store = LocalRecordStore(fileURL: fileURL)
        let center = try makeCenter(store)
        XCTAssertEqual(center.revision, 0)
        try store.set(sidekickId: "reminders", key: "reminder:1", value: .object(["title": .string("Call")]))
        XCTAssertEqual(center.revision, 0)
        try store.set(sidekickId: MakeSidekick.id, key: "message:r1:m1", value: .object(["from": .string("person")]))
        XCTAssertEqual(center.revision, 1)
        try store.applyRemote(ops: [RemoteOp(seq: 1, opId: "op1", sidekickId: MakeSidekick.inboxId, key: "person:u1", value: .object(["name": .string("Priya")]), deleted: false)], lastSeq: 1)
        XCTAssertEqual(center.revision, 2, "a pulled inbox record redraws too")
    }

    func testABuiltRequestPlaysItsBuiltScreenOncePerPhone() throws {
        let store = LocalRecordStore(fileURL: fileURL)
        let center = try makeCenter(store)
        let time = JSONValue.string("2026-10-14T10:00:00.000Z")
        try store.set(sidekickId: MakeSidekick.id, key: "req:request01", value: .object(["title": .string("Plants"), "status": .string("looking"), "createdAt": time, "updatedAt": time]))
        XCTAssertNil(center.unshownBuilt(), "not built yet")
        try store.set(sidekickId: MakeSidekick.id, key: "req:request01", value: .object(["title": .string("Plants"), "status": .string("built"), "createdAt": time, "updatedAt": time, "sidekickId": .string("plants"), "plan": .string("Water"), "builtAt": time]))
        XCTAssertEqual(center.unshownBuilt()?.reqId, "request01")
        center.builtShown.insert("request01")
        XCTAssertNil(center.unshownBuilt())
        // Remembered across launches
        let again = try makeCenter(store)
        XCTAssertNil(again.unshownBuilt())
    }
}
