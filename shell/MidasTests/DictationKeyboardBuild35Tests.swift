#if MIDAS_TEST_BUILD
// Build 35: make the mic test unmistakable (TEST BUILD, founder 2026-11-19;
// docs/briefs/dictation-keyboard-test.md, "Build 35"; branch agent/dictation-test, never merged).
// Compiled only against a Test build: run with the "Midas Test" scheme's test action.
//
// The probe-loss cause: build 34's Midas Test removed a queued probe file even when the store
// refused the record. The write gate refuses a key whose type the phone's Sidekick list does not
// have yet ("no record type is declared for probe:..."), which is what a phone has right after the
// Sidekick gained `probe:` and before Midas Test fetched the new list (saveKeyboardRecords ran on
// open before the list came back). Reproduced on a simulator 2026-11-19 with the build 34 app.
// Also here: an attempt the keyboard never answered is answered by Midas Test; keyboard-only;
// the mic label; `mic` on keyboard runs and its summary; the keyboard log.
import AVFoundation
import Speech
import XCTest
@testable import Midas

/// A stand-in keyboard microphone whose start can fail at a step, every time.
@MainActor
private final class FailingMicEngine: DictationKeyboardMicEngine {
    var onStep: ((DictationKeyboardProbeStep) -> Void)?
    private(set) var lastStepFailure: (step: DictationKeyboardProbeStep, error: DictationKeyboardProbeError)?
    var lastRecogniserError: DictationKeyboardProbeError?
    var audioCount = DictationKeyboardAudioCount.none
    var isOnDeviceAvailable = true
    let failure = NSError(domain: "com.apple.coreaudio.avfaudio", code: 561_145_187, userInfo: [NSLocalizedDescriptionKey: "Session activation failed"])

    func startAudio(tap: @escaping VoiceAudioTap) throws {
        onStep?(.sessionCategory)
        onStep?(.activate)
        lastStepFailure = (.activate, DictationKeyboardProbeError(failure))
        throw failure
    }

    func stopAudio() {}

    func startRecognition(request: SFSpeechAudioBufferRecognitionRequest, resultHandler: @escaping VoiceRecognitionHandler) {}

    func cancelRecognition() {}
}

/// A Sidekick list whose Dictation types can be swapped, like the phone's before and after a fetch.
@MainActor
private final class SwappableTypes {
    var dictationTypes: JSONValue?

    func types(forSidekickId sidekickId: String) -> JSONValue? {
        sidekickId == DictationRunRecord.sidekickId ? dictationTypes : nil
    }
}

@MainActor
final class DictationKeyboardBuild35Tests: XCTestCase {
    private let startedAt = Date(timeIntervalSince1970: 1_763_600_000)
    private let context = DictationKeyboardProbeContext(fullAccess: true, microphone: "granted", speech: "authorized", build: "35", ios: "27.1")
    private var temporaryFolder: URL!

