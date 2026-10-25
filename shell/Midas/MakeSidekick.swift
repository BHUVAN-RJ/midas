import Foundation
import Observation
import SwiftUI

// Make (founder, 2026-10-23/24, docs/briefs/make.md, docs/briefs/make-contract.md): a Sidekick
// built into the shell, like jess. A person says what they need; the founder answers in a thread
// per request, sends question cards and design options, sets each request's status by hand, and
// at the end the request is Built and the new Sidekick is on the person's home grid. The founder
// has his own built-in Sidekick, the Inbox (`make-inbox`), listed only for him.
//
// Everything rides on the ordinary records and sync (contract section 2); the server copies a
// person's records into the founder's inbox and his replies back (section 3). This file holds the
// ids, the words, the record shapes, the reading and the writing; the screens are in
// MakeHomeView, MakeThreadView, MakeQuestionCardView, MakeBuiltView and MakeInboxView.

// MARK: - Ids and words

/// Make and the Inbox: native, not repairable, never a web bundle.
enum MakeSidekick {
    static let id = "make"
    static let inboxId = "make-inbox"

    static func isMake(_ sidekick: SidekickEntry) -> Bool {
        sidekick.id == id
    }

    static func isInbox(_ sidekick: SidekickEntry) -> Bool {
        sidekick.id == inboxId
    }

    /// The Sidekicks built into the shell (jess, Make, the Inbox): their swipe says repair is not
    /// available, and a Built request can never name one of them.
    static let builtInIds: Set<String> = [JessSidekick.id, id, inboxId]

    /// Make's listing as the server sends it (contract section 1), for a DEBUG build before the
    /// server lists it.
    static let localEntry = SidekickEntry(id: id, name: MakeCopy.title, symbolName: "plus", backgroundHex: "#000000", version: "built-in")
    static let localInboxEntry = SidekickEntry(id: inboxId, name: MakeCopy.inboxTitle, symbolName: "tray", backgroundHex: "#000000", version: "built-in")

    /// The home grid's Sidekicks. A DEBUG build adds Make after jess while the server does not list
    /// it yet (contract section 9), and the Inbox too when it runs with the seeds; a release build
    /// shows exactly what the server lists.
    static func listedEntries(_ entries: [SidekickEntry], seeded: Bool = MakeSeeds.isOn) -> [SidekickEntry] {
        #if DEBUG
        return addingLocalEntries(to: entries, includeInbox: seeded)
        #else
        return entries
        #endif
    }

    /// Make goes after jess (or first without jess), the Inbox after Make, each only if missing.
    static func addingLocalEntries(to entries: [SidekickEntry], includeInbox: Bool) -> [SidekickEntry] {
        var listed = entries
        let hasMake = listed.contains(where: isMake)
        if !hasMake {
            let jessIndex = listed.firstIndex(where: JessSidekick.isJess)
            let makeIndex = jessIndex.map(nextIndex) ?? 0
            listed.insert(localEntry, at: makeIndex)
        }
        let hasInbox = listed.contains(where: isInbox)
        if includeInbox && !hasInbox {
            let makeIndex = listed.firstIndex(where: isMake) ?? -1
            listed.insert(localInboxEntry, at: makeIndex + 1)
        }
        return listed
    }

    private static func nextIndex(_ index: Int) -> Int {
        index + 1
    }
}

/// Every word Make shows (docs/WRITING.md). The open picks each sit in one constant here:
/// `senderName` (founder pick open: "Bhuvan" or "Make") and `repairWord` (a new word for "repair"
/// is being researched; "Repair" until then).
enum MakeCopy {
    static let title = "Make"
    static let inboxTitle = "Inbox"
    /// The name the person sees for the other side (open pick; contract default "Bhuvan").
    static let senderName = "Bhuvan"
    /// What the swipe's toast calls repair (open pick; "Repair" until the new word is chosen).
    static let repairWord = "Repair"
    static let newRequestPlaceholder = "New Request"
    static let messagePlaceholder = "Message"
    static let replyPlaceholder = "Reply"
    static let noRequests = "No Requests"
    static let noPeople = "No Requests"
    static let you = "You"
    static let sendButton = "Send"
    static let backButton = "Back"
    static let builtCardLine = "Built · Open"
    static let builtPickerTitle = "Built"
    static let planPlaceholder = "Plan"
    static let noSidekicksToPick = "No Sidekicks"
    static let cancelButton = "Cancel"

    static func notAvailable(repairWord: String = repairWord) -> String {
        "\(repairWord) not available for this Sidekick."
    }

    /// A design card's line in a list or a notification: "3 designs".
    static func designs(count: Int) -> String {
        count == 1 ? "1 design" : "\(count) designs"
    }

    /// "Bhuvan: 3 designs", "You: Picked B".
    static func line(from speaker: String, _ text: String) -> String {
        "\(speaker): \(text)"
    }
}

/// A request's status, set by the founder by hand (contract section 2). S2: the word plus four
/// steps; Sent has none filled.
enum MakeStatus: String, CaseIterable, Sendable {
    case sent
    case figuringOut = "figuring_out"
    case looking
    case building
    case built

