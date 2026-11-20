#if MIDAS_TEST_BUILD
// Midas dictation keyboard (TEST BUILD, founder 2026-11-14; branch agent/dictation-test, never
// merged; docs/briefs/dictation-keyboard-test.md, docs/mockups/dictation-keyboard-2026-11-13.html).
// Compiled into the Midas Test app and the MidasKeyboard extension: the contract between them and
// the keyboard's pure logic (pages, spacing), so the app's tests can check what the keyboard does.
//
//   keyboard  writes request.json  { seq, wantsListening }        posts  ...dictation.request
//   app       writes state.json    { live, listening, heard, ... } posts  ...dictation.state
//   app       writes delivery.json { id, text, endOfSpeechAt }     posts  ...dictation.delivery
//   keyboard  inserts, writes acks.json [{ id, insertedAt }]       posts  ...dictation.ack
//
// All files live in the App Group container (`dictation-keyboard/`); no network. The extension
// cannot record, so the microphone runs in the app (DictationKeyboardSession).
import Foundation

/// The fixed numbers and names of the keyboard dictation test.
enum DictationKeyboardConstants {
    /// Opens Midas Test and starts a dictation session (the Test app's own scheme, so the everyday
    /// Midas on the same phone never answers it).
    static let urlScheme = "midastest"
    static let urlHost = "dictation"
    static let startURL = URL(string: "midastest://dictation")!
    /// Silence after the last new words that counts as a pause: the app then inserts.
    static let endOfSpeechSilence: Duration = .seconds(1)
    /// The session ends this long after the last use.
    static let sessionIdleTimeout: TimeInterval = 5 * 60
    /// How long the keyboard waits for the app to answer before it shows Start Dictation.
    static let answerTimeout: TimeInterval = 1.2
    /// A delivery older than this is not inserted (the keyboard was closed when it came).
    static let deliveryMaxAge: TimeInterval = 10
    /// The acks file keeps this many, newest last.
    static let maxAcks = 20
    /// Folder inside the App Group container.
    static let folderName = "dictation-keyboard"

    /// Darwin notification names (the payload is always in the files).
    static let requestNotification = "com.bhuvanrj.midas.test.dictation.request"
    static let stateNotification = "com.bhuvanrj.midas.test.dictation.state"
    static let deliveryNotification = "com.bhuvanrj.midas.test.dictation.delivery"
    static let ackNotification = "com.bhuvanrj.midas.test.dictation.ack"
    /// Build 34: the keyboard queued a probe or a run of its own microphone for the app to save.
    static let keyboardRecordsNotification = "com.bhuvanrj.midas.test.dictation.keyboard-records"

    /// The line on the Midas Test screen after Start Dictation (docs/WRITING.md).
    static let swipeBackLine = "Swipe back to keep typing."
    /// The one button on the listening panel when no session is live.
    static let startButtonTitle = "Start Dictation"
    /// The one line shown without Full Access (letters only, App Review 4.4.1).
    static let fullAccessLine = "Allow Full Access to turn on dictation."

    /// Whether a link is the keyboard's start link.
    static func isStartURL(_ url: URL) -> Bool {
        url.scheme == urlScheme && url.host == urlHost
    }
}

// MARK: The handoff

/// Keyboard → app: whether the keyboard wants the microphone now. Only the newest counts, so a
/// quick stop then start can never be read in the wrong order.
struct DictationKeyboardRequest: Codable, Equatable, Sendable {
    /// Milliseconds since 1970 when written, bumped past the previous one: survives the keyboard's
    /// process being started again.
    let seq: Int
    let wantsListening: Bool
    let at: Date

    /// A request newer than `previousSeq`.
    static func next(wantsListening: Bool, at: Date, previousSeq: Int) -> DictationKeyboardRequest {
        let clockSeq = Int((at.timeIntervalSince1970 * 1000).rounded(.down))
        let seq = max(clockSeq, previousSeq + 1)
        return DictationKeyboardRequest(seq: seq, wantsListening: wantsListening, at: at)
    }
}

