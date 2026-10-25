import XCTest
@testable import Midas

// Make's records, read (docs/briefs/make-contract.md section 2, founder 2026-10-24): the keys of
// the person's `make` store and the founder's `make-inbox` store, the request list (H1, newest
// updatedAt first), a thread in order (T2, Built last), which card the pill answers, each row's
// last line and unread count (on the phone only), the people in the inbox, the status words (S2).

private let base = Date(timeIntervalSince1970: 1_792_000_000)

/// A time `minutes` after the base, as a record carries it.
private func at(_ minutes: Double) -> JSONValue {
    .string(MakeTime.string(base.addingTimeInterval(minutes * 60)))
}

private func makeRecord(_ key: String, _ fields: [String: JSONValue], sidekickId: String = MakeSidekick.id) -> LocalRecord {
    LocalRecord(sidekickId: sidekickId, key: key, value: .object(fields))
}

private func request(_ title: String, status: String = "sent", created: Double, updated: Double, extra: [String: JSONValue] = [:]) -> [String: JSONValue] {
    var fields: [String: JSONValue] = ["title": .string(title), "status": .string(status), "createdAt": at(created), "updatedAt": at(updated)]
    for (name, value) in extra {
        fields[name] = value
    }
    return fields
}

private func message(_ from: String, _ text: String, _ minutes: Double) -> [String: JSONValue] {
    ["from": .string(from), "text": .string(text), "sentAt": at(minutes)]
}

private func choiceCard(_ question: String, options: [(String, String)], ownWords: Bool, _ minutes: Double) -> [String: JSONValue] {
    var optionValues: [JSONValue] = []
    for (optionId, label) in options {
        optionValues.append(.object(["id": .string(optionId), "label": .string(label)]))
    }
    return ["question": .string(question), "kind": .string("choice"), "options": .array(optionValues), "allowsOwnWords": .bool(ownWords), "sentAt": at(minutes)]
}

private func designCard(_ optionIds: [String], _ minutes: Double) -> [String: JSONValue] {
    var optionValues: [JSONValue] = []
    for optionId in optionIds {
        optionValues.append(.object(["id": .string(optionId), "image": .string("file:img\(optionId)")]))
    }
    return ["question": .string("Pick one"), "kind": .string("design"), "options": .array(optionValues), "allowsOwnWords": .bool(false), "sentAt": at(minutes)]
}

@MainActor
final class MakeRecordsTests: XCTestCase {
    private var defaultsSuite = ""

    override func setUp() {
        super.setUp()
        defaultsSuite = "make-records-\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
        super.tearDown()
    }

    // MARK: Keys

    func testKeysOfBothStoresReadAndWriteTheContractShapes() {
        XCTAssertEqual(MakeKey.parse("req:r1", inInbox: false), .request(userId: nil, reqId: "r1"))
        XCTAssertEqual(MakeKey.parse("message:r1:m1", inInbox: false), .message(userId: nil, reqId: "r1", msgId: "m1"))
        XCTAssertEqual(MakeKey.parse("card:r1:c1", inInbox: false), .card(userId: nil, reqId: "r1", cardId: "c1"))
        XCTAssertEqual(MakeKey.parse("answer:r1:c1", inInbox: false), .answer(userId: nil, reqId: "r1", cardId: "c1"))
        XCTAssertEqual(MakeKey.parse("req:u1:r1", inInbox: true), .request(userId: "u1", reqId: "r1"))
        XCTAssertEqual(MakeKey.parse("message:u1:r1:m1", inInbox: true), .message(userId: "u1", reqId: "r1", msgId: "m1"))
        XCTAssertEqual(MakeKey.parse("answer:u1:r1:c1", inInbox: true), .answer(userId: "u1", reqId: "r1", cardId: "c1"))
        XCTAssertEqual(MakeKey.parse("person:u1", inInbox: true), .person(userId: "u1"))

        // Wrong part counts, empty parts and other prefixes are not Make's
        XCTAssertNil(MakeKey.parse("req:", inInbox: false))
        XCTAssertNil(MakeKey.parse("message:r1", inInbox: false))
        XCTAssertNil(MakeKey.parse("req:u1:r1", inInbox: false), "the person's store has no user id in its keys")
        XCTAssertNil(MakeKey.parse("person:u1", inInbox: false), "people live only in the inbox")
        XCTAssertNil(MakeKey.parse("widget:main", inInbox: false))
        XCTAssertNil(MakeKey.parse("req:u1::r1", inInbox: true))

        XCTAssertEqual(MakeKey.message(userId: nil, reqId: "r1", msgId: "m1").key, "message:r1:m1")
        XCTAssertEqual(MakeKey.card(userId: "u1", reqId: "r1", cardId: "c1").key, "card:u1:r1:c1")
        XCTAssertEqual(MakeKey.person(userId: "u1").key, "person:u1")
        XCTAssertEqual(MakeKey.request(userId: "u1", reqId: "r1").key, "req:u1:r1", "the request key is req:, not request: (shell types own request:)")
    }