    /// The four the founder sets, in order (Inbox F1's buttons).
    static let handSet: [MakeStatus] = [.figuringOut, .looking, .building, .built]

    var word: String {
        switch self {
        case .sent:
            return "Sent"
        case .figuringOut:
            return "Figuring Out"
        case .looking:
            return "Looking"
        case .building:
            return "Building"
        case .built:
            return "Built"
        }
    }

    /// How many of the four steps are filled: Sent 0 … Built 4.
    var stepCount: Int {
        switch self {
        case .sent:
            return 0
        case .figuringOut:
            return 1
        case .looking:
            return 2
        case .building:
            return 3
        case .built:
            return 4
        }
    }

    /// An unknown word from a newer server reads as Sent rather than hiding the request.
    static func parse(_ text: String?) -> MakeStatus {
        guard let text, let status = MakeStatus(rawValue: text) else {
            return .sent
        }
        return status
    }
}

/// Ids are UUIDs without dashes: 32 characters of `^[A-Za-z0-9_-]{8,40}$` (contract section 2).
enum MakeIds {
    static func new() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
}

/// Times in records: ISO 8601 with milliseconds, as the store writes `clientTime`.
enum MakeTime {
    static func string(_ date: Date) -> String {
        date.ISO8601Format(.iso8601WithTimeZone(includingFractionalSeconds: true))
    }

    static func parse(_ text: String?) -> Date? {
        guard let text else {
            return nil
        }
        if let withFraction = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) {
            return withFraction
        }
        return try? Date.ISO8601FormatStyle().parse(text)
    }

    /// The time under a request: "9:30 AM" today, "Yesterday", the weekday within a week, else
    /// "Oct 12".
    static func listLabel(_ date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let startOfToday = calendar.startOfDay(for: now)
        if let weekAgo = calendar.date(byAdding: .day, value: -6, to: startOfToday), date >= weekAgo, date < now {
            var weekday = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            weekday = weekday.weekday(.abbreviated)
            return date.formatted(weekday)
        }
        var monthDay = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        monthDay = monthDay.month(.abbreviated).day()
        return date.formatted(monthDay)
    }
}

// MARK: - Keys

/// One Make record's key, read. In the person's `make` store keys start at the request id; in the
/// founder's `make-inbox` store they start with the person's user id.
enum MakeKey: Equatable, Sendable {
    case request(userId: String?, reqId: String)
    case message(userId: String?, reqId: String, msgId: String)
    case card(userId: String?, reqId: String, cardId: String)
    case answer(userId: String?, reqId: String, cardId: String)
    case person(userId: String)

    static let requestPrefix = "req:"
    static let messagePrefix = "message:"
    static let cardPrefix = "card:"
    static let answerPrefix = "answer:"
    static let personPrefix = "person:"

    /// Nil for a key that is not one of Make's, or has the wrong number of parts.
    static func parse(_ key: String, inInbox: Bool) -> MakeKey? {
        let parts = key.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let kind = parts.first, !parts.dropFirst().contains(where: \.isEmpty) else {
            return nil
        }
        // The inbox's keys carry the user id first
        let idParts = Array(parts.dropFirst())
        let userId: String? = inInbox ? idParts.first : nil
        let rest = inInbox ? Array(idParts.dropFirst()) : idParts
        if inInbox && userId == nil {
            return nil
        }
        switch (kind, rest.count) {
        case ("req", 1):
            return .request(userId: userId, reqId: rest[0])
        case ("message", 2):
            return .message(userId: userId, reqId: rest[0], msgId: rest[1])
        case ("card", 2):
            return .card(userId: userId, reqId: rest[0], cardId: rest[1])
        case ("answer", 2):
            return .answer(userId: userId, reqId: rest[0], cardId: rest[1])
        case ("person", 0) where inInbox:
            return .person(userId: userId ?? "")
        default:
            return nil
        }
    }

    var key: String {
        switch self {
        case .request(let userId, let reqId):
            return Self.joined("req", userId, [reqId])
        case .message(let userId, let reqId, let msgId):
            return Self.joined("message", userId, [reqId, msgId])
        case .card(let userId, let reqId, let cardId):
            return Self.joined("card", userId, [reqId, cardId])
        case .answer(let userId, let reqId, let cardId):
            return Self.joined("answer", userId, [reqId, cardId])
        case .person(let userId):
            return "person:\(userId)"
        }
    }

    private static func joined(_ kind: String, _ userId: String?, _ ids: [String]) -> String {
        var parts = [kind]
        if let userId {
            parts.append(userId)
        }
        parts.append(contentsOf: ids)
        return parts.joined(separator: ":")
    }
}

// MARK: - Records, read

/// A request: one thread, one status.
struct MakeRequest: Equatable, Identifiable, Sendable {
    /// The person's user id in the founder's inbox; nil in the person's own store.
    let userId: String?
    let reqId: String
    let title: String
    let status: MakeStatus
    let createdAt: Date?
    let updatedAt: Date?
    let sidekickId: String?
    let plan: String?
    let builtAt: Date?
    /// The record as stored, so a status write keeps fields this build does not know.
    let value: JSONValue