    override func setUp() {
        super.setUp()
        temporaryFolder = FileManager.default.temporaryDirectory.appending(path: "dictation-build35-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: temporaryFolder)
        super.tearDown()
    }

    private func seconds(_ offset: TimeInterval) -> Date {
        startedAt.addingTimeInterval(offset)
    }

    private func attempt(id: String = "1763600000000-0001", startedAt start: Date? = nil) -> DictationKeyboardProbeAttempt {
        DictationKeyboardProbeAttempt(id: id, startedAt: start ?? startedAt, context: context)
    }

    private func failedProbe(id: String = "1763600000000-0001") -> DictationKeyboardProbe {
        let error = DictationKeyboardProbeError(domain: "com.apple.coreaudio.avfaudio", code: 561_145_187, message: "Session activation failed")
        return attempt(id: id).failed(at: .activate, error: error, audio: .none, date: seconds(1))
    }

    // The Dictation types as the phone's list had them before build 34 (no probe:) and after
    private static let typesBeforeProbe: JSONValue = .object([
        "run:": .object(["$type": .string("dictation.run"), "schema": .object(["type": .string("object")])]),
    ])
    private static let typesWithProbe: JSONValue = .object([
        "run:": .object(["$type": .string("dictation.run"), "schema": .object(["type": .string("object")])]),
        "probe:": .object(["$type": .string("dictation.probe"), "schema": .object(["type": .string("object"), "required": .array([.string("at"), .string("result")])])]),
        "log:": .object(["$type": .string("dictation.log"), "schema": .object(["type": .string("object"), "required": .array([.string("entries")])])]),
    ])

    /// A store with the app's real write gate, reading the swappable list.
    private func gatedStore(_ list: SwappableTypes) throws -> LocalRecordStore {
        let store = LocalRecordStore(fileURL: temporaryFolder.appending(path: "records.json"))
        let engine = try RecordSchemaEngine()
        store.writeGate = RecordTypeGate.make(engine: engine, typesProvider: list.types(forSidekickId:))
        return store
    }

    private func mailbox() -> DictationKeyboardMailbox {
        DictationKeyboardMailbox(folder: temporaryFolder.appending(path: "group"))
    }

    private func queuedProbeCount(_ box: DictationKeyboardMailbox) -> Int {
        let folder = box.folder.appending(path: DictationKeyboardMailbox.probesFolder)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return files.count
    }

    private static func builtInSettings() -> DictationGateSettings {
        .builtIn
    }

    private static func ignoreRun(_ run: DictationRun) {}

    // MARK: The probe-loss cause

    func testAProbeTheStoreRefusesStaysQueuedAndIsSavedOnceTheListKnowsProbes() throws {
        let list = SwappableTypes()
        list.dictationTypes = Self.typesBeforeProbe
        let store = try gatedStore(list)
        let center = DictationTestCenter(store: store, device: DictationDeviceInfo(device: "iPhone17,1", ios: "27.1", build: "35"))
        let box = mailbox()
        let session = DictationKeyboardSession(settings: Self.builtInSettings, saveRun: Self.ignoreRun, mailbox: box, saveProbe: center.storeProbe)
        let probe = failedProbe()
        try box.queue(probe, id: probe.id, in: DictationKeyboardMailbox.probesFolder)

        // Midas Test opens before its Sidekick list is fetched: the old list refuses probe:
        session.saveKeyboardRecords(now: seconds(5))
        XCTAssertEqual(store.query(sidekickId: DictationRunRecord.sidekickId, keyPrefix: DictationProbeRecord.keyPrefix).count, 0)
        XCTAssertEqual(queuedProbeCount(box), 1, "a refused probe must stay queued (build 34 deleted it)")
        XCTAssertTrue(center.lastSaveError?.contains("no record type is declared for probe:") ?? false, center.lastSaveError ?? "no error")

        // The list arrives with probe:
        list.dictationTypes = Self.typesWithProbe
        session.saveKeyboardRecords(now: seconds(6))
        let saved = store.query(sidekickId: DictationRunRecord.sidekickId, keyPrefix: DictationProbeRecord.keyPrefix)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.value["$type"]?.stringValue, "dictation.probe")
        XCTAssertEqual(saved.first?.value["step"]?.stringValue, "activate")
        XCTAssertEqual(saved.first?.value["errorCode"]?.numberValue, 561_145_187)
        XCTAssertEqual(queuedProbeCount(box), 0)
        // Saved once
        session.saveKeyboardRecords(now: seconds(7))
        XCTAssertEqual(store.query(sidekickId: DictationRunRecord.sidekickId, keyPrefix: DictationProbeRecord.keyPrefix).count, 1)
    }

    func testStoreProbeThrowsTheRefusalAndSaveProbeStillOnlyNotesIt() throws {
        let list = SwappableTypes()
        list.dictationTypes = Self.typesBeforeProbe
        let store = try gatedStore(list)
        let center = DictationTestCenter(store: store)
        XCTAssertThrowsError(try center.storeProbe(failedProbe()))
        center.saveProbe(failedProbe(id: "1763600000000-0002"))
        XCTAssertNotNil(center.lastSaveError)
        list.dictationTypes = Self.typesWithProbe
        XCTAssertNoThrow(try center.storeProbe(failedProbe(id: "1763600000000-0003")))
        XCTAssertNil(center.lastSaveError)
    }

    // MARK: An attempt the keyboard never answered