/// App → keyboard: the session as it is now.
struct DictationKeyboardState: Codable, Equatable, Sendable {
    /// A session is running (the microphone is on in Midas Test).
    let live: Bool
    /// Words are being listened for now.
    let listening: Bool
    /// The raw words of the current listen, as they come.
    let heard: String
    /// The newest request the app has acted on.
    let handledSeq: Int
    let updatedAt: Date
    /// When the session ends unless used again; nil when not live.
    let endsAt: Date?

    static let off = DictationKeyboardState(live: false, listening: false, heard: "", handledSeq: 0, updatedAt: .distantPast, endsAt: nil)
}

/// App → keyboard: one pause's text, after the gate.
struct DictationKeyboardDelivery: Codable, Equatable, Sendable {
    let id: String
    /// The gate's output, as it should go in (the keyboard adds the space before it).
    let text: String
    let endOfSpeechAt: Date
    let deliveredAt: Date
}

/// Keyboard → app: a delivery was inserted.
struct DictationKeyboardAck: Codable, Equatable, Sendable {
    let id: String
    let insertedAt: Date
}

/// The JSON both sides write: millisecond dates, sorted keys.
enum DictationKeyboardHandoff {
    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) -> Value? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(type, from: data)
    }

    /// The acks with one more, oldest dropped past `maxAcks`; an id already there is not added twice.
    static func appending(_ ack: DictationKeyboardAck, to acks: [DictationKeyboardAck]) -> [DictationKeyboardAck] {
        var updated = acks
        let alreadyThere = updated.contains { existing in existing.id == ack.id }
        if !alreadyThere {
            updated.append(ack)
        }
        let overflow = updated.count - DictationKeyboardConstants.maxAcks
        if overflow > 0 {
            updated.removeFirst(overflow)
        }
        return updated
    }

    /// Whether the keyboard should insert this delivery now: not inserted yet and recent.
    static func shouldInsert(_ delivery: DictationKeyboardDelivery, acks: [DictationKeyboardAck], now: Date) -> Bool {
        let inserted = acks.contains { ack in ack.id == delivery.id }
        guard !inserted, !delivery.text.isEmpty else {
            return false
        }
        let age = now.timeIntervalSince(delivery.deliveredAt)
        return age <= DictationKeyboardConstants.deliveryMaxAge
    }

    /// Whether the app has answered `request`: it handled that request or a newer one.
    static func isAnswered(_ request: DictationKeyboardRequest, by state: DictationKeyboardState) -> Bool {
        state.handledSeq >= request.seq
    }
}

/// The four files in the App Group container. Each write replaces the whole file at once.
struct DictationKeyboardMailbox: Sendable {
    let folder: URL

    static let requestFile = "request.json"
    static let stateFile = "state.json"
    static let deliveryFile = "delivery.json"
    static let acksFile = "acks.json"