    var id: String {
        MakeThreadRef(userId: userId, reqId: reqId).id
    }

    var ref: MakeThreadRef {
        MakeThreadRef(userId: userId, reqId: reqId)
    }
}

enum MakeSpeaker: String, Sendable {
    case person
    case maker
}

struct MakeMessage: Equatable, Sendable {
    let msgId: String
    let from: MakeSpeaker
    let text: String
    let sentAt: Date?
}

struct MakeCardOption: Equatable, Identifiable, Sendable {
    let id: String
    let label: String?
    /// `file:<id>`.
    let image: String?
}

enum MakeCardKind: String, Sendable {
    case choice
    case design
}

struct MakeCard: Equatable, Identifiable, Sendable {
    let cardId: String
    let question: String
    let kind: MakeCardKind
    let options: [MakeCardOption]
    let allowsOwnWords: Bool
    let sentAt: Date?

    var id: String {
        cardId
    }

    func option(withId optionId: String) -> MakeCardOption? {
        options.first(where: hasId(optionId))
    }

    private func hasId(_ optionId: String) -> (MakeCardOption) -> Bool {
        { option in option.id == optionId }
    }

    /// The letter under a design: A, B, C …
    static func letter(at index: Int) -> String {
        let letters = Array("ABCDEFGH")
        return index < letters.count ? String(letters[index]) : String(index + 1)
    }
}

struct MakeAnswer: Equatable, Sendable {
    let cardId: String
    let optionId: String?
    let text: String?
    let sentAt: Date?
}

struct MakePerson: Hashable, Identifiable, Sendable {
    let userId: String
    let name: String
    let firstAt: Date?

    var id: String {
        userId
    }
}

/// One thread on screen: the person's request, or a person's request in the founder's inbox.
struct MakeThreadRef: Hashable, Identifiable, Sendable {
    let userId: String?
    let reqId: String

    var id: String {
        if let userId {
            return "\(userId):\(reqId)"
        }
        return reqId
    }
}

/// What a thread shows, in order (T2: messages and cards, no status; R3: the Built card).
enum MakeThreadItem: Equatable, Identifiable, Sendable {
    case message(MakeMessage)
    case card(MakeCard, answer: MakeAnswer?)
    /// The person's own words given to a card.
    case ownWords(MakeAnswer)
    case built(MakeRequest)

    var id: String {
        switch self {
        case .message(let message):
            return "m:\(message.msgId)"
        case .card(let card, _):
            return "c:\(card.cardId)"
        case .ownWords(let answer):
            return "a:\(answer.cardId)"
        case .built(let request):
            return "b:\(request.reqId)"
        }
    }

    var sentAt: Date? {
        switch self {
        case .message(let message):
            return message.sentAt
        case .card(let card, _):
            return card.sentAt
        case .ownWords(let answer):
            return answer.sentAt
        case .built(let request):
            return request.builtAt ?? request.updatedAt
        }
    }

    /// Who the item is from: the founder's side for cards and Built.
    var speaker: MakeSpeaker {
        switch self {
        case .message(let message):
            return message.from
        case .card, .built:
            return .maker
        case .ownWords:
            return .person
        }
    }
}

/// Something that happened in a thread, for its last line and its unread count: a message, a
/// card, an answer (an option picked counts as the person's, at the answer's time), Built.
struct MakeEvent: Equatable, Sendable {
    let sentAt: Date
    let speaker: MakeSpeaker
    let words: String
    let isBuilt: Bool
}

struct MakeThread: Equatable, Sendable {
    let request: MakeRequest?
    let items: [MakeThreadItem]
    /// Every answer, by card id.
    let answers: [String: MakeAnswer]
    /// What happened, oldest first (only dated things).
    var events: [MakeEvent] = []

    /// The newest card, if it has no answer yet.
    var openCard: MakeCard? {
        var newest: MakeCard?
        for item in items {
            if case .card(let card, _) = item {
                newest = card
            }
        }
        guard let newest, answers[newest.cardId] == nil else {
            return nil
        }
        return newest
    }

    /// The pill's words go as the answer to the newest card when it is unanswered and takes own
    /// words; otherwise as a message (contract section 8).
    var pillAnswersCard: MakeCard? {
        guard let openCard, openCard.allowsOwnWords else {
            return nil
        }
        return openCard
    }

    var latestSentAt: Date? {
        events.last?.sentAt
    }
}

/// Reads Make's records out of a store's records: pure, so the screens and the tests share it.
enum MakeRecords {
    // MARK: Fields

    static func request(userId: String?, reqId: String, value: JSONValue) -> MakeRequest? {
        guard let title = value["title"]?.stringValue else {
            return nil
        }
        return MakeRequest(
            userId: userId,
            reqId: reqId,
            title: title,
            status: MakeStatus.parse(value["status"]?.stringValue),
            createdAt: MakeTime.parse(value["createdAt"]?.stringValue),
            updatedAt: MakeTime.parse(value["updatedAt"]?.stringValue),
            sidekickId: value["sidekickId"]?.stringValue,
            plan: value["plan"]?.stringValue,
            builtAt: MakeTime.parse(value["builtAt"]?.stringValue),
            value: value
        )
    }

