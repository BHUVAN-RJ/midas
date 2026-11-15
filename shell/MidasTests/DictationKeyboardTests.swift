#if MIDAS_TEST_BUILD
// The Midas dictation keyboard (TEST BUILD, founder 2026-11-14; docs/briefs/dictation-keyboard-test.md;
// branch agent/dictation-test, never merged). Compiled only against a Test build: run with the
// "Midas Test" scheme's test action.
//
// The session state machine in Midas Test (start, live, pause → insert, stop, timeout, end); the
// App Group handoff (JSON shape, request order, acks, which delivery goes in, the files); the space
// rule; the keyboard's pages (listening, letters, numbers, symbols, next keyboard) and shift; the
// keyboard without Full Access; the listening panel; the gate's text for one pause; and the
// `dictation.run` record a keyboard insert saves, through the Dictation Sidekick's real manifest.
import XCTest
@testable import Midas

private let keyboardRepoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@MainActor
final class DictationKeyboardTests: XCTestCase {
    private typealias Machine = DictationKeyboardSessionMachine
    private let startedAt = Date(timeIntervalSince1970: 1_763_160_000)
    private let device = DictationDeviceInfo(device: "iPhone17,1", ios: "27.0", build: "33")
    private var temporaryFolder: URL!

    override func setUp() {
        super.setUp()
        temporaryFolder = FileManager.default.temporaryDirectory.appending(path: "dictation-keyboard-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: temporaryFolder)
        super.tearDown()
    }

    private func seconds(_ offset: TimeInterval) -> Date {
        startedAt.addingTimeInterval(offset)
    }

    private func request(_ wantsListening: Bool, seq: Int, at offset: TimeInterval = 0) -> DictationKeyboardRequest {
        DictationKeyboardRequest(seq: seq, wantsListening: wantsListening, at: seconds(offset))
    }

    // MARK: The constants

    func testTheBriefsNumbersAndWords() {
        XCTAssertEqual(DictationKeyboardConstants.endOfSpeechSilence, .seconds(1))
        XCTAssertEqual(DictationKeyboardConstants.sessionIdleTimeout, 300)
        XCTAssertEqual(DictationKeyboardConstants.startURL.absoluteString, "midastest://dictation")
        XCTAssertTrue(DictationKeyboardConstants.isStartURL(URL(string: "midastest://dictation")!))
        XCTAssertFalse(DictationKeyboardConstants.isStartURL(URL(string: "midas://dictation")!))
        XCTAssertFalse(DictationKeyboardConstants.isStartURL(URL(string: "midastest://home")!))
        XCTAssertEqual(DictationKeyboardConstants.swipeBackLine, "Swipe back to keep typing.")
        XCTAssertEqual(DictationKeyboardConstants.startButtonTitle, "Start Dictation")
        XCTAssertEqual(VoiceTranscriberOptions.keyboardDictation.endOfSpeechSilence, .seconds(1))
    }

    // MARK: The session state machine

    func testStartTurnsTheMicrophoneOnAndWaitsForTheKeyboard() {
        var machine = Machine()
        XCTAssertEqual(machine.phase, .off)
        XCTAssertEqual(machine.start(at: startedAt), [.startMicrophone, .publishState])
        XCTAssertEqual(machine.phase, .live)
        XCTAssertEqual(machine.endsAt, seconds(300))
        let state = machine.state(heard: "", now: startedAt)
        XCTAssertTrue(state.live)
        XCTAssertFalse(state.listening)
    }

    func testStartTakesTheRequestTheKeyboardWroteBeforeOpeningMidas() {
        var machine = Machine()
        let effects = machine.start(at: startedAt, pendingRequest: request(true, seq: 10))
        XCTAssertEqual(effects, [.startMicrophone, .startListening, .publishState])
        XCTAssertEqual(machine.phase, .listening)
        XCTAssertEqual(machine.handledSeq, 10)
    }

    func testStartingAgainWhileLiveDoesNotRestartTheMicrophone() {
        var machine = Machine()
        _ = machine.start(at: startedAt)
        XCTAssertEqual(machine.start(at: seconds(5)), [.publishState])
        XCTAssertEqual(machine.endsAt, seconds(305))
    }

    func testAPauseInsertsAndListensAgain() {
        var machine = Machine()
        _ = machine.start(at: startedAt)
        XCTAssertEqual(machine.request(request(true, seq: 1), at: seconds(1)), [.startListening, .publishState])
        XCTAssertEqual(machine.phase, .listening)
        let effects = machine.listenEnded(raw: "um be there at 6", at: seconds(4))
        XCTAssertEqual(effects, [.deliver(raw: "um be there at 6"), .startListening, .publishState])
        XCTAssertEqual(machine.phase, .listening)
        XCTAssertEqual(machine.endsAt, seconds(304))
    }

    func testAListenThatHeardNothingInsertsNothing() {
        var machine = Machine()
        _ = machine.start(at: startedAt, pendingRequest: request(true, seq: 1))
        XCTAssertEqual(machine.listenEnded(raw: "  ", at: seconds(300)), [.startListening, .publishState])
    }

    func testStoppingFinishesTheListenAndItsWordsStillGoIn() {
        var machine = Machine()
        _ = machine.start(at: startedAt, pendingRequest: request(true, seq: 1))
        XCTAssertEqual(machine.request(request(false, seq: 2), at: seconds(2)), [.finishListening, .publishState])
        XCTAssertEqual(machine.phase, .finishing)
        XCTAssertFalse(machine.state(heard: "tell mom", now: seconds(2)).listening)
        XCTAssertEqual(machine.listenEnded(raw: "tell mom", at: seconds(3)), [.deliver(raw: "tell mom"), .publishState])
        XCTAssertEqual(machine.phase, .live)
    }

    func testListeningAskedAgainWhileFinishingStartsANewListenAfterTheWordsGoIn() {
        var machine = Machine()
        _ = machine.start(at: startedAt, pendingRequest: request(true, seq: 1))
        _ = machine.request(request(false, seq: 2), at: seconds(1))
        XCTAssertEqual(machine.request(request(true, seq: 3), at: seconds(1.2)), [.publishState])
        XCTAssertEqual(machine.listenEnded(raw: "ok", at: seconds(1.5)), [.deliver(raw: "ok"), .startListening, .publishState])
        XCTAssertEqual(machine.phase, .listening)
    }

    func testAnOlderRequestIsIgnored() {
        var machine = Machine()
        _ = machine.start(at: startedAt, pendingRequest: request(true, seq: 5))
        XCTAssertEqual(machine.request(request(false, seq: 4), at: seconds(1)), [])
        XCTAssertEqual(machine.request(request(true, seq: 5), at: seconds(1)), [])
        XCTAssertEqual(machine.phase, .listening)
    }

    func testARequestWithNoSessionTellsTheKeyboardThereIsNone() {
        var machine = Machine()
        XCTAssertEqual(machine.request(request(true, seq: 7), at: startedAt), [.publishState])
        XCTAssertEqual(machine.phase, .off)
        let state = machine.state(heard: "", now: startedAt)
        XCTAssertFalse(state.live)
        XCTAssertEqual(state.handledSeq, 7)
        XCTAssertNil(state.endsAt)
    }

    func testTheSessionEndsFiveMinutesAfterTheLastUse() {
        var machine = Machine()
        _ = machine.start(at: startedAt)
        _ = machine.request(request(true, seq: 1), at: seconds(60))
        machine.heard(at: seconds(90))
        _ = machine.listenEnded(raw: "hello", at: seconds(91))
        machine.inserted(at: seconds(100))
        XCTAssertEqual(machine.endsAt, seconds(400))
        XCTAssertEqual(machine.tick(at: seconds(399)), [])
        XCTAssertEqual(machine.tick(at: seconds(400)), [.cancelListening, .stopMicrophone, .publishState])
        XCTAssertEqual(machine.phase, .off)
        XCTAssertEqual(machine.tick(at: seconds(1000)), [])
    }

    func testAnIdleLiveSessionEndsWithoutCancellingAListen() {
        var machine = Machine()
        _ = machine.start(at: startedAt)
        XCTAssertEqual(machine.tick(at: seconds(300)), [.stopMicrophone, .publishState])
    }

    func testEndingStopsEverythingOnce() {
        var machine = Machine()
        _ = machine.start(at: startedAt, pendingRequest: request(true, seq: 1))
        XCTAssertEqual(machine.end(), [.cancelListening, .stopMicrophone, .publishState])
        XCTAssertEqual(machine.end(), [])
        XCTAssertEqual(machine.listenEnded(raw: "late words", at: seconds(1)), [], "a listen cancelled by the end inserts nothing")
        XCTAssertFalse(machine.wantsListening)
    }

    func testAFailedListenInsertsWhatWasHeardAndDoesNotLoop() {
        var machine = Machine()
        _ = machine.start(at: startedAt, pendingRequest: request(true, seq: 1))
        XCTAssertEqual(machine.listenFailed(raw: "half a sentence", at: seconds(2)), [.deliver(raw: "half a sentence"), .publishState])
        XCTAssertEqual(machine.phase, .live)
        XCTAssertFalse(machine.wantsListening)
        XCTAssertEqual(machine.request(request(true, seq: 2), at: seconds(3)), [.startListening, .publishState], "the orb's tap listens again")
    }

    func testTheStateShowsTheWordsOnlyWhileListening() {
        var machine = Machine()
        _ = machine.start(at: startedAt, pendingRequest: request(true, seq: 3))
        let listening = machine.state(heard: "be there", now: seconds(1))
        XCTAssertEqual(listening, DictationKeyboardState(live: true, listening: true, heard: "be there", handledSeq: 3, updatedAt: seconds(1),
                                                         endsAt: seconds(300)))
        _ = machine.request(request(false, seq: 4), at: seconds(2))
        XCTAssertEqual(machine.state(heard: "be there", now: seconds(2)).heard, "")
    }

    // MARK: The handoff

    func testARequestIsWrittenAsSortedJSONWithMillisecondDates() throws {
        let written = DictationKeyboardRequest(seq: 1_763_160_000_123, wantsListening: true, at: Date(timeIntervalSince1970: 1_763_160_000.123))
        let text = String(decoding: try DictationKeyboardHandoff.encode(written), as: UTF8.self)
        XCTAssertEqual(text, #"{"at":1763160000123,"seq":1763160000123,"wantsListening":true}"#)
        XCTAssertEqual(DictationKeyboardHandoff.decode(DictationKeyboardRequest.self, from: Data(text.utf8)), written)
    }

    func testEveryFileReadsBackAsWritten() throws {
        let state = DictationKeyboardState(live: true, listening: true, heard: "tell mom", handledSeq: 9, updatedAt: seconds(1), endsAt: seconds(301))
        let delivery = DictationKeyboardDelivery(id: "1763160000000-1", text: "Tell Mom I'm on my way.", endOfSpeechAt: seconds(2), deliveredAt: seconds(3))
        let ack = DictationKeyboardAck(id: "1763160000000-1", insertedAt: seconds(3.05))
        XCTAssertEqual(DictationKeyboardHandoff.decode(DictationKeyboardState.self, from: try DictationKeyboardHandoff.encode(state)), state)
        XCTAssertEqual(DictationKeyboardHandoff.decode(DictationKeyboardDelivery.self, from: try DictationKeyboardHandoff.encode(delivery)), delivery)
        XCTAssertEqual(DictationKeyboardHandoff.decode([DictationKeyboardAck].self, from: try DictationKeyboardHandoff.encode([ack])), [ack])
        XCTAssertNil(DictationKeyboardHandoff.decode(DictationKeyboardState.self, from: Data("{\"live\":true}".utf8)), "a broken file reads as nothing")
    }

    func testTheMailboxKeepsEachFileInTheFolder() throws {
        let mailbox = DictationKeyboardMailbox(folder: temporaryFolder)
        XCTAssertNil(mailbox.readRequest())
        XCTAssertNil(mailbox.readState())
        XCTAssertNil(mailbox.readDelivery())
        XCTAssertEqual(mailbox.readAcks(), [])
        let written = request(true, seq: 42)
        try mailbox.writeRequest(written)
        XCTAssertEqual(mailbox.readRequest(), written)
        try mailbox.writeState(.off)
        XCTAssertEqual(mailbox.readState(), .off)
        let delivery = DictationKeyboardDelivery(id: "a", text: "Hi.", endOfSpeechAt: seconds(1), deliveredAt: seconds(2))
        try mailbox.writeDelivery(delivery)
        XCTAssertEqual(mailbox.readDelivery(), delivery)
        try mailbox.appendAck(DictationKeyboardAck(id: "a", insertedAt: seconds(2)))
        try mailbox.appendAck(DictationKeyboardAck(id: "a", insertedAt: seconds(3)))
        try mailbox.appendAck(DictationKeyboardAck(id: "b", insertedAt: seconds(4)))
        XCTAssertEqual(mailbox.readAcks().map(\.id), ["a", "b"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryFolder.appending(path: "acks.json").path))
    }

    func testRequestsAlwaysGetNewer() {
        let first = DictationKeyboardRequest.next(wantsListening: true, at: startedAt, previousSeq: 0)
        XCTAssertEqual(first.seq, 1_763_160_000_000)
        let sameMillisecond = DictationKeyboardRequest.next(wantsListening: false, at: startedAt, previousSeq: first.seq)
        XCTAssertEqual(sameMillisecond.seq, first.seq + 1)
        let clockWentBack = DictationKeyboardRequest.next(wantsListening: true, at: seconds(-60), previousSeq: sameMillisecond.seq)
        XCTAssertEqual(clockWentBack.seq, sameMillisecond.seq + 1)
    }

    func testAcksKeepTheNewestTwenty() {
        var acks: [DictationKeyboardAck] = []
        for index in 1...25 {
            acks = DictationKeyboardHandoff.appending(DictationKeyboardAck(id: "id\(index)", insertedAt: seconds(Double(index))), to: acks)
        }
        XCTAssertEqual(acks.count, 20)
        XCTAssertEqual(acks.first?.id, "id6")
        XCTAssertEqual(acks.last?.id, "id25")
    }

    func testADeliveryGoesInOnceAndOnlyWhileFresh() {
        let delivery = DictationKeyboardDelivery(id: "d1", text: "Be there at 6.", endOfSpeechAt: seconds(0), deliveredAt: seconds(1))
        XCTAssertTrue(DictationKeyboardHandoff.shouldInsert(delivery, acks: [], now: seconds(1.1)))
        XCTAssertTrue(DictationKeyboardHandoff.shouldInsert(delivery, acks: [], now: seconds(11)))
        XCTAssertFalse(DictationKeyboardHandoff.shouldInsert(delivery, acks: [], now: seconds(11.5)), "the keyboard was closed when it came")
        let inserted = [DictationKeyboardAck(id: "d1", insertedAt: seconds(1.2))]
        XCTAssertFalse(DictationKeyboardHandoff.shouldInsert(delivery, acks: inserted, now: seconds(1.3)))
        let empty = DictationKeyboardDelivery(id: "d2", text: "", endOfSpeechAt: seconds(0), deliveredAt: seconds(1))
        XCTAssertFalse(DictationKeyboardHandoff.shouldInsert(empty, acks: [], now: seconds(1.1)))
    }

    // MARK: The space rule

    func testASpaceGoesBeforeDictatedTextOnlyWhenNeeded() {
        XCTAssertEqual(DictationKeyboardSpacing.textToInsert("Be there at 6.", before: nil), "Be there at 6.")
        XCTAssertEqual(DictationKeyboardSpacing.textToInsert("Be there at 6.", before: ""), "Be there at 6.")
        XCTAssertEqual(DictationKeyboardSpacing.textToInsert("Be there at 6.", before: "Ok."), " Be there at 6.")
        XCTAssertEqual(DictationKeyboardSpacing.textToInsert("Be there at 6.", before: "Ok. "), "Be there at 6.")
        XCTAssertEqual(DictationKeyboardSpacing.textToInsert("Be there at 6.", before: "Ok.\n"), "Be there at 6.")
        XCTAssertEqual(DictationKeyboardSpacing.textToInsert("Be there at 6.", before: "Ok.\t"), "Be there at 6.")
        XCTAssertEqual(DictationKeyboardSpacing.textToInsert("", before: "Ok."), "")
    }

    func testTheNextLetterIsCapitalAtASentenceStart() {
        XCTAssertTrue(DictationKeyboardSpacing.shouldCapitalize(before: nil))
        XCTAssertTrue(DictationKeyboardSpacing.shouldCapitalize(before: ""))
        XCTAssertTrue(DictationKeyboardSpacing.shouldCapitalize(before: "Done. "))
        XCTAssertTrue(DictationKeyboardSpacing.shouldCapitalize(before: "Really? "))
        XCTAssertTrue(DictationKeyboardSpacing.shouldCapitalize(before: "Hi\n"))
        XCTAssertFalse(DictationKeyboardSpacing.shouldCapitalize(before: "Done."))
        XCTAssertFalse(DictationKeyboardSpacing.shouldCapitalize(before: "see you "))
        XCTAssertFalse(DictationKeyboardSpacing.shouldCapitalize(before: "see"))
    }

    // MARK: The keyboard's pages

    func testTheKeyboardOpensListening() {
        var layout = DictationKeyboardLayout(hasFullAccess: true)
        XCTAssertEqual(layout.page, .listening)
        XCTAssertTrue(layout.rows.isEmpty)
        XCTAssertTrue(layout.showsListenKey)
        XCTAssertNil(layout.fullAccessLine)
        XCTAssertEqual(layout.appeared(), [.startListening])
    }

    func testABCStopsListeningAndShowsLetters() {
        var layout = DictationKeyboardLayout(hasFullAccess: true)
        XCTAssertEqual(layout.handle(.abc), [.stopListening])
        XCTAssertEqual(layout.page, .letters)
        XCTAssertEqual(layout.rows, DictationKeyboardLayout.letterRows)
        XCTAssertEqual(layout.rows.map(\.count), [10, 9, 7])
        XCTAssertEqual(layout.handle(.abc), [], "already typing: nothing to stop")
    }

    func testOneTwoThreeStopsListeningAndShowsNumbersThenSymbols() {
        var layout = DictationKeyboardLayout(hasFullAccess: true)
        XCTAssertEqual(layout.handle(.numbers), [.stopListening])
        XCTAssertEqual(layout.page, .numbers)
        XCTAssertEqual(layout.rows[0], ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
        XCTAssertTrue(layout.rows[2].contains("!"))
        XCTAssertEqual(layout.handle(.symbols), [])
        XCTAssertEqual(layout.page, .symbols)
        XCTAssertTrue(layout.rows[0].contains("#"))
        XCTAssertEqual(layout.handle(.numbers), [])
        XCTAssertEqual(layout.page, .numbers)
        XCTAssertEqual(layout.handle(.abc), [])
        XCTAssertEqual(layout.page, .letters)
    }

    func testTheListenKeyGoesBackToListening() {
        var layout = DictationKeyboardLayout(hasFullAccess: true)
        _ = layout.handle(.abc)
        XCTAssertEqual(layout.handle(.listen), [.startListening])
        XCTAssertEqual(layout.page, .listening)
        _ = layout.handle(.numbers)
        XCTAssertEqual(layout.handle(.listen), [.startListening])
        XCTAssertEqual(layout.page, .listening)
    }

    func testTheEmojiKeyStopsListeningAndSwitchesKeyboard() {
        var layout = DictationKeyboardLayout(hasFullAccess: true)
        XCTAssertEqual(layout.handle(.nextKeyboard), [.stopListening, .nextKeyboard])
        _ = layout.handle(.abc)
        XCTAssertEqual(layout.handle(.nextKeyboard), [.nextKeyboard])
    }

    func testClosingTheKeyboardStopsListeningAndOpeningListensAgain() {
        var layout = DictationKeyboardLayout(hasFullAccess: true)
        XCTAssertEqual(layout.disappeared(), [.stopListening])
        _ = layout.handle(.abc)
        XCTAssertEqual(layout.disappeared(), [])
        XCTAssertEqual(layout.appeared(), [.startListening])
        XCTAssertEqual(layout.page, .listening)
    }

    func testTypingKeys() {
        var layout = DictationKeyboardLayout(hasFullAccess: true)
        _ = layout.handle(.abc)
        XCTAssertEqual(layout.handle(.character("o")), [.insert("o")])
        XCTAssertEqual(layout.handle(.space), [.insert(" ")])
        XCTAssertEqual(layout.handle(.returnKey), [.insert("\n")])
        XCTAssertEqual(layout.handle(.backspace), [.deleteBackward])
    }

    func testShiftCapitalisesOneLetterAndLockKeepsIt() {
        var layout = DictationKeyboardLayout(hasFullAccess: true)
        _ = layout.handle(.abc)
        _ = layout.handle(.shift)
        XCTAssertEqual(layout.shift, .once)
        XCTAssertEqual(layout.handle(.character("o")), [.insert("O")])
        XCTAssertEqual(layout.handle(.character("k")), [.insert("k")])
        _ = layout.handle(.shiftLock)
        XCTAssertEqual(layout.handle(.character("o")), [.insert("O")])
        XCTAssertEqual(layout.handle(.character("k")), [.insert("K")])
        _ = layout.handle(.shift)
        XCTAssertEqual(layout.shift, .off)
    }

    func testShiftDoesNotTouchNumbersAndAutoCapitalisesOnLettersOnly() {
        var layout = DictationKeyboardLayout(hasFullAccess: true)
        _ = layout.handle(.abc)
        layout.autoCapitalize(before: "")
        XCTAssertEqual(layout.shift, .once)
        layout.autoCapitalize(before: "ok")
        XCTAssertEqual(layout.shift, .off)
        _ = layout.handle(.numbers)
        layout.autoCapitalize(before: "")
        XCTAssertEqual(layout.shift, .off)
        XCTAssertEqual(layout.handle(.character("!")), [.insert("!")])
    }

    // MARK: Without Full Access

    func testWithoutFullAccessTheKeyboardTypesLettersOnly() {
        var layout = DictationKeyboardLayout(hasFullAccess: false)
        XCTAssertEqual(layout.page, .letters)
        XCTAssertFalse(layout.showsListenKey)
        XCTAssertEqual(layout.fullAccessLine, "Allow Full Access to turn on dictation.")
        XCTAssertEqual(layout.appeared(), [])
        XCTAssertEqual(layout.page, .letters)
        XCTAssertEqual(layout.handle(.listen), [])
        XCTAssertEqual(layout.page, .letters)
        XCTAssertEqual(layout.handle(.numbers), [])
        XCTAssertEqual(layout.page, .numbers)
        XCTAssertEqual(layout.handle(.nextKeyboard), [.nextKeyboard])
        XCTAssertEqual(layout.disappeared(), [])
        XCTAssertEqual(layout.handle(.character("a")), [.insert("a")])
    }

    // MARK: The listening panel

    func testThePanelFollowsTheAppsAnswer() {
        let asked = request(true, seq: 100, at: 0)
        XCTAssertEqual(DictationKeyboardPanel.from(state: nil, request: asked, now: seconds(0.5)), .connecting)
        XCTAssertEqual(DictationKeyboardPanel.from(state: nil, request: asked, now: seconds(1.3)), .startButton, "no answer: no session")
        let stale = DictationKeyboardState(live: true, listening: true, heard: "old", handledSeq: 99, updatedAt: seconds(-30), endsAt: seconds(200))
        XCTAssertEqual(DictationKeyboardPanel.from(state: stale, request: asked, now: seconds(2)), .startButton, "a state from before the request")
        let off = DictationKeyboardState(live: false, listening: false, heard: "", handledSeq: 100, updatedAt: seconds(0.1), endsAt: nil)
        XCTAssertEqual(DictationKeyboardPanel.from(state: off, request: asked, now: seconds(0.2)), .startButton)
        let listening = DictationKeyboardState(live: true, listening: true, heard: "be there", handledSeq: 100, updatedAt: seconds(0.1), endsAt: seconds(300))
        XCTAssertEqual(DictationKeyboardPanel.from(state: listening, request: asked, now: seconds(0.2)), .listening(heard: "be there"))
        let idle = DictationKeyboardState(live: true, listening: false, heard: "", handledSeq: 101, updatedAt: seconds(0.1), endsAt: seconds(300))
        XCTAssertEqual(DictationKeyboardPanel.from(state: idle, request: asked, now: seconds(0.2)), .idle)
        XCTAssertEqual(DictationKeyboardPanel.from(state: nil, request: nil, now: seconds(0)), .startButton)
    }

    // MARK: The gate's text for one pause

    func testThePauseIsCleanedByTheGateWithNoModel() throws {
        let settings = DictationGateSettings.builtIn
        let outcome = try XCTUnwrap(DictationKeyboardInsertText.make(raw: "uh tell mom im on my way", settings: settings))
        let expected = DictationGate.decideForInsert("uh tell mom im on my way", settings: settings)
        XCTAssertEqual(outcome.gate.decision, expected)
        XCTAssertEqual(outcome.text, expected.text)
        XCTAssertEqual(outcome.gate.decision.path, .rule)
        XCTAssertFalse(outcome.text.lowercased().hasPrefix("uh"))
        XCTAssertEqual(outcome.text.first, "T")
        XCTAssertEqual(outcome.text.last, ".")
        XCTAssertNil(DictationKeyboardInsertText.make(raw: "   ", settings: settings))
    }

    func testAModelPathIsInsertedAsTheRulesLeftItFinished() throws {
        let settings = DictationGateSettings.builtIn
        let lightPhrase = DictationGateSettings.builtInPhrases.first(where: Self.isLightPhrase)
        let raw = try XCTUnwrap(lightPhrase?.text, "the built-in phrases have a light one")
        let decision = DictationGate.decideForInsert(raw, settings: settings)
        XCTAssertNotNil(decision.instruction, "the built-in settings send this to the model path")
        let outcome = try XCTUnwrap(DictationKeyboardInsertText.make(raw: raw, settings: settings))
        XCTAssertEqual(outcome.text, DictationGate.finished(decision.text, settings: settings))
        XCTAssertEqual(outcome.gate.decision.path, .light)
    }

    private static func isLightPhrase(_ phrase: DictationTestPhrase) -> Bool {
        phrase.expect == .light
    }

    // MARK: The record a keyboard insert saves

    private func gatedStore() throws -> LocalRecordStore {
        let store = LocalRecordStore(fileURL: temporaryFolder.appending(path: "store.json"))
        let manifestURL = keyboardRepoRoot.appending(path: "sidekicks/dictation/manifest.json")
        let manifest = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: manifestURL))
        let types = try XCTUnwrap(manifest["types"])
        func typesFor(_ sidekickId: String) -> JSONValue? {
            sidekickId == DictationRunRecord.sidekickId ? types : nil
        }
        store.writeGate = RecordTypeGate.make(engine: try RecordSchemaEngine(), typesProvider: typesFor)
        return store
    }

    private func keyboardRun() throws -> DictationRun {
        let raw = "uh tell mom im on my way"
        let outcome = try XCTUnwrap(DictationKeyboardInsertText.make(raw: raw, settings: .builtIn))
        return DictationTestRuns.keyboard(raw: raw, inserted: outcome.text, gate: outcome.gate, endOfSpeechAt: seconds(10), rawFinalAt: seconds(11.002),
                                          insertedAt: seconds(11.045), modelStatus: "Available", thermal: .fair)
    }

    func testAKeyboardRunCarriesItsTimingsAndPath() throws {
        let run = try keyboardRun()
        XCTAssertEqual(run.source, .keyboard)
        XCTAssertEqual(run.cleanupMs, 0)
        XCTAssertEqual(run.releaseToRawMs, 1002)
        XCTAssertEqual(run.totalMs, 1045)
        XCTAssertEqual(run.path, .rule)
        XCTAssertFalse(run.firstCall)
        XCTAssertNil(run.expect)
        let value = DictationRunRecord.value(run, device: device)
        XCTAssertEqual(value["source"], .string("keyboard"))
        XCTAssertEqual(value["cleaned"], .string(run.cleaned))
        XCTAssertEqual(value["raw"], .string("uh tell mom im on my way"))
        XCTAssertEqual(value["releaseToRawMs"], .number(1002))
        XCTAssertEqual(value["totalMs"], .number(1045))
        XCTAssertEqual(value["path"], .string("rule"))
        XCTAssertEqual(value["thermal"], .string("fair"))
        XCTAssertEqual(value["build"], .string("33"))
    }

    func testAKeyboardRunIsSavedThroughTheManifestLikeTheTestScreens() throws {
        let store = try gatedStore()
        let center = DictationTestCenter(store: store, device: device, now: { self.startedAt })
        center.save(try keyboardRun())
        XCTAssertNil(center.lastSaveError)
        let runs = store.query(sidekickId: "dictation", keyPrefix: "run:")
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.value["source"], .string("keyboard"))
        let summary = try XCTUnwrap(store.get(sidekickId: "dictation", key: "summary:main"))
        XCTAssertEqual(summary["runs"], .number(1))
        XCTAssertEqual(summary["paths"]?["rule"]?["averageTotalMs"], .number(1045))
    }

    func testAnUnknownSourceIsStillRefusedByTheManifest() throws {
        let store = try gatedStore()
        var value = DictationRunRecord.value(try keyboardRun(), device: device)
        if case .object(var fields) = value {
            fields["source"] = .string("typed")
            value = .object(fields)
        }
        XCTAssertThrowsError(try store.set(sidekickId: "dictation", key: "run:typed", value: value))
    }
}
#endif