    func testNewIdsMatchTheContractPattern() throws {
        let pattern = try NSRegularExpression(pattern: "^[A-Za-z0-9_-]{8,40}$")
        let first = MakeIds.new()
        let second = MakeIds.new()
        XCTAssertEqual(first.count, 32)
        XCTAssertFalse(first.contains("-"))
        XCTAssertNotEqual(first, second)
        let range = NSRange(location: 0, length: (first as NSString).length)
        XCTAssertNotNil(pattern.firstMatch(in: first, range: range))
    }

    // MARK: H1

    func testRequestsAreListedNewestUpdatedFirst() {
        let records = [
            makeRecord("req:old", request("Old", created: 0, updated: 10)),
            makeRecord("req:new", request("New", status: "looking", created: 5, updated: 50)),
            makeRecord("req:mid", request("Mid", status: "figuring_out", created: 1, updated: 30)),
            makeRecord("message:new:m1", message("person", "New", 5)),
        ]
        let requests = MakeRecords.requests(in: records, inInbox: false)
        XCTAssertEqual(requests.map(\.reqId), ["new", "mid", "old"])
        XCTAssertEqual(requests[0].status, .looking)
        XCTAssertEqual(requests[1].status, .figuringOut)
        XCTAssertNil(requests[0].userId)
    }

    func testTheInboxListsOnePersonsRequests() {
        let records = [
            makeRecord("req:u1:r1", request("Plants", created: 0, updated: 1), sidekickId: MakeSidekick.inboxId),
            makeRecord("req:u2:r2", request("Bills", created: 0, updated: 2), sidekickId: MakeSidekick.inboxId),
        ]
        let forFirst = MakeRecords.requests(in: records, inInbox: true, userId: "u1")
        XCTAssertEqual(forFirst.map(\.reqId), ["r1"])
        XCTAssertEqual(forFirst.first?.userId, "u1")
        XCTAssertEqual(forFirst.first?.ref, MakeThreadRef(userId: "u1", reqId: "r1"))
        XCTAssertEqual(MakeRecords.requests(in: records, inInbox: true).count, 2)
    }

    // MARK: T2