    static func message(msgId: String, value: JSONValue) -> MakeMessage? {
        guard let fromText = value["from"]?.stringValue, let from = MakeSpeaker(rawValue: fromText), let text = value["text"]?.stringValue else {
            return nil
        }
        return MakeMessage(msgId: msgId, from: from, text: text, sentAt: MakeTime.parse(value["sentAt"]?.stringValue))
    }

    static func card(cardId: String, value: JSONValue) -> MakeCard? {
        guard let question = value["question"]?.stringValue, let kindText = value["kind"]?.stringValue, let kind = MakeCardKind(rawValue: kindText) else {
            return nil
        }
        var options: [MakeCardOption] = []
        for optionValue in value["options"]?.arrayValue ?? [] {
            guard let optionId = optionValue["id"]?.stringValue else {
                continue
            }
            options.append(MakeCardOption(id: optionId, label: optionValue["label"]?.stringValue, image: optionValue["image"]?.stringValue))
        }
        let allowsOwnWords = value["allowsOwnWords"]?.boolValue ?? false
        return MakeCard(cardId: cardId, question: question, kind: kind, options: options, allowsOwnWords: allowsOwnWords, sentAt: MakeTime.parse(value["sentAt"]?.stringValue))
    }

    static func answer(cardId: String, value: JSONValue) -> MakeAnswer? {
        let optionId = value["optionId"]?.stringValue
        let text = value["text"]?.stringValue
        guard optionId != nil || text != nil else {
            return nil
        }
        return MakeAnswer(cardId: cardId, optionId: optionId, text: text, sentAt: MakeTime.parse(value["sentAt"]?.stringValue))
    }

    // MARK: Lists

    /// The requests in a store, newest `updatedAt` first (H1). `userId` limits the inbox to one
    /// person; nil in the person's store reads every request.
    static func requests(in records: [LocalRecord], inInbox: Bool, userId: String? = nil) -> [MakeRequest] {
        var requests: [MakeRequest] = []
        for record in records {
            guard case .request(let recordUserId, let reqId) = MakeKey.parse(record.key, inInbox: inInbox) else {
                continue
            }
            if let userId, recordUserId != userId {
                continue
            }
            if let request = request(userId: recordUserId, reqId: reqId, value: record.value) {
                requests.append(request)
            }
        }
        return requests.sorted(by: isNewerFirst)
    }

    private static func isNewerFirst(_ first: MakeRequest, _ second: MakeRequest) -> Bool {
        let firstTime = first.updatedAt ?? first.createdAt ?? .distantPast
        let secondTime = second.updatedAt ?? second.createdAt ?? .distantPast
        if firstTime != secondTime {
            return firstTime > secondTime
        }
        return first.reqId < second.reqId
    }

    /// One request's thread: messages, cards (with their answers) and the person's own words in
    /// time order, then Built when the request is built.
    static func thread(_ ref: MakeThreadRef, in records: [LocalRecord]) -> MakeThread {
        let inInbox = ref.userId != nil
        var request: MakeRequest?
        var messages: [MakeMessage] = []
        var cards: [MakeCard] = []
        var answers: [String: MakeAnswer] = [:]
        for record in records {
            guard let key = MakeKey.parse(record.key, inInbox: inInbox) else {
                continue
            }
            switch key {
            case .request(let userId, let reqId) where userId == ref.userId && reqId == ref.reqId:
                request = self.request(userId: userId, reqId: reqId, value: record.value)
            case .message(let userId, let reqId, let msgId) where userId == ref.userId && reqId == ref.reqId:
                if let message = message(msgId: msgId, value: record.value) {
                    messages.append(message)
                }
            case .card(let userId, let reqId, let cardId) where userId == ref.userId && reqId == ref.reqId:
                if let card = card(cardId: cardId, value: record.value) {
                    cards.append(card)
                }
            case .answer(let userId, let reqId, let cardId) where userId == ref.userId && reqId == ref.reqId:
                if let answer = answer(cardId: cardId, value: record.value) {
                    answers[cardId] = answer
                }
            default:
                continue
            }
        }
        var items: [MakeThreadItem] = []
        for message in messages {
            items.append(.message(message))
        }
        for card in cards {
            items.append(.card(card, answer: answers[card.cardId]))
            if let answer = answers[card.cardId], answer.text != nil {
                items.append(.ownWords(answer))
            }
        }
        items.sort(by: isEarlier)
        if let request, request.status == .built {
            items.append(.built(request))
        }
        let events = self.events(messages: messages, cards: cards, answers: answers, request: request)
        return MakeThread(request: request, items: items, answers: answers, events: events)
    }