    func testMidasTestAnswersAnAttemptOlderThanAnyListenAndLeavesAYoungOne() throws {
        var probes: [DictationKeyboardProbe] = []
        func keepProbe(_ probe: DictationKeyboardProbe) {
            probes.append(probe)
        }
        let box = mailbox()
        let session = DictationKeyboardSession(settings: Self.builtInSettings, saveRun: Self.ignoreRun, mailbox: box, saveProbe: keepProbe)
        var waiting = attempt()
        waiting.reached(.recogniser)
        box.writeProbeAttempt(waiting)

        // Five minutes on, a listen could still be running: left alone
        session.saveKeyboardRecords(now: seconds(5 * 60))
        XCTAssertTrue(probes.isEmpty)
        XCTAssertEqual(box.readProbeAttempt(), waiting)

        // Six minutes on it cannot be: a failed probe at its last step
        session.saveKeyboardRecords(now: seconds(6 * 60))
        XCTAssertEqual(probes.count, 1)
        XCTAssertEqual(probes.first?.result, .failed)
        XCTAssertEqual(probes.first?.step, .recogniser)
        XCTAssertEqual(probes.first?.error, .keyboardEnded)
        XCTAssertEqual(probes.first?.id, waiting.id)
        XCTAssertNil(box.readProbeAttempt())
        XCTAssertFalse(attempt().isAbandoned(now: seconds(359)))
        XCTAssertTrue(attempt().isAbandoned(now: seconds(360)))
    }

    // MARK: keyboard-only and the mic label

    func testKeyboardOnlyIsReadFromSettingsAndNeverFallsBack() {
        XCTAssertEqual(DictationKeyboardMicMode.keyboardOnly.rawValue, "keyboard-only")
        XCTAssertEqual(DictationKeyboardMicMode.from(settings: .object(["keyboardMic": .string("keyboard-only")])), .keyboardOnly)
        XCTAssertEqual(DictationKeyboardMicRoute.route(mode: .keyboardOnly, hasFullAccess: true, keyboardMicFailed: false), .keyboardMic)
        XCTAssertEqual(DictationKeyboardMicRoute.route(mode: .keyboardOnly, hasFullAccess: true, keyboardMicFailed: true), .keyboardMic)
        XCTAssertNil(DictationKeyboardMicRoute.route(mode: .keyboardOnly, hasFullAccess: false, keyboardMicFailed: true))
        // The fallback of keyboard is unchanged
        XCTAssertEqual(DictationKeyboardMicRoute.route(mode: .keyboard, hasFullAccess: true, keyboardMicFailed: true), .app)
    }

    func testTheGateSettingsAcceptKeyboardOnly() {
        guard case .object(var fields) = DictationGateSettings.builtIn.recordValue else {
            return XCTFail("built-in settings are not an object")
        }
        fields["keyboardMic"] = .string("keyboard-only")
        let resolved = DictationGateSettings.resolved(.object(fields))
        XCTAssertTrue(resolved.isSaved)
        XCTAssertEqual(resolved.settings.keyboardMic, .keyboardOnly)
        XCTAssertEqual(resolved.settings.recordValue["keyboardMic"]?.stringValue, "keyboard-only")
    }

    func testTheLabelAndTheLoggedReasonNameTheMicrophone() {
        XCTAssertEqual(DictationKeyboardMicRoute.keyboardMic.label, "KEYBOARD MIC")
        XCTAssertEqual(DictationKeyboardMicRoute.app.label, "APP MIC")
        XCTAssertEqual(DictationKeyboardMicRoute.keyboardMic.runMic, .keyboard)
        XCTAssertEqual(DictationKeyboardMicRoute.app.runMic, .app)
        XCTAssertEqual(DictationKeyboardMicRoute.reason(mode: .keyboardOnly, hasFullAccess: true, keyboardMicFailed: false), "keyboardMic keyboard-only")
        XCTAssertEqual(DictationKeyboardMicRoute.reason(mode: .keyboard, hasFullAccess: true, keyboardMicFailed: true),
                       "keyboardMic keyboard, keyboard mic failed: fallback")
        XCTAssertEqual(DictationKeyboardMicRoute.reason(mode: .app, hasFullAccess: true, keyboardMicFailed: false), "keyboardMic app")
        XCTAssertEqual(DictationKeyboardMicRoute.reason(mode: .keyboard, hasFullAccess: false, keyboardMicFailed: false), "no full access")
    }