    func testAThreadIsInTimeOrderWithOwnWordsAfterTheirCardAndBuiltLast() {
        let records = [
            makeRecord("req:r1", request("Plants", status: "built", created: 0, updated: 90, extra: ["sidekickId": .string("plants"), "plan": .string("Water reminders"), "builtAt": at(90)])),
            makeRecord("message:r1:m2", message("maker", "On it", 20)),
            makeRecord("message:r1:m1", message("person", "My plants keep dying", 0)),
            makeRecord("card:r1:c1", choiceCard("Forgetting or not knowing when?", options: [("o1", "Forgetting"), ("o2", "Not knowing when")], ownWords: true, 10)),
            makeRecord("answer:r1:c1", ["cardId": .string("c1"), "text": .string("Both, honestly"), "sentAt": at(15)]),
            makeRecord("message:other:m9", message("person", "Another request", 5)),
        ]
        let thread = MakeRecords.thread(MakeThreadRef(userId: nil, reqId: "r1"), in: records)
        XCTAssertEqual(thread.items.map(\.id), ["m:m1", "c:c1", "a:c1", "m:m2", "b:r1"])
        XCTAssertEqual(thread.request?.plan, "Water reminders")
        XCTAssertEqual(thread.answers["c1"]?.text, "Both, honestly")
        XCTAssertEqual(thread.items.last?.speaker, .maker)
    }

    func testThePillAnswersOnlyTheNewestCardWhileItIsOpenAndTakesOwnWords() {
        let open = [
            makeRecord("card:r1:c1", choiceCard("First?", options: [("o1", "A")], ownWords: true, 1)),
            makeRecord("answer:r1:c1", ["cardId": .string("c1"), "optionId": .string("o1"), "sentAt": at(2)]),
            makeRecord("card:r1:c2", choiceCard("Second?", options: [("o3", "B")], ownWords: true, 3)),
        ]
        let openThread = MakeRecords.thread(MakeThreadRef(userId: nil, reqId: "r1"), in: open)
        XCTAssertEqual(openThread.openCard?.cardId, "c2")
        XCTAssertEqual(openThread.pillAnswersCard?.cardId, "c2")

        let noOwnWords = [makeRecord("card:r1:c3", choiceCard("Third?", options: [("o4", "C")], ownWords: false, 1))]
        let noOwnWordsThread = MakeRecords.thread(MakeThreadRef(userId: nil, reqId: "r1"), in: noOwnWords)
        XCTAssertEqual(noOwnWordsThread.openCard?.cardId, "c3")
        XCTAssertNil(noOwnWordsThread.pillAnswersCard, "a card without own words never takes the pill's words")

        // An older card left unanswered is not open once a newer card is answered
        let olderOpen = [
            makeRecord("card:r1:c1", choiceCard("First?", options: [("o1", "A")], ownWords: true, 1)),
            makeRecord("card:r1:c2", choiceCard("Second?", options: [("o3", "B")], ownWords: true, 3)),
            makeRecord("answer:r1:c2", ["cardId": .string("c2"), "optionId": .string("o3"), "sentAt": at(4)]),
        ]
        let olderOpenThread = MakeRecords.thread(MakeThreadRef(userId: nil, reqId: "r1"), in: olderOpen)
        XCTAssertNil(olderOpenThread.openCard)
        XCTAssertNil(olderOpenThread.pillAnswersCard)
    }

    // MARK: Rows