    private static func events(messages: [MakeMessage], cards: [MakeCard], answers: [String: MakeAnswer], request: MakeRequest?) -> [MakeEvent] {
        var events: [MakeEvent] = []
        for message in messages {
            if let sentAt = message.sentAt {
                events.append(MakeEvent(sentAt: sentAt, speaker: message.from, words: message.text, isBuilt: false))
            }
        }
        for card in cards {
            if let sentAt = card.sentAt {
                events.append(MakeEvent(sentAt: sentAt, speaker: .maker, words: cardWords(card), isBuilt: false))
            }
            if let answer = answers[card.cardId], let sentAt = answer.sentAt {
                let words = answer.optionId.map(optionWordsFor(card)) ?? answer.text ?? ""
                events.append(MakeEvent(sentAt: sentAt, speaker: .person, words: words, isBuilt: false))
            }
        }
        if let request, request.status == .built, let builtAt = request.builtAt ?? request.updatedAt {
            events.append(MakeEvent(sentAt: builtAt, speaker: .maker, words: itemWords(.built(request)), isBuilt: true))
        }
        return events.sorted(by: isEarlierEvent)
    }

    private static func optionWordsFor(_ card: MakeCard) -> (String) -> String {
        { optionId in optionWords(card: card, optionId: optionId) }
    }

    private static func isEarlierEvent(_ first: MakeEvent, _ second: MakeEvent) -> Bool {
        first.sentAt < second.sentAt
    }

    // Undated items go first; equal times keep messages before cards by id, so the order is stable
    private static func isEarlier(_ first: MakeThreadItem, _ second: MakeThreadItem) -> Bool {
        let firstTime = first.sentAt ?? .distantPast
        let secondTime = second.sentAt ?? .distantPast
        if firstTime != secondTime {
            return firstTime < secondTime
        }
        return first.id < second.id
    }

    /// The people in the founder's inbox, the one with the newest request first.
    static func people(in records: [LocalRecord]) -> [MakePerson] {
        var people: [String: MakePerson] = [:]
        var requestUserIds: Set<String> = []
        for record in records {
            switch MakeKey.parse(record.key, inInbox: true) {
            case .person(let userId):
                let name = record.value["name"]?.stringValue ?? ""
                people[userId] = MakePerson(userId: userId, name: name, firstAt: MakeTime.parse(record.value["firstAt"]?.stringValue))
            case .request(let userId, _):
                if let userId {
                    requestUserIds.insert(userId)
                }
            default:
                continue
            }
        }
        // A request that came before its person record still shows its person
        for userId in requestUserIds where people[userId] == nil {
            people[userId] = MakePerson(userId: userId, name: "", firstAt: nil)
        }
        let requests = self.requests(in: records, inInbox: true)
        var newestByUser: [String: Date] = [:]
        for request in requests {
            guard let userId = request.userId else {
                continue
            }
            let time = request.updatedAt ?? request.createdAt ?? .distantPast
            newestByUser[userId] = max(newestByUser[userId] ?? .distantPast, time)
        }
        func isNewerPerson(_ first: MakePerson, _ second: MakePerson) -> Bool {
            let firstTime = newestByUser[first.userId] ?? .distantPast
            let secondTime = newestByUser[second.userId] ?? .distantPast
            if firstTime != secondTime {
                return firstTime > secondTime
            }
            return first.userId < second.userId
        }
        return people.values.sorted(by: isNewerPerson)
    }

    // MARK: Lines

    /// The last line under a request: "Bhuvan: 3 designs", "You: Picked B"; nil for an empty thread.
    /// `forFounder` speaks from the founder's side: his own words are "You", the person's plain.
    static func lastLine(of thread: MakeThread, forFounder: Bool, senderName: String = MakeCopy.senderName) -> String? {
        guard let event = thread.events.last else {
            return nil
        }
        let words = event.words
        let isMine = forFounder ? event.speaker == .maker : event.speaker == .person
        if event.isBuilt {
            return words
        }
        if isMine {
            return MakeCopy.line(from: MakeCopy.you, words)
        }
        return forFounder ? words : MakeCopy.line(from: senderName, words)
    }

    static func itemWords(_ item: MakeThreadItem) -> String {
        switch item {
        case .message(let message):
            return message.text
        case .card(let card, let answer):
            if let answer, let optionId = answer.optionId {
                return optionWords(card: card, optionId: optionId)
            }
            return cardWords(card)
        case .ownWords(let answer):
            return answer.text ?? ""
        case .built(let request):
            return MakeStatus.built.word + (request.plan.map(prefixedPlan) ?? "")
        }
    }

    private static func prefixedPlan(_ plan: String) -> String {
        " · " + plan
    }

    /// A card's own line: its question, or "3 designs" for designs.
    static func cardWords(_ card: MakeCard) -> String {
        card.kind == .design ? MakeCopy.designs(count: card.options.count) : card.question
    }

    /// A picked option's words: its label, or "Picked B" for an unlabelled design.
    static func optionWords(card: MakeCard, optionId: String) -> String {
        guard let index = card.options.firstIndex(where: { $0.id == optionId }) else {
            return optionId
        }
        if let label = card.options[index].label {
            return label
        }
        return "Picked \(MakeCard.letter(at: index))"
    }
}

// MARK: - Records, written

/// Writes Make's records through the store, so the write gate stamps `$type` and checks them
/// against native-types.js before they are kept (contract sections 2 and 3).
@MainActor
struct MakeWriter {
    let store: LocalRecordStore
    var now: @MainActor () -> Date = Date.init