    func testEveryFailedTryInOneAppearanceIsReportedAndStopsListening() async {
        let engine = FailingMicEngine()
        var probes: [DictationKeyboardProbe] = []
        var failures: [DictationKeyboardProbeStep] = []
        var stopped = 0
        func heard(_ text: String) {}
        func insert(_ text: String) -> Date {
            Date()
        }
        func answered(_ probe: DictationKeyboardProbe) {
            probes.append(probe)
        }
        func inserted(_ run: DictationKeyboardMicRun) {}
        func attemptChanged(_ attempt: DictationKeyboardProbeAttempt?) {}
        func stoppedListening() {
            stopped += 1
        }
        func listenFailed(_ step: DictationKeyboardProbeStep, _ error: DictationKeyboardProbeError) {
            failures.append(step)
        }
        let handlers = DictationKeyboardMicListener.Handlers(heard: heard, insert: insert, answered: answered, inserted: inserted,
                                                             attemptChanged: attemptChanged, stoppedListening: stoppedListening,
                                                             listenFailed: listenFailed)
        let listener = DictationKeyboardMicListener(engine: engine, settings: Self.builtInSettings, handlers: handlers)
        await listener.start(context: context)
        // The idle orb tapped: the same appearance tries again and fails again
        await listener.start(context: context)
        XCTAssertEqual(probes.count, 1, "one probe per appearance")
        XCTAssertEqual(failures, [.activate, .activate])
        XCTAssertEqual(stopped, 2, "the panel goes idle after each failed try")
        XCTAssertFalse(listener.wantsListening)
    }

    // MARK: mic on keyboard runs

    private func keyboardRun(raw: String, mic: DictationRunMic?, at offset: TimeInterval) throws -> DictationRun {
        let outcome = try XCTUnwrap(DictationKeyboardInsertText.make(raw: raw, settings: .builtIn))
        var run = DictationTestRuns.keyboard(raw: raw, inserted: outcome.text, gate: outcome.gate, endOfSpeechAt: seconds(offset),
                                             rawFinalAt: seconds(offset + 0.5), insertedAt: seconds(offset + 1), modelStatus: "Available", thermal: .nominal)
        run.mic = mic
        return run
    }

    func testAKeyboardRunRecordsItsMicAndTheSummaryCountsPerMic() throws {
        let store = LocalRecordStore(fileURL: temporaryFolder.appending(path: "runs.json"))
        let center = DictationTestCenter(store: store, device: DictationDeviceInfo(device: "iPhone17,1", ios: "27.1", build: "35"))
        center.save(try keyboardRun(raw: "send the deck", mic: nil, at: 0))
        let withoutMic = store.get(sidekickId: DictationRunRecord.sidekickId, key: DictationRunRecord.summaryKey)
        XCTAssertNil(withoutMic?["mics"], "no mics before any run logged one")

        center.save(try keyboardRun(raw: "uh tell mom", mic: .keyboard, at: 10))
        center.save(try keyboardRun(raw: "call David", mic: .keyboard, at: 20))
        center.save(try keyboardRun(raw: "lunch on tuesday", mic: .app, at: 30))
        let runs = store.query(sidekickId: DictationRunRecord.sidekickId, keyPrefix: DictationRunRecord.keyPrefix)
        var mics: [String] = []
        for run in runs {
            mics.append(run.value["mic"]?.stringValue ?? "none")
        }
        XCTAssertEqual(mics.sorted(), ["app", "keyboard", "keyboard", "none"])
        let summary = store.get(sidekickId: DictationRunRecord.sidekickId, key: DictationRunRecord.summaryKey)
        XCTAssertEqual(summary?["mics"]?["keyboard"]?["runs"]?.numberValue, 2)
        XCTAssertEqual(summary?["mics"]?["app"]?["runs"]?.numberValue, 1)
        XCTAssertEqual(summary?["runs"]?.numberValue, 4)
    }