    /// The App Group's folder; nil without the App Group (no Full Access in the keyboard, or an
    /// unsigned build).
    static func shared(appGroup: String, fileManager: FileManager = .default) -> DictationKeyboardMailbox? {
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            return nil
        }
        let folder = container.appending(path: DictationKeyboardConstants.folderName)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return DictationKeyboardMailbox(folder: folder)
    }

    private func fileURL(_ name: String) -> URL {
        folder.appending(path: name)
    }

    private func write<Value: Encodable>(_ value: Value, to name: String) throws {
        let data = try DictationKeyboardHandoff.encode(value)
        // Build 35: the folder again if it is gone, so a write never fails for that
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: fileURL(name), options: .atomic)
    }

    private func read<Value: Decodable>(_ type: Value.Type, from name: String) -> Value? {
        guard let data = try? Data(contentsOf: fileURL(name)) else {
            return nil
        }
        return DictationKeyboardHandoff.decode(type, from: data)
    }

    func writeRequest(_ request: DictationKeyboardRequest) throws {
        try write(request, to: Self.requestFile)
    }

    func readRequest() -> DictationKeyboardRequest? {
        read(DictationKeyboardRequest.self, from: Self.requestFile)
    }

    func writeState(_ state: DictationKeyboardState) throws {
        try write(state, to: Self.stateFile)
    }

    func readState() -> DictationKeyboardState? {
        read(DictationKeyboardState.self, from: Self.stateFile)
    }

    func writeDelivery(_ delivery: DictationKeyboardDelivery) throws {
        try write(delivery, to: Self.deliveryFile)
    }

    func readDelivery() -> DictationKeyboardDelivery? {
        read(DictationKeyboardDelivery.self, from: Self.deliveryFile)
    }

    func readAcks() -> [DictationKeyboardAck] {
        read([DictationKeyboardAck].self, from: Self.acksFile) ?? []
    }

    func appendAck(_ ack: DictationKeyboardAck) throws {
        let updated = DictationKeyboardHandoff.appending(ack, to: readAcks())
        try write(updated, to: Self.acksFile)
    }

    // MARK: Build 34, mic inside the keyboard

    /// The Dictation Sidekick's settings:main as the app last synced it (the keyboard reads
    /// keyboardMic and the gate settings from it).
    static let settingsFile = "settings.json"
    /// The keyboard's microphone attempt in progress; left behind when iOS ended the keyboard.
    static let probeAttemptFile = "probe-attempt.json"
    /// One file per probe or run the keyboard's own microphone made, until the app saves it.
    static let probesFolder = "probes"
    static let keyboardRunsFolder = "keyboard-runs"

    func writeSettings(_ value: JSONValue?) throws {
        guard let value else {
            try? FileManager.default.removeItem(at: fileURL(Self.settingsFile))
            return
        }
        try write(value, to: Self.settingsFile)
    }

    func readSettings() -> JSONValue? {
        read(JSONValue.self, from: Self.settingsFile)
    }

    func writeProbeAttempt(_ attempt: DictationKeyboardProbeAttempt?) {
        guard let attempt else {
            try? FileManager.default.removeItem(at: fileURL(Self.probeAttemptFile))
            return
        }
        try? write(attempt, to: Self.probeAttemptFile)
    }

    func readProbeAttempt() -> DictationKeyboardProbeAttempt? {
        read(DictationKeyboardProbeAttempt.self, from: Self.probeAttemptFile)
    }

    /// A queued item, one file each, so the app can delete what it saved while the keyboard adds more.
    func queue<Value: Encodable>(_ value: Value, id: String, in folderName: String) throws {
        let queueFolder = folder.appending(path: folderName)
        try FileManager.default.createDirectory(at: queueFolder, withIntermediateDirectories: true)
        let data = try DictationKeyboardHandoff.encode(value)
        try data.write(to: queueFolder.appending(path: id + ".json"), options: .atomic)
    }

    /// Every queued item in a folder, oldest file name first, with the file to delete once saved.
    func queued<Value: Decodable>(_ type: Value.Type, in folderName: String) -> [(file: URL, value: Value)] {
        let queueFolder = folder.appending(path: folderName)
        let files = (try? FileManager.default.contentsOfDirectory(at: queueFolder, includingPropertiesForKeys: nil)) ?? []
        let sortedFiles = files.sorted(by: Self.isEarlierFileName)
        var items: [(file: URL, value: Value)] = []
        for file in sortedFiles where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file), let value = DictationKeyboardHandoff.decode(type, from: data) else {
                // A file that can never be read would block nothing but would stay: removed
                try? FileManager.default.removeItem(at: file)
                continue
            }
            items.append((file, value))
        }
        return items
    }

    private static func isEarlierFileName(_ first: URL, _ second: URL) -> Bool {
        first.lastPathComponent < second.lastPathComponent
    }

    func removeQueued(_ file: URL) {
        try? FileManager.default.removeItem(at: file)
    }
}