    func testTheLastLineSpeaksFromEachSide() {
        let ref = MakeThreadRef(userId: nil, reqId: "r1")
        let asked = [
            makeRecord("message:r1:m1", message("person", "Plants", 0)),
            makeRecord("card:r1:c1", choiceCard("Forgetting or not knowing when?", options: [("o1", "Forgetting")], ownWords: true, 10)),
        ]
        let askedThread = MakeRecords.thread(ref, in: asked)
        XCTAssertEqual(MakeRecords.lastLine(of: askedThread, forFounder: false), "\(MakeCopy.senderName): Forgetting or not knowing when?")

        // Picking an option is the person's, at the answer's time
        let picked = asked + [makeRecord("answer:r1:c1", ["cardId": .string("c1"), "optionId": .string("o1"), "sentAt": at(12)])]
        let pickedThread = MakeRecords.thread(ref, in: picked)
        XCTAssertEqual(MakeRecords.lastLine(of: pickedThread, forFounder: false), "You: Forgetting")

        let designs = [makeRecord("card:r1:c2", designCard(["d1", "d2", "d3"], 20))]
        let designThread = MakeRecords.thread(ref, in: designs)
        XCTAssertEqual(MakeRecords.lastLine(of: designThread, forFounder: false), "Bhuvan: 3 designs".replacingOccurrences(of: "Bhuvan", with: MakeCopy.senderName))

        let pickedDesign = designs + [makeRecord("answer:r1:c2", ["cardId": .string("c2"), "optionId": .string("d2"), "sentAt": at(21)])]
        let pickedDesignThread = MakeRecords.thread(ref, in: pickedDesign)
        XCTAssertEqual(MakeRecords.lastLine(of: pickedDesignThread, forFounder: false), "You: Picked B")

        // The founder reads the person's words plain and his own as "You"
        let inboxRef = MakeThreadRef(userId: "u1", reqId: "r1")
        let inbox = [
            makeRecord("message:u1:r1:m1", message("person", "build me an app for reminders", 0), sidekickId: MakeSidekick.inboxId),
        ]
        XCTAssertEqual(MakeRecords.lastLine(of: MakeRecords.thread(inboxRef, in: inbox), forFounder: true), "build me an app for reminders")
        let replied = inbox + [makeRecord("message:u1:r1:m2", message("maker", "On it", 3), sidekickId: MakeSidekick.inboxId)]
        XCTAssertEqual(MakeRecords.lastLine(of: MakeRecords.thread(inboxRef, in: replied), forFounder: true), "You: On it")

        XCTAssertNil(MakeRecords.lastLine(of: MakeRecords.thread(ref, in: []), forFounder: false))
    }

    func testUnreadCountsTheOtherSideSinceTheLastSeenItem() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        let marks = MakeReadMarks(defaults: defaults)
        let ref = MakeThreadRef(userId: nil, reqId: "r1")
        var records = [
            makeRecord("message:r1:m1", message("person", "Plants", 0)),
            makeRecord("message:r1:m2", message("maker", "On it", 5)),
            makeRecord("card:r1:c1", choiceCard("Forgetting?", options: [("o1", "Yes")], ownWords: true, 6)),
        ]
        XCTAssertEqual(marks.unreadCount(MakeRecords.thread(ref, in: records), ref: ref, forFounder: false), 2, "the founder's message and card are new to the person; the person's own words are not")
        XCTAssertEqual(marks.unreadCount(MakeRecords.thread(ref, in: records), ref: ref, forFounder: true), 1)

        marks.markSeen(MakeRecords.thread(ref, in: records), ref: ref)
        XCTAssertEqual(marks.unreadCount(MakeRecords.thread(ref, in: records), ref: ref, forFounder: false), 0)

        records.append(makeRecord("message:r1:m3", message("maker", "Ferns or cactus?", 9)))
        XCTAssertEqual(marks.unreadCount(MakeRecords.thread(ref, in: records), ref: ref, forFounder: false), 1)

        // Kept on the phone: a new reader over the same defaults remembers
        let reopened = MakeReadMarks(defaults: defaults)
        XCTAssertEqual(reopened.lastSeenAt(ref), base.addingTimeInterval(6 * 60))