    func testARunTheKeyboardsOwnMicQueuedIsSavedWithMicKeyboard() throws {
        var saved: [DictationRun] = []
        func keepRun(_ run: DictationRun) {
            saved.append(run)
        }
        let box = mailbox()
        let session = DictationKeyboardSession(settings: Self.builtInSettings, saveRun: keepRun, mailbox: box)
        let outcome = try XCTUnwrap(DictationKeyboardInsertText.make(raw: "uh tell mom im on my way", settings: .builtIn))
        let micRun = DictationKeyboardMicRun(id: "1763600004000-0002", raw: "uh tell mom im on my way", outcome: outcome, endOfSpeechAt: seconds(1),
                                             rawFinalAt: seconds(1.4), insertedAt: seconds(1.5), thermal: .fair)
        try box.queue(micRun, id: micRun.id, in: DictationKeyboardMailbox.keyboardRunsFolder)
        session.saveKeyboardRecords(now: seconds(2))
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.mic, .keyboard)
        XCTAssertEqual(saved.first?.source, .keyboard)
    }

    // MARK: The keyboard log

    private func entry(_ index: Int) -> DictationKeyboardLogEntry {
        DictationKeyboardLogEntry(at: seconds(TimeInterval(index)), event: "mic step", detail: "step \(index)")
    }

    func testTheRingLogKeepsTheLastFiftyAndCutsLongLines() {
        var entries: [DictationKeyboardLogEntry] = []
        for index in 0..<55 {
            entries = DictationKeyboardLog.appending(entry(index), to: entries)
        }
        XCTAssertEqual(entries.count, 50)
        XCTAssertEqual(entries.first?.detail, "step 5")
        XCTAssertEqual(entries.last?.detail, "step 54")
        let long = DictationKeyboardLogEntry(at: seconds(0), event: String(repeating: "e", count: 90), detail: String(repeating: "d", count: 900))
        let cut = DictationKeyboardLog.appending(long, to: [])
        XCTAssertEqual(cut.first?.event.count, 40)
        XCTAssertEqual(cut.first?.detail.count, 300)
    }

    func testTheLogRecordHasEachLineWithItsTimeEventAndDetail() {
        let value = DictationKeyboardLog.recordValue([entry(1), entry(2)], updatedAt: seconds(3))
        XCTAssertEqual(DictationKeyboardLog.recordKey, "log:keyboard")
        XCTAssertEqual(value["updatedAt"]?.stringValue, DictationProbeRecord.timestamp(seconds(3)))
        guard case .array(let lines) = value["entries"] else {
            return XCTFail("no entries")
        }
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0]["at"]?.stringValue, DictationProbeRecord.timestamp(seconds(1)))
        XCTAssertEqual(lines[0]["event"]?.stringValue, "mic step")
        XCTAssertEqual(lines[1]["detail"]?.stringValue, "step 2")
        XCTAssertTrue(DictationKeyboardLog.memoryDetail().hasPrefix("footprint "))
    }

    func testMidasTestSavesTheKeyboardLogOnceForEachNewLine() throws {
        var savedLogs: [[DictationKeyboardLogEntry]] = []
        func keepLog(_ entries: [DictationKeyboardLogEntry]) {
            savedLogs.append(entries)
        }
        let box = mailbox()
        let session = DictationKeyboardSession(settings: Self.builtInSettings, saveRun: Self.ignoreRun, mailbox: box, saveLog: keepLog)
        session.saveKeyboardRecords(now: seconds(1))
        XCTAssertTrue(savedLogs.isEmpty, "no log yet")
        try box.appendLog(entry(1))
        try box.appendLog(entry(2))
        XCTAssertEqual(box.readLog(), [entry(1), entry(2)])
        session.saveKeyboardRecords(now: seconds(3))
        session.saveKeyboardRecords(now: seconds(4))
        XCTAssertEqual(savedLogs.count, 1, "an unchanged log is not written again")
        try box.appendLog(entry(5))
        session.saveKeyboardRecords(now: seconds(6))
        XCTAssertEqual(savedLogs.count, 2)
        XCTAssertEqual(savedLogs.last?.last, entry(5))
    }

    func testTheCenterStoresTheLogAsOneRecord() throws {
        let store = LocalRecordStore(fileURL: temporaryFolder.appending(path: "log.json"))
        let center = DictationTestCenter(store: store)
        try center.storeKeyboardLog([entry(1)])
        try center.storeKeyboardLog([entry(1), entry(2)])
        let logs = store.query(sidekickId: DictationRunRecord.sidekickId, keyPrefix: "log:")
        XCTAssertEqual(logs.count, 1)
        guard case .array(let lines) = logs.first?.value["entries"] else {
            return XCTFail("no entries")
        }
        XCTAssertEqual(lines.count, 2)
    }
}
#endif