/// Darwin notifications: a wake-up with no payload, across the app and the keyboard.
enum DictationKeyboardDarwin {
    static func post(_ name: String) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let notificationName = CFNotificationName(name as CFString)
        CFNotificationCenterPostNotification(center, notificationName, nil, nil, true)
    }
}

/// Listens for Darwin notifications by name and calls `handler` on the main actor. Stops when
/// released.
final class DictationDarwinObserver: @unchecked Sendable {
    private let handler: @MainActor @Sendable (String) -> Void
    private let names: [String]

    init(names: [String], handler: @escaping @MainActor @Sendable (String) -> Void) {
        self.names = names
        self.handler = handler
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        for name in names {
            CFNotificationCenterAddObserver(center, observer, Self.callback, name as CFString, nil, .deliverImmediately)
        }
    }

    deinit {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveEveryObserver(center, observer)
    }

    fileprivate func deliver(_ name: String) {
        let handler = self.handler
        Task { @MainActor in
            handler(name)
        }
    }

    // A C function: no captures; the observer pointer leads back to the instance
    private static let callback: CFNotificationCallback = { _, observer, name, _, _ in
        guard let observer, let name else {
            return
        }
        let instance = Unmanaged<DictationDarwinObserver>.fromOpaque(observer).takeUnretainedValue()
        instance.deliver(name.rawValue as String)
    }
}

// MARK: The keyboard's logic

/// The space rule: dictated text goes in after a space unless the text before the cursor is empty
/// or already ends in whitespace.
enum DictationKeyboardSpacing {
    static func textToInsert(_ text: String, before contextBefore: String?) -> String {
        guard !text.isEmpty else {
            return ""
        }
        guard let lastCharacter = contextBefore?.last else {
            return text
        }
        if lastCharacter.isWhitespace {
            return text
        }
        return " " + text
    }

    /// A capital for the next letter: at the start, or after a sentence end and a space, or a new line.
    static func shouldCapitalize(before contextBefore: String?) -> Bool {
        guard let context = contextBefore, !context.isEmpty else {
            return true
        }
        if context.hasSuffix("\n") {
            return true
        }
        let trimmed = context.trimmingCharacters(in: .whitespaces)
        guard context.last == " ", let lastMark = trimmed.last else {
            return trimmed.isEmpty
        }
        return lastMark == "." || lastMark == "!" || lastMark == "?"
    }
}

/// Which keys show (docs/mockups/dictation-keyboard-2026-11-13.html).
enum DictationKeyboardPage: String, Equatable, Sendable {
    /// jess's orb and the raw words; ABC on the left, 123 and 😊 on the right.
    case listening
    case letters
    case numbers
    /// "#+=": the second symbols page.
    case symbols
}

enum DictationKeyboardShift: Equatable, Sendable {
    case off
    /// The next letter only.
    case once
    case locked
}

/// A key the person tapped.
enum DictationKeyboardControl: Equatable, Sendable {
    case abc
    case numbers
    case symbols
    /// ● next to space: back to listening.
    case listen
    /// 😊 (or 🌐 on a phone where iOS draws none): the next keyboard.
    case nextKeyboard
    case shift
    /// Shift tapped twice quickly.
    case shiftLock
    case character(String)
    case space
    case backspace
    case returnKey
}

/// What the keyboard does after a tap.
enum DictationKeyboardEffect: Equatable, Sendable {
    case startListening
    case stopListening
    case nextKeyboard
    case insert(String)
    case deleteBackward
}

/// The keyboard's pages and shift. Opens on listening with Full Access, on letters without it.
struct DictationKeyboardLayout: Equatable, Sendable {
    let hasFullAccess: Bool
    private(set) var page: DictationKeyboardPage
    private(set) var shift: DictationKeyboardShift = .off

    init(hasFullAccess: Bool) {
        self.hasFullAccess = hasFullAccess
        self.page = hasFullAccess ? .listening : .letters
    }