    /// H1's Send: the request (status Sent, the words as its title, up to 200) and the words as
    /// its first message. Returns the new request id; nil for empty words.
    @discardableResult
    func newRequest(words: String) throws -> String? {
        let text = Self.trimmed(words)
        guard !text.isEmpty else {
            return nil
        }
        let reqId = MakeIds.new()
        let time = MakeTime.string(now())
        let title = String(text.prefix(200))
        let request: JSONValue = .object([
            "title": .string(title),
            "status": .string(MakeStatus.sent.rawValue),
            "createdAt": .string(time),
            "updatedAt": .string(time),
        ])
        try store.set(sidekickId: MakeSidekick.id, key: MakeKey.request(userId: nil, reqId: reqId).key, value: request)
        try writeMessage(sidekickId: MakeSidekick.id, key: .message(userId: nil, reqId: reqId, msgId: MakeIds.new()), from: .person, text: text, userId: nil, time: time)
        return reqId
    }

    /// The person's words in a thread: the answer to the newest card when it is open and takes
    /// own words, otherwise a message.
    func send(words: String, in thread: MakeThread, reqId: String) throws {
        let text = Self.trimmed(words)
        guard !text.isEmpty else {
            return
        }
        if let card = thread.pillAnswersCard {
            try answer(reqId: reqId, cardId: card.cardId, optionId: nil, text: text)
            return
        }
        try writeMessage(sidekickId: MakeSidekick.id, key: .message(userId: nil, reqId: reqId, msgId: MakeIds.new()), from: .person, text: text, userId: nil, time: MakeTime.string(now()))
    }

    /// A card's Send: the picked option, or own words. Only the first answer counts (the server
    /// refuses a second), so a card that has one is left alone.
    func answer(reqId: String, cardId: String, optionId: String?, text: String?) throws {
        let key = MakeKey.answer(userId: nil, reqId: reqId, cardId: cardId).key
        guard store.get(sidekickId: MakeSidekick.id, key: key) == nil else {
            return
        }
        var fields: [String: JSONValue] = [
            "cardId": .string(cardId),
            "sentAt": .string(MakeTime.string(now())),
        ]
        if let optionId {
            fields["optionId"] = .string(optionId)
        } else if let text {
            fields["text"] = .string(text)
        } else {
            return
        }
        try store.set(sidekickId: MakeSidekick.id, key: key, value: .object(fields))
    }

    // MARK: The founder's side

    /// A reply in the inbox: a maker message the server copies to the person.
    func reply(words: String, userId: String, reqId: String) throws {
        let text = Self.trimmed(words)
        guard !text.isEmpty else {
            return
        }
        try writeMessage(sidekickId: MakeSidekick.inboxId, key: .message(userId: userId, reqId: reqId, msgId: MakeIds.new()), from: .maker, text: text, userId: userId, time: MakeTime.string(now()))
    }

    /// F1's status buttons: the request written again with the new status. Built also carries the
    /// Sidekick and the plan (the server then assigns the Sidekick and sends the push). Fields this
    /// build does not know are kept.
    func setStatus(_ status: MakeStatus, request: MakeRequest, sidekickId: String? = nil, plan: String? = nil) throws {
        guard let userId = request.userId else {
            return
        }
        guard case .object(var fields) = request.value else {
            return
        }
        let time = MakeTime.string(now())
        fields["status"] = .string(status.rawValue)
        fields["updatedAt"] = .string(time)
        fields["userId"] = .string(userId)
        if status == .built {
            guard let sidekickId, let plan = plan.map(Self.trimmed), !plan.isEmpty else {
                return
            }
            fields["sidekickId"] = .string(sidekickId)
            fields["plan"] = .string(String(plan.prefix(200)))
            fields["builtAt"] = .string(time)
        }
        try store.set(sidekickId: MakeSidekick.inboxId, key: MakeKey.request(userId: userId, reqId: request.reqId).key, value: .object(fields))
    }

    private func writeMessage(sidekickId: String, key: MakeKey, from: MakeSpeaker, text: String, userId: String?, time: String) throws {
        var fields: [String: JSONValue] = [
            "from": .string(from.rawValue),
            "text": .string(String(text.prefix(4000))),
            "sentAt": .string(time),
        ]
        if let userId {
            fields["userId"] = .string(userId)
        }
        try store.set(sidekickId: sidekickId, key: key.key, value: .object(fields))
    }

    static func trimmed(_ words: String) -> String {
        words.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Unread, on this phone only

/// The last `sentAt` seen per thread (contract section 8: unread state stays on the phone). A
/// thread is unread when the other side has something newer.
@MainActor
final class MakeReadMarks {
    static let defaultsKey = "midas.make.lastSeen"
    private let defaults: UserDefaults
    private var lastSeen: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.lastSeen = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
    }

    func lastSeenAt(_ ref: MakeThreadRef) -> Date? {
        MakeTime.parse(lastSeen[ref.id])
    }

    /// Everything in the thread up to now has been seen.
    func markSeen(_ thread: MakeThread, ref: MakeThreadRef) {
        guard let latest = thread.latestSentAt else {
            return
        }
        if let seen = lastSeenAt(ref), seen >= latest {
            return
        }
        lastSeen[ref.id] = MakeTime.string(latest)
        defaults.set(lastSeen, forKey: Self.defaultsKey)
    }

    /// The other side's items newer than the last seen one: the founder's for the person, the
    /// person's for the founder.
    func unreadCount(_ thread: MakeThread, ref: MakeThreadRef, forFounder: Bool) -> Int {
        let otherSide: MakeSpeaker = forFounder ? .person : .maker
        let seen = lastSeenAt(ref) ?? .distantPast
        var count = 0
        for event in thread.events where event.speaker == otherSide && event.sentAt > seen {
            count += 1
        }
        return count
    }
}

/// Built requests whose Built screen already played on this phone (R2 plays once per request).
@MainActor
final class MakeBuiltShown {
    static let defaultsKey = "midas.make.builtShown"
    private let defaults: UserDefaults
    private let storageKey: String
    private var shown: Set<String>