        // An option picked is the person's: new to the founder
        let inboxRef = MakeThreadRef(userId: "u1", reqId: "r1")
        let inbox = [
            makeRecord("card:u1:r1:c1", choiceCard("Forgetting?", options: [("o1", "Yes")], ownWords: true, 6), sidekickId: MakeSidekick.inboxId),
            makeRecord("answer:u1:r1:c1", ["cardId": .string("c1"), "optionId": .string("o1"), "sentAt": at(7)], sidekickId: MakeSidekick.inboxId),
        ]
        XCTAssertEqual(marks.unreadCount(MakeRecords.thread(inboxRef, in: inbox), ref: inboxRef, forFounder: true), 1)
    }

    func testPeopleAreListedByTheirNewestRequest() {
        let records = [
            makeRecord("person:u1", ["name": .string("Priya"), "firstAt": at(0)], sidekickId: MakeSidekick.inboxId),
            makeRecord("person:u2", ["name": .string("Ana"), "firstAt": at(0)], sidekickId: MakeSidekick.inboxId),
            makeRecord("req:u1:r1", request("Reminders", created: 0, updated: 10), sidekickId: MakeSidekick.inboxId),
            makeRecord("req:u2:r2", request("Running", created: 0, updated: 40), sidekickId: MakeSidekick.inboxId),
            makeRecord("req:u3:r3", request("Plants", created: 0, updated: 20), sidekickId: MakeSidekick.inboxId),
        ]
        let people = MakeRecords.people(in: records)
        XCTAssertEqual(people.map(\.userId), ["u2", "u3", "u1"])
        XCTAssertEqual(people[0].name, "Ana")
        XCTAssertEqual(people[1].name, "", "a request before its person record still lists its person")
        XCTAssertEqual(MakeInboxSummary.displayName(people[1]), "u3")
    }

    // MARK: S2 and words

    func testStatusWordsStepsAndUnknownStatuses() {
        XCTAssertEqual(MakeStatus.allCases.map(\.word), ["Sent", "Figuring Out", "Looking", "Building", "Built"])
        XCTAssertEqual(MakeStatus.allCases.map(\.stepCount), [0, 1, 2, 3, 4])
        XCTAssertEqual(MakeStatus.allCases.map(\.rawValue), ["sent", "figuring_out", "looking", "building", "built"])
        XCTAssertEqual(MakeStatus.handSet, [.figuringOut, .looking, .building, .built])
        XCTAssertEqual(MakeStatus.parse("figuring_out"), .figuringOut)
        XCTAssertEqual(MakeStatus.parse("archived"), .sent)
        XCTAssertEqual(MakeStatus.parse(nil), .sent)
    }

    func testListTimesAreYesterdayTheWeekdayOrTheDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let locale = Locale(identifier: "en_US_POSIX")
        // Thursday 2026-10-22, 12:00 UTC
        let now = Date(timeIntervalSince1970: 1_792_670_400)
        let today = MakeTime.listLabel(now.addingTimeInterval(-2 * 3600), now: now, calendar: calendar, locale: locale)
        XCTAssertTrue(today.contains("10:00"), "today shows the time: \(today)")
        XCTAssertEqual(MakeTime.listLabel(now.addingTimeInterval(-24 * 3600), now: now, calendar: calendar, locale: locale), "Yesterday")
        XCTAssertEqual(MakeTime.listLabel(now.addingTimeInterval(-4 * 24 * 3600), now: now, calendar: calendar, locale: locale), "Sun")
        XCTAssertEqual(MakeTime.listLabel(now.addingTimeInterval(-10 * 24 * 3600), now: now, calendar: calendar, locale: locale), "Oct 12")
    }

    func testTimesRoundTripWithAndWithoutMilliseconds() {
        let date = Date(timeIntervalSince1970: 1_792_000_000.25)
        let text = MakeTime.string(date)
        XCTAssertTrue(text.hasSuffix("Z"))
        let parsed = MakeTime.parse(text)
        XCTAssertEqual(parsed?.timeIntervalSince1970 ?? 0, date.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(MakeTime.parse("2026-10-15T09:30:00Z")?.timeIntervalSince1970, 1_792_056_600)
        XCTAssertNil(MakeTime.parse("not a time"))
    }

    func testSubLineJoinsTheLastLineAndTheTime() {
        XCTAssertEqual(MakeRequestRow.subline(lastLine: "Bhuvan: 3 designs", time: "9:30 AM"), "Bhuvan: 3 designs · 9:30 AM")
        XCTAssertEqual(MakeRequestRow.subline(lastLine: nil, time: "Sun"), "Sun")
        XCTAssertNil(MakeRequestRow.subline(lastLine: "", time: nil))
    }
}