    /// The ● key next to space; only with Full Access (dictation needs the App Group).
    var showsListenKey: Bool {
        hasFullAccess
    }

    /// The one line shown without Full Access.
    var fullAccessLine: String? {
        hasFullAccess ? nil : DictationKeyboardConstants.fullAccessLine
    }

    static let letterRows: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]

    static let numberRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
        [".", ",", "?", "!", "'"],
    ]

    static let symbolRows: [[String]] = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"],
        [".", ",", "?", "!", "'"],
    ]

    /// The character keys of the page showing; empty on listening.
    var rows: [[String]] {
        switch page {
        case .listening:
            return []
        case .letters:
            return Self.letterRows
        case .numbers:
            return Self.numberRows
        case .symbols:
            return Self.symbolRows
        }
    }

    /// The keyboard came up: listening again with Full Access.
    mutating func appeared() -> [DictationKeyboardEffect] {
        shift = .off
        guard hasFullAccess else {
            page = .letters
            return []
        }
        page = .listening
        return [.startListening]
    }

    /// The keyboard went away: listening stops (text already said still inserts).
    mutating func disappeared() -> [DictationKeyboardEffect] {
        page == .listening ? [.stopListening] : []
    }

    /// Shift on for the next letter when a sentence starts (letters page only).
    mutating func autoCapitalize(before contextBefore: String?) {
        guard page == .letters, shift != .locked else {
            return
        }
        shift = DictationKeyboardSpacing.shouldCapitalize(before: contextBefore) ? .once : .off
    }

    /// Leaves listening for a typing page: listening stops first.
    private mutating func show(_ newPage: DictationKeyboardPage) -> [DictationKeyboardEffect] {
        let wasListening = page == .listening
        page = newPage
        return wasListening ? [.stopListening] : []
    }

    mutating func handle(_ control: DictationKeyboardControl) -> [DictationKeyboardEffect] {
        switch control {
        case .abc:
            return show(.letters)
        case .numbers:
            return show(.numbers)
        case .symbols:
            return show(.symbols)
        case .listen:
            guard hasFullAccess else {
                return []
            }
            page = .listening
            shift = .off
            return [.startListening]
        case .nextKeyboard:
            let stopping: [DictationKeyboardEffect] = page == .listening ? [.stopListening] : []
            return stopping + [.nextKeyboard]
        case .shift:
            shift = shift == .off ? .once : .off
            return []
        case .shiftLock:
            shift = .locked
            return []
        case .character(let character):
            return [.insert(typed(character))]
        case .space:
            return [.insert(" ")]
        case .backspace:
            return [.deleteBackward]
        case .returnKey:
            return [.insert("\n")]
        }
    }

    /// A letter with shift applied; a one-time shift is used up.
    private mutating func typed(_ character: String) -> String {
        guard page == .letters else {
            return character
        }
        switch shift {
        case .off:
            return character
        case .once:
            shift = .off
            return character.uppercased()
        case .locked:
            return character.uppercased()
        }
    }
}

/// What the listening panel shows.
enum DictationKeyboardPanel: Equatable, Sendable {
    /// Asked the app; waiting for its answer.
    case connecting
    /// No live session: the one button.
    case startButton
    /// Live but not listening (a listen failed): the orb, idle; a tap listens again.
    case idle
    case listening(heard: String)
    /// Text just went in.
    case inserted

    /// The panel for the app's state, the keyboard's last request and the time now.
    static func from(state: DictationKeyboardState?, request: DictationKeyboardRequest?, now: Date) -> DictationKeyboardPanel {
        guard let request else {
            return state?.live == true ? .idle : .startButton
        }
        guard let state, DictationKeyboardHandoff.isAnswered(request, by: state) else {
            let waited = now.timeIntervalSince(request.at)
            return waited < DictationKeyboardConstants.answerTimeout ? .connecting : .startButton
        }
        guard state.live else {
            return .startButton
        }
        return state.listening ? .listening(heard: state.heard) : .idle
    }
}
#endif