    init(defaults: UserDefaults = .standard, key: String = MakeBuiltShown.defaultsKey) {
        self.defaults = defaults
        self.storageKey = key
        let saved = defaults.stringArray(forKey: key) ?? []
        self.shown = Set(saved)
    }

    func contains(_ key: String) -> Bool {
        shown.contains(key)
    }

    func insert(_ key: String) {
        guard !shown.contains(key) else {
            return
        }
        shown.insert(key)
        defaults.set(shown.sorted(), forKey: storageKey)
    }
}

// MARK: - The center

/// Make's long-lived state: its store, the writer, the change counter the screens redraw on, the
/// read marks, what a notification asked to open, and which thread is on screen.
@MainActor
@Observable
final class MakeCenter {
    let store: LocalRecordStore
    @ObservationIgnored let writer: MakeWriter
    @ObservationIgnored let readMarks: MakeReadMarks
    @ObservationIgnored let builtShown: MakeBuiltShown
    /// R3's "already built" plays once per Built card too.
    @ObservationIgnored let threadCardsSeen: MakeBuiltShown
    @ObservationIgnored let api: MakeAPI
    let builtStage = MakeBuiltStage()
    /// Bumped on every change to a Make or Inbox record, pulled or written: the screens read it, so
    /// they redraw.
    private(set) var revision = 0
    /// A notification's request, to open once Make is on screen.
    var pendingRequestId: String?
    /// A notification's inbox thread, to open once the Inbox is on screen.
    var pendingInboxThread: MakeThreadRef?
    /// The thread on screen now; a push for it shows no banner.
    var openThread: MakeThreadRef?
    /// A pull (`recordSync.syncNow()` in the app; nothing with the seeds).
    @ObservationIgnored var sync: @MainActor () async -> Void
    /// A card's picture by file id: from the phone, else fetched from the server and kept.
    @ObservationIgnored var fileData: @MainActor (String) async -> Data? = MakeCenter.noFile

    static func noFile(_ fileId: String) async -> Data? {
        nil
    }

    init(store: LocalRecordStore, api: MakeAPI, defaults: UserDefaults = .standard, sync: @escaping @MainActor () async -> Void) {
        self.store = store
        self.writer = MakeWriter(store: store)
        self.readMarks = MakeReadMarks(defaults: defaults)
        self.builtShown = MakeBuiltShown(defaults: defaults)
        self.threadCardsSeen = MakeBuiltShown(defaults: defaults, key: "midas.make.builtCardSeen")
        self.api = api
        self.sync = sync
        store.addChangeObserver(handleStoreChange)
    }

    private func handleStoreChange(_ change: LocalRecordChange) {
        guard change.sidekickId == MakeSidekick.id || change.sidekickId == MakeSidekick.inboxId else {
            return
        }
        revision += 1
    }

    /// The person's records in `make`.
    func personRecords() -> [LocalRecord] {
        store.query(sidekickId: MakeSidekick.id, keyPrefix: "")
    }

    /// The founder's records in `make-inbox`.
    func inboxRecords() -> [LocalRecord] {
        store.query(sidekickId: MakeSidekick.inboxId, keyPrefix: "")
    }

    func records(for ref: MakeThreadRef) -> [LocalRecord] {
        ref.userId == nil ? personRecords() : inboxRecords()
    }

    func thread(_ ref: MakeThreadRef) -> MakeThread {
        MakeRecords.thread(ref, in: records(for: ref))
    }

    /// The built request that has not played its Built screen on this phone yet, oldest first.
    func unshownBuilt() -> MakeRequest? {
        let requests = MakeRecords.requests(in: personRecords(), inInbox: false)
        let built = requests.filter(isBuiltAndUnshown)
        return built.last
    }

    private func isBuiltAndUnshown(_ request: MakeRequest) -> Bool {
        request.status == .built && request.sidekickId != nil && !builtShown.contains(request.reqId)
    }
}

// MARK: - Server routes

/// A Sidekick the founder can hand over as Built (`GET /make/sidekicks`).
struct MakeBuildable: Equatable, Identifiable, Decodable, Sendable {
    let id: String
    let name: String
    let version: String
}

/// Make's own server route, with the user's session: the Built picker's list (founder only).
struct MakeAPI: Sendable {
    let platformOrigin: URL
    let session: URLSession
    let sessionToken: @Sendable () -> String?

    static func sidekicksRequest(platformOrigin: URL, token: String?) -> URLRequest {
        var request = URLRequest(url: platformOrigin.appending(path: "make/sidekicks"))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Every base Sidekick, minus the built-in ones; empty when the server has no such route yet
    /// (404) or could not be reached.
    func fetchSidekicks() async -> [MakeBuildable] {
        let request = Self.sidekicksRequest(platformOrigin: platformOrigin, token: sessionToken())
        guard let (body, response) = try? await session.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200 else {
            return []
        }
        return Self.buildables(from: body)
    }

    static func buildables(from body: Data) -> [MakeBuildable] {
        struct Reply: Decodable {
            let sidekicks: [MakeBuildable]
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: body) else {
            return []
        }
        return reply.sidekicks.filter(isPickable)
    }

    private static func isPickable(_ buildable: MakeBuildable) -> Bool {
        !MakeSidekick.builtInIds.contains(buildable.id)
    }
}

// MARK: - DEBUG seeds

/// A DEBUG run with the launch argument `-MidasMakeSeeds YES` shows Make and the Inbox filled with
/// sample requests from a store of their own that never syncs, so the screens can be tried before
/// the server side lands (contract section 9). Never in a release build.
enum MakeSeeds {
    static let launchArgument = "MidasMakeSeeds"

    static var isOn: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: launchArgument)
        #else
        return false
        #endif
    }

    /// A person's thread mid-way (a choice card answered, the next one open), one built request,
    /// and the same person in the inbox.
    @MainActor
    static func fill(_ store: LocalRecordStore, now: Date = Date()) {
        func at(_ minutesAgo: Double) -> JSONValue {
            .string(MakeTime.string(now.addingTimeInterval(-minutesAgo * 60)))
        }
        let plants = "seedplants0001"
        let reminders = "seedreminders01"
        let records: [(String, String, JSONValue)] = [
            (MakeSidekick.id, "req:\(plants)", .object(["title": .string("My plants keep dying. I forget to water them."), "status": .string("looking"), "createdAt": at(60), "updatedAt": at(5)])),
            (MakeSidekick.id, "message:\(plants):seedmsg00001", .object(["from": .string("person"), "text": .string("My plants keep dying. I forget to water them."), "sentAt": at(60)])),
            (MakeSidekick.id, "card:\(plants):seedcard0001", .object(["question": .string("What problem are we facing: forgetting, or not knowing when?"), "kind": .string("choice"), "options": .array([.object(["id": .string("seedopt00001"), "label": .string("Forgetting")]), .object(["id": .string("seedopt00002"), "label": .string("Not knowing when")])]), "allowsOwnWords": .bool(true), "sentAt": at(50)])),
            (MakeSidekick.id, "answer:\(plants):seedcard0001", .object(["cardId": .string("seedcard0001"), "optionId": .string("seedopt00001"), "sentAt": at(45)])),
            (MakeSidekick.id, "card:\(plants):seedcard0002", .object(["question": .string("Classy or playful?"), "kind": .string("choice"), "options": .array([.object(["id": .string("seedopt00003"), "label": .string("Classy")]), .object(["id": .string("seedopt00004"), "label": .string("Playful")])]), "allowsOwnWords": .bool(true), "sentAt": at(5)])),
            (MakeSidekick.id, "req:\(reminders)", .object(["title": .string("Build me an app for reminders"), "status": .string("built"), "createdAt": at(3000), "updatedAt": at(2000), "sidekickId": .string("reminders"), "plan": .string("Lists, times and a widget"), "builtAt": at(2000)])),
            (MakeSidekick.id, "message:\(reminders):seedmsg00002", .object(["from": .string("person"), "text": .string("Build me an app for reminders"), "sentAt": at(3000)])),
            (MakeSidekick.inboxId, "person:seeduser0001", .object(["name": .string("Priya"), "firstAt": at(3000), "userId": .string("seeduser0001")])),
            (MakeSidekick.inboxId, "req:seeduser0001:\(plants)", .object(["title": .string("My plants keep dying. I forget to water them."), "status": .string("looking"), "createdAt": at(60), "updatedAt": at(5), "userId": .string("seeduser0001")])),
            (MakeSidekick.inboxId, "message:seeduser0001:\(plants):seedmsg00001", .object(["from": .string("person"), "text": .string("My plants keep dying. I forget to water them."), "sentAt": at(60), "userId": .string("seeduser0001")])),
            (MakeSidekick.inboxId, "message:seeduser0001:\(plants):seedmsg00003", .object(["from": .string("person"), "text": .string("Ferns every week, the cactus every month."), "sentAt": at(4), "userId": .string("seeduser0001")])),
        ]
        for (sidekickId, key, value) in records where store.get(sidekickId: sidekickId, key: key) == nil {
            try? store.set(sidekickId: sidekickId, key: key, value: value)
        }
    }

    /// The Built picker's list with the seeds on.
    static let buildables = [
        MakeBuildable(id: "plants", name: "Plants", version: "1"),
        MakeBuildable(id: "reminders", name: "Reminders", version: "3"),
    ]
}
